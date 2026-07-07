"""R9 ops-defense game (BLUE) fix for RED18b (TWO net-new CRITICAL vulns), found
by an independent adversarial re-verification of the RED18 `harness_materialize_tree`
fix while it was still uncommitted:

  .ops-game/R9-red18b-verify-hardened.md point 2 (PATH TRAVERSAL, CRITICAL) --
  `outpath="$dest/$path"` was unsanitized. `git mktree` accepts a tree entry
  whose NAME is literally ".." (a normal `git add` refuses this -- the
  filesystem has no such path -- but a hand-crafted tree object built via
  plumbing does not go through the filesystem), and `git ls-tree -r` emits
  that ".." component verbatim as part of the printed path, e.g.
  "custom-addons/../../PWNED-harness-preflight.sh". The unsanitized
  "$dest/$path" then writes OUTSIDE $dest. Since $dest is
  `mktemp -d "${HARNESS_DIR}/.odoo-harness-snap.XXXXXX"` -- a SIBLING of the
  harness scripts themselves -- two ".." components land an attacker-
  controlled EXECUTABLE right next to validate-warm.sh/validate-full.sh: a
  self-propagating backdoor. Empirically reproduced below (exit 0, file
  written one directory above $dest, before this fix).

  .ops-game/R9-red18b-verify-hardened.md point 3 (SYMLINK ESCAPE, CRITICAL)
  -- `ln -sf -- "$target" "$outpath"` applied zero validation to the blob-
  derived symlink target text. A committed symlink -> /root/.ssh/id_rsa (or
  -> ../../..) landed inside the materialized snapshot, which
  docker-compose.validate.yml then bind-mounts into the odoo container as
  $PROJECT_ADDONS. Also reproduced below.

Fix (this diff, in harness_materialize_tree, identically in both
validate-warm.sh and validate-full.sh):
  1. Path sanitization: before `outpath` is ever computed, reject (fail
     CLOSED, non-zero, naming the offending path) any ls-tree entry path
     that is absolute, has a ".." path component ANYWHERE (as a whole
     component: leading, trailing, or in the middle -- not merely as a
     string prefix), or does not sit under "custom-addons/". A second,
     independent, structural check then canonicalizes the just-`mkdir -p`'d
     parent directory (`cd ... && pwd -P`) and asserts it is still strictly
     under $dest, as a belt-and-suspenders backstop.
  2. Symlink entries (mode 120000) are now REJECTED outright -- skipped with
     a stderr note, the same way a submodule (160000) entry already was.
     Odoo addon modules never need an in-tree symlink, and this also removes
     the "write through an earlier-created symlink" ordering escape by
     construction: no symlink is EVER created anywhere inside $dest.

These tests are hermetic: pure git + filesystem, no docker, no network. Each
test extracts the ACTUAL `harness_materialize_tree` function text out of the
real validate-warm.sh / validate-full.sh files (via `_extract_materialize_fn`,
same helper as tests/test_snapshot_filter_immune_r9.py) and executes it
standalone in a throwaway bash subprocess -- so a regression to the fixed
file directly breaks these tests, not a reimplementation of the fix's intent.

The malicious ".." tree entries are built with `git hash-object` + `git
mktree` plumbing (never `git add`, which the real filesystem would refuse for
a path component literally named "..") -- this is exactly how a real attacker
would have to construct and push such a tree, and is the same construction
independently reproduced in the red-team report.

Non-vacuousness: `OLD_UNSANITIZED_FN` below is the exact function body
validate-warm.sh/validate-full.sh shipped with immediately before this fix
(RED18-fixed -- ls-tree + cat-file, filter-immune -- but RED18b-vulnerable --
no path sanitization, symlinks recreated verbatim). It predates this fix and
was never committed to history under this name, so it is reproduced here
literally (mirroring the `OLD_ARCHIVE_FN` pattern in
tests/test_snapshot_filter_immune_r9.py) as the negative control: every
attack scenario below is run against BOTH the fixed (real, extracted) function
and this old one, and the old one is asserted to actually escape / actually
create the symlink -- proving the positive assertions against the fixed
function are discriminating, not trivially true.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
HARNESS_SRC = ODOO_PACK / "validation-harness"
WARM_SH = HARNESS_SRC / "validate-warm.sh"
FULL_SH = HARNESS_SRC / "validate-full.sh"

# The exact pre-RED18b-fix function body (ls-tree + cat-file, RED18-immune,
# but with zero path sanitization and unconditional symlink recreation) --
# used ONLY as a negative/vulnerable control to prove the new tests actually
# discriminate, never as part of the shipped fix. Verbatim copy of what both
# scripts contained immediately before this diff.
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


# --------------------------------------------------------------------------
# shared fixture helpers (self-contained, mirroring
# tests/test_snapshot_filter_immune_r9.py's own helpers)
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
    """entries: pre-formatted lines "<mode> <type> <sha>\\t<name>" (git mktree,
    non-`-z` form: LF-separated entries, TAB before the name)."""
    stdin = ("\n".join(entries) + "\n").encode("utf-8")
    return _git(["mktree"], repo, input_bytes=stdin).stdout.decode().strip()


def _commit_tree(repo: Path, tree_oid: str, message: str) -> str:
    return _git(["commit-tree", tree_oid, "-m", message], repo).stdout.decode().strip()


def _make_traversal_project(tmp_path: Path, name: str, path_components: list[str]) -> tuple[Path, str]:
    """Hand-crafts (via git plumbing, never `git add`) a commit whose
    custom-addons/ tree contains one entry at the literal path
    "custom-addons/" + "/".join(path_components) -- where some of
    path_components are literally "..". This is exactly how RED18b's `git
    mktree` attack is built: a normal `git add` refuses a path component
    named ".." (no such filesystem path exists), but a hand-crafted tree
    object built purely from plumbing commands does not go through the
    filesystem at all, and `git ls-tree -r` emits the component verbatim.
    Returns (repo_path, commit_sha)."""
    repo = tmp_path / name
    _init_repo(repo)
    payload = b"#!/bin/sh\necho PWNED\n"
    payload_oid = _hash_blob(repo, payload)
    # Build from the innermost (leaf) component outward.
    leaf_name = path_components[-1]
    tree_oid = _mktree(repo, [f"100755 blob {payload_oid}\t{leaf_name}"])
    for component in reversed(path_components[:-1]):
        tree_oid = _mktree(repo, [f"040000 tree {tree_oid}\t{component}"])
    root_tree = _mktree(repo, [f"040000 tree {tree_oid}\tcustom-addons"])
    commit = _commit_tree(repo, root_tree, f"attack: {'/'.join(path_components)}")
    return repo, commit


def _make_symlink_project(tmp_path: Path, name: str) -> tuple[Path, str]:
    """A NORMAL commit (via `git add` -- no plumbing needed; symlink target
    text is unrestricted by git itself) containing a legit module file plus
    two attacker-controlled symlink entries, mirroring RED18b point 3's exact
    repro scenarios."""
    project = tmp_path / name
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    (mod / "__manifest__.py").write_text("{'name': 'mod1', 'depends': []}\n", encoding="utf-8")
    (mod / "evil_link_abs").symlink_to("/etc/passwd")
    (mod / "evil_link_rel").symlink_to("../../x")
    ref = _commit_all(project, "symlink attack (RED18b point 3)")
    return project, ref


def _files_under(root: Path) -> set[Path]:
    if not root.exists():
        return set()
    return {p for p in root.rglob("*") if p.is_file() or p.is_symlink()}


# ==========================================================================
# (1) PATH TRAVERSAL -- leading "../.." (the exact RED18b point 2 repro:
#     "custom-addons/../../PWNED-harness-preflight.sh"). FIXED function fails
#     closed and writes NOTHING outside $dest; the pre-fix function escapes.
# ==========================================================================
@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_leading_dotdot_traversal_is_blocked(tmp_path, script):
    project, ref = _make_traversal_project(
        tmp_path, f"trav-lead-{script.stem}", ["..", "..", "PWNED-harness-preflight.sh"]
    )
    # Sanity: confirm git really does emit the ".." components verbatim before
    # asserting anything about the harness's handling of them.
    lst = _git(["ls-tree", "-r", ref, "--", "custom-addons"], project).stdout.decode()
    assert "custom-addons/../../PWNED-harness-preflight.sh" in lst, lst

    fn_src = _extract_materialize_fn(script)
    dest = tmp_path / f"dest-lead-{script.stem}"
    escape_target = dest.parent / "PWNED-harness-preflight.sh"  # 2x ".." from dest/custom-addons/

    before_outside = _files_under(tmp_path) - _files_under(dest)
    result = _run_materialize(fn_src, project, ref, dest)
    after_outside = _files_under(tmp_path) - _files_under(dest)

    assert result.returncode != 0, (
        f"{script.name}: expected the leading '../..' traversal to fail closed, "
        f"got exit 0: {result.stdout!r} {result.stderr!r}"
    )
    assert not escape_target.exists(), (
        f"{script.name}: PWNED-harness-preflight.sh was written OUTSIDE the snapshot "
        f"dir at {escape_target} -- path traversal was NOT blocked"
    )
    assert after_outside == before_outside, (
        f"{script.name}: materialization created file(s) outside $dest despite failing: "
        f"{after_outside - before_outside}"
    )


@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_leading_dotdot_traversal_escapes_under_old_unsanitized_fn(tmp_path, script):
    """Non-vacuousness control: the SAME attack against the pre-fix function
    body DOES escape $dest and DOES write the attacker file -- proving the
    assertions in test_leading_dotdot_traversal_is_blocked actually
    discriminate fixed-vs-vulnerable code."""
    project, ref = _make_traversal_project(
        tmp_path, f"trav-lead-old-{script.stem}", ["..", "..", "PWNED-harness-preflight.sh"]
    )
    dest = tmp_path / f"dest-lead-old-{script.stem}"
    escape_target = dest.parent / "PWNED-harness-preflight.sh"

    result = _run_materialize(OLD_UNSANITIZED_FN, project, ref, dest)

    assert result.returncode == 0, (
        "expected the pre-fix function to succeed (no sanitization) -- it did not, "
        f"so this control no longer reproduces RED18b: {result.stdout!r} {result.stderr!r}"
    )
    assert escape_target.exists(), (
        "expected the pre-fix function to write PWNED-harness-preflight.sh OUTSIDE "
        "$dest (the RED18b point 2 finding) -- it did not, so this control no longer "
        "reproduces RED18b"
    )
    assert escape_target.read_bytes() == b"#!/bin/sh\necho PWNED\n"


# ==========================================================================
# (2) PATH TRAVERSAL -- ".." in the MIDDLE of the path (not merely a prefix),
#     e.g. "custom-addons/foo/../../../PWNED-mid.sh".
# ==========================================================================
@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_middle_dotdot_traversal_is_blocked(tmp_path, script):
    project, ref = _make_traversal_project(
        tmp_path, f"trav-mid-{script.stem}", ["foo", "..", "..", "..", "PWNED-mid.sh"]
    )
    lst = _git(["ls-tree", "-r", ref, "--", "custom-addons"], project).stdout.decode()
    assert "custom-addons/foo/../../../PWNED-mid.sh" in lst, lst

    fn_src = _extract_materialize_fn(script)
    dest = tmp_path / f"dest-mid-{script.stem}"
    escape_target = dest.parent / "PWNED-mid.sh"

    before_outside = _files_under(tmp_path) - _files_under(dest)
    result = _run_materialize(fn_src, project, ref, dest)
    after_outside = _files_under(tmp_path) - _files_under(dest)

    assert result.returncode != 0, (
        f"{script.name}: expected the mid-path '..' traversal to fail closed, "
        f"got exit 0: {result.stdout!r} {result.stderr!r}"
    )
    assert not escape_target.exists(), (
        f"{script.name}: PWNED-mid.sh was written OUTSIDE the snapshot dir at "
        f"{escape_target} -- the mid-path '..' component was NOT blocked"
    )
    assert after_outside == before_outside, (
        f"{script.name}: materialization created file(s) outside $dest despite failing: "
        f"{after_outside - before_outside}"
    )


@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_middle_dotdot_traversal_escapes_under_old_unsanitized_fn(tmp_path, script):
    project, ref = _make_traversal_project(
        tmp_path, f"trav-mid-old-{script.stem}", ["foo", "..", "..", "..", "PWNED-mid.sh"]
    )
    dest = tmp_path / f"dest-mid-old-{script.stem}"
    escape_target = dest.parent / "PWNED-mid.sh"

    result = _run_materialize(OLD_UNSANITIZED_FN, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    assert escape_target.exists(), (
        "expected the pre-fix function to also escape via a mid-path '..' component "
        "-- it did not, so this control no longer reproduces RED18b"
    )


# ==========================================================================
# (3) PATH TRAVERSAL -- a ".." component whose NET resolution still lands
#     inside $dest ("custom-addons/a/../../b" -> dest/b) must STILL be
#     rejected. This proves the fix's LEXICAL (component-wise) rule is doing
#     real, independent work -- not merely a "does it resolve outside $dest"
#     containment check, which this specific path would satisfy trivially.
# ==========================================================================
@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_dotdot_traversal_that_nets_inside_dest_is_still_blocked(tmp_path, script):
    project, ref = _make_traversal_project(tmp_path, f"trav-net-{script.stem}", ["a", "..", "..", "b"])
    lst = _git(["ls-tree", "-r", ref, "--", "custom-addons"], project).stdout.decode()
    assert "custom-addons/a/../../b" in lst, lst

    fn_src = _extract_materialize_fn(script)
    dest = tmp_path / f"dest-net-{script.stem}"

    result = _run_materialize(fn_src, project, ref, dest)

    assert result.returncode != 0, (
        f"{script.name}: 'custom-addons/a/../../b' nets out to a path INSIDE $dest, "
        "but must still be rejected by the lexical '..'-component rule -- a pure "
        "post-hoc containment check would wrongly let this one through: "
        f"{result.stdout!r} {result.stderr!r}"
    )
    assert not (dest / "b").exists(), f"{script.name}: 'b' was materialized despite the '..' component"


# ==========================================================================
# (4) SYMLINK ESCAPE (RED18b point 3) -- symlink entries (mode 120000) must
#     be skipped, never recreated in $dest, for both an absolute and a
#     relative-traversal target.
# ==========================================================================
@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_symlink_entries_are_not_materialized(tmp_path, script):
    project, ref = _make_symlink_project(tmp_path, f"sym-{script.stem}")
    fn_src = _extract_materialize_fn(script)
    dest = tmp_path / f"dest-sym-{script.stem}"

    result = _run_materialize(fn_src, project, ref, dest)

    assert result.returncode == 0, (
        f"{script.name}: a tree with (rejected) symlink entries alongside a normal "
        f"file should still succeed overall: {result.stdout!r} {result.stderr!r}"
    )
    symlinks_in_dest = [p for p in dest.rglob("*") if p.is_symlink()]
    assert symlinks_in_dest == [], (
        f"{script.name}: symlink entries were materialized into the snapshot: "
        f"{symlinks_in_dest} -- these get bind-mounted into the odoo container"
    )
    # The normal file in the same tree must still materialize correctly --
    # rejecting symlinks must not sacrifice legitimate content.
    manifest = dest / "custom-addons" / "mod1" / "__manifest__.py"
    assert manifest.is_file() and not manifest.is_symlink()
    assert "mod1" in manifest.read_text(encoding="utf-8")


@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_symlink_entries_are_materialized_under_old_unsanitized_fn(tmp_path, script):
    """Non-vacuousness control: the SAME symlink tree against the pre-fix
    function DOES recreate both attacker-controlled symlinks in $dest."""
    project, ref = _make_symlink_project(tmp_path, f"sym-old-{script.stem}")
    dest = tmp_path / f"dest-sym-old-{script.stem}"

    result = _run_materialize(OLD_UNSANITIZED_FN, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    abs_link = dest / "custom-addons" / "mod1" / "evil_link_abs"
    rel_link = dest / "custom-addons" / "mod1" / "evil_link_rel"
    assert abs_link.is_symlink() and os.readlink(abs_link) == "/etc/passwd", (
        "expected the pre-fix function to recreate the absolute-target symlink -- "
        "it did not, so this control no longer reproduces RED18b point 3"
    )
    assert rel_link.is_symlink() and os.readlink(rel_link) == "../../x", (
        "expected the pre-fix function to recreate the relative-traversal symlink -- "
        "it did not, so this control no longer reproduces RED18b point 3"
    )


# ==========================================================================
# (5) REGRESSION -- a normal tree (no traversal, no symlinks) still
#     materializes correctly under the FIXED function: round-trip content,
#     correct paths, no false rejection.
# ==========================================================================
@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_normal_tree_still_materializes_correctly(tmp_path, script):
    project = tmp_path / f"normal-{script.stem}"
    _init_repo(project)
    mod1 = project / "custom-addons" / "mod1"
    mod1.mkdir(parents=True)
    (mod1 / "__manifest__.py").write_text("{'name': 'mod1', 'depends': []}\n", encoding="utf-8")
    nested = mod1 / "static" / "src"
    nested.mkdir(parents=True)
    (nested / "widget.js").write_text("console.log('hi');\n", encoding="utf-8")
    ref = _commit_all(project, "normal commit")

    fn_src = _extract_materialize_fn(script)
    dest = tmp_path / f"dest-normal-{script.stem}"
    result = _run_materialize(fn_src, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    manifest = dest / "custom-addons" / "mod1" / "__manifest__.py"
    widget = dest / "custom-addons" / "mod1" / "static" / "src" / "widget.js"
    assert manifest.read_text(encoding="utf-8") == "{'name': 'mod1', 'depends': []}\n"
    assert widget.read_text(encoding="utf-8") == "console.log('hi');\n"
