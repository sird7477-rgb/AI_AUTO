"""ops-defense2 BLUE fix: templates/domain-packs/odoo/hooks/pre-push-combiner gate 2
must not silently skip when the odoo domain-pack validation hook is ABSENT from the
current worktree.

Confirmed defect (RED, this round): gate 2 resolves the odoo validation hook
per-worktree via `top="$(git rev-parse --show-toplevel)"`,
`ODOO_HOOK="$top/.omx/domain-packs/odoo/hooks/pre-push"`, then
`if [ -f "$ODOO_HOOK" ] ... ; then run; fi` with NO else branch. Multi-worktree (some
worktrees never materializing the odoo domain-pack via `ai-domain-pack ... odoo`) is
this project's normal operating mode. When `$ODOO_HOOK` does not exist, gate 2 is
SILENTLY skipped: exit 0, zero stderr, push proceeds looking fully validated. This is
asymmetric with gate 1, whose own skip path (AI_AUTO_HOME unresolved, or the engine
hook missing/non-parsing) DOES print a `[pre-push] WARNING: ...` line every time.

Fix: when `$ODOO_HOOK` is absent (including when `$top` itself failed to resolve),
gate 2 now emits a distinct, LOUD `[pre-push] NOT-VALIDATED (odoo domain-pack gate 2):
...` line to stderr, and still exits 0 (advisory, non-blocking) -- mirroring gate 1's
own warn-not-block philosophy and the domain pack's existing NOT-VALIDATED style (see
hooks/pre-push's own `NOT-VALIDATED (scanner ... unavailable)` markers). A worktree
that legitimately carries no odoo pack must remain pushable for non-odoo changes; this
fix only removes the SILENCE, not the non-blocking nature of the skip.

Non-vacuousness: rather than `git show HEAD:...` at test-collection time (which
silently hands back the FIXED text the moment this fix is committed -- see the sibling
test_pre_push_combiner_exec_bit_defense2.py's own docstring for the same lesson learned
elsewhere in this project), the OLD gate-2 shell snippet (silent `if -f ... ; then`
with no else) is embedded here as a literal string, pinned once at authoring time
against the real pre-fix combiner, and run directly to PROVE it produces no such
warning. The CURRENT/fixed combiner is exercised live from the real, on-disk, shipped
templates/domain-packs/odoo/hooks/pre-push-combiner in the other tests below, so a real
future regression (e.g. someone "simplifying" the else branch back out) is still
caught.
"""
from __future__ import annotations

import os
import stat
from pathlib import Path
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]
COMBINER = ROOT / "templates" / "domain-packs" / "odoo" / "hooks" / "pre-push-combiner"

# Embedded literal reproduction of pre-push-combiner's gate 2 as it existed BEFORE this
# round's fix (i.e. before ops-defense2's absent-hook LOUD-notice fix). Gate 1 is
# irrelevant to this defect and omitted for a minimal, self-contained repro. Note this
# is the state gate 2 was in immediately AFTER the sibling exec-bit fix (which added the
# `-x`/`else`/bash-fallback split) but BEFORE this round's fix (which adds the outer
# `else` for genuine absence) -- i.e. exactly the silent-skip-on-absence defect this
# test targets, isolated from the already-fixed exec-bit defect.
PRE_FIX_COMBINER_GATE2_ONLY = r'''#!/usr/bin/env bash
set -uo pipefail
refs="$(cat)"

# --- gate 2: odoo domain-pack validation (per-worktree materialized reference) -------------
top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
ODOO_HOOK="${top:+$top/.omx/domain-packs/odoo/hooks/pre-push}"
if [ -n "$ODOO_HOOK" ] && [ -f "$ODOO_HOOK" ]; then
  if [ -x "$ODOO_HOOK" ]; then
    printf '%s\n' "$refs" | "$ODOO_HOOK" "$@"
    orc=$?
  else
    printf '[pre-push] WARNING: odoo pack hook present but not executable (%s); running via bash and continuing -- fix the exec bit\n' "$ODOO_HOOK" >&2
    printf '%s\n' "$refs" | bash "$ODOO_HOOK" "$@"
    orc=$?
  fi
  [ "$orc" -ne 0 ] && exit "$orc"
fi

exit 0
'''


def _git(args: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=cwd, text=True, capture_output=True, check=check)


