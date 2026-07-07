"""R6 ops-defense game (BLUE) fixes for two findings in
.ops-game/R5-red11-reattack.md:

  RED11-4  validation-harness/harness-slug.sh: `harness_proj_slug`'s disambiguating
           hash was POSIX `cksum` -- a 32-bit, non-cryptographic CRC. A birthday
           search found a genuine collision after ~72k random trials (in line with
           the textbook ~65k bound for a true 32-bit space), and CRCs are
           additionally linear/algebraically forgeable for a CHOSEN target. Fixed
           by deriving the hash from `sha256sum` instead (first 12 lowercase hex
           chars of a cryptographic 256-bit digest kept, well beyond cksum's raw 32
           bits), while preserving every RED3-4/RED7-2 property: sibling `git
           worktree` checkouts of ONE repo still share a slug (same
           `--git-common-dir` identity); different repos still differ; the hash
           still survives the trailing `cut -c1-40` even when the cosmetic $tail is
           long (hash placed immediately after the "h-" prefix); the slug is still
           a valid docker-compose project name ([a-z][a-z0-9-]*, <=40 chars).

  RED7-4 / RED12 dogfood  scripts/verify.sh's run_product reads a
           `[verify-project] RUNTIME_ORACLE=<state>[:<detail>]` marker on the
           project verifier's own captured output to distinguish "a real runtime
           oracle ran and passed" from "verifier only did static checks" (see the
           comment block above the oracle-check in scripts/verify.sh). Before this
           fix, ai-lab's OWN scripts/verify-project.sh -- despite genuinely
           bringing up a docker-compose flask+postgres app and hitting its
           endpoints -- never emitted that marker, so the contract was INERT even
           when dogfooded on the engine repo itself. Fixed by emitting
           `RUNTIME_ORACLE=passed:ai-lab-app-smoke` once the docker-compose smoke
           test has actually run to completion and succeeded, `RUNTIME_ORACLE=
           docker-down` when docker itself is unavailable (binary missing or
           daemon unreachable, so the smoke test is skipped instead of crashing on
           a raw docker error), and `RUNTIME_ORACLE=skipped` on the docs/plans-only
           scoped fast-path where skipping the smoke test is a deliberate, correct
           scope decision. No existing assertion (pytest, curl endpoint checks,
           docker compose ps/logs) was loosened -- only the marker line was added.

These tests build small, hermetic fixture git repos / fake "project" directories
under pytest's tmp_path (never touching the real shared worktree) and drive the
real scripts as subprocesses, matching the pattern used by
tests/test_slug_and_scope_r4.py (harness-slug) and
tests/test_odoo_harness_honesty_r2.py (no-op fake `docker` on PATH) and
tests/test_verify_seam_runtime_ip1.py (RUNTIME_ORACLE marker contract).

Non-vacuousness: each assertion here targets behavior that is only true of the
FIXED script content. Manually reverting to the pre-fix content (available via
`git show HEAD:<path>`, since these edits are uncommitted in this worktree at
authoring time) makes the corresponding assertion fail -- see the session's final
report for the revert/rerun proof for each test.
"""
from __future__ import annotations

import hashlib
import os
import re
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
HARNESS_SLUG = ODOO_PACK / "validation-harness" / "harness-slug.sh"
VERIFY_PROJECT = ROOT / "scripts" / "verify-project.sh"

DOCKER_NAME_RE = re.compile(r"^[a-z][a-z0-9-]{0,39}$")


# --------------------------------------------------------------------------
# shared fixture helpers
# --------------------------------------------------------------------------
def _git(args: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args], cwd=cwd, text=True, capture_output=True, check=check
    )


def _init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git(["init", "-q"], path)
    _git(["config", "user.email", "t@example.invalid"], path)
    _git(["config", "user.name", "T"], path)


def _commit_all(path: Path, message: str) -> str:
    _git(["add", "-A"], path)
    _git(["commit", "-q", "-m", message], path)
    return _git(["rev-parse", "HEAD"], path).stdout.strip()


def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _slug_of(project_dir: Path) -> str:
    cmd = f'. "{HARNESS_SLUG}"; harness_proj_slug "{project_dir}"'
    result = subprocess.run(
        ["bash", "-c", cmd], text=True, capture_output=True, check=True
    )
    return result.stdout.strip()


