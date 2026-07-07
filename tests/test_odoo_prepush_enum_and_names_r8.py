"""R7 RED15-2/RED15-4 re-attack fixes (BLUE, ops-defense game, this round).

Confirmed defects being closed here (see .ops-game/R7-red15-reattack.md, findings
RED15-2 and RED15-4, both scored "holds? NO" against the hook at that time):

  RED15-2  templates/domain-packs/odoo/hooks/pre-push's own new-branch-push
           commit-enumeration used `git rev-list "$lsha" --not --remotes`. This is
           the SAME forgeable-glob class already removed from
           scripts/review-gate-binding.sh's octopus merge-base fix, just never
           touched in this sibling file: `refs/remotes/*` refs are ordinary,
           same-UID-writable local refs (`git update-ref
           refs/remotes/origin/decoy <sha-at-or-after-the-pushed-tip>`, no
           network/fetch needed). A decoy ref planted at/after the pushed tip made
           `rev-list` return ZERO commits, so BOTH `$mods` and `$runtime_files`
           were empty and the hook fell through to the silent
           "no custom-addons changes; skip Odoo validation" exit-0 path even
           though the pushed commit carried a real custom-addons/runtime-file
           change. Fix: never derive "what's being pushed" from a local
           remote-tracking glob. The pre-push STDIN `rsha` for a ref is the
           AUTHENTIC value git negotiated with the remote server -- for an
           existing ref it is already used untouched (`$rsha..$lsha`, always
           correct); for a brand-new ref (`rsha` all-zeros) there is no authentic
           lower bound at all, so the fix over-approximates safely by
           enumerating ALL of `$lsha`'s history (`git rev-list "$lsha"`, no
           `--not --remotes`) rather than subtracting any local ref. This can
           validate MORE commits than strictly new, never fewer -- it can never
           again silently collapse to zero via a forged local ref.

  RED15-4  `runtime_re`'s `Dockerfile[^/]*` alternative only matches the PREFIX
           naming convention (`Dockerfile`, `Dockerfile.prod`) and missed both
           the equally-real SUFFIX convention (`api.Dockerfile`,
           `backend.dockerfile` -- `docker build -f api.Dockerfile .` works, and
           multi-service monorepos use it so editors' `*.Dockerfile` glob
           highlighting picks the file up) and Podman/Buildah's own DEFAULT build
           file name `Containerfile` (a mainstream Docker-CLI-compatible tool,
           not an exotic alias). Fix: add `[^/]*\\.dockerfile` (suffix form,
           matched case-insensitively like the rest of the regex) and
           `Containerfile[^/]*` (mirroring the existing Dockerfile
           prefix-optional-suffix allowance) to the alternation, still
           basename-anchored via the existing `(.*/)?...$` wrapper so an
           unrelated file that merely contains the substring "dockerfile" does
           not match.

These tests build small, hermetic fixture git repos under pytest's tmp_path (never
touching the real shared worktree) and drive the real hook as a subprocess fed a
synthetic push-refs line on stdin -- matching the pattern used by
tests/test_odoo_prepush_merge_regex_r6.py and tests/test_odoo_harness_honesty_r2.py
for the same seam. No docker daemon is required for any test in this file.

Non-vacuousness: each assertion targets behavior only true of the FIXED script.
Reverting the enumeration back to `rev-list "$lsha" --not --remotes` (RED15-2
tests) or reverting the regex back to drop the suffix-dockerfile/Containerfile
alternatives (RED15-4 tests) reproduces the pre-fix content and flips the
relevant assertions below to fail -- verified by a one-shot manual revert/rerun
during authoring (see the session's final report).
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
PRE_PUSH = ODOO_PACK / "hooks" / "pre-push"

ZERO = "0" * 40


# --------------------------------------------------------------------------
# shared fixture helpers (small local copies -- mirrors test_odoo_prepush_merge_regex_r6.py)
# --------------------------------------------------------------------------
def _git(args: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args], cwd=cwd, text=True, capture_output=True, check=check
    )


def _init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git(["init", "-q", "-b", "main"], path)
    _git(["config", "user.email", "t@example.invalid"], path)
    _git(["config", "user.name", "T"], path)


def _commit_all(path: Path, message: str) -> str:
    _git(["add", "-A"], path)
    _git(["commit", "-q", "-m", message], path)
    return _git(["rev-parse", "HEAD"], path).stdout.strip()


def _run_prepush(project: Path, lsha: str, rsha: str):
    stdin = f"refs/heads/main {lsha} refs/heads/main {rsha}\n"
    env = os.environ.copy()
    env.pop("ODOO_HARNESS_DIR", None)
    env.pop("SKIP_ODOO_VALIDATE", None)
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


# ==========================================================================
# RED15-2 -- forgeable `--not --remotes` new-branch enumeration
# ==========================================================================
def test_prepush_decoy_remote_ref_does_not_erase_module_enumeration(tmp_path):
    """The exact RED15-2 PoC shape: a brand-new-branch push (stdin rsha == all
    zeros) whose tip commit adds a custom-addons/ module. Before running, plant
    a same-UID-writable local remote-tracking ref, `refs/remotes/origin/decoy`,
    pointed AT the pushed tip -- no fetch, no network, just `git update-ref`.
    Pre-fix, `rev-list "$lsha" --not --remotes` excludes everything reachable
    from that decoy (i.e. everything, since decoy == lsha), so the enumerated
    commit list -- and therefore $mods -- silently collapses to empty and the
    hook falls through to the silent "no custom-addons changes" exit-0 skip.
    Fixed, the new-branch case no longer consults any `--remotes` glob at all,
    so the decoy has zero effect on enumeration."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    _commit_all(project, "base")

    (project / "custom-addons" / "mod1").mkdir(parents=True)
    (project / "custom-addons" / "mod1" / "__manifest__.py").write_text(
        "{'name': 'mod1', 'depends': []}\n", encoding="utf-8"
    )
    tip_sha = _commit_all(project, "add custom-addons module (this is what's being pushed)")

    # Plant the decoy AT the pushed tip -- the sharpest form of the PoC (RED15-2's
    # own reproduction used decoy == the pushed commit).
    _git(["update-ref", "refs/remotes/origin/decoy", tip_sha], project)

    result = _run_prepush(project, lsha=tip_sha, rsha=ZERO)

    assert "no custom-addons changes; skip Odoo validation" not in result.stdout, (
        f"RED15-2 regression: a same-UID-writable refs/remotes/* decoy erased the "
        f"enumerated pushed-commit set, hiding a real custom-addons/ change and "
        f"falling through to the silent skip path. stdout={result.stdout!r}"
    )
    assert "ODOO_HARNESS_DIR not set" in result.stdout, result.stdout
    assert "NOT VALIDATED" in result.stdout, result.stdout
    assert result.returncode != 0, result.stdout


