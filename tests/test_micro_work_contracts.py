from scripts.micro_work_contracts import micro_work_scope_audit, validate_micro_unit


def valid_unit() -> dict:
    return {
        "id": "mw-1",
        "goal": "Add the micro-work validator",
        "scope_paths": ["tools/micro-work", "scripts/micro_work_contracts.py"],
        "smallest_useful_wedge": "validator plus tests only; no runtime",
        "non_goals": ["scripts/review-gate.sh"],
        "required_evidence": ["verify", "review-gate"],
        "completion_criteria": ["validate passes", "tests green"],
    }


def test_validate_micro_unit_accepts_complete_unit() -> None:
    result = validate_micro_unit(valid_unit())
    assert result.accepted
    assert result.reason == "micro_unit_ready"


def test_validate_micro_unit_requires_all_fields() -> None:
    missing = validate_micro_unit({"id": "x", "goal": "y"})
    assert not missing.accepted
    assert missing.reason == "missing_micro_unit_fields"
    assert "scope_paths" in missing.data["missing"]
    assert "completion_criteria" in missing.data["missing"]

    # Empty list fields are treated as missing.
    empty_scope = validate_micro_unit({**valid_unit(), "scope_paths": []})
    assert empty_scope.reason == "missing_micro_unit_fields"
    assert empty_scope.data["missing"] == ["scope_paths"]


def test_validate_micro_unit_rejects_scope_nongoal_conflict() -> None:
    conflict = validate_micro_unit(
        {**valid_unit(), "scope_paths": ["a/b"], "non_goals": ["a/b"]}
    )
    assert not conflict.accepted
    assert conflict.reason == "non_goal_scope_conflict"
    assert conflict.data["conflict"] == ["a/b"]


def test_micro_work_scope_audit_is_report_only_and_flags_drift_and_leak() -> None:
    unit = valid_unit()
    audit = micro_work_scope_audit(
        unit,
        ["tools/micro-work", "docs/UNRELATED.md", "scripts/review-gate.sh"],
    )
    assert audit["report_only"] is True
    # docs/UNRELATED.md and scripts/review-gate.sh are outside scope.
    assert "docs/UNRELATED.md" in audit["scope_drift"]
    assert "scripts/review-gate.sh" in audit["scope_drift"]
    # tools/micro-work is in scope, so not drift.
    assert "tools/micro-work" not in audit["scope_drift"]
    # scripts/review-gate.sh is an explicit non-goal -> leak.
    assert audit["non_goal_leak"] == ["scripts/review-gate.sh"]
    assert audit["has_required_evidence"] is True
    assert audit["has_smallest_useful_wedge"] is True

    # A change fully within scope produces no drift and no leak.
    clean = micro_work_scope_audit(unit, ["scripts/micro_work_contracts.py"])
    assert clean["scope_drift"] == []
    assert clean["non_goal_leak"] == []


def test_non_object_json_is_rejected_without_crashing() -> None:
    # Valid JSON that is not an object must fail closed, and the report-only
    # audit must not raise (it has no scope/non-goals to evaluate).
    for bad in ([], "string", 42, None):
        assert validate_micro_unit(bad).reason == "invalid_micro_unit"  # type: ignore[arg-type]
        audit = micro_work_scope_audit(bad, ["a/b"])  # type: ignore[arg-type]
        assert audit["report_only"] is True
        assert audit["scope_drift"] == []
        assert audit["non_goal_leak"] == []

    # An object whose scope_paths/non_goals are wrong types must not crash the
    # audit; they are treated as empty.
    bad_typed = micro_work_scope_audit({"scope_paths": 5, "non_goals": True}, ["a/b"])
    assert bad_typed["scope_drift"] == ["a/b"]
    assert bad_typed["non_goal_leak"] == []
