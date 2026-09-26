#!/usr/bin/env python3
"""Unit tests for resolve_app.py. Runs with zero dependencies:

    python3 -m unittest discover -s tests

Process-touching tests use the current process (always alive, always in
/proc), so nothing here needs a running Hyprland session.
"""

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "python"),
)

import resolve_app as r


class CanonicalizationTests(unittest.TestCase):
    def test_browser_aliases_stay_in_sync_with_the_qml_mirror(self):
        # The JSON file is canonical; Model.js mirrors it as a QML-safe
        # literal and model.test.js fails loudly on drift. Here only the
        # loader's failure mode matters: a missing file resolves nothing.
        self.assertIsInstance(r.BROWSER_BINARY_TO_APP, dict)
        self.assertGreater(len(r.BROWSER_BINARY_TO_APP), 0)


class ProcParsingTests(unittest.TestCase):
    def test_proc_stat_parses_blobs_and_rejects_garbage(self):
        blob = b"1234 (myapp) S 100 200 300 400 -1 0 0 0 0\n"
        with mock.patch("builtins.open", mock.mock_open(read_data=blob)):
            stat = r.proc_stat(1234)
        self.assertEqual(stat["comm"], "myapp")
        self.assertEqual(stat["ppid"], 100)
        self.assertEqual(stat["tpgid"], -1)
        bad = b"1 (bash) S notanumber 2 3 4 5 6 7 8 9\n"
        with mock.patch("builtins.open", mock.mock_open(read_data=bad)):
            self.assertIsNone(r.proc_stat(1))

    def test_proc_name_prefers_argv_basename_falls_back_to_comm(self):
        stat_blob = b"1234 (oldcomm) S 1 2 3 4 5 0 0 0 0\n"

        def fake_open(path, *args, **kwargs):
            if "cmdline" in str(path):
                return mock.mock_open(read_data=b"/usr/bin/foo\0--bar\0")()
            return mock.mock_open(read_data=stat_blob)()

        with mock.patch("builtins.open", fake_open):
            self.assertEqual(r.proc_name(1234), "foo")

        def fake_empty_cmdline(path, *args, **kwargs):
            if "cmdline" in str(path):
                return mock.mock_open(read_data=b"")()
            return mock.mock_open(read_data=stat_blob)()

        with mock.patch("builtins.open", fake_empty_cmdline):
            self.assertEqual(r.proc_name(1234), "oldcomm")

    def test_proc_helpers_return_none_for_a_missing_pid(self):
        self.assertIsNone(r.proc_stat(2**31 - 1))
        self.assertIsNone(r.proc_name(2**31 - 1))


class FakeProc:
    """In-memory /proc stand-in for resolver tree tests.

    Models only what resolve_app reads: proc_stat fields and direct
    children. proc_name() falls back to comm because fake pids have no
    /proc/[pid]/cmdline on disk.
    """

    def __init__(self):
        self.stats = {}
        self.kids = {}

    def add(self, pid, comm, ppid, ttynr=0, tpgid=-1):
        self.stats[pid] = {
            "comm": comm,
            "ppid": ppid,
            "pgrp": pid,
            "session": pid if ttynr else 0,
            "ttynr": ttynr,
            "tpgid": tpgid,
        }
        self.kids.setdefault(ppid, []).append(pid)

    def install(self, testcase):
        testcase._orig_proc_stat = r.proc_stat
        testcase._orig_children = getattr(r, "_children", None)
        r.proc_stat = self.stats.get
        r._children = lambda pid: list(self.kids.get(pid, []))

    @staticmethod
    def restore(testcase):
        r.proc_stat = testcase._orig_proc_stat
        if testcase._orig_children is not None:
            r._children = testcase._orig_children


