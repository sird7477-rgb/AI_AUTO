from scripts.self_demo_contracts import (
    artifact_delta_check,
    artifact_sync,
    benchmark_capture_record,
    benchmark_wrapper_plan,
    benchmark_evidence,
    browser_qa_evidence_policy,
    completion_acceptance_scope,
    completion_authority,
    completion_pack_routing_policy,
    diff_scope_classification,
    guidance_minimality_boundary,
    obsidian_autopush_policy,
    persona_lens_policy,
    phase_scope_guard_policy,
    product_challenge_policy,
    process_cleanup_evidence,
    registry_scan_boundary,
    review_revision_loop_policy,
    reviewer_eligibility,
    review_context_boundary,
    review_gate_short_summary,
    self_demo_record,
    startup_preflight_boundary,
    status_notice_boundary,
    template_parity_boundary,
    todo_report_reconciliation,
    tool_adoption_status_policy,
    untracked_artifact_review_guard,
    update_visibility_policy,
    vault_write_boundary,
    visual_artifact_policy,
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


def test_completion_acceptance_scope_blocks_safety_gate_as_completion() -> None:
    base = {
        "user_acceptance_criteria": [
            "create strategy candidates",
            "produce backtest results",
            "run fallback loops",
            "obtain AI unanimity",
        ],
        "required_evidence": [
            "strategy_candidates",
            "backtest_results",
            "fallback_loops",
            "ai_unanimity",
        ],
        "claimed_complete": True,
    }

    # Acceptance criteria are mandatory and immutable.
    assert completion_acceptance_scope({**base, "user_acceptance_criteria": []}).reason == "missing_acceptance_criteria"
    assert completion_acceptance_scope({**base, "acceptance_criteria_mutated": True}).reason == "acceptance_scope_mutated"

    # Preserving the scope without claiming completion is allowed.
    not_claimed = completion_acceptance_scope({**base, "claimed_complete": False})
    assert not_claimed.accepted
    assert not_claimed.reason == "completion_not_claimed"

    # A completion claim must define required evidence; an empty requirement set
    # cannot be vacuously satisfied by a deliverable or no-result report.
    for vacuous in (
        {**base, "required_evidence": [], "deliverable_proven": True},
        {**base, "required_evidence": [], "no_result_final_report": True, "safety_gate_triggered": True},
    ):
        result = completion_acceptance_scope(vacuous)
        assert not result.accepted
        assert result.reason == "missing_required_evidence_definition"

    # An intermediate fail-closed safety gate alone cannot satisfy completion.
    gate_only = completion_acceptance_scope({**base, "safety_gate_triggered": True})
    assert not gate_only.accepted
    assert gate_only.reason == "safety_gate_not_completion"

    full_evidence = {
        "strategy_candidates",
        "backtest_results",
        "fallback_loops",
        "ai_unanimity",
    }

    # Even with every required evidence item, completion needs an explicit
    # deliverable or no-result report; evidence alone is not a completion claim.
    bare_claim = completion_acceptance_scope({**base, "evidence_provided": sorted(full_evidence)})
    assert not bare_claim.accepted
    assert bare_claim.reason == "completion_requires_deliverable_or_no_result_report"

    # A no-result final report still has to carry every required evidence item.
    partial_report = completion_acceptance_scope(
        {
            **base,
            "safety_gate_triggered": True,
            "no_result_final_report": True,
            "evidence_provided": ["strategy_candidates", "backtest_results"],
        }
    )
    assert not partial_report.accepted
    assert partial_report.reason == "no_result_report_missing_required_evidence"
    assert partial_report.data["missing"] == ["fallback_loops", "ai_unanimity"]

    # A complete no-result final report is a valid completion after a safety gate.
    full_report = completion_acceptance_scope(
        {
            **base,
            "safety_gate_triggered": True,
            "no_result_final_report": True,
            "evidence_provided": sorted(full_evidence),
        }
    )
    assert full_report.accepted
    assert full_report.reason == "no_result_report_complete"

    # A proven deliverable also has to carry the required evidence.
    deliverable_missing = completion_acceptance_scope(
        {
            **base,
            "deliverable_proven": True,
            "evidence_provided": ["strategy_candidates"],
        }
    )
    assert not deliverable_missing.accepted
    assert deliverable_missing.reason == "deliverable_missing_required_evidence"

    deliverable_complete = completion_acceptance_scope(
        {
            **base,
            "deliverable_proven": True,
            "safety_gate_triggered": True,
            "evidence_provided": sorted(full_evidence),
        }
    )
    assert deliverable_complete.accepted
    assert deliverable_complete.reason == "deliverable_complete"


def test_startup_preflight_boundary_requires_non_blocking_pass_through() -> None:
    valid = {
        "preflight_name": "project update notice",
        "target_timeout_seconds": 0.5,
        "hard_timeout_seconds": 1,
        "failure_mode": "warning_only",
        "passes_through_primary_invocation": True,
    }
    assert startup_preflight_boundary(valid).accepted
    assert startup_preflight_boundary(
        {
            **valid,
            "preflight_name": "obsidian knowledge auto-push",
            "target_timeout_seconds": 2,
            "hard_timeout_seconds": 5,
        }
    ).accepted
    assert startup_preflight_boundary({**valid, "target_timeout_seconds": 4, "hard_timeout_seconds": 5}).reason == (
        "project_update_notice_timeout_too_high"
    )
    assert startup_preflight_boundary(
        {
            **valid,
            "preflight_name": "template update notice",
            "target_timeout_seconds": 4,
            "hard_timeout_seconds": 5,
        }
    ).reason == "project_update_notice_timeout_too_high"
    assert startup_preflight_boundary(
        {
            **valid,
            "preflight_name": "AI_AUTO update notice",
            "target_timeout_seconds": 4,
            "hard_timeout_seconds": 5,
        }
    ).reason == "project_update_notice_timeout_too_high"
    assert startup_preflight_boundary(
        {
            **valid,
            "preflight_name": "obsidian knowledge auto-push",
            "target_timeout_seconds": 3,
            "hard_timeout_seconds": 5,
        }
    ).reason == "knowledge_preflight_timeout_too_high"
    assert startup_preflight_boundary({**valid, "failure_mode": "fail_closed"}).reason == (
        "startup_preflight_must_be_warning_only"
    )
    assert startup_preflight_boundary({**valid, "passes_through_primary_invocation": False}).reason == (
        "startup_preflight_must_pass_through"
    )
    assert startup_preflight_boundary({**valid, "hard_timeout_seconds": 6}).reason == (
        "project_update_notice_timeout_too_high"
    )
    assert startup_preflight_boundary({**valid, "starts_daemon": True}).reason == (
        "startup_preflight_must_not_start_runtime"
    )


def test_vault_write_boundary_requires_existing_guards_and_idempotent_failure() -> None:
    valid = {
        "explicit_vault_config": True,
        "uses_existing_validator": True,
        "preserves_sync_class_guard": True,
        "rejects_symlink_escape": True,
        "rejects_dot_omx_vault": True,
        "idempotent_failure": True,
        "failure_mode": "warning_only",
    }
    assert vault_write_boundary(valid).accepted
    assert vault_write_boundary({**valid, "explicit_vault_config": False}).reason == (
        "vault_boundary_missing_controls"
    )
    assert vault_write_boundary({**valid, "failure_mode": "raises"}).reason == (
        "vault_write_failure_must_be_warning_only"
    )
    assert vault_write_boundary({**valid, "discovers_vault_by_mount_scan": True}).reason == (
        "vault_boundary_must_not_mount_scan"
    )
    assert vault_write_boundary({**valid, "claims_obsidian_authority": True}).reason == (
        "obsidian_authority_forbidden"
    )


def test_review_context_boundary_requires_complete_or_split_untracked_review() -> None:
    valid = {
        "material_untracked_artifacts": True,
        "content_included": False,
        "split_review": True,
        "split_synthesis": True,
        "focused_ai_council": False,
    }
    assert review_context_boundary(valid).accepted
    assert review_context_boundary({**valid, "split_synthesis": False}).reason == "split_review_needs_synthesis"
    assert review_context_boundary(
        {
            "material_untracked_artifacts": True,
            "content_included": False,
            "split_review": False,
            "focused_ai_council": False,
        }
    ).reason == "material_untracked_review_needs_context"
    assert review_context_boundary({**valid, "claims_complete_review": True, "truncated_context": True}).reason == (
        "truncated_context_cannot_claim_complete_review"
    )


def test_registry_scan_boundary_keeps_startup_scans_bounded() -> None:
    valid = {
        "current_repo_scope": True,
        "registry_scope": True,
        "workspace_scan": False,
        "mounted_drive_scan": False,
        "startup_path": True,
    }
    assert registry_scan_boundary(valid).accepted
    assert registry_scan_boundary({**valid, "workspace_scan": True}).reason == (
        "startup_registry_scan_must_not_workspace_crawl"
    )
    assert registry_scan_boundary({**valid, "mounted_drive_scan": True}).reason == (
        "registry_scan_must_not_mount_scan"
    )
    assert registry_scan_boundary({**valid, "current_repo_scope": False, "registry_scope": False}).reason == (
        "registry_scan_needs_bounded_scope"
    )


def test_template_parity_boundary_requires_version_and_patch_notes_for_template_owned_changes() -> None:
    assert template_parity_boundary({"template_owned_change": False}).accepted
    valid = {
        "template_owned_change": True,
        "template_version_updated": True,
        "patch_notes_updated": True,
        "template_sync_check": True,
    }
    assert template_parity_boundary(valid).accepted
    assert template_parity_boundary({**valid, "patch_notes_updated": False}).reason == (
        "template_parity_missing_controls"
    )


def test_status_notice_boundary_stays_display_only_and_does_not_record_feedback() -> None:
    valid = {
        "display_only": True,
        "passes_through_primary_invocation": True,
        "records_feedback": False,
    }
    assert status_notice_boundary(valid).accepted
    assert status_notice_boundary({**valid, "records_feedback": True}).reason == (
        "status_notice_must_not_record_feedback"
    )
    assert status_notice_boundary({**valid, "applies_patch": True}).reason == "status_notice_must_not_apply_changes"
    assert status_notice_boundary({**valid, "passes_through_primary_invocation": False}).reason == (
        "status_notice_must_pass_through"
    )


def test_guidance_minimality_boundary_blocks_broad_rewrites_without_plan() -> None:
    valid = {
        "behavior_exists": True,
        "doc_budget_ok": True,
        "minimal_sections": True,
    }
    assert guidance_minimality_boundary(valid).accepted
    assert guidance_minimality_boundary({**valid, "broad_policy_rewrite": True}).reason == (
        "broad_guidance_rewrite_needs_plan"
    )
    assert guidance_minimality_boundary({**valid, "minimal_sections": False}).reason == (
        "guidance_minimality_missing_controls"
    )


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


def test_todo_report_reconciliation_rejects_unresolved_work() -> None:
    result = todo_report_reconciliation(
        [
            {"id": "done", "status": "complete", "evidence": "./scripts/verify.sh pass"},
            {"id": "operational", "status": "operational_clear", "evidence": "caller, runtime guard, docs, and verification evidence exist"},
            {"id": "contract-done", "status": "complete_contract", "evidence": "contract and runtime caller verified"},
            {"id": "planned", "status": "planned_not_run"},
            {"id": "deferred", "status": "deferred", "reason": "needs approval"},
            {"id": "approval", "status": "approval_needed", "reason": "human approval"},
            {"id": "blocked", "status": "blocked", "reason": "dependency unavailable"},
            {"id": "later", "status": "later_gated", "reason": "separate trigger"},
            {"id": "reference", "status": "reference_only", "reason": "not active work"},
            {"id": "contract", "status": "contract_started"},
        ]
    )
    assert not result.accepted
    assert result.reason == "unresolved_todo_report"
    assert result.data["unresolved"] == ["planned", "deferred", "approval", "blocked", "contract"]
    assert todo_report_reconciliation([{"id": "bad-contract-done", "status": "complete_contract"}]).reason == (
        "invalid_todo_report"
    )
    assert todo_report_reconciliation(
        [{"id": "contract-only", "status": "complete_contract", "evidence": "contract-only helper exists"}]
    ).data["invalid"] == {"contract-only": "complete_mentions_unfinished_operating_surface"}
    assert todo_report_reconciliation(
        [{"id": "pending-runtime", "status": "complete_contract", "evidence": "runtime wiring is pending"}]
    ).data["invalid"] == {"pending-runtime": "complete_mentions_unfinished_operating_surface"}
    assert todo_report_reconciliation(
        [{"id": "contract-cleared", "status": "complete_contract", "evidence": "risk is contract-cleared"}]
    ).data["invalid"] == {"contract-cleared": "complete_mentions_unfinished_operating_surface"}
    assert todo_report_reconciliation(
        [{"id": "future-work", "status": "complete_observe_mode", "evidence": "gate policy is separate future work"}]
    ).data["invalid"] == {"future-work": "complete_mentions_unfinished_operating_surface"}
    assert todo_report_reconciliation(
        [{"id": "safe-note", "status": "complete_contract", "evidence": "optional future polish is not active TODO"}]
    ).accepted
    assert todo_report_reconciliation(
        [{"id": "observe", "status": "complete_observe_mode", "evidence": "observe mode exists; policy is later-gated and not active"}]
    ).accepted
    assert todo_report_reconciliation([{"id": "bad-done", "status": "complete"}]).reason == "invalid_todo_report"
    assert todo_report_reconciliation([{"id": "bad-later", "status": "later_gated"}]).data["invalid"] == {
        "bad-later": "non_active_status_requires_reason"
    }


def test_todo_report_reconciliation_accepts_only_resolved_or_bounded_items() -> None:
    result = todo_report_reconciliation(
        [
            {"id": "done", "status": "complete", "evidence": "./scripts/verify.sh pass"},
            {"id": "operational", "status": "operational_clear", "evidence": "caller, runtime guard, docs, and verification evidence exist"},
            {"id": "later", "status": "later_gated", "reason": "separate trigger"},
            {"id": "reference", "status": "reference_only", "reason": "not active work"},
        ]
    )
    assert result.accepted
    assert result.data["unresolved"] == []


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


def test_persona_lens_policy_promotes_lenses_without_slowing_small_tasks() -> None:
    routine = {
        "task_size": "small",
        "hard_triggers": [],
        "routine_small": True,
        "active_lenses": [],
        "classifier_status": "ok",
    }
    assert persona_lens_policy(routine).reason == "persona_lens_suppressed"
    assert persona_lens_policy({**routine, "classifier_status": "error"}).reason == "persona_classifier_strict_gate"
    assert persona_lens_policy({**routine, "active_lenses": ["security"]}).reason == (
        "routine_small_must_suppress_lenses"
    )
    multi = {
        **routine,
        "task_size": "large",
        "routine_small": False,
        "hard_triggers": ["security", "deployment"],
        "active_lenses": ["security", "deployment", "integrator"],
        "minimum_review_gate": "strict",
    }
    assert persona_lens_policy(multi).accepted
    assert persona_lens_policy({**multi, "active_lenses": ["security", "deployment"]}).reason == (
        "multi_lens_requires_integrator"
    )


def test_obsidian_autopush_policy_is_dry_run_and_approval_bounded() -> None:
    valid = {
        "invoked_from_home_checkout": True,
        "opt_in": True,
        "pending_drafts": ["ai-lab.md", "project-a.md"],
        "explicit_vault_config": True,
        "dry_run_summary": True,
        "uses_knowledge_collect": True,
        "push_requested": False,
        "user_push_approval": False,
    }
    assert obsidian_autopush_policy(valid).accepted
    assert obsidian_autopush_policy({**valid, "invoked_from_home_checkout": False}).reason == (
        "obsidian_autopush_skipped_not_home"
    )
    assert obsidian_autopush_policy({**valid, "push_requested": True}).reason == (
        "obsidian_push_requires_user_approval"
    )
    assert obsidian_autopush_policy({**valid, "dry_run_summary": False}).reason == (
        "obsidian_autopush_requires_dry_run_summary"
    )


def test_obsidian_autopush_shareable_only_lane_skips_per_run_approval() -> None:
    base = {
        "invoked_from_home_checkout": True,
        "opt_in": True,
        "pending_drafts": ["ai-lab.md", "project-a.md"],
        "explicit_vault_config": True,
        "dry_run_summary": True,
        "uses_knowledge_collect": True,
        "push_requested": True,
        "user_push_approval": False,
        "shareable_only_autopush": True,
        "all_pushed_shareable_only": True,
        "secret_scan_passed": True,
    }

    # Shareable-only push is approved-by-classification: no per-run approval needed.
    ready = obsidian_autopush_policy(base)
    assert ready.accepted
    assert ready.data["mode"] == "shareable_only_autopush"

    # Secret preflight failure blocks the shareable-only push.
    assert obsidian_autopush_policy({**base, "secret_scan_passed": False}).reason == (
        "obsidian_autopush_secret_scan_failed"
    )

    # If the batch is not provably shareable-only, the per-run approval is required again.
    assert obsidian_autopush_policy({**base, "all_pushed_shareable_only": False}).reason == (
        "obsidian_push_requires_user_approval"
    )

    # An explicitly approved shareable-only push still passes and is labeled.
    approved = obsidian_autopush_policy({**base, "user_push_approval": True})
    assert approved.accepted
    assert approved.data["mode"] == "shareable_only_autopush"

    # Boundary guards still apply in the shareable-only lane.
    assert obsidian_autopush_policy({**base, "claims_obsidian_authority": True}).reason == (
        "obsidian_autopush_boundary_violation"
    )


def test_update_visibility_policy_is_display_only_fast_and_low_noise() -> None:
    valid = {
        "status": "stale",
        "display_only": True,
        "passes_through_primary_invocation": True,
        "throttle_scope": "session",
        "target_timeout_seconds": 0.5,
        "hard_timeout_seconds": 1,
        "clear_notice": True,
    }
    assert update_visibility_policy(valid).accepted
    assert update_visibility_policy({**valid, "target_timeout_seconds": 0.8}).reason == (
        "project_update_notice_timeout_too_high"
    )
    assert update_visibility_policy({**valid, "throttle_scope": "project_file"}).reason == (
        "update_visibility_throttle_must_be_ephemeral"
    )
    assert update_visibility_policy({**valid, "status": "current", "notice_visible": True}).reason == (
        "current_update_status_should_stay_quiet"
    )


def test_visual_artifact_policy_promotes_source_of_truth_checks() -> None:
    mermaid = {
        "artifact_type": "mermaid",
        "owner_declared": True,
        "paired_spec": False,
        "human_reviewed": False,
        "stale_export": False,
        "ambiguous_source": False,
    }
    assert visual_artifact_policy(mermaid).accepted
    assert visual_artifact_policy({**mermaid, "owner_declared": False}).reason == "visual_owner_required"
    assert visual_artifact_policy({**mermaid, "stale_export": True}).reason == "visual_stale_export"
    assert visual_artifact_policy({**mermaid, "ambiguous_source": True}).reason == (
        "visual_ambiguous_source_of_truth"
    )
    excalidraw = {**mermaid, "artifact_type": "excalidraw", "owner_declared": False}
    assert visual_artifact_policy(excalidraw).reason == "visual_excalidraw_explanatory_only"
    assert visual_artifact_policy({**excalidraw, "paired_spec": True}).reason == "visual_unreviewed_spec"
    assert visual_artifact_policy({**excalidraw, "paired_spec": True, "human_reviewed": True}).accepted


def test_product_challenge_policy_triggers_only_for_broad_work() -> None:
    broad = {
        "request_shape": "broad_strategy",
        "task_size": "large",
        "approved_plan_exists": False,
        "challenge_reason": "new workflow direction needs value and alternative pressure",
        "questions": ["who uses it?", "what is non-goal?", "smallest useful outcome?"],
    }
    assert product_challenge_policy(broad).reason == "product_challenge_required"
    assert product_challenge_policy({**broad, "challenge_reason": ""}).reason == (
        "product_challenge_reason_required"
    )
    assert product_challenge_policy({**broad, "questions": ["1", "2", "3", "4"]}).reason == (
        "product_challenge_max_three_questions"
    )
    small = {**broad, "request_shape": "typo", "task_size": "small", "challenge_reason": ""}
    assert product_challenge_policy(small).reason == "product_challenge_skipped_routine_small"
    assert product_challenge_policy({**broad, "approved_plan_exists": True}).reason == (
        "product_challenge_skipped_approved_plan"
    )


def test_browser_qa_evidence_policy_stays_report_only_and_credential_safe() -> None:
    valid = {
        "target": "http://localhost:5001",
        "report_only": True,
        "attempts_patch": False,
        "cdp_access": True,
        "loopback_bound": True,
        "user_launched_or_isolated": True,
        "approval_recorded": True,
        "exports_cookies_or_tokens": False,
        "visual_verdict": True,
        "verify_evidence": True,
        "review_gate_evidence": True,
    }
    assert browser_qa_evidence_policy(valid).accepted
    assert browser_qa_evidence_policy({**valid, "attempts_patch": True}).reason == "browser_qa_must_be_report_only"
    assert browser_qa_evidence_policy({**valid, "approval_recorded": False}).reason == "browser_qa_cdp_boundary"
    assert browser_qa_evidence_policy({**valid, "exports_cookies_or_tokens": True}).reason == (
        "browser_qa_must_not_export_credentials"
    )
    assert browser_qa_evidence_policy({**valid, "sensitive_evidence": True, "redacted": False}).reason == (
        "browser_qa_redaction_required"
    )
    assert browser_qa_evidence_policy({**valid, "verify_evidence": False}).reason == (
        "visual_verdict_not_completion_authority"
    )


def test_phase_scope_guard_policy_detects_leakage_and_deferrals() -> None:
    valid = {
        "phase": "docs",
        "allowed_files": ["docs/WORKFLOW.md"],
        "changed_files": ["docs/WORKFLOW.md"],
        "deferred_files": [],
    }
    assert phase_scope_guard_policy(valid).accepted
    assert phase_scope_guard_policy({**valid, "changed_files": ["scripts/review-gate.sh"]}).reason == (
        "phase_scope_out_of_phase_edit"
    )
    deferred = {
        **valid,
        "changed_files": ["docs/WORKFLOW.md", "scripts/review-gate.sh"],
        "deferred_files": ["scripts/review-gate.sh"],
    }
    assert phase_scope_guard_policy(deferred).accepted
    assert phase_scope_guard_policy({**valid, "material_finding_missing_deferral": True}).reason == (
        "phase_scope_missing_deferral_record"
    )


def test_review_revision_loop_policy_bounds_review_fix_cycles() -> None:
    valid = {
        "finding_state": "accepted",
        "structured": True,
        "cycle_count": 1,
        "verification_passed": True,
        "changed_diff": True,
    }
    assert review_revision_loop_policy(valid).reason == "review_revision_task_ready"
    assert review_revision_loop_policy({**valid, "finding_state": "rejected"}).reason == "review_revision_skipped"
    assert review_revision_loop_policy({**valid, "structured": False}).reason == "review_revision_skipped"
    assert review_revision_loop_policy({**valid, "second_pass_requested": True, "changed_diff": False}).reason == (
        "review_revision_second_pass_requires_diff"
    )
    assert review_revision_loop_policy({**valid, "cycle_count": 3}).reason == "review_revision_cycle_limit"
    assert review_revision_loop_policy({**valid, "verification_passed": False}).reason == (
        "review_revision_verification_failure"
    )
    assert review_revision_loop_policy({**valid, "unclear_reviewer_output": True}).reason == (
        "review_revision_unclear_review"
    )


def test_tool_adoption_status_policy_is_read_only_and_blocks_silent_promotion() -> None:
    required = {
        "tool": "shellcheck",
        "installed": True,
        "adoption_state": "required_gate",
        "source": "automation-doctor",
        "next_gate": "verify",
    }
    assert tool_adoption_status_policy(required).accepted
    assert tool_adoption_status_policy({**required, "installed": False}).reason == "tool_required_missing"
    assert tool_adoption_status_policy({**required, "installs_tool": True}).reason == "tool_status_must_be_read_only"
    assert tool_adoption_status_policy({**required, "silent_required_promotion": True}).reason == (
        "tool_silent_gate_promotion"
    )
    optional = {**required, "tool": "hyperfine", "installed": False, "adoption_state": "optional"}
    assert tool_adoption_status_policy(optional).reason == "tool_optional_missing_warning"
    reference = {**required, "tool": "ruff", "installed": True, "adoption_state": "reference_only"}
    assert tool_adoption_status_policy(reference).reason == "tool_reference_installed_info"


def test_completion_pack_routing_policy_audits_triggers_without_runtime_lane() -> None:
    packs = {"security", "deployment", "observability", "performance", "data", "ui"}
    security = {"input_shape": "security_review", "available_packs": packs, "adds_runtime_lane": False}
    assert completion_pack_routing_policy(security).data["trigger"] == "security"
    assert completion_pack_routing_policy({**security, "input_shape": "deployment_files"}).data["trigger"] == (
        "deployment"
    )
    assert completion_pack_routing_policy({**security, "input_shape": "persisted_data"}).data["trigger"] == "data"
    assert completion_pack_routing_policy({**security, "input_shape": "ui_work"}).data["trigger"] == "ui"
    assert completion_pack_routing_policy({**security, "input_shape": "docs_generation_lens"}).reason == (
        "completion_pack_reference_lens"
    )
    assert completion_pack_routing_policy({**security, "available_packs": {"security"}}).reason == (
        "completion_pack_inventory_missing"
    )
    assert completion_pack_routing_policy({**security, "adds_runtime_lane": True}).reason == (
        "completion_pack_audit_must_not_add_runtime_lane"
    )
