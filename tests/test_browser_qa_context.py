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
    env = {**os.environ, "OUT_DIR": str(repo / ".omx" / "review-context")}
    for key, value in values.items():
        env[f"BROWSER_QA_{key.upper()}"] = value
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


def test_browser_qa_audit_reports_read_only_evidence(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    context = _run_context(repo, TARGET="http://127.0.0.1:3000", STEPS="open dashboard", SCREENSHOT_NOTE="main path")

    assert "## Browser QA Evidence Audit" in context
    assert "audit_status: report_only" in context
    assert "target: http://127.0.0.1:3000" in context
    assert "qa_status: qa_ok:report_only" in context


def test_browser_qa_audit_blocks_fix_loop_and_unsafe_cdp(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    fix_loop = _run_context(repo, ATTEMPTS_PATCH="1")
    assert "qa_status: qa_block:auto_fix_not_allowed" in fix_loop

    unsafe_cdp = _run_context(repo, CDP_ACCESS="1", LOOPBACK_BOUND="1", USER_LAUNCHED_OR_ISOLATED="0", APPROVAL_RECORDED="1")
    assert "qa_status: qa_block:credential_boundary" in unsafe_cdp

    safe_cdp = _run_context(
        repo,
        CDP_ACCESS="1",
        LOOPBACK_BOUND="1",
        USER_LAUNCHED_OR_ISOLATED="1",
        APPROVAL_RECORDED="1",
        EXPORTS_COOKIES_OR_TOKENS="0",
    )
    assert "qa_status: qa_ok:cdp_report_only" in safe_cdp


def test_browser_qa_audit_flags_redaction_and_visual_authority(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    sensitive = _run_context(repo, SENSITIVE_EVIDENCE="1", REDACTED="0")
    assert "qa_status: qa_warning:redaction_required" in sensitive

    visual_only = _run_context(repo, VISUAL_VERDICT="1", VERIFY_EVIDENCE="1", REVIEW_GATE_EVIDENCE="0")
    assert "qa_status: qa_warning:visual_not_completion_authority" in visual_only
