"""RED2-1 (2026-07-07 R1 red-team, CRITICAL/LIVE) — scripts/verify.sh's run_product fail-closed
guard previously checked only SHAPE (empty / unparseable / no-executable-content) of a project's
scripts/verify-project.sh, never SUBSTANCE. A verifier that runs ONLY static checks
(py_compile/xmllint style) and never invokes a real runtime oracle (e.g. the Odoo docker harness)
was non-empty, parsed, and exited 0 -- so it read as full green identically to a verifier that
actually booted a runtime and exercised it. docs/ops-audits/2026-07-07-spec-v2.md (IP-1'/AC1-5)
names this exact content-blindness as the root cause of a real incident: a static-only-green
verify-project.sh let an infinite-recursion commit reach origin and kill the odoo.sh build.

Contract under test (see the comment block above the oracle-check in run_product,
scripts/verify.sh): a project verifier that actually exercised a runtime oracle prints, on its
own stdout/stderr, a line matching:

    [verify-project] RUNTIME_ORACLE=<state>[:<detail>]

<state> is `passed` (optionally `passed:<harness-version>`) when a real harness ran and passed;
anything else (`absent`, `skipped`, `docker-down`, or no such line at all) means no runtime
oracle was confirmed. verify.sh reads the LAST such line in the verifier's captured output and:
  - no match / state != passed(:*)  -> LOUD `NOT-VALIDATED (runtime oracle did not run)`.
    Advisory (exit 0) by default; fails CLOSED with exit 3 when
    AI_AUTO_REQUIRE_RUNTIME_ORACLE=1 is set (the project/domain-pack opting in to require it).
  - state == passed(:*) -> full green, no degradation.

HONEST LIMIT (D2): this is a SIGNAL contract, not a forgery-proof one. A same-UID verifier can
print the passed marker without ever touching Docker/odoo-bin -- this seam makes static-only
masquerading DETECTABLE, it does not make forging the marker impossible (that needs an
out-of-band auditor, spec AC1-7, out of scope here). test_runtime_oracle_marker_is_same_uid_forgeable
below documents that limit as a NEGATIVE-knowledge fixture, mirroring spec AC1-6.

These tests build small, hermetic fixture "project" directories (their own throwaway git repos
under pytest's tmp_path) -- never touching the real shared worktree -- and drive the real
scripts/verify.sh as a subprocess with AI_AUTO_VERIFY_SCOPE=product, matching the pattern used by
tests/test_doctor_bootstrap_ip2.py for other scripts/*.sh seams.
"""
import os
import stat
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "scripts" / "verify.sh"

STATIC_ONLY_VERIFIER = """#!/usr/bin/env bash
set -euo pipefail
echo "[verify-project] running static checks only (py_compile/xmllint-style)"
python3 -c "print('static check ok')"
exit 0
"""

RUNTIME_ORACLE_PASSED_VERIFIER = """#!/usr/bin/env bash
set -euo pipefail
echo "[verify-project] booting fake runtime harness..."
echo "[verify-project] RUNTIME_ORACLE=passed:fake-harness-1.0"
exit 0
"""

RUNTIME_ORACLE_SKIPPED_VERIFIER = """#!/usr/bin/env bash
set -euo pipefail
echo "[verify-project] docker unavailable, skipping runtime harness"
echo "[verify-project] RUNTIME_ORACLE=docker-down"
exit 0
"""

FAILING_VERIFIER = """#!/usr/bin/env bash
set -euo pipefail
echo "[verify-project] running static checks only"
exit 1
"""

FORGED_PASS_VERIFIER = """#!/usr/bin/env bash
set -euo pipefail
# Same-UID forgery: prints the passed marker WITHOUT ever running a harness.
echo "[verify-project] RUNTIME_ORACLE=passed:never-ran-anything"
exit 0
"""


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


def _make_project(tmp_path: Path, name: str, verifier_body: str) -> Path:
    project = tmp_path / name
    _init_git_repo(project)
    scripts_dir = project / "scripts"
    scripts_dir.mkdir(parents=True, exist_ok=True)
    vp = scripts_dir / "verify-project.sh"
    vp.write_text(verifier_body, encoding="utf-8")
    _make_executable(vp)
    return project


