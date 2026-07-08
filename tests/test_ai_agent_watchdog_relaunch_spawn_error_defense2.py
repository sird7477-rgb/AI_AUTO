"""BLUE fix (ops-defense2 R... ): bound relaunch retries when the SPAWN ITSELF fails.

Confirmed MEDIUM-HIGH/LIVE defect being closed here:

`maybe_relaunch` calls `subprocess.run(argv, check=False, ...)`. That call can still
RAISE -- `FileNotFoundError` for a bad/stale relaunch argv (confirmed empirically),
or `subprocess.TimeoutExpired` if the relaunched process hangs past the configured
timeout -- and it raised BEFORE `entry["relaunch_count"]` was incremented (the
increment was the very next line, only reached on a normal return). Round 5's
per-pane try/except in `run_scan` (see test_ai_agent_watchdog_dos_isolation_defense2.py)
catches that exception and keeps the daemon alive -- but because relaunch_count was
never bumped for the FAILED attempt, `max_relaunch` never trips: a persistently-bad
relaunch command is retried on EVERY scan interval forever, growing events.log without
bound. No race needed -- this reproduces single-threaded, iteration after iteration.

Fix (tools/ai-agent-watchdog, `maybe_relaunch` only):
  - `entry["relaunch_count"]` is now incremented for the ATTEMPT, before the
    `subprocess.run` call, so the count is durable even if the spawn raises.
  - The `subprocess.run` call is wrapped in
    `try/except (FileNotFoundError, subprocess.TimeoutExpired, OSError)`; on a spawn
    failure a distinct event `"relaunch_spawn_error"` (carrying the exception class
    name) is logged and `"relaunch_spawn_error"` is returned -- the existing
    `"relaunch_stopped"` / `max_relaunch` cap logic (unchanged threshold) then trips
    on the next attempt exactly as it already does for a healthy relaunch that merely
    keeps failing to fix the pane.
  - The success path (`event("relaunch", ...)`, return `"relaunch"`) is unchanged in
    shape; it still increments the same counter, just earlier.
  - KeyboardInterrupt/SystemExit are not in the except clause and still propagate.

Non-vacuousness: the tests reconstruct the PRE-FIX `maybe_relaunch` body in-test (not
read from git) and prove that under the identical monkeypatched failing
`subprocess.run`, the pre-fix shape lets `relaunch_count` stay stuck at 0 forever
(unbounded retries), while the fixed code on disk bounds retries at `max_relaunch`.
"""
from __future__ import annotations

import importlib.machinery
import importlib.util
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
_TOOL = ROOT / "tools" / "ai-agent-watchdog"


def _load():
    loader = importlib.machinery.SourceFileLoader("ai_agent_watchdog_under_test_relaunch", str(_TOOL))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)  # safe: the tool guards execution behind `if __name__ == "__main__"`
    return mod


WD = _load()
CUR = 1_800_000_000.0


def _entry(max_relaunch: int = 3) -> dict:
    return {
        "pane": "pane-relaunch",
        "relaunch_argv": ["bogus-relaunch-cmd-xyz"],
        "max_relaunch": max_relaunch,
        "relaunch_timeout_seconds": 5,
        "relaunch_count": 0,
    }


# --- Fixed behavior: spawn failure still counts toward, and is bounded by, max_relaunch ---

def test_maybe_relaunch_file_not_found_increments_count_and_bounds_retries(tmp_path, monkeypatch):
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))
    calls: list[list[str]] = []

    def fake_run(argv, **kwargs):
        calls.append(argv)
        raise FileNotFoundError(2, "No such file or directory", argv[0])

    monkeypatch.setattr(WD.subprocess, "run", fake_run)

    entry = _entry(max_relaunch=3)

    # Drive it like repeated scan iterations would: call maybe_relaunch over and over
    # on the SAME entry (production mutates the registry entry in place and persists
    # it via save_registry at the end of each run_scan iteration).
    results = [WD.maybe_relaunch(entry, dry_run=False, current=CUR) for _ in range(6)]

    assert results == [
        "relaunch_spawn_error",
        "relaunch_spawn_error",
        "relaunch_spawn_error",
        "relaunch_stopped",
        "relaunch_stopped",
        "relaunch_stopped",
    ], f"retries must stop being ATTEMPTED once max_relaunch is reached; got {results!r}"

    assert entry["relaunch_count"] == 3, "count must be bounded at max_relaunch, not stuck at 0"
    assert len(calls) == 3, (
        "subprocess.run must not be invoked again once max_relaunch attempts have failed -- "
        f"got {len(calls)} calls, expected exactly 3 (bounded, not unbounded)"
    )


