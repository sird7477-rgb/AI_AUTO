from scripts.reflection_contracts import (
    field_validation_state,
    merge_drafts,
    observability_trace,
    preserve_core_verdict,
    portable_instruction_surface,
    resource_execution_mode,
    review_integrity_report,
    route_qc,
    sanitize_payload,
    validate_backfill_request,
    validate_promotion_request,
    validate_ui_reference,
    validate_transition,
    visual_qc_result,
)


def test_work_item_transition_requires_evidence() -> None:
    assert validate_transition("execution", "editing", "code_ready", {"verify": True}).accepted
    result = validate_transition("execution", "editing", "code_ready", {})
    assert not result.accepted
    assert result.reason == "missing_verify_evidence"


def test_reflection_cannot_own_field_transition() -> None:
    result = validate_transition("reflection", "pending_field_validation", "field_verified")
    assert not result.accepted
    assert result.reason == "reflection_may_mirror_but_not_own_work_transition"
    assert validate_transition("reflection", "editing", "code_ready", {"verify": True}).reason == (
        "reflection_may_mirror_but_not_own_work_transition"
    )
    assert validate_transition("reflection", "review_ready", "committed").reason == (
        "reflection_may_mirror_but_not_own_work_transition"
    )


def test_state_transition_rejects_unknown_and_cross_owner() -> None:
    assert validate_transition("reflection", "draft", "magic_done").reason == "unknown_state"
    assert validate_transition("reflection", "draft", "code_ready").reason == "cross_owned_transition"


def test_privacy_blocks_raw_logs_private_paths_credentials_and_screenshots() -> None:
    payloads = [
        r"Traceback in C:\Users\Private\project\app.py",
        "token=abc123",
        "screenshot=/tmp/private-screen.png",
        "system prompt: keep this raw prompt",
    ]
    for payload in payloads:
        result = sanitize_payload(payload)
        assert not result["accepted"]
        assert result["summary"] == "redacted private/sensitive content"
        assert payload not in result.values()


def test_review_integrity_does_not_claim_unanimity_for_degraded_fallback() -> None:
    report = review_integrity_report(
        [
            {"name": "Claude", "status": "skipped", "coverage": "independent", "verdict": "skipped"},
            {
                "name": "Gemini",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            },
            {"name": "Codex", "status": "available", "coverage": "fallback", "verdict": "approve_with_notes"},
        ]
    )
    assert report["decision"] == "proceed_degraded"
    assert report["unanimous"] is False
    assert report["unavailable"] == ["Claude"]
    assert report["degraded"] == ["Codex"]


def test_review_integrity_accepts_two_independent_available_approvals() -> None:
    report = review_integrity_report(
        [
            {
                "name": "Claude",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            },
            {
                "name": "Gemini",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve_with_notes",
                "context_completeness": 1.0,
            },
        ]
    )
    assert report["decision"] == "proceed"
    assert report["unanimous"] is True
    assert report["independent_approvals"] == ["Claude", "Gemini"]


def test_review_integrity_blocks_empty_reviewer_set() -> None:
    report = review_integrity_report([])
    assert report["decision"] == "blocked"
    assert report["unanimous"] is False
    assert report["independent_approvals"] == []
    assert report["reason"] == "missing_reviewers"


def test_review_integrity_blocks_request_changes_and_block_verdicts() -> None:
    request_changes = review_integrity_report(
        [
            {
                "name": "Gemini",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            },
            {"name": "Codex", "status": "available", "coverage": "fallback", "verdict": "request_changes"},
        ]
    )
    assert request_changes["decision"] == "blocked"
    assert request_changes["unanimous"] is False
    assert request_changes["blocking"] == ["Codex"]

    block = review_integrity_report(
        [
            {"name": "Claude", "status": "available", "coverage": "independent", "verdict": "block"},
            {
                "name": "Gemini",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            },
        ]
    )
    assert block["decision"] == "blocked"
    assert block["blocking"] == ["Claude"]


