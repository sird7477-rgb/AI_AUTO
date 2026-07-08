"""BLUE fix: port the RED17b-2 immutable-snapshot fix (already shipped in
validate-warm.sh / validate-full.sh, and independently hardened against
RED18 / RED18b) to validate-odoo.sh -- an older CI-slice registry-load
validator that still set `export PROJECT_ADDONS="$PROJECT/custom-addons"`
directly, i.e. mounted the LIVE (mutable) working directory as validation
ground truth. A same-UID or merely concurrent (non-adversarial) edit to
custom-addons/ during the validation window made the container test
different bytes than the commit under test -- exactly the same defect class
as RED17b-2, just in the sibling script that had not yet been fixed.

Fix: validate-odoo.sh now carries its own copy of `harness_materialize_tree`
(verbatim, [validate]-tagged, byte-identical in behavior to validate-warm.sh's
and validate-full.sh's copies -- confirmed by a tag-normalized diff at fix
time) that materializes `$HARNESS_VALIDATE_REF` (default HEAD) via `git
ls-tree` + `git cat-file blob` -- filter-immune, no `git archive` (which runs
the tree's own committed .gitattributes clean/smudge/textconv/filter
conversions -- a net-new git-exec RCE over an untrusted pushed tree, the
exact RED18 finding) -- into a throwaway snapshot dir, points PROJECT_ADDONS
at that snapshot, and drops it via a cleanup trap. Path-traversal ("..") and
symlink tree entries are rejected/skipped with a fail-closed, structural
canonicalize-under-$dest check, same as the reference implementation.

These tests are hermetic: pure git + filesystem, no docker, no network. Each
test extracts the ACTUAL `harness_materialize_tree` function text out of the
real validate-odoo.sh (via `_extract_materialize_fn`, the same technique
tests/test_snapshot_path_safety_r9.py and tests/test_snapshot_filter_immune_r9.py
use for validate-warm.sh/validate-full.sh) and executes it standalone in a
throwaway bash subprocess -- so a regression to the shipped file directly
breaks these tests, not a reimplementation of the fix's intent.

Three scenario groups are BLUE-task-specific and not already covered by the
warm/full test files (which never touch validate-odoo.sh):
  1. mutating the LIVE custom-addons dir AFTER the snapshot is taken must not
     change the already-materialized (validated) bytes -- with a genuine
     non-vacuous negative control: the exact pre-fix approach (PROJECT_ADDONS
     pointed straight at the live dir, no copy at all) DOES pick up the
     post-"snapshot" mutation, proving the positive assertion discriminates.
  2. the snapshot reflects the PASSED ref's content, not HEAD's and not the
     dirty worktree's, when all three differ.
  3 & 4. malicious tree entries (a ".." path component, a symlink) are
     rejected/skipped -- reusing the exact attack-construction helpers from
     tests/test_snapshot_path_safety_r9.py -- plus a filter-immunity positive
     control reusing tests/test_snapshot_filter_immune_r9.py's evil-filter
     scenario, each with the same OLD_* negative controls to prove
     non-vacuousness.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
HARNESS_SRC = ODOO_PACK / "validation-harness"
ODOO_SH = HARNESS_SRC / "validate-odoo.sh"


# The exact pre-RED18b-fix function body (ls-tree + cat-file, RED18-immune,
# but with zero path sanitization and unconditional symlink recreation) --
# verbatim copy of tests/test_snapshot_path_safety_r9.py's OLD_UNSANITIZED_FN,
# used ONLY as a negative/vulnerable control here too, to prove the path/
# symlink assertions against validate-odoo.sh's (fixed) copy actually
# discriminate.
OLD_UNSANITIZED_FN = '''
harness_materialize_tree() {
  local proj="$1" ref="$2" dest="$3" n=0 line meta path mode type oid outpath target
  git -C "$proj" rev-parse --verify -q "${ref}^{tree}" >/dev/null 2>&1 || return 1
  while IFS= read -r -d '' line; do
    meta="${line%%$'\t'*}"; path="${line#*$'\t'}"
    mode="${meta%% *}"
    type="${meta#* }"; type="${type%% *}"
    oid="${meta##* }"
    case "$mode" in
      160000)
        continue ;;
    esac
    [ "$type" = "blob" ] || { continue; }
    outpath="$dest/$path"
    mkdir -p "$(dirname "$outpath")" || return 1
    if [ "$mode" = "120000" ]; then
      target="$(git -C "$proj" cat-file blob "$oid")" || return 1
      ln -sf -- "$target" "$outpath" || return 1
    else
      git -C "$proj" cat-file blob "$oid" > "$outpath" || return 1
      [ "$mode" = "100755" ] && chmod +x "$outpath"
    fi
    n=$((n+1))
  done < <(git -C "$proj" ls-tree -r -z "$ref" -- custom-addons 2>/dev/null)
  [ "$n" -gt 0 ] || return 1
  return 0
}
'''

# The exact pre-fix `git archive | tar -x` pattern (RED18's finding), used
# ONLY as a negative/vulnerable filter-immunity control. Verbatim copy of
# tests/test_snapshot_filter_immune_r9.py's OLD_ARCHIVE_FN.
OLD_ARCHIVE_FN = '''
harness_materialize_tree() {
  local proj="$1" ref="$2" dest="$3"
  mkdir -p "$dest"
  git -C "$proj" archive "$ref" -- custom-addons | tar -x -C "$dest"
}
'''


# --------------------------------------------------------------------------
# shared fixture helpers (self-contained, mirroring
# tests/test_snapshot_path_safety_r9.py / tests/test_snapshot_filter_immune_r9.py)
# --------------------------------------------------------------------------
def _git(args: list[str], cwd: Path, check: bool = True, input_bytes: bytes | None = None):
    return subprocess.run(
        ["git", *args], cwd=cwd, input=input_bytes, capture_output=True, check=check
    )


def _init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git(["init", "-q"], path)
    _git(["config", "user.email", "t@example.invalid"], path)
    _git(["config", "user.name", "T"], path)


def _commit_all(path: Path, message: str) -> str:
    _git(["add", "-A"], path)
    _git(["commit", "-q", "-m", message], path)
    return _git(["rev-parse", "HEAD"], path).stdout.decode().strip()


def _extract_materialize_fn(script: Path) -> str:
    """Pull the literal `harness_materialize_tree() { ... }` function body out
    of the real shipped script -- so tests exercise exactly what ships, not a
    reimplementation of the fix's intent."""
    lines = script.read_text(encoding="utf-8").splitlines()
    start = next(
        i for i, l in enumerate(lines) if l.lstrip().startswith("harness_materialize_tree() {")
    )
    end = None
    for j in range(start + 1, len(lines)):
        if lines[j].strip() == "}":
            end = j
            break
    assert end is not None, f"no closing '}}' found for harness_materialize_tree() in {script}"
    return "\n".join(lines[start : end + 1])


