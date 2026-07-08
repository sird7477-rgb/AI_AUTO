"""R9-DRIFT / RED-4 fix: `git cat-file blob <oid>` false-positive + collect-review-context.sh
`$@`-forwarding blind spot.

.ops-game2/R1-red4-quality-gitregression.md (RED-1, HIGH, LIVE) found the tree-wide
git-exec drift-guard embedded in scripts/verify-machinery.sh (the `R9-DRIFT` python heredoc,
around line 11257) FAILING when actually run against HEAD: it flagged the 3
`git cat-file blob "$oid"` sites in the validate-warm/full/odoo.sh RED17b-2 snapshot
materializer (a canary-proven FILTER-IMMUNE object-database read, not a reopened clean/smudge
RCE) and 2 lines in collect-review-context.sh's `post_commit_range_diff` (a `$@`-forwarding
helper the guard's static, per-line rule 2 cannot see through).

These tests extract the guard's EXACT python body verbatim out of the shipped heredoc (never a
reimplementation -- a reimplementation could silently diverge from what verify-machinery.sh
actually runs) and execute it for real, three ways:

  1. against this repo's real HEAD tree            -> must report ZERO violations.
  2. against a tmp tree with a planted, genuinely-unhardened NEW `git diff` / `git status`
     call                                            -> must STILL be caught (the cat-file
                                                         exemption must not have gone blind).
  3. against a tmp tree with a planted `git cat-file --textconv`/`--filters` call
                                                       -> must STILL be caught (the exemption
                                                         is narrow: bare object reads only, not
                                                         a blanket `cat-file` pass).

A 4th class of test proves each fix is load-bearing (not a vacuous no-op). Earlier revisions of
this file did this by re-extracting the PRE-FIX guard body / PRE-FIX collect-review-context.sh
content via `git show HEAD:<path>` -- but that only proves anything while HEAD is still the
pre-fix commit. The moment the fix is committed, HEAD becomes the POST-fix state and `git show
HEAD:` silently hands back the FIXED code, so the "pre-fix must misbehave" assertion fails
against a perfectly healthy fixed tree (a systemic defect, not specific to this file). Fixed by
embedding each PRE-FIX code shape as a LITERAL (a tiny predicate function, or a short inline
heredoc string) directly in this file, verified once against the actual pre-fix commit
(2209dd6's parent) at authoring time and pinned here forever after -- no runtime git dependency.
The CURRENT/fixed guard is still extracted live from the WORKING-TREE file on disk (that is what
actually ships), so a real future regression in verify-machinery.sh is still caught; only the
PRE-FIX contrast is now a durable literal instead of a moving ref. "Revert -> FAIL" for each fix,
independently, forever -- not just until the next commit.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
VERIFY_MACHINERY = ROOT / "scripts" / "verify-machinery.sh"
COLLECT_REVIEW_CONTEXT = ROOT / "scripts" / "collect-review-context.sh"

HEREDOC_OPEN = "cat > \"${guard}\" <<'PYEOF'"
HEREDOC_CLOSE = "PYEOF"


def _extract_r9_drift_guard(script_text: str) -> str:
    """Pull the R9-DRIFT guard's python body verbatim out of the shipped heredoc.

    Mirrors exactly what verify-machinery.sh itself does at runtime (`cat > "${guard}"
    <<'PYEOF' ... PYEOF`) -- this is the literal source the shipped test suite executes at
    the assertion on ~line 11660, not a hand-copied approximation of it.
    """
    lines = script_text.splitlines()
    start = end = None
    for i, line in enumerate(lines):
        if line.strip() == HEREDOC_OPEN:
            start = i + 1
        elif start is not None and line == HEREDOC_CLOSE:
            end = i
            break
    assert start is not None and end is not None, (
        "R9-DRIFT guard heredoc markers not found in verify-machinery.sh -- "
        "extraction pattern is stale, fix the test, not the assertion below"
    )
    return "\n".join(lines[start:end]) + "\n"


def _run_guard(guard_src: str, target_root: Path, tmp_path: Path) -> subprocess.CompletedProcess[str]:
    guard_file = tmp_path / f"guard-{len(list(tmp_path.glob('guard-*.py')))}.py"
    guard_file.write_text(guard_src, encoding="utf-8")
    return subprocess.run(
        [sys.executable, str(guard_file), str(target_root)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _mirror_tree(tmp_path: Path, name: str) -> Path:
    """Copy the real repo's scanned subtrees (scripts/hooks/tools/templates) into an isolated
    tmp root, so a test can overwrite ONE file in the copy without touching the real worktree
    (read-only w.r.t. the actual repo; no git write commands anywhere in this file)."""
    dest = tmp_path / name
    for sub in ("scripts", "hooks", "tools", "templates"):
        src = ROOT / sub
        if src.is_dir():
            shutil.copytree(src, dest / sub)
    return dest


# ---------------------------------------------------------------------------
# 1. The CURRENT (fixed) guard, run against the CURRENT (fixed) real tree: zero violations.
# ---------------------------------------------------------------------------

def test_guard_passes_clean_at_head(tmp_path: Path) -> None:
    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    proc = _run_guard(guard_src, ROOT, tmp_path)
    assert proc.returncode == 0, (
        "R9-DRIFT guard should report ZERO violations against the fixed HEAD tree; got:\n"
        f"stdout={proc.stdout}\nstderr={proc.stderr}"
    )
    assert "R9-DRIFT OK" in proc.stdout
    assert "VIOLATIONS" not in proc.stderr


# ---------------------------------------------------------------------------
# 2. A genuinely-unhardened NEW git call must still be caught (exemption didn't blind the guard).
# ---------------------------------------------------------------------------

def test_guard_still_catches_planted_unhardened_diff(tmp_path: Path) -> None:
    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "new-bad.sh").write_text(
        'git -C "$P" diff --name-only HEAD\n', encoding="utf-8"
    )
    proc = _run_guard(guard_src, fake, tmp_path)
    assert proc.returncode == 1, "planted bare worktree `git diff` must be flagged, not silently passed"
    assert "new-bad.sh" in proc.stderr
    assert "R9-DRIFT VIOLATIONS" in proc.stderr


def test_guard_still_catches_planted_unhardened_status(tmp_path: Path) -> None:
    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "new-bad-status.sh").write_text(
        'git -C "$P" status --porcelain\n', encoding="utf-8"
    )
    proc = _run_guard(guard_src, fake, tmp_path)
    assert proc.returncode == 1, "planted bare `git status` must still be flagged"
    assert "new-bad-status.sh" in proc.stderr


# ---------------------------------------------------------------------------
# 3. The cat-file exemption is NARROW: --textconv / --filters cat-file calls stay guarded.
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("bad_line", [
    'git -C "$proj" cat-file --textconv HEAD:some/path > "$out" || return 1\n',
    'git -C "$proj" cat-file --filters HEAD:some/path > "$out" || return 1\n',
])
def test_guard_still_catches_cat_file_textconv_and_filters(tmp_path: Path, bad_line: str) -> None:
    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "bad-catfile.sh").write_text(bad_line, encoding="utf-8")
    proc = _run_guard(guard_src, fake, tmp_path)
    assert proc.returncode == 1, (
        "a `git cat-file --textconv`/`--filters` call explicitly requests the filter driver "
        "and must NOT be swept up in the bare-object-read exemption"
    )
    assert "bad-catfile.sh" in proc.stderr


def test_guard_still_exempts_bare_cat_file_blob(tmp_path: Path) -> None:
    """Positive control: the exact shipped form (`cat-file blob "$oid"`, no --textconv/--filters)
    must pass -- proves the exemption is not merely theoretical/never-taken."""
    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "ok-catfile.sh").write_text(
        'git -C "$proj" cat-file blob "$oid" > "$outpath" || return 1\n', encoding="utf-8"
    )
    proc = _run_guard(guard_src, fake, tmp_path)
    assert proc.returncode == 0, (
        f"bare `cat-file blob <oid>` (filter-immune object read) must NOT be flagged; got:\n"
        f"stderr={proc.stderr}"
    )


# ---------------------------------------------------------------------------
# 3b. F6 (canary-confirmed): the cat-file exemption used LITERAL-SUBSTRING matching
#     (`"--textconv" not in line and "--filters" not in line`), which an unambiguous git OPTION
#     ABBREVIATION defeats -- `--text`/`--textc`/`--filt` run the identical filter/textconv driver
#     but do not contain the flagged substring. The fix inverts to an allowlist: exempt cat-file
#     ONLY when none of its argument tokens start with `--` at all (short options -p/-t/-s/-e are
#     unaffected -- git does not abbreviate them and none run a filter).
# ---------------------------------------------------------------------------

def _pre_f6_cat_file_object_read(line: str) -> bool:
    """Embedded literal reproduction of the PRE-F6-fix `cat_file_object_read` predicate's
    substring-matching half (verbatim, once `sub == "cat-file"` is already established by the
    caller): `"--textconv" not in line and "--filters" not in line`. This is EXACTLY the literal
    substring check that shipped before F6 and that an unambiguous git option ABBREVIATION
    (`--text`/`--textc`/`--filt`/`--filte`) defeats -- embedded here so this non-vacuousness
    proof never depends on a moving `git show HEAD:` ref (see the F6 fix comment in
    scripts/verify-machinery.sh, "a literal-SUBSTRING check ... is defeated by any unambiguous
    OPTION ABBREVIATION", for provenance)."""
    return "--textconv" not in line and "--filters" not in line


@pytest.mark.parametrize("bad_line", [
    'git -C "$proj" cat-file --text HEAD:some/path > "$out" || return 1\n',
    'git -C "$proj" cat-file --textc HEAD:some/path > "$out" || return 1\n',
])
def test_guard_flags_abbreviated_textconv_catfile(tmp_path: Path, bad_line: str) -> None:
    """NON-VACUOUS: the embedded PRE-F6 substring predicate must WRONGLY treat this abbreviated
    `--textconv` cat-file call as an exempt bare object read (proving the bug class), while the
    CURRENT allowlist guard -- extracted from the real, on-disk, shipped verify-machinery.sh --
    must flag it."""
    assert _pre_f6_cat_file_object_read(bad_line) is True, (
        "revert -> FAIL evidence: the PRE-F6 substring-matching predicate must WRONGLY exempt an "
        f"abbreviated `--textconv` cat-file call (that is the defect F6 fixed): {bad_line!r}"
    )

    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "bad-catfile-abbrev-textconv.sh").write_text(bad_line, encoding="utf-8")

    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    proc = _run_guard(current_guard_src, fake, tmp_path)
    assert proc.returncode == 1, (
        "the FIXED allowlist guard must flag an abbreviated `--text`/`--textc` cat-file call "
        f"(any long option disqualifies the exemption); got:\n"
        f"stdout={proc.stdout}\nstderr={proc.stderr}"
    )
    assert "bad-catfile-abbrev-textconv.sh" in proc.stderr


