"""R1 RED2/RED3 fixes for the odoo domain-pack (BLUE, ops-defense game round 2).

Confirmed defects being closed here (see .ops-game/R1-red2-oracle.md and
.ops-game/R1-red3-conc-opcost.md):

  RED2-3  hooks/pre-push: a runtime-relevant change OUTSIDE custom-addons/ (e.g.
          requirements.txt) that resolves to an EMPTY module scope must not exit
          clean-green silently -- it must go through the same NOT-VALIDATED
          ack/block path as every other "could not actually validate" reason.
  RED2-4  hooks/pre-push: a missing check-schema-catalog.py must not silently drop
          a BLOCKING lane -- it must surface a LOUD NOT-VALIDATED marker, mirroring
          verify-machinery.sh's verify_scanner_absent pattern.
  RED2-7  validation-harness/validate-full.sh: the closing message must reflect
          which sub-passes actually ran, not unconditionally claim both did.
  RED3-3  validation-harness/harness-lock.sh: a missing `flock` must degrade to
          no-lock LOUDLY (stderr warning), not silently.
  RED3-4  validation-harness/harness-slug.sh: the docker volume/slug must be keyed
          on repo IDENTITY (git common-dir), not the worktree's own absolute path,
          so sibling `git worktree` checkouts of the SAME repo share one warm base
          -- while two DIFFERENT repos still get different slugs (isolation intact).

These tests build small, hermetic fixture git repos/projects under pytest's
tmp_path (never touching the real shared worktree) and drive the real scripts as
subprocesses, matching the pattern used by tests/test_doctor_bootstrap_ip2.py for
other domain-pack/doctor-adjacent shell seams. Docker is mocked with a no-op fake
binary prepended to PATH -- no real daemon is required.

Non-vacuousness: each assertion here targets behavior that is only true of the
FIXED script content. Restoring the pre-fix content (available via
`git show HEAD:<path>`, since these edits are uncommitted in this worktree at
authoring time) makes the corresponding assertion fail -- see the session's final
report for a one-shot manual revert/rerun proof of each.
"""
from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
PRE_PUSH = ODOO_PACK / "hooks" / "pre-push"
VALIDATE_FULL = ODOO_PACK / "validation-harness" / "validate-full.sh"
HARNESS_SLUG = ODOO_PACK / "validation-harness" / "harness-slug.sh"
HARNESS_LOCK = ODOO_PACK / "validation-harness" / "harness-lock.sh"


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


def _fake_docker_bin(tmp_path: Path) -> Path:
    """A hermetic, no-op fake `docker` on PATH: succeeds unconditionally for any
    subcommand (info/version/compose ...), never touches a real daemon."""
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    _make_executable(docker)
    return bin_dir


# ==========================================================================
# RED2-3 -- pre-push: runtime-relevant change outside custom-addons/, empty scope
# ==========================================================================
def _run_prepush(project: Path, lsha: str, rsha: str, env_extra: dict | None = None):
    stdin = f"refs/heads/main {lsha} refs/heads/main {rsha}\n"
    env = os.environ.copy()
    env.pop("ODOO_HARNESS_DIR", None)
    env.pop("SKIP_ODOO_VALIDATE", None)
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["bash", str(PRE_PUSH)],
        cwd=project,
        input=stdin,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def test_prepush_requirements_only_change_is_not_silently_green(tmp_path):
    project = tmp_path / "project"
    _init_repo(project)
    (project / "requirements.txt").write_text("flask==1.0\n", encoding="utf-8")
    base_sha = _commit_all(project, "base")

    # Only requirements.txt changes -- zero custom-addons/ files touched.
    (project / "requirements.txt").write_text("flask==2.0\n", encoding="utf-8")
    new_sha = _commit_all(project, "bump flask (no module touched)")

    result = _run_prepush(project, lsha=new_sha, rsha=base_sha)

    assert "runtime-relevant" in result.stdout, result.stdout
    assert "NOT VALIDATED" in result.stdout, result.stdout
    # Must not be a silent clean exit: this is the exact old-bug behavior.
    assert result.returncode != 0, result.stdout