def _run_materialize(
    fn_src: str, project: Path, ref: str, dest: Path
) -> subprocess.CompletedProcess[str]:
    dest.mkdir(parents=True, exist_ok=True)
    script = f'set -euo pipefail\n{fn_src}\nharness_materialize_tree "$1" "$2" "$3"\n'
    return subprocess.run(
        ["bash", "-c", script, "_", str(project), ref, str(dest)],
        text=True,
        capture_output=True,
        check=False,
    )


def _hash_blob(repo: Path, content: bytes) -> str:
    return _git(["hash-object", "-w", "--stdin"], repo, input_bytes=content).stdout.decode().strip()


def _mktree(repo: Path, entries: list[str]) -> str:
    stdin = ("\n".join(entries) + "\n").encode("utf-8")
    return _git(["mktree"], repo, input_bytes=stdin).stdout.decode().strip()


def _commit_tree(repo: Path, tree_oid: str, message: str) -> str:
    return _git(["commit-tree", tree_oid, "-m", message], repo).stdout.decode().strip()


def _make_traversal_project(tmp_path: Path, name: str, path_components: list[str]) -> tuple[Path, str]:
    """Hand-crafts (via git plumbing, never `git add`) a commit whose
    custom-addons/ tree contains one entry at the literal path
    "custom-addons/" + "/".join(path_components), where some components are
    literally "..". Identical construction to
    tests/test_snapshot_path_safety_r9.py's helper of the same name."""
    repo = tmp_path / name
    _init_repo(repo)
    payload = b"#!/bin/sh\necho PWNED\n"
    payload_oid = _hash_blob(repo, payload)
    leaf_name = path_components[-1]
    tree_oid = _mktree(repo, [f"100755 blob {payload_oid}\t{leaf_name}"])
    for component in reversed(path_components[:-1]):
        tree_oid = _mktree(repo, [f"040000 tree {tree_oid}\t{component}"])
    root_tree = _mktree(repo, [f"040000 tree {tree_oid}\tcustom-addons"])
    commit = _commit_tree(repo, root_tree, f"attack: {'/'.join(path_components)}")
    return repo, commit