# ==========================================================================
# RED11-4 -- harness-slug.sh: sha256-derived hash, not cksum
# ==========================================================================
def test_slug_long_shared_prefix_basenames_still_do_not_collide(tmp_path):
    """RED7-2's original PoC shape must still hold with the new hash: two
    DIFFERENT repos whose sanitized basenames share a >=38-char common prefix
    must still get DIFFERENT slugs."""
    long_prefix = "this-is-a-very-long-organization-project-name-for-client"
    repo_a = tmp_path / f"{long_prefix}-ALPHA"
    repo_b = tmp_path / f"{long_prefix}-BETA"
    _init_repo(repo_a)
    (repo_a / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo_a, "init")
    _init_repo(repo_b)
    (repo_b / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo_b, "init")

    assert len(long_prefix) >= 38, "test setup bug: prefix too short"

    slug_a = _slug_of(repo_a)
    slug_b = _slug_of(repo_b)

    assert slug_a != slug_b, (
        f"two different repos with a long shared basename prefix collided to "
        f"one slug ({slug_a!r})"
    )


def test_slug_still_shares_across_worktrees_of_same_repo(tmp_path):
    """RED3-4 property must survive the hash-algorithm swap: sibling `git
    worktree` checkouts of ONE repo share one slug."""
    repo_a = tmp_path / "repoA"
    _init_repo(repo_a)
    (repo_a / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo_a, "init")
    _git(["branch", "wt2"], repo_a)
    wt2 = tmp_path / "repoA-wt2"
    _git(["worktree", "add", "-q", str(wt2), "wt2"], repo_a)

    slug_main = _slug_of(repo_a)
    slug_worktree = _slug_of(wt2)

    assert slug_main == slug_worktree, (slug_main, slug_worktree)