@pytest.mark.parametrize("bad_line", [
    'git -C "$proj" cat-file --filt HEAD:some/path > "$out" || return 1\n',
    'git -C "$proj" cat-file --filte HEAD:some/path > "$out" || return 1\n',
])
def test_guard_flags_abbreviated_filters_catfile(tmp_path: Path, bad_line: str) -> None:
    """NON-VACUOUS: the embedded PRE-F6 substring predicate must WRONGLY treat this abbreviated
    `--filters` cat-file call as an exempt bare object read (proving the bug class), while the
    CURRENT allowlist guard -- extracted from the real, on-disk, shipped verify-machinery.sh --
    must flag it."""
    assert _pre_f6_cat_file_object_read(bad_line) is True, (
        "revert -> FAIL evidence: the PRE-F6 substring-matching predicate must WRONGLY exempt an "
        f"abbreviated `--filters` cat-file call (that is the defect F6 fixed): {bad_line!r}"
    )

    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "bad-catfile-abbrev-filters.sh").write_text(bad_line, encoding="utf-8")

    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    proc = _run_guard(current_guard_src, fake, tmp_path)
    assert proc.returncode == 1, (
        "the FIXED allowlist guard must flag an abbreviated `--filt`/`--filte` cat-file call "
        f"(any long option disqualifies the exemption); got:\n"
        f"stdout={proc.stdout}\nstderr={proc.stderr}"
    )
    assert "bad-catfile-abbrev-filters.sh" in proc.stderr


