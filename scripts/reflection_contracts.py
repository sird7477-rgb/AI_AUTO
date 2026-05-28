"""Pure contract helpers for the AI_AUTO Reflection Loop plan.

These helpers intentionally do not perform file writes, command execution, or
Obsidian sync. They lock the Phase 1 contract shape before runtime hooks exist.
"""

from __future__ import annotations

import re
from collections import OrderedDict
from dataclasses import dataclass
from typing import Any


WORK_TRANSITIONS = {
    ("editing", "code_ready"),
    ("code_ready", "review_ready"),
    ("review_ready", "committed"),
    ("committed", "pending_field_validation"),
    ("pending_field_validation", "field_verified"),
    ("field_verified", "done"),
}

KNOWLEDGE_TRANSITIONS = {
    ("draft", "sanitized"),
    ("sanitized", "triaged"),
    ("triaged", "local_private"),
    ("local_private", "pushed_to_obsidian"),
    ("pushed_to_obsidian", "promotion_candidate"),
    ("promotion_candidate", "accepted_change"),
    ("promotion_candidate", "rejected"),
    ("promotion_candidate", "deferred"),
}

WORK_STATES = {state for transition in WORK_TRANSITIONS for state in transition}
KNOWLEDGE_STATES = {state for transition in KNOWLEDGE_TRANSITIONS for state in transition}

REFLECTION_FORBIDDEN_WORK_TRANSITIONS = {
    ("pending_field_validation", "field_verified"),
    ("field_verified", "done"),
}

