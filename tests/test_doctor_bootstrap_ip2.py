"""SPEC IP-2' AC2-1' — `automation-doctor.sh --bootstrap` is a strict, opt-in detector
for gate/harness wiring presence, with an ENUMERATED required set (red-review D9). It must
NOT change the existing `--project` warn-only semantics (an early-stage/un-migrated project
directory is legitimately absent all framework files and must not be fail-closed there).

These tests build small, hermetic fixture "project" directories (their own throwaway git
repos under pytest's tmp_path) -- never touching the real shared worktree -- and drive
`scripts/automation-doctor.sh` as a subprocess, matching the pattern used by
tests/test_docker_config_guard.py for other scripts/*.sh doctor-adjacent seams.
"""
import os
import stat
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCTOR = ROOT / "scripts" / "automation-doctor.sh"


def _run(args: list[str], *, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(DOCTOR), *args],
        cwd=cwd,
        env=os.environ.copy(),
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


def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _make_fake_engine(engine_dir: Path, *, with_review_gate: bool, with_session_lock: bool) -> None:
    """A minimal fake 'engine' checkout: only the pieces run_bootstrap_check inspects."""
    hooks_dir = engine_dir / "hooks"
    scripts_dir = engine_dir / "scripts"
    hooks_dir.mkdir(parents=True, exist_ok=True)
    scripts_dir.mkdir(parents=True, exist_ok=True)

    pre_push = hooks_dir / "pre-push"
    pre_push.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    _make_executable(pre_push)

    if with_review_gate:
        review_gate = scripts_dir / "review-gate.sh"
        review_gate.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        _make_executable(review_gate)

    if with_session_lock:
        session_lock = scripts_dir / "session-lock.sh"
        session_lock.write_text("#!/usr/bin/env bash\n:\n", encoding="utf-8")
        _make_executable(session_lock)


def _install_shim(project: Path, engine_dir: Path) -> None:
    """Hand-write a pre-push shim matching the exact marker/format
    run_bootstrap_check (and check_project_globalization) parse: the literal string
    'AI_AUTO shim' somewhere in the file, and a line `AI_AUTO_HOME="<path>"`.
    """
    hooks_dir = project / ".git" / "hooks"
    hooks_dir.mkdir(parents=True, exist_ok=True)
    shim = hooks_dir / "pre-push"
    shim.write_text(
        "#!/usr/bin/env bash\n"
        "# AI_AUTO shim -- baked engine path (do not edit)\n"
        f'AI_AUTO_HOME="{engine_dir}"\n'
        "exit 0\n",
        encoding="utf-8",
    )
    _make_executable(shim)


def _install_verify_project(project: Path) -> None:
    verify_project = project / "scripts"
    verify_project.mkdir(parents=True, exist_ok=True)
    vp = verify_project / "verify-project.sh"
    vp.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    _make_executable(vp)


# ---------------------------------------------------------------------------
# --bootstrap: complete fixture -> exit 0
# ---------------------------------------------------------------------------

def test_bootstrap_complete_fixture_exits_zero(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    engine = tmp_path / "engine"
    _init_git_repo(project)
    _make_fake_engine(engine, with_review_gate=True, with_session_lock=True)
    _install_shim(project, engine)
    _install_verify_project(project)

    result = _run(["--bootstrap"], cwd=project)

    assert result.returncode == 0, result.stdout
    assert "MISSING required gate/harness wiring" not in result.stdout
    assert "all required gate/harness wiring present" in result.stdout


# ---------------------------------------------------------------------------
# --bootstrap: each required item, independently absent -> non-zero, named
# ---------------------------------------------------------------------------

def test_bootstrap_missing_hook_shim_fails_and_names_it(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    _init_git_repo(project)
    _install_verify_project(project)
    # No pre-push shim installed at all -- the root-cause condition (D1/D3): a worktree
    # with zero gate wiring where a push proceeds with nothing automated running.

    result = _run(["--bootstrap"], cwd=project)

    assert result.returncode != 0, result.stdout
    assert "pre-push hook shim not installed" in result.stdout


def test_bootstrap_missing_review_gate_entrypoint_fails_and_names_it(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    engine = tmp_path / "engine"
    _init_git_repo(project)
    _make_fake_engine(engine, with_review_gate=False, with_session_lock=True)
    _install_shim(project, engine)
    _install_verify_project(project)

    result = _run(["--bootstrap"], cwd=project)

    assert result.returncode != 0, result.stdout
    assert "review-gate entrypoint not reachable" in result.stdout
    # the OTHER three required items are independently satisfied and must still pass
    assert "session-lock.sh not reachable" not in result.stdout
    assert "verify seam missing" not in result.stdout


def test_bootstrap_missing_session_lock_fails_and_names_it(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    engine = tmp_path / "engine"
    _init_git_repo(project)
    _make_fake_engine(engine, with_review_gate=True, with_session_lock=False)
    _install_shim(project, engine)
    _install_verify_project(project)

    result = _run(["--bootstrap"], cwd=project)

    assert result.returncode != 0, result.stdout
    assert "session-lock.sh not reachable" in result.stdout
    assert "review-gate entrypoint not reachable" not in result.stdout


def test_bootstrap_missing_verify_seam_fails_and_names_it(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    engine = tmp_path / "engine"
    _init_git_repo(project)
    _make_fake_engine(engine, with_review_gate=True, with_session_lock=True)
    _install_shim(project, engine)
    # No scripts/verify-project.sh in the project.

    result = _run(["--bootstrap"], cwd=project)

    assert result.returncode != 0, result.stdout
    assert "verify seam missing or not executable: scripts/verify-project.sh" in result.stdout


# ---------------------------------------------------------------------------
# D9 regression: default/--project mode semantics are UNCHANGED by --bootstrap's
# existence -- the SAME absent wiring that fails --bootstrap must remain a
# non-blocking WARN (exit 0) in --project mode.
# ---------------------------------------------------------------------------

def test_project_mode_stays_warn_only_on_the_same_absence(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    _init_git_repo(project)
    # Same fixture as test_bootstrap_missing_hook_shim_fails_and_names_it: no hook shim,
    # no verify-project.sh. --project must still treat this as legitimate/early-stage.

    result = _run(["--project"], cwd=project)

    assert result.returncode == 0, result.stdout
    assert "MISSING required gate/harness wiring" not in result.stdout
    assert "[warn]" in result.stdout


def test_bootstrap_flag_appears_in_help(tmp_path: Path) -> None:
    result = _run(["--help"], cwd=tmp_path)

    assert result.returncode == 0, result.stdout
    assert "--bootstrap" in result.stdout
