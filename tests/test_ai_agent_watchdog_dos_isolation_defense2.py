"""BLUE fix (ops-defense2 R... ): watchdog whole-daemon DoS from one poisoned pane.

Confirmed HIGH/LIVE defect being closed here (two-part, defense in depth):

  A. `parse_reset_at`'s relative-time branch (`resets in <N>s`) parsed N with
     UNBOUNDED digits. `current + int(n)` (current is a float) raises
     OverflowError ("int too large to convert to float") once N is large
     enough (hundreds of digits). This is reachable from ordinary monitored
     pane text -- a tmux pane merely needs to contain that substring (e.g.
     web content the agent `cat`'d, a prompt-injected subagent output, a
     file) for the reset-scheduling path (which exists precisely for the
     stable/idle-content condition) to raise.

  B. `run_scan`'s per-iteration loop called `scan_entry` for every registered
     pane with NO try/except, so ONE pane raising (from (A), or a tmux
     capture failure, or anything else) propagated all the way out of
     `run_scan` -- aborting the scan of every OTHER registered pane in that
     iteration and killing the whole watchdog daemon process. A single
     on-screen string in one pane was a denial of service against every
     other monitored session.

Fix (tools/ai-agent-watchdog only):
  A. `parse_reset_at` clamps the parsed relative seconds to MAX_REL_SECONDS
     (43200s / 12h, reusing the ledger's existing max-wait notion) before
     doing the `current + seconds` arithmetic, wrapped in a belt-and-
     suspenders try/except (OverflowError, ValueError) that returns None.
     Normal behavior (`resets in 300s` -> now+300, the 12h am/pm clock
     forms) is unchanged -- see test_ai_agent_watchdog_reset_parse.py.
  B. `run_scan` wraps the per-pane `scan_entry` call in try/except Exception
     (re-raising KeyboardInterrupt/SystemExit), logs the pane id + exception
     class to stderr, and `continue`s to the next pane. The registry lock
     (`_state_lock`) is unaffected -- it's a context manager entered once per
     iteration around the whole loop, released via its own try/finally
     regardless of what happens inside.

Non-vacuousness: both tests below embed a small in-test reconstruction of
the PRE-FIX arithmetic/loop (not read from git) and prove it actually raises
/ actually aborts on the exact same input that the fixed code on disk
now handles cleanly.
"""
from __future__ import annotations

import datetime as dt
import importlib.machinery
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
_TOOL = ROOT / "tools" / "ai-agent-watchdog"


def _load():
    loader = importlib.machinery.SourceFileLoader("ai_agent_watchdog_under_test_dos", str(_TOOL))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)  # safe: the tool guards execution behind `if __name__ == "__main__"`
    return mod


WD = _load()
CUR = dt.datetime(2026, 7, 7, 18, 30, 0).timestamp()


# --- Part A: parse_reset_at must never raise on an absurd relative-time value -------------

def test_parse_reset_at_huge_relative_seconds_does_not_raise():
    poisoned = "resets in " + ("9" * 400) + "s"
    ts = WD.parse_reset_at(poisoned, CUR)  # must not raise
    assert ts is not None, "an implausibly-large relative time should clamp, not vanish to None"
    assert ts == pytest.approx(CUR + WD.MAX_REL_SECONDS), (
        "huge N must be clamped to the module's far-future ceiling, not used verbatim"
    )
    assert ts < CUR + 10**9, "clamped result must be a sane, finite near-term timestamp"


def test_parse_reset_at_moderately_large_real_value_still_works_unclamped():
    # A real, plausible-but-large value under the ceiling must pass through unchanged --
    # the clamp must not clobber legitimate large-but-sane relative waits.
    ts = WD.parse_reset_at("resets in 5000s", CUR)
    assert ts == pytest.approx(CUR + 5000)


def test_parse_reset_at_existing_small_relative_and_clock_forms_unchanged():
    # Regression guard: the fix must not disturb the two already-covered forms.
    assert WD.parse_reset_at("resets in 300s", CUR) == pytest.approx(CUR + 300)
    ts = WD.parse_reset_at("resets 11:20pm", CUR)
    assert dt.datetime.fromtimestamp(ts).strftime("%H:%M") == "23:20"


def test_old_unguarded_relative_arithmetic_raises_overflow_on_the_same_input():
    # Non-vacuous: reconstruct the PRE-FIX arithmetic in-test (this is exactly what the
    # shipped code did before the fix -- `return current + int(rel.group(1))`, no clamp, no
    # guard) and prove IT raises OverflowError on the identical poisoned digit string that
    # the fixed WD.parse_reset_at now handles without raising. This is not read from git --
    # it is a literal, minimal reconstruction of the vulnerable expression.
    def old_parse_rel(current: float, digits: str) -> float:
        return current + int(digits)  # pre-fix: unbounded, unguarded

    with pytest.raises(OverflowError):
        old_parse_rel(CUR, "9" * 400)