def test_prepush_decoy_remote_ref_does_not_erase_runtime_file_enumeration(tmp_path):
    """Companion to the above, targeting $runtime_files (not $mods): a decoy ref
    planted at the pushed tip must not hide a Dockerfile added in that same
    new-branch push (no custom-addons/ change at all in this scenario, so the
    runtime-files path is the only thing standing between this push and the
    fully-silent skip)."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    _commit_all(project, "base")

    (project / "Dockerfile").write_text("FROM ubuntu\n", encoding="utf-8")
    tip_sha = _commit_all(project, "add Dockerfile (this is what's being pushed)")

    _git(["update-ref", "refs/remotes/origin/decoy", tip_sha], project)

    result = _run_prepush(project, lsha=tip_sha, rsha=ZERO)

    assert "no custom-addons changes; skip Odoo validation" not in result.stdout, (
        f"RED15-2 regression: decoy erased runtime-file enumeration too. "
        f"stdout={result.stdout!r}"
    )
    assert "runtime-relevant" in result.stdout, result.stdout
    assert "Dockerfile" in result.stdout, result.stdout
    assert "NOT VALIDATED" in result.stdout, result.stdout
    assert result.returncode != 0, result.stdout


def test_prepush_new_branch_without_decoy_still_enumerates_normally(tmp_path):
    """Non-vacuousness / no-regression guard: a plain new-branch push with NO
    decoy ref in play must still detect a real custom-addons/ module change --
    the fix (dropping `--not --remotes` for an over-approximating full-history
    `rev-list "$lsha"`) must not itself under-detect the ordinary case.

    Note: the module-adding commit is deliberately NOT the repo's root commit
    (a "base" commit precedes it) -- `git diff-tree` without `--root` prints
    nothing for a parentless root commit, a pre-existing, orthogonal quirk of
    this hook's diff-tree invocation (same family as RED11-2's merge-commit
    gap, but not itself a RED15 finding and out of scope for this fix); using a
    non-root tip keeps this test isolated to the enumeration fix under test."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    _commit_all(project, "base")

    (project / "custom-addons" / "mod1").mkdir(parents=True)
    (project / "custom-addons" / "mod1" / "__manifest__.py").write_text(
        "{'name': 'mod1', 'depends': []}\n", encoding="utf-8"
    )
    tip_sha = _commit_all(project, "add custom-addons module")

    result = _run_prepush(project, lsha=tip_sha, rsha=ZERO)

    assert "no custom-addons changes; skip Odoo validation" not in result.stdout, result.stdout
    assert "ODOO_HARNESS_DIR not set" in result.stdout, result.stdout
    assert result.returncode != 0, result.stdout


