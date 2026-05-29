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
        "PRODUCT_CHALLENGE_REQUEST_SHAPE": values.get("request_shape", ""),
        "PRODUCT_CHALLENGE_TASK_SIZE": values.get("task_size", ""),
        "PRODUCT_CHALLENGE_APPROVED_PLAN_EXISTS": values.get("approved_plan", "0"),
        "PRODUCT_CHALLENGE_REASON": values.get("reason", ""),
        "PRODUCT_CHALLENGE_QUESTIONS": values.get("questions", ""),
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


def test_product_challenge_audit_requires_reason_for_broad_work(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    missing = _run_context(repo, request_shape="broad_strategy", task_size="large")
    assert "## Product Challenge Audit" in missing
    assert "challenge_status: missing_product_challenge_reason" in missing
    assert "manual_review_required: true" in missing

    required = _run_context(
        repo,
        request_shape="broad_strategy",
        task_size="large",
        reason="new product direction needs value pressure",
        questions="user,non-goal,smallest outcome",
    )
    assert "challenge_status: required" in required
    assert "challenge_reason: new product direction needs value pressure" in required
    assert "question_count: 3" in required


def test_product_challenge_audit_skips_small_and_approved_plan(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    small = _run_context(repo, request_shape="typo", task_size="small")
    assert "challenge_status: skipped_routine_small" in small

    approved = _run_context(repo, request_shape="broad_strategy", task_size="large", approved_plan="1")
    assert "challenge_status: skipped_approved_plan" in approved
