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

Non-vacuousness: `test_pre_fix_combiner_silently_skips_non_executable_hook`
re-extracts the exact pre-fix combiner text via `git show HEAD:...` (uncommitted at
authoring time, so HEAD still holds the pre-fix content), writes it to a scratch
executable file, and proves it does NOT run the sentinel-writing fake hook and does
NOT print any WARNING -- i.e. reverting the combiner to HEAD reopens the defect.
"""
from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
COMBINER = ROOT / "templates" / "domain-packs" / "odoo" / "hooks" / "pre-push-combiner"


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
    """Non-vacuousness proof: the pre-fix combiner text (as committed at HEAD,
    before this round's edit) silently skips a present-but-non-executable odoo
    hook -- no sentinel, no WARNING, exit 0. Reverting the combiner to HEAD
    reopens exactly this defect."""
    pre_fix_text = subprocess.run(
        ["git", "-C", str(ROOT), "show", "HEAD:templates/domain-packs/odoo/hooks/pre-push-combiner"],
        text=True,
        capture_output=True,
        check=True,
    ).stdout

    assert "not executable" not in pre_fix_text, (
        "HEAD:pre-push-combiner already contains the fix -- this revert-proof is "
        "no longer meaningful; the fix must have been committed already."
    )

    pre_fix_combiner = tmp_path / "pre-push-combiner-pre-fix"
    pre_fix_combiner.write_text(pre_fix_text, encoding="utf-8")
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
