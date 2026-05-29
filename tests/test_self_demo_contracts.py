from scripts.self_demo_contracts import (
    artifact_delta_check,
    artifact_sync,
    benchmark_capture_record,
    benchmark_wrapper_plan,
    benchmark_evidence,
    completion_authority,
    diff_scope_classification,
    process_cleanup_evidence,
    reviewer_eligibility,
    review_gate_short_summary,
    self_demo_record,
    todo_report_reconciliation,
    untracked_artifact_review_guard,
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
    assert result.data["readiness_supported"] is False
    readiness = benchmark_evidence({**valid, "claims_readiness": True})
    assert readiness.accepted
    assert readiness.data["readiness_supported"] is True
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


def test_reviewer_eligibility_accepts_all_independent_eligible_reviewers() -> None:
    report = reviewer_eligibility(
        [
            {"name": "Claude", "coverage": "independent", "context_completeness": 1.0, "verdict": "approve"},
            {"name": "Gemini", "coverage": "independent", "context_completeness": 1.0, "verdict": "approve_with_notes"},
        ]
    )
    assert report["eligible"] == ["Claude", "Gemini"]
    assert report["ineligible"] == {}
    assert report["unanimous_eligible"] is True


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
    assert completion_authority({**valid, "subagent_claims_authority": True}).reason == "sidecar_authority_forbidden"
    assert completion_authority({**valid, "checkpoint_claims_authority": True}).reason == "sidecar_authority_forbidden"
    assert completion_authority({**valid, "delegated_claims_authority": True}).reason == "sidecar_authority_forbidden"
    missing = completion_authority({**valid, "verify": False, "review_gate": False})
    assert missing.reason == "missing_completion_fields"
    assert missing.data["missing"] == ["verify", "review_gate"]
    individually_missing = {
        field: completion_authority({**valid, field: False}).data["missing"] for field in (
            "diff_inspected",
            "plan_alignment",
            "leader_owned_final",
        )
    }
    assert individually_missing == {
        "diff_inspected": ["diff_inspected"],
        "plan_alignment": ["plan_alignment"],
        "leader_owned_final": ["leader_owned_final"],
    }
    assert completion_authority({key: value for key, value in valid.items() if key != "review_gate_decision"}).reason == (
        "review_gate_not_ready"
    )
    for decision in ("blocked", "revise", "review_manually", "missing"):
        assert completion_authority({**valid, "review_gate_decision": decision}).reason == "review_gate_not_ready"
    degraded = completion_authority({**valid, "review_gate_decision": "proceed_degraded"})
    assert degraded.reason == "degraded_review_reporting_required"
    assert degraded.data["missing"] == ["degraded_trust_reported", "missing_reviewers_reported"]
    assert completion_authority(
        {
            **valid,
            "review_gate_decision": "proceed_degraded",
            "degraded_trust_reported": True,
            "missing_reviewers_reported": True,
        }
    ).accepted


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


def test_artifact_delta_check_blocks_late_or_final_unsynced_findings() -> None:
    assert artifact_delta_check(
        [
            {
                "id": "late-risk",
                "material": True,
                "learned_after_artifact_write": True,
                "artifact": "plans/example.md",
                "artifact_contains_finding": True,
                "artifact_updated_after_finding": True,
            },
            {
                "id": "deferred-axis",
                "material": True,
                "learned_after_artifact_write": True,
                "deferred_with_reason": "needs separate approval",
            },
            {"id": "minor-note", "material": False, "appears_in_final_answer": True},
        ]
    ).accepted

    late_missing_update = artifact_delta_check(
        [
            {
                "id": "late-risk",
                "material": True,
                "learned_after_artifact_write": True,
                "artifact": "plans/example.md",
                "artifact_contains_finding": True,
            }
        ]
    )
    assert late_missing_update.reason == "late_findings_missing_artifact_update"
    assert late_missing_update.data["unsynced"] == ["late-risk"]

    final_answer_missing_artifact = artifact_delta_check(
        [{"id": "final-claim", "material": True, "appears_in_final_answer": True}]
    )
    assert final_answer_missing_artifact.reason == "final_answer_contains_unsynced_findings"
    assert final_answer_missing_artifact.data["unsynced"] == ["final-claim"]

    final_answer_missing_artifact_path = artifact_delta_check(
        [
            {
                "id": "final-claim",
                "material": True,
                "appears_in_final_answer": True,
                "artifact_contains_finding": True,
            }
        ]
    )
    assert final_answer_missing_artifact_path.reason == "final_answer_contains_unsynced_findings"
    assert final_answer_missing_artifact_path.data["unsynced"] == ["final-claim"]


def test_review_gate_short_summary_blocks_overstated_authority() -> None:
    valid = {
        "final_decision": "proceed_degraded",
        "decision_reason": "single_external_plus_codex_fallback_approval",
        "review_coverage": "single_external_plus_codex_fallback",
        "trust_level": "degraded",
        "missing_or_unusable_reviewers": "claude:skipped",
        "authority_statement": "degraded approval only",
        "degraded_trust_reported": True,
        "missing_reviewers_reported": True,
    }
    assert review_gate_short_summary(valid).accepted
    assert review_gate_short_summary({**valid, "degraded_trust_reported": False}).reason == (
        "degraded_summary_missing_disclosure"
    )
    assert review_gate_short_summary({**valid, "trust_level": "normal"}).reason == (
        "normal_trust_requires_multi_reviewer"
    )
    assert review_gate_short_summary({**valid, "authority_statement": "unanimous approval"}).reason == (
        "unanimity_requires_multi_reviewer_coverage"
    )


def test_untracked_artifact_review_guard_requires_context_or_manual_review() -> None:
    valid = {
        "guard_status": "clear",
        "files": [
            {"path": "plans/new-plan.md", "material": True, "included_in_context": True},
            {"path": "notes/private.md", "material": True, "secret_risk": True, "manual_review_required": True},
            {"path": "scratch.tmp", "material": False},
        ]
    }
    assert untracked_artifact_review_guard(valid).accepted
    missing = untracked_artifact_review_guard(
        {"files": [{"path": "plans/new-plan.md", "material": True, "included_in_context": False}]}
    )
    assert missing.reason == "material_untracked_artifacts_not_reviewed"
    assert missing.data["files"] == ["plans/new-plan.md"]
    structured_missing = untracked_artifact_review_guard(
        {
            "guard_status": "material_untracked_artifacts_present",
            "manual_review_required": True,
            "manual_reviewed": False,
            "files": [{"path": "plans/new-plan.md", "material": True, "included_in_context": True}],
        }
    )
    assert structured_missing.reason == "material_untracked_artifacts_require_manual_review"
    structured_reviewed = untracked_artifact_review_guard(
        {
            "guard_status": "material_untracked_artifacts_present",
            "manual_review_required": True,
            "manual_reviewed": True,
            "files": [{"path": "plans/new-plan.md", "material": True, "included_in_context": True}],
        }
    )
    assert structured_reviewed.accepted


def test_todo_report_reconciliation_separates_unresolved_and_deferred_work() -> None:
    result = todo_report_reconciliation(
        [
            {"id": "done", "status": "complete", "evidence": "./scripts/verify.sh pass"},
            {"id": "contract-done", "status": "complete_contract", "evidence": "contract and runtime caller verified"},
            {"id": "planned", "status": "planned_not_run"},
            {"id": "later", "status": "later_gated", "reason": "separate trigger"},
            {"id": "reference", "status": "reference_only", "reason": "not active work"},
            {"id": "contract", "status": "contract_started"},
        ]
    )
    assert result.accepted
    assert result.data["unresolved"] == ["planned", "contract"]
    assert todo_report_reconciliation([{"id": "bad-contract-done", "status": "complete_contract"}]).reason == (
        "invalid_todo_report"
    )
    assert todo_report_reconciliation([{"id": "bad-done", "status": "complete"}]).reason == "invalid_todo_report"
    assert todo_report_reconciliation([{"id": "bad-later", "status": "later_gated"}]).data["invalid"] == {
        "bad-later": "non_active_status_requires_reason"
    }


def test_diff_scope_classification_maps_paths_to_review_intensity() -> None:
    docs_only = diff_scope_classification(["plans/example.md", "docs/WORKFLOW.md"])
    assert docs_only.accepted
    assert docs_only.data["scopes"] == ["docs", "plans"]
    assert docs_only.data["review_intensity"] == "lightweight"

    nested_docs = diff_scope_classification(["docs/research/example.md", "tests/fixtures/example.txt"])
    assert nested_docs.accepted
    assert nested_docs.data["scopes"] == ["docs", "tests"]

    strict = diff_scope_classification(["AGENTS.md", "scripts/verify.sh", "templates/automation-base/AGENTS.md"])
    assert strict.accepted
    assert strict.data["scopes"] == ["guidance", "scripts", "templates"]
    assert strict.data["review_intensity"] == "strict"

    unknown = diff_scope_classification(["mystery.file"])
    assert unknown.accepted
    assert unknown.reason == "diff_scope_ready"
    assert unknown.data["unknown_paths"] is True


def test_benchmark_wrapper_plan_requires_contract_evidence_without_install_claims() -> None:
    valid = {
        "command": "python -m scripts.benchmark_wrapper fixture",
        "output_json": "plans/benchmark.json",
        "output_markdown": "plans/benchmark.md",
        "sample_count": 3,
        "environment": "local fixture",
        "external_tool_optional": True,
        "evidence_record": valid_benchmark_record(),
    }
    assert benchmark_wrapper_plan(valid).accepted
    assert benchmark_wrapper_plan({**valid, "requires_external_tool": True, "external_tool_optional": False}).reason == (
        "benchmark_external_tool_must_be_optional"
    )
    assert benchmark_wrapper_plan({**valid, "claims_readiness_from_single_run": True}).reason == (
        "single_benchmark_run_cannot_claim_readiness"
    )
    assert benchmark_wrapper_plan({**valid, "output_json": "plans/benchmark.txt"}).reason == (
        "benchmark_json_output_required"
    )
    degraded = {
        **valid,
        "evidence_record": {
            **valid_benchmark_record(),
            "threshold_source": "project_baseline",
            "baseline_evidence": "captured by tests",
            "threshold_rationale": "fixture threshold",
            "measured": 150,
        },
    }
    assert benchmark_wrapper_plan(degraded).reason == "benchmark_wrapper_degraded_evidence"


def test_benchmark_capture_record_separates_unavailable_from_evidence_pass() -> None:
    unavailable = {
        "schema_version": "ai_auto_benchmark_v1",
        "name": "verify",
        "command": "./scripts/verify.sh",
        "benchmark_run_status": "unavailable",
        "verdict": "unavailable",
        "environment": {"git_commit": "abc"},
        "tool": {"name": "hyperfine", "available": False, "version": None},
        "sample_count": 0,
        "claims_readiness": False,
        "replaces_verify": False,
        "replaces_review_gate": False,
    }
    result = benchmark_capture_record(unavailable)
    assert result.accepted
    assert result.reason == "benchmark_capture_unavailable_recorded"
    assert result.data["readiness_supported"] is False
    assert benchmark_capture_record({**unavailable, "claims_readiness": True}).reason == (
        "benchmark_capture_cannot_claim_readiness"
    )
    assert benchmark_capture_record({**unavailable, "claims_readiness": "false"}).reason == (
        "benchmark_capture_boolean_fields_required"
    )
    assert benchmark_capture_record({**unavailable, "tool": {"name": "hyperfine", "available": True}}).reason == (
        "unavailable_capture_requires_missing_tool"
    )
    assert benchmark_capture_record({**unavailable, "tool": {"name": "hyperfine", "available": "false"}}).reason == (
        "benchmark_capture_boolean_fields_required"
    )


def test_benchmark_capture_record_accepts_observed_measurement_without_readiness() -> None:
    observed = {
        "schema_version": "ai_auto_benchmark_v1",
        "name": "verify",
        "command": "./scripts/verify.sh",
        "benchmark_run_status": "pass",
        "verdict": "observed",
        "environment": {"git_commit": "abc"},
        "tool": {"name": "hyperfine", "available": True, "version": "hyperfine 1.0"},
        "sample_count": 3,
        "measured_ms": 123.0,
        "claims_readiness": False,
        "replaces_verify": False,
        "replaces_review_gate": False,
    }
    result = benchmark_capture_record(observed)
    assert result.accepted
    assert result.reason == "benchmark_capture_pass"
    assert benchmark_capture_record({**observed, "sample_count": 0}).reason == (
        "invalid_benchmark_capture_measurement"
    )


def test_process_cleanup_evidence_rejects_lingering_or_unreaped_timeout() -> None:
    valid = {
        "command": "timeout 1 fake-reviewer",
        "timeout_seconds": 180,
        "kill_after_seconds": 5,
        "exit_status": 124,
        "cleanup_checked": True,
        "timed_out": True,
        "forced_kill_or_reaped": True,
    }
    assert process_cleanup_evidence(valid).accepted
    assert process_cleanup_evidence({**valid, "lingering_processes": ["fake-reviewer"]}).reason == (
        "lingering_processes_detected"
    )
    assert process_cleanup_evidence({**valid, "kill_after_seconds": 0}).reason == "invalid_process_timeout"
    assert process_cleanup_evidence({**valid, "forced_kill_or_reaped": False}).reason == "timed_out_process_not_reaped"
