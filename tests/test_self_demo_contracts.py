from scripts.self_demo_contracts import (
    artifact_sync,
    benchmark_evidence,
    completion_authority,
    reviewer_eligibility,
    self_demo_record,
)


def valid_demo_record() -> dict[str, object]:
    return {
        "change_class": "helper",
        "scenario": "user runs a representative helper check",
        "command_or_simulation": "python -m scripts.self_demo_contracts fixture",
        "expected_behavior": "reports evidence without mutating state",
        "evidence": "pytest fixture output",
        "side_effects": "none",
        "cleanup_state": "not_applicable",
        "manual_checks": "none",
        "demo_verdict": "pass",
    }


def valid_benchmark_record() -> dict[str, object]:
    return {
        "scenario": "helper validates a representative workflow",
        "functional_demo_verdict": "pass",
        "metric": "runtime_ms",
        "baseline": 100,
        "measured": 95,
        "threshold": 120,
        "unit": "ms",
        "direction": "lower_is_better",
        "environment": "local pytest fixture",
        "sample_count": 3,
        "threshold_source": "temporary_fixture",
    }


def test_self_demo_record_requires_representative_evidence() -> None:
    assert self_demo_record(valid_demo_record()).accepted
    missing = self_demo_record({"change_class": "helper"})
    assert missing.reason == "missing_self_demo_fields"
    assert "scenario" in missing.data["missing"]
    empty = self_demo_record({**valid_demo_record(), "scenario": "   ", "evidence": ""})
    assert empty.reason == "empty_self_demo_fields"
    assert empty.data["empty"] == ["evidence", "scenario"]


def test_self_demo_record_separates_valid_shape_from_readiness() -> None:
    degraded = self_demo_record({**valid_demo_record(), "demo_verdict": "degraded"})
    assert not degraded.accepted
    assert degraded.reason == "self_demo_not_ready"
    assert degraded.data["record_valid"] is True


def test_self_demo_record_cannot_replace_verify_or_review_gate() -> None:
    assert self_demo_record({**valid_demo_record(), "replaces_verify": True}).reason == (
        "self_demo_must_not_replace_verification_gates"
    )
    assert self_demo_record({**valid_demo_record(), "replaces_review_gate": True}).reason == (
        "self_demo_must_not_replace_verification_gates"
    )
    assert self_demo_record({**valid_demo_record(), "write_capable": True}).reason == (
        "write_capable_demo_requires_scope"
    )


def test_benchmark_lives_after_functional_demo_and_before_tool_adoption() -> None:
    valid = valid_benchmark_record()
    result = benchmark_evidence(valid)
    assert not result.accepted
    assert result.reason == "benchmark_fixture_only"
    assert result.data["contract_valid"] is True
    assert result.data["readiness_supported"] is False
    assert benchmark_evidence({**valid, "functional_demo_verdict": "fail"}).reason == (
        "benchmark_requires_functional_demo_pass"
    )
    assert benchmark_evidence({**valid, "claims_tool_adoption": True}).reason == (
        "benchmark_does_not_approve_tool_adoption"
    )


def test_benchmark_reports_degraded_without_becoming_gate_replacement() -> None:
    degraded_record = {
        **valid_benchmark_record(),
        "measured": 150,
        "sample_count": 2,
        "threshold_source": "project_baseline",
        "baseline_evidence": "captured by tests on 2026-05-28 in local venv",
        "threshold_rationale": "allows 20 percent regression from captured baseline",
    }
    degraded = benchmark_evidence(degraded_record)
    assert not degraded.accepted
    assert degraded.reason == "benchmark_degraded"
    assert benchmark_evidence({**degraded_record, "replaces_verify": True}).reason == (
        "benchmark_must_not_replace_verification_gates"
    )


def test_benchmark_threshold_source_must_support_readiness_claims() -> None:
    valid = valid_benchmark_record()
    assert benchmark_evidence({**valid, "claims_readiness": True}).reason == (
        "temporary_fixture_cannot_support_readiness"
    )
    assert benchmark_evidence({**valid, "threshold_source": "project_baseline", "claims_readiness": True}).reason == (
        "missing_project_baseline_evidence"
    )
    assert benchmark_evidence(
        {
            **valid,
            "threshold_source": "project_baseline",
            "baseline_evidence": "captured by tests on 2026-05-28 in local venv",
            "threshold_rationale": "allows 20 percent regression from captured baseline",
            "claims_readiness": True,
        }
    ).accepted
    assert benchmark_evidence({**valid, "threshold_source": "established_standard"}).reason == (
        "missing_threshold_reference"
    )
    assert benchmark_evidence(
        {
            **valid,
            "threshold_source": "established_standard",
            "threshold_reference": "trust me",
        }
    ).reason == "invalid_threshold_reference"
    assert benchmark_evidence(
        {
            **valid,
            "threshold_source": "established_standard",
            "threshold_reference": "docs/performance-slo.md#self-demo-runtime",
        }
    ).accepted


