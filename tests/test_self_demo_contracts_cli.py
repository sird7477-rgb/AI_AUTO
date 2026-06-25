"""CLI entry point for self_demo_contracts.

The CLI is the missing mechanism that lets a shell gate invoke one named
contract fail-closed: accepted -> exit 0, rejected -> exit 1, bad usage /
unknown contract / invalid JSON -> exit 2. It is what turns a contract's
ContractResult(accepted=False) (contracts never raise) into a nonzero exit.
"""
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts" / "self_demo_contracts.py"

VALID_SUMMARY = {
    "final_decision": "proceed",
    "decision_reason": "both reviewers approved",
    "review_coverage": "multi_reviewer",
    "trust_level": "normal",
    "missing_or_unusable_reviewers": "none",
    "authority_statement": "both reviewers approve",
}


def _run(contract, payload):
    return subprocess.run(
        [sys.executable, str(SCRIPT), contract],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        cwd=str(REPO),
    )


def test_accepted_contract_exits_zero():
    result = _run("review_gate_short_summary", VALID_SUMMARY)
    assert result.returncode == 0, result.stderr


def test_rejected_contract_exits_one_with_reason_on_stderr():
    bad = {**VALID_SUMMARY, "review_coverage": "single"}  # normal trust needs multi_reviewer
    result = _run("review_gate_short_summary", bad)
    assert result.returncode == 1
    assert "normal_trust_requires_multi_reviewer" in result.stderr


def test_unknown_contract_exits_two():
    result = _run("no_such_contract", {})
    assert result.returncode == 2
    assert "unknown contract" in result.stderr


def test_invalid_json_exits_two():
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "review_gate_short_summary"],
        input="{not json",
        capture_output=True,
        text=True,
        cwd=str(REPO),
    )
    assert result.returncode == 2
    assert "invalid JSON" in result.stderr


def test_missing_argument_exits_two():
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        input="{}",
        capture_output=True,
        text=True,
        cwd=str(REPO),
    )
    assert result.returncode == 2
    assert "usage" in result.stderr


def test_list_argument_contract_supported():
    # diff_scope_classification takes a list, not a dict — the CLI must pass it through.
    result = _run("diff_scope_classification", ["docs/readme.md", "plans/x.md"])
    assert result.returncode == 0, result.stderr
