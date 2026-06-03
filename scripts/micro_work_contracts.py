"""Pure contracts for AI_AUTO MicroWork unit validation.

Side-effect-free: validates the shape of a "micro-unit" work definition and
computes a report-only scope audit. It never executes work, mutates files, or
holds completion authority above `scripts/verify.sh` / `scripts/review-gate.sh`.

A micro-unit is a JSON object describing one bounded slice of work: its goal,
the smallest useful wedge, in-scope paths, explicit non-goals, the evidence
required to call it done, and the completion criteria. The point is to make the
"micro unit + scope discipline + immutable completion criteria" working style
checkable instead of prose-only.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ContractResult:
    accepted: bool
    reason: str
    data: dict[str, Any]


REQUIRED_FIELDS = (
    "id",
    "goal",
    "scope_paths",
    "smallest_useful_wedge",
    "non_goals",
    "required_evidence",
    "completion_criteria",
)
LIST_FIELDS = ("scope_paths", "non_goals", "required_evidence", "completion_criteria")


def _nonempty_str(value: Any) -> bool:
    return isinstance(value, str) and value.strip() != ""


def _nonempty_list(value: Any) -> bool:
    return isinstance(value, (list, tuple)) and any(_nonempty_str(item) for item in value)


def validate_micro_unit(record: dict[str, Any]) -> ContractResult:
    """Validate the shape of a micro-unit definition (read-only)."""
    if not isinstance(record, dict):
        return ContractResult(False, "invalid_micro_unit", {})
    missing = []
    for field in REQUIRED_FIELDS:
        value = record.get(field)
        ok = _nonempty_list(value) if field in LIST_FIELDS else _nonempty_str(value)
        if not ok:
            missing.append(field)
    if missing:
        return ContractResult(False, "missing_micro_unit_fields", {"missing": sorted(missing)})

    scope = {item.strip() for item in record["scope_paths"] if _nonempty_str(item)}
    non_goals = {item.strip() for item in record["non_goals"] if _nonempty_str(item)}
    conflict = sorted(scope & non_goals)
    if conflict:
        # A path cannot be both in scope and an explicit non-goal.
        return ContractResult(False, "non_goal_scope_conflict", {"conflict": conflict})
    return ContractResult(True, "micro_unit_ready", {})


def _path_under(path: str, entry: str) -> bool:
    entry = entry.rstrip("/")
    return path == entry or path.startswith(entry + "/")


def micro_work_scope_audit(record: dict[str, Any], changed_paths: list[str]) -> dict[str, Any]:
    """Report-only scope audit; never blocks. Computes drift vs the declared
    scope and non-goals for the given changed paths."""
    if not isinstance(record, dict):
        # Non-object JSON has no scope/non-goals; report nothing rather than crash.
        return {
            "report_only": True,
            "scope_drift": [],
            "non_goal_leak": [],
            "has_required_evidence": False,
            "has_smallest_useful_wedge": False,
        }
    scope_raw = record.get("scope_paths")
    non_goals_raw = record.get("non_goals")
    scope = [item.strip() for item in scope_raw if _nonempty_str(item)] if isinstance(scope_raw, (list, tuple)) else []
    non_goals = [item.strip() for item in non_goals_raw if _nonempty_str(item)] if isinstance(non_goals_raw, (list, tuple)) else []
    changed = [path.strip() for path in (changed_paths or []) if _nonempty_str(path)]

    scope_drift = [path for path in changed if not any(_path_under(path, entry) for entry in scope)]
    non_goal_leak = [path for path in changed if any(_path_under(path, entry) for entry in non_goals)]
    return {
        "report_only": True,
        "scope_drift": scope_drift,
        "non_goal_leak": non_goal_leak,
        "has_required_evidence": _nonempty_list(record.get("required_evidence")),
        "has_smallest_useful_wedge": _nonempty_str(record.get("smallest_useful_wedge")),
    }
