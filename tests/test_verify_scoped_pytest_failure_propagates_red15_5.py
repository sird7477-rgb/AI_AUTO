"""RED15-5 (2026-07-07 R7 ops-defense re-attack, CRITICAL) --
.ops-game/R7-red15-reattack.md: scripts/verify-project.sh's run_product_pytest used to be a
bare `.venv/bin/python -m pytest -q tests/test_app.py` relying on `set -e` (errexit) to abort
the caller on failure. That is unsafe specifically because run_scoped_product_verification
(the function that calls run_product_pytest on the "known product scope" fast-path -- the path
scripts/review-gate.sh actually takes on EVERY gate run, since it sets
AI_AUTO_VERIFY_DIFF_SCOPE=1 unconditionally) is itself invoked at the bottom of the file as
`run_scoped_product_verification || scoped_rc=$?`. Per bash's documented errexit-under-`||`
semantics, that disables `set -e` for run_scoped_product_verification's ENTIRE nested call
tree (including the bare pytest call several function-calls deep) for the duration of that one
invocation. A genuinely failing product pytest therefore did NOT abort: execution fell straight
through to run_product_smoke, which (if the docker smoke passed on its own independent merits)
legitimately printed `[verify-project] success` / `RUNTIME_ORACLE=passed:ai-lab-app-smoke` and
the whole script exited 0 -- a real, non-adversarial product regression silently discarded, no
forgery needed.

Fix (already applied to scripts/verify-project.sh, verified by this file): run_product_pytest
now explicitly captures its own exit status via `set +e; ...; rc=$?; set -e` (correct
regardless of the caller's ambient errexit state) and returns it, treating pytest's own exit 5
("no tests collected") as non-fatal (return 0) -- mirroring hooks/pre-commit's
pre_commit_run_pytest convention -- while any other nonzero rc (a real failure) propagates.
run_scoped_product_verification now calls it as `run_product_pytest || pytest_rc=$?` and, on a
nonzero pytest_rc, returns that rc IMMEDIATELY, before run_product_smoke ever runs.

Non-vacuousness / revert-FAIL proof (see the session's final report for the exact transcript):
temporarily reverting just the two hunks in scripts/verify-project.sh back to the pre-fix
shape (bare `run_product_pytest` call in run_scoped_product_verification, bare pytest
invocation with no rc capture in run_product_pytest) makes
test_scoped_known_product_scope_real_pytest_failure_blocks_before_smoke FAIL: the script exits
0 and prints RUNTIME_ORACLE=passed even though the fake pytest simulated a real failure --
reproducing RED15-5 exactly. Restoring the fix makes it pass again.

Fixture pattern (fake docker/curl on PATH, fake `.venv/bin/python` standing in for pytest, real
scripts/verify-project.sh driven as a subprocess) mirrors
tests/test_slug_hash_and_oracle_dogfood_r6.py's `_fake_bin` / `_make_verify_project_fixture` /
`_run_verify_project` helpers and tests/test_verify_seam_runtime_ip1.py's fixture-project style.
"""
from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERIFY_PROJECT = ROOT / "scripts" / "verify-project.sh"


def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _fake_bin(tmp_path: Path, *, docker_ok: bool) -> Path:
    """Hermetic fake `docker` + `curl` on PATH -- no real daemon/network is ever touched.
    docker_ok=True makes every docker subcommand (info / compose up / compose ps / compose
    down) succeed unconditionally, simulating a real, reachable docker daemon whose smoke test
    would legitimately pass ON ITS OWN MERITS -- this is deliberate: it proves a blocked run is
    blocked by the pytest-failure guard, not merely because docker also happened to fail."""
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text(
        "#!/usr/bin/env bash\n" + ("exit 0\n" if docker_ok else "exit 1\n"),
        encoding="utf-8",
    )
    _make_executable(docker)
    curl = bin_dir / "curl"
    curl.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    _make_executable(curl)
    return bin_dir


def _make_verify_project_fixture(tmp_path: Path, name: str, *, pytest_rc: int) -> Path:
    """A minimal fixture project directory: fake `.venv/bin/python` standing in for pytest
    (hardcoded to exit `pytest_rc` when invoked as `-m pytest ...`, mirroring a real pytest run
    without needing a real venv/pytest/test suite) + a placeholder tests/test_app.py."""
    project = tmp_path / name
    venv_bin = project / ".venv" / "bin"
    venv_bin.mkdir(parents=True)
    python = venv_bin / "python"
    python.write_text(
        "#!/usr/bin/env bash\n"
        "if [ \"${1:-}\" = \"-m\" ] && [ \"${2:-}\" = \"pytest\" ]; then\n"
        f"  echo '[fake pytest] simulating a real product-test run, exit {pytest_rc}'\n"
        f"  exit {pytest_rc}\n"
        "fi\n"
        "exit 0\n",
        encoding="utf-8",
    )
    _make_executable(python)
    tests_dir = project / "tests"
    tests_dir.mkdir()
    (tests_dir / "test_app.py").write_text("# fixture placeholder\n", encoding="utf-8")
    return project