def test_prepush_pure_module_change_is_unaffected_by_the_runtime_file_check(tmp_path):
    """Guard against over-widening: an ordinary custom-addons/-only change must
    still reach the normal module-scope path (not get diverted into the new
    runtime-relevant-file NOT-VALIDATED branch)."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "custom-addons" / "mod1").mkdir(parents=True)
    (project / "custom-addons" / "mod1" / "__manifest__.py").write_text(
        "{'name': 'mod1', 'depends': []}\n", encoding="utf-8"
    )
    base_sha = _commit_all(project, "base")
    (project / "custom-addons" / "mod1" / "views.xml").write_text(
        "<odoo/>\n", encoding="utf-8"
    )
    new_sha = _commit_all(project, "add a view")

    result = _run_prepush(project, lsha=new_sha, rsha=base_sha)

    # Falls through to "ODOO_HARNESS_DIR not set" (mods is non-empty), NOT the
    # runtime-relevant-file branch.
    assert "runtime-relevant" not in result.stdout, result.stdout
    assert "ODOO_HARNESS_DIR not set" in result.stdout, result.stdout


# ==========================================================================
# RED2-4 -- pre-push: check-schema-catalog.py absent must be LOUD, not silent
# ==========================================================================
def test_prepush_schema_catalog_absence_is_loud_not_silent(tmp_path):
    project = tmp_path / "project"
    _init_repo(project)
    (project / "custom-addons" / "mod1").mkdir(parents=True)
    (project / "custom-addons" / "mod1" / "__manifest__.py").write_text(
        "{'name': 'mod1', 'depends': []}\n", encoding="utf-8"
    )
    base_sha = _commit_all(project, "base")
    (project / "custom-addons" / "mod1" / "views.xml").write_text(
        "<odoo/>\n", encoding="utf-8"
    )
    new_sha = _commit_all(project, "add a view")

    # A harness dir that exists but has NO check-schema-catalog.py (nor any of the
    # other optional screens) -- exactly the "file absent/renamed" scenario.
    harness = tmp_path / "harness"
    harness.mkdir()

    result = _run_prepush(
        project, lsha=new_sha, rsha=base_sha, env_extra={"ODOO_HARNESS_DIR": str(harness)}
    )

    assert (
        "NOT-VALIDATED (scanner check-schema-catalog.py unavailable)" in result.stdout
    ), result.stdout


# ==========================================================================
# RED2-7 -- validate-full.sh: honest closing message (no over-claim on skip)
# ==========================================================================
def test_validate_full_views_only_change_reports_skips_honestly(tmp_path):
    project = tmp_path / "project"
    _init_repo(project)
    mod_dir = project / "custom-addons" / "mod1"
    (mod_dir / "views").mkdir(parents=True)
    (mod_dir / "__manifest__.py").write_text(
        "{'name': 'mod1', 'depends': []}\n", encoding="utf-8"
    )
    (mod_dir / "views" / "mod1_view.xml").write_text(
        "<odoo><data>v1</data></odoo>\n", encoding="utf-8"
    )
    _commit_all(project, "base")
    # Uncommitted views-only edit: WANT_TEST=0, WANT_DEMO=0 (no .py/.csv, no
    # models|tests|data|security|wizard path, no demo/ file).
    (mod_dir / "views" / "mod1_view.xml").write_text(
        "<odoo><data>v2</data></odoo>\n", encoding="utf-8"
    )

    fake_bin = _fake_docker_bin(tmp_path)
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
    # Redirect the base-rebuild lock file OUT of the real (shared) harness dir --
    # HARNESS_LOCK_FILE, if already exported, wins over harness-lock.sh's default.
    env["HARNESS_LOCK_FILE"] = str(tmp_path / "harness-base.lock")
    env.pop("SKIP_TEST_PASS", None)
    env.pop("SKIP_DEMO_PASS", None)

    result = subprocess.run(
        ["bash", str(VALIDATE_FULL), str(project)],
        cwd=tmp_path,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )

    assert result.returncode == 0, result.stdout
    assert "[full] PASS" in result.stdout, result.stdout
    assert "tests SKIPPED" in result.stdout, result.stdout
    assert "demo SKIPPED" in result.stdout, result.stdout
    # The old, over-claiming sentence must be gone.
    assert "tests + demo load clean" not in result.stdout, result.stdout


# ==========================================================================
# RED3-4 -- harness-slug.sh: keyed on repo identity, shared across worktrees,
#           still isolated across different repos
# ==========================================================================
def _slug_of(project_dir: Path) -> str:
    cmd = f'. "{HARNESS_SLUG}"; harness_proj_slug "{project_dir}"'
    result = subprocess.run(
        ["bash", "-c", cmd], text=True, capture_output=True, check=True
    )
    return result.stdout.strip()


def test_harness_slug_shared_across_worktrees_of_same_repo(tmp_path):
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


def test_harness_slug_differs_across_different_repos(tmp_path):
    repo_a = tmp_path / "repoA"
    _init_repo(repo_a)
    (repo_a / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo_a, "init")

    repo_b = tmp_path / "repoB"
    _init_repo(repo_b)
    (repo_b / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo_b, "init")

    assert _slug_of(repo_a) != _slug_of(repo_b)


def test_harness_slug_stable_and_within_length_budget(tmp_path):
    """Regression guard on the existing contract (docker-safe, <=40 chars, stable
    across repeated calls) -- the RED3-4 rework must not break this."""
    repo = tmp_path / "repo"
    _init_repo(repo)
    (repo / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo, "init")

    slug1 = _slug_of(repo)
    slug2 = _slug_of(repo)
    assert slug1 == slug2
    assert len(slug1) <= 40
    assert slug1[0].isalpha()


# ==========================================================================
# RED3-3 -- harness-lock.sh: missing flock must degrade LOUDLY, not silently
# ==========================================================================
def _minimal_bin_without_flock(tmp_path: Path) -> Path:
    bin_dir = tmp_path / "no-flock-bin"
    bin_dir.mkdir(exist_ok=True)
    for tool in ("bash", "sh", "cat", "mkdir", "rm", "true"):
        src = subprocess.run(
            ["bash", "-c", f"command -v {tool}"], text=True, capture_output=True
        ).stdout.strip()
        if src:
            (bin_dir / tool).symlink_to(src)
    return bin_dir


def test_harness_lock_missing_flock_warns_loudly(tmp_path):
    bin_dir = _minimal_bin_without_flock(tmp_path)
    # Sanity: this constructed PATH genuinely lacks flock.
    probe = subprocess.run(
        ["bash", "-c", "command -v flock"],
        env={"PATH": str(bin_dir)},
        text=True,
        capture_output=True,
    )
    assert probe.returncode != 0, "test setup bug: flock still resolvable on PATH"

    env = {"PATH": str(bin_dir), "HARNESS_DIR": str(tmp_path), "HARNESS_SLUG": "t"}
    result = subprocess.run(
        ["bash", "-c", f'. "{HARNESS_LOCK}"; harness_lock write'],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )

    assert result.returncode == 0, result.stdout  # still degrades (never blocks work)
    assert "WARNING" in result.stdout, result.stdout
    assert "flock" in result.stdout.lower(), result.stdout