def _make_symlink_project(tmp_path: Path, name: str) -> tuple[Path, str]:
    project = tmp_path / name
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    (mod / "__manifest__.py").write_text("{'name': 'mod1', 'depends': []}\n", encoding="utf-8")
    (mod / "evil_link_abs").symlink_to("/etc/passwd")
    (mod / "evil_link_rel").symlink_to("../../x")
    ref = _commit_all(project, "symlink attack (RED18b point 3)")
    return project, ref


def _make_evil_filter_project(tmp_path: Path, sentinel: Path, name: str) -> tuple[Path, str]:
    project = tmp_path / name
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    (mod / "__manifest__.py").write_text("{'name': 'mod1', 'depends': []}\n", encoding="utf-8")
    (mod / "views.xml").write_text(
        "<odoo><data>RAW-COMMITTED-BYTES</data></odoo>\n", encoding="utf-8"
    )
    (project / ".gitattributes").write_text("* filter=evil\n", encoding="utf-8")
    smudge_cmd = f"sh -c 'touch \"{sentinel}\"; printf SMUDGED-BY-EVIL-FILTER'"
    _git(["config", "filter.evil.smudge", smudge_cmd], project)
    ref = _commit_all(project, "evil commit (RED18 repro)")
    return project, ref


def _files_under(root: Path) -> set[Path]:
    if not root.exists():
        return set()
    return {p for p in root.rglob("*") if p.is_file() or p.is_symlink()}


RAW_BYTES = "<odoo><data>RAW-COMMITTED-BYTES</data></odoo>\n".encode("utf-8")


# ==========================================================================
# (1) LIVE-MUTATION-AFTER-SNAPSHOT -- the core BLUE fix for validate-odoo.sh:
#     once harness_materialize_tree has run, mutating the LIVE custom-addons/
#     dir must not change the already-copied snapshot bytes.
# ==========================================================================
def test_mutating_live_addons_after_snapshot_does_not_change_validated_bytes(tmp_path):
    project = tmp_path / "proj"
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    manifest = mod / "__manifest__.py"
    manifest.write_text("{'name': 'mod1', 'version': 'V1-COMMITTED'}\n", encoding="utf-8")
    ref = _commit_all(project, "v1")

    fn_src = _extract_materialize_fn(ODOO_SH)
    dest = tmp_path / "snap"
    result = _run_materialize(fn_src, project, ref, dest)
    assert result.returncode == 0, (result.stdout, result.stderr)

    snap_manifest = dest / "custom-addons" / "mod1" / "__manifest__.py"
    assert "V1-COMMITTED" in snap_manifest.read_text(encoding="utf-8")

    # Mutate the LIVE working directory AFTER the snapshot was taken -- this
    # simulates a same-UID or concurrent edit landing during the validation
    # window (RED17b-2's exact scenario).
    manifest.write_text("{'name': 'mod1', 'version': 'V2-MUTATED-AFTER-SNAPSHOT'}\n", encoding="utf-8")

    snap_content_after_mutation = snap_manifest.read_text(encoding="utf-8")
    assert "V1-COMMITTED" in snap_content_after_mutation, (
        "the materialized snapshot changed after a POST-snapshot live-tree edit -- "
        "validate-odoo.sh is not actually isolated from concurrent mutation"
    )
    assert "V2-MUTATED-AFTER-SNAPSHOT" not in snap_content_after_mutation