def test_benchmark_classifies_failures_and_invalid_inputs() -> None:
    valid = {
        **valid_benchmark_record(),
        "threshold_source": "project_baseline",
        "baseline_evidence": "captured by tests on 2026-05-28 in local venv",
        "threshold_rationale": "allows 20 percent regression from captured baseline",
    }
    assert benchmark_evidence({**valid, "benchmark_run_status": "fail"}).reason == "benchmark_fail"
    assert benchmark_evidence({**valid, "direction": "sideways"}).reason == "invalid_benchmark_direction"
    assert benchmark_evidence({**valid, "threshold_source": "invented"}).reason == "invalid_threshold_source"
    assert benchmark_evidence({**valid, "sample_count": 0}).reason == "benchmark_requires_samples"
    assert benchmark_evidence({**valid, "sample_count": "many"}).reason == "invalid_sample_count"
    assert benchmark_evidence({**valid, "measured": "fast"}).reason == "invalid_benchmark_number"
    assert benchmark_evidence({**valid, "measured": -1}).reason == "negative_benchmark_number"


def test_benchmark_supports_higher_is_better() -> None:
    valid = {
        **valid_benchmark_record(),
        "metric": "throughput_ops",
        "baseline": 100,
        "measured": 125,
        "threshold": 110,
        "unit": "ops",
        "direction": "higher_is_better",
        "threshold_source": "project_baseline",
        "baseline_evidence": "captured by tests on 2026-05-28 in local venv",
        "threshold_rationale": "requires at least 10 percent gain over baseline",
    }
    result = benchmark_evidence(valid)
    assert result.accepted
    assert result.reason == "benchmark_pass"
    zero_baseline = benchmark_evidence({**valid, "baseline": 0})
    assert zero_baseline.accepted
    assert zero_baseline.data["ratio"] == float("inf")


def test_reviewer_eligibility_blocks_false_unanimity() -> None:
    report = reviewer_eligibility(
        [
            {"name": "Claude", "coverage": "independent", "context_completeness": 1.0, "verdict": "approve"},
            {
                "name": "Codex",
                "coverage": "fallback",
                "context_completeness": 1.0,
                "verdict": "approve_with_notes",
            },
            {"name": "Host", "host_executor": True, "context_completeness": 1.0, "verdict": "approve"},
            {
                "name": "SameSession",
                "same_session_executor": True,
                "context_completeness": 1.0,
                "verdict": "approve",
            },
            {
                "name": "Truncated",
                "truncated_context": True,
                "context_completeness": 1.0,
                "verdict": "approve",
            },
            {"name": "LowContext", "context_completeness": 0.5, "verdict": "approve"},
            {
                "name": "DegradedSignals",
                "context_completeness": 1.0,
                "degraded_signals": True,
                "verdict": "approve",
            },
        ]
    )
    assert report["unanimous_eligible"] is False
    assert report["ineligible"]["Codex"] == "fallback_or_degraded_coverage"
    assert report["ineligible"]["Host"] == "host_executor_not_independent"
    assert report["ineligible"]["SameSession"] == "same_session_executor_not_independent"
    assert report["ineligible"]["Truncated"] == "truncated_context"
    assert report["ineligible"]["LowContext"] == "context_incomplete"
    assert report["ineligible"]["DegradedSignals"] == "degraded_signals_present"


def test_completion_authority_remains_leader_owned() -> None:
    valid = {
        "diff_inspected": True,
        "plan_alignment": True,
        "verify": True,
        "review_gate": True,
        "review_gate_decision": "proceed",
        "leader_owned_final": True,
    }
    assert completion_authority(valid).accepted
    assert completion_authority({**valid, "sidecar_claims_authority": True}).reason == "sidecar_authority_forbidden"
    missing = completion_authority({**valid, "verify": False, "review_gate": False})
    assert missing.reason == "missing_completion_fields"
    assert missing.data["missing"] == ["verify", "review_gate"]


def test_reviewer_eligibility_handles_invalid_context_and_duplicate_names() -> None:
    report = reviewer_eligibility(
        [
            {"name": "NoneContext", "context_completeness": None, "verdict": "approve"},
            {"name": "StringContext", "context_completeness": "0.95", "verdict": "approve"},
            {"host_executor": True, "context_completeness": 1.0, "verdict": "approve"},
            {"truncated_context": True, "context_completeness": 1.0, "verdict": "approve"},
        ]
    )
    assert report["eligible"] == ["StringContext"]
    assert report["ineligible"]["NoneContext"] == "invalid_context_completeness"
    assert report["ineligible"]["reviewer_3"] == "host_executor_not_independent"
    assert report["ineligible"]["reviewer_4"] == "truncated_context"


def test_artifact_sync_requires_material_findings_to_land_or_defer() -> None:
    assert artifact_sync(
        [
            {"id": "A", "material": True, "artifact": "plans/example.md"},
            {"id": "B", "material": True, "deferred_with_reason": "later phase"},
            {"id": "C", "material": False},
        ]
    ).accepted
    missing = artifact_sync([{"id": "late-finding", "material": True}])
    assert missing.reason == "material_findings_missing_artifact_sync"
    assert missing.data["unsynced"] == ["late-finding"]