PRIVATE_PATTERN = re.compile(
    r"("
    r"[A-Za-z]:\\[^\s]+"
    r"|/(home|Users|root|mnt)/[^\s]+"
    r"|\b(password|passwd|pwd|token|secret|authorization|api[_-]?key|client[_-]?secret)\s*[:=]\s*\S+"
    r"|bearer\s+\S+"
    r"|screenshot\s*[:=]\s*\S+"
    r"|\b(system|developer|user)\s+prompt\s*:"
    r")",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class ContractResult:
    accepted: bool
    reason: str


def validate_transition(owner: str, from_state: str, to_state: str, evidence: dict[str, Any] | None = None) -> ContractResult:
    """Validate Reflection Loop work/knowledge state ownership."""

    evidence = evidence or {}
    transition = (from_state, to_state)
    if from_state not in WORK_STATES | KNOWLEDGE_STATES or to_state not in WORK_STATES | KNOWLEDGE_STATES:
        return ContractResult(False, "unknown_state")

    if from_state in WORK_STATES and to_state in KNOWLEDGE_STATES:
        return ContractResult(False, "cross_owned_transition")
    if from_state in KNOWLEDGE_STATES and to_state in WORK_STATES:
        return ContractResult(False, "cross_owned_transition")

    if owner == "reflection" and transition in REFLECTION_FORBIDDEN_WORK_TRANSITIONS:
        return ContractResult(False, "reflection_may_mirror_but_not_own_work_transition")

    if transition in WORK_TRANSITIONS:
        if transition == ("editing", "code_ready") and not evidence.get("verify"):
            return ContractResult(False, "missing_verify_evidence")
        return ContractResult(True, "accepted_work_transition")

    if transition in KNOWLEDGE_TRANSITIONS:
        return ContractResult(True, "accepted_knowledge_transition")

    return ContractResult(False, "transition_not_allowed")


def sanitize_payload(payload: str) -> dict[str, Any]:
    """Return a persistence-safe privacy result for draft/report/index outputs."""

    findings = PRIVATE_PATTERN.findall(payload or "")
    if not findings:
        return {"accepted": True, "summary": payload, "skip_count": 0, "reason": "clean"}
    return {
        "accepted": False,
        "summary": "redacted private/sensitive content",
        "skip_count": len(findings),
        "reason": "privacy_blocked",
    }


def review_integrity_report(reviewers: list[dict[str, str]]) -> dict[str, Any]:
    """Summarize reviewer coverage without overstating degraded/fallback results."""

    if not reviewers:
        return {
            "decision": "blocked",
            "unanimous": False,
            "independent_approvals": [],
            "unavailable": [],
            "degraded": [],
            "reason": "missing_reviewers",
        }

    unavailable = [r["name"] for r in reviewers if r.get("status") in {"skipped", "missing"}]
    degraded = [r["name"] for r in reviewers if r.get("coverage") in {"degraded", "fallback"}]
    blocking = [
        r["name"]
        for r in reviewers
        if r.get("verdict") in {"request_changes", "block", "blocked", "revise", "review_manually"}
    ]
    independent_approvals = [
        r["name"]
        for r in reviewers
        if r.get("verdict", "").startswith("approve")
        and r.get("status") == "available"
        and r.get("coverage") == "independent"
    ]
    if blocking:
        return {
            "decision": "blocked",
            "unanimous": False,
            "independent_approvals": independent_approvals,
            "unavailable": unavailable,
            "degraded": degraded,
            "blocking": blocking,
        }

    unanimous = not unavailable and not degraded and len(independent_approvals) == len(reviewers)
    decision = "proceed" if unanimous else "proceed_degraded"
    return {
        "decision": decision,
        "unanimous": unanimous,
        "independent_approvals": independent_approvals,
        "unavailable": unavailable,
        "degraded": degraded,
        "blocking": blocking,
    }


def preserve_core_verdict(core_verdict: str, sidecar_results: list[dict[str, str]]) -> dict[str, Any]:
    warnings = [item for item in sidecar_results if item.get("status") == "failed"]
    return {"core_verdict": core_verdict, "warnings": warnings}


def merge_drafts(candidates: list[dict[str, str]]) -> list[dict[str, str]]:
    """Deterministically keep one draft per repeat_key."""

    merged: OrderedDict[str, dict[str, str]] = OrderedDict()
    for item in candidates:
        key = item["repeat_key"]
        if key not in merged:
            merged[key] = dict(item)
            continue
        existing = merged[key]
        existing["summary"] = existing.get("summary") or item.get("summary", "")
        existing["evidence_count"] = str(int(existing.get("evidence_count", "1")) + int(item.get("evidence_count", "1")))
    return list(merged.values())


def route_qc(task: dict[str, Any]) -> list[str]:
    layers = ["minimal", "code"]
    if task.get("commit_candidate"):
        layers.append("review")
    if task.get("domain_logic"):
        layers.append("domain")
    if task.get("ui_change"):
        layers.append("ux_ui")
    if task.get("field_required"):
        layers.append("field")
    if task.get("bugfix") or task.get("repeat_issue") or task.get("critical"):
        layers.append("regression")
    return layers


def field_validation_state(evidence: dict[str, Any]) -> ContractResult:
    if not evidence.get("checklist"):
        return ContractResult(False, "missing_field_checklist")
    if evidence.get("stale") or evidence.get("degraded"):
        return ContractResult(False, "pending_field_validation")
    if evidence.get("requires_operator") and not evidence.get("operator_confirmation"):
        return ContractResult(False, "missing_operator_confirmation")
    if not evidence.get("post_check"):
        return ContractResult(False, "missing_post_check")
    return ContractResult(True, "field_verified")


def validate_ui_reference(reference: dict[str, Any]) -> ContractResult:
    if not reference.get("source"):
        return ContractResult(False, "missing_reference_source")
    if not reference.get("extracted_principles"):
        return ContractResult(False, "missing_extracted_principles")
    if "rejected_elements" not in reference:
        return ContractResult(False, "missing_rejected_elements")
    if reference.get("raw_sensitive_asset"):
        return ContractResult(False, "raw_sensitive_asset_forbidden")
    if reference.get("copy_visual_surface"):
        return ContractResult(False, "reference_copy_forbidden")
    if not reference.get("mapped_artifacts"):
        return ContractResult(False, "missing_traceability")
    return ContractResult(True, "reference_contract_ready")


def visual_qc_result(evidence: dict[str, Any]) -> ContractResult:
    if not evidence.get("screenshot"):
        return ContractResult(False, "missing_screenshot")
    if not evidence.get("console_checked"):
        return ContractResult(False, "missing_console_status")
    if evidence.get("overflow"):
        return ContractResult(False, "needs_visual_revision")
    if not evidence.get("functional_pass"):
        return ContractResult(False, "functional_failed")
    if not evidence.get("taste_pass"):
        return ContractResult(False, "needs_visual_revision")
    return ContractResult(True, "ux_ui_checked")


def resource_execution_mode(profile: dict[str, Any]) -> dict[str, Any]:
    if profile.get("exclusive_lock_missing"):
        return {"mode": "manual-only", "sidecar": "defer", "subagents": 0, "obsidian_push": "blocked"}
    if profile.get("constrained"):
        return {"mode": "minimal", "sidecar": "defer", "subagents": 0, "obsidian_push": "blocked"}
    if profile.get("busy"):
        return {"mode": "standard", "sidecar": "essential-only", "subagents": 1, "obsidian_push": "defer"}
    return {"mode": "full", "sidecar": "allowed", "subagents": 2, "obsidian_push": "lock-required"}


def validate_backfill_request(request: dict[str, Any]) -> ContractResult:
    if not request.get("explicit_projects"):
        return ContractResult(False, "missing_explicit_projects")
    if not request.get("dry_run"):
        return ContractResult(False, "backfill_requires_dry_run")
    if request.get("vault_push"):
        return ContractResult(False, "backfill_must_not_push_to_vault")
    if request.get("infer_historical_status"):
        return ContractResult(False, "historical_status_inference_forbidden")
    if request.get("copy_raw_omx"):
        return ContractResult(False, "raw_omx_copy_forbidden")
    return ContractResult(True, "backfill_request_ready")


def validate_promotion_request(request: dict[str, Any]) -> ContractResult:
    allowed_sources = {"local_draft", "feedback", "reviewed_note"}
    if request.get("source") not in allowed_sources:
        return ContractResult(False, "unsupported_promotion_source")
    if request.get("direct_guidance_write") or request.get("direct_obsidian_to_runtime"):
        return ContractResult(False, "direct_promotion_forbidden")
    if not request.get("reviewed"):
        return ContractResult(False, "missing_review")
    if not request.get("repo_edit_proposal"):
        return ContractResult(False, "missing_repo_edit_proposal")
    if not request.get("verify"):
        return ContractResult(False, "missing_verify_gate")
    if not request.get("review_gate"):
        return ContractResult(False, "missing_review_gate")
    return ContractResult(True, "promotion_request_ready")


def observability_trace(event: dict[str, Any]) -> dict[str, Any]:
    forbidden_fields = {"raw_transcript", "raw_prompt", "private_path"}
    if forbidden_fields & event.keys():
        return {"accepted": False, "reason": "raw_observability_payload_forbidden"}

    required_fields = ("trigger", "artifact", "skipped_reason", "next_action")
    missing = [field for field in required_fields if not event.get(field)]
    if missing:
        return {"accepted": False, "reason": f"missing_{missing[0]}"}

    payload = "\n".join(str(event[field]) for field in required_fields)
    privacy = sanitize_payload(payload)
    if not privacy["accepted"]:
        return {"accepted": False, "reason": "observability_trace_privacy_blocked"}

    return {
        "accepted": True,
        "trigger": event["trigger"],
        "artifact": event["artifact"],
        "skipped_reason": event["skipped_reason"],
        "next_action": event["next_action"],
    }


def portable_instruction_surface(surface: dict[str, Any]) -> ContractResult:
    allowed_surfaces = {"AGENTS.md", "SKILL.md", "helper", "hook"}
    if surface.get("kind") not in allowed_surfaces:
        return ContractResult(False, "unsupported_instruction_surface")
    if surface.get("provider_hard_dependency"):
        return ContractResult(False, "provider_specific_dependency_forbidden")
    if surface.get("stale_model_override"):
        return ContractResult(False, "stale_model_override_forbidden")
    if surface.get("provider_specific") and surface.get("kind") not in {"helper", "hook"}:
        return ContractResult(False, "provider_specifics_must_be_isolated")
    if not surface.get("fallback"):
        return ContractResult(False, "missing_portable_fallback")
    return ContractResult(True, "portable_instruction_surface_ready")
