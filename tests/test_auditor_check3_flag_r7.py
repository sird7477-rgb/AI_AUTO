"""R7 (RED13-4 re-attack fix): CHECK3-RUNTIME-ORACLE must FLAG (not SKIP) an ABSENT/stripped
verify-output log when AI_AUTO_REQUIRE_RUNTIME_ORACLE=1 is set.

Evidence: .ops-game/R6-red13-reattack.md, "RED13-4 -- CHECK3-RUNTIME-ORACLE's SKIP path is
attacker-controllable: deleting the verify-output log silently erases a would-be HIGH even
under AI_AUTO_REQUIRE_RUNTIME_ORACLE=1". scripts/ai-auto-audit.sh's `check_runtime_oracle`
had an unconditional `if [ ! -f "${VERIFY_OUTPUT_FILE}" ]; then skip_check ...` that never
consulted AI_AUTO_REQUIRE_RUNTIME_ORACLE at all, unlike the NOT-VALIDATED branch below it --
so a same-UID actor (or a broken run) that deletes the log makes the runtime-oracle check
disappear as a SKIP instead of failing closed as a HIGH FLAG, defeating the point of the
required-oracle opt-in.

This module mirrors tests/test_ai_auto_audit_r5.py's fixture/helper idiom exactly (same
`_base_env`/`_init_repo`/`_commit`/`_record_proceed_binding`/`_record_history_entry`/
`_run_audit` helpers, duplicated here rather than imported since r5's module has no public
import surface and per-file hermetic fixtures are the established pattern in this test suite).

Covers two REQUIRE-gated "no evidence" shapes in `check_runtime_oracle`:
  1. the verify-output log file is entirely ABSENT (deleted, or verify never wrote it) --
     the RED13-4 finding itself.
  2. the log file is PRESENT but has had its `RUNTIME_ORACLE=` line stripped/truncated out
     (no NOT-VALIDATED signal either) -- the sibling SKIP branch a few lines below the first,
     same "no evidence the oracle ran" shape, same missing REQUIRE-gate bug, fixed the same way.
For each: under REQUIRE=1 -> FLAG (HIGH), nonzero exit. Without REQUIRE -> SKIP, exit 0
(unchanged, matches test_no_verify_output_log_skips_runtime_oracle_check in r5).
"""

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "scripts" / "ai-auto-audit.sh"