def test_mutating_live_addons_after_pointing_there_directly_leaks_through_old_approach(tmp_path):
    """Non-vacuousness control: reproduces the EXACT pre-fix validate-odoo.sh
    behavior -- `PROJECT_ADDONS="$PROJECT/custom-addons"`, i.e. no snapshot
    copy at all, just a direct reference to the live directory -- and shows
    that a live-tree mutation made AFTER that assignment DOES change what a
    reader of $PROJECT_ADDONS sees. This is the RED17b-2-class defect
    validate-odoo.sh actually shipped with, and proves the positive assertion
    above is discriminating (a no-op/always-pass test would pass here too if
    it weren't reading the real materialized copy)."""
    project = tmp_path / "proj-old"
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    manifest = mod / "__manifest__.py"
    manifest.write_text("{'name': 'mod1', 'version': 'V1-COMMITTED'}\n", encoding="utf-8")
    _commit_all(project, "v1")

    # Old validate-odoo.sh: PROJECT_ADDONS = "$PROJECT/custom-addons" (the
    # live dir itself -- no cat-file copy, no snapshot dir).
    old_project_addons = project / "custom-addons"
    old_manifest = old_project_addons / "mod1" / "__manifest__.py"
    assert "V1-COMMITTED" in old_manifest.read_text(encoding="utf-8")

    # A same-UID/concurrent edit during the validation window.
    manifest.write_text("{'name': 'mod1', 'version': 'V2-MUTATED-AFTER-SNAPSHOT'}\n", encoding="utf-8")

    assert "V2-MUTATED-AFTER-SNAPSHOT" in old_manifest.read_text(encoding="utf-8"), (
        "expected the pre-fix direct-live-dir approach to leak the post-'snapshot' "
        "mutation through -- it did not, so this control no longer reproduces RED17b-2"
    )


# ==========================================================================
# (2) REF-SCOPING -- the snapshot must reflect the PASSED ref's content, not
#     HEAD's, and not the dirty worktree's, when all three differ.
# ==========================================================================
def test_passed_ref_content_is_validated_not_head_or_worktree(tmp_path):
    project = tmp_path / "proj-refscope"
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    manifest = mod / "__manifest__.py"

    manifest.write_text("{'name': 'mod1', 'version': 'REF1-CONTENT'}\n", encoding="utf-8")
    ref1 = _commit_all(project, "ref1")

    manifest.write_text("{'name': 'mod1', 'version': 'HEAD-CONTENT'}\n", encoding="utf-8")
    _commit_all(project, "head commit")  # HEAD now differs from ref1

    # Dirty, UNCOMMITTED worktree change on top of HEAD -- a third, distinct
    # value neither ref1 nor HEAD's committed blob holds.
    manifest.write_text("{'name': 'mod1', 'version': 'WORKTREE-DIRTY-CONTENT'}\n", encoding="utf-8")

    fn_src = _extract_materialize_fn(ODOO_SH)
    dest = tmp_path / "snap-refscope"
    # Explicitly pass ref1 (mirrors HARNESS_VALIDATE_REF=ref1 while the live
    # repo's HEAD and worktree have since moved on).
    result = _run_materialize(fn_src, project, ref1, dest)
    assert result.returncode == 0, (result.stdout, result.stderr)

    snap_manifest = dest / "custom-addons" / "mod1" / "__manifest__.py"
    content = snap_manifest.read_text(encoding="utf-8")
    assert "REF1-CONTENT" in content, f"expected ref1's content, got: {content!r}"
    assert "HEAD-CONTENT" not in content
    assert "WORKTREE-DIRTY-CONTENT" not in content


# ==========================================================================
# (3) PATH TRAVERSAL -- reusing the exact attack construction from
#     tests/test_snapshot_path_safety_r9.py, now targeting validate-odoo.sh.
# ==========================================================================
def test_dotdot_path_traversal_is_rejected(tmp_path):
    project, ref = _make_traversal_project(
        tmp_path, "trav-odoo", ["..", "..", "PWNED-harness-preflight.sh"]
    )
    lst = _git(["ls-tree", "-r", ref, "--", "custom-addons"], project).stdout.decode()
    assert "custom-addons/../../PWNED-harness-preflight.sh" in lst, lst

    fn_src = _extract_materialize_fn(ODOO_SH)
    dest = tmp_path / "dest-trav-odoo"
    escape_target = dest.parent / "PWNED-harness-preflight.sh"

    before_outside = _files_under(tmp_path) - _files_under(dest)
    result = _run_materialize(fn_src, project, ref, dest)
    after_outside = _files_under(tmp_path) - _files_under(dest)

    assert result.returncode != 0, (
        f"expected the '../..' traversal to fail closed, got exit 0: "
        f"{result.stdout!r} {result.stderr!r}"
    )
    assert not escape_target.exists(), (
        "PWNED-harness-preflight.sh was written OUTSIDE the snapshot dir -- "
        "path traversal was NOT blocked in validate-odoo.sh"
    )
    assert after_outside == before_outside


