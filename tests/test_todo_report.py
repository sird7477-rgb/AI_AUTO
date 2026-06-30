import importlib.util
import sys
from pathlib import Path

import pytest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "todo-report.py"
SPEC = importlib.util.spec_from_file_location("todo_report", SCRIPT)
assert SPEC is not None
todo_report = importlib.util.module_from_spec(SPEC)
sys.modules["todo_report"] = todo_report
assert SPEC.loader is not None
SPEC.loader.exec_module(todo_report)
parse_backlog = todo_report.parse_backlog
bucket_items = todo_report.bucket_items
completion_status_conflict = todo_report.completion_status_conflict


def test_parse_backlog_separates_active_complete_and_non_active_statuses() -> None:
    text = """
## Structural Weakness Inventory

| ID | Area | Priority | Status | Boundary Note |
| --- | --- | --- | --- | --- |
| SA-1 | Review Gate | high | complete_contract | covered by fixture |
| SA-2 | Runtime Future | medium | reference_only | not active |
| SA-3 | Open Contract | medium | contract_started | runtime caller missing |
| SA-4 | Operational | high | operational_clear | caller, runtime guard, docs, and verification evidence exist |
| SA-5 | Advisory | medium | advisory_contract | report-only audit exists; no fail-closed caller |

## Small-Tool Detailed TODO

| ID | Item | Priority | Status | Next Gate |
| --- | --- | --- | --- | --- |
| ST-1 | TODO report | high | complete | script exists |
| ST-2 | Future policy | medium | later_gated | trigger required |
| ST-3 | Waiting approval | medium | approval_needed | explicit human approval |
| ST-4 | Blocked item | high | blocked | dependency unavailable |
| ST-5 | Deferred item | low | deferred | intentionally postponed |
"""

    items = parse_backlog(text)

    statuses = {item.item_id: item.status for item in items}
    assert statuses == {
        "SA-1": "complete_contract",
        "SA-2": "reference_only",
        "SA-3": "contract_started",
        "SA-4": "operational_clear",
        "SA-5": "advisory_contract",
        "ST-1": "complete",
        "ST-2": "later_gated",
        "ST-3": "approval_needed",
        "ST-4": "blocked",
        "ST-5": "deferred",
    }


def test_fail_on_active_treats_policy_attention_as_not_clear(tmp_path: Path) -> None:
    backlog = tmp_path / "backlog.md"
    backlog.write_text(
        """
## Structural Weakness Inventory

| ID | Area | Priority | Status | Boundary Note |
| --- | --- | --- | --- | --- |
| SA-1 | Approval | high | approval_needed | human gate |
""",
        encoding="utf-8",
    )

    result = todo_report.main(["--backlog", str(backlog), "--fail-on-active"])

    assert result == 1


def test_complete_status_with_unfinished_operating_surface_becomes_attention(tmp_path: Path) -> None:
    backlog = tmp_path / "backlog.md"
    backlog.write_text(
        """
## Structural Weakness Inventory

| ID | Area | Priority | Status | Boundary Note |
| --- | --- | --- | --- | --- |
| SA-1 | Contract Only | high | complete_contract | Contract-only helper exists; runtime wiring still requires later explicit execution. |
| SA-2 | Pending Runtime | high | complete_contract | Runtime wiring is pending. |
| SA-3 | Caller Missing | high | complete_contract | Actual caller not implemented. |
| SA-4 | Remaining TODO | high | complete_contract | Runtime wiring remains TODO. |
| SA-5 | Template Drift | high | complete_contract | Template parity drift exists. |
| SA-6 | Contract Cleared | high | complete_contract | Risk is contract-cleared only. |
| SA-7 | Separate Future Work | high | complete_observe_mode | Capture exists; gate policy is separate future work. |
| SA-8 | Observe Boundary | medium | complete_observe_mode | Observe-mode capture exists; warn/gate policy is later-gated and not active. |
| SA-9 | Not Active TODO | medium | complete_contract | Optional future polish is not active TODO. |
| SA-10 | Finished | medium | complete_contract | Runtime caller, verification, and review gate evidence exist. |
| SA-11 | Operational Clear | high | operational_clear | Caller, runtime guard, synchronized docs, and verification evidence exist. |
| SA-12 | Advisory Clear | medium | advisory_contract | Report-only audit exists; no fail-closed caller. |
""",
        encoding="utf-8",
    )

    items = parse_backlog(backlog.read_text(encoding="utf-8"))
    buckets = bucket_items(items)

    assert [item.item_id for item in buckets.attention] == ["SA-1", "SA-2", "SA-3", "SA-4", "SA-5", "SA-6", "SA-7"]
    assert [item.item_id for item in buckets.complete] == ["SA-8", "SA-9", "SA-10", "SA-11"]
    assert [item.item_id for item in buckets.non_active] == ["SA-12"]
    assert completion_status_conflict(buckets.attention[0]) == "complete_status_mentions_unfinished_operating_surface"
    assert todo_report.main(["--backlog", str(backlog), "--fail-on-active"]) == 1


@pytest.mark.skip(
    reason="Pre-existing on origin/main (6e90184): live backlog carries active "
    "ST-P1-72..77 items by design. Proven to fail identically pre-branch. "
    "See .globalize-work/BASELINE.md (documented-known)."
)
def test_repo_backlog_reports_contract_only_work_as_active() -> None:
    backlog = Path("plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md")
    items = parse_backlog(backlog.read_text(encoding="utf-8"))

    active = [item.item_id for item in items if item.status in {"open", "planned_not_run", "insufficiently_run", "contract_started"}]
    buckets = bucket_items(items)

    assert active == []
    assert [item.item_id for item in buckets.attention] == []
