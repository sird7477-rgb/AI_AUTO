import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _run_context(repo: Path, allowed: str, deferred: str = "", deferred_records: str = "") -> str:
    env = {
        **os.environ,
        "OUT_DIR": str(repo / ".omx" / "review-context"),
        "PHASE_SCOPE_PHASE": "docs",
        "PHASE_SCOPE_ALLOWED_FILES": allowed,
        "PHASE_SCOPE_DEFERRED_FILES": deferred,
        "PHASE_SCOPE_DEFERRED_RECORDS": deferred_records,
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


def test_collect_review_context_reports_phase_scope_guard(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    (repo / "scripts").mkdir(parents=True)
    (repo / "docs").mkdir()
    shutil.copy(ROOT / "scripts" / "collect-review-context.sh", repo / "scripts" / "collect-review-context.sh")
    (repo / "docs" / "workflow.md").write_text("draft\n", encoding="utf-8")
    subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)

    clear = _run_context(repo, "docs/workflow.md,scripts/collect-review-context.sh")
    assert "## Phase Scope Guard" in clear
    assert "phase_scope_status: clear" in clear

    blocked = _run_context(repo, "docs/other.md")
    assert "phase_scope_status: out_of_phase_edit" in blocked
    assert "docs/workflow.md" in blocked

    deferred_without_reason = _run_context(repo, "docs/other.md", deferred="docs/workflow.md")
    assert "phase_scope_status: missing_deferral_record" in deferred_without_reason
    assert "docs/workflow.md" in deferred_without_reason

    deferred_with_reason = _run_context(
        repo,
        "docs/other.md,scripts/collect-review-context.sh",
        deferred="docs/workflow.md",
        deferred_records="docs/workflow.md|tracked plan spillover",
    )
    assert "phase_scope_status: clear" in deferred_with_reason
