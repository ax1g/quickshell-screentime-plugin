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


if __name__ == "__main__":
    unittest.main()