def test_review_integrity_requires_schema_and_enough_independent_context() -> None:
    malformed = review_integrity_report(
        [
            {"status": "available", "coverage": "independent", "verdict": "approve"},
            {"name": "Mystery", "status": "available", "coverage": "independent", "verdict": "approve_later"},
        ]
    )
    assert malformed["decision"] == "blocked"
    assert malformed["reason"] == "malformed_reviewer_record"
    assert malformed["malformed"][0]["missing"] == ["name"]
    assert malformed["malformed"][1]["reason"] == "invalid_reviewer_verdict"

    duplicated = review_integrity_report(
        [
            {
                "name": "Claude",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            },
            {
                "name": "Claude",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            },
        ]
    )
    assert duplicated["decision"] == "blocked"
    assert duplicated["malformed"][0]["reason"] == "duplicate_reviewer_name"

    one_approval = review_integrity_report(
        [
            {
                "name": "Claude",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            }
        ]
    )
    assert one_approval["decision"] == "proceed_degraded"
    assert one_approval["unanimous"] is False
    assert one_approval["insufficient_independent"] is True

    low_context = review_integrity_report(
        [
            {
                "name": "Claude",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 0.5,
            },
            {
                "name": "Gemini",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            },
        ]
    )
    assert low_context["decision"] == "proceed_degraded"
    assert low_context["degraded"] == ["Claude"]
    assert low_context["degraded_reasons"] == {"Claude": "context_completeness_below_threshold"}

    failed_reviewer = review_integrity_report(
        [
            {"name": "Claude", "status": "failed", "coverage": "independent", "verdict": "failed"},
            {
                "name": "Gemini",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            },
        ]
    )
    assert failed_reviewer["decision"] == "proceed_degraded"
    assert failed_reviewer["unavailable"] == ["Claude"]

    missing_context = review_integrity_report(
        [
            {"name": "Claude", "status": "available", "coverage": "independent", "verdict": "approve"},
            {"name": "Gemini", "status": "available", "coverage": "independent", "verdict": "approve"},
        ]
    )
    assert missing_context["decision"] == "blocked"
    assert missing_context["reason"] == "no_usable_approvals"
    assert missing_context["degraded"] == ["Claude", "Gemini"]
    assert missing_context["degraded_reasons"] == {
        "Claude": "missing_context_completeness",
        "Gemini": "missing_context_completeness",
    }

    invalid_context = review_integrity_report(
        [
            {
                "name": "Claude",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": True,
            },
            {
                "name": "Gemini",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            },
        ]
    )
    assert invalid_context["decision"] == "proceed_degraded"
    assert invalid_context["degraded_reasons"] == {"Claude": "invalid_context_completeness"}

    no_usable_approvals = review_integrity_report(
        [
            {"name": "Claude", "status": "missing", "coverage": "independent", "verdict": "missing"},
            {"name": "Gemini", "status": "failed", "coverage": "independent", "verdict": "failed"},
        ]
    )
    assert no_usable_approvals["decision"] == "blocked"
    assert no_usable_approvals["reason"] == "no_usable_approvals"

    skipped_block = review_integrity_report(
        [
            {"name": "Claude", "status": "skipped", "coverage": "independent", "verdict": "block"},
            {
                "name": "Gemini",
                "status": "available",
                "coverage": "independent",
                "verdict": "approve",
                "context_completeness": 1.0,
            },
        ]
    )
    assert skipped_block["decision"] == "proceed_degraded"
    assert skipped_block["blocking"] == []


def test_sidecar_failure_preserves_core_verdict() -> None:
    result = preserve_core_verdict(
        "proceed",
        [
            {"name": "knowledge-draft", "status": "failed"},
            {"name": "trace", "status": "ok"},
        ],
    )
    assert result["accepted"]
    assert result["core_verdict"] == "proceed"
    assert result["warnings"] == [{"name": "knowledge-draft", "status": "failed"}]


def test_sidecar_cannot_claim_completion_or_override_core_verdict() -> None:
    result = preserve_core_verdict(
        "revise",
        [
            {"name": "reflection-draft", "status": "ok", "claims_completion": True},
            {"name": "knowledge-draft", "status": "ok", "overrides_core_verdict": True},
        ],
    )
    assert not result["accepted"]
    assert result["core_verdict"] == "revise"
    assert [item["name"] for item in result["authority_violations"]] == ["reflection-draft", "knowledge-draft"]

    blocked = preserve_core_verdict("blocked", [{"name": "knowledge-draft", "status": "ok"}])
    assert blocked["accepted"]
    assert blocked["core_verdict"] == "blocked"


