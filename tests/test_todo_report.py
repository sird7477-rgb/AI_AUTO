import importlib.util
import sys
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "todo-report.py"
SPEC = importlib.util.spec_from_file_location("todo_report", SCRIPT)
assert SPEC is not None
todo_report = importlib.util.module_from_spec(SPEC)
sys.modules["todo_report"] = todo_report
assert SPEC.loader is not None
SPEC.loader.exec_module(todo_report)
parse_backlog = todo_report.parse_backlog


def test_parse_backlog_separates_active_complete_and_non_active_statuses() -> None:
    text = """
## Structural Weakness Inventory

| ID | Area | Priority | Status | Boundary Note |
| --- | --- | --- | --- | --- |
| SA-1 | Review Gate | high | complete_contract | covered by fixture |
| SA-2 | Runtime Future | medium | reference_only | not active |
| SA-3 | Open Contract | medium | contract_started | runtime caller missing |

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


def test_repo_backlog_has_no_active_todos_after_clearance() -> None:
    backlog = Path("plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md")
    items = parse_backlog(backlog.read_text(encoding="utf-8"))

    active = [item.item_id for item in items if item.status in {"open", "planned_not_run", "insufficiently_run", "contract_started"}]

    assert active == []
