"""BLUE fix (ops-defense2): watchdog registry read-modify-write was unlocked.

Confirmed defect being closed here:

  tools/ai-agent-watchdog already has a working `_state_lock()` fcntl.flock
  contextmanager, but it was ONLY applied inside cmd_ledger_record /
  cmd_ledger_done. `cmd_register` and `run_scan` (the daemon scan loop) still
  did an UNLOCKED load_registry -> mutate -> save_registry. A normal
  `register` racing a concurrent daemon scan iteration could silently drop
  the just-registered pane (or the scan's own in-flight mutations) -- a
  last-writer-wins clobber with no error, no warning, nothing.

Fix (tools/ai-agent-watchdog only; this file's edit boundary):
  Both `cmd_register` and `run_scan` now wrap their full load->mutate->save
  cycle in `with _state_lock():` (the SAME flock already used by the ledger
  commands). `run_scan` takes the lock PER ITERATION (not across the whole
  daemon lifetime), so it is never held during `time.sleep(interval)`.

Non-vacuousness: this test drives the REAL `cmd_register` and `run_scan`
(via the argparse-wired `func`/direct call, not a hand-rolled stand-in) with
a real fcntl.flock underneath -- no lock internals are mocked. It fails
against the pre-fix code (available via `git show
HEAD:tools/ai-agent-watchdog`, since this edit is uncommitted in this
worktree at authoring time): without the lock, `cmd_register`'s call returns
almost immediately (it never blocks on the scan's in-flight lock) and the
scan's slower save -- which lands AFTER the register's unlocked save --
silently clobbers the just-registered pane. See the session's final report
for the one-shot manual revert/rerun proof.
"""
from __future__ import annotations

import importlib.machinery
import importlib.util
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_TOOL = ROOT / "tools" / "ai-agent-watchdog"


def _load():
    loader = importlib.machinery.SourceFileLoader("ai_agent_watchdog_under_test_lock", str(_TOOL))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)  # safe: the tool guards execution behind `if __name__ == "__main__"`
    return mod


WD = _load()


def test_concurrent_scan_and_register_no_lost_update(tmp_path, monkeypatch):
    # Isolate state under this test's tmp dir (no real HOME/XDG state touched).
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))

    # Seed the registry with one pre-existing pane, as a daemon would have.
    WD.save_registry({"version": 1, "entries": {"pane-a": {"pane": "pane-a"}}})

    started = threading.Event()

    def fake_scan_entry(entry, dry_run):
        # Signal that we're inside run_scan's locked load->mutate->save section,
        # then hold it open for a while -- simulating a scan iteration that
        # takes real time (tmux capture-pane, etc). If the lock isn't actually
        # held here, a concurrent register races straight through instead of
        # blocking.
        started.set()
        time.sleep(0.4)
        entry["scanned"] = True
        return "scanned"

    monkeypatch.setattr(WD, "scan_entry", fake_scan_entry)

    scan_thread = threading.Thread(target=WD.run_scan, args=(1, 1.0, True))
    scan_thread.start()
    assert started.wait(2), "scan thread never entered its RMW section"
    # Give the scan thread a brief head start so it is provably inside the
    # locked section (holding the lock, mid-sleep) before we race register.
    time.sleep(0.05)

    resume_file = tmp_path / "resume.txt"
    resume_file.write_text("resume\n", encoding="utf-8")
    args = WD.parser().parse_args(["register", "pane-b", "--resume-file", str(resume_file)])

    t0 = time.time()
    rc = args.func(args)
    elapsed = time.time() - t0

    scan_thread.join(timeout=5)
    assert not scan_thread.is_alive(), "scan thread did not finish"
    assert rc == 0

    # If register's RMW is actually locked, it must have blocked on the
    # scan's in-flight lock (held for ~0.4s) rather than racing straight
    # through unlocked.
    assert elapsed >= 0.3, (
        f"cmd_register returned in {elapsed:.3f}s without blocking on the "
        "scan's in-flight lock -- the registry RMW is unlocked (the "
        "confirmed defect)"
    )

    data = WD.load_registry()
    assert data["entries"]["pane-a"].get("scanned") is True, (
        "the scan's write was lost -- register's save clobbered it "
        "(unlocked read-modify-write race)"
    )
    assert "pane-b" in data["entries"], (
        "the register's write was lost -- the scan's save clobbered it "
        "(the confirmed unlocked-registry lost-update race)"
    )


def test_register_and_second_register_do_not_lose_each_others_writes(tmp_path, monkeypatch):
    # A simpler double-check with two concurrent registrations of DIFFERENT
    # panes: both must survive. This alone would not have caught the
    # confirmed defect as reliably (register-vs-register races are much
    # narrower without an artificial delay), but it is a cheap sanity check
    # that locking cmd_register doesn't break the basic multi-register case.
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))
    resume_file = tmp_path / "resume.txt"
    resume_file.write_text("resume\n", encoding="utf-8")

    def register(pane):
        args = WD.parser().parse_args(["register", pane, "--resume-file", str(resume_file)])
        return args.func(args)

    threads = [threading.Thread(target=register, args=(p,)) for p in ("pane-x", "pane-y", "pane-z")]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=5)

    data = WD.load_registry()
    assert set(data["entries"]) == {"pane-x", "pane-y", "pane-z"}