class TerminalResolutionTests(unittest.TestCase):
    """Simulated process trees for _resolve_terminal_foreground."""

    def setUp(self):
        self.world = FakeProc()
        self.world.install(self)

    def tearDown(self):
        FakeProc.restore(self)

    def test_foot_style_terminal_resolves_via_child_session(self):
        # foot does not hold the pty as its controlling terminal; the
        # spawned shell's session does. Regression test for "shows foot".
        w = self.world
        w.add(100, "foot", 1)  # ttynr=0, tpgid=-1
        w.add(110, "bash", 100, ttynr=34817, tpgid=120)
        w.add(120, "opencode", 110, ttynr=34817, tpgid=120)
        self.assertEqual(r._resolve_terminal_foreground(100), "opencode")

    def test_legacy_terminal_holding_tty_uses_own_tpgid(self):
        w = self.world
        w.add(200, "term", 1, ttynr=5, tpgid=210)
        w.add(210, "btop", 200)
        self.assertEqual(r._resolve_terminal_foreground(200), "btop")

    def test_login_shell_dash_is_stripped(self):
        # Login shells report comm "-bash"; it must resolve as plain bash
        # instead of tracking a separate "-bash" app.
        w = self.world
        w.add(300, "foot", 1)
        w.add(310, "-bash", 300, ttynr=34817, tpgid=310)
        self.assertEqual(r._resolve_terminal_foreground(300), "bash")

    def test_unknown_foreground_binary_passes_through(self):
        w = self.world
        w.add(900, "foot", 1)
        w.add(910, "bash", 900, ttynr=21, tpgid=920)
        w.add(920, "myapp", 910)
        self.assertEqual(r._resolve_terminal_foreground(900), "myapp")

    def test_no_tty_owning_descendant_returns_none(self):
        w = self.world
        w.add(300, "term", 1)
        w.add(310, "notify-send", 300)  # no controlling tty
        self.assertIsNone(r._resolve_terminal_foreground(300))

    def test_tty_session_found_below_direct_children(self):
        w = self.world
        w.add(400, "term", 1)
        w.add(410, "shim", 400)  # depth 2, no tty
        w.add(420, "bash", 410, ttynr=99, tpgid=430)
        w.add(430, "htop", 420)
        self.assertEqual(r._resolve_terminal_foreground(400), "htop")

    def test_tty_session_beyond_depth_limit_returns_none(self):
        w = self.world
        w.add(500, "term", 1)
        parent = 500
        for pid in range(510, 520):  # chain deeper than limit
            w.add(pid, "wrap", parent)
            parent = pid
        w.add(520, "bash", parent, ttynr=7, tpgid=530)
        w.add(530, "top", 520)
        self.assertIsNone(r._resolve_terminal_foreground(500))

    def test_browser_worker_as_foreground_walks_to_canonical_browser(self):
        w = self.world
        w.add(600, "foot", 1)
        w.add(610, "bash", 600, ttynr=11, tpgid=620)
        w.add(620, "Web Content", 630)  # browser worker is fg
        w.add(630, "zen-bin", 610)
        self.assertEqual(r._resolve_terminal_foreground(600), "zen")

    def test_ancestor_walk_bounded_for_pathological_worker_chain(self):
        # A worker chain deeper than the hop cap (e.g. reparented/recycled
        # browser workers) must terminate instead of walking forever, and
        # must not misattribute the time to a worker name.
        w = self.world
        w.add(800, "foot", 1)
        w.add(810, "bash", 800, ttynr=13, tpgid=820)
        parent = 820
        # Build a chain of N+2 browser-worker comms (all in
        # BROWSER_SUBPROCESS_COMMS) so the cap is reached before a browser
        # binary appears.
        for i in range(1, r._MAX_ANCESTOR_HOPS + 2):
            pid = 800 + i
            w.add(pid, "Web Content", parent)
            parent = pid
        name = r._resolve_terminal_foreground(800)
        # Terminates without hanging; whatever the resolved name, it must
        # not be a browser worker.
        self.assertNotIn(name, r.BROWSER_SUBPROCESS_COMMS)

    def test_negative_tpgid_on_tty_holder_falls_back_to_search(self):
        # A tty-owning session whose own tpgid is invalid must not be
        # selected; the search continues (or fails cleanly).
        w = self.world
        w.add(700, "term", 1)
        w.add(710, "weird", 700, ttynr=12, tpgid=-1)
        self.assertIsNone(r._resolve_terminal_foreground(700))