# --- Part B: run_scan must isolate one pane's exception from every other pane ------------

def test_run_scan_isolates_one_poisoned_pane_from_the_rest(tmp_path, monkeypatch):
    # "pane-a" sorts FIRST -- matching run_scan's own `sorted(data["entries"].items())`
    # iteration order -- so this proves a FAILURE raised on an EARLIER pane does not prevent
    # LATER panes from being reached, which is the actual property the fix adds.
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))
    WD.save_registry({
        "version": 1,
        "entries": {
            "pane-a-poisoned": {"pane": "pane-a-poisoned"},
            "pane-b": {"pane": "pane-b"},
            "pane-c": {"pane": "pane-c"},
        },
    })

    processed: list[str] = []

    def fake_scan_entry(entry, dry_run):
        pane = entry["pane"]
        if pane == "pane-a-poisoned":
            raise OverflowError("int too large to convert to float")  # simulates the (A) defect
        processed.append(pane)
        return "no_action"

    monkeypatch.setattr(WD, "scan_entry", fake_scan_entry)

    rc = WD.run_scan(1, 0.0, dry_run=True)  # must return normally, not raise

    assert rc == 0
    assert processed == ["pane-b", "pane-c"], (
        "every non-poisoned pane must still be scanned in the same iteration "
        f"as the poisoned one; got {processed!r}"
    )


def test_run_scan_reraises_keyboard_interrupt_and_system_exit(tmp_path, monkeypatch):
    # The isolation must not swallow real control-flow signals.
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))
    WD.save_registry({"version": 1, "entries": {"pane-a": {"pane": "pane-a"}}})

    def fake_scan_entry(entry, dry_run):
        raise KeyboardInterrupt()

    monkeypatch.setattr(WD, "scan_entry", fake_scan_entry)
    with pytest.raises(KeyboardInterrupt):
        WD.run_scan(1, 0.0, dry_run=True)


def test_registry_lock_still_released_after_a_poisoned_pane(tmp_path, monkeypatch):
    # Belt-and-suspenders: confirm the lock discipline (_state_lock as a context manager
    # around the whole per-iteration loop) is not defeated by a per-pane exception -- a
    # second run_scan call afterwards must not deadlock (would hang/timeout if the flock
    # were leaked).
    monkeypatch.setenv("AI_AGENT_WATCHDOG_STATE_DIR", str(tmp_path / "state"))
    WD.save_registry({"version": 1, "entries": {"pane-a": {"pane": "pane-a"}}})

    def raising_scan_entry(entry, dry_run):
        raise ValueError("boom")

    monkeypatch.setattr(WD, "scan_entry", raising_scan_entry)
    WD.run_scan(1, 0.0, dry_run=True)

    monkeypatch.setattr(WD, "scan_entry", lambda entry, dry_run: "no_action")
    rc = WD.run_scan(1, 0.0, dry_run=True)  # would hang under a leaked flock
    assert rc == 0


def test_old_unguarded_loop_aborts_before_reaching_pane_b_on_the_same_monkeypatch():
    # Non-vacuous: reconstruct the PRE-FIX per-iteration loop in-test -- a plain `for`
    # calling scan_entry with NO try/except, exactly as run_scan's loop body read before
    # this fix -- and show that the identical poisoned-pane callable used above aborts it
    # before pane-b (or pane-c) is ever processed. This is a literal, minimal
    # reconstruction of the vulnerable loop shape, not read from git.
    # Name it to sort FIRST (sorted() order matches run_scan's own `sorted(...)` iteration),
    # so the abort is guaranteed to happen before pane-b/pane-c are ever reached.
    entries = {
        "pane-0-poisoned": {"pane": "pane-0-poisoned"},
        "pane-b": {"pane": "pane-b"},
        "pane-c": {"pane": "pane-c"},
    }
    processed: list[str] = []

    def fake_scan_entry(entry, dry_run):
        pane = entry["pane"]
        if pane == "pane-0-poisoned":
            raise OverflowError("int too large to convert to float")
        processed.append(pane)
        return "no_action"

    def old_run_scan_once(entries_dict, scan_fn):
        results = {}
        for pane, entry in sorted(entries_dict.items()):
            results[pane] = scan_fn(entry, dry_run=True)  # pre-fix: no try/except here
        return results

    with pytest.raises(OverflowError):
        old_run_scan_once(entries, fake_scan_entry)

    assert processed == [], (
        "the pre-fix loop shape must abort BEFORE reaching pane-b/pane-c "
        "(sorted order visits pane-poisoned first), proving isolation is what "
        "the fix adds rather than something the old shape already had"
    )