def test_duplicate_draft_keys_are_idempotent() -> None:
    result = merge_drafts(
        [
            {"repeat_key": "review-gate:degraded", "summary": "first", "evidence_count": "1"},
            {"repeat_key": "review-gate:degraded", "summary": "second", "evidence_count": "2"},
            {"repeat_key": "privacy:path", "summary": "redacted", "evidence_count": "1"},
        ]
    )
    assert len(result) == 2
    assert result[0]["repeat_key"] == "review-gate:degraded"
    assert result[0]["summary"] == "first"
    assert result[0]["evidence_count"] == "3"


def test_qc_routing_is_conditional_by_task_risk() -> None:
    assert route_qc({"commit_candidate": True}) == ["minimal", "code", "review"]
    assert route_qc({"ui_change": True, "field_required": True, "repeat_issue": True}) == [
        "minimal",
        "code",
        "ux_ui",
        "field",
        "regression",
    ]


def test_field_validation_requires_fresh_project_evidence() -> None:
    assert field_validation_state({"checklist": True, "post_check": True}).accepted
    assert field_validation_state({"post_check": True}).reason == "missing_field_checklist"
    assert field_validation_state({"checklist": True, "post_check": True, "stale": True}).reason == "pending_field_validation"
    assert (
        field_validation_state({"checklist": True, "post_check": True, "requires_operator": True}).reason
        == "missing_operator_confirmation"
    )


def test_ui_reference_requires_principles_traceability_and_non_copy_boundary() -> None:
    valid = {
        "source": "redacted screenshot note",
        "extracted_principles": ["dense operational table", "status-first actions"],
        "rejected_elements": ["brand colors", "exact layout"],
        "mapped_artifacts": ["docs/UI_PROFILE.md", "ui-spec.md", "screenshot evidence"],
    }
    assert validate_ui_reference(valid).accepted
    assert validate_ui_reference({**valid, "copy_visual_surface": True}).reason == "reference_copy_forbidden"
    assert validate_ui_reference({**valid, "raw_sensitive_asset": True}).reason == "raw_sensitive_asset_forbidden"
    assert validate_ui_reference({**valid, "extracted_principles": []}).reason == "missing_extracted_principles"


def test_visual_qc_separates_functional_and_taste_pass() -> None:
    assert visual_qc_result(
        {
            "screenshot": "viewport.png",
            "console_checked": True,
            "functional_pass": True,
            "taste_pass": True,
            "overflow": False,
        }
    ).accepted
    assert visual_qc_result({"console_checked": True}).reason == "missing_screenshot"
    assert visual_qc_result({"screenshot": "x.png", "console_checked": True, "functional_pass": True, "taste_pass": False}).reason == "needs_visual_revision"


def test_resource_execution_mode_degrades_before_contention() -> None:
    assert resource_execution_mode({}) == {
        "mode": "full",
        "sidecar": "allowed",
        "subagents": 2,
        "obsidian_push": "lock-required",
    }
    assert resource_execution_mode({"busy": True})["sidecar"] == "essential-only"
    assert resource_execution_mode({"constrained": True}) == {
        "mode": "minimal",
        "sidecar": "defer",
        "subagents": 0,
        "obsidian_push": "blocked",
    }
    assert resource_execution_mode({"exclusive_lock_missing": True}) == {
        "mode": "manual-only",
        "sidecar": "defer",
        "subagents": 0,
        "obsidian_push": "blocked",
    }


def test_backfill_requires_explicit_projects_and_dry_run() -> None:
    valid = {"explicit_projects": ["ai-lab"], "dry_run": True}
    assert validate_backfill_request(valid).accepted
    assert validate_backfill_request({"dry_run": True}).reason == "missing_explicit_projects"
    assert validate_backfill_request({"explicit_projects": ["ai-lab"]}).reason == "backfill_requires_dry_run"
    assert validate_backfill_request({**valid, "vault_push": True}).reason == "backfill_must_not_push_to_vault"
    assert validate_backfill_request({**valid, "infer_historical_status": True}).reason == "historical_status_inference_forbidden"
    assert validate_backfill_request({**valid, "copy_raw_omx": True}).reason == "raw_omx_copy_forbidden"


