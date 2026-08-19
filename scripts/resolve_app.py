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
# Single source of truth: lib/browser_aliases.json (shared with Model.js).
_ALIASES_JSON = os.path.join(
    os.path.dirname(__file__), os.pardir, "lib", "browser_aliases.json"
)
try:
    with open(_ALIASES_JSON) as _f:
        BROWSER_BINARY_TO_APP = json.load(_f)
except (OSError, json.JSONDecodeError):
    BROWSER_BINARY_TO_APP = {}


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


def _resolve_terminal_foreground(terminal_pid):
    """Resolve the foreground process in a terminal window.

    Reads the terminal's own /proc/[pid]/stat to get the ``tpgid`` field,
    which is the PID of the foreground process group.  This is O(1) instead
    of walking all of /proc.  If the foreground process is a browser
    subprocess (Web Content, forkserver, …), walks its ancestor chain to
    find the browser binary.  Returns the canonical app name, or None.
    """
    stat = proc_stat(terminal_pid)
    if stat is None:
        return None

    tpgid = stat["tpgid"]
    if not tpgid or tpgid == terminal_pid:
        return None

    name = proc_name(tpgid)
    if not name:
        return None

    # Walk up from a browser worker (Web Content, forkserver, …) to the
    # browser binary so time attributes to the browser, not an internal
    # process.  Only reads /proc for ancestors, not all processes.
    pid = tpgid
    while name in BROWSER_SUBPROCESS_COMMS:
        parent_stat = proc_stat(pid)
        ppid = parent_stat["ppid"] if parent_stat else 0
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
