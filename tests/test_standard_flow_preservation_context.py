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
        "STANDARD_FLOW_HIDES_STANDARD_FIELD": values.get("hides", "0"),
        "STANDARD_FLOW_CUSTOM_RELATIONSHIP": values.get("relationship", ""),
        "STANDARD_FLOW_IMPACT_MAP_RECORDED": values.get("impact_map", "0"),
        "STANDARD_FLOW_REGRESSION_EVIDENCE": values.get("regression", "0"),
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
    assert "## Standard Flow Preservation Audit" in context
    return context.split("## Standard Flow Preservation Audit", 1)[1].split("## Browser QA Evidence Audit", 1)[0]


def test_standard_flow_audit_not_affected_by_default(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    audit = _audit(_run_context(repo))
    assert "audit_status: report_only" in audit
    assert "standard_flow_status: not_affected" in audit


def test_standard_flow_audit_requires_impact_map_and_regression(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    no_map = _audit(_run_context(repo, hides="1", relationship="extends_standard"))
    assert "standard_flow_status: impact_map_required" in no_map
    assert "manual_review_required: true" in no_map

    no_reg = _audit(_run_context(repo, hides="1", relationship="extends_standard", impact_map="1"))
    assert "standard_flow_status: regression_required" in no_reg


def test_standard_flow_audit_blocks_parallel_replacement_and_passes_extend(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    blocked = _audit(
        _run_context(repo, hides="1", relationship="parallel_replacement", impact_map="1", regression="1")
    )
    assert "standard_flow_status: parallel_replacement_blocked" in blocked

    preserved = _audit(
        _run_context(repo, hides="1", relationship="extends_standard", impact_map="1", regression="1")
    )
    assert "standard_flow_status: preserved" in preserved
