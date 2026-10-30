"""Tests for runlimits.py: the threads rewrite and the machine-wide run slots."""

import json
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from runlimits import RunSlot, limit_threads, pid_alive  # noqa: E402

PSI_CPLEX = "preind 1\r\naggind 50\r\nlpmethod 4 \r\nthreads -1\r\npredual -1\r\n*  threads 2\r\nsolutiontype 2"


class LimitThreadsTests(unittest.TestCase):
    def test_rewrites_threads_line_keeps_comments_and_line_ends(self):
        text, changes = limit_threads(PSI_CPLEX, 12)
        self.assertIn("\r\nthreads 12\r\n", text)
        self.assertIn("*  threads 2", text)       # comment untouched
        self.assertTrue(text.endswith("solutiontype 2"))
        self.assertEqual(changes, ["threads -1 -> threads 12"])

    def test_equals_form_and_case(self):
        text, changes = limit_threads("Threads = 48\nsolver ipm\n", 12)
        self.assertEqual(text, "threads 12\nsolver ipm\n")
        self.assertEqual(len(changes), 1)

    def test_no_threads_line(self):
        text, changes = limit_threads("lpmethod 4\n", 12)
        self.assertEqual((text, changes), ("lpmethod 4\n", []))

    def test_already_at_limit(self):
        self.assertEqual(limit_threads("threads 12\n", 12), ("threads 12\n", []))


class RunSlotTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())

    def test_acquire_and_release(self):
        with RunSlot("a", 2, self.dir) as s:
            self.assertTrue(s.path.exists())
            info = json.loads(s.path.read_text())
            self.assertEqual(info["label"], "a")
        self.assertEqual(list(self.dir.glob("slot*.lock")), [])

    def test_blocks_when_full(self):
        with RunSlot("a", 2, self.dir), RunSlot("b", 2, self.dir):
            with self.assertRaises(TimeoutError):
                with RunSlot("c", 2, self.dir, poll_s=0.05, timeout_s=0.2):
                    pass

    def test_waits_for_a_free_slot(self):
        first = RunSlot("a", 1, self.dir).__enter__()
        threading.Timer(0.3, first.__exit__).start()
        t0 = time.monotonic()
        with RunSlot("b", 1, self.dir, poll_s=0.05, timeout_s=5) as s:
            self.assertGreaterEqual(time.monotonic() - t0, 0.25)
            self.assertGreater(s.waited_s, 0.2)

    def test_clears_slot_of_a_finished_process(self):
        p = subprocess.run([sys.executable, "-c", "import os; print(os.getpid())"], capture_output=True, text=True)
        dead = int(p.stdout.strip())
        self.assertFalse(pid_alive(dead))
        (self.dir / "slot0.lock").write_text(json.dumps({"pid": dead, "label": "old"}))
        with RunSlot("new", 1, self.dir, poll_s=0.05, timeout_s=2) as s:
            self.assertEqual(json.loads(s.path.read_text())["label"], "new")

    def test_disabled(self):
        with RunSlot("a", 0, self.dir) as s:
            self.assertIsNone(s.path)


if __name__ == "__main__":
    unittest.main()
