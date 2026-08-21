#!/usr/bin/env python3
"""Unit tests for resolve_app.py. Runs with zero dependencies:

    python3 -m unittest discover -s tests

Process-touching tests use the current process (always alive, always in
/proc), so nothing here needs a running Hyprland session.
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts"))

import resolve_app as r  # noqa: E402


class CanonicalizationTests(unittest.TestCase):
    def test_browser_aliases_json_is_loaded(self):
        json_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "lib", "browser_aliases.json")
        with open(json_path) as f:
            expected = json.load(f)
        self.assertEqual(r.BROWSER_BINARY_TO_APP, expected)

    def test_browser_binaries_fold_to_canonical_names(self):
        for binary in ("zen-bin", "zen_browser", "brave-browser", "chrome"):
            self.assertIn(binary, r.BROWSER_BINARY_TO_APP)

    def test_browser_worker_comms_are_flagged(self):
        for comm in ("Web Content", "forkserver", "rdd", "zygote", "GPU Process"):
            self.assertIn(comm, r.BROWSER_SUBPROCESS_COMMS)

    def test_unknown_binary_passes_through(self):
        self.assertEqual(r.BROWSER_BINARY_TO_APP.get("foot", "foot"), "foot")


class ProcParsingTests(unittest.TestCase):
    def test_proc_stat_parses_current_process(self):
        stat = r.proc_stat(os.getpid())
        assert stat is not None
        self.assertIn("comm", stat)
        self.assertIn("ppid", stat)
        self.assertIn("tpgid", stat)
        self.assertGreater(stat["ppid"], 0)

    def test_proc_stat_tolerates_missing_pid(self):
        self.assertIsNone(r.proc_stat(2**31 - 1))

    def test_proc_name_resolves_current_process(self):
        name = r.proc_name(os.getpid())
        assert name
        self.assertNotIn("/", name)

    def test_proc_name_unknown_pid_returns_none(self):
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
        w.add(100, "foot", 1)                      # ttynr=0, tpgid=-1
        w.add(110, "bash", 100, ttynr=34817, tpgid=120)
        w.add(120, "opencode", 110, ttynr=34817, tpgid=120)
        self.assertEqual(r._resolve_terminal_foreground(100), "opencode")

    def test_legacy_terminal_holding_tty_uses_own_tpgid(self):
        w = self.world
        w.add(200, "term", 1, ttynr=5, tpgid=210)
        w.add(210, "btop", 200)
        self.assertEqual(r._resolve_terminal_foreground(200), "btop")

    def test_no_tty_owning_descendant_returns_none(self):
        w = self.world
        w.add(300, "term", 1)
        w.add(310, "notify-send", 300)             # no controlling tty
        self.assertIsNone(r._resolve_terminal_foreground(300))

    def test_tty_session_found_below_direct_children(self):
        w = self.world
        w.add(400, "term", 1)
        w.add(410, "shim", 400)                    # depth 2, no tty
        w.add(420, "bash", 410, ttynr=99, tpgid=430)
        w.add(430, "htop", 420)
        self.assertEqual(r._resolve_terminal_foreground(400), "htop")

    def test_tty_session_beyond_depth_limit_returns_none(self):
        w = self.world
        w.add(500, "term", 1)
        parent = 500
        for pid in range(510, 520):                # chain deeper than limit
            w.add(pid, "wrap", parent)
            parent = pid
        w.add(520, "bash", parent, ttynr=7, tpgid=530)
        w.add(530, "top", 520)
        self.assertIsNone(r._resolve_terminal_foreground(500))

    def test_browser_worker_as_foreground_walks_to_canonical_browser(self):
        w = self.world
        w.add(600, "foot", 1)
        w.add(610, "bash", 600, ttynr=11, tpgid=620)
        w.add(620, "Web Content", 630)             # browser worker is fg
        w.add(630, "zen-bin", 610)
        self.assertEqual(r._resolve_terminal_foreground(600), "zen")

    def test_negative_tpgid_on_tty_holder_falls_back_to_search(self):
        # A tty-owning session whose own tpgid is invalid must not be
        # selected; the search continues (or fails cleanly).
        w = self.world
        w.add(700, "term", 1)
        w.add(710, "weird", 700, ttynr=12, tpgid=-1)
        self.assertIsNone(r._resolve_terminal_foreground(700))


if __name__ == "__main__":
    unittest.main()
