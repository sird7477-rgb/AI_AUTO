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
            "readiness_supported": verdict == "pass",
        },
    )


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