@pytest.mark.parametrize("ok_line", [
    'git -C "$proj" cat-file blob "$oid" > "$outpath" || return 1\n',
    'git -C "$proj" cat-file -p "$oid" > "$outpath" || return 1\n',
    'git -C "$proj" cat-file -t "$oid" > "$outpath" || return 1\n',
])
def test_guard_still_exempts_bare_and_short_catfile(tmp_path: Path, ok_line: str) -> None:
    """No over-strict regression: the real shipped form (bare object type/blob read) and the
    short-option forms (`-p`/`-t`, which git never abbreviates and which never invoke a filter)
    must stay exempt under the new allowlist logic."""
    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "ok-catfile-short.sh").write_text(ok_line, encoding="utf-8")
    proc = _run_guard(guard_src, fake, tmp_path)
    assert proc.returncode == 0, (
        f"bare/short-option `cat-file` object read must NOT be flagged; got:\n"
        f"stdout={proc.stdout}\nstderr={proc.stderr}"
    )


# ---------------------------------------------------------------------------
# 4. "revert -> FAIL": each half of the fix is independently load-bearing. Earlier versions of
#    these 3 tests re-extracted PRE-FIX source straight from `git show HEAD:<path>` at test time
#    -- which only proves anything while HEAD is still the pre-fix commit. Once the fix is
#    committed, HEAD becomes the FIXED state and `git show HEAD:` silently hands back the fixed
#    code, so "revert -> FAIL" degenerates into a guard-clause self-skip (an
#    already-fixed-at-HEAD assertion failure) forever after. Fixed by embedding each PRE-FIX code
#    shape as a LITERAL constant/function below, pinned once against the real pre-fix commit
#    (2209dd6's parent) at authoring time -- never re-read from git at test time. The CURRENT/
#    fixed guard is still extracted LIVE from the real, on-disk, shipped verify-machinery.sh (via
#    `_extract_r9_drift_guard(VERIFY_MACHINERY.read_text(...))`), so a real future regression is
#    still caught.
# ---------------------------------------------------------------------------

def _pre_r9drift_catfile_would_violate(line: str, via_review_git: bool = False) -> bool:
    """Embedded literal reproduction of the rule-4 cat-file gate as it existed BEFORE the
    R9-DRIFT/RED-4 guard-side fix (commit 2209dd6): `cat-file` carried NO bare-object-read
    exemption at all and fell straight into the SAME unconditional attr-source + core.fsmonitor
    gate as status/checkout/restore/reset/stash/apply/archive:

        if sub in (..., "cat-file"):
            if "--attr-source=" not in line and not via_review_git:
                violations.append(...)          # clean-filter RCE vector
            if not via_review_git and "core.fsmonitor=" not in line:
                violations.append(...)           # fsmonitor RCE vector

    (see 2209dd6's diff hunk to scripts/verify-machinery.sh, rule 4, for provenance). Embedded
    here as a literal so this non-vacuousness proof never depends on a moving `git show HEAD:`
    ref."""
    if via_review_git:
        return False
    return ("--attr-source=" not in line) or ("core.fsmonitor=" not in line)


