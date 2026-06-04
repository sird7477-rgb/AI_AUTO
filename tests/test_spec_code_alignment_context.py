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
        "SPEC_ALIGN_PATCH_SIZE": values.get("patch_size", ""),
        "SPEC_ALIGN_APPLYING_SCOPE_CHANGE": values.get("applying", "0"),
        "SPEC_ALIGN_ROWS": values.get("rows", ""),
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
    assert "## Spec Code Alignment Audit" in context
    return context.split("## Spec Code Alignment Audit", 1)[1].split("## Browser QA Evidence Audit", 1)[0]


def test_spec_code_alignment_audit_not_required_for_small_patch(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    audit = _audit(_run_context(repo, patch_size="small"))
    assert "audit_status: report_only" in audit
    assert "spec_code_alignment_status: not_required" in audit


def test_spec_code_alignment_audit_requires_mapping_when_triggered(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    missing = _audit(_run_context(repo, patch_size="medium"))
    assert "spec_code_alignment_status: mapping_required" in missing
    assert "manual_review_required: true" in missing

    # Applying a reviewer scope change on a small patch still triggers the gate.
    via_scope = _audit(_run_context(repo, patch_size="small", applying="1"))
    assert "spec_code_alignment_status: mapping_required" in via_scope


def test_spec_code_alignment_audit_reports_clear_and_attention(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    clear = _audit(_run_context(repo, patch_size="large", rows="SR-1:aligned,SR-2:updated,SR-3:not_applicable"))
    assert "spec_code_alignment_status: clear" in clear

    attention = _audit(
        _run_context(repo, patch_size="medium", rows="SR-1:aligned,SR-4:blocked,SR-5:needs_user_confirmation")
    )
    assert "unresolved_rows: SR-4 SR-5" in attention
    assert "spec_code_alignment_status: attention" in attention


def test_spec_code_alignment_audit_mirrors_contract_validation(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    # An unknown status must not be read as a clear mapping (mirrors the
    # contract's invalid_spec_alignment_row rejection).
    bad_status = _audit(_run_context(repo, patch_size="large", rows="SR-1:aligned,SR-2:typoed"))
    assert "spec_code_alignment_status: invalid_rows" in bad_status
    assert "invalid_rows: SR-2" in bad_status
    assert "manual_review_required: true" in bad_status

    # A row with no colon is malformed, not a silent clear.
    no_colon = _audit(_run_context(repo, patch_size="medium", rows="SR-1"))
    assert "spec_code_alignment_status: invalid_rows" in no_colon

    # Whitespace around id/status is tolerated like a normal mapping.
    spaced = _audit(_run_context(repo, patch_size="large", rows=" SR-1 : aligned , SR-2 : blocked "))
    assert "spec_code_alignment_status: attention" in spaced
    assert "unresolved_rows: SR-2" in spaced

    # An unknown patch size is rejected, matching the contract.
    bad_size = _audit(_run_context(repo, patch_size="huge"))
    assert "spec_code_alignment_status: invalid_patch_size" in bad_size
