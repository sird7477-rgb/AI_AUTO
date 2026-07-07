"""R3 RED7 re-attack fixes (BLUE, ops-defense game round 4).

Confirmed defects being closed here (see .ops-game/R3-red7-reattack.md, findings
RED7-2 and RED7-3):

  RED7-2  validation-harness/harness-slug.sh: `slug="h-${tail:-p}-${hash}"` followed
          by `cut -c1-40` truncates the disambiguating cksum hash away entirely
          whenever the sanitized repo-basename `tail` is itself >=38 chars -- two
          UNRELATED repos whose basenames share a long common prefix (e.g.
          "...-for-client-ALPHA" vs "...-for-client-BETA") then collapse to a
          byte-identical slug, hence the same COMPOSE_PROJECT_NAME, hence the same
          docker container/volume/base-DB across different codebases. Fix: the hash
          is now zero-padded to a fixed 10-digit width and placed immediately after
          the "h-" prefix, so "h-<10-digit-hash>-" (13 chars) is always inside the
          40-char budget and always survives truncation; only the cosmetic $tail
          suffix gets truncated away when long.

  RED7-3  hooks/pre-push: `runtime_re='^(requirements[^/]*\\.txt|Dockerfile[^/]*|...)$'`
          is root-anchored, so a Dockerfile/requirements.txt/docker-compose file
          living in ANY subdirectory (e.g. `docker/Dockerfile`, a very common
          layout) evades the runtime-file scan entirely and -- if the same push
          also touches zero custom-addons/ modules -- falls straight through to the
          silent pre-RED2-3 "no custom-addons changes; skip Odoo validation; exit 0"
          path, reopening the exact bypass class RED2-3 closed. Fix: the regex now
          allows an optional `(.*/)?` directory prefix before the filename, matching
          the runtime-relevant BASENAME anywhere in the path, not only at repo root.

These tests build small, hermetic fixture git repos under pytest's tmp_path (never
touching the real shared worktree) and drive the real scripts as subprocesses --
matching the pattern used by tests/test_odoo_harness_honesty_r2.py and
tests/test_pre_push_binding_ref_ip1.py for the same seams. No docker daemon is
required for either test in this file.

Non-vacuousness: each assertion here targets behavior that is only true of the
FIXED script content. Restoring the pre-fix content (available via
`git show HEAD:<path>`, since these edits are uncommitted in this worktree at
authoring time) makes the corresponding assertion fail -- see the session's final
report for a one-shot manual revert/rerun proof of each.
"""
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
PRE_PUSH = ODOO_PACK / "hooks" / "pre-push"
HARNESS_SLUG = ODOO_PACK / "validation-harness" / "harness-slug.sh"

DOCKER_NAME_RE = re.compile(r"^[a-z][a-z0-9-]{0,39}$")


# --------------------------------------------------------------------------
# shared fixture helpers (small, local copies -- mirrors the pattern already
# used by the sibling r2/ip1 test files rather than importing across them)
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


def _slug_of(project_dir: Path) -> str:
    cmd = f'. "{HARNESS_SLUG}"; harness_proj_slug "{project_dir}"'
    result = subprocess.run(
        ["bash", "-c", cmd], text=True, capture_output=True, check=True
    )
    return result.stdout.strip()


