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

A 4th class of test proves each fix is load-bearing (not a vacuous no-op): it re-extracts the
PRE-FIX guard body and the PRE-FIX collect-review-context.sh content straight from git HEAD
(read-only `git show` -- this worktree's edits are not yet committed) and shows that, in
isolation, EACH pre-fix half reproduces its half of the original RED-1 failure against the
current tree. "Revert -> FAIL" for each fix, independently.
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


def _git_show(rev: str, relpath: str) -> str:
    """Read-only: fetch a path's content at `rev` without touching the working tree."""
    proc = subprocess.run(
        ["git", "-C", str(ROOT), "show", f"{rev}:{relpath}"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return proc.stdout


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
# 4. "revert -> FAIL": each half of the fix is independently load-bearing, proven by
#    re-extracting the PRE-FIX source straight from git HEAD (read-only `git show`; this
#    worktree's edits are uncommitted, so HEAD is still the pre-fix state).
# ---------------------------------------------------------------------------

def test_revert_guard_side_fix_reopens_cat_file_false_positive(tmp_path: Path) -> None:
    """Isolate the guard-side fix: run the PRE-FIX guard body (from HEAD) against the CURRENT
    (fixed) tree. The 3 cat-file sites are unchanged by the collect-review-context.sh fix, so
    this must reproduce (a subset of) the original RED-1 failure -- proving the guard-side
    change, not some unrelated drift, is what makes cat-file pass."""
    pre_fix_script = _git_show("HEAD", "scripts/verify-machinery.sh")
    pre_fix_guard_src = _extract_r9_drift_guard(pre_fix_script)
    proc = _run_guard(pre_fix_guard_src, ROOT, tmp_path)
    assert proc.returncode == 1, "pre-fix guard must still fail on cat-file sites in the real tree"
    assert "cat-file" in proc.stderr
    assert "validate-warm.sh" in proc.stderr or "validate-full.sh" in proc.stderr or "validate-odoo.sh" in proc.stderr


def test_revert_collect_review_context_fix_reopens_dollar_at_blind_spot(tmp_path: Path) -> None:
    """Isolate the collect-review-context.sh fix: run the CURRENT (fixed) guard against a tree
    mirror where ONLY collect-review-context.sh is swapped back to its PRE-FIX (HEAD) content.
    Must reproduce the original 4 `--no-ext-diff`/`--no-textconv` violations on lines 252/254."""
    current_guard_src = _extract_r9_drift_guard(VERIFY_MACHINERY.read_text(encoding="utf-8"))
    mirror = _mirror_tree(tmp_path, "mirror-revert-crc")
    pre_fix_crc = _git_show("HEAD", "scripts/collect-review-context.sh")
    (mirror / "scripts" / "collect-review-context.sh").write_text(pre_fix_crc, encoding="utf-8")
    proc = _run_guard(current_guard_src, mirror, tmp_path)
    assert proc.returncode == 1, (
        "reverting collect-review-context.sh alone must reopen its 2 flagged lines"
    )
    assert "collect-review-context.sh:252" in proc.stderr
    assert "collect-review-context.sh:254" in proc.stderr


def test_revert_both_fixes_reproduces_original_ten_violations(tmp_path: Path) -> None:
    """Combined revert: PRE-FIX guard + PRE-FIX collect-review-context.sh together must fail
    with all 5 originally-flagged call sites (3 cat-file + 2 collect-review-context.sh lines),
    matching RED-1's reported scope."""
    pre_fix_script = _git_show("HEAD", "scripts/verify-machinery.sh")
    pre_fix_guard_src = _extract_r9_drift_guard(pre_fix_script)
    mirror = _mirror_tree(tmp_path, "mirror-revert-both")
    pre_fix_crc = _git_show("HEAD", "scripts/collect-review-context.sh")
    (mirror / "scripts" / "collect-review-context.sh").write_text(pre_fix_crc, encoding="utf-8")
    proc = _run_guard(pre_fix_guard_src, mirror, tmp_path)
    assert proc.returncode == 1
    for needle in (
        "collect-review-context.sh:252",
        "collect-review-context.sh:254",
        "validate-warm.sh:127",
        "validate-full.sh:132",
        "validate-odoo.sh:134",
    ):
        assert needle in proc.stderr, f"expected pre-fix violation {needle!r} missing from:\n{proc.stderr}"
