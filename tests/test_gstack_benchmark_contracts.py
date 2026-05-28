from scripts.gstack_benchmark_contracts import (
    browser_qa_contract,
    parallel_conductor_contract,
    persona_lens_contract,
    product_challenge_contract,
    retro_draft_contract,
    security_release_ops_contract,
)


def test_product_challenge_triggers_for_broad_work_and_skips_small_tasks() -> None:
    valid = {
        "flags": ["strategic"],
        "problem": "Too broad rebuild request",
        "smallest_wedge": "Phase A contract only",
        "non_goals": ["runtime adoption"],
        "risks": ["scope creep"],
        "acceptance_evidence": ["review gate"],
        "decision": "narrow",
    }
    assert product_challenge_contract(valid).accepted
    assert product_challenge_contract({"flags": ["small_maintenance"]}).reason == "skip_small_maintenance"
    assert product_challenge_contract({"flags": ["strategic"], "decision": "maybe"}).reason == "missing_product_challenge_fields"
    assert product_challenge_contract({**valid, "decision": "maybe"}).reason == "invalid_product_challenge_decision"


def test_browser_qa_requires_evidence_and_blocks_unapproved_persistent_state() -> None:
    valid = {
        "route": "/todos",
        "viewports": ["desktop", "mobile"],
        "screenshots": ["desktop.png"],
        "console_checked": True,
        "network_checked": True,
        "user_path": "open list",
        "regression_decision": "covered by smoke",
        "mode": "report_only",
        "source_of_truth": "user_template",
    }
    assert browser_qa_contract(valid).accepted
    assert browser_qa_contract({**valid, "screenshots": []}).reason == "missing_browser_qa_evidence"
    assert (
        browser_qa_contract({**valid, "persistent_authenticated_state": True}).reason
        == "browser_state_requires_explicit_approval"
    )
    assert browser_qa_contract({**valid, "mode": "fix_loop"}).reason == "fix_loop_requires_execution_scope"


def test_retro_draft_is_sanitized_and_non_authoritative() -> None:
    valid = {
        "repeated_failure": "late finding missed artifact update",
        "gate_caught": "review-gate",
        "gate_missed": "manual artifact sync",
        "evidence": "review note",
        "proposed_update": "add artifact sync check",
    }
    assert retro_draft_contract(valid).accepted
    assert retro_draft_contract({**valid, "evidence": "token=abc123"}).reason == "retro_draft_privacy_blocked"
    assert retro_draft_contract({**valid, "obsidian_runtime_authority": True}).reason == "obsidian_runtime_authority_forbidden"
    assert retro_draft_contract({**valid, "promotion_without_review_gate": True}).reason == "promotion_requires_review_gate"


def test_persona_lenses_are_conditional_not_standing_roster() -> None:
    valid = {"requested_lenses": ["product", "security"], "task_shapes": ["broad_product_work", "auth_secrets_data_or_deploy"]}
    assert persona_lens_contract(valid).accepted
    assert persona_lens_contract({"standing_roster": True}).reason == "standing_persona_roster_forbidden"
    assert persona_lens_contract({"requested_lenses": ["design"], "task_shapes": []}).reason == "persona_lens_missing_task_shape_trigger"
    assert persona_lens_contract({"requested_lenses": ["retro"], "task_shapes": ["repeated_failure_or_phase_end"], "routine_small_task": True}).reason == "routine_task_must_not_gain_persona_lanes"


def test_security_release_ops_triggers_are_conditional_and_side_effect_free() -> None:
    security = {"triggers": ["tokens"]}
    release = {
        "deployment_candidate": True,
        "tests": "passed",
        "docs": "updated",
        "rollback": "defined",
        "monitoring": "smoke",
        "user_summary": "ready",
    }
    assert security_release_ops_contract(security).accepted
    assert security_release_ops_contract(release).accepted
    assert security_release_ops_contract({"triggers": []}).reason == "security_release_lane_not_triggered"
    assert security_release_ops_contract({**release, "auto_deploy": True}).reason == "autonomous_release_side_effect_forbidden"
    assert security_release_ops_contract({"deployment_candidate": True}).reason == "missing_release_evidence"


def test_parallel_conductor_is_research_only_without_separate_execution_plan() -> None:
    valid = {
        "research_only": True,
        "worktree_owner": "owner",
        "branch_owner": "branch",
        "conductor": "integrator",
        "integration_gate": "review-gate",
        "lock_strategy": "exclusive",
        "duplicate_draft_strategy": "dedupe",
        "reviewer_coverage": "defined",
    }
    assert parallel_conductor_contract(valid).accepted
    assert parallel_conductor_contract({**valid, "research_only": False}).reason == "parallel_sprint_execution_requires_separate_approval"
    assert parallel_conductor_contract({**valid, "starts_worktrees": True}).reason == "worktree_execution_forbidden_without_plan"
    assert parallel_conductor_contract({"research_only": True}).reason == "missing_parallel_conductor_contract"


def test_gstack_benchmark_language_does_not_imply_runtime_adoption() -> None:
    assert product_challenge_contract({"flags": ["small_maintenance"], "installs_gstack": True}).reason == (
        "runtime_gstack_adoption_requires_separate_approval"
    )
    assert product_challenge_contract({"flags": ["strategic"], "runtime_gstack_adoption": True}).reason == (
        "runtime_gstack_adoption_requires_separate_approval"
    )
    assert persona_lens_contract({"standing_roster": True, "benchmark_research": True}).reason == "standing_persona_roster_forbidden"
    assert (
        parallel_conductor_contract(
            {
                "research_only": True,
                "worktree_owner": "owner",
                "branch_owner": "branch",
                "conductor": "integrator",
                "integration_gate": "review-gate",
                "lock_strategy": "exclusive",
                "duplicate_draft_strategy": "dedupe",
                "reviewer_coverage": "defined",
                "starts_worktrees": True,
            }
        ).reason
        == "worktree_execution_forbidden_without_plan"
    )
