import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _prepare_repo(repo: Path) -> None:
    (repo / "scripts").mkdir(parents=True)
    (repo / ".gitignore").write_text(".omx/\n", encoding="utf-8")
    shutil.copy(ROOT / "scripts" / "collect-review-context.sh", repo / "scripts" / "collect-review-context.sh")
    subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo, check=True)
    subprocess.run(["git", "add", ".gitignore", "scripts/collect-review-context.sh"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-m", "baseline"], cwd=repo, check=True, stdout=subprocess.DEVNULL)


def _run_context(repo: Path, before_status: str | None = None) -> str:
    env = {**os.environ, "OUT_DIR": str(repo / ".omx" / "review-context")}
    if before_status is not None:
        env["REPO_STATUS_BEFORE_CONTEXT"] = before_status
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


def test_tree_churn_audit_reports_stable_status(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    context = _run_context(repo)

    assert "## Tree Churn Audit" in context
    assert "audit_status: report_only" in context
    assert "tree_churn_status: stable" in context


def test_tree_churn_audit_reports_new_untracked_files(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)
    (repo / "notes.md").write_text("new\n", encoding="utf-8")

    context = _run_context(repo, before_status="")

    assert "tree_churn_status: changed" in context
    assert "new_untracked_during_context:" in context
    assert "- notes.md" in context
