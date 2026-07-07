"""RED6-2 (R2 red-review, HIGH, connectivity) — `scripts/automation-doctor.sh` must resolve
the reviewer-state directory the SAME way `scripts/run-ai-reviews.sh:18` and
`scripts/review-gate.sh:118` do: `REVIEW_STATE_DIR="${REVIEW_STATE_DIR:-.omx/reviewer-state}"`.

Before the fix, the doctor's "checking reviewer state" block hardcoded the literal
`.omx/reviewer-state` and never read `REVIEW_STATE_DIR` at all. Any environment that sets
`REVIEW_STATE_DIR` to a non-default location (exactly as run-ai-reviews.sh/review-gate.sh
themselves support, and as verify-machinery.sh's own test suite exercises) would have the
doctor inspect the wrong (empty) directory and print a false-green "no disabled reviewers
recorded" while a reviewer marker sits, live, in the real (custom) state dir.

These tests build small, hermetic fixture "project" directories (their own throwaway git repos
under pytest's tmp_path) and drive scripts/automation-doctor.sh as a subprocess -- matching the
pattern used by tests/test_doctor_bootstrap_ip2.py.
"""
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCTOR = ROOT / "scripts" / "automation-doctor.sh"

MARKER_BODY = (
    "disabled_at=2026-07-07T00:00:00+00:00\n"
    "reason=repeated_timeout\n"
    "details=3 consecutive timeouts\n"
    "source_run_id=test-run-1\n"
    "next_action=user_reset_required\n"
    "reset_hint=RESET_DISABLED_AI_REVIEWERS=claude ./scripts/review-gate.sh\n"
)


def _run(args: list[str], *, cwd: Path, env: dict) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(DOCTOR), *args],
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def _init_git_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q"], cwd=path, check=True)
    subprocess.run(["git", "config", "user.email", "t@example.invalid"], cwd=path, check=True)
    subprocess.run(["git", "config", "user.name", "T"], cwd=path, check=True)
    (path / "README.md").write_text("fixture\n", encoding="utf-8")
    subprocess.run(["git", "add", "-A"], cwd=path, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "base"], cwd=path, check=True)


def _base_env(*, review_state_dir: str | None) -> dict:
    env = os.environ.copy()
    env.pop("REVIEW_STATE_DIR", None)
    if review_state_dir is not None:
        env["REVIEW_STATE_DIR"] = review_state_dir
    return env


# ---------------------------------------------------------------------------
# Default location (REVIEW_STATE_DIR unset): unchanged behaviour, still works.
# ---------------------------------------------------------------------------

def test_default_location_reports_disabled_reviewer(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    _init_git_repo(project)
    state_dir = project / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "claude.disabled").write_text(MARKER_BODY, encoding="utf-8")

    result = _run(["--project"], cwd=project, env=_base_env(review_state_dir=None))

    assert "reviewer disabled: claude" in result.stdout, result.stdout
    assert "no disabled reviewers recorded" not in result.stdout, result.stdout


def test_default_location_no_markers_is_clean_pass(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    _init_git_repo(project)
    # ensure_dir() only warns (never creates) without --fix, so create the empty
    # state dir explicitly to reach the "no disabled reviewers recorded" branch.
    (project / ".omx" / "reviewer-state").mkdir(parents=True, exist_ok=True)

    result = _run(["--project"], cwd=project, env=_base_env(review_state_dir=None))

    assert "no disabled reviewers recorded" in result.stdout, result.stdout


# ---------------------------------------------------------------------------
# Custom REVIEW_STATE_DIR (the RED6-2 regression): the disabled marker lives ONLY
# in the custom dir, matching what run-ai-reviews.sh/review-gate.sh would have
# written under that same override. A doctor that hardcodes .omx/reviewer-state
# would find the (empty) default dir and print a false-green "no disabled
# reviewers recorded" here -- this must NOT happen.
# ---------------------------------------------------------------------------

def test_custom_review_state_dir_reports_disabled_reviewer_not_false_green(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    _init_git_repo(project)
    custom_dir = project / ".omx" / "custom-rs"
    custom_dir.mkdir(parents=True, exist_ok=True)
    (custom_dir / "gemini.disabled").write_text(MARKER_BODY, encoding="utf-8")

    # The default dir exists but is empty -- exactly the false-green trap: a doctor
    # that ignores REVIEW_STATE_DIR looks here, finds nothing, and reports "clean".
    default_dir = project / ".omx" / "reviewer-state"
    default_dir.mkdir(parents=True, exist_ok=True)

    env = _base_env(review_state_dir=".omx/custom-rs")
    result = _run(["--project"], cwd=project, env=env)

    assert "reviewer disabled: gemini" in result.stdout, result.stdout
    assert "no disabled reviewers recorded" not in result.stdout, result.stdout


def test_custom_review_state_dir_with_no_markers_is_clean_pass(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    _init_git_repo(project)
    custom_dir = project / ".omx" / "custom-rs"
    custom_dir.mkdir(parents=True, exist_ok=True)

    env = _base_env(review_state_dir=".omx/custom-rs")
    result = _run(["--project"], cwd=project, env=env)

    assert "no disabled reviewers recorded" in result.stdout, result.stdout
