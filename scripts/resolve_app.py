#!/usr/bin/env python3
"""Resolve the app actually running in the active terminal window.

The compositor reports a terminal's appId (e.g. "foot"), but for screen
time we want the process running inside it (e.g. "opencode", "btop").
Given the terminal's pid, this walks /proc to find the terminal's pty and
then reports the process group leader currently in the foreground of that
tty — the standard notion of "the app the terminal is running".

Results are canonicalized: a browser launched from a terminal (or one of
its subprocesses) reports the browser's screen-time app name, never the
binary or an internal worker (zen-bin / Web Content / forkserver / …), so
screen time aggregates per browser.

Usage: resolve_app.py <terminal-pid>
Prints a single process name (basename of argv[0], falling back to comm)
and nothing on failure.
"""

import glob
import json
import os
import subprocess
import sys


# comm names of internal browser worker processes. These must never show up
# as screen-time apps on their own.
BROWSER_SUBPROCESS_COMMS = {
    "Web Content",
    "forkserver",
    "socket",
    "rdd",
    "utility",
    "tab",
    "GPU Process",
    "Content Process",
    "Utility Process",
    "Isolated Web App",
    "WebExtensions",
    "spellcheck",
    "renderer",
    "Renderer",
    "zygote",
    "gpu-process",
    "GPU",
    "Crashpad Handler",
    "Chrome_ChildThread",
}

# Browser binary basenames -> canonical screen-time app name.
# Keep in sync with lib/Model.js BROWSER_ALIASES (same keys, same targets).
BROWSER_BINARY_TO_APP = {
    "zen-bin": "zen",
    "zen_browser": "zen",
    "zen": "zen",
    "firefox": "firefox",
    "librewolf": "librewolf",
    "waterfox": "waterfox",
    "tor-browser": "tor-browser",
    "mullvad-browser": "mullvad-browser",
    "google-chrome": "google-chrome",
    "chrome": "google-chrome",
    "chromium": "chromium",
    "brave": "brave",
    "brave-browser": "brave",
    "vivaldi": "vivaldi",
    "microsoft-edge": "microsoft-edge",
    "edge": "microsoft-edge",
}


def proc_stat(pid):
    """Parse /proc/[pid]/stat. Returns a dict or None on failure."""
    try:
        with open(f"/proc/{pid}/stat", "rb") as fh:
            data = fh.read().decode()
    except (OSError, ValueError):
        return None
    try:
        lparen = data.index("(")
        rparen = data.rindex(")")
    except ValueError:
        return None
    comm = data[lparen + 1 : rparen]
    fields = data[rparen + 1 :].split()
    if len(fields) < 8:
        return None
    return {
        "comm": comm,
        "ppid": int(fields[1]),
        "pgrp": int(fields[2]),
        "session": int(fields[3]),
        "ttynr": int(fields[4]),
        "tpgid": int(fields[5]),
    }


def proc_name(pid):
    """Display name of a process: basename of argv[0], falling back to comm."""
    stat = proc_stat(pid)
    if stat is None:
        return None
    name = stat["comm"]
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            args = fh.read().decode(errors="replace").split("\0")
        if args and args[0]:
            name = os.path.basename(args[0])
    except OSError:
        pass
    return name


def _readlink(path):
    """Read a symlink, returning None on any error."""
    try:
        return os.readlink(path)
    except (OSError, ValueError):
        return None


def _resolve_terminal_foreground(terminal_pid):
    """Walk /proc on demand to find the foreground process in a terminal.

    Instead of reading every process upfront, this reads each /proc entry
    only when needed during the tree walk.  Returns the foreground process
    group leader's name, or None.
    """
    # Collect the terminal's descendants by walking /proc and checking ppid.
    # We only read stat for processes whose ppid chain leads to terminal_pid.
    candidates = []  # (pid, stat) for descendants of terminal_pid
    ppid_map = {}    # pid -> ppid (for quick parent lookups)

    for entry in glob.glob("/proc/[0-9]*"):
        try:
            pid = int(entry.split("/")[-1])
        except (ValueError, IndexError):
            continue
        stat = proc_stat(pid)
        if stat is None:
            continue
        ppid_map[pid] = stat["ppid"]
        # Fast check: is this a direct child or grandchild of terminal_pid?
        # We do a shallow check here; the full ancestry walk happens below.
        if stat["ppid"] == terminal_pid or stat.get("pgrp") == terminal_pid:
            candidates.append((pid, stat))

    # Walk upward from each candidate to verify full ancestry.
    def is_descendant(pid, root):
        seen = set()
        while pid and pid != 1 and pid not in seen:
            if pid == root:
                return True
            seen.add(pid)
            pid = ppid_map.get(pid, 0)
        return False

    # Find the PTY owned by a descendant of the terminal.
    pty = None
    for pid, _stat in candidates:
        if not is_descendant(pid, terminal_pid):
            continue
        target = _readlink(f"/proc/{pid}/fd/0")
        if target and target.startswith("/dev/pts/"):
            pty = target
            break

    if pty is None:
        return None

    # Find the foreground process group leader on that PTY.
    tpgid = None
    for pid, stat in candidates:
        if not is_descendant(pid, terminal_pid):
            continue
        target = _readlink(f"/proc/{pid}/fd/0")
        if target == pty:
            tpgid = stat["tpgid"]
            break

    if not tpgid:
        return None

    name = proc_name(tpgid)
    if not name:
        return None

    # Walk up from a browser worker (Web Content, forkserver, …) to the
    # browser binary so time attributes to the browser, not an internal
    # process.
    pid = tpgid
    while name in BROWSER_SUBPROCESS_COMMS:
        ppid = ppid_map.get(pid, 0)
        if ppid <= 1:
            break
        pid = ppid
        name = proc_name(pid)
        if not name:
            break

    return BROWSER_BINARY_TO_APP.get(name, name) if name else None


def main():
    if len(sys.argv) == 2:
        try:
            terminal_pid = int(sys.argv[1])
        except ValueError:
            sys.exit(0)
    else:
        try:
            out = subprocess.run(
                ["hyprctl", "activewindow", "-j"],
                capture_output=True,
                text=True,
                timeout=2,
            ).stdout
            terminal_pid = int(json.loads(out).get("pid") or 0)
        except (ValueError, json.JSONDecodeError, subprocess.SubprocessError):
            terminal_pid = 0

    if not terminal_pid:
        sys.exit(0)

    name = _resolve_terminal_foreground(terminal_pid)
    if name:
        print(name)


if __name__ == "__main__":
    main()