def test_slug_still_docker_name_valid_and_within_budget(tmp_path):
    """The sha256-based construction must still be a valid docker-compose
    project name (lowercase [a-z][a-z0-9-]*, <=40 chars) for both a short and a
    long-basename repo."""
    short_repo = tmp_path / "r"
    _init_repo(short_repo)
    (short_repo / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(short_repo, "init")

    long_repo = tmp_path / "this-is-a-very-long-organization-project-name-for-client-GAMMA"
    _init_repo(long_repo)
    (long_repo / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(long_repo, "init")

    for repo in (short_repo, long_repo):
        slug = _slug_of(repo)
        assert len(slug) <= 40, slug
        assert DOCKER_NAME_RE.match(slug), slug


def test_slug_two_different_repos_with_shared_basename_get_different_hashes(tmp_path):
    """Direct RED11-4 collision-path check: two DIFFERENT repos sharing the exact
    SAME basename (the realistic collision path named in the finding -- "backend",
    "app", "infra" recur across clients) but living under different parent
    directories (hence different git-common-dir IDENTITY) must get different
    slugs -- the hash portion must disambiguate them since $tail is identical."""
    repo_a = tmp_path / "clientA" / "backend"
    repo_b = tmp_path / "clientB" / "backend"
    _init_repo(repo_a)
    (repo_a / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo_a, "init")
    _init_repo(repo_b)
    (repo_b / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo_b, "init")

    slug_a = _slug_of(repo_a)
    slug_b = _slug_of(repo_b)

    assert slug_a.endswith("-backend")
    assert slug_b.endswith("-backend")
    assert slug_a != slug_b, (slug_a, slug_b)


def test_slug_hash_segment_is_sha256_derived_not_cksum(tmp_path):
    """Non-vacuous algorithm check: the 12-hex-char hash segment embedded in the
    slug must equal the first 12 hex chars of sha256(identity), NOT any function
    of cksum's decimal CRC. This directly distinguishes the fixed construction
    from the pre-fix `cksum`-based one -- reverting to cksum makes this fail
    because a 32-bit decimal cksum value zero-padded to 10 digits is never equal
    to a 12-char hex sha256 prefix for an arbitrary identity string (and even on
    the rare digit-only coincidence, the two algorithms diverge for any of the
    many identities used across this test file)."""
    repo = tmp_path / "hashcheck-repo"
    _init_repo(repo)
    (repo / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo, "init")

    # The harness hashes `git --git-common-dir`'s resolved absolute path, not the
    # worktree path itself -- resolve it the same way the script does so the
    # expected value is computed over the identical identity string.
    gcd = _git(
        ["rev-parse", "--path-format=absolute", "--git-common-dir"], repo
    ).stdout.strip()
    identity = str(Path(gcd).resolve())

    expected_hash = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:12]
    slug = _slug_of(repo)

    # slug shape is "h-<hash>-<tail>"
    assert slug.startswith(f"h-{expected_hash}-"), (
        f"slug {slug!r} does not start with the expected sha256-derived hash "
        f"segment h-{expected_hash}- ; this fails if the hash is still cksum-"
        f"derived (or any other algorithm) instead of sha256."
    )
    # Companion negative check: the hash segment must NOT look like a
    # zero-padded 10-digit cksum decimal value (the pre-fix shape).
    hash_segment = slug.split("-")[1]
    assert not re.fullmatch(r"[0-9]{10}", hash_segment), (
        f"hash segment {hash_segment!r} still looks like a cksum-shaped "
        f"10-digit decimal value -- regression to the pre-fix algorithm"
    )


# ==========================================================================
# RED7-4 / RED12 dogfood -- verify-project.sh emits RUNTIME_ORACLE
# ==========================================================================
def _fake_bin(tmp_path: Path, *, docker_ok: bool) -> Path:
    """A hermetic fake `docker` + `curl` on PATH, mirroring the no-op fake
    binary pattern from tests/test_odoo_harness_honesty_r2.py. `docker_ok=True`
    makes every docker subcommand (info/compose up/compose ps/compose down...)
    succeed unconditionally, simulating a real, reachable docker daemon.
    `docker_ok=False` makes every docker subcommand fail, simulating docker
    being uninstalled or its daemon unreachable -- no real daemon is ever
    touched either way."""
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


def _make_verify_project_fixture(tmp_path: Path, name: str) -> Path:
    """A minimal fixture project directory: fake `.venv/bin/python` (so
    run_product_pytest never needs a real venv/pytest) + a placeholder
    tests/test_app.py."""
    project = tmp_path / name
    venv_bin = project / ".venv" / "bin"
    venv_bin.mkdir(parents=True)
    python = venv_bin / "python"
    python.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
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


def test_verify_project_emits_passed_marker_on_full_docker_smoke_success(tmp_path):
    """The headline dogfood fixture: with docker "reachable" (faked), the
    unscoped full run (run_product_pytest + run_product_smoke) must emit
    RUNTIME_ORACLE=passed:ai-lab-app-smoke ONLY after the smoke test's own
    checks (docker compose up, readiness curl loop, endpoint curls, docker
    compose ps) have all run -- proving the RUNTIME_ORACLE contract is no
    longer inert on ai-lab's own verifier."""
    project = _make_verify_project_fixture(tmp_path, "proj-passed")
    fake_bin = _fake_bin(tmp_path, docker_ok=True)

    result = _run_verify_project(project, fake_bin)

    assert result.returncode == 0, result.stdout
    assert "[verify-project] RUNTIME_ORACLE=passed:ai-lab-app-smoke" in result.stdout, result.stdout
    assert "[verify-project] success" in result.stdout, result.stdout
    # the marker must come after the smoke test's own success line, not before
    success_idx = result.stdout.index("[verify-project] success")
    marker_idx = result.stdout.index("RUNTIME_ORACLE=passed")
    assert marker_idx > success_idx, result.stdout


def test_verify_project_emits_docker_down_marker_when_docker_unavailable(tmp_path):
    """When docker is unavailable (binary present but every subcommand fails,
    simulating an unreachable daemon), the smoke test must be skipped
    gracefully -- not crash on a raw docker error -- and must emit
    RUNTIME_ORACLE=docker-down, never a passed marker."""
    project = _make_verify_project_fixture(tmp_path, "proj-docker-down")
    fake_bin = _fake_bin(tmp_path, docker_ok=False)

    result = _run_verify_project(project, fake_bin)

    assert result.returncode == 0, result.stdout
    assert "[verify-project] RUNTIME_ORACLE=docker-down" in result.stdout, result.stdout
    assert "RUNTIME_ORACLE=passed" not in result.stdout, result.stdout


def test_verify_project_emits_skipped_marker_on_docs_only_scoped_change(tmp_path):
    """The docs/plans-only scoped fast-path is a deliberate, correct skip (not
    a docker problem) and must be distinguishable from docker-down: it must
    emit RUNTIME_ORACLE=skipped."""
    project = _make_verify_project_fixture(tmp_path, "proj-scoped-skip")
    fake_bin = _fake_bin(tmp_path, docker_ok=True)

    result = _run_verify_project(
        project,
        fake_bin,
        env_extra={
            "AI_AUTO_VERIFY_DIFF_SCOPE": "1",
            "AI_AUTO_VERIFY_CHANGED_PATHS": "docs/readme.md\n",
        },
    )

    assert result.returncode == 0, result.stdout
    assert "[verify-project] RUNTIME_ORACLE=skipped" in result.stdout, result.stdout
    assert "RUNTIME_ORACLE=passed" not in result.stdout, result.stdout
    assert "RUNTIME_ORACLE=docker-down" not in result.stdout, result.stdout