class SteamTitleTests(unittest.TestCase):
    """Steam window classes resolve to game titles from local appmanifests."""

    def _write_manifest(self, directory, appid, name):
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, f"appmanifest_{appid}.acf")
        with open(path, "w") as f:
            f.write(
                f'"AppState"\n{{\n\t"appid"\t\t"{appid}"\n\t"name"\t\t"{name}"\n}}\n'
            )
        return path

    def test_steam_class_parsing(self):
        self.assertEqual(r._steam_class_appid("steam_app_730"), "730")
        self.assertEqual(r._steam_class_appid("Steam_App_440900"), "440900")
        for bad in ("foot", "steam_app_", None):
            self.assertIsNone(r._steam_class_appid(bad))
        # Non-Steam shortcuts (e.g. Battle.net) report a slug, not an AppID.
        for slug in ("steam_app_battlenet", "Steam_App_Battlenet"):
            self.assertTrue(r._is_steam_class(slug))
        for bad in ("foot", None):
            self.assertFalse(r._is_steam_class(bad))

    def test_acf_name_parses_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_manifest(tmp, "730", "Counter-Strike 2")
            self.assertEqual(r._acf_name(path), "Counter-Strike 2")

    def test_acf_name_missing_file_is_none(self):
        self.assertIsNone(r._acf_name(os.path.join(tempfile.gettempdir(), "nope.acf")))

    def test_steam_title_searches_roots(self):
        with tempfile.TemporaryDirectory() as tmp:
            self._write_manifest(tmp, "570", "Dota 2")
            original = r._STEAM_ROOTS
            r._STEAM_ROOTS = [tmp]
            try:
                self.assertEqual(r.steam_title_for_class("steam_app_570"), "Dota 2")
                self.assertEqual(r.steam_title_for_class("steam_app_999"), None)
            finally:
                r._STEAM_ROOTS = original


class MainTests(unittest.TestCase):
    """main() never crashes and stays silent on bad hyprctl output."""

    def _run_main_no_args(self, run_result=None, run_error=None):
        if run_error is not None:
            run_mock = mock.Mock(side_effect=run_error)
        else:
            run_mock = mock.Mock(return_value=mock.Mock(stdout=run_result))
        buf = io.StringIO()
        with (
            mock.patch.object(r.subprocess, "run", run_mock),
            mock.patch.object(r.sys, "argv", ["resolve_app.py"]),
            redirect_stdout(buf),
            self.assertRaises(SystemExit) as cm,
        ):
            r.main()
        return cm.exception.code, buf.getvalue()

    def test_main_stays_silent_on_bad_hyprctl_output(self):
        cases = [
            ("missing hyprctl", None, FileNotFoundError("hyprctl")),
            ("list json", "[1, 2]", None),
            ("garbage json", "not json", None),
            (
                "non-string title",
                json.dumps(
                    {"pid": 0, "class": "steam_app_battlenet", "title": 123}
                ),
                None,
            ),
        ]
        for name, result, error in cases:
            with self.subTest(name):
                code, out = self._run_main_no_args(
                    run_result=result, run_error=error
                )
                self.assertEqual(code, 0)
                self.assertEqual(out, "")

    def test_main_slug_title_falls_back_to_window_title(self):
        """A slug class with no manifest prints the live title, stripped."""
        rows = [
            ("exact title", "World of Warcraft", "World of Warcraft\n"),
            ("padded title", "  World of Warcraft  ", "World of Warcraft\n"),
            # Blank title stays silent, so tracking keeps the stable slug key.
            ("blank title", "   ", ""),
        ]
        for name, title, expected in rows:
            with self.subTest(name):
                code, out = self._run_main_no_args(
                    run_result=json.dumps(
                        {
                            "pid": 0,
                            "class": "steam_app_battlenet",
                            "title": title,
                        }
                    )
                )
                self.assertEqual(code, 0)
                self.assertEqual(out, expected)


if __name__ == "__main__":
    unittest.main()