def _git(args: list[str], cwd: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _init_repo(path: Path, env: dict[str, str]) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git(["init", "-q", "-b", "main"], path, env)
    _git(["config", "user.email", "t@example.invalid"], path, env)
    _git(["config", "user.name", "T"], path, env)
    (path / ".gitignore").write_text(".omx/\n", encoding="utf-8")


def _commit(path: Path, env: dict[str, str], filename: str, content: str, message: str) -> str:
    (path / filename).write_text(content, encoding="utf-8")
    _git(["add", "-A"], path, env)
    _git(["commit", "-q", "-m", message], path, env)
    return _git(["rev-parse", "HEAD"], path, env).stdout.strip()


def _base_env(tmp_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["AI_AUTO_HOME"] = str(ROOT)
    env["AI_AUTO_GIT_HARDEN_SH"] = str(ROOT / "scripts" / "git-harden.sh")
    env["AI_AUTO_REVIEW_GATE_BINDING_SH"] = str(ROOT / "scripts" / "review-gate-binding.sh")
    env["AI_AUTO_RUN_AI_REVIEWS_SH"] = str(ROOT / "scripts" / "run-ai-reviews.sh")
    home = tmp_path / "home"
    home.mkdir(parents=True, exist_ok=True)
    env["HOME"] = str(home)
    env["AI_AUTO_PROVENANCE_KEY_FILE"] = str(tmp_path / "provenance.key")
    # Hermetic: never let a stray AI_AUTO_REQUIRE_RUNTIME_ORACLE from the outer environment
    # leak into the "not required" control runs below.
    env.pop("AI_AUTO_REQUIRE_RUNTIME_ORACLE", None)
    return env


def _record_proceed_binding(project: Path, env: dict[str, str]) -> None:
    script = (
        f". '{ROOT / 'scripts' / 'git-harden.sh'}'; "
        f". '{ROOT / 'scripts' / 'review-gate-binding.sh'}'; "
        "review_binding_record proceed normal test-verdict.md"
    )
    subprocess.run(
        ["bash", "-c", script],
        cwd=project,
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _record_history_entry(project: Path, head_sha: str, verdict: str = "proceed") -> None:
    omx = project / ".omx"
    omx.mkdir(parents=True, exist_ok=True)
    with (omx / "review-history.log").open("a", encoding="utf-8") as fh:
        fh.write(
            '{"ts":"2026-07-07T00:00:00+00:00","head_sha":"%s","verdict":"%s","reason":"","source":"review-gate"}\n'
            % (head_sha, verdict)
        )


def _run_audit(project: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(AUDIT), str(project)],
        env=env,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )


def _setup_gated_project(tmp_path: Path, env: dict[str, str]) -> Path:
    """A project with a genuine proceed binding + matching history entry, so CHECK1/CHECK2/
    CHECK5 all PASS and only CHECK3-RUNTIME-ORACLE can be responsible for the exit code."""
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")
    _record_proceed_binding(project, env)
    _record_history_entry(project, head_sha, "proceed")
    return project


# ---------------------------------------------------------------------------------------------
# 1. RED13-4 core finding: verify-output log file entirely ABSENT.
#    Under AI_AUTO_REQUIRE_RUNTIME_ORACLE=1 -> FLAG (HIGH), nonzero exit (was SKIP + exit 0).
#    Without the require flag -> SKIP, exit 0 (unchanged from r5's existing coverage).
# ---------------------------------------------------------------------------------------------
def test_absent_verify_output_log_flags_high_when_required(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = _setup_gated_project(tmp_path, env)

    # No .omx/review-context/latest-verify-output.txt is ever written for this project.
    assert not (project / ".omx" / "review-context" / "latest-verify-output.txt").exists()

    env_required = dict(env)
    env_required["AI_AUTO_REQUIRE_RUNTIME_ORACLE"] = "1"
    result = _run_audit(project, env_required)

    assert result.returncode != 0, (
        f"expected a nonzero exit for an absent verify-output log under REQUIRE=1:\n{result.stdout}"
    )
    assert "CHECK3-RUNTIME-ORACLE" in result.stdout
    assert "FLAG (HIGH)" in result.stdout
    assert "no evidence" in result.stdout

    # Control: WITHOUT the require flag, the identical absent log is still just a SKIP, exit 0
    # -- a project that never opted into the contract must not be penalized (non-vacuousness +
    # no-regression on the existing r5 behavior).
    result_default = _run_audit(project, env)
    assert result_default.returncode == 0, (
        f"unexpected nonzero exit without the opt-in:\n{result_default.stdout}"
    )
    assert "CHECK3-RUNTIME-ORACLE" in result_default.stdout
    assert "SKIP" in result_default.stdout


# ---------------------------------------------------------------------------------------------
# 2. Sibling gap: verify-output log PRESENT but its RUNTIME_ORACLE= line stripped/truncated out
#    (no NOT-VALIDATED signal either) -- same "no evidence" shape as #1, same fix.
# ---------------------------------------------------------------------------------------------
def test_verify_output_log_without_oracle_line_flags_high_when_required(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = _setup_gated_project(tmp_path, env)

    context_dir = project / ".omx" / "review-context"
    context_dir.mkdir(parents=True, exist_ok=True)
    (context_dir / "latest-verify-output.txt").write_text(
        "some unrelated verify output, no RUNTIME_ORACLE= line at all\n",
        encoding="utf-8",
    )

    env_required = dict(env)
    env_required["AI_AUTO_REQUIRE_RUNTIME_ORACLE"] = "1"
    result = _run_audit(project, env_required)

    assert result.returncode != 0, (
        f"expected a nonzero exit for a log with no RUNTIME_ORACLE= line under REQUIRE=1:\n{result.stdout}"
    )
    assert "CHECK3-RUNTIME-ORACLE" in result.stdout
    assert "FLAG (HIGH)" in result.stdout
    assert "no evidence" in result.stdout

    # Control: without the require flag, the identical log is still just a SKIP, exit 0.
    result_default = _run_audit(project, env)
    assert result_default.returncode == 0, (
        f"unexpected nonzero exit without the opt-in:\n{result_default.stdout}"
    )
    assert "CHECK3-RUNTIME-ORACLE" in result_default.stdout
    assert "SKIP" in result_default.stdout
