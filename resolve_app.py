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


def proc_name(pid, infos):
    """Display name of a process: basename of argv[0], falling back to comm."""
    stat = infos.get(pid)
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


def proc_stat(pid):
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

    infos = {}
    for entry in glob.glob("/proc/[0-9]*"):
        pid = int(entry.split("/")[-1])
        stat = proc_stat(pid)
        if stat is not None:
            infos[pid] = stat

    def is_descendant(pid, root):
        seen = set()
        while pid and pid != 1 and pid not in seen:
            if pid == root:
                return True
            seen.add(pid)
            stat = infos.get(pid)
            pid = stat["ppid"] if stat else 0
        return pid == root

    pty = None
    for pid, stat in infos.items():
        if not is_descendant(pid, terminal_pid):
            continue
        try:
            target = os.readlink(f"/proc/{pid}/fd/0")
        except (OSError, ValueError):
            continue
        if target.startswith("/dev/pts/"):
            pty = target
            break

    if pty is None:
        sys.exit(0)

    tpgid = None
    for pid, stat in infos.items():
        try:
            if os.readlink(f"/proc/{pid}/fd/0") == pty:
                tpgid = stat["tpgid"]
                break
        except (OSError, ValueError):
            continue

    if not tpgid:
        sys.exit(0)

    stat = infos.get(tpgid)
    if stat is None:
        sys.exit(0)

    name = proc_name(tpgid, infos)
    if not name:
        sys.exit(0)

    # A browser's internal workers (Web Content, forkserver, rdd, …) normally
    # carry the browser binary in argv[0], so their name already collapses to
    # the binary — but a zombie or mid-exec process may expose only its comm.
    # Walk up to the nearest ancestor that is not itself a worker so time
    # attributes to the browser rather than to an internal process.
    pid = tpgid
    while name in BROWSER_SUBPROCESS_COMMS:
        stat = infos.get(pid)
        ppid = stat["ppid"] if stat else 0
        if ppid <= 1 or ppid not in infos:
            break
        pid = ppid
        name = proc_name(pid, infos)
        if not name:
            break

    # Fold binary names into the canonical app (zen-bin -> zen) so the
    # tracking service aggregates a browser under a single key.
    print(BROWSER_BINARY_TO_APP.get(name, name))


if __name__ == "__main__":
    main()
