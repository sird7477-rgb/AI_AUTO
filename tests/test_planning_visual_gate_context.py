import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _prepare_repo(repo: Path) -> None:
    (repo / "scripts").mkdir(parents=True)
    shutil.copy(ROOT / "scripts" / "collect-review-context.sh", repo / "scripts" / "collect-review-context.sh")
    subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)


def _run_context(repo: Path, **values: str) -> str:
    env = {
        **os.environ,
        "OUT_DIR": str(repo / ".omx" / "review-context"),
        "PLANNING_VISUAL_STAGE": values.get("stage", ""),
        "PLANNING_VISUAL_COMPLEXITY_SIGNALS": values.get("complexity", ""),
        "PLANNING_VISUAL_LAYOUT_SIGNALS": values.get("layout", ""),
        "PLANNING_VISUAL_STRUCTURE_PRESENT": values.get("structure", "0"),
        "PLANNING_VISUAL_FLOW_PRESENT": values.get("flow", "0"),
        "PLANNING_VISUAL_WIREFRAME_PRESENT": values.get("wireframe", "0"),
        "PLANNING_VISUAL_OPTIMIZER_DONE": values.get("optimizer", "0"),
        "PLANNING_VISUAL_PROPOSAL_RECORDED": values.get("proposal", "0"),
        "PLANNING_VISUAL_OVERRIDES_SPEC": values.get("overrides", "0"),
    }
    subprocess.run(
        ["bash", "scripts/collect-review-context.sh"],
        cwd=repo,
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    return (repo / ".omx" / "review-context" / "latest-review-context.md").read_text(encoding="utf-8")


def _audit(context: str) -> str:
    assert "## Planning Visual Gate Audit" in context
    return context.split("## Planning Visual Gate Audit", 1)[1].split("## Browser QA Evidence Audit", 1)[0]


def test_planning_visual_gate_audit_is_report_only_and_not_required_by_default(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    audit = _audit(_run_context(repo))
    assert "audit_status: report_only" in audit
    assert "runtime_tool_install_required: false" in audit
    assert "planning_visual_status: not_required" in audit


def test_planning_visual_gate_audit_proposes_missing_artifacts(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    unproposed = _audit(_run_context(repo, complexity="entangled_state_transitions", layout="popup_view"))
    assert "proposed_artifacts: structure_model flow_visual optimizer_pass ui_wireframe" in unproposed
    assert "planning_visual_status: proposal_required" in unproposed
    assert "manual_review_required: true" in unproposed

    proposed = _audit(
        _run_context(repo, complexity="entangled_state_transitions", layout="popup_view", proposal="1")
    )
    assert "planning_visual_status: proposed" in proposed
    assert "manual_review_required: true" not in proposed


def test_planning_visual_gate_audit_satisfied_and_spec_authoritative(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    satisfied = _audit(
        _run_context(
            repo,
            complexity="pdf_dashboard_migration_scope",
            layout="list_columns",
            structure="1",
            flow="1",
            wireframe="1",
            optimizer="1",
        )
    )
    assert "planning_visual_status: satisfied" in satisfied

    override = _audit(_run_context(repo, complexity="entangled_state_transitions", overrides="1"))
    assert "planning_visual_status: spec_must_stay_authoritative" in override
