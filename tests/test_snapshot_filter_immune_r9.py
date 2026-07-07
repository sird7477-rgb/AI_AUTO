"""R9 ops-defense game (BLUE) fix for RED18 (HIGH, net-new git-exec RCE),
found by an independent adversarial re-verification of the RED17b-2 TOCTOU
fix while it was still uncommitted:

  .ops-game/R9-red18-verify-toctou-fix.md point 5 -- RED17b-2 replaced the
  live-bind-mount TOCTOU with `git -C "$PROJECT" archive "$HARNESS_VALIDATE_REF"
  -- custom-addons | tar -x -C "$HARNESS_SNAPSHOT_DIR"`. The fix's own code
  comment claimed this was "safe against the untrusted project by
  construction" because archive is tree-based. That claim is FALSE for real
  git (verified in the report by direct reproduction, git 2.43.0): `git
  archive` DOES run clean/smudge/textconv/filter conversions declared by the
  archived tree's OWN (committed, attacker-controlled-via-push)
  .gitattributes -- a committed `* filter=evil` plus a (local or global,
  e.g. git-lfs) `filter.evil.smudge=<cmd>` config execs <cmd> during `git
  archive`, with no `--attr-source` flag available to suppress it (unlike
  every other worktree-touching git call in these two scripts). Since
  $HARNESS_VALIDATE_REF is precisely the untrusted pushed tree, this is a
  NET-NEW git-exec RCE reopening the exact threat class this codebase spent
  many rounds closing -- the pre-RED17b-2 bind-mount approach never invoked
  git archive/smudge at all.

  Fix (this diff): replace `git archive | tar -x` in both
  validate-warm.sh and validate-full.sh with a `harness_materialize_tree()`
  function built ONLY from `git ls-tree -r -z <ref> -- custom-addons`
  (enumerate mode/type/oid/path) and `git cat-file blob <oid>` (read the RAW
  stored bytes for each entry, redirected straight to a file -- no shell
  command-substitution mangling). Neither ls-tree nor cat-file ever consults
  .gitattributes or runs a clean/smudge/textconv/filter driver, and neither
  refreshes the index (so no fsmonitor-hook exec either) -- that machinery
  belongs exclusively to worktree-checkout/archive operations, which these
  two plumbing commands do not implement. Executable bit (100755) is
  reapplied from the ls-tree mode; symlink entries (120000) are recreated as
  symlinks from the blob's raw target text (never dereferenced); submodule
  entries (160000) are skipped with a stderr note (never followed). A bad/
  unresolvable ref, or a ref with no (materializable) custom-addons/ content,
  makes the function return non-zero -- the caller then exits 2 with a clear
  message, never a silently-empty-but-"clean" snapshot.

These tests are hermetic: pure git + filesystem, no docker, no network.
Each test extracts the ACTUAL `harness_materialize_tree` function text out of
the real validate-warm.sh / validate-full.sh files (via
`_extract_materialize_fn`) and executes it standalone in a throwaway bash
subprocess -- so a regression to the fixed file directly breaks these tests,
not a reimplementation of what the fix is supposed to do.

Non-vacuousness proof for the positive control specifically:
`test_archive_approach_is_vulnerable_control` runs the exact pre-fix `git
archive <ref> -- custom-addons | tar -x` pattern (the one this diff replaces
-- see the code block quoted in .ops-game/R9-red18-verify-toctou-fix.md point
5) against the SAME evil-filter scenario and shows it DOES let the smudge
command execute and DOES yield corrupted (non-raw) bytes -- i.e. the same
assertions that pass against the FIXED function fail against the pre-fix
approach, proving the positive-control test is discriminating and not
trivially true.
"""
from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
HARNESS_SRC = ODOO_PACK / "validation-harness"
WARM_SH = HARNESS_SRC / "validate-warm.sh"
FULL_SH = HARNESS_SRC / "validate-full.sh"

# The exact pre-fix pattern RED17b-2 shipped and RED18 broke (quoted verbatim
# in .ops-game/R9-red18-verify-toctou-fix.md point 5's reproduction). Used
# ONLY as a negative/vulnerable control to prove the new tests actually
# discriminate -- never as part of the shipped fix.
OLD_ARCHIVE_FN = '''
harness_materialize_tree() {
  local proj="$1" ref="$2" dest="$3"
  mkdir -p "$dest"
  git -C "$proj" archive "$ref" -- custom-addons | tar -x -C "$dest"
}
'''


# --------------------------------------------------------------------------
# shared fixture helpers (self-contained -- deliberately not importing from
# tests/test_harness_validates_pushed_tree_r9.py to keep this file a single
# standalone unit for the RED18 fix)
# --------------------------------------------------------------------------
def _git(args: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=cwd, text=True, capture_output=True, check=check)


