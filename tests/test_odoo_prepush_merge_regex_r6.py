"""R5 RED11-2/RED11-3 re-attack fixes (BLUE, ops-defense game, this round).

Confirmed defects being closed here (see .ops-game/R5-red11-reattack.md, findings
RED11-2 and RED11-3, both scored "Holds? NO / LIVE" against the file at that time):

  RED11-2  hooks/pre-push: the changed-file scan called
           `git diff-tree -r --no-commit-id --name-only "$c"` for every commit in the
           pushed range, with no `-m`/`-c`/`--cc`. By git's own design, plain
           `diff-tree` prints NOTHING for a merge commit. An "evil merge" -- a file
           (Dockerfile, requirements.txt, a custom-addons/ module) introduced ONLY
           during the merge's own conflict resolution, present in neither parent's
           tree individually -- was therefore invisible to BOTH `$mods` (module
           detection, gating the manifest/schema-catalog/warm-base screens) and
           `$runtime_files` (the RED2-3/RED7-3 outside-custom-addons scan). Fix: add
           `-m` to the existing per-commit invocation, so the commit is diffed
           against EACH of its parents; a file that differs from a parent shows up in
           that parent's diff, which is enough to surface a merge-only-injected file
           (the same file differs from every parent, so it appears regardless of
           which parent's diff is inspected). `-m` is already applied one resolved
           commit sha at a time (never to a raw multi-commit range), so this stays
           scoped to exactly the pushed commits -- not a history-wide traversal. For
           an ordinary single-parent commit `-m` diffs against that one parent, i.e.
           byte-identical output to the pre-fix call, so normal (non-merge) detection
           is unchanged.

  RED11-3  hooks/pre-push: `runtime_re` was matched with plain `grep -E` (no `-i`)
           and its compose alternative was `docker-compose[^/]*\\.ya?ml` only. Two
           independent evasions: (a) case -- `dockerfile`, `DOCKERFILE`,
           `docker-compose.YML` all evade a case-sensitive match though Docker itself
           is not case-enforcing; (b) naming -- Compose Specification v2's own default
           discovery name is `compose.yaml`/`compose.yml` (no "docker-" prefix
           required at all), which the `docker-compose`-only alternative never
           matched. Fix: match with `grep -Ei` (case-insensitive) and widen the
           alternative to `(docker-)?compose[^/]*\\.ya?ml`, still basename-anchored
           via the existing `(.*/)?...$` wrapper so an unrelated file that merely
           contains the substring "compose" (e.g. `recompose.yaml`) does not match.

These tests build small, hermetic fixture git repos under pytest's tmp_path (never
touching the real shared worktree) and drive the real hook as a subprocess fed a
synthetic push-refs line on stdin -- matching the pattern used by
tests/test_slug_and_scope_r4.py and tests/test_odoo_harness_honesty_r2.py for the
same seam. No docker daemon is required for any test in this file.

Non-vacuousness: each assertion targets behavior only true of the FIXED script.
Reverting `-m` back out of the diff-tree call (RED11-2 tests) or reverting `grep -Ei`
back to `grep -E` with the narrower alternative (RED11-3 tests) reproduces the
pre-fix content and flips every assertion below to fail -- verified by a one-shot
manual revert/rerun during authoring (see the session's final report).
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
PRE_PUSH = ODOO_PACK / "hooks" / "pre-push"


# --------------------------------------------------------------------------
# shared fixture helpers (small local copies -- mirrors test_slug_and_scope_r4.py)
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
# RED11-2 -- evil merge must not hide files from the change scan
# ==========================================================================
def test_prepush_evil_merge_runtime_file_is_detected_not_silently_skipped(tmp_path):
    """The exact RED11-2 PoC shape, isolated to its sharpest form: a Dockerfile and
    requirements.txt are injected ONLY during a merge's own conflict resolution --
    present in neither parent's own commit, and no custom-addons/ file exists
    anywhere in the pushed range. A pre-fix (`diff-tree` without `-m`) scan sees
    nothing for the merge commit and falls straight to the silent
    "no custom-addons changes; skip Odoo validation" exit-0 path. The fix must
    instead surface the injected runtime files via the same NOT-VALIDATED
    ack/block path used for a root-level runtime file change."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    base_sha = _commit_all(project, "base")

    _git(["checkout", "-q", "-b", "feature"], project)
    (project / "notes.txt").write_text("feature notes\n", encoding="utf-8")
    _commit_all(project, "feature: benign non-addon change")

    _git(["checkout", "-q", "main"], project)
    (project / "README.md").write_text("base\nmain change\n", encoding="utf-8")
    _commit_all(project, "main: unrelated")

    merge = _git(["merge", "-q", "--no-ff", "--no-commit", "feature"], project, check=False)
    assert merge.returncode == 0, merge.stdout + merge.stderr
    (project / "Dockerfile").write_text("FROM ubuntu\n", encoding="utf-8")
    (project / "requirements.txt").write_text("flask==1.0\n", encoding="utf-8")
    merge_sha = _commit_all(project, "merge feature into main (evil: inject Dockerfile+reqs)")

    result = _run_prepush(project, lsha=merge_sha, rsha=base_sha)

    assert "no custom-addons changes; skip Odoo validation" not in result.stdout, (
        f"RED11-2 regression: evil-merge-injected runtime files were invisible to "
        f"the scan; hook fell through to the silent skip path. stdout={result.stdout!r}"
    )
    assert "runtime-relevant" in result.stdout, result.stdout
    assert "Dockerfile" in result.stdout, result.stdout
    assert "requirements.txt" in result.stdout, result.stdout
    assert "NOT VALIDATED" in result.stdout, result.stdout
    assert result.returncode != 0, result.stdout


