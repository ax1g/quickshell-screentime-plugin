#!/usr/bin/env python3
"""Resolve the app actually running in the active terminal window.

The compositor reports a terminal's appId (e.g. "foot"), but for screen
time we want the process running inside it (e.g. "opencode", "btop").
Given the terminal's pid, this walks /proc to find the terminal's pty and
then reports the process group leader currently in the foreground of that
tty — the standard notion of "the app the terminal is running".

Usage: resolve_app.py <terminal-pid>
Prints a single process name (basename of argv[0], falling back to comm)
and nothing on failure.
"""

import glob
import json
import os
import subprocess
import sys


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

    name = stat["comm"]
    try:
        with open(f"/proc/{tpgid}/cmdline", "rb") as fh:
            args = fh.read().decode(errors="replace").split("\0")
        if args and args[0]:
            name = os.path.basename(args[0])
    except OSError:
        pass

    print(name)


if __name__ == "__main__":
    main()
