"""RED9-5 (R4 red-team re-attack, HIGH, docs: .ops-game/R4-red9-reattack.md) —
`scripts/write-session-checkpoint.sh` is an unfixed sibling of the RED6-2 doctor bug
(tests/test_doctor_review_state_dir_r3.py): it must resolve the reviewer-state directory the
SAME way `scripts/run-ai-reviews.sh:18` / `scripts/review-gate.sh:118` /
`scripts/automation-doctor.sh:737` (RED6-2 fix) do:
`REVIEW_STATE_DIR="${REVIEW_STATE_DIR:-.omx/reviewer-state}"`.

Before this fix, the "## Reviewer State" section of write-session-checkpoint.sh hardcoded the
literal `.omx/reviewer-state` and never read `REVIEW_STATE_DIR` at all. Any environment that
overrides `REVIEW_STATE_DIR` (exactly as run-ai-reviews.sh/review-gate.sh themselves support)
would have the checkpoint inspect the wrong (empty) directory and print a false "none" for the
Reviewer State section while a reviewer marker sits, live, in the real (custom) state dir. This
checkpoint file is explicitly documented (script comment, "## Resume Notes" section) as "resume
evidence" an agent/operator is meant to trust -- a false "none" here is the same false-green harm
class RED6-2 was rated HIGH for.

This test builds a small, hermetic fixture "project" git repo under pytest's tmp_path and drives
scripts/write-session-checkpoint.sh as a real subprocess -- matching the pattern used by
tests/test_doctor_review_state_dir_r3.py for the sibling doctor fix.
"""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKPOINT_SCRIPT = ROOT / "scripts" / "write-session-checkpoint.sh"

MARKER_BODY = (
    "reviewer=gemini\n"
    "disabled_at=2026-07-07T00:00:00+00:00\n"
    "reason=prompt_size_limit\n"
    "details=class=prompt_size_limit; tail=large_prompt_prompt_file_fallback_failed\n"
    "disable_class=transient\n"
    "source_run_id=test-run-1\n"
    "next_action=auto_recover_after_cooldown_300s\n"
    "chronic_count=1\n"
    "reset_hint=RESET_DISABLED_AI_REVIEWERS=gemini ./scripts/review-gate.sh\n"
)


def _init_git_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q"], cwd=path, check=True)
    subprocess.run(["git", "config", "user.email", "t@example.invalid"], cwd=path, check=True)
    subprocess.run(["git", "config", "user.name", "T"], cwd=path, check=True)
    (path / "README.md").write_text("fixture\n", encoding="utf-8")
    subprocess.run(["git", "add", "-A"], cwd=path, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "base"], cwd=path, check=True)


def _run_checkpoint(project: Path, *, review_state_dir: str | None, checkpoint_out: Path) -> str:
    env = os.environ.copy()
    env.pop("REVIEW_STATE_DIR", None)
    if review_state_dir is not None:
        env["REVIEW_STATE_DIR"] = review_state_dir
    env["OMX_SESSION_CHECKPOINT_FILE"] = str(checkpoint_out)
    result = subprocess.run(
        ["bash", str(CHECKPOINT_SCRIPT)],
        cwd=project,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=60,
    )
    assert result.returncode == 0, f"checkpoint script failed:\n{result.stdout}"
    assert checkpoint_out.is_file(), result.stdout
    return checkpoint_out.read_text()


# ---------------------------------------------------------------------------
# Default location (REVIEW_STATE_DIR unset): unchanged behaviour, still works.
# ---------------------------------------------------------------------------

def test_default_location_reports_disabled_reviewer(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    _init_git_repo(project)
    state_dir = project / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "gemini.disabled").write_text(MARKER_BODY, encoding="utf-8")

    checkpoint = _run_checkpoint(
        project, review_state_dir=None, checkpoint_out=tmp_path / "checkpoint.md"
    )

    assert "gemini: prompt_size_limit" in checkpoint, checkpoint
    assert "## Reviewer State\n\n- none" not in checkpoint, checkpoint


def test_default_location_no_markers_reports_none(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    _init_git_repo(project)
    (project / ".omx" / "reviewer-state").mkdir(parents=True, exist_ok=True)

    checkpoint = _run_checkpoint(
        project, review_state_dir=None, checkpoint_out=tmp_path / "checkpoint.md"
    )

    assert "## Reviewer State\n\n- none" in checkpoint, checkpoint


# ---------------------------------------------------------------------------
# Custom REVIEW_STATE_DIR (the RED9-5 regression): the disabled marker lives ONLY in the
# custom dir, matching what run-ai-reviews.sh/review-gate.sh would have written under that same
# override. A checkpoint script that hardcodes .omx/reviewer-state finds the (empty) default
# dir and prints a false "none" here -- this must NOT happen.
# ---------------------------------------------------------------------------

def test_custom_review_state_dir_reports_disabled_reviewer_not_false_none(tmp_path: Path) -> None:
    """PoC-mirrored from .ops-game/R4-red9-reattack.md RED9-5: plant a genuinely disabled
    gemini.disabled marker under a REVIEW_STATE_DIR=custom-state override, then run the real,
    unmodified scripts/write-session-checkpoint.sh -- the pre-fix script reported
    '## Reviewer State\\n\\n- none' here.

    Revert-proof: this exact scenario is the reproduction the red-team report ran against the
    pre-fix committed script and got the false-"none" result; against the fixed script, the
    marker must be surfaced.
    """
    project = tmp_path / "proj"
    _init_git_repo(project)
    custom_dir = project / "custom-state"
    custom_dir.mkdir(parents=True, exist_ok=True)
    (custom_dir / "gemini.disabled").write_text(MARKER_BODY, encoding="utf-8")

    # The default dir exists but is empty -- exactly the false-green trap: a script that
    # ignores REVIEW_STATE_DIR looks here, finds nothing, and reports "none".
    default_dir = project / ".omx" / "reviewer-state"
    default_dir.mkdir(parents=True, exist_ok=True)

    checkpoint = _run_checkpoint(
        project, review_state_dir="custom-state", checkpoint_out=tmp_path / "checkpoint.md"
    )

    assert "gemini: prompt_size_limit" in checkpoint, (
        f"a disabled reviewer marker under a custom REVIEW_STATE_DIR was reported as 'none' "
        f"(RED9-5 reopened):\n{checkpoint}"
    )
    assert "## Reviewer State\n\n- none" not in checkpoint, checkpoint


def test_custom_review_state_dir_with_no_markers_reports_none(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    _init_git_repo(project)
    custom_dir = project / "custom-state"
    custom_dir.mkdir(parents=True, exist_ok=True)

    checkpoint = _run_checkpoint(
        project, review_state_dir="custom-state", checkpoint_out=tmp_path / "checkpoint.md"
    )

    assert "## Reviewer State\n\n- none" in checkpoint, checkpoint