def test_dotdot_path_traversal_escapes_under_old_unsanitized_fn(tmp_path):
    """Non-vacuousness control for the traversal test above."""
    project, ref = _make_traversal_project(
        tmp_path, "trav-odoo-old", ["..", "..", "PWNED-harness-preflight.sh"]
    )
    dest = tmp_path / "dest-trav-odoo-old"
    escape_target = dest.parent / "PWNED-harness-preflight.sh"

    result = _run_materialize(OLD_UNSANITIZED_FN, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    assert escape_target.exists(), (
        "expected the pre-fix function to write outside $dest -- it did not, so "
        "this control no longer reproduces the defect"
    )
    assert escape_target.read_bytes() == b"#!/bin/sh\necho PWNED\n"


# ==========================================================================
# (4) SYMLINK ESCAPE -- reusing the exact attack construction from
#     tests/test_snapshot_path_safety_r9.py, now targeting validate-odoo.sh.
# ==========================================================================
def test_symlink_entries_are_not_materialized(tmp_path):
    project, ref = _make_symlink_project(tmp_path, "sym-odoo")
    fn_src = _extract_materialize_fn(ODOO_SH)
    dest = tmp_path / "dest-sym-odoo"

    result = _run_materialize(fn_src, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    symlinks_in_dest = [p for p in dest.rglob("*") if p.is_symlink()]
    assert symlinks_in_dest == [], (
        f"symlink entries were materialized into the snapshot: {symlinks_in_dest} -- "
        "these get bind-mounted into the odoo container"
    )
    manifest = dest / "custom-addons" / "mod1" / "__manifest__.py"
    assert manifest.is_file() and not manifest.is_symlink()
    assert "mod1" in manifest.read_text(encoding="utf-8")


def test_symlink_entries_are_materialized_under_old_unsanitized_fn(tmp_path):
    """Non-vacuousness control for the symlink test above."""
    project, ref = _make_symlink_project(tmp_path, "sym-odoo-old")
    dest = tmp_path / "dest-sym-odoo-old"

    result = _run_materialize(OLD_UNSANITIZED_FN, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    abs_link = dest / "custom-addons" / "mod1" / "evil_link_abs"
    rel_link = dest / "custom-addons" / "mod1" / "evil_link_rel"
    assert abs_link.is_symlink() and os.readlink(abs_link) == "/etc/passwd"
    assert rel_link.is_symlink() and os.readlink(rel_link) == "../../x"


# ==========================================================================
# (5) FILTER-IMMUNITY -- reusing the exact evil-filter scenario from
#     tests/test_snapshot_filter_immune_r9.py, now targeting validate-odoo.sh.
# ==========================================================================
def test_materialize_is_filter_immune(tmp_path):
    sentinel = tmp_path / "SMUDGE-RAN.sentinel"
    project, ref = _make_evil_filter_project(tmp_path, sentinel, "evilproj-odoo")
    fn_src = _extract_materialize_fn(ODOO_SH)
    dest = tmp_path / "dest-evil-odoo"

    result = _run_materialize(fn_src, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    assert not sentinel.exists(), (
        "the evil filter.evil.smudge command RAN during materialization -- "
        "validate-odoo.sh's harness_materialize_tree is NOT filter-immune"
    )
    out_file = dest / "custom-addons" / "mod1" / "views.xml"
    got = out_file.read_bytes()
    assert got == RAW_BYTES, (
        f"materialized content was smudged ({got!r}) instead of the RAW committed "
        f"bytes ({RAW_BYTES!r}) -- validate-odoo.sh is running a content filter"
    )


def test_archive_approach_is_vulnerable_control(tmp_path):
    """Non-vacuousness control for the filter-immunity test above."""
    sentinel = tmp_path / "SMUDGE-RAN.sentinel"
    project, ref = _make_evil_filter_project(tmp_path, sentinel, "evilproj-odoo-old")
    dest = tmp_path / "dest-evil-odoo-old"

    result = _run_materialize(OLD_ARCHIVE_FN, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    assert sentinel.exists(), (
        "expected the pre-fix `git archive | tar -x` pattern to let the evil smudge "
        "filter execute -- it did not, so this control no longer reproduces RED18"
    )
    out_file = dest / "custom-addons" / "mod1" / "views.xml"
    assert out_file.read_bytes() != RAW_BYTES


# ==========================================================================
# (6) STATIC CONFIRMATION -- no conversion-running git command in the
#     shipped script's code (outside comments); ls-tree + cat-file present;
#     PROJECT_ADDONS is derived from the snapshot, not "$PROJECT/custom-addons"
#     directly.
# ==========================================================================
def test_no_conversion_running_git_command_is_used():
    lines = ODOO_SH.read_text(encoding="utf-8").splitlines()
    code_only = "\n".join(l for l in lines if not l.lstrip().startswith("#"))

    assert "git archive" not in code_only, "validate-odoo.sh still invokes `git archive` in code"
    assert "git checkout" not in code_only, "validate-odoo.sh still invokes `git checkout` in code"
    assert "worktree add" not in code_only, "validate-odoo.sh still invokes `git worktree add` in code"
    assert "--textconv" not in code_only, "validate-odoo.sh invokes a textconv-converting git call"

    assert "ls-tree -r -z" in code_only, "validate-odoo.sh does not use `git ls-tree -r -z`"
    assert "cat-file blob" in code_only, "validate-odoo.sh does not use `git cat-file blob`"

    assert 'PROJECT_ADDONS="$PROJECT/custom-addons"' not in code_only, (
        "validate-odoo.sh still points PROJECT_ADDONS directly at the live "
        "working directory (the RED17b-2-class defect this diff fixes)"
    )
    assert "HARNESS_SNAPSHOT_DIR/custom-addons" in code_only, (
        "validate-odoo.sh does not point PROJECT_ADDONS at a materialized snapshot"
    )
    assert "HARNESS_VALIDATE_REF" in code_only


# ==========================================================================
# (7) REGRESSION -- a normal tree (no traversal, no symlinks) still
#     materializes correctly, including nested paths and content.
# ==========================================================================
def test_normal_tree_still_materializes_correctly(tmp_path):
    project = tmp_path / "normal-odoo"
    _init_repo(project)
    mod1 = project / "custom-addons" / "mod1"
    mod1.mkdir(parents=True)
    (mod1 / "__manifest__.py").write_text("{'name': 'mod1', 'depends': []}\n", encoding="utf-8")
    nested = mod1 / "static" / "src"
    nested.mkdir(parents=True)
    (nested / "widget.js").write_text("console.log('hi');\n", encoding="utf-8")
    ref = _commit_all(project, "normal commit")

    fn_src = _extract_materialize_fn(ODOO_SH)
    dest = tmp_path / "dest-normal-odoo"
    result = _run_materialize(fn_src, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    manifest = dest / "custom-addons" / "mod1" / "__manifest__.py"
    widget = dest / "custom-addons" / "mod1" / "static" / "src" / "widget.js"
    assert manifest.read_text(encoding="utf-8") == "{'name': 'mod1', 'depends': []}\n"
    assert widget.read_text(encoding="utf-8") == "console.log('hi');\n"


# ==========================================================================
# (8) FAIL-CLOSED -- a bad/unresolvable ref must not silently succeed.
# ==========================================================================
def test_materialize_fails_closed_on_bad_ref(tmp_path):
    project = tmp_path / "badref-odoo"
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    (mod / "__manifest__.py").write_text("{'name': 'mod1', 'depends': []}\n", encoding="utf-8")
    _commit_all(project, "v1")

    fn_src = _extract_materialize_fn(ODOO_SH)
    dest = tmp_path / "dest-badref-odoo"
    result = _run_materialize(fn_src, project, "0" * 40, dest)

    assert result.returncode != 0, (
        f"a bad/unresolvable ref must fail closed: {result.stdout!r} {result.stderr!r}"
    )
    produced = list((dest / "custom-addons").rglob("*")) if (dest / "custom-addons").exists() else []
    assert produced == []