def _run_verify_project(
    project: Path, fake_bin: Path, *, env_extra: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
    env.pop("AI_AUTO_VERIFY_DIFF_SCOPE", None)
    env.pop("AI_AUTO_VERIFY_CHANGED_PATHS", None)
    env.pop("AI_AUTO_VERIFY_INJECT_SCOPED_FAILURE", None)
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["bash", str(VERIFY_PROJECT)],
        cwd=project,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


# ==========================================================================
# RED15-5 -- scoped ("known product scope") path
# ==========================================================================
def test_scoped_known_product_scope_real_pytest_failure_blocks_before_smoke(tmp_path):
    """THE headline RED15-5 fixture. A real (simulated) product pytest failure on the scoped
    fast-path (AI_AUTO_VERIFY_DIFF_SCOPE=1, changed path in the known product-scope set) must:
      1. make the whole script exit NONZERO (matching pytest's own exit code), and
      2. NEVER print RUNTIME_ORACLE=passed -- even though docker is faked to succeed, so the
         smoke test WOULD have passed on its own merits had it been reached.
    Before the fix this printed RUNTIME_ORACLE=passed and exited 0 (the exact RED15-5 bug)."""
    project = _make_verify_project_fixture(tmp_path, "proj-scoped-pytest-fails", pytest_rc=1)
    fake_bin = _fake_bin(tmp_path, docker_ok=True)

    result = _run_verify_project(
        project,
        fake_bin,
        env_extra={
            "AI_AUTO_VERIFY_DIFF_SCOPE": "1",
            "AI_AUTO_VERIFY_CHANGED_PATHS": "app.py\n",
        },
    )

    assert result.returncode == 1, result.stdout
    assert "RUNTIME_ORACLE=passed" not in result.stdout, result.stdout
    assert "[verify-project] success" not in result.stdout, result.stdout
    assert "starting docker compose" not in result.stdout, result.stdout
    assert "product pytest FAILED" in result.stdout, result.stdout


def test_scoped_known_product_scope_passing_pytest_still_reaches_smoke(tmp_path):
    """A genuinely passing scoped pytest must still proceed to the docker smoke test and emit
    the passed marker -- the fix must not accidentally block the good path too."""
    project = _make_verify_project_fixture(tmp_path, "proj-scoped-pytest-passes", pytest_rc=0)
    fake_bin = _fake_bin(tmp_path, docker_ok=True)

    result = _run_verify_project(
        project,
        fake_bin,
        env_extra={
            "AI_AUTO_VERIFY_DIFF_SCOPE": "1",
            "AI_AUTO_VERIFY_CHANGED_PATHS": "app.py\n",
        },
    )

    assert result.returncode == 0, result.stdout
    assert "[verify-project] RUNTIME_ORACLE=passed:ai-lab-app-smoke" in result.stdout, result.stdout
    assert "[verify-project] success" in result.stdout, result.stdout


def test_scoped_known_product_scope_no_tests_collected_is_non_fatal(tmp_path):
    """pytest's own exit 5 ("no tests were collected") must NOT be treated as a failure -- it
    must still proceed to the docker smoke test and emit the passed marker, matching
    hooks/pre-commit's pre_commit_run_pytest convention for a test-less run."""
    project = _make_verify_project_fixture(tmp_path, "proj-scoped-pytest-no-tests", pytest_rc=5)
    fake_bin = _fake_bin(tmp_path, docker_ok=True)

    result = _run_verify_project(
        project,
        fake_bin,
        env_extra={
            "AI_AUTO_VERIFY_DIFF_SCOPE": "1",
            "AI_AUTO_VERIFY_CHANGED_PATHS": "app.py\n",
        },
    )

    assert result.returncode == 0, result.stdout
    assert "pytest collected no tests (exit 5); nothing to gate, not blocking" in result.stdout, result.stdout
    assert "[verify-project] RUNTIME_ORACLE=passed:ai-lab-app-smoke" in result.stdout, result.stdout


# ==========================================================================
# RED15-5 -- unscoped / full ("mapping unknown" fallback, or no diff-scope at all) path
# ==========================================================================
def test_unscoped_full_path_real_pytest_failure_still_propagates(tmp_path):
    """Regression guard for the bottom-of-file caller (`run_product_pytest;
    run_product_smoke`, reached when AI_AUTO_VERIFY_DIFF_SCOPE is unset/0): this path was
    already a bare top-level call under normal (non-suppressed) errexit, so it should already
    propagate correctly -- this test proves the fix didn't regress it and that no OTHER path
    silently swallows a real failure here either."""
    project = _make_verify_project_fixture(tmp_path, "proj-unscoped-pytest-fails", pytest_rc=1)
    fake_bin = _fake_bin(tmp_path, docker_ok=True)

    result = _run_verify_project(project, fake_bin)

    assert result.returncode != 0, result.stdout
    assert "RUNTIME_ORACLE=passed" not in result.stdout, result.stdout
