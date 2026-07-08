"""ops-defense2 BLUE fix: templates/domain-packs/odoo/hooks/pre-push-combiner gate 2
must not silently skip a PRESENT-but-non-executable odoo hook.

Confirmed defect (RED, this round): gate 2 tested
`[ -n "$ODOO_HOOK" ] && [ -f "$ODOO_HOOK" ] && [ -x "$ODOO_HOOK" ]` with no else --
if the odoo hook file exists but lost its exec bit (e.g. via the sibling
tools/ai-domain-pack install-mode defect, fixed together in this round), the ENTIRE
odoo registry-load/validate-warm oracle silently drops: EXIT=0, zero stderr, push
proceeds as if nothing were wrong.

Fix: when the hook file is present, run it regardless of the exec bit (`bash
"$ODOO_HOOK"` if not -x, direct exec if -x), and emit a distinct WARNING to stderr
when it had to fall back to the bash-invocation path. A genuinely ABSENT hook (the
normal "no odoo pack in this worktree" case) is still skipped quietly.

Non-vacuousness: `test_pre_fix_combiner_silently_skips_non_executable_hook` used to
re-extract the exact pre-fix combiner text via `git show HEAD:...` at test-collection
time. That only proves anything while HEAD is still the pre-fix commit -- the moment
the fix is committed, HEAD becomes the FIXED state and `git show HEAD:` silently hands
back the fixed text, so the "pre-fix must silently skip" assertion fails against a
perfectly healthy fixed tree (a systemic defect, not specific to this file; see the
sibling R9-DRIFT/ai-domain-pack test files for the same pattern). Fixed by embedding
the OLD gate-2 shell snippet as a literal heredoc string below (pinned once against the
real pre-fix commit, 2209dd6's parent, at authoring time -- never re-read from git at
test time) and running THAT directly. The CURRENT/fixed combiner is still exercised
live from the real, on-disk, shipped templates/domain-packs/odoo/hooks/pre-push-combiner
(see the other tests in this file), so a real future regression is still caught.
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
# round's fix (commit 2209dd6's parent). Gate 1 (AI_AUTO_HOME framework-binding
# resolution) is irrelevant to this defect and is omitted for a minimal, self-contained
# repro. The condition `[ -n "$ODOO_HOOK" ] && [ -f "$ODOO_HOOK" ] && [ -x "$ODOO_HOOK" ]`
# has NO else branch -- a present-but-non-executable odoo hook simply falls out of the
# condition: no sentinel runs, no WARNING, exit 0.
PRE_FIX_COMBINER_GATE2_ONLY = r'''#!/usr/bin/env bash
set -uo pipefail
refs="$(cat)"

# --- gate 2: odoo domain-pack validation (per-worktree materialized reference) -------------
top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
ODOO_HOOK="${top:+$top/.omx/domain-packs/odoo/hooks/pre-push}"
if [ -n "$ODOO_HOOK" ] && [ -f "$ODOO_HOOK" ] && [ -x "$ODOO_HOOK" ]; then
  printf '%s\n' "$refs" | "$ODOO_HOOK" "$@"
  orc=$?
  [ "$orc" -ne 0 ] && exit "$orc"
fi
'''


def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


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


def _write_fake_odoo_hook(project: Path, sentinel: Path, executable: bool) -> Path:
    hook_dir = project / ".omx" / "domain-packs" / "odoo" / "hooks"
    hook_dir.mkdir(parents=True, exist_ok=True)
    hook = hook_dir / "pre-push"
    hook.write_text(
        f"#!/usr/bin/env bash\ncat >/dev/null\ntouch {sentinel}\nexit 0\n",
        encoding="utf-8",
    )
    if executable:
        _make_executable(hook)
    else:
        hook.chmod(0o644)  # explicit non-exec, no ambiguity with umask
    return hook


def _run_combiner(combiner_path: Path, project: Path, env_extra: dict | None = None):
    stdin = "refs/heads/main aaa refs/heads/main bbb\n"
    env = os.environ.copy()
    # Pin AI_AUTO_HOME to a deliberately nonexistent path so gate 1 (the
    # framework binding gate, out of scope for this fix) takes its own
    # WARNING-and-skip branch instead of auto-resolving a real engine checkout
    # (e.g. /root/workspace/ai-lab) off PATH-adjacent candidates and blocking
    # on this test's synthetic, gate-1-unaware refs.
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


def test_combiner_runs_present_non_executable_odoo_hook_with_warning(tmp_path):
    project = tmp_path / "project"
    _init_repo(project)
    sentinel = tmp_path / "sentinel"
    _write_fake_odoo_hook(project, sentinel, executable=False)

    result = _run_combiner(COMBINER, project)

    assert sentinel.exists(), (
        f"gate 2 did not run the present-but-non-executable odoo hook "
        f"(stdout={result.stdout!r} stderr={result.stderr!r})"
    )
    assert "not executable" in result.stderr, result.stderr
    assert "running via bash" in result.stderr, result.stderr
    assert result.returncode == 0, result.stdout + result.stderr


def test_combiner_runs_present_executable_odoo_hook_without_spurious_warning(tmp_path):
    """Guard against over-widening: a normally-executable hook must still run
    cleanly, with no bogus not-executable WARNING."""
    project = tmp_path / "project"
    _init_repo(project)
    sentinel = tmp_path / "sentinel"
    _write_fake_odoo_hook(project, sentinel, executable=True)

    result = _run_combiner(COMBINER, project)

    assert sentinel.exists(), result.stdout + result.stderr
    assert "not executable" not in result.stderr, result.stderr
    assert result.returncode == 0, result.stdout + result.stderr


def test_combiner_stays_quiet_when_odoo_hook_genuinely_absent(tmp_path):
    """The legitimate quiet-skip case (no odoo pack installed in this worktree)
    must be preserved -- only presence-without-exec-bit becomes loud."""
    project = tmp_path / "project"
    _init_repo(project)

    result = _run_combiner(COMBINER, project)

    assert "not executable" not in result.stderr, result.stderr
    assert result.returncode == 0, result.stdout + result.stderr


def test_pre_fix_combiner_silently_skips_non_executable_hook(tmp_path):
    """Non-vacuousness proof: the embedded PRE-FIX gate-2 snippet (literal, pinned
    against the real pre-fix commit, no git dependency) silently skips a
    present-but-non-executable odoo hook -- no sentinel, no WARNING, exit 0. Reverting
    the combiner to this pre-fix shape reopens exactly this defect (see the other
    tests in this file for proof the REAL current combiner does not)."""
    assert "not executable" not in PRE_FIX_COMBINER_GATE2_ONLY, (
        "the embedded PRE-FIX literal accidentally contains the fix -- this "
        "revert-proof is no longer meaningful; fix the embedded literal, not this assertion"
    )

    pre_fix_combiner = tmp_path / "pre-push-combiner-pre-fix"
    pre_fix_combiner.write_text(PRE_FIX_COMBINER_GATE2_ONLY, encoding="utf-8")
    _make_executable(pre_fix_combiner)

    project = tmp_path / "project"
    _init_repo(project)
    sentinel = tmp_path / "sentinel"
    _write_fake_odoo_hook(project, sentinel, executable=False)

    result = _run_combiner(pre_fix_combiner, project)

    assert not sentinel.exists(), (
        "pre-fix combiner unexpectedly ran the non-executable hook -- the "
        "revert-proof no longer demonstrates the original defect"
    )
    assert "not executable" not in result.stderr
    assert result.returncode == 0