# ==========================================================================
# RED7-2 -- harness-slug.sh: long shared-prefix basenames must NOT collide
# ==========================================================================
def test_harness_slug_long_shared_prefix_basenames_do_not_collide(tmp_path):
    """The exact RED7-2 PoC shape: two DIFFERENT repos whose sanitized basenames
    share a >=38-char common prefix (so "h-" + tail alone already fills the
    40-char budget) must still get DIFFERENT slugs -- the disambiguating hash
    must survive truncation."""
    long_prefix = "this-is-a-very-long-organization-project-name-for-client"
    repo_a = tmp_path / f"{long_prefix}-ALPHA"
    repo_b = tmp_path / f"{long_prefix}-BETA"
    _init_repo(repo_a)
    (repo_a / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo_a, "init")
    _init_repo(repo_b)
    (repo_b / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(repo_b, "init")

    # Sanity: the shared prefix really is long enough to trigger the bug class
    # (old code: "h-" + 38+ chars of tail already >= 40, leaving zero room for
    # the disambiguating hash suffix).
    assert len(long_prefix) >= 38, "test setup bug: prefix too short to reproduce RED7-2"

    slug_a = _slug_of(repo_a)
    slug_b = _slug_of(repo_b)

    assert slug_a != slug_b, (
        f"RED7-2 regression: two different repos with a long shared basename "
        f"prefix collided to one slug ({slug_a!r}), which means one shared "
        f"COMPOSE_PROJECT_NAME / container / volume / base-DB across unrelated "
        f"repos."
    )


def test_harness_slug_still_shares_across_worktrees_of_same_repo(tmp_path):
    """Companion non-vacuousness / no-regression check: the RED3-4 property (one
    repo's sibling `git worktree` checkouts share one slug, so they share one
    warm base) must survive the RED7-2 reordering fix."""
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


def test_harness_slug_still_docker_name_valid_and_within_budget(tmp_path):
    """The fixed construction must still be a valid docker-compose project name
    (lowercase [a-z][a-z0-9-]*, <=40 chars) for both a short and a long-basename
    repo."""
    short_repo = tmp_path / "r"
    _init_repo(short_repo)
    (short_repo / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(short_repo, "init")

    long_repo = tmp_path / ("this-is-a-very-long-organization-project-name-for-client-GAMMA")
    _init_repo(long_repo)
    (long_repo / "f.txt").write_text("hi\n", encoding="utf-8")
    _commit_all(long_repo, "init")

    for repo in (short_repo, long_repo):
        slug = _slug_of(repo)
        assert len(slug) <= 40, slug
        assert DOCKER_NAME_RE.match(slug), slug


# ==========================================================================
# RED7-3 -- pre-push: subdirectory runtime files must not evade the scan
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


def test_prepush_subdir_dockerfile_is_not_silently_skipped(tmp_path):
    """The exact RED7-3 PoC: a Dockerfile nested under a subdirectory (a common
    layout), with zero custom-addons/ files touched, must NOT fall through to the
    silent pre-RED2-3 "no custom-addons changes; skip" exit-0 path -- it must hit
    the same runtime-relevant NOT-VALIDATED ack/block path as a root-level file."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "some" / "subdir").mkdir(parents=True)
    (project / "some" / "subdir" / "Dockerfile").write_text(
        "FROM python:3.11\n", encoding="utf-8"
    )
    base_sha = _commit_all(project, "base")

    (project / "some" / "subdir" / "Dockerfile").write_text(
        "FROM python:3.12\n", encoding="utf-8"
    )
    new_sha = _commit_all(project, "bump base image (no module touched)")

    result = _run_prepush(project, lsha=new_sha, rsha=base_sha)

    assert "no custom-addons changes; skip Odoo validation" not in result.stdout, (
        f"RED7-3 regression: subdirectory Dockerfile silently exited clean-green. "
        f"stdout={result.stdout!r}"
    )
    assert "runtime-relevant" in result.stdout, result.stdout
    assert "NOT VALIDATED" in result.stdout, result.stdout
    assert result.returncode != 0, result.stdout


def test_prepush_root_runtime_file_still_detected(tmp_path):
    """Non-vacuousness companion: the pre-existing root-level case (RED2-3) must
    still work after widening the regex to also match subdirectories."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "requirements.txt").write_text("flask==1.0\n", encoding="utf-8")
    base_sha = _commit_all(project, "base")

    (project / "requirements.txt").write_text("flask==2.0\n", encoding="utf-8")
    new_sha = _commit_all(project, "bump flask (no module touched)")

    result = _run_prepush(project, lsha=new_sha, rsha=base_sha)

    assert "runtime-relevant" in result.stdout, result.stdout
    assert "NOT VALIDATED" in result.stdout, result.stdout
    assert result.returncode != 0, result.stdout


def test_prepush_pure_module_change_still_unaffected_by_widened_regex(tmp_path):
    """Guard against over-widening: an ordinary custom-addons/-only change must
    still reach the normal module-scope path, not get diverted into the
    runtime-relevant-file branch, even with the basename-anywhere match."""
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

    assert "runtime-relevant" not in result.stdout, result.stdout
    assert "ODOO_HARNESS_DIR not set" in result.stdout, result.stdout
