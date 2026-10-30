"""Limits for local TIMES runs (James, 29 Oct 2026).

On James's workstation every TIMES run uses at most ``DEFAULT_THREADS`` solver
threads, and at most ``DEFAULT_MAX_PARALLEL`` CPU-heavy runs run at the same
time. This keeps the machine usable and gives every test the same resources,
so that timings are comparable.

* ``limit_threads`` rewrites the ``threads`` line of a solver option file
  (CPLEX ``cplex.opt``, GAMS/HiGHS ``highs.opt``, ...). Option files without a
  ``threads`` line are left alone; the GAMS ``threads=`` command-line option
  covers them.
* ``RunSlot`` is a machine-wide counting semaphore made of lock files in one
  directory: a run takes a free ``slot<k>.lock`` (created exclusively) and
  removes it when it ends; a lock whose process no longer exists is cleared.
  It only counts runs that use it (``make_reference.py`` and scripts built on
  this module).

Standard library only.
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

DEFAULT_THREADS = 12
DEFAULT_MAX_PARALLEL = 4

_THREADS_LINE = re.compile(r"^(?P<indent>\s*)threads(?:\s*=\s*|\s+)(?P<value>\S+)\s*$", re.IGNORECASE)


def default_threads() -> int:
    return int(os.environ.get("TIMESJL_THREADS", DEFAULT_THREADS))


def default_max_parallel() -> int:
    return int(os.environ.get("TIMESJL_MAX_PARALLEL", DEFAULT_MAX_PARALLEL))


def default_slot_dir() -> Path:
    return Path(os.environ.get("TIMESJL_SLOT_DIR", Path(tempfile.gettempdir()) / "timesjl-run-slots"))


def limit_threads(text: str, threads: int) -> tuple[str, list[str]]:
    """Set every non-comment ``threads`` option line to ``threads``.

    Returns the new text and the lines changed (``"old -> new"``). Comment lines
    (starting with ``*``) are kept as they are.
    """
    out, changes = [], []
    for ln in text.splitlines(keepends=True):
        body = ln.rstrip("\r\n")
        eol = ln[len(body):]
        m = _THREADS_LINE.match(body)
        if m and not body.lstrip().startswith("*"):
            new = f"{m.group('indent')}threads {threads}"
            if body != new:
                changes.append(f"{body.strip()} -> {new.strip()}")
            out.append(new + eol)
        else:
            out.append(ln)
    return "".join(out), changes


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if sys.platform == "win32":
        import ctypes

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return ctypes.get_last_error() == 5  # access denied: the process exists
        try:
            code = ctypes.c_ulong()
            kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
            return code.value == 259  # STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


class RunSlot:
    """Hold one of ``max_parallel`` machine-wide run slots while a run lasts.

    ``max_parallel <= 0`` disables the limit. ``waited_s`` is the time spent
    waiting for a slot (not part of the run's own wall time).
    """

    def __init__(self, label: str, max_parallel: int | None = None, slot_dir: Path | None = None,
                 poll_s: float = 30.0, timeout_s: float | None = None):
        self.label = label
        self.max_parallel = default_max_parallel() if max_parallel is None else max_parallel
        self.slot_dir = Path(slot_dir) if slot_dir else default_slot_dir()
        self.poll_s = poll_s
        self.timeout_s = timeout_s
        self.path: Path | None = None
        self.waited_s = 0.0

    def _clear_if_stale(self, path: Path) -> None:
        try:
            info = json.loads(path.read_text())
            pid = int(info.get("pid", 0))
        except (OSError, ValueError):
            return  # being written or unreadable: leave it
        if not pid_alive(pid):
            try:
                path.unlink()
            except OSError:
                pass

    def __enter__(self) -> "RunSlot":
        if self.max_parallel <= 0:
            return self
        self.slot_dir.mkdir(parents=True, exist_ok=True)
        t0 = time.monotonic()
        announced = False
        while True:
            for k in range(self.max_parallel):
                path = self.slot_dir / f"slot{k}.lock"
                try:
                    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                except FileExistsError:
                    self._clear_if_stale(path)
                    continue
                with os.fdopen(fd, "w") as f:
                    json.dump({"pid": os.getpid(), "label": self.label,
                               "since": time.strftime("%Y-%m-%dT%H:%M:%S")}, f)
                self.path = path
                self.waited_s = time.monotonic() - t0
                return self
            if self.timeout_s is not None and time.monotonic() - t0 > self.timeout_s:
                raise TimeoutError(f"no free run slot in {self.slot_dir} after {self.timeout_s} s")
            if not announced:
                print(f"  waiting for a run slot ({self.max_parallel} in use, {self.slot_dir})", flush=True)
                announced = True
            time.sleep(self.poll_s)

    def __exit__(self, *exc) -> None:
        if self.path is not None:
            try:
                self.path.unlink()
            except OSError:
                pass
            self.path = None
