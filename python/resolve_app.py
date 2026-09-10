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
from collections import deque

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
# Single source of truth: js/browser_aliases.json (shared with Model.js).
_ALIASES_JSON = os.path.join(
    os.path.dirname(__file__), os.pardir, "js", "browser_aliases.json"
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
    try:
        return {
            "comm": comm,
            "ppid": int(fields[1]),
            "pgrp": int(fields[2]),
            "session": int(fields[3]),
            "ttynr": int(fields[4]),
            "tpgid": int(fields[5]),
        }
    except ValueError:
        return None


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
    # Login shells report "-bash": strip the marker so they resolve as
    # plain "bash" instead of tracking a separate "-bash" app.
    name = name.removeprefix("-")
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

# Cap ancestor hops so a pathological ppid cycle can't loop forever.
_MAX_ANCESTOR_HOPS = 10

# steamapps dirs holding appmanifest_<appid>.acf (overlapping on purpose).
_STEAM_ROOTS = [
    os.path.expanduser("~/.steam/steam/steamapps"),
    os.path.expanduser("~/.local/share/Steam/steamapps"),
    os.path.expanduser("~/.steam/root/steamapps"),
    os.path.expanduser("~/.var/app/com.valvesoftware.Steam/.steam/steam/steamapps"),
]

_STEAM_CLASS_RE = re.compile(r"^steam_app_(\d+)$", re.IGNORECASE)
_STEAM_CLASS_PREFIX_RE = re.compile(r"^steam_app_", re.IGNORECASE)


def _steam_class_appid(class_name):
    """AppID from a Steam window class ("steam_app_730" -> "730").

    Steam games report their AppID as the compositor window class. Returns
    None for anything else, including non-string input.
    """
    if not isinstance(class_name, str):
        return None
    m = _STEAM_CLASS_RE.match(class_name)
    return m.group(1) if m else None


def _is_steam_class(class_name):
    """True for any steam_app_* class, numeric AppID or not.

    Non-Steam shortcuts and third-party launch wrappers (e.g. Battle.net
    added as a non-Steam game) report a slug instead of a numeric AppID,
    "steam_app_battlenet" rather than "steam_app_1234567". There is no
    appmanifest for these, so they can't resolve via steam_title_for_class,
    but Service.qml still routes them here because it matches on the same
    prefix.
    """
    return isinstance(class_name, str) and bool(
        _STEAM_CLASS_PREFIX_RE.match(class_name)
    )


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
    frontier = deque((pid, 1) for pid in _children(terminal_pid))
    seen = set()
    while frontier:
        pid, depth = frontier.popleft()
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

    # Walk up from a browser worker to the browser binary it belongs to.
    pid = tpgid
    hops = 0
    while name in BROWSER_SUBPROCESS_COMMS and hops < _MAX_ANCESTOR_HOPS:
        parent_stat = proc_stat(pid)
        ppid = parent_stat["ppid"] if parent_stat else 0
        if ppid <= 1:
            break
        pid = ppid
        hops += 1
        name = proc_name(pid)
        if not name:
            break

    return BROWSER_BINARY_TO_APP.get(name, name) if name else None


def main():
    window_class = ""
    window_title = ""
    if len(sys.argv) == 2:
        try:
            terminal_pid = int(sys.argv[1])
        except ValueError:
            sys.exit(0)
    else:
        try:
            out = subprocess.run(
                ["hyprctl", "activewindow", "-j"],
                check=False,
                capture_output=True,
                text=True,
                timeout=2,
            ).stdout
            info = json.loads(out)
            if not isinstance(info, dict):
                raise TypeError("hyprctl activewindow is not a JSON object")
            terminal_pid = int(info.get("pid") or 0)
            window_class = str(info.get("class") or "")
            # Non-string titles would mint garbage keys; stay silent instead.
            raw_title = info.get("title")
            window_title = raw_title if isinstance(raw_title, str) else ""
        except (
            ValueError,
            json.JSONDecodeError,
            subprocess.SubprocessError,
            OSError,
            AttributeError,
            TypeError,
        ):
            terminal_pid = 0
            window_class = ""
            window_title = ""

    # Steam class carries the AppID: resolve via manifests, else keep the
    # stable steam_app_* key by exiting silently.
    if _steam_class_appid(window_class) is not None:
        title = steam_title_for_class(window_class)
        if title:
            print(title)
        sys.exit(0)

    # Non-Steam slugs (e.g. steam_app_battlenet) cover many games; tell them
    # apart by window title instead.
    if _steam_class_appid(window_class) is None and _is_steam_class(window_class):
        title = window_title.strip()
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