def test_maybe_relaunch_timeout_expired_increments_count_and_bounds_retries(tmp_path, monkeypatch):
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))
    calls: list[list[str]] = []

    def fake_run(argv, **kwargs):
        calls.append(argv)
        raise subprocess.TimeoutExpired(cmd=argv, timeout=kwargs.get("timeout", 5))

    monkeypatch.setattr(WD.subprocess, "run", fake_run)

    entry = _entry(max_relaunch=2)

    results = [WD.maybe_relaunch(entry, dry_run=False, current=CUR) for _ in range(4)]

    assert results == ["relaunch_spawn_error", "relaunch_spawn_error", "relaunch_stopped", "relaunch_stopped"]
    assert entry["relaunch_count"] == 2
    assert len(calls) == 2, "TimeoutExpired must bound retries the same way FileNotFoundError does"


def test_maybe_relaunch_spawn_error_never_raises_out(tmp_path, monkeypatch):
    # Belt-and-suspenders: maybe_relaunch itself must not let the spawn exception escape
    # (this is what would, pre-fix, have relied entirely on run_scan's separate isolation
    # try/except to avoid killing the daemon -- here we confirm maybe_relaunch is
    # well-behaved on its own terms too).
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))

    def fake_run(argv, **kwargs):
        raise FileNotFoundError(2, "No such file or directory", argv[0])

    monkeypatch.setattr(WD.subprocess, "run", fake_run)
    entry = _entry(max_relaunch=1)
    result = WD.maybe_relaunch(entry, dry_run=False, current=CUR)  # must not raise
    assert result == "relaunch_spawn_error"
    assert entry["relaunch_count"] == 1


def test_run_scan_end_to_end_bounds_relaunch_across_iterations_and_stops_growing_the_log(tmp_path, monkeypatch):
    # Drive N full scan iterations (the actual daemon loop), not just direct maybe_relaunch
    # calls, to prove the fix holds at the level real production hits it: registry
    # persistence across iterations, plus events.log growth.
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))
    missing_pane_text = tmp_path / "no-such-pane-text.txt"  # read_pane -> (None, err) -> maybe_relaunch
    WD.save_registry({
        "version": 1,
        "entries": {
            "pane-x": {
                "pane": "pane-x",
                "pane_text_file": str(missing_pane_text),
                "relaunch_argv": ["bogus-relaunch-cmd-xyz"],
                "max_relaunch": 3,
                "relaunch_timeout_seconds": 5,
                "relaunch_count": 0,
            }
        },
    })

    calls: list[list[str]] = []

    def fake_run(argv, **kwargs):
        calls.append(argv)
        raise FileNotFoundError(2, "No such file or directory", argv[0])

    monkeypatch.setattr(WD.subprocess, "run", fake_run)

    rc = WD.run_scan(iterations=6, interval=0.0, dry_run=False)  # must return normally
    assert rc == 0

    data = WD.load_registry()
    assert data["entries"]["pane-x"]["relaunch_count"] == 3, (
        "after 6 scan iterations of a permanently-broken relaunch argv, the count must be "
        "bounded at max_relaunch (3), not still climbing / not stuck at 0"
    )
    assert len(calls) == 3, (
        f"subprocess.run must be attempted exactly max_relaunch (3) times across 6 iterations, "
        f"not once per iteration forever -- got {len(calls)} calls"
    )

    log_lines = WD.log_path().read_text(encoding="utf-8").strip().splitlines()
    spawn_error_events = [l for l in log_lines if '"kind": "relaunch_spawn_error"' in l]
    stopped_events = [l for l in log_lines if '"kind": "relaunch_stopped"' in l]
    assert len(spawn_error_events) == 3, "exactly one relaunch_spawn_error per failed attempt, then no more"
    assert len(stopped_events) == 3, "remaining iterations after the cap must log relaunch_stopped, not retry"


