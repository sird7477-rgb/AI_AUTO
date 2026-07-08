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
