"""Session-limit reset parsing in tools/ai-agent-watchdog (stop-and-go scheduling).

Regression: the shipped `parse_reset_at` used `resets\\s+([0-2]?[0-9]):([0-5][0-9])\\b`,
which returns None for the real banner "... resets 11:20pm (Asia/Seoul)" (no word boundary
between "20" and "pm"), so NO reset-aware resume was ever scheduled for the exact format
Claude Code emits on a session limit. These tests pin the fixed 12h/am-pm + optional-tz +
optional-"at" parsing. Reverting the fix makes the pm/am cases fail (they return None or the
wrong hour).
"""
import datetime as dt
import importlib.machinery
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
_TOOL = ROOT / "tools" / "ai-agent-watchdog"


def _load():
    loader = importlib.machinery.SourceFileLoader("ai_agent_watchdog_under_test", str(_TOOL))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)  # safe: the tool guards execution behind `if __name__ == "__main__"`
    return mod


WD = _load()
# A fixed "now" so day-rollover assertions are deterministic: 2026-07-07 18:30 local.
CUR = dt.datetime(2026, 7, 7, 18, 30, 0).timestamp()


def _hhmm(ts):
    return dt.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M") if ts is not None else None


def test_real_session_limit_banner_pm_is_parsed_not_none():
    # The exact format from the incident. Old code returned None here.
    ts = WD.parse_reset_at("You've hit your session limit · resets 11:20pm (Asia/Seoul)", CUR)
    assert ts is not None, "pm banner must schedule a reset, not be ignored"
    assert _hhmm(ts) == "2026-07-07 23:20"


@pytest.mark.parametrize(
    "text,want",
    [
        ("resets 8:00am", "2026-07-08 08:00"),        # am, already past -> tomorrow
        ("resets at 8:00am", "2026-07-08 08:00"),      # optional "at"
        ("resets 12:00am", "2026-07-08 00:00"),        # midnight (12am -> 00)
        ("resets 12:30pm", "2026-07-08 12:30"),        # noon-ish 12pm stays 12
        ("resets 11:20PM", "2026-07-07 23:20"),        # case-insensitive suffix
        ("resets 23:20", "2026-07-07 23:20"),          # 24h form still supported
    ],
)
def test_clock_forms(text, want):
    assert _hhmm(WD.parse_reset_at(text, CUR)) == want


def test_relative_and_no_match():
    assert WD.parse_reset_at("resets in 300s", CUR) == pytest.approx(CUR + 300)
    assert WD.parse_reset_at("nothing about limits here", CUR) is None


@pytest.mark.parametrize(
    "text",
    [
        "resets 12:00amazing",       # glued 'amazing' -- no clean separator, reject
        "resets 3:00amber alert",     # glued 'amber'
        "resets 10:30pmatch found",   # glued 'pmatch'
    ],
)
def test_no_over_match_on_glued_prose(text):
    # parse_reset_at is fed the WHOLE captured pane, so a time-shaped token immediately glued
    # to an ordinary word starting with am/pm must NOT be read as a meridiem suffix (would
    # schedule a bogus resume). The trailing \b + single-space separator reject these.
    assert WD.parse_reset_at(text, CUR) is None


def test_meridiem_does_not_bleed_across_a_newline():
    # A legit "resets 12:00" followed on the NEXT line by prose starting with "am" must parse
    # as 12:00 (noon) -- the "am" of "amazing" must NOT be captured as a meridiem (which would
    # wrongly yield 00:00). The single-space (non-newline) meridiem separator guarantees this.
    ts = WD.parse_reset_at("the sprint resets 12:00\namazing work everyone", CUR)
    assert _hhmm(ts) == "2026-07-08 12:00"  # noon tomorrow (12:00 already past 18:30 -> next day)


def test_pm_is_twelve_hours_after_the_buggy_am_interpretation():
    # Guards the specific defect: a naive parse would read "11:20pm" as 11:20 (AM), which is
    # past -> tomorrow 11:20, i.e. ~12h LATE vs the correct 23:20 today.
    ts = WD.parse_reset_at("resets 11:20pm", CUR)
    wrong_am = dt.datetime(2026, 7, 8, 11, 20).timestamp()
    assert ts == dt.datetime(2026, 7, 7, 23, 20).timestamp()
    assert ts < wrong_am


def _cli(args, stdin=""):
    import subprocess
    return subprocess.run([str(_TOOL), "parse-reset", *args], input=stdin,
                          capture_output=True, text=True)


def test_parse_reset_cli_pm_banner_and_seconds():
    r = _cli(["--now", str(CUR), "--json"],
             stdin="You've hit your session limit · resets 11:20pm (Asia/Seoul)")
    assert r.returncode == 0
    import json as _j
    out = _j.loads(r.stdout)
    assert out["seconds_from_now"] == 4 * 3600 + 50 * 60   # 18:30 -> 23:20 today
    assert out["reset_at_local"].endswith("23:20:00")


def test_parse_reset_cli_no_match_exits_1():
    r = _cli([], stdin="no limits mentioned here")
    assert r.returncode == 1