# --- Non-vacuous: prove the PRE-FIX shape does NOT bound retries on the same input --------

def test_old_unguarded_maybe_relaunch_leaves_count_at_zero_forever(monkeypatch):
    # Literal, minimal reconstruction of the vulnerable pre-fix maybe_relaunch body (not
    # read from git): relaunch_count is only incremented on the line AFTER subprocess.run,
    # so a spawn that raises never reaches it. Combined with run_scan's per-pane isolation
    # (which catches the exception and continues -- proven in
    # test_ai_agent_watchdog_dos_isolation_defense2.py), this is exactly the shape that
    # let a persistently-bad relaunch argv retry every scan interval forever.
    def old_maybe_relaunch(entry, dry_run, current):
        argv = entry.get("relaunch_argv")
        if not argv:
            return "pane_unavailable"
        if entry.get("relaunch_count", 0) >= entry.get("max_relaunch", 1):
            return "relaunch_stopped"
        if dry_run:
            return "would_relaunch"
        subprocess.run(argv, check=False, timeout=entry.get("relaunch_timeout_seconds", 30))  # raises here
        entry["relaunch_count"] = entry.get("relaunch_count", 0) + 1  # pre-fix: never reached on raise
        return "relaunch"

    def fake_run(argv, **kwargs):
        raise FileNotFoundError(2, "No such file or directory", argv[0])

    monkeypatch.setattr(subprocess, "run", fake_run)

    entry = _entry(max_relaunch=3)

    # Simulate run_scan's per-pane isolation catching the raise every time, exactly as the
    # daemon does today -- the exception never escapes to the caller, but (pre-fix) it also
    # never bumps the counter.
    for _ in range(10):
        try:
            old_maybe_relaunch(entry, dry_run=False, current=CUR)
        except Exception:
            pass  # this is what run_scan's isolation try/except does

    assert entry["relaunch_count"] == 0, (
        "pre-fix shape: relaunch_count never advances past 0 because the increment is "
        "unreachable once subprocess.run raises -- this is the unbounded-retry defect"
    )
    # max_relaunch (3) was never tripped after 10 attempts -- proving the retry was unbounded
    # under the pre-fix shape, in contrast to the fixed WD.maybe_relaunch above which stops
    # attempting after exactly max_relaunch failures.


# --- Regression: a normal, successful relaunch is unaffected --------------------------------

def test_maybe_relaunch_success_path_still_increments_once_and_honors_cap(tmp_path, monkeypatch):
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))
    calls: list[list[str]] = []

    def fake_run(argv, **kwargs):
        calls.append(argv)

        class _CP:
            returncode = 0

        return _CP()

    monkeypatch.setattr(WD.subprocess, "run", fake_run)

    entry = _entry(max_relaunch=2)

    r1 = WD.maybe_relaunch(entry, dry_run=False, current=CUR)
    assert r1 == "relaunch"
    assert entry["relaunch_count"] == 1

    r2 = WD.maybe_relaunch(entry, dry_run=False, current=CUR)
    assert r2 == "relaunch"
    assert entry["relaunch_count"] == 2

    # Cap still trips at max_relaunch exactly as before the fix.
    r3 = WD.maybe_relaunch(entry, dry_run=False, current=CUR)
    assert r3 == "relaunch_stopped"
    assert entry["relaunch_count"] == 2, "a stopped attempt must not further increment the count"
    assert len(calls) == 2, "no subprocess.run call once the cap has tripped"


def test_maybe_relaunch_dry_run_does_not_spawn_or_increment(tmp_path, monkeypatch):
    # Regression: dry-run behavior (would_relaunch) untouched by the fix.
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))
    called = False

    def fake_run(argv, **kwargs):
        nonlocal called
        called = True

    monkeypatch.setattr(WD.subprocess, "run", fake_run)
    entry = _entry(max_relaunch=3)
    result = WD.maybe_relaunch(entry, dry_run=True, current=CUR)
    assert result == "would_relaunch"
    assert entry["relaunch_count"] == 0
    assert called is False
