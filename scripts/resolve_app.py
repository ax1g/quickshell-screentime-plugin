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
import re
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


def _children(pid):
    """Direct child pids of a process, via /proc task children files."""
    try:
        tasks = os.listdir(f"/proc/{pid}/task")
    except OSError:
        return []
    out = []
    for tid in tasks:
        try:
            with open(f"/proc/{pid}/task/{tid}/children") as fh:
                out.extend(int(p) for p in fh.read().split())
        except (OSError, ValueError):
            continue
    return out


# Levels below the terminal to search for the pty-owning session.
# Terminals spawn their shell directly (depth 1); wrappers are rare.
_MAX_TTY_SEARCH_DEPTH = 4

# steamapps directories that hold appmanifest_<appid>.acf files. The first
# two are the same library via symlink on most installs; both are listed
# because neither is guaranteed to exist.
_STEAM_ROOTS = [
    os.path.expanduser("~/.steam/steam/steamapps"),
    os.path.expanduser("~/.local/share/Steam/steamapps"),
    os.path.expanduser("~/.steam/root/steamapps"),
    os.path.expanduser(
        "~/.var/app/com.valvesoftware.Steam/.steam/steam/steamapps"
    ),
]

_STEAM_CLASS_RE = re.compile(r"^steam_app_(\d+)$", re.IGNORECASE)


def _steam_class_appid(class_name):
    """AppID from a Steam window class ("steam_app_730" -> "730").

    Steam games report their AppID as the compositor window class. Returns
    None for anything else, including non-string input.
    """
    if not isinstance(class_name, str):
        return None
    m = _STEAM_CLASS_RE.match(class_name)
    return m.group(1) if m else None


def _acf_name(path):
    """Game title from an appmanifest .acf file, or None.

    ACF is Valve's KeyValues format; manifests carry the title as a flat
    "name" entry ("name"\t\t"Stardew Valley"), so a targeted regex beats
    shipping a full parser.
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            data = fh.read()
    except OSError:
        return None
    m = re.search(r'"name"\s*"([^"]*)"', data)
    return m.group(1) if m else None


def steam_title_for_class(class_name):
    """Resolve a steam_app_* window class to its game title, or None."""
    appid = _steam_class_appid(class_name)
    if appid is None:
        return None
    for root_dir in _STEAM_ROOTS:
        title = _acf_name(os.path.join(root_dir, f"appmanifest_{appid}.acf"))
        if title:
            return title
    return None


def _find_tty_session(terminal_pid):
    """Bounded DFS below the terminal for a descendant owning a pty.

    Terminals like foot spawn their shell with forkpty, so the pty is
    the child's controlling terminal, not the terminal's own.  Returns
    that descendant's proc_stat (its ``tpgid`` is the foreground group),
    or None when no descendant owns a tty.
    """
    frontier = [(pid, 1) for pid in _children(terminal_pid)]
    seen = set()
    while frontier:
        pid, depth = frontier.pop(0)
        if pid in seen or depth > _MAX_TTY_SEARCH_DEPTH:
            continue
        seen.add(pid)
        stat = proc_stat(pid)
        if stat is None:
            continue
        if stat["ttynr"] and stat["tpgid"] > 0:
            return stat
        for child in _children(pid):
            frontier.append((child, depth + 1))
    return None


def _resolve_terminal_foreground(terminal_pid):
    """Resolve the foreground process in a terminal window.

    Reads the terminal's own /proc/[pid]/stat ``tpgid`` field when the
    terminal holds the pty as its controlling terminal.  Otherwise (e.g.
    foot reports ttynr=0 / tpgid=-1) searches its descendants for the
    pty-owning session and uses that session's ``tpgid``.  If the
    foreground process is a browser subprocess (Web Content, forkserver,
    …), walks its ancestor chain to find the browser binary.  Returns
    the canonical app name, or None.
    """
    stat = proc_stat(terminal_pid)
    if stat is None:
        return None

    tpgid = stat["tpgid"]
    if tpgid <= 0 or tpgid == terminal_pid:
        tty_stat = _find_tty_session(terminal_pid)
        tpgid = tty_stat["tpgid"] if tty_stat else 0
    if tpgid <= 0:
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
    window_class = ""
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
            info = json.loads(out)
            terminal_pid = int(info.get("pid") or 0)
            window_class = info.get("class") or ""
        except (ValueError, json.JSONDecodeError, subprocess.SubprocessError):
            terminal_pid = 0

    # Steam games: the class carries the AppID, so /proc walking is both
    # unnecessary and wrong (it would report the game binary). Resolve the
    # title from local manifests; if the manifest is missing, exit without
    # output so tracking keeps the stable steam_app_* key instead of
    # flip-flopping to a binary name.
    if _steam_class_appid(window_class) is not None:
        title = steam_title_for_class(window_class)
        if title:
            print(title)
        sys.exit(0)

    if not terminal_pid:
        sys.exit(0)

    name = _resolve_terminal_foreground(terminal_pid)
    if name:
        print(name)


if __name__ == "__main__":
    main()