def test_promotion_requires_repo_edit_proposal_verify_and_review_gate() -> None:
    valid = {
        "source": "reviewed_note",
        "reviewed": True,
        "repo_edit_proposal": True,
        "verify": True,
        "review_gate": True,
        "review_integrity": {
            "decision": "proceed",
            "unanimous": True,
            "independent_approvals": ["Claude", "Gemini"],
            "unavailable": [],
            "degraded": [],
            "blocking": [],
        },
    }
    assert validate_promotion_request(valid).accepted
    assert validate_promotion_request({**valid, "source": "raw_obsidian"}).reason == "unsupported_promotion_source"
    assert validate_promotion_request({**valid, "direct_guidance_write": True}).reason == "direct_promotion_forbidden"
    assert validate_promotion_request({**valid, "direct_obsidian_to_runtime": True}).reason == "direct_promotion_forbidden"
    assert validate_promotion_request({**valid, "reviewed": False}).reason == "missing_review"
    assert validate_promotion_request({**valid, "repo_edit_proposal": False}).reason == "missing_repo_edit_proposal"
    assert validate_promotion_request({**valid, "verify": False}).reason == "missing_verify_gate"
    assert validate_promotion_request({**valid, "review_gate": False}).reason == "missing_review_gate"
    assert validate_promotion_request({key: value for key, value in valid.items() if key != "review_integrity"}).reason == (
        "missing_review_integrity"
    )
    assert validate_promotion_request({**valid, "review_integrity": {"decision": "blocked"}}).reason == (
        "review_integrity_blocked"
    )
    degraded_integrity = {
        "decision": "proceed_degraded",
        "independent_approvals": ["Gemini"],
        "unavailable": ["Claude"],
        "degraded": [],
        "blocking": [],
    }
    assert validate_promotion_request({**valid, "review_integrity": degraded_integrity}).reason == (
        "degraded_review_requires_acknowledgement"
    )
    assert validate_promotion_request(
        {**valid, "review_integrity": degraded_integrity, "degraded_review_acknowledged": True}
    ).accepted
    assert validate_promotion_request({**valid, "review_integrity": {"decision": "proceed", "unanimous": True}}).reason == (
        "review_integrity_not_ready"
    )
    assert validate_promotion_request(
        {
            **valid,
            "review_integrity": {
                "decision": "proceed",
                "unanimous": True,
                "independent_approvals": ["Claude", "Gemini"],
                "degraded": ["Codex"],
            },
        }
    ).reason == "review_integrity_not_ready"
    assert validate_promotion_request(
        {**valid, "review_integrity": {"decision": "proceed_degraded"}, "degraded_review_acknowledged": True}
    ).reason == "review_integrity_not_ready"


def test_observability_trace_is_diagnostic_without_raw_transcript() -> None:
    valid = {
        "trigger": "review-gate",
        "artifact": ".omx/review-results/review-verdict.md",
        "skipped_reason": "none",
        "next_action": "continue",
    }
    trace = observability_trace(valid)
    assert trace["accepted"]
    assert "raw_transcript" not in trace
    assert observability_trace({**valid, "raw_transcript": "full chat"})["reason"] == "raw_observability_payload_forbidden"
    assert observability_trace({**valid, "raw_prompt": "developer prompt: secret"})["reason"] == "raw_observability_payload_forbidden"
    assert observability_trace({**valid, "artifact": r"C:\Users\Private\trace.log"})["reason"] == "observability_trace_privacy_blocked"
    assert observability_trace({**valid, "next_action": ""})["reason"] == "missing_next_action"


def test_portable_instruction_surface_keeps_provider_specifics_isolated() -> None:
    valid = {"kind": "AGENTS.md", "fallback": "nearest App-safe surface"}
    assert portable_instruction_surface(valid).accepted
    assert portable_instruction_surface({"kind": "prompt", "fallback": "manual"}).reason == "unsupported_instruction_surface"
    assert portable_instruction_surface({**valid, "provider_hard_dependency": True}).reason == "provider_specific_dependency_forbidden"
    assert portable_instruction_surface({**valid, "stale_model_override": True}).reason == "stale_model_override_forbidden"
    assert portable_instruction_surface({**valid, "provider_specific": True}).reason == "provider_specifics_must_be_isolated"
    assert portable_instruction_surface({"kind": "helper", "provider_specific": True, "fallback": "codex fallback"}).accepted
    assert portable_instruction_surface({"kind": "hook"}).reason == "missing_portable_fallback"