# Embedded literal reproduction of collect-review-context.sh's `post_commit_range_diff` as it
# existed BEFORE the R9-DRIFT/RED-4 fix (commit 2209dd6): the `--no-ext-diff`/`--no-textconv`
# flags were NOT baked into the chokepoint -- they depended on the caller forwarding them via
# `"$@"`, a blind spot the static, per-line guard cannot see through. Pinned here as a literal
# (verified against 2209dd6's parent at authoring time) so this proof never depends on git HEAD.
PRE_FIX_POST_COMMIT_RANGE_DIFF = '''#!/usr/bin/env bash
# Embedded PRE-FIX (before 2209dd6) reproduction of post_commit_range_diff: the
# --no-ext-diff/--no-textconv flags are NOT baked in here -- they depend on the
# caller supplying them via "$@", which the static R9-DRIFT guard cannot see
# through to (the `$@`-forwarding blind spot this fix closed).
post_commit_range_diff() {
  local base="$1"
  shift
  if [ "${base}" = "$(review_binding_empty_tree)" ]; then
    review_git diff "$@" "${base}" HEAD 2>/dev/null
  else
    review_git diff "$@" "${base}...HEAD" 2>/dev/null
  fi
}
'''


def test_revert_guard_side_fix_reopens_cat_file_false_positive(tmp_path: Path) -> None:
    """Isolate the guard-side fix: the embedded PRE-FIX predicate (no cat-file exemption) must
    WRONGLY flag the real shipped form of a bare, filter-immune `cat-file blob "$oid"` object
    read (proving the bug class RED-1 found), while the CURRENT guard -- extracted from the
    real, on-disk, shipped verify-machinery.sh -- must exempt it."""
    bare_cat_file_line = 'git -C "$proj" cat-file blob "$oid" > "$outpath" || return 1'
    assert _pre_r9drift_catfile_would_violate(bare_cat_file_line), (
        "revert -> FAIL evidence: pre-R9-DRIFT-fix cat-file had no bare-object-read exemption "
        f"at all and would wrongly flag this bare, filter-immune cat-file read: {bare_cat_file_line!r}"
    )

    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "validate-warm.sh").write_text(bare_cat_file_line + "\n", encoding="utf-8")
    proc = _run_guard(current_guard_src, fake, tmp_path)
    assert proc.returncode == 0, (
        "the FIXED guard must exempt the bare cat-file read (matching the shipped "
        f"validate-warm/full/odoo.sh form); got:\nstdout={proc.stdout}\nstderr={proc.stderr}"
    )


def test_revert_collect_review_context_fix_reopens_dollar_at_blind_spot(tmp_path: Path) -> None:
    """Isolate the collect-review-context.sh fix: run the CURRENT (fixed) guard -- extracted
    live from the real, on-disk, shipped verify-machinery.sh -- against a tree mirror where ONLY
    collect-review-context.sh is swapped for the embedded PRE-FIX literal (`$@`-forwarding, no
    baked-in flags). Must reproduce the original 4 `--no-ext-diff`/`--no-textconv` violations
    (2 diff calls x 2 required flags each)."""
    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    mirror = _mirror_tree(tmp_path, "mirror-revert-crc")
    (mirror / "scripts" / "collect-review-context.sh").write_text(
        PRE_FIX_POST_COMMIT_RANGE_DIFF, encoding="utf-8"
    )
    proc = _run_guard(current_guard_src, mirror, tmp_path)
    assert proc.returncode == 1, (
        "reverting collect-review-context.sh alone must reopen its 2 flagged diff calls; got:\n"
        f"stdout={proc.stdout}\nstderr={proc.stderr}"
    )
    assert proc.stderr.count("collect-review-context.sh:") == 4, (
        f"expected exactly 4 violations (2 diff calls x --no-ext-diff/--no-textconv), got:\n{proc.stderr}"
    )
    assert "MISSING --no-ext-diff" in proc.stderr
    assert "MISSING --no-textconv" in proc.stderr


def test_revert_both_fixes_reproduces_original_ten_violations(tmp_path: Path) -> None:
    """Combined revert: BOTH pre-fix defects together must reproduce the original RED-1 scope --
    3 cat-file sites (2 checks each: attr-source + fsmonitor => 6) + 2 collect-review-context.sh
    diff calls (2 checks each: --no-ext-diff + --no-textconv => 4) => 10. The cat-file half is
    proven via the embedded literal predicate (guard-side fix is not independently runnable as a
    full guard without reconstructing the whole heredoc -- see the tiny-predicate test above);
    the collect-review-context.sh half is proven by actually running the CURRENT real guard,
    extracted live from disk, against the embedded PRE-FIX literal. Together this shows the two
    fixes are independent and additive -- reverting either alone reopens exactly its own share,
    reverting both reopens the full original count."""
    bare_cat_file_line = 'git -C "$proj" cat-file blob "$oid" > "$outpath" || return 1'
    # 3 real shipped sites (validate-warm.sh / validate-full.sh / validate-odoo.sh), all the
    # identical bare shape -- each would cost 2 violations (attr-source + fsmonitor) pre-fix.
    cat_file_pre_fix_violations = 0
    for _ in range(3):
        if _pre_r9drift_catfile_would_violate(bare_cat_file_line):
            cat_file_pre_fix_violations += 2
    assert cat_file_pre_fix_violations == 6, (
        "revert -> FAIL evidence: all 3 real cat-file sites must reopen under the pre-fix "
        f"(no-exemption) predicate; got {cat_file_pre_fix_violations} violations"
    )

    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    mirror = _mirror_tree(tmp_path, "mirror-revert-both")
    (mirror / "scripts" / "collect-review-context.sh").write_text(
        PRE_FIX_POST_COMMIT_RANGE_DIFF, encoding="utf-8"
    )
    proc = _run_guard(current_guard_src, mirror, tmp_path)
    assert proc.returncode == 1
    crc_violations = proc.stderr.count("collect-review-context.sh:")
    assert crc_violations == 4, (
        f"expected 4 collect-review-context.sh violations, got {crc_violations}:\n{proc.stderr}"
    )

    assert cat_file_pre_fix_violations + crc_violations == 10, (
        "combined pre-fix violation count must match RED-1's originally-reported scope "
        f"(3 cat-file sites x 2 + 2 diff calls x 2 = 10); got "
        f"{cat_file_pre_fix_violations} + {crc_violations} = {cat_file_pre_fix_violations + crc_violations}"
    )