def test_prepush_new_branch_without_relevant_change_still_skips_cleanly(tmp_path):
    """Guard against over-widening: a new-branch push touching nothing relevant
    (no custom-addons/, no runtime files) must still hit the ordinary clean
    exit-0 skip -- the full-history over-approximation changes WHICH commits
    are scanned, not what counts as a relevant change within them."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    tip_sha = _commit_all(project, "docs only")

    result = _run_prepush(project, lsha=tip_sha, rsha=ZERO)

    assert "runtime-relevant" not in result.stdout, result.stdout
    assert "no custom-addons changes; skip Odoo validation" in result.stdout, result.stdout
    assert result.returncode == 0, result.stdout


# ==========================================================================
# RED15-4 -- suffix-style Dockerfile naming and Podman's Containerfile
# ==========================================================================
def test_prepush_dockerfile_suffix_and_containerfile_variants_are_detected(tmp_path):
    """The exact RED15-4 verified-evasion matrix: a suffix-style `api.Dockerfile`
    (root), a lowercase suffix-style `foo.dockerfile` (root), a root-level
    `Containerfile`, and a SUBdirectory `Containerfile` must all be recognized
    as runtime-relevant, with zero custom-addons/ changes in the same commit."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    base_sha = _commit_all(project, "base")

    (project / "api.Dockerfile").write_text("FROM ubuntu\n", encoding="utf-8")
    (project / "foo.dockerfile").write_text("FROM ubuntu\n", encoding="utf-8")
    (project / "Containerfile").write_text("FROM ubuntu\n", encoding="utf-8")
    (project / "deploy").mkdir()
    (project / "deploy" / "Containerfile").write_text("FROM ubuntu\n", encoding="utf-8")
    new_sha = _commit_all(
        project, "add suffix-style Dockerfiles and root+subdir Containerfiles"
    )

    result = _run_prepush(project, lsha=new_sha, rsha=base_sha)

    assert "no custom-addons changes; skip Odoo validation" not in result.stdout, (
        f"RED15-4 regression: a suffix-Dockerfile or Containerfile name evaded "
        f"the match and the hook fell through to the silent skip path. "
        f"stdout={result.stdout!r}"
    )
    assert "runtime-relevant" in result.stdout, result.stdout
    assert "api.Dockerfile" in result.stdout, result.stdout
    assert "foo.dockerfile" in result.stdout, result.stdout
    assert "Containerfile" in result.stdout, result.stdout
    assert "deploy/Containerfile" in result.stdout, result.stdout
    assert "NOT VALIDATED" in result.stdout, result.stdout
    assert result.returncode != 0, result.stdout


def test_prepush_unrelated_file_still_not_treated_as_runtime_after_regex_widening(tmp_path):
    """Guard against over-matching: a plain unrelated file whose name merely
    CONTAINS the substring "dockerfile" (but is not itself a `*.dockerfile` /
    `Dockerfile*` / `Containerfile*` basename) must still hit the ordinary
    "nothing relevant changed" clean-exit path -- the widened regex must stay
    basename-anchored, not turn into a bare substring match."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    base_sha = _commit_all(project, "base")

    (project / "not-a-dockerfile-mention.md").write_text(
        "this file just talks about dockerfile and Containerfile in prose\n",
        encoding="utf-8",
    )
    new_sha = _commit_all(project, "docs mentioning the words, not matching names")

    result = _run_prepush(project, lsha=new_sha, rsha=base_sha)

    assert "runtime-relevant" not in result.stdout, result.stdout
    assert "no custom-addons changes; skip Odoo validation" in result.stdout, result.stdout
    assert result.returncode == 0, result.stdout
