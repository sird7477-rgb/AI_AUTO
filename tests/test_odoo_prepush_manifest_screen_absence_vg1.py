"""RED-VG-1 fix for the odoo domain-pack pre-push hook (BLUE, ops-defense game).

Defect being closed (see the RED-VG-1 comment in
templates/domain-packs/odoo/hooks/pre-push, directly above the block under test):

  RED-VG-1  hooks/pre-push: the static manifest-integrity screen
            (check-manifest-files.py) is documented as "the one validation that
            still fires when ODOO_HARNESS_DIR is unset". The pre-fix hook (see
            `git show HEAD:templates/domain-packs/odoo/hooks/pre-push`) silently
            skipped this screen with NO output at all when the script was
            missing/renamed -- "push validated" did not imply "manifest-files
            checked", with zero signal to the pusher. The fix makes the absence
            LOUD: it prints a NOT-VALIDATED marker, mirroring the RED2-4
            check-schema-catalog.py sibling block's exact wording and exact
            control flow (print-and-fall-through, not a forced exit) --
            deliberately NOT routing through odoo_unvalidated_ack_or_block here,
            because doing so would exit the whole hook unconditionally
            (block, or ack-and-exit-0) before the pre-existing "ODOO_HARNESS_DIR
            not set" / "docker unavailable" ack-or-block gates further down ever
            get a chance to run their own, independent fail-closed checks --
            which is exactly the regression an earlier draft of this fix
            introduced (verified against 7 existing pre-push tests failing
            with that draft; restored to print-and-continue here).

These tests build small, hermetic fixture git repos under pytest's tmp_path and
drive the real hook script as a subprocess, matching the pattern used by
tests/test_odoo_harness_honesty_r2.py for the sibling RED2-4 check-schema-catalog.py
fix.

Non-vacuousness: every assertion here targets behavior that is only true of the
FIXED script content. Restoring the pre-fix content (`git show HEAD:<path>`, since
this edit is uncommitted in this worktree at authoring time) makes each
corresponding assertion fail -- verified manually (see the session report).
"""
from __future__ import annotations

import os
import shutil
import stat
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
PRE_PUSH = ODOO_PACK / "hooks" / "pre-push"
REAL_MANIFEST_SCREEN = ODOO_PACK / "validation-harness" / "check-manifest-files.py"


# --------------------------------------------------------------------------
# shared fixture helpers (mirrors tests/test_odoo_harness_honesty_r2.py)
# --------------------------------------------------------------------------
def _git(args: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args], cwd=cwd, text=True, capture_output=True, check=check
    )


def _init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git(["init", "-q"], path)
    _git(["config", "user.email", "t@example.invalid"], path)
    _git(["config", "user.name", "T"], path)


def _commit_all(path: Path, message: str) -> str:
    _git(["add", "-A"], path)
    _git(["commit", "-q", "-m", message], path)
    return _git(["rev-parse", "HEAD"], path).stdout.strip()


def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _fake_docker_bin(tmp_path: Path) -> Path:
    """A hermetic, no-op fake `docker` on PATH: succeeds unconditionally for any
    subcommand (info/version/compose ...), never touches a real daemon."""
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    _make_executable(docker)
    return bin_dir


def _make_module(project: Path, name: str = "mod1") -> None:
    mod_dir = project / "custom-addons" / name
    mod_dir.mkdir(parents=True)
    (mod_dir / "__manifest__.py").write_text(
        "{'name': '%s', 'depends': []}\n" % name, encoding="utf-8"
    )


def _add_view(project: Path, name: str = "mod1") -> None:
    (project / "custom-addons" / name / "views.xml").write_text(
        "<odoo/>\n", encoding="utf-8"
    )


def _run_prepush(project: Path, lsha: str, rsha: str, env_extra: dict | None = None):
    stdin = f"refs/heads/main {lsha} refs/heads/main {rsha}\n"
    env = os.environ.copy()
    env.pop("ODOO_HARNESS_DIR", None)
    env.pop("SKIP_ODOO_VALIDATE", None)
    env.pop("AI_AUTO_ODOO_UNVALIDATED_ACK_BY", None)
    env.pop("AI_AUTO_PRINCIPAL_EVIDENCE", None)
    env.pop("AI_AUTO_PROVENANCE_KEY_FILE", None)
    env.pop("AI_AUTO_HOME", None)
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["bash", str(PRE_PUSH)],
        cwd=project,
        input=stdin,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


# ==========================================================================
# RED-VG-1 -- pre-push: check-manifest-files.py absence must be LOUD, not silent
# ==========================================================================
def test_manifest_screen_absence_is_loud_not_silent(tmp_path):
    project = tmp_path / "project"
    _init_repo(project)
    _make_module(project)
    base_sha = _commit_all(project, "base")
    _add_view(project)
    new_sha = _commit_all(project, "add a view")

    # A harness dir that exists but has NO check-manifest-files.py -- the
    # "script absent/renamed" scenario. (No file next to the real hook path
    # either: templates/domain-packs/odoo/hooks/ ships only pre-push itself.)
    harness = tmp_path / "harness"
    harness.mkdir()

    result = _run_prepush(
        project, lsha=new_sha, rsha=base_sha, env_extra={"ODOO_HARNESS_DIR": str(harness)}
    )

    assert (
        "NOT-VALIDATED (scanner check-manifest-files.py unavailable)" in result.stdout
    ), result.stdout
    assert "manifest-files-checked" in result.stdout, result.stdout