# ---------------------------------------------------------------------------
# 5. F7 (canary-proven false-negative, ops-defense2 game #2 R4): the HARDENING-MARKER checks
#    themselves (rules 3/4/5/6/7/8's "--attr-source=" / "core.fsmonitor=" / "core.hooksPath=" /
#    "--no-ext-diff" / "--no-textconv" substring tests) ran against the WHOLE (logical) line,
#    unscoped to the SPECIFIC matched git invocation -- and only the FIRST git invocation on a
#    line was ever inspected (`INVOKE.search` stops at its first match). Two exploit shapes both
#    made the guard report ZERO violations for a genuinely-unguarded call:
#      (1) a trailing shell COMMENT carrying a hardening-marker substring
#          (`git <dangerous> ...  # ... --attr-source= ...`);
#      (2) a SECOND, chained git call on the same line supplying the marker
#          (`git <dangerous> ; git <hardened> --attr-source=...`).
#    Fixed by (a) stripping a trailing shell comment before any marker test (COMMENT_RE), and
#    (b) bounding the marker checks to the SAME shell command as the matched invocation via
#    CMD_SEP + _owning_segment (split on `;`/`&`/`&&`/`|`/`||`/backtick -- the same separator
#    alphabet the F6 cat-file allowlist already used). Both are proven non-vacuous below the same
#    way F6 was: an embedded literal reproduction of the PRE-F7 whole-line substring predicate
#    that WRONGLY passes each exploit shape, contrasted with the CURRENT guard (extracted live
#    from the real, on-disk, shipped verify-machinery.sh) which must flag it.
# ---------------------------------------------------------------------------

def _pre_f7_marker_present_wholeline(line: str, marker: str) -> bool:
    """Embedded literal reproduction of the PRE-F7 hardening-marker test: a bare, UNSCOPED
    whole-line substring check (`marker in line`), exactly as every rule 3/4/5/6/7/8 check used
    to read (e.g. `"--attr-source=" not in line`). This is the literal predicate F7 replaced with
    the CMD_SEP/_owning_segment-bounded version -- embedded here so the non-vacuousness proof
    never depends on a moving `git show HEAD:` ref."""
    return marker in line


@pytest.mark.parametrize(
    "marker", ["--attr-source=", "core.fsmonitor=", "core.hooksPath="]
)
def test_guard_flags_dangerous_call_with_trailing_comment_marker(tmp_path: Path, marker: str) -> None:
    """NON-VACUOUS (exploit shape 1, trailing comment): a genuinely bare, unhardened `git status`
    followed by a trailing shell COMMENT that happens to carry a hardening-marker substring must
    still be FLAGGED by the current (fixed) guard -- the comment must not be able to vouch for a
    command it does not actually decorate. The embedded PRE-F7 whole-line predicate wrongly treats
    the marker as present (proving the bug class)."""
    bad_line = (
        'git status --porcelain  '
        '# decoy comment, NOT a real flag: --attr-source= core.fsmonitor= core.hooksPath=\n'
    )
    assert _pre_f7_marker_present_wholeline(bad_line, marker) is True, (
        "revert -> FAIL evidence: the PRE-F7 whole-line substring predicate must WRONGLY see the "
        f"comment-only {marker!r} as satisfying the hardening requirement: {bad_line!r}"
    )

    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "comment-exploit.sh").write_text(bad_line, encoding="utf-8")

    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    proc = _run_guard(current_guard_src, fake, tmp_path)
    assert proc.returncode == 1, (
        "the FIXED guard must flag a bare `git status` whose only hardening markers live inside a "
        f"trailing comment (not the real command); got:\nstdout={proc.stdout}\nstderr={proc.stderr}"
    )
    assert "comment-exploit.sh" in proc.stderr
    assert "R9-DRIFT VIOLATIONS" in proc.stderr


