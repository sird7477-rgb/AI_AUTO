"""Pure contracts for selective GStack benchmark adoption in AI_AUTO.

The helpers are intentionally side-effect free. They do not install GStack,
create personas, start browsers, push to Obsidian, merge branches, deploy, or
operate worktrees. They encode the Phase A-F adoption boundaries from the
benchmark plan so future runtime work can be tested against a small contract.
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from json import JSONDecodeError
from typing import Any

from scripts.reflection_contracts import sanitize_payload


@dataclass(frozen=True)
class ContractResult:
    accepted: bool
    reason: str
    data: dict[str, Any]


PRODUCT_CHALLENGE_TRIGGERS = {
    "broad",
    "ambiguous",
    "strategic",
    "high_cost",
    "product_shaping",
    "rebuild_plan",
}

SMALL_MAINTENANCE_TRIGGERS = {
    "typo",
    "small_maintenance",
    "already_scoped_patch",
    "mechanical_patch",
}

UI_BROWSER_REQUIRED_FIELDS = {
    "route",
    "viewports",
    "screenshots",
    "console_checked",
    "network_checked",
    "user_path",
    "regression_decision",
}

RETRO_REQUIRED_FIELDS = {
    "repeated_failure",
    "gate_caught",
    "gate_missed",
    "evidence",
    "proposed_update",
}

PERSONA_TRIGGER_MAP = {
    "product": "broad_product_work",
    "design": "ui_work",
    "browser_qa": "browser_facing_work",
    "security": "auth_secrets_data_or_deploy",
    "release": "deployment_candidate",
    "retro": "repeated_failure_or_phase_end",
}

SECURITY_TRIGGERS = {
    "auth",
    "secrets",
    "tokens",
    "cookies",
    "browser_state",
    "pii",
    "data_retention",
    "production_adjacent",
}

RELEASE_REQUIRED_FIELDS = {
    "tests",
    "docs",
    "rollback",
    "monitoring",
    "user_summary",
}

PARALLEL_CONTRACT_FIELDS = {
    "worktree_owner",
    "branch_owner",
    "conductor",
    "integration_gate",
    "lock_strategy",
    "duplicate_draft_strategy",
    "reviewer_coverage",
}


def product_challenge_contract(task: dict[str, Any]) -> ContractResult:
    flags = set(task.get("flags", []))
    if flags & SMALL_MAINTENANCE_TRIGGERS and not flags & PRODUCT_CHALLENGE_TRIGGERS:
        return ContractResult(False, "skip_small_maintenance", {"triggered": False})
    if not flags & PRODUCT_CHALLENGE_TRIGGERS:
        return ContractResult(False, "no_product_challenge_trigger", {"triggered": False})

    missing = [
        field
        for field in ("problem", "smallest_wedge", "non_goals", "risks", "acceptance_evidence", "decision")
        if not task.get(field)
    ]
    if missing:
        return ContractResult(False, "missing_product_challenge_fields", {"missing": missing})
    if task["decision"] not in {"proceed", "narrow", "ask", "reject"}:
        return ContractResult(False, "invalid_product_challenge_decision", {"decision": task["decision"]})
    return ContractResult(True, "product_challenge_ready", {"triggered": True, "decision": task["decision"]})


def browser_qa_contract(evidence: dict[str, Any]) -> ContractResult:
    missing = sorted(field for field in UI_BROWSER_REQUIRED_FIELDS if not evidence.get(field))
    if missing:
        return ContractResult(False, "missing_browser_qa_evidence", {"missing": missing})
    if evidence.get("persistent_authenticated_state") and not evidence.get("explicit_browser_state_approval"):
        return ContractResult(False, "browser_state_requires_explicit_approval", {})
    if evidence.get("mode") not in {"report_only", "fix_loop"}:
        return ContractResult(False, "invalid_browser_qa_mode", {"mode": evidence.get("mode")})
    if evidence.get("mode") == "fix_loop" and not evidence.get("explicit_execution_scope"):
        return ContractResult(False, "fix_loop_requires_execution_scope", {})
    if evidence.get("source_of_truth") not in {"user_template", "project_screen", "external_reference"}:
        return ContractResult(False, "invalid_ui_source_of_truth", {"source_of_truth": evidence.get("source_of_truth")})
    return ContractResult(True, "browser_qa_ready", {"mode": evidence["mode"]})


def retro_draft_contract(draft: dict[str, Any]) -> ContractResult:
    missing = sorted(field for field in RETRO_REQUIRED_FIELDS if not draft.get(field))
    if missing:
        return ContractResult(False, "missing_retro_draft_fields", {"missing": missing})
    privacy = sanitize_payload(json.dumps(draft, ensure_ascii=False, sort_keys=True))
    if not privacy["accepted"]:
        return ContractResult(False, "retro_draft_privacy_blocked", {"privacy": privacy})
    if draft.get("obsidian_runtime_authority"):
        return ContractResult(False, "obsidian_runtime_authority_forbidden", {})
    if draft.get("promotion_without_review_gate"):
        return ContractResult(False, "promotion_requires_review_gate", {})
    return ContractResult(True, "retro_draft_ready", {"privacy": privacy})


def persona_lens_contract(task: dict[str, Any]) -> ContractResult:
    if task.get("standing_roster"):
        return ContractResult(False, "standing_persona_roster_forbidden", {})

    requested = set(task.get("requested_lenses", []))
    unknown = sorted(requested - set(PERSONA_TRIGGER_MAP))
    if unknown:
        return ContractResult(False, "unknown_persona_lens", {"unknown": unknown})

    task_shapes = set(task.get("task_shapes", []))
    missing_triggers = sorted(lens for lens in requested if PERSONA_TRIGGER_MAP[lens] not in task_shapes)
    if missing_triggers:
        return ContractResult(False, "persona_lens_missing_task_shape_trigger", {"missing": missing_triggers})

    if task.get("routine_small_task") and requested:
        return ContractResult(False, "routine_task_must_not_gain_persona_lanes", {})

    return ContractResult(True, "persona_lenses_ready", {"lenses": sorted(requested)})


def security_release_ops_contract(work: dict[str, Any]) -> ContractResult:
    triggers = set(work.get("triggers", []))
    if work.get("auto_merge") or work.get("auto_deploy") or work.get("production_canary"):
        return ContractResult(False, "autonomous_release_side_effect_forbidden", {})

    security_active = bool(triggers & SECURITY_TRIGGERS)
    release_active = bool(work.get("release_candidate") or work.get("deployment_candidate"))
    if not security_active and not release_active:
        return ContractResult(False, "security_release_lane_not_triggered", {"triggered": False})

    missing_release = []
    if release_active:
        missing_release = sorted(field for field in RELEASE_REQUIRED_FIELDS if not work.get(field))
        if missing_release:
            return ContractResult(False, "missing_release_evidence", {"missing": missing_release})

    return ContractResult(
        True,
        "security_release_ops_ready",
        {"security_active": security_active, "release_active": release_active},
    )


def parallel_conductor_contract(plan: dict[str, Any]) -> ContractResult:
    if not plan.get("research_only") and not plan.get("approved_parallel_execution_plan"):
        return ContractResult(False, "parallel_sprint_execution_requires_separate_approval", {})
    if plan.get("starts_worktrees") and not plan.get("approved_parallel_execution_plan"):
        return ContractResult(False, "worktree_execution_forbidden_without_plan", {})

    missing = sorted(field for field in PARALLEL_CONTRACT_FIELDS if not plan.get(field))
    if missing:
        return ContractResult(False, "missing_parallel_conductor_contract", {"missing": missing})

    return ContractResult(True, "parallel_conductor_contract_ready", {"research_only": bool(plan.get("research_only"))})


CONTRACTS = {
    "product": product_challenge_contract,
    "browser-qa": browser_qa_contract,
    "retro": retro_draft_contract,
    "persona": persona_lens_contract,
    "security-release": security_release_ops_contract,
    "parallel": parallel_conductor_contract,
}


def _main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in CONTRACTS:
        names = ", ".join(sorted(CONTRACTS))
        print(f"usage: {argv[0]} <{names}> < input.json", file=sys.stderr)
        return 2
    try:
        payload = json.load(sys.stdin)
    except JSONDecodeError as exc:
        print(json.dumps({"accepted": False, "reason": "invalid_json", "error": str(exc)}, sort_keys=True))
        return 2
    result = CONTRACTS[argv[1]](payload)
    print(json.dumps({"accepted": result.accepted, "reason": result.reason, **result.data}, ensure_ascii=False, sort_keys=True))
    return 0 if result.accepted else 1


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv))