def _run_verify(project: Path, *, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["AI_AUTO_VERIFY_SCOPE"] = "product"
    # Hermetic: never let a stray AI_AUTO_REQUIRE_RUNTIME_ORACLE from the outer environment
    # leak into a test that doesn't explicitly set it.
    env.pop("AI_AUTO_REQUIRE_RUNTIME_ORACLE", None)
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        ["bash", str(VERIFY)],
        cwd=project,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def test_static_only_verifier_is_advisory_not_validated_by_default(tmp_path: Path) -> None:
    project = _make_project(tmp_path, "static-only", STATIC_ONLY_VERIFIER)
    result = _run_verify(project)
    # Default (no opt-in) is ADVISORY: does not regress every project that has no runtime-oracle
    # need at all -- but it MUST be loudly detectable, not a silent green no-op.
    assert result.returncode == 0, result.stdout
    assert "NOT-VALIDATED (runtime oracle did not run)" in result.stdout, result.stdout


def test_static_only_verifier_fails_closed_when_runtime_oracle_required(tmp_path: Path) -> None:
    project = _make_project(tmp_path, "static-only-required", STATIC_ONLY_VERIFIER)
    result = _run_verify(project, extra_env={"AI_AUTO_REQUIRE_RUNTIME_ORACLE": "1"})
    # This is the headline-defect fixture: a verify-project.sh that ONLY runs
    # py_compile-style static checks and never touches a runtime oracle must NOT be full
    # green when the oracle is required -- distinct exit code (3), not the generic 1 used
    # for a structurally-empty/absent verifier and not a clean 0.
    assert result.returncode == 3, result.stdout
    assert "NOT-VALIDATED (runtime oracle did not run)" in result.stdout, result.stdout
    assert "fail CLOSED" in result.stdout, result.stdout


def test_runtime_oracle_skipped_state_is_also_not_validated(tmp_path: Path) -> None:
    project = _make_project(tmp_path, "oracle-skipped", RUNTIME_ORACLE_SKIPPED_VERIFIER)
    result = _run_verify(project, extra_env={"AI_AUTO_REQUIRE_RUNTIME_ORACLE": "1"})
    assert result.returncode == 3, result.stdout
    assert "docker-down" in result.stdout, result.stdout


def test_runtime_oracle_passed_marker_is_full_green_even_when_required(tmp_path: Path) -> None:
    project = _make_project(tmp_path, "oracle-passed", RUNTIME_ORACLE_PASSED_VERIFIER)
    result = _run_verify(project, extra_env={"AI_AUTO_REQUIRE_RUNTIME_ORACLE": "1"})
    assert result.returncode == 0, result.stdout
    assert "runtime oracle signal: PASSED (passed:fake-harness-1.0)" in result.stdout, result.stdout
    assert "NOT-VALIDATED" not in result.stdout, result.stdout


def test_verifier_own_failure_still_propagates_unchanged(tmp_path: Path) -> None:
    # The oracle check must never mask or relabel a real verifier failure -- that exit code
    # (1 here) must pass straight through, same as before this fix.
    project = _make_project(tmp_path, "verifier-fails", FAILING_VERIFIER)
    result = _run_verify(project, extra_env={"AI_AUTO_REQUIRE_RUNTIME_ORACLE": "1"})
    assert result.returncode == 1, result.stdout
    assert "NOT-VALIDATED" not in result.stdout, result.stdout


def test_runtime_oracle_marker_is_same_uid_forgeable_documented_limit(tmp_path: Path) -> None:
    # Negative-knowledge fixture (spec AC1-6 / D2 honest limit): the contract is a SIGNAL, not
    # a proof. A same-UID verifier that prints the passed marker WITHOUT running any harness is
    # NOT rejected by this tool-side seam -- documenting that this is detectable-by-an-
    # out-of-band-auditor-only, not prevented here.
    project = _make_project(tmp_path, "forged-pass", FORGED_PASS_VERIFIER)
    result = _run_verify(project, extra_env={"AI_AUTO_REQUIRE_RUNTIME_ORACLE": "1"})
    assert result.returncode == 0, result.stdout
    assert "runtime oracle signal: PASSED" in result.stdout, result.stdout