@pytest.mark.parametrize(
    "marker", ["--attr-source=", "core.fsmonitor=", "core.hooksPath="]
)
def test_guard_flags_first_call_in_chain_despite_second_calls_markers(tmp_path: Path, marker: str) -> None:
    """NON-VACUOUS (exploit shape 2, chained calls): a bare, unhardened `git status` chained via
    `;` ahead of a SECOND, fully-hardened `git diff` on the SAME line must still get the bare
    `status` FLAGGED -- the second call's --attr-source=/-c core.fsmonitor=/-c core.hooksPath=
    markers live in a different shell command and must not satisfy the first, unrelated one. The
    embedded PRE-F7 whole-line predicate wrongly treats the marker as present (proving the bug
    class)."""
    bad_line = (
        'git status --porcelain ; '
        'git diff --attr-source="$ET" -c core.fsmonitor= -c core.hooksPath=/dev/null '
        '--name-only HEAD\n'
    )
    assert _pre_f7_marker_present_wholeline(bad_line, marker) is True, (
        "revert -> FAIL evidence: the PRE-F7 whole-line substring predicate must WRONGLY see the "
        f"second call's {marker!r} as satisfying the first (bare) call's hardening requirement: "
        f"{bad_line!r}"
    )

    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "chain-exploit.sh").write_text(bad_line, encoding="utf-8")

    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    proc = _run_guard(current_guard_src, fake, tmp_path)
    assert proc.returncode == 1, (
        "the FIXED guard must flag the bare `git status` even though a second, hardened `git diff` "
        f"is chained after it on the same line; got:\nstdout={proc.stdout}\nstderr={proc.stderr}"
    )
    assert "chain-exploit.sh" in proc.stderr
    assert "R9-DRIFT VIOLATIONS" in proc.stderr


def test_guard_flags_bare_call_with_marker_in_earlier_chained_command(tmp_path: Path) -> None:
    """NON-VACUOUS variant: a marker-looking decoy in an EARLIER chained command must not vouch
    for a bare, dangerous call that comes AFTER it on the same line either (segment-scoping must
    work in both directions, not just forward)."""
    bad_line = 'echo "x" --attr-source=fake ; git status --porcelain\n'
    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "earlier-decoy.sh").write_text(bad_line, encoding="utf-8")
    proc = _run_guard(current_guard_src, fake, tmp_path)
    assert proc.returncode == 1, (
        "a bare `git status` chained after an unrelated command carrying a decoy --attr-source= "
        f"must still be flagged; got:\nstdout={proc.stdout}\nstderr={proc.stderr}"
    )
    assert "earlier-decoy.sh" in proc.stderr


# ---------------------------------------------------------------------------
# 6. F7 regressions: legitimately hardened single calls, plain safe lines, and the F6 cat-file
#    forms must all keep behaving exactly as before -- the F7 scoping fix must not manufacture a
#    NEW false-positive (over-strict scoping) any more than the pre-fix bug produced a false-
#    negative (unscoped substring matching).
# ---------------------------------------------------------------------------

def test_guard_still_passes_legitimately_hardened_single_call(tmp_path: Path) -> None:
    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "ok-status.sh").write_text(
        'git -c core.hooksPath=/dev/null --attr-source="$ET" -c core.fsmonitor= status --short\n',
        encoding="utf-8",
    )
    proc = _run_guard(guard_src, fake, tmp_path)
    assert proc.returncode == 0, (
        f"a fully-hardened single `git status` call must NOT be flagged; got:\n"
        f"stdout={proc.stdout}\nstderr={proc.stderr}"
    )


def test_guard_still_passes_plain_safe_line(tmp_path: Path) -> None:
    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "ok-revparse.sh").write_text(
        'git rev-parse --show-toplevel\n', encoding="utf-8"
    )
    proc = _run_guard(guard_src, fake, tmp_path)
    assert proc.returncode == 0, (
        f"`git rev-parse` (not in SUBS at all) must never be flagged; got:\n"
        f"stdout={proc.stdout}\nstderr={proc.stderr}"
    )


def test_guard_still_exempts_bare_catfile_with_trailing_decoy_comment(tmp_path: Path) -> None:
    """F6+F7 interaction: a bare, filter-immune `cat-file blob` read with a trailing comment that
    NAMES --textconv/--filters as prose must stay exempt -- the comment must not be able to
    manufacture a false-POSITIVE any more than it could manufacture a false-negative elsewhere."""
    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "ok-catfile-comment.sh").write_text(
        'git -C "$proj" cat-file blob "$oid" > "$outpath" || return 1  '
        '# note: this is NOT --textconv or --filters\n',
        encoding="utf-8",
    )
    proc = _run_guard(guard_src, fake, tmp_path)
    assert proc.returncode == 0, (
        f"a bare cat-file read with an unrelated trailing comment must stay exempt; got:\n"
        f"stdout={proc.stdout}\nstderr={proc.stderr}"
    )


def test_guard_still_passes_real_ai_worktree_remove_prune_die_idiom(tmp_path: Path) -> None:
    """Concrete regression case found while building the F7 fix: tools/ai-worktree's real shipped
    `git worktree remove "$target" || die "remove failed (... 'git worktree remove --force' ...)"`
    line chains a fully-hardened `worktree remove` with `||` ahead of a `die` call whose STRING
    ARGUMENT happens to mention `git worktree remove --force` in prose. An early (rejected) fully
    independent per-segment invocation scan mis-flagged the `die` segment as a second, bare
    `worktree remove` invocation. The shipped fix scopes ONLY the one identified (first) invocation
    to its own segment, so this must stay clean -- proven directly against the real, on-disk file
    (not a synthetic fixture), so a future regression here is caught for real."""
    import shutil as _shutil

    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    ai_worktree = ROOT / "tools" / "ai-worktree"
    assert ai_worktree.is_file(), "tools/ai-worktree must exist for this regression check"
    text = ai_worktree.read_text(encoding="utf-8")
    assert "worktree remove" in text and "|| die" in text, (
        "tools/ai-worktree no longer contains the `worktree remove ... || die \"...\"` idiom this "
        "regression test targets -- update the fixture/assertions to match the new shipped shape"
    )
    mirror = tmp_path / "mirror-ai-worktree"
    (mirror / "tools").mkdir(parents=True)
    _shutil.copy(ai_worktree, mirror / "tools" / "ai-worktree")
    proc = _run_guard(guard_src, mirror, tmp_path)
    assert proc.returncode == 0, (
        f"the real tools/ai-worktree file must scan clean; got:\n"
        f"stdout={proc.stdout}\nstderr={proc.stderr}"
    )


