"""Pure contracts for AI_AUTO self-demo validation.

These helpers do not execute commands, write files, start Docker, call browsers,
or approve small-tool adoption. They only validate the evidence shape needed
before a workflow upgrade can claim representative user-facing coverage.
Self-demo required fields are intentionally string-only; use explicit sentinel
words such as "none" or "not_applicable" when a field has no applicable content.
"""

from __future__ import annotations

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
ALLOWED_TODO_STATUSES = {
    "complete",
    "complete_contract",
    "complete_observe_mode",
    "display_only_complete",
    "installed_required",
    "contract_started",
    "open",
    "planned_not_run",
    "insufficiently_run",
    "deferred",
    "later_gated",
    "reference_only",
    "excluded",
    "approval_needed",
    "blocked",
}
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


def _non_empty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _reference_like(value: Any) -> bool:
    text = str(value).strip() if value is not None else ""
    lowered = text.lower()
    return lowered.startswith(("http://", "https://", "docs/", "doc:", "standard:", "rfc:", "iso:"))


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
        if status in {"complete", "complete_contract", "complete_observe_mode", "display_only_complete", "installed_required"} and not _non_empty(item.get("evidence")):
            invalid[item_id] = "complete_requires_evidence"
            continue
        if status in {"deferred", "later_gated", "reference_only", "excluded", "approval_needed", "blocked"} and not _non_empty(item.get("reason")):
            invalid[item_id] = "non_active_status_requires_reason"
            continue
        if status in {"open", "planned_not_run", "insufficiently_run", "contract_started"}:
            unresolved.append(item_id)

    if invalid:
        return ContractResult(False, "invalid_todo_report", {"invalid": invalid})
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