def _init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git(["init", "-q"], path)
    _git(["config", "user.email", "t@example.invalid"], path)
    _git(["config", "user.name", "T"], path)
    (path / "f.txt").write_text("x\n", encoding="utf-8")
    _git(["add", "-A"], path)
    _git(["commit", "-q", "-m", "init"], path)


def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _write_fake_odoo_hook(project: Path, sentinel: Path) -> Path:
    hook_dir = project / ".omx" / "domain-packs" / "odoo" / "hooks"
    hook_dir.mkdir(parents=True, exist_ok=True)
    hook = hook_dir / "pre-push"
    hook.write_text(
        f"#!/usr/bin/env bash\ncat >/dev/null\ntouch {sentinel}\nexit 0\n",
        encoding="utf-8",
    )
    _make_executable(hook)
    return hook


def _run_combiner(combiner_path: Path, project: Path, env_extra: dict | None = None):
    stdin = "refs/heads/main aaa refs/heads/main bbb\n"
    env = os.environ.copy()
    # Pin AI_AUTO_HOME to a deliberately nonexistent path so gate 1 (the framework
    # binding gate, out of scope for this fix) takes its own WARNING-and-skip branch
    # instead of auto-resolving a real engine checkout and blocking on this test's
    # synthetic, gate-1-unaware refs.
    env["AI_AUTO_HOME"] = "/nonexistent-ai-auto-home-for-tests"
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["bash", str(combiner_path)],
        cwd=project,
        input=stdin,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def test_combiner_warns_loudly_when_odoo_hook_absent_but_still_succeeds(tmp_path):
    """The actual defect: no .omx/domain-packs/odoo/hooks/pre-push materialized in this
    worktree at all (the normal state for a worktree that never ran
    `ai-domain-pack ... odoo`). Push must still succeed (advisory, non-blocking) but
    must no longer be silent about it."""
    project = tmp_path / "project"
    _init_repo(project)
    assert not (project / ".omx" / "domain-packs" / "odoo" / "hooks" / "pre-push").exists()

    result = _run_combiner(COMBINER, project)

    assert result.returncode == 0, result.stdout + result.stderr
    assert "NOT-VALIDATED (odoo domain-pack gate 2)" in result.stderr, result.stderr
    assert "does NOT imply" in result.stderr, result.stderr
    assert "ai-domain-pack" in result.stderr, result.stderr


def test_pre_fix_combiner_silently_skips_absent_hook(tmp_path):
    """Non-vacuousness proof: the embedded PRE-FIX gate-2 snippet (literal, pinned at
    authoring time, no git dependency) silently skips a genuinely absent odoo hook --
    no WARNING, no NOT-VALIDATED, exit 0. Reverting the combiner to this pre-fix shape
    reopens exactly the defect this round closes (see the other test in this file for
    proof the REAL current combiner does not)."""
    assert "NOT-VALIDATED" not in PRE_FIX_COMBINER_GATE2_ONLY, (
        "the embedded PRE-FIX literal accidentally contains the fix -- this "
        "revert-proof is no longer meaningful; fix the embedded literal, not this assertion"
    )

    pre_fix_combiner = tmp_path / "pre-push-combiner-pre-fix"
    pre_fix_combiner.write_text(PRE_FIX_COMBINER_GATE2_ONLY, encoding="utf-8")
    _make_executable(pre_fix_combiner)

    project = tmp_path / "project"
    _init_repo(project)

    result = _run_combiner(pre_fix_combiner, project)

    assert result.returncode == 0
    assert result.stderr == "", (
        f"pre-fix combiner unexpectedly produced stderr output -- the revert-proof "
        f"no longer demonstrates the original silent-skip defect (stderr={result.stderr!r})"
    )


def test_combiner_still_runs_present_hook_without_spurious_absent_warning(tmp_path):
    """Regression guard: when the odoo hook IS present (and executable), it must still
    run (sentinel created), with no spurious 'NOT-VALIDATED (odoo domain-pack gate 2)'
    absence warning -- that branch is only for genuine absence."""
    project = tmp_path / "project"
    _init_repo(project)
    sentinel = tmp_path / "sentinel"
    _write_fake_odoo_hook(project, sentinel)

    result = _run_combiner(COMBINER, project)

    assert sentinel.exists(), result.stdout + result.stderr
    assert "NOT-VALIDATED (odoo domain-pack gate 2)" not in result.stderr, result.stderr
    assert result.returncode == 0, result.stdout + result.stderr
