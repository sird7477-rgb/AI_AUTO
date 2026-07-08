"""ops-defense2 BLUE fix: tools/ai-domain-pack `copy_source_to_target` must preserve
the SOURCE file's executable bit when installing a domain-pack file into a target
tree.

Confirmed defect (RED, this round): `copy_source_to_target` writes every pack file
via `tempfile.mkstemp` (always mode 0600) + `os.replace`, and never propagates the
source file's mode onto the target. An installed hook (e.g.
.omx/domain-packs/odoo/hooks/pre-push) therefore lands NON-executable even when its
source template on disk is 0755 -- silently disabling anything downstream that
gates on `[ -x "$ODOO_HOOK" ]` (see the sibling combiner defect, fixed together in
this round and covered by tests/test_pre_push_combiner_exec_bit_defense2.py).

Fix: after writing the temp file's bytes, `os.chmod` it to the source's `st_mode &
0o777` BEFORE `os.replace`, so the atomic replace lands with the source's mode.

Non-vacuousness: `test_pre_fix_behavior_reopens_the_bug_on_revert` used to re-extract the exact
pre-fix function body via `git show HEAD:tools/ai-domain-pack` at test-collection time. That only
proves anything while HEAD is still the pre-fix commit -- the moment the fix is committed, HEAD
becomes the FIXED state and `git show HEAD:` silently hands back the fixed source, so the
"pre-fix must drop the exec bit" assertion fails against a perfectly healthy fixed tree (a
systemic defect, not specific to this file; see the sibling R9-DRIFT/combiner test files for the
same pattern). Fixed by embedding a minimal, literal re-implementation of the OLD
`copy_source_to_target` (mkstemp 0600 + os.replace, NO chmod) directly below, pinned once against
the real pre-fix commit (2209dd6's parent) at authoring time -- never re-read from git at test
time. The CURRENT/fixed function is still imported live from the real, on-disk, shipped
tools/ai-domain-pack, so a real future regression is still caught.
"""
from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import tempfile
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "ai-domain-pack"


def _pre_fix_copy_source_to_target(source_dir: Path, target_dir: Path, source_files: dict) -> None:
    """Embedded literal reproduction of `copy_source_to_target` as it existed BEFORE this
    round's fix (commit 2209dd6's parent): every pack file was written via
    `tempfile.mkstemp` (which always creates the temp file at mode 0600) followed by
    `os.replace`, with NO `os.chmod` propagating the source file's mode onto the target --
    verbatim minus the docstring/symlink guards (irrelevant to the exec-bit defect), so the
    installed file silently lands non-executable even when its source template on disk is
    0755. Pinned here as a literal so this non-vacuousness proof never depends on a moving
    `git show HEAD:` ref."""
    target_dir.mkdir(parents=True, exist_ok=True)
    for rel in source_files:
        source_path = source_dir / rel
        target_path = target_dir / rel
        target_path.parent.mkdir(parents=True, exist_ok=True)
        tmp_fd, tmp_name = tempfile.mkstemp(prefix=f".{target_path.name}.", dir=str(target_path.parent))
        try:
            with os.fdopen(tmp_fd, "wb") as handle:
                handle.write(source_path.read_bytes())
            os.replace(tmp_name, target_path)
        finally:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)


def _load_current_tool():
    loader = importlib.machinery.SourceFileLoader("ai_domain_pack_under_test", str(TOOL))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def _is_exec(path: Path) -> bool:
    return bool(path.stat().st_mode & 0o111) and os.access(path, os.X_OK)


def test_executable_source_stays_executable_after_install(tmp_path):
    mod = _load_current_tool()
    source_dir = tmp_path / "source"
    target_dir = tmp_path / "target"
    source_dir.mkdir()
    hook = source_dir / "hooks" / "pre-push"
    hook.parent.mkdir(parents=True)
    hook.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    hook.chmod(0o755)

    mod.copy_source_to_target(source_dir, target_dir, {"hooks/pre-push": "irrelevant-hash"})

    installed = target_dir / "hooks" / "pre-push"
    assert installed.exists()
    assert _is_exec(installed), f"installed hook lost its exec bit: {oct(installed.stat().st_mode)}"


def test_non_executable_source_stays_non_executable(tmp_path):
    """Guard against over-widening: the fix must propagate the source's mode,
    not unconditionally +x every installed file."""
    mod = _load_current_tool()
    source_dir = tmp_path / "source"
    target_dir = tmp_path / "target"
    source_dir.mkdir()
    readme = source_dir / "README.md"
    readme.write_text("docs\n", encoding="utf-8")
    readme.chmod(0o644)

    mod.copy_source_to_target(source_dir, target_dir, {"README.md": "irrelevant-hash"})

    installed = target_dir / "README.md"
    assert installed.exists()
    assert not _is_exec(installed), f"non-exec source spuriously gained +x: {oct(installed.stat().st_mode)}"


def test_pre_fix_behavior_reopens_the_bug_on_revert(tmp_path):
    """Non-vacuousness proof: the embedded PRE-FIX re-implementation (mkstemp 0600 +
    os.replace, no chmod) drops the exec bit, while the REAL current
    `copy_source_to_target` -- imported live from the on-disk, shipped
    tools/ai-domain-pack -- preserves it. This pins that the FIXED behavior asserted
    above is genuinely due to the `os.chmod` line, not incidental, without depending
    on git HEAD."""
    source_dir = tmp_path / "pf-source"
    target_dir = tmp_path / "pf-target"
    source_dir.mkdir()
    hook = source_dir / "hooks" / "pre-push"
    hook.parent.mkdir(parents=True)
    hook.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    hook.chmod(0o755)

    _pre_fix_copy_source_to_target(source_dir, target_dir, {"hooks/pre-push": "irrelevant-hash"})

    installed = target_dir / "hooks" / "pre-push"
    assert installed.exists()
    # This is the bug: pre-fix code loses the exec bit (mkstemp's 0600 survives
    # os.replace unchanged).
    assert not _is_exec(installed), (
        "pre-fix copy_source_to_target unexpectedly preserved the exec bit -- "
        "the revert-proof no longer demonstrates the original defect"
    )

    # Now prove the REAL current (fixed) function, imported live from disk, does NOT
    # reproduce the defect on the identical input.
    mod = _load_current_tool()
    fixed_target_dir = tmp_path / "pf-target-fixed"
    mod.copy_source_to_target(source_dir, fixed_target_dir, {"hooks/pre-push": "irrelevant-hash"})
    fixed_installed = fixed_target_dir / "hooks" / "pre-push"
    assert fixed_installed.exists()
    assert _is_exec(fixed_installed), (
        f"the FIXED copy_source_to_target must preserve the exec bit: {oct(fixed_installed.stat().st_mode)}"
    )
