"""Orchestrator stop-and-go recovery ledger (GAP B / IP-2 minimal core)."""
import json
import subprocess
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parents[1] / "tools" / "ai-agent-watchdog"


def _wd(tmp_path):
    def run(*args, **kw):
        env = {"AI_AGENT_WATCHDOG_STATE_DIR": str(tmp_path / "state"), "HOME": str(tmp_path), "PATH": "/usr/bin:/bin"}
        return subprocess.run([str(TOOL), *args], capture_output=True, text=True, env=env, **kw)
    return run


def test_record_not_before_gate_and_due(tmp_path):
    wd = _wd(tmp_path)
    assert wd("ledger-record", "--key", "k", "--payload", "redo", "--reset-epoch", "2000000000", "--max-retries", "2", "--now", "1999990000").returncode == 0
    assert wd("ledger-due", "--now", "1999999999").returncode == 3          # before reset+eps -> nothing due
    due = wd("ledger-due", "--now", "2000000100", "--json")
    assert due.returncode == 0 and len(json.loads(due.stdout)) == 1


def test_idempotent_by_key(tmp_path):
    wd = _wd(tmp_path)
    wd("ledger-record", "--key", "same", "--reset-epoch", "2000000000", "--now", "1999990000")
    wd("ledger-record", "--key", "same", "--reset-epoch", "2000000000", "--now", "1999990000")
    due = json.loads(wd("ledger-due", "--now", "2000000100", "--json").stdout)
    assert len(due) == 1  # no duplicate


def test_max_retries_exhaustion(tmp_path):
    wd = _wd(tmp_path)
    wd("ledger-record", "--key", "k", "--reset-epoch", "2000000000", "--max-retries", "2", "--now", "1999990000")
    wd("ledger-done", "--key", "k", "--retried")
    wd("ledger-done", "--key", "k", "--retried")
    assert wd("ledger-due", "--now", "2000000100").returncode == 3  # exhausted -> not due


def test_done_removes_from_due(tmp_path):
    wd = _wd(tmp_path)
    wd("ledger-record", "--key", "k", "--reset-epoch", "2000000000", "--now", "1999990000")
    wd("ledger-done", "--key", "k")
    assert wd("ledger-due", "--now", "2000000100").returncode == 3
