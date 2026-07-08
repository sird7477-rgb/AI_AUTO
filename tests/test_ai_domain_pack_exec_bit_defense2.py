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

Non-vacuousness: `test_pre_fix_behavior_reopens_the_bug_on_revert` re-extracts the
exact pre-fix function body via `git show HEAD:tools/ai-domain-pack` (this edit is
uncommitted at authoring time, so HEAD still holds the pre-fix source) and proves
IT strips the exec bit -- i.e. reverting tools/ai-domain-pack to HEAD reopens the
defect and this suite would fail against it.
"""
from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import stat
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "ai-domain-pack"


def _load_module_from_source(name: str, source: str, tmp_path: Path):
    """Load a standalone module from literal source text (used to load the
    pre-fix HEAD version into a separate module object for the revert proof,
    without touching the real, already-fixed working-tree file)."""
    scratch = tmp_path / f"{name}.py"
    scratch.write_text(source, encoding="utf-8")
    loader = importlib.machinery.SourceFileLoader(name, str(scratch))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)  # safe: tool guards execution behind `if __name__ == "__main__"`
    return mod


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
    """Non-vacuousness proof: the pre-fix function body (as committed at HEAD,
    before this round's edit) drops the exec bit. This pins that the FIXED
    behavior asserted above is genuinely due to the edit, not incidental."""
    pre_fix_source = subprocess.run(
        ["git", "-C", str(ROOT), "show", "HEAD:tools/ai-domain-pack"],
        text=True,
        capture_output=True,
        check=True,
    ).stdout

    assert "os.chmod(tmp_name" not in pre_fix_source, (
        "HEAD:tools/ai-domain-pack already contains the fix -- this revert-proof "
        "is no longer meaningful; the fix must have been committed already."
    )

    pre_fix_mod = _load_module_from_source("ai_domain_pack_pre_fix", pre_fix_source, tmp_path)

    source_dir = tmp_path / "pf-source"
    target_dir = tmp_path / "pf-target"
    source_dir.mkdir()
    hook = source_dir / "hooks" / "pre-push"
    hook.parent.mkdir(parents=True)
    hook.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    hook.chmod(0o755)

    pre_fix_mod.copy_source_to_target(source_dir, target_dir, {"hooks/pre-push": "irrelevant-hash"})

    installed = target_dir / "hooks" / "pre-push"
    assert installed.exists()
    # This is the bug: pre-fix code loses the exec bit (mkstemp's 0600 survives
    # os.replace unchanged). If this assertion ever starts failing, the pre-fix
    # snapshot no longer reproduces the defect -- investigate before trusting green.
    assert not _is_exec(installed), (
        "pre-fix copy_source_to_target unexpectedly preserved the exec bit -- "
        "the revert-proof no longer demonstrates the original defect"
    )