# ---------------------------------------------------------------------------
# 7. F7-2 (RED-refuted "errs safe" claim, ops-defense2 game #2 R6): the F7 comment-stripper
#    (COMMENT_RE, `re.compile(r'(?:(?<=\s)|^)#.*$')`) claimed to err SAFE (false-positive only)
#    because it "does not track quoting". RED refuted this: a `#` inside an EARLIER quoted
#    string on the SAME physical line is itself a word-boundary `#` (preceded by whitespace), so
#    the regex truncates there too -- deleting a REAL git invocation that follows the quote. That
#    is a false-NEGATIVE (a genuine violation goes unscanned), the dangerous direction, directly
#    contradicting the "errs safe" claim. Fixed by replacing COMMENT_RE with
#    `_strip_trailing_comment`, a quoting-aware left-to-right scanner (see scripts/verify-
#    machinery.sh for its full docstring/rationale) that only truncates at a `#` that is BOTH
#    outside any quote AND at a word boundary.
# ---------------------------------------------------------------------------

# Embedded literal reproduction of the PRE-F7-2 COMMENT_RE regex exactly as it shipped in R5/F7
# (verified against the real on-disk verify-machinery.sh at authoring time) -- pinned here as a
# literal so the non-vacuousness proof below never depends on a moving `git show HEAD:` ref.
_OLD_COMMENT_RE = re.compile(r'(?:(?<=\s)|^)#.*$')


def _extract_strip_trailing_comment(script_text: str):
    """Pull the CURRENT (fixed) `_strip_trailing_comment` function body verbatim out of the
    shipped R9-DRIFT guard heredoc and exec it standalone, so unit-level assertions below run the
    REAL shipped implementation, not a hand-copied reimplementation that could silently diverge."""
    guard_src = _extract_r9_drift_guard(script_text)
    start_marker = "def _strip_trailing_comment(line):"
    end_marker = "CMD_SEP = re.compile(r'[;&|`]+')"
    start = guard_src.index(start_marker)
    end = guard_src.index(end_marker, start)
    fn_src = guard_src[start:end]
    ns: dict = {}
    exec(fn_src, ns)
    return ns["_strip_trailing_comment"]


def _build_old_comment_re_guard_src() -> str:
    """Reconstruct the guard exactly as it behaved under the OLD (pre-F7-2), quoting-unaware
    COMMENT_RE by taking the CURRENT, on-disk, shipped guard body and swapping ONLY the one
    `line_nc = _strip_trailing_comment(line)` call site back to the literal OLD regex-based
    `COMMENT_RE.sub('', line)` behavior -- INVOKE, CMD_SEP, _owning_segment, and every rule stay
    the real, current, shipped code, unmodified. This isolates exactly the ONE behavioral
    difference F7-2 changed and runs it end-to-end for real (not a hand-rebuilt guard), without
    ever reading `git show HEAD:` (the swap is done on the CURRENT working-tree source)."""
    current = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    anchor = "line_nc = _strip_trailing_comment(line)"
    assert anchor in current, (
        "extraction anchor stale -- update this test's swap-in point to match the current guard"
    )
    return current.replace(
        anchor,
        r"line_nc = re.compile(r'(?:(?<=\s)|^)#.*$').sub('', line)",
    )


def test_old_comment_re_truncates_at_quoted_hash_deleting_real_git_call() -> None:
    """NON-VACUOUS root-cause proof: the embedded literal OLD COMMENT_RE regex, run directly
    against the exploit line, truncates at the `#` inside the EARLIER quoted string and deletes
    the real, unhardened `git diff --patch HEAD` invocation that follows it."""
    bad_line = 'msg="issue #123 needs a fix"; git diff --patch HEAD'
    old_stripped = _OLD_COMMENT_RE.sub('', bad_line)
    assert "git diff" not in old_stripped, (
        "revert -> FAIL evidence: the OLD quoting-unaware COMMENT_RE must truncate at the quoted "
        f"`#` and delete the real `git diff --patch` call: stripped={old_stripped!r}"
    )


def test_guard_built_on_old_comment_re_hides_the_dangerous_diff(tmp_path: Path) -> None:
    """NON-VACUOUS end-to-end proof: a guard reconstructed with ONLY the OLD, quoting-unaware
    COMMENT_RE swapped back in (everything else is the real, current, shipped code) reports ZERO
    violations for a planted, genuinely-unhardened `git diff --patch HEAD` that is preceded on the
    same line by a quoted string containing a `#` -- the comment-stripping step alone hides the
    violation before INVOKE ever gets to see it. This is the false-negative F7-2 closes."""
    bad_line = 'msg="issue #123 needs a fix"; git diff --patch HEAD\n'
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "quoted-hash.sh").write_text(bad_line, encoding="utf-8")

    old_guard_src = _build_old_comment_re_guard_src()
    proc = _run_guard(old_guard_src, fake, tmp_path)
    assert proc.returncode == 0, (
        "revert -> FAIL evidence: the OLD-COMMENT_RE-based guard must WRONGLY report ZERO "
        f"violations (the quoted `#` deletes the real git diff call); got:\n"
        f"stdout={proc.stdout}\nstderr={proc.stderr}"
    )
    assert "quoted-hash.sh" not in proc.stderr