def _init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git(["init", "-q"], path)
    _git(["config", "user.email", "t@example.invalid"], path)
    _git(["config", "user.name", "T"], path)


def _commit_all(path: Path, message: str) -> str:
    _git(["add", "-A"], path)
    _git(["commit", "-q", "-m", message], path)
    return _git(["rev-parse", "HEAD"], path).stdout.strip()


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


def _make_evil_project(tmp_path: Path, sentinel: Path, name: str = "evilproj") -> tuple[Path, str]:
    """A repo whose committed tree carries a `.gitattributes` (`* filter=evil`)
    plus a local `filter.evil.smudge` config that both touches `sentinel`
    (proves the command RAN) and emits corrupted content instead of the raw
    bytes (proves WHAT ran) -- the exact RED18 repro scenario, now used to
    assert immunity rather than merely to demonstrate the break."""
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


RAW_BYTES = "<odoo><data>RAW-COMMITTED-BYTES</data></odoo>\n".encode("utf-8")


# ==========================================================================
# (1) POSITIVE CONTROL -- the exact RED18 repro, now asserting immunity, for
#     BOTH validate-warm.sh's and validate-full.sh's copy of the function.
# ==========================================================================
@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_materialize_is_filter_immune_positive_control(tmp_path, script):
    sentinel = tmp_path / "SMUDGE-RAN.sentinel"
    project, ref = _make_evil_project(tmp_path, sentinel, name=f"evilproj-{script.stem}")
    fn_src = _extract_materialize_fn(script)
    dest = tmp_path / f"dest-{script.stem}"

    result = _run_materialize(fn_src, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    assert not sentinel.exists(), (
        "the evil filter.evil.smudge command RAN during materialization -- "
        f"{script.name}'s harness_materialize_tree is NOT filter-immune"
    )
    out_file = dest / "custom-addons" / "mod1" / "views.xml"
    assert out_file.exists(), result.stderr
    got = out_file.read_bytes()
    assert got == RAW_BYTES, (
        f"materialized content was smudged ({got!r}) instead of the RAW committed "
        f"bytes ({RAW_BYTES!r}) -- {script.name} is running a content filter"
    )


# ==========================================================================
# (1b) Non-vacuousness control: the SAME scenario against the exact pre-fix
#      `git archive | tar -x` pattern DOES let the smudge command execute and
#      DOES yield corrupted content -- proving the assertions above actually
#      discriminate fixed-vs-vulnerable code, not trivially true.
# ==========================================================================
def test_archive_approach_is_vulnerable_control(tmp_path):
    sentinel = tmp_path / "SMUDGE-RAN.sentinel"
    project, ref = _make_evil_project(tmp_path, sentinel, name="evilproj-old")
    dest = tmp_path / "dest-old"

    result = _run_materialize(OLD_ARCHIVE_FN, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    assert sentinel.exists(), (
        "expected the pre-fix `git archive | tar -x` pattern to let the evil "
        "smudge filter execute (this is the RED18 finding) -- it did not, which "
        "means this control scenario no longer reproduces RED18 and the positive-"
        "control test above may be vacuous"
    )
    out_file = dest / "custom-addons" / "mod1" / "views.xml"
    got = out_file.read_bytes()
    assert got != RAW_BYTES, (
        "expected the pre-fix archive approach to yield SMUDGED (non-raw) content "
        "-- it materialized the raw bytes instead, so this control no longer "
        "reproduces RED18"
    )


# ==========================================================================
# (2) round-trip: a normal file's snapshot content == its committed content,
#     byte-for-byte (including bytes that are not valid UTF-8).
# ==========================================================================
@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_materialize_round_trip_byte_identical(tmp_path, script):
    project = tmp_path / f"rt-{script.stem}"
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    (mod / "__manifest__.py").write_text("{'name': 'mod1', 'depends': []}\n", encoding="utf-8")
    # Deliberately not valid UTF-8 / has no trailing newline, to catch any
    # text-mode or newline-normalizing mishandling in the materializer.
    binary_content = b"\x00\x01\xffodoo-binary-ish-blob\xfe\xfd no trailing newline"
    (mod / "blob.dat").write_bytes(binary_content)
    ref = _commit_all(project, "normal commit")

    fn_src = _extract_materialize_fn(script)
    dest = tmp_path / f"dest-rt-{script.stem}"
    result = _run_materialize(fn_src, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    out_file = dest / "custom-addons" / "mod1" / "blob.dat"
    assert out_file.read_bytes() == binary_content, (
        "round-tripped bytes differ from the committed blob -- materialization "
        "is not byte-identical"
    )


# ==========================================================================
# (3) executable bit is preserved (100755 -> +x), and a non-executable file
#     stays non-executable.
# ==========================================================================
@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_materialize_preserves_executable_bit(tmp_path, script):
    project = tmp_path / f"exe-{script.stem}"
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    (mod / "__manifest__.py").write_text("{'name': 'mod1', 'depends': []}\n", encoding="utf-8")
    script_file = mod / "run.sh"
    script_file.write_text("#!/bin/sh\necho hi\n", encoding="utf-8")
    script_file.chmod(script_file.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    plain_file = mod / "plain.txt"
    plain_file.write_text("not executable\n", encoding="utf-8")
    plain_file.chmod(plain_file.stat().st_mode & ~stat.S_IXUSR & ~stat.S_IXGRP & ~stat.S_IXOTH)
    ref = _commit_all(project, "exe bit commit")
    # Sanity: confirm git actually recorded the differing modes before testing materialization.
    lstree = _git(["ls-tree", "-r", ref, "--", "custom-addons"], project).stdout
    assert "100755" in lstree and "run.sh" in lstree, lstree
    assert "100644" in lstree and "plain.txt" in lstree, lstree

    fn_src = _extract_materialize_fn(script)
    dest = tmp_path / f"dest-exe-{script.stem}"
    result = _run_materialize(fn_src, project, ref, dest)

    assert result.returncode == 0, (result.stdout, result.stderr)
    out_script = dest / "custom-addons" / "mod1" / "run.sh"
    out_plain = dest / "custom-addons" / "mod1" / "plain.txt"
    assert out_script.stat().st_mode & stat.S_IXUSR, "executable bit was NOT preserved"
    assert not (out_plain.stat().st_mode & stat.S_IXUSR), "a plain file became executable"


# ==========================================================================
# (4) fail-closed on a bad ref: non-zero exit, no partial/empty-but-"valid"
#     snapshot silently accepted.
# ==========================================================================
@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_materialize_fails_closed_on_bad_ref(tmp_path, script):
    project = tmp_path / f"badref-{script.stem}"
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    (mod / "__manifest__.py").write_text("{'name': 'mod1', 'depends': []}\n", encoding="utf-8")
    _commit_all(project, "v1")

    fn_src = _extract_materialize_fn(script)
    dest = tmp_path / f"dest-badref-{script.stem}"
    result = _run_materialize(fn_src, project, "0" * 40, dest)

    assert result.returncode != 0, (
        "a bad/unresolvable ref must fail closed (non-zero), not silently "
        f"succeed: {result.stdout!r} {result.stderr!r}"
    )
    produced = list((dest / "custom-addons").rglob("*")) if (dest / "custom-addons").exists() else []
    assert produced == [], f"a bad ref produced snapshot content anyway: {produced}"


@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_materialize_fails_closed_when_ref_has_no_custom_addons(tmp_path, script):
    """A valid, resolvable ref that simply has no custom-addons/ tree must
    also fail closed (matches the pre-fix `git archive` behavior of a hard
    'pathspec did not match any files' error) -- never a silently-empty-but-
    "validated" snapshot that lets a downstream check read an empty dir as
    a clean pass."""
    project = tmp_path / f"nocustom-{script.stem}"
    _init_repo(project)
    (project / "README.md").write_text("no custom-addons here\n", encoding="utf-8")
    ref = _commit_all(project, "no custom-addons")

    fn_src = _extract_materialize_fn(script)
    dest = tmp_path / f"dest-nocustom-{script.stem}"
    result = _run_materialize(fn_src, project, ref, dest)

    assert result.returncode != 0, (
        "a ref with no custom-addons/ tree must fail closed: "
        f"{result.stdout!r} {result.stderr!r}"
    )


# ==========================================================================
# (5) static confirmation: no conversion-running git command (archive/
#     checkout/worktree add) remains in either script, outside of comment
#     lines documenting the fix's rationale; ls-tree + cat-file ARE present.
# ==========================================================================
@pytest.mark.parametrize("script", [WARM_SH, FULL_SH], ids=["validate-warm.sh", "validate-full.sh"])
def test_no_conversion_running_git_command_is_used(script):
    lines = script.read_text(encoding="utf-8").splitlines()
    code_only = "\n".join(l for l in lines if not l.lstrip().startswith("#"))

    assert "git archive" not in code_only, f"{script.name} still invokes `git archive` in code"
    assert "git checkout" not in code_only, f"{script.name} still invokes `git checkout` in code"
    assert "worktree add" not in code_only, f"{script.name} still invokes `git worktree add` in code"
    assert "--textconv" not in code_only, f"{script.name} invokes a textconv-converting git call"

    assert "ls-tree -r -z" in code_only, f"{script.name} does not use `git ls-tree -r -z`"
    assert "cat-file blob" in code_only, f"{script.name} does not use `git cat-file blob`"