def test_prepush_evil_merge_custom_addons_module_is_detected(tmp_path):
    """Companion to the above, targeting the broader RED11-2 claim that $mods
    (module detection, gating manifest/schema-catalog/warm-base screens) is
    ALSO blind to a merge-only-injected file, not only $runtime_files. A
    custom-addons/ module file is injected only during merge conflict
    resolution; neither parent's own commit touches custom-addons/ at all."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    base_sha = _commit_all(project, "base")

    _git(["checkout", "-q", "-b", "feature"], project)
    (project / "notes.txt").write_text("feature notes\n", encoding="utf-8")
    _commit_all(project, "feature: benign non-addon change")

    _git(["checkout", "-q", "main"], project)
    (project / "README.md").write_text("base\nmain change\n", encoding="utf-8")
    _commit_all(project, "main: unrelated")

    merge = _git(["merge", "-q", "--no-ff", "--no-commit", "feature"], project, check=False)
    assert merge.returncode == 0, merge.stdout + merge.stderr
    (project / "custom-addons" / "mod1").mkdir(parents=True)
    (project / "custom-addons" / "mod1" / "__manifest__.py").write_text(
        "{'name': 'mod1', 'depends': []}\n", encoding="utf-8"
    )
    merge_sha = _commit_all(project, "merge feature into main (evil: inject module)")

    result = _run_prepush(project, lsha=merge_sha, rsha=base_sha)

    assert "no custom-addons changes; skip Odoo validation" not in result.stdout, (
        f"RED11-2 regression: evil-merge-injected custom-addons module was invisible "
        f"to $mods; hook fell through to the silent skip path. stdout={result.stdout!r}"
    )
    assert "ODOO_HARNESS_DIR not set" in result.stdout, result.stdout
    assert "NOT VALIDATED" in result.stdout, result.stdout
    assert result.returncode != 0, result.stdout


def test_prepush_normal_nonmerge_push_detection_is_unchanged(tmp_path):
    """Non-vacuousness / no-regression guard: adding `-m` must not change detection
    for the ordinary single-parent (non-merge) case -- a root-level module change
    across two plain sequential commits must still be caught exactly as before."""
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

    assert "no custom-addons changes; skip Odoo validation" not in result.stdout, result.stdout
    assert "runtime-relevant" not in result.stdout, result.stdout
    assert "ODOO_HARNESS_DIR not set" in result.stdout, result.stdout


# ==========================================================================
# RED11-3 -- case-insensitivity and modern compose.yaml naming
# ==========================================================================
def test_prepush_compose_v2_dockerfile_case_and_naming_evasions_are_detected(tmp_path):
    """The exact RED11-3 verified-evasion matrix: a bare Compose v2 `compose.yaml`
    (root, no "docker-" prefix), a lowercase `dockerfile` (root), and an
    upper-cased-extension `docker-compose.YML` living in a SUBdirectory must all
    be recognized as runtime-relevant, with zero custom-addons/ changes in the
    same commit."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    base_sha = _commit_all(project, "base")

    (project / "compose.yaml").write_text("services: {}\n", encoding="utf-8")
    (project / "dockerfile").write_text("FROM ubuntu\n", encoding="utf-8")
    (project / "deploy").mkdir()
    (project / "deploy" / "docker-compose.YML").write_text(
        "services: {}\n", encoding="utf-8"
    )
    new_sha = _commit_all(project, "add compose v2 file, lowercase dockerfile, subdir YML")

    result = _run_prepush(project, lsha=new_sha, rsha=base_sha)

    assert "no custom-addons changes; skip Odoo validation" not in result.stdout, (
        f"RED11-3 regression: a runtime file evaded the (case/name) match and the "
        f"hook fell through to the silent skip path. stdout={result.stdout!r}"
    )
    assert "runtime-relevant" in result.stdout, result.stdout
    assert "compose.yaml" in result.stdout, result.stdout
    assert "dockerfile" in result.stdout, result.stdout
    assert "docker-compose.YML" in result.stdout, result.stdout
    assert "NOT VALIDATED" in result.stdout, result.stdout
    assert result.returncode != 0, result.stdout


def test_prepush_normal_module_change_still_unaffected_by_widened_regex(tmp_path):
    """Guard against over-widening: an ordinary custom-addons/-only change must
    still reach the normal module-scope path, not get diverted into the
    runtime-relevant-file branch."""
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


def test_prepush_unrelated_file_is_not_treated_as_runtime(tmp_path):
    """Guard against over-matching: a plain unrelated file change (no
    custom-addons/, no requirements/Dockerfile/compose-family name) must still
    hit the ordinary "nothing relevant changed" clean-exit path."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    base_sha = _commit_all(project, "base")
    (project / "README.md").write_text("base\nmore docs\n", encoding="utf-8")
    new_sha = _commit_all(project, "docs only")

    result = _run_prepush(project, lsha=new_sha, rsha=base_sha)

    assert "runtime-relevant" not in result.stdout, result.stdout
    assert "no custom-addons changes; skip Odoo validation" in result.stdout, result.stdout
    assert result.returncode == 0, result.stdout