# ==========================================================================
# RED-VG-1 -- must NOT short-circuit the hook: exactly like the
# check-schema-catalog.py sibling (RED2-4), the absence marker is a
# print-and-continue, not a forced exit. Execution must still reach later
# gates (here: the pre-existing "ODOO_HARNESS_DIR not set" ack-or-block),
# which independently fail-close the push when nothing is configured at all.
# This is also the regression guard for the earlier over-tight draft of this
# fix (which called odoo_unvalidated_ack_or_block here and exited before ever
# reaching this later message -- breaking 7 pre-existing pre-push tests that
# assert on it).
# ==========================================================================
def test_manifest_screen_absence_does_not_abort_the_hook(tmp_path):
    project = tmp_path / "project"
    _init_repo(project)
    _make_module(project)
    base_sha = _commit_all(project, "base")
    _add_view(project)
    new_sha = _commit_all(project, "add a view")

    # No ODOO_HARNESS_DIR at all: dirname($0)/check-manifest-files.py is also
    # absent (the real hooks/ dir ships only pre-push), so the screen cannot
    # run, but nothing else is misconfigured either.
    result = _run_prepush(project, lsha=new_sha, rsha=base_sha)

    assert (
        "NOT-VALIDATED (scanner check-manifest-files.py unavailable)" in result.stdout
    ), result.stdout
    # Reached the later, pre-existing gate -- proves the marker did not exit
    # the hook by itself.
    assert "NOT VALIDATED (validator unavailable): ODOO_HARNESS_DIR not set" in result.stdout, (
        result.stdout
    )
    assert result.returncode != 0, result.stdout  # still not silently green overall


# ==========================================================================
# RED-VG-1 -- guard against over-widening: when check-manifest-files.py IS
# present and finds nothing wrong, this screen must run normally (no
# NOT-VALIDATED marker for it) and the hook must proceed past it exactly as
# before.
# ==========================================================================
def test_manifest_screen_present_runs_normally_no_false_not_validated(tmp_path):
    project = tmp_path / "project"
    _init_repo(project)
    _make_module(project)
    base_sha = _commit_all(project, "base")
    _add_view(project)
    new_sha = _commit_all(project, "add a view")

    harness = tmp_path / "harness"
    harness.mkdir()
    shutil.copy(REAL_MANIFEST_SCREEN, harness / "check-manifest-files.py")

    fake_bin = _fake_docker_bin(tmp_path)
    env_extra = {
        "ODOO_HARNESS_DIR": str(harness),
        "PATH": f"{fake_bin}:{os.environ.get('PATH', '')}",
    }

    result = _run_prepush(project, lsha=new_sha, rsha=base_sha, env_extra=env_extra)

    # The screen ran (its own OK message shows up) and did NOT trip its own
    # absence marker.
    assert "[manifest-files] OK" in result.stdout, result.stdout
    assert (
        "NOT-VALIDATED (scanner check-manifest-files.py unavailable)" not in result.stdout
    ), result.stdout
    # Execution reached later stages (this harness has no other optional
    # scripts either), confirming the manifest screen did not itself abort
    # the hook early -- same as the pre-fix behavior for the "present" case.
    assert (
        "NOT-VALIDATED (scanner check-schema-catalog.py unavailable)" in result.stdout
    ), result.stdout


def test_manifest_screen_absent_module_missing_file_class_still_flagged_when_present(tmp_path):
    """Sanity/no-regression companion: the screen's actual BLOCKING behavior
    (when it IS present and DOES find a problem) is unaffected by RED-VG-1 --
    this fix only touches the absence branch."""
    project = tmp_path / "project"
    _init_repo(project)
    mod_dir = project / "custom-addons" / "mod1"
    mod_dir.mkdir(parents=True)
    (mod_dir / "__manifest__.py").write_text(
        "{'name': 'mod1', 'depends': [], 'data': ['views/missing.xml']}\n",
        encoding="utf-8",
    )
    base_sha = _commit_all(project, "base")
    _add_view(project)
    new_sha = _commit_all(project, "add a view")

    harness = tmp_path / "harness"
    harness.mkdir()
    shutil.copy(REAL_MANIFEST_SCREEN, harness / "check-manifest-files.py")

    result = _run_prepush(
        project, lsha=new_sha, rsha=base_sha, env_extra={"ODOO_HARNESS_DIR": str(harness)}
    )

    assert result.returncode != 0, result.stdout
    assert "a __manifest__.py references a missing file" in result.stdout, result.stdout
