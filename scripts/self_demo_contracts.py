"""Pure contracts for AI_AUTO self-demo validation.

These helpers do not execute commands, write files, start Docker, call browsers,
or approve small-tool adoption. They only validate the evidence shape needed
before a workflow upgrade can claim representative user-facing coverage.
Self-demo required fields are intentionally string-only; use explicit sentinel
words such as "none" or "not_applicable" when a field has no applicable content.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ContractResult:
    accepted: bool
    reason: str
    data: dict[str, Any]


SELF_DEMO_REQUIRED_FIELDS = {
    "change_class",
    "scenario",
    "command_or_simulation",
    "expected_behavior",
    "evidence",
    "side_effects",
    "cleanup_state",
    "manual_checks",
    "demo_verdict",
}

ALLOWED_CHANGE_CLASSES = {"module", "script", "helper", "template", "guidance", "workflow"}
ALLOWED_DEMO_VERDICTS = {"pass", "fail", "degraded", "not_applicable"}
ALLOWED_BENCHMARK_DIRECTIONS = {"lower_is_better", "higher_is_better"}
ALLOWED_THRESHOLD_SOURCES = {"established_standard", "project_baseline", "temporary_fixture"}
ALLOWED_BENCHMARK_RUN_STATUSES = {"pass", "fail", "error"}
ALLOWED_BENCHMARK_CAPTURE_STATUSES = {"pass", "fail", "error", "unavailable"}
ALLOWED_REVIEW_DECISIONS = {"proceed", "proceed_degraded", "review_manually", "revise", "blocked"}
COMPLETE_TODO_STATUSES = {
    "complete",
    "complete_contract",
    "complete_observe_mode",
    "display_only_complete",
    "installed_required",
    "operational_clear",
}
ACTIVE_TODO_STATUSES = {
    "contract_started",
    "open",
    "planned_not_run",
    "insufficiently_run",
}
ATTENTION_TODO_STATUSES = {
    "deferred",
    "approval_needed",
    "blocked",
}
NON_ACTIVE_TODO_STATUSES = {
    "later_gated",
    "reference_only",
    "excluded",
}
ALLOWED_TODO_STATUSES = (
    COMPLETE_TODO_STATUSES | ACTIVE_TODO_STATUSES | ATTENTION_TODO_STATUSES | NON_ACTIVE_TODO_STATUSES
)
ALLOWED_DIFF_SCOPES = {
    "docs",
    "plans",
    "guidance",
    "scripts",
    "tools",
    "tests",
    "templates",
    "app",
    "docker",
    "github_actions",
    "unknown",
}
REVIEWER_MIN_CONTEXT_COMPLETENESS = 0.9
OBSERVE_BOUNDARY_PATTERN = re.compile(r"\bnot active\b(?!\s+TODO)", re.IGNORECASE)
MISLEADING_COMPLETE_EVIDENCE_PATTERNS = (
    re.compile(r"\bcontract[- ]only\b", re.IGNORECASE),
    re.compile(r"\bcontract[- ](cleared|covered|done|met)\b", re.IGNORECASE),
    re.compile(r"\bcontract coverage only\b", re.IGNORECASE),
    re.compile(r"\b(no|missing)\s+(runtime\s+)?caller\b", re.IGNORECASE),
    re.compile(r"\b(runtime|wiring|caller|call path|operating surface|tooling|gate policy|parity|sync|version)\b.*\b(pending|not implemented|not wired|not synced|missing|absent|unimplemented|mismatch)\b", re.IGNORECASE),
    re.compile(r"\b(pending|missing|absent|unimplemented|not synced|mismatch)\b.*\b(runtime|wiring|caller|call path|operating surface|tooling|gate policy|parity|sync|version)\b", re.IGNORECASE),
    re.compile(r"\b(remains?|remaining)\s+TODO\b", re.IGNORECASE),
    OBSERVE_BOUNDARY_PATTERN,
    re.compile(r"\b(still requires?|still needs?|still active TODO|not currently clear|separate execution|separate\s+(future\s+|later\s+)?work|later explicit execution)\b", re.IGNORECASE),
)


def _non_empty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _reference_like(value: Any) -> bool:
    text = str(value).strip() if value is not None else ""
    lowered = text.lower()
    return lowered.startswith(("http://", "https://", "docs/", "doc:", "standard:", "rfc:", "iso:"))


def _misleading_complete_evidence(status: Any, value: Any) -> bool:
    if not _non_empty(value):
        return False
    for pattern in MISLEADING_COMPLETE_EVIDENCE_PATTERNS:
        if pattern.search(str(value)):
            if status in {"complete_observe_mode", "display_only_complete"} and pattern is OBSERVE_BOUNDARY_PATTERN:
                continue
            return True
    return False


def self_demo_record(record: dict[str, Any]) -> ContractResult:
    missing = sorted(field for field in SELF_DEMO_REQUIRED_FIELDS if field not in record)
    if missing:
        return ContractResult(False, "missing_self_demo_fields", {"missing": missing})
    empty = sorted(field for field in SELF_DEMO_REQUIRED_FIELDS if not _non_empty(record.get(field)))
    if empty:
        return ContractResult(False, "empty_self_demo_fields", {"empty": empty})
    if record["change_class"] not in ALLOWED_CHANGE_CLASSES:
        return ContractResult(False, "invalid_change_class", {"change_class": record["change_class"]})
    if record["demo_verdict"] not in ALLOWED_DEMO_VERDICTS:
        return ContractResult(False, "invalid_demo_verdict", {"demo_verdict": record["demo_verdict"]})
    if record.get("replaces_verify") or record.get("replaces_review_gate"):
        return ContractResult(False, "self_demo_must_not_replace_verification_gates", {})
    if record.get("write_capable") and not record.get("explicit_execution_scope"):
        return ContractResult(False, "write_capable_demo_requires_scope", {})
    if record["demo_verdict"] != "pass":
        return ContractResult(
            False,
            "self_demo_not_ready",
            {"verdict": record["demo_verdict"], "record_valid": True},
        )
    return ContractResult(True, "self_demo_ready", {"verdict": record["demo_verdict"]})


def benchmark_evidence(record: dict[str, Any]) -> ContractResult:
    required = {
        "scenario",
        "functional_demo_verdict",
        "metric",
        "baseline",
        "measured",
        "threshold",
        "unit",
        "direction",
        "environment",
        "sample_count",
        "threshold_source",
    }
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_benchmark_fields", {"missing": missing})
    if record["functional_demo_verdict"] != "pass":
        return ContractResult(False, "benchmark_requires_functional_demo_pass", {})
    if record.get("claims_tool_adoption"):
        return ContractResult(False, "benchmark_does_not_approve_tool_adoption", {})
    if record.get("replaces_verify") or record.get("replaces_review_gate"):
        return ContractResult(False, "benchmark_must_not_replace_verification_gates", {})
    if record["direction"] not in ALLOWED_BENCHMARK_DIRECTIONS:
        return ContractResult(False, "invalid_benchmark_direction", {"direction": record["direction"]})
    try:
        sample_count = int(record["sample_count"])
    except (TypeError, ValueError):
        return ContractResult(False, "invalid_sample_count", {"sample_count": record["sample_count"]})
    if sample_count < 1:
        return ContractResult(False, "benchmark_requires_samples", {"sample_count": record["sample_count"]})
    if record["threshold_source"] not in ALLOWED_THRESHOLD_SOURCES:
        return ContractResult(False, "invalid_threshold_source", {"threshold_source": record["threshold_source"]})
    if record.get("claims_readiness") and record["threshold_source"] == "temporary_fixture":
        return ContractResult(False, "temporary_fixture_cannot_support_readiness", {})
    if record["threshold_source"] == "established_standard":
        if not _non_empty(record.get("threshold_reference")):
            return ContractResult(False, "missing_threshold_reference", {"threshold_source": record["threshold_source"]})
        if not _reference_like(record.get("threshold_reference")):
            return ContractResult(False, "invalid_threshold_reference", {"threshold_reference": record["threshold_reference"]})
    if record["threshold_source"] == "project_baseline":
        missing_evidence = [
            field for field in ("baseline_evidence", "threshold_rationale") if not _non_empty(record.get(field))
        ]
        if missing_evidence:
            return ContractResult(False, "missing_project_baseline_evidence", {"missing": missing_evidence})
    if record.get("benchmark_run_status") is not None:
        run_status = record["benchmark_run_status"]
        if run_status not in ALLOWED_BENCHMARK_RUN_STATUSES:
            return ContractResult(False, "invalid_benchmark_run_status", {"benchmark_run_status": run_status})
        if run_status in {"fail", "error"}:
            return ContractResult(False, "benchmark_fail", {"verdict": "fail", "status": run_status})

    try:
        baseline = float(record["baseline"])
        measured = float(record["measured"])
        threshold = float(record["threshold"])
    except (TypeError, ValueError):
        return ContractResult(False, "invalid_benchmark_number", {})
    if baseline < 0 or measured < 0 or threshold < 0:
        return ContractResult(False, "negative_benchmark_number", {})
    if record["direction"] == "lower_is_better":
        ratio = measured / baseline if baseline else float("inf")
        verdict = "pass" if measured <= threshold else "degraded"
    else:
        ratio = measured / baseline if baseline else float("inf")
        verdict = "pass" if measured >= threshold else "degraded"

    if record["threshold_source"] == "temporary_fixture":
        return ContractResult(
            False,
            "benchmark_fixture_only",
            {
                "verdict": verdict,
                "ratio": ratio,
                "metric": record["metric"],
                "unit": record["unit"],
                "contract_valid": True,
                "readiness_supported": False,
            },
        )

    return ContractResult(
        verdict == "pass",
        f"benchmark_{verdict}",
        {
            "verdict": verdict,
            "ratio": ratio,
            "metric": record["metric"],
            "unit": record["unit"],
            "readiness_supported": verdict == "pass" and bool(record.get("claims_readiness")),
        },
    )


def review_gate_short_summary(record: dict[str, Any]) -> ContractResult:
    required = {
        "final_decision",
        "decision_reason",
        "review_coverage",
        "trust_level",
        "missing_or_unusable_reviewers",
        "authority_statement",
    }
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_review_summary_fields", {"missing": missing})
    empty = sorted(field for field in required if not _non_empty(record.get(field)))
    if empty:
        return ContractResult(False, "empty_review_summary_fields", {"empty": empty})
    if record["final_decision"] not in ALLOWED_REVIEW_DECISIONS:
        return ContractResult(False, "invalid_review_decision", {"final_decision": record["final_decision"]})
    if record.get("claims_commit_ready") and record["final_decision"] not in {"proceed", "proceed_degraded"}:
        return ContractResult(False, "commit_ready_claim_without_ready_decision", {})
    if record["final_decision"] == "proceed_degraded":
        degraded_required = ("degraded_trust_reported", "missing_reviewers_reported")
        missing_degraded = [field for field in degraded_required if not record.get(field)]
        if missing_degraded:
            return ContractResult(False, "degraded_summary_missing_disclosure", {"missing": missing_degraded})
    if record["trust_level"] == "normal" and record["review_coverage"] != "multi_reviewer":
        return ContractResult(False, "normal_trust_requires_multi_reviewer", {})
    authority = str(record["authority_statement"]).lower()
    if "unanimous" in authority and record["review_coverage"] != "multi_reviewer":
        return ContractResult(False, "unanimity_requires_multi_reviewer_coverage", {})
    return ContractResult(True, "review_summary_ready", {})


def untracked_artifact_review_guard(record: dict[str, Any]) -> ContractResult:
    guard_status = record.get("guard_status")
    if guard_status is not None:
        if guard_status not in {"clear", "material_untracked_artifacts_present"}:
            return ContractResult(False, "invalid_untracked_guard_status", {"guard_status": guard_status})
        if guard_status == "material_untracked_artifacts_present" and not record.get("manual_review_required"):
            return ContractResult(False, "material_untracked_guard_requires_manual_review", {})
        if guard_status == "material_untracked_artifacts_present" and not record.get("manual_reviewed"):
            return ContractResult(False, "material_untracked_artifacts_require_manual_review", {})

    files = record.get("files")
    if not isinstance(files, list):
        return ContractResult(False, "invalid_untracked_file_list", {})

    material_uncovered: list[str] = []
    for item in files:
        if not isinstance(item, dict):
            return ContractResult(False, "invalid_untracked_file_record", {"item": item})
        path = str(item.get("path", "")).strip()
        if not path:
            return ContractResult(False, "missing_untracked_path", {})
        if not item.get("material"):
            continue
        if item.get("secret_risk"):
            if not item.get("manual_review_required"):
                material_uncovered.append(path)
            continue
        if item.get("included_in_context") or item.get("manual_review_required"):
            continue
        material_uncovered.append(path)

    if material_uncovered:
        return ContractResult(False, "material_untracked_artifacts_not_reviewed", {"files": material_uncovered})
    return ContractResult(True, "untracked_artifacts_guarded", {})


def todo_report_reconciliation(items: list[dict[str, Any]]) -> ContractResult:
    if not isinstance(items, list):
        return ContractResult(False, "invalid_todo_items", {})

    invalid: dict[str, str] = {}
    unresolved: list[str] = []
    for index, item in enumerate(items, start=1):
        if not isinstance(item, dict):
            invalid[f"item_{index}"] = "invalid_item"
            continue
        item_id = str(item.get("id") or f"item_{index}")
        status = item.get("status")
        if status not in ALLOWED_TODO_STATUSES:
            invalid[item_id] = "invalid_status"
            continue
        if status in COMPLETE_TODO_STATUSES and not _non_empty(item.get("evidence")):
            invalid[item_id] = "complete_requires_evidence"
            continue
        if status in COMPLETE_TODO_STATUSES and _misleading_complete_evidence(status, item.get("evidence")):
            invalid[item_id] = "complete_mentions_unfinished_operating_surface"
            continue
        if status in {"deferred", "later_gated", "reference_only", "excluded", "approval_needed", "blocked"} and not _non_empty(item.get("reason")):
            invalid[item_id] = "non_active_status_requires_reason"
            continue
        if status in ACTIVE_TODO_STATUSES or status in ATTENTION_TODO_STATUSES:
            unresolved.append(item_id)

    if invalid:
        return ContractResult(False, "invalid_todo_report", {"invalid": invalid})
    if unresolved:
        return ContractResult(False, "unresolved_todo_report", {"unresolved": unresolved})
    return ContractResult(True, "todo_report_ready", {"unresolved": unresolved})


def diff_scope_classification(paths: list[str]) -> ContractResult:
    if not isinstance(paths, list):
        return ContractResult(False, "invalid_diff_paths", {})

    scopes: set[str] = set()
    for path in paths:
        if not isinstance(path, str) or not path.strip():
            return ContractResult(False, "invalid_diff_path", {"path": path})
        clean = path.strip()
        if clean.startswith("templates/automation-base/"):
            scopes.add("templates")
        elif clean == "AGENTS.md" or clean.endswith("/AGENTS.md"):
            scopes.add("guidance")
        elif clean.startswith("docs/") and clean.endswith(".md"):
            scopes.add("docs")
        elif clean.startswith("plans/") or clean.startswith(".omx/plans/"):
            scopes.add("plans")
        elif clean.startswith("scripts/") and clean.endswith((".sh", ".py")):
            scopes.add("scripts")
        elif clean.startswith("tools/") or clean.startswith("bin/"):
            scopes.add("tools")
        elif clean.startswith("tests/"):
            scopes.add("tests")
        elif clean in {"Dockerfile", "docker-compose.yml"} or clean.startswith("docker/"):
            scopes.add("docker")
        elif clean.startswith(".github/workflows/"):
            scopes.add("github_actions")
        elif clean.endswith((".py", ".js", ".ts", ".tsx", ".jsx", ".html", ".css")):
            scopes.add("app")
        else:
            scopes.add("unknown")

    review_intensity = "standard"
    if scopes & {"guidance", "scripts", "templates", "docker", "github_actions"}:
        review_intensity = "strict"
    elif scopes <= {"docs", "plans"}:
        review_intensity = "lightweight"

    return ContractResult(
        True,
        "diff_scope_ready",
        {"scopes": sorted(scopes), "review_intensity": review_intensity, "unknown_paths": "unknown" in scopes},
    )


def benchmark_wrapper_plan(record: dict[str, Any]) -> ContractResult:
    required = {
        "command",
        "output_json",
        "output_markdown",
        "sample_count",
        "environment",
        "evidence_record",
    }
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_benchmark_wrapper_fields", {"missing": missing})
    if record.get("requires_external_tool") and not record.get("external_tool_optional"):
        return ContractResult(False, "benchmark_external_tool_must_be_optional", {})
    if record.get("claims_readiness_from_single_run"):
        return ContractResult(False, "single_benchmark_run_cannot_claim_readiness", {})
    if not str(record["output_json"]).endswith(".json"):
        return ContractResult(False, "benchmark_json_output_required", {"output_json": record["output_json"]})
    if not str(record["output_markdown"]).endswith(".md"):
        return ContractResult(False, "benchmark_markdown_output_required", {"output_markdown": record["output_markdown"]})

    evidence = record["evidence_record"]
    if not isinstance(evidence, dict):
        return ContractResult(False, "invalid_benchmark_evidence_record", {})
    evidence_result = benchmark_evidence(evidence)
    if evidence_result.reason == "benchmark_degraded":
        return ContractResult(False, "benchmark_wrapper_degraded_evidence", {"reason": evidence_result.reason})
    if not evidence_result.accepted and evidence_result.reason != "benchmark_fixture_only":
        return ContractResult(False, "benchmark_evidence_contract_failed", {"reason": evidence_result.reason})
    return ContractResult(True, "benchmark_wrapper_ready", {"evidence_reason": evidence_result.reason})


def benchmark_capture_record(record: dict[str, Any]) -> ContractResult:
    required = {
        "schema_version",
        "name",
        "command",
        "benchmark_run_status",
        "verdict",
        "environment",
        "tool",
        "claims_readiness",
        "replaces_verify",
        "replaces_review_gate",
    }
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_benchmark_capture_fields", {"missing": missing})
    if record["benchmark_run_status"] not in ALLOWED_BENCHMARK_CAPTURE_STATUSES:
        return ContractResult(False, "invalid_benchmark_capture_status", {})
    if not isinstance(record.get("claims_readiness"), bool):
        return ContractResult(False, "benchmark_capture_boolean_fields_required", {"field": "claims_readiness"})
    if not isinstance(record.get("replaces_verify"), bool):
        return ContractResult(False, "benchmark_capture_boolean_fields_required", {"field": "replaces_verify"})
    if not isinstance(record.get("replaces_review_gate"), bool):
        return ContractResult(False, "benchmark_capture_boolean_fields_required", {"field": "replaces_review_gate"})
    if record["claims_readiness"] is True:
        return ContractResult(False, "benchmark_capture_cannot_claim_readiness", {})
    if record["replaces_verify"] is True or record["replaces_review_gate"] is True:
        return ContractResult(False, "benchmark_capture_must_not_replace_gates", {})
    tool = record["tool"]
    if not isinstance(tool, dict) or "name" not in tool or "available" not in tool:
        return ContractResult(False, "invalid_benchmark_capture_tool", {})
    if not isinstance(tool["available"], bool):
        return ContractResult(False, "benchmark_capture_boolean_fields_required", {"field": "tool.available"})
    if record["benchmark_run_status"] == "unavailable":
        if tool["available"] is True:
            return ContractResult(False, "unavailable_capture_requires_missing_tool", {})
        try:
            unavailable_samples = int(record.get("sample_count", -1))
        except (TypeError, ValueError):
            return ContractResult(False, "unavailable_capture_has_no_samples", {})
        if unavailable_samples != 0:
            return ContractResult(False, "unavailable_capture_has_no_samples", {})
        return ContractResult(True, "benchmark_capture_unavailable_recorded", {"readiness_supported": False})
    if record["benchmark_run_status"] == "pass":
        if tool["available"] is not True:
            return ContractResult(False, "passing_capture_requires_available_tool", {})
        try:
            sample_count = int(record.get("sample_count", 0))
            measured_ms = float(record.get("measured_ms"))
        except (TypeError, ValueError):
            return ContractResult(False, "invalid_benchmark_capture_measurement", {})
        if sample_count < 1 or measured_ms < 0:
            return ContractResult(False, "invalid_benchmark_capture_measurement", {})
    return ContractResult(True, f"benchmark_capture_{record['benchmark_run_status']}", {"readiness_supported": False})


def process_cleanup_evidence(record: dict[str, Any]) -> ContractResult:
    required = {"command", "timeout_seconds", "kill_after_seconds", "exit_status", "cleanup_checked"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_process_cleanup_fields", {"missing": missing})
    if not record.get("cleanup_checked"):
        return ContractResult(False, "process_cleanup_not_checked", {})
    if record.get("lingering_processes"):
        return ContractResult(False, "lingering_processes_detected", {"processes": record["lingering_processes"]})
    try:
        timeout_seconds = int(record["timeout_seconds"])
        kill_after_seconds = int(record["kill_after_seconds"])
    except (TypeError, ValueError):
        return ContractResult(False, "invalid_process_timeout", {})
    if timeout_seconds < 1 or kill_after_seconds < 1:
        return ContractResult(False, "invalid_process_timeout", {})
    if record.get("timed_out") and not record.get("forced_kill_or_reaped"):
        return ContractResult(False, "timed_out_process_not_reaped", {})
    return ContractResult(True, "process_cleanup_ready", {})


def reviewer_eligibility(
    reviewers: list[dict[str, Any]],
    threshold: float = REVIEWER_MIN_CONTEXT_COMPLETENESS,
) -> dict[str, Any]:
    eligible: list[str] = []
    ineligible: dict[str, str] = {}
    name_counts: dict[str, int] = {}
    for index, reviewer in enumerate(reviewers, start=1):
        raw_name = reviewer.get("name")
        base_name = raw_name.strip() if isinstance(raw_name, str) and raw_name.strip() else f"reviewer_{index}"
        name_counts[base_name] = name_counts.get(base_name, 0) + 1
        name = base_name if name_counts[base_name] == 1 else f"{base_name}#{name_counts[base_name]}"

        try:
            context_completeness = float(reviewer.get("context_completeness", 0))
        except (TypeError, ValueError):
            ineligible[name] = "invalid_context_completeness"
            continue

        if reviewer.get("host_executor"):
            ineligible[name] = "host_executor_not_independent"
        elif reviewer.get("same_session_executor"):
            ineligible[name] = "same_session_executor_not_independent"
        elif reviewer.get("truncated_context"):
            ineligible[name] = "truncated_context"
        elif reviewer.get("coverage") in {"fallback", "degraded"}:
            ineligible[name] = "fallback_or_degraded_coverage"
        elif context_completeness < threshold:
            ineligible[name] = "context_incomplete"
        elif reviewer.get("degraded_signals"):
            ineligible[name] = "degraded_signals_present"
        elif reviewer.get("verdict") not in {"approve", "approve_with_notes", "pass", "pass_with_notes"}:
            ineligible[name] = "non_approval_verdict"
        else:
            eligible.append(name)

    return {
        "eligible": eligible,
        "ineligible": ineligible,
        "unanimous_eligible": bool(reviewers) and not ineligible and len(eligible) == len(reviewers),
    }


def completion_authority(evidence: dict[str, Any]) -> ContractResult:
    required = ("diff_inspected", "plan_alignment", "verify", "review_gate", "leader_owned_final")
    missing = [field for field in required if not evidence.get(field)]
    if missing:
        return ContractResult(False, "missing_completion_fields", {"missing": missing})
    if (
        evidence.get("sidecar_claims_authority")
        or evidence.get("subagent_claims_authority")
        or evidence.get("checkpoint_claims_authority")
        or evidence.get("delegated_claims_authority")
    ):
        return ContractResult(False, "sidecar_authority_forbidden", {})
    if evidence.get("review_gate_decision") not in {"proceed", "proceed_degraded"}:
        return ContractResult(False, "review_gate_not_ready", {"decision": evidence.get("review_gate_decision")})
    if evidence.get("review_gate_decision") == "proceed_degraded":
        missing_degraded = [
            field for field in ("degraded_trust_reported", "missing_reviewers_reported") if not evidence.get(field)
        ]
        if missing_degraded:
            return ContractResult(False, "degraded_review_reporting_required", {"missing": missing_degraded})
    return ContractResult(True, "completion_authority_ready", {})


def completion_acceptance_scope(record: dict[str, Any]) -> ContractResult:
    """User-defined completion criteria are immutable acceptance scope.

    A fail-closed intermediate safety gate (for example a no-order or
    no-candidate guard) must not satisfy completion on its own. When such a gate
    is the reason no deliverable was produced, completion is valid only when the
    user-defined deliverable is proven with the required evidence, or when an
    explicit no-result final report is produced that still carries every required
    evidence item (e.g. strategy candidates attempted, backtests, fallback loops,
    AI unanimity). The user's acceptance criteria cannot be narrowed away.
    """
    criteria = record.get("user_acceptance_criteria")
    if not isinstance(criteria, (list, tuple)) or not [c for c in criteria if _non_empty(c)]:
        return ContractResult(False, "missing_acceptance_criteria", {})

    if record.get("acceptance_criteria_mutated"):
        return ContractResult(False, "acceptance_scope_mutated", {})

    # No completion claim yet: the acceptance scope is simply preserved.
    if not record.get("claimed_complete"):
        return ContractResult(True, "completion_not_claimed", {})

    required_evidence = [item for item in (record.get("required_evidence") or []) if _non_empty(item)]
    # A completion claim must define the evidence the user requires; otherwise a
    # proven deliverable or no-result report would satisfy an empty requirement.
    if not required_evidence:
        return ContractResult(False, "missing_required_evidence_definition", {})
    provided_evidence = {item for item in (record.get("evidence_provided") or []) if _non_empty(item)}
    missing_evidence = [item for item in required_evidence if item not in provided_evidence]

    deliverable_proven = bool(record.get("deliverable_proven"))
    safety_gate_triggered = bool(record.get("safety_gate_triggered"))
    no_result_report = bool(record.get("no_result_final_report"))

    # An intermediate fail-closed safety gate alone cannot satisfy completion.
    if safety_gate_triggered and not deliverable_proven and not no_result_report:
        return ContractResult(False, "safety_gate_not_completion", {})

    # Either valid completion path must still carry every required evidence item.
    if missing_evidence:
        reason = (
            "no_result_report_missing_required_evidence"
            if no_result_report and not deliverable_proven
            else "deliverable_missing_required_evidence"
        )
        return ContractResult(False, reason, {"missing": missing_evidence})

    if deliverable_proven:
        return ContractResult(True, "deliverable_complete", {})
    if no_result_report:
        return ContractResult(True, "no_result_report_complete", {})

    # Completion claimed with neither a proven deliverable nor a no-result report.
    return ContractResult(False, "completion_requires_deliverable_or_no_result_report", {})


def startup_preflight_boundary(record: dict[str, Any]) -> ContractResult:
    required = {
        "preflight_name",
        "target_timeout_seconds",
        "hard_timeout_seconds",
        "failure_mode",
        "passes_through_primary_invocation",
    }
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_startup_preflight_fields", {"missing": missing})
    try:
        target_timeout = float(record["target_timeout_seconds"])
        hard_timeout = float(record["hard_timeout_seconds"])
    except (TypeError, ValueError):
        return ContractResult(False, "invalid_startup_preflight_timeout", {})
    if target_timeout <= 0 or hard_timeout <= 0 or target_timeout > hard_timeout:
        return ContractResult(False, "invalid_startup_preflight_timeout", {})
    preflight_name = str(record["preflight_name"]).lower()
    is_update_notice = (
        "project update" in preflight_name
        or "template update" in preflight_name
        or "update notice" in preflight_name
        or "drift notice" in preflight_name
        or "status notice" in preflight_name
    )
    if is_update_notice:
        if target_timeout > 0.5 or hard_timeout > 1:
            return ContractResult(
                False,
                "project_update_notice_timeout_too_high",
                {"target_timeout_seconds": target_timeout, "hard_timeout_seconds": hard_timeout},
            )
    elif ("knowledge" in preflight_name or "obsidian" in preflight_name) and (target_timeout > 2 or hard_timeout > 5):
        return ContractResult(
            False,
            "knowledge_preflight_timeout_too_high",
            {"target_timeout_seconds": target_timeout, "hard_timeout_seconds": hard_timeout},
        )
    if hard_timeout > 5:
        return ContractResult(False, "startup_preflight_timeout_too_high", {"hard_timeout_seconds": hard_timeout})
    if record["failure_mode"] != "warning_only":
        return ContractResult(False, "startup_preflight_must_be_warning_only", {})
    if not record.get("passes_through_primary_invocation"):
        return ContractResult(False, "startup_preflight_must_pass_through", {})
    if record.get("starts_daemon") or record.get("background_mutation"):
        return ContractResult(False, "startup_preflight_must_not_start_runtime", {})
    if record.get("mutates_project_files"):
        return ContractResult(False, "startup_preflight_must_not_mutate_project_files", {})
    return ContractResult(True, "startup_preflight_boundary_ready", {})


def vault_write_boundary(record: dict[str, Any]) -> ContractResult:
    required = {
        "explicit_vault_config",
        "uses_existing_validator",
        "preserves_sync_class_guard",
        "rejects_symlink_escape",
        "rejects_dot_omx_vault",
        "idempotent_failure",
        "failure_mode",
    }
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_vault_boundary_fields", {"missing": missing})
    missing_controls = sorted(field for field in required - {"failure_mode"} if not record.get(field))
    if missing_controls:
        return ContractResult(False, "vault_boundary_missing_controls", {"missing": missing_controls})
    if record["failure_mode"] != "warning_only":
        return ContractResult(False, "vault_write_failure_must_be_warning_only", {})
    if record.get("discovers_vault_by_mount_scan"):
        return ContractResult(False, "vault_boundary_must_not_mount_scan", {})
    if record.get("claims_obsidian_authority"):
        return ContractResult(False, "obsidian_authority_forbidden", {})
    return ContractResult(True, "vault_write_boundary_ready", {})


def review_context_boundary(record: dict[str, Any]) -> ContractResult:
    required = {"material_untracked_artifacts", "content_included", "split_review", "focused_ai_council"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_review_context_fields", {"missing": missing})
    if record.get("claims_complete_review") and record.get("truncated_context"):
        return ContractResult(False, "truncated_context_cannot_claim_complete_review", {})
    if record["material_untracked_artifacts"] and not (
        record.get("content_included") or record.get("split_review") or record.get("focused_ai_council")
    ):
        return ContractResult(False, "material_untracked_review_needs_context", {})
    if record.get("split_review") and not record.get("split_synthesis"):
        return ContractResult(False, "split_review_needs_synthesis", {})
    return ContractResult(True, "review_context_boundary_ready", {})


def registry_scan_boundary(record: dict[str, Any]) -> ContractResult:
    required = {"current_repo_scope", "registry_scope", "workspace_scan", "mounted_drive_scan"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_registry_scan_fields", {"missing": missing})
    if not record.get("current_repo_scope") and not record.get("registry_scope"):
        return ContractResult(False, "registry_scan_needs_bounded_scope", {})
    if record.get("startup_path") and record.get("workspace_scan"):
        return ContractResult(False, "startup_registry_scan_must_not_workspace_crawl", {})
    if record.get("mounted_drive_scan"):
        return ContractResult(False, "registry_scan_must_not_mount_scan", {})
    return ContractResult(True, "registry_scan_boundary_ready", {})


def template_parity_boundary(record: dict[str, Any]) -> ContractResult:
    if not record.get("template_owned_change"):
        return ContractResult(True, "template_parity_not_applicable", {})
    required = {"template_version_updated", "patch_notes_updated", "template_sync_check"}
    missing_controls = sorted(field for field in required if not record.get(field))
    if missing_controls:
        return ContractResult(False, "template_parity_missing_controls", {"missing": missing_controls})
    return ContractResult(True, "template_parity_boundary_ready", {})


def status_notice_boundary(record: dict[str, Any]) -> ContractResult:
    required = {"display_only", "passes_through_primary_invocation", "records_feedback"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_status_notice_fields", {"missing": missing})
    if not record.get("display_only"):
        return ContractResult(False, "status_notice_must_be_display_only", {})
    if not record.get("passes_through_primary_invocation"):
        return ContractResult(False, "status_notice_must_pass_through", {})
    if record.get("records_feedback"):
        return ContractResult(False, "status_notice_must_not_record_feedback", {})
    if record.get("applies_patch") or record.get("commits_or_pushes"):
        return ContractResult(False, "status_notice_must_not_apply_changes", {})
    return ContractResult(True, "status_notice_boundary_ready", {})


def guidance_minimality_boundary(record: dict[str, Any]) -> ContractResult:
    required = {"behavior_exists", "doc_budget_ok", "minimal_sections"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_guidance_minimality_fields", {"missing": missing})
    if record.get("broad_policy_rewrite") and not record.get("explicit_plan"):
        return ContractResult(False, "broad_guidance_rewrite_needs_plan", {})
    missing_controls = sorted(field for field in required if not record.get(field))
    if missing_controls:
        return ContractResult(False, "guidance_minimality_missing_controls", {"missing": missing_controls})
    return ContractResult(True, "guidance_minimality_boundary_ready", {})


def artifact_sync(findings: list[dict[str, Any]]) -> ContractResult:
    unsynced = []
    for finding in findings:
        if not finding.get("material"):
            continue
        if finding.get("artifact"):
            continue
        if finding.get("deferred_with_reason"):
            continue
        unsynced.append(finding.get("id", "unknown"))
    if unsynced:
        return ContractResult(False, "material_findings_missing_artifact_sync", {"unsynced": unsynced})
    return ContractResult(True, "artifact_sync_ready", {})


def artifact_delta_check(findings: list[dict[str, Any]]) -> ContractResult:
    late_unsynced = []
    final_answer_unsynced = []
    for finding in findings:
        if not finding.get("material"):
            continue
        if finding.get("deferred_with_reason"):
            continue

        finding_id = finding.get("id", "unknown")
        artifact_contains_finding = bool(finding.get("artifact_contains_finding"))
        artifact_updated_after_finding = bool(finding.get("artifact_updated_after_finding"))

        if finding.get("learned_after_artifact_write") and not (
            finding.get("artifact") and artifact_contains_finding and artifact_updated_after_finding
        ):
            late_unsynced.append(finding_id)
        if finding.get("appears_in_final_answer") and not (finding.get("artifact") and artifact_contains_finding):
            final_answer_unsynced.append(finding_id)

    if final_answer_unsynced:
        return ContractResult(
            False,
            "final_answer_contains_unsynced_findings",
            {"unsynced": final_answer_unsynced},
        )
    if late_unsynced:
        return ContractResult(
            False,
            "late_findings_missing_artifact_update",
            {"unsynced": late_unsynced},
        )
    return ContractResult(True, "artifact_delta_ready", {})


def persona_lens_policy(record: dict[str, Any]) -> ContractResult:
    required = {"task_size", "hard_triggers", "routine_small", "active_lenses", "classifier_status"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_persona_lens_fields", {"missing": missing})
    if record["classifier_status"] != "ok":
        return ContractResult(False, "persona_classifier_strict_gate", {})
    active_lenses = record.get("active_lenses")
    hard_triggers = record.get("hard_triggers")
    if not isinstance(active_lenses, list) or not isinstance(hard_triggers, list):
        return ContractResult(False, "invalid_persona_lens_lists", {})
    if record.get("routine_small"):
        if active_lenses:
            return ContractResult(False, "routine_small_must_suppress_lenses", {"active_lenses": active_lenses})
        return ContractResult(True, "persona_lens_suppressed", {"active_lenses": []})
    if hard_triggers and not active_lenses:
        return ContractResult(False, "hard_trigger_requires_lens", {"hard_triggers": hard_triggers})
    if len(active_lenses) > 1 and "integrator" not in active_lenses:
        return ContractResult(False, "multi_lens_requires_integrator", {"active_lenses": active_lenses})
    if record.get("minimum_review_gate") == "none" and hard_triggers:
        return ContractResult(False, "hard_trigger_requires_review_gate", {})
    return ContractResult(True, "persona_lens_ready", {"active_lenses": active_lenses})


def obsidian_autopush_policy(record: dict[str, Any]) -> ContractResult:
    required = {
        "invoked_from_home_checkout",
        "opt_in",
        "pending_drafts",
        "explicit_vault_config",
        "dry_run_summary",
        "uses_knowledge_collect",
        "push_requested",
        "user_push_approval",
    }
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_obsidian_autopush_fields", {"missing": missing})
    if not record.get("invoked_from_home_checkout"):
        return ContractResult(True, "obsidian_autopush_skipped_not_home", {})
    if not record.get("opt_in"):
        return ContractResult(True, "obsidian_autopush_skipped_not_opted_in", {})
    if not record.get("pending_drafts"):
        return ContractResult(True, "obsidian_autopush_skipped_no_pending_drafts", {})
    # Shareable-only auto-push: every pushed note is shareable_summary/
    # external_private_vault, which is the deliberate per-note consent to publish,
    # so a separate per-run user approval is satisfied by that classification. A
    # secret/redaction preflight must still have passed. Any non-shareable push
    # keeps the explicit user approval requirement.
    shareable_only = bool(record.get("shareable_only_autopush") and record.get("all_pushed_shareable_only"))
    if record.get("push_requested"):
        if shareable_only:
            if not record.get("secret_scan_passed"):
                return ContractResult(False, "obsidian_autopush_secret_scan_failed", {})
        elif not record.get("user_push_approval"):
            return ContractResult(False, "obsidian_push_requires_user_approval", {})
    if not record.get("dry_run_summary"):
        return ContractResult(False, "obsidian_autopush_requires_dry_run_summary", {})
    if not record.get("explicit_vault_config") or not record.get("uses_knowledge_collect"):
        return ContractResult(False, "obsidian_autopush_missing_safe_path", {})
    if record.get("mount_scan") or record.get("claims_obsidian_authority"):
        return ContractResult(False, "obsidian_autopush_boundary_violation", {})
    if not record.get("push_requested"):
        mode = "dry_run"
    elif shareable_only:
        mode = "shareable_only_autopush"
    else:
        mode = "approved_push"
    return ContractResult(True, "obsidian_autopush_ready", {"mode": mode})


def shareable_autopromotion_policy(record: dict[str, Any]) -> ContractResult:
    """Rule for auto-promoting a local_private draft to shareable_summary.

    Promotion is allowed only for a local_private draft whose surface is on the
    allowlist, that is sanitized, and that passes the secret/redaction scan. This
    is default-deny: a surface off the allowlist (for example project-specific
    surfaces, or local-path-prone surfaces like ssh) is held local and never
    auto-published.
    """
    required = {"source_sync_class", "surface", "surface_allowlist", "redaction_status", "secret_scan_passed"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_autopromotion_fields", {"missing": missing})
    allowlist = record.get("surface_allowlist")
    if not isinstance(allowlist, (list, tuple)):
        return ContractResult(False, "invalid_surface_allowlist", {})
    if record.get("source_sync_class") != "local_private":
        return ContractResult(False, "not_local_private", {"source_sync_class": record.get("source_sync_class")})
    if record.get("surface") not in allowlist:
        return ContractResult(False, "surface_not_allowlisted", {"surface": record.get("surface")})
    if record.get("redaction_status") != "sanitized":
        return ContractResult(False, "not_sanitized", {})
    if not record.get("secret_scan_passed"):
        return ContractResult(False, "secret_scan_failed", {})
    return ContractResult(True, "autopromote_to_shareable_summary", {"target_sync_class": "shareable_summary"})


def update_visibility_policy(record: dict[str, Any]) -> ContractResult:
    required = {
        "status",
        "display_only",
        "passes_through_primary_invocation",
        "throttle_scope",
        "target_timeout_seconds",
        "hard_timeout_seconds",
    }
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_update_visibility_fields", {"missing": missing})
    if record["status"] not in {"current", "stale", "error"}:
        return ContractResult(False, "invalid_update_visibility_status", {"status": record["status"]})
    boundary = startup_preflight_boundary(
        {
            "preflight_name": "AI_AUTO update notice",
            "target_timeout_seconds": record["target_timeout_seconds"],
            "hard_timeout_seconds": record["hard_timeout_seconds"],
            "failure_mode": "warning_only",
            "passes_through_primary_invocation": record["passes_through_primary_invocation"],
            "mutates_project_files": record.get("mutates_project_files", False),
            "starts_daemon": record.get("starts_daemon", False),
            "background_mutation": record.get("background_mutation", False),
        }
    )
    if not boundary.accepted:
        return boundary
    if not record.get("display_only"):
        return ContractResult(False, "update_visibility_must_be_display_only", {})
    if record["throttle_scope"] not in {"session", "ephemeral"}:
        return ContractResult(False, "update_visibility_throttle_must_be_ephemeral", {})
    if record["status"] == "current" and record.get("notice_visible"):
        return ContractResult(False, "current_update_status_should_stay_quiet", {})
    if record["status"] in {"stale", "error"} and not record.get("clear_notice"):
        return ContractResult(False, "update_visibility_requires_clear_notice", {})
    return ContractResult(True, f"update_visibility_{record['status']}", {})


def visual_artifact_policy(record: dict[str, Any]) -> ContractResult:
    required = {"artifact_type", "owner_declared", "paired_spec", "human_reviewed", "stale_export", "ambiguous_source"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_visual_artifact_fields", {"missing": missing})
    if record["artifact_type"] not in {"mermaid", "structurizr", "excalidraw", "export"}:
        return ContractResult(False, "invalid_visual_artifact_type", {})
    if record.get("stale_export"):
        return ContractResult(False, "visual_stale_export", {})
    if record.get("ambiguous_source"):
        return ContractResult(False, "visual_ambiguous_source_of_truth", {})
    if record["artifact_type"] in {"mermaid", "structurizr"} and not record.get("owner_declared"):
        return ContractResult(False, "visual_owner_required", {})
    if record["artifact_type"] == "excalidraw":
        if not record.get("paired_spec"):
            return ContractResult(False, "visual_excalidraw_explanatory_only", {})
        if not record.get("human_reviewed"):
            return ContractResult(False, "visual_unreviewed_spec", {})
    return ContractResult(True, "visual_artifact_ready", {})


PLANNING_VISUAL_COMPLEXITY_SIGNALS = {
    "entangled_state_transitions",
    "one_to_n_or_bidirectional_links",
    "many_permission_button_alert_conditions",
    "pdf_dashboard_migration_scope",
    "explicit_visual_tool_mention",
}
PLANNING_VISUAL_LAYOUT_SIGNALS = {
    "form_structure_change",
    "section_layout",
    "list_columns",
    "popup_view",
    "button_placement",
}
PLANNING_VISUAL_STAGES = {"interview", "planning", "pre_implementation_doc"}


def planning_visual_gate_policy(record: dict[str, Any]) -> ContractResult:
    """Advisory planning gate for visualization and UI-wireframe artifacts.

    When a spec crosses complexity or layout thresholds, the structure model /
    flow visual / optimizer pass (and, for layout-heavy specs, a UI wireframe)
    should be proposed as work candidates before the final implementation
    instruction doc. The gate is advisory: proposing the missing artifacts
    satisfies it; the source spec stays authoritative and visualization is
    subordinate to it. It never installs tools or owns completion.
    """
    required = {
        "stage",
        "spec_complexity_signals",
        "layout_signals",
        "structure_artifact_present",
        "flow_visual_present",
        "ui_wireframe_present",
        "optimizer_pass_done",
        "proposal_recorded",
        "visualization_overrides_spec",
    }
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_planning_visual_gate_fields", {"missing": missing})
    stage = record["stage"]
    if stage not in PLANNING_VISUAL_STAGES:
        return ContractResult(False, "invalid_planning_visual_gate_stage", {"stage": stage})
    complexity = record.get("spec_complexity_signals") or []
    layout = record.get("layout_signals") or []
    if not isinstance(complexity, list) or not isinstance(layout, list):
        return ContractResult(False, "invalid_planning_visual_gate_signals", {})
    unknown = sorted(
        [s for s in complexity if s not in PLANNING_VISUAL_COMPLEXITY_SIGNALS]
        + [s for s in layout if s not in PLANNING_VISUAL_LAYOUT_SIGNALS]
    )
    if unknown:
        return ContractResult(False, "unknown_planning_visual_gate_signal", {"signals": unknown})
    # Source spec stays authoritative; visualization is a subordinate artifact.
    if record.get("visualization_overrides_spec"):
        return ContractResult(False, "planning_visual_gate_spec_must_stay_authoritative", {})
    complexity_triggered = len(complexity) > 0
    layout_triggered = len(layout) > 0
    if not complexity_triggered and not layout_triggered:
        return ContractResult(True, "planning_visual_gate_not_required", {})
    proposed: list[str] = []
    if complexity_triggered:
        if not record.get("structure_artifact_present"):
            proposed.append("structure_model")
        if not record.get("flow_visual_present"):
            proposed.append("flow_visual")
        if not record.get("optimizer_pass_done"):
            proposed.append("optimizer_pass")
    if layout_triggered and not record.get("ui_wireframe_present"):
        proposed.append("ui_wireframe")
    if not proposed:
        return ContractResult(True, "planning_visual_gate_satisfied", {})
    # Missing artifacts must be proposed as candidates before the final
    # implementation-instruction doc; proposing them satisfies the advisory gate.
    if not record.get("proposal_recorded"):
        return ContractResult(
            False,
            "planning_visual_gate_proposal_required",
            {"proposed": proposed, "stage": stage},
        )
    return ContractResult(True, "planning_visual_gate_proposed", {"proposed": proposed})


def product_challenge_policy(record: dict[str, Any]) -> ContractResult:
    required = {"request_shape", "task_size", "approved_plan_exists", "challenge_reason"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_product_challenge_fields", {"missing": missing})
    if record.get("approved_plan_exists"):
        return ContractResult(True, "product_challenge_skipped_approved_plan", {})
    if record["task_size"] == "small" and record["request_shape"] in {"typo", "narrow_bugfix", "routine_doc"}:
        return ContractResult(True, "product_challenge_skipped_routine_small", {})
    required_shape = record["task_size"] in {"medium", "large"} or record["request_shape"] in {
        "broad_strategy",
        "product_strategy",
        "large_ui_workflow",
        "unclear_value",
    }
    if required_shape:
        if not _non_empty(record.get("challenge_reason")):
            return ContractResult(False, "product_challenge_reason_required", {})
        questions = record.get("questions", [])
        if not isinstance(questions, list) or len(questions) > 3:
            return ContractResult(False, "product_challenge_max_three_questions", {})
        return ContractResult(True, "product_challenge_required", {"questions": questions})
    return ContractResult(True, "product_challenge_not_required", {})


def browser_qa_evidence_policy(record: dict[str, Any]) -> ContractResult:
    required = {"target", "report_only", "attempts_patch", "cdp_access", "visual_verdict", "verify_evidence", "review_gate_evidence"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_browser_qa_fields", {"missing": missing})
    if not record.get("report_only") or record.get("attempts_patch"):
        return ContractResult(False, "browser_qa_must_be_report_only", {})
    if record.get("cdp_access"):
        cdp_required = {"loopback_bound", "user_launched_or_isolated", "approval_recorded", "exports_cookies_or_tokens"}
        missing_cdp = sorted(field for field in cdp_required if field not in record)
        if missing_cdp:
            return ContractResult(False, "missing_browser_qa_cdp_fields", {"missing": missing_cdp})
        if not record.get("loopback_bound") or not record.get("user_launched_or_isolated") or not record.get("approval_recorded"):
            return ContractResult(False, "browser_qa_cdp_boundary", {})
        if record.get("exports_cookies_or_tokens"):
            return ContractResult(False, "browser_qa_must_not_export_credentials", {})
    if record.get("sensitive_evidence") and not record.get("redacted"):
        return ContractResult(False, "browser_qa_redaction_required", {})
    if record.get("visual_verdict") and not (record.get("verify_evidence") and record.get("review_gate_evidence")):
        return ContractResult(False, "visual_verdict_not_completion_authority", {})
    return ContractResult(True, "browser_qa_evidence_ready", {})


def phase_scope_guard_policy(record: dict[str, Any]) -> ContractResult:
    required = {"phase", "allowed_files", "changed_files", "deferred_files"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_phase_scope_fields", {"missing": missing})
    allowed = set(record.get("allowed_files") or [])
    changed = set(record.get("changed_files") or [])
    deferred = set(record.get("deferred_files") or [])
    if not all(isinstance(value, str) and value for value in allowed | changed | deferred):
        return ContractResult(False, "invalid_phase_scope_paths", {})
    out_of_phase = sorted(changed - allowed)
    unresolved = [path for path in out_of_phase if path not in deferred]
    if unresolved and not record.get("plan_updated"):
        return ContractResult(False, "phase_scope_out_of_phase_edit", {"files": unresolved})
    if record.get("material_finding_missing_deferral"):
        return ContractResult(False, "phase_scope_missing_deferral_record", {})
    return ContractResult(True, "phase_scope_ready", {"deferred": sorted(deferred)})


def review_revision_loop_policy(record: dict[str, Any]) -> ContractResult:
    required = {"finding_state", "structured", "cycle_count", "verification_passed", "changed_diff"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_review_revision_fields", {"missing": missing})
    if record.get("cycle_count", 0) > 2:
        return ContractResult(False, "review_revision_cycle_limit", {})
    if record.get("unclear_reviewer_output"):
        return ContractResult(False, "review_revision_unclear_review", {})
    if record.get("reviewer_disagreement"):
        return ContractResult(False, "review_revision_manual_review", {})
    if record["finding_state"] != "accepted" or not record.get("structured"):
        return ContractResult(True, "review_revision_skipped", {})
    if record.get("second_pass_requested") and not record.get("changed_diff"):
        return ContractResult(False, "review_revision_second_pass_requires_diff", {})
    if record.get("repeated_verification_failure") or not record.get("verification_passed"):
        return ContractResult(False, "review_revision_verification_failure", {})
    return ContractResult(True, "review_revision_task_ready", {})


def tool_adoption_status_policy(record: dict[str, Any]) -> ContractResult:
    required = {"tool", "installed", "adoption_state", "source", "next_gate"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_tool_status_fields", {"missing": missing})
    state = record["adoption_state"]
    if state not in {"required_gate", "optional", "reference_only", "rejected", "missing", "installed"}:
        return ContractResult(False, "invalid_tool_adoption_state", {"adoption_state": state})
    if record.get("installs_tool") or record.get("promotes_required_gate"):
        return ContractResult(False, "tool_status_must_be_read_only", {})
    if state == "required_gate" and not record.get("installed"):
        return ContractResult(False, "tool_required_missing", {"tool": record["tool"]})
    if record.get("silent_required_promotion"):
        return ContractResult(False, "tool_silent_gate_promotion", {})
    if state == "optional" and not record.get("installed"):
        return ContractResult(True, "tool_optional_missing_warning", {})
    if state == "reference_only" and record.get("installed"):
        return ContractResult(True, "tool_reference_installed_info", {})
    return ContractResult(True, "tool_adoption_status_ready", {})


def completion_pack_routing_policy(record: dict[str, Any]) -> ContractResult:
    required = {"input_shape", "available_packs", "adds_runtime_lane"}
    missing = sorted(field for field in required if field not in record)
    if missing:
        return ContractResult(False, "missing_completion_pack_fields", {"missing": missing})
    packs = set(record.get("available_packs") or [])
    required_packs = {"security", "deployment", "observability", "performance", "data", "ui"}
    missing_packs = sorted(required_packs - packs)
    if missing_packs:
        return ContractResult(False, "completion_pack_inventory_missing", {"missing": missing_packs})
    if record.get("adds_runtime_lane"):
        return ContractResult(False, "completion_pack_audit_must_not_add_runtime_lane", {})
    shape = record["input_shape"]
    mapping = {
        "security_review": "security",
        "deployment_files": "deployment",
        "persisted_data": "data",
        "ui_work": "ui",
        "performance_change": "performance",
        "observability_change": "observability",
    }
    if shape == "docs_generation_lens":
        return ContractResult(True, "completion_pack_reference_lens", {"trigger": "reference_lens"})
    trigger = mapping.get(shape)
    if not trigger:
        return ContractResult(True, "completion_pack_no_trigger", {})
    return ContractResult(True, "completion_pack_trigger_ready", {"trigger": trigger})