def test_guard_flags_git_call_after_quoted_hash_false_negative_fixed(tmp_path: Path) -> None:
    """The actual fix: the CURRENT (fixed) guard -- extracted live from the real, on-disk,
    shipped verify-machinery.sh -- MUST flag the same planted `git diff --patch HEAD` line, now
    that comment-stripping is quoting-aware and no longer eats a real invocation following a
    quoted `#`."""
    bad_line = 'msg="issue #123 needs a fix"; git diff --patch HEAD\n'
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "quoted-hash.sh").write_text(bad_line, encoding="utf-8")

    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    proc = _run_guard(current_guard_src, fake, tmp_path)
    assert proc.returncode == 1, (
        "the FIXED guard must flag the unhardened `git diff --patch` that follows a quoted `#` "
        f"on the same line; got:\nstdout={proc.stdout}\nstderr={proc.stderr}"
    )
    assert "quoted-hash.sh" in proc.stderr
    assert "R9-DRIFT VIOLATIONS" in proc.stderr


def test_guard_still_flags_genuine_trailing_comment_after_quoting_aware_rewrite(tmp_path: Path) -> None:
    """Preserved R5/F7 intent: a GENUINE trailing shell comment carrying a hardening-marker
    substring must still be stripped (so it can never vouch for a dangerous call) under the new
    quoting-aware `_strip_trailing_comment` -- exactly the shape the original R5 fix targeted."""
    bad_line = 'git status --porcelain   # --attr-source= core.fsmonitor=\n'
    fake = tmp_path / "fake"
    (fake / "scripts").mkdir(parents=True)
    (fake / "scripts" / "trailing-comment.sh").write_text(bad_line, encoding="utf-8")

    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    proc = _run_guard(current_guard_src, fake, tmp_path)
    assert proc.returncode == 1, (
        "a genuine trailing comment must still be stripped, so its markers cannot vouch for the "
        f"bare `git status`; got:\nstdout={proc.stdout}\nstderr={proc.stderr}"
    )
    assert "trailing-comment.sh" in proc.stderr


def test_strip_trailing_comment_ignores_quoted_hash() -> None:
    """Unit-level (real shipped function, extracted verbatim): a `#` inside a single- or
    double-quoted string is not a comment start -- the line must come back UNCHANGED."""
    strip = _extract_strip_trailing_comment(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    line = 'msg="issue #123 needs a fix"; git diff --patch HEAD'
    assert strip(line) == line


def test_strip_trailing_comment_ignores_mid_word_hash() -> None:
    """Unit-level: a `#` NOT preceded by whitespace/line-start (mid-word, e.g. a `git log`
    format placeholder or a ref-like path) must not start a comment -- no spurious truncation."""
    strip = _extract_strip_trailing_comment(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    for line in (
        'git log --format=%h#%s',
        'echo refs/heads/#x',
        'foo#bar baz',
    ):
        assert strip(line) == line, f"mid-word `#` must not truncate: {line!r} -> {strip(line)!r}"


def test_strip_trailing_comment_still_strips_genuine_boundary_hash() -> None:
    """Unit-level: a `#` at a real word boundary (line-start or preceded by whitespace) outside
    any quote still starts a comment and truncates through end of line -- the R5/F7 intent."""
    strip = _extract_strip_trailing_comment(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    assert strip('git status --porcelain   # --attr-source= core.fsmonitor=') == 'git status --porcelain   '
    assert strip('# a leading comment') == ''


def test_guard_f6_catfile_forms_unaffected_by_f7(tmp_path: Path) -> None:
    """F6 non-regression under F7: the abbreviated --text/--filt cat-file forms must still be
    flagged, and the bare/short-option forms must still be exempt, after the F7 comment-strip +
    segment-scoping change (parametrized re-check of the F6 suite's core assertions in one place)."""
    guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    cases = [
        ('git -C "$proj" cat-file --text HEAD:some/path > "$out" || return 1\n', 1),
        ('git -C "$proj" cat-file --filt HEAD:some/path > "$out" || return 1\n', 1),
        ('git -C "$proj" cat-file blob "$oid" > "$outpath" || return 1\n', 0),
        ('git -C "$proj" cat-file -p "$oid" > "$outpath" || return 1\n', 0),
    ]
    for i, (bad_line, expected_rc) in enumerate(cases):
        fake = tmp_path / f"fake{i}"
        (fake / "scripts").mkdir(parents=True)
        (fake / "scripts" / "catfile.sh").write_text(bad_line, encoding="utf-8")
        proc = _run_guard(guard_src, fake, tmp_path)
        assert proc.returncode == expected_rc, (
            f"case {bad_line!r}: expected rc={expected_rc}, got {proc.returncode}\n"
            f"stdout={proc.stdout}\nstderr={proc.stderr}"
        )
