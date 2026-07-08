"""BLUE fix (ops-defense2) closing a CRITICAL/LIVE oracle bypass in the Odoo
domain-pack warm-cache, confirmed by a full black-box RED PoC.

Confirmed defect (see the session's RED PoC): validate-warm.sh's
WARM_CACHE_PRIME=1 test/CI hook wrote the EXACT SAME pass-cache marker file a
genuine, docker-backed validation run writes -- but WITHOUT ever invoking
`docker compose` (zero Odoo load). Nothing in the real push chain
(templates/domain-packs/odoo/hooks/pre-push, pre-push-combiner, the framework
hooks/pre-push, git-scrub.sh) ever unset WARM_CACHE_PRIME. RED's PoC: a module
with invalid Python syntax, primed via WARM_CACHE_PRIME=1 (verified zero
docker calls via a logging docker shim), then a SECOND ordinary invocation
with no env override reused the cache and printed
"[warm] PASS (cached, no-op)" -- the broken module never loaded. Two vectors:
  (i)  WARM_CACHE_PRIME leaks into a real push via ambient/inherited env, and
  (ii) a marker primed out-of-band (a test/CI run, or a hostile shell)
       PERSISTS on disk and is later reused by an entirely separate, later,
       ordinary production invocation.
Vector (ii) means an env-scrub alone is insufficient -- the durable marker
itself must be non-authoritative for production.

Fix (both parts; A is the essential one):

  A. validate-warm.sh: cache-marker PROVENANCE. The marker file now carries a
     one-line provenance stamp instead of being empty. WARM_CACHE_PRIME writes
     "provenance=primed"; a genuine, docker-backed PASS writes
     "provenance=genuine" (the ONLY site that ran a real `docker compose run`
     odoo-bin -u load). The cache-hit reuse path now accepts a marker as a
     valid cached PASS ONLY if its provenance is "genuine", OR "primed" AND
     the CURRENT invocation is itself WARM_CACHE_PRIME=1 (an equally-primed/
     test context) -- never a plain production invocation. A non-genuine
     marker read by a plain invocation is treated as a cache MISS: the script
     falls through to a real validation instead of exiting on a fabricated
     PASS. validate-full.sh was checked and carries no WARM_CACHE_PRIME hook
     of its own (confirmed by grep; it never defines WARM_CACHE_KEY/
     WARM_CACHE_DIR), so it needed no equivalent change.

  B. templates/domain-packs/odoo/hooks/pre-push: env-scrub chokepoint
     (defense in depth). odoo_validate_one_ref() -- the one function that
     actually invokes validate-warm.sh on a real push -- now
     `unset WARM_CACHE_PRIME WARM_CLASSIFY_ONLY` immediately before each call,
     so an inherited/leaked test-only override can never reach a real push.
     WARM_CLASSIFY_ONLY is scrubbed too: grepping validate-warm.sh for `WARM_`
     env reads shows it ALSO exits 0 before any docker call in its
     `validate` branch (not just the asset-skip/cache-hit branches) -- an
     ambient WARM_CLASSIFY_ONLY=1 is the same class of silent-bypass risk as
     WARM_CACHE_PRIME. WARM_NO_ASSET_SKIP and WARM_NO_CACHE are deliberately
     NOT scrubbed: both only ever force MORE validation to run if inherited,
     never less, so neither is a bypass vector.

These tests are hermetic: `docker` is a small scripted fake binary on PATH
(never a real daemon) that logs every invocation to a file and lets a test
control the exit code of the one subcommand ("compose ... run ...") that
represents the actual `-u <mods> --stop-after-init` Odoo load, so a test can
simulate "this module is broken" (nonzero exit) or "this module installs
cleanly" (exit 0) without ever running real Odoo. Harness scripts are copied
into a per-test tmp_path directory (never the real shared worktree).

Non-vacuousness (PROJECT RULE: pin pre-fix behavior as an embedded literal,
never `git show HEAD` at test time): `OLD_CACHE_LOGIC_SH` below is a literal,
self-contained reproduction of the exact pre-fix caching section (an empty
marker file on prime; ANY existing marker file honored as a cached PASS,
unconditionally, on the next invocation) -- not a fetch from git history.
test_old_cache_logic_would_have_reused_a_primed_marker_as_pass drives that
literal snippet through the identical prime-then-plain-invocation sequence
used against the real, fixed validate-warm.sh, and shows it WOULD serve a
fabricated cached PASS -- proving the bypass this diff closes was real, and
that the fixed script (exercised in the sibling test) no longer does it.
"""
from __future__ import annotations

import hashlib
import shutil
import stat
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
HARNESS_SRC = ODOO_PACK / "validation-harness"
PRE_PUSH = ODOO_PACK / "hooks" / "pre-push"
CHECK_SCHEMA_CATALOG = HARNESS_SRC / "check-schema-catalog.py"

_HARNESS_FILES = [
    "validate-warm.sh",
    "validate-full.sh",
    "harness-preflight.sh",
    "harness-slug.sh",
    "harness-lock.sh",
    "check-parity.sh",
]


# --------------------------------------------------------------------------
# shared fixture helpers (mirrors tests/test_harness_validates_pushed_tree_r9.py
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


def _slug_of(project: Path, harness: Path) -> str:
    cmd = f'. "{harness / "harness-slug.sh"}"; harness_proj_slug "{project}"'
    result = subprocess.run(["bash", "-c", cmd], text=True, capture_output=True, check=True)
    return result.stdout.strip()


def _stamp_parity(harness: Path, slug: str, base_db: str, modules_csv: str) -> None:
    module_set_sha = hashlib.sha256(modules_csv.encode("utf-8")).hexdigest()
    stamp = harness / f".warm-base.{slug}.{base_db}.parity.env"
    stamp.write_text(
        f"point_release=1-lite\nmodule_set={modules_csv}\nmodule_set_sha={module_set_sha}\n",
        encoding="utf-8",
    )


def _stamp_epoch(harness: Path, slug: str, base_db: str) -> None:
    (harness / f".warm-base.{slug}.{base_db}.epoch").write_text("1\n", encoding="utf-8")


def _make_module_project(tmp_path: Path, name: str = "project") -> Path:
    project = tmp_path / name
    _init_repo(project)
    mod = project / "custom-addons" / "mod1"
    mod.mkdir(parents=True)
    (mod / "__manifest__.py").write_text("{'name': 'mod1', 'depends': []}\n", encoding="utf-8")
    (mod / "views.xml").write_text("<odoo><data>v1</data></odoo>\n", encoding="utf-8")
    return project


# A small, SCRIPTED fake `docker`: logs every invocation (so a test can prove
# whether a real docker-backed run happened), answers the small set of
# subcommands validate-warm.sh's non-cached path actually needs (version/info
# preflight, `compose up`, the `exec ... psql -lqt` base-DB probe, `rm -f`),
# and lets a test control the exit code of `compose ... run` -- the ONE
# subcommand standing in for the real `-u <mods> --stop-after-init` Odoo load
# -- via FAKE_DOCKER_RUN_EXIT (default 1 = "this module is broken", the RED
# PoC's exact scenario; a test sets it to 0 to simulate a clean install).
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
    up) exit 0 ;;
    exec)
      rest="$*"
      case "$rest" in
        *psql*) printf 'base                                                            | odoo     | UTF8     |\\n'; exit 0 ;;
        *) exit 0 ;;
      esac
      ;;
    run) exit "${FAKE_DOCKER_RUN_EXIT:-1}" ;;
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
    for k in ("WARM_CACHE_PRIME", "WARM_CLASSIFY_ONLY", "WARM_NO_CACHE", "WARM_NO_ASSET_SKIP"):
        env.pop(k, None)
    if extra:
        env.update(extra)
    return env


def _run_validate_warm(
    project: Path, harness: Path, env: dict, mods: str = "mod1"
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(harness / "validate-warm.sh"), str(project), mods],
        cwd=harness,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def _cache_marker_files(harness: Path, slug: str) -> list[Path]:
    return sorted((harness / f".warm-pass-cache.{slug}").glob("*")) if (
        harness / f".warm-pass-cache.{slug}"
    ).exists() else []


def _setup(tmp_path: Path, name: str = "core"):
    project = _make_module_project(tmp_path, f"{name}-project")
    _commit_all(project, "v1")
    harness = _copy_harness(tmp_path, f"{name}-harness")
    slug = _slug_of(project, harness)
    _stamp_parity(harness, slug, "base", "mod1")
    _stamp_epoch(harness, slug, "base")
    docker_log = tmp_path / f"{name}-docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    return project, harness, slug, docker_log, fake_bin


# ==========================================================================
# (1) CORE PROOF -- a marker primed out-of-band must never satisfy a later,
#     plain production invocation.
# ==========================================================================
def test_primed_marker_rejected_by_plain_production_invocation(tmp_path):
    project, harness, slug, docker_log, fake_bin = _setup(tmp_path, "core1")

    # Step 1: an out-of-band prime (a test/CI run, or a hostile shell) -- the
    # docker run-exit is rigged to FAIL (1), standing in for "this module has
    # invalid Python syntax" (RED's exact PoC module), so if the cache were
    # ever reused as PASS without a real load, that would be observably wrong.
    prime_env = _base_env(fake_bin, docker_log, {"WARM_CACHE_PRIME": "1", "FAKE_DOCKER_RUN_EXIT": "1"})
    primed = _run_validate_warm(project, harness, prime_env)
    assert primed.returncode == 0, primed.stdout
    assert "CACHE PRIMED" in primed.stdout, primed.stdout

    # The prime must not have invoked the real validation subcommand at all.
    log_after_prime = docker_log.read_text(encoding="utf-8")
    assert "run --rm" not in log_after_prime, (
        f"WARM_CACHE_PRIME invoked the real docker run step -- it must stay a "
        f"docker-free fixture hook. Log:\n{log_after_prime}"
    )

    # The on-disk marker must be stamped as PRIMED, not indistinguishable from
    # a genuine run (this is the provenance fix's core artifact).
    markers = _cache_marker_files(harness, slug)
    assert len(markers) == 1, markers
    assert markers[0].read_text(encoding="utf-8").strip() == "provenance=primed"

    # Step 2: an entirely ordinary, LATER, production invocation -- no
    # WARM_CACHE_PRIME, exactly what a real `git push` would run. It reads
    # the exact same on-disk marker the prime just wrote.
    prod_env = _base_env(fake_bin, docker_log, {"FAKE_DOCKER_RUN_EXIT": "1"})
    prod = _run_validate_warm(project, harness, prod_env)

    assert "PASS (cached, no-op)" not in prod.stdout, (
        "a primed, non-genuine marker was reused as a cached PASS by a plain "
        f"production invocation -- the bypass is NOT closed. stdout:\n{prod.stdout}"
    )
    # It must instead have re-validated for real (invoked docker's run step)
    # and, since that run is rigged to fail, reported FAIL -- never a silent
    # green.
    log_after_prod = docker_log.read_text(encoding="utf-8")
    assert "run --rm" in log_after_prod, (
        f"the production invocation never invoked a real docker validation run "
        f"-- it must fall through to one instead of trusting the primed marker. "
        f"Log:\n{log_after_prod}"
    )
    assert prod.returncode != 0, prod.stdout
    assert "[warm] FAIL" in prod.stdout, prod.stdout
    assert "non-genuine provenance" in prod.stdout, prod.stdout


# ==========================================================================
# (2) NON-VACUOUSNESS CONTROL -- the exact pre-fix caching logic, embedded
#     literally (never fetched via `git show HEAD`), driven through the same
#     prime-then-plain sequence, DOES serve a fabricated cached PASS.
# ==========================================================================
OLD_CACHE_LOGIC_SH = """#!/usr/bin/env bash
set -euo pipefail
CACHE_DIR="$1"; KEY="$2"; MODE="$3"
if [ -f "${CACHE_DIR}/${KEY}" ]; then
  echo "[warm] PASS (cached, no-op): content already validated on this warm base (key ${KEY:0:12}); -u not re-run."
  exit 0
fi
if [ "$MODE" = "prime" ]; then
  mkdir -p "$CACHE_DIR"
  : > "${CACHE_DIR}/${KEY}"
  echo "[warm] CACHE PRIMED ${KEY:0:12}"
  exit 0
fi
echo "[warm] would run real docker validation here (module is BROKEN in this scenario)"
exit 1
"""


def test_old_cache_logic_would_have_reused_a_primed_marker_as_pass(tmp_path):
    old_script = tmp_path / "old_cache_logic.sh"
    old_script.write_text(OLD_CACHE_LOGIC_SH, encoding="utf-8")
    old_script.chmod(old_script.stat().st_mode | stat.S_IXUSR)

    cache_dir = tmp_path / "old-cache"
    key = "deadbeefcafe" * 4  # arbitrary stand-in cache key

    primed = subprocess.run(
        ["bash", str(old_script), str(cache_dir), key, "prime"],
        text=True, capture_output=True, check=False,
    )
    assert primed.returncode == 0, primed.stdout
    assert "CACHE PRIMED" in primed.stdout

    # A later, plain ("production") invocation of the OLD logic against the
    # SAME out-of-band-primed marker.
    prod = subprocess.run(
        ["bash", str(old_script), str(cache_dir), key, "check"],
        text=True, capture_output=True, check=False,
    )
    assert prod.returncode == 0, prod.stdout
    assert "PASS (cached, no-op)" in prod.stdout, (
        "the embedded pre-fix logic no longer reproduces the bypass -- this "
        "control is no longer discriminating"
    )
    # This is exactly the RED PoC outcome: a "broken module" (the old script's
    # "check" branch, if it had actually run, would have printed FAIL/exit 1)
    # never ran, yet a PASS was printed anyway -- confirming the historical
    # defect this diff's provenance check closes.


# ==========================================================================
# (3) ENV-SCRUB -- the odoo pre-push hook must unset WARM_CACHE_PRIME before
#     calling validate-warm.sh, so an inherited/leaked test-only override can
#     never reach a real push.
# ==========================================================================
def test_prepush_scrubs_warm_cache_prime_before_validating(tmp_path):
    project, harness, slug, docker_log, fake_bin = _setup(tmp_path, "scrub")
    # A change to custom-addons/ that hooks/pre-push must actually validate.
    (project / "custom-addons" / "mod1" / "views.xml").write_text(
        "<odoo><data>v2</data></odoo>\n", encoding="utf-8"
    )
    new_sha = _commit_all(project, "v2")

    # A clean, SUCCESSFUL docker run this time (FAKE_DOCKER_RUN_EXIT=0) so a
    # real push can go all the way green -- proving the scrub didn't just
    # accidentally turn a would-be prime into a block; it turned it into a
    # REAL validation that legitimately passes.
    env = _base_env(fake_bin, docker_log, {
        "WARM_CACHE_PRIME": "1",       # simulates a leaked/ambient test-only override
        "FAKE_DOCKER_RUN_EXIT": "0",
        "ODOO_HARNESS_DIR": str(harness),
    })
    stdin = f"refs/heads/main {new_sha} refs/heads/main 0000000000000000000000000000000000000000\n"
    result = subprocess.run(
        ["bash", str(PRE_PUSH)],
        cwd=project,
        input=stdin,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )

    assert "CACHE PRIMED" not in result.stdout, (
        "hooks/pre-push let an inherited WARM_CACHE_PRIME=1 reach validate-warm.sh "
        f"-- the env-scrub chokepoint is missing or broken. stdout:\n{result.stdout}"
    )
    log = docker_log.read_text(encoding="utf-8")
    assert "run --rm" in log, (
        f"pre-push never reached a real docker validation run -- expected it to, "
        f"once WARM_CACHE_PRIME was correctly scrubbed. Log:\n{log}"
    )
    assert result.returncode == 0, result.stdout
    assert "Odoo validation passed" in result.stdout, result.stdout

    # The marker this real run left behind must be genuine-provenance (not the
    # scrubbed-away primed path).
    markers = _cache_marker_files(harness, slug)
    assert len(markers) == 1, markers
    assert markers[0].read_text(encoding="utf-8").strip() == "provenance=genuine"


# ==========================================================================
# (4) REGRESSION -- the legitimate caching optimization still works for a
#     GENUINE (docker-backed) PASS, and WARM_CACHE_PRIME still works for its
#     intended docker-free test/CI purpose.
# ==========================================================================
def test_genuine_pass_is_legitimately_cached_and_reused(tmp_path):
    project, harness, slug, docker_log, fake_bin = _setup(tmp_path, "regress")

    # First, ordinary production invocation with a real (shimmed) docker run
    # that SUCCEEDS -- a genuine PASS.
    env1 = _base_env(fake_bin, docker_log, {"FAKE_DOCKER_RUN_EXIT": "0"})
    first = _run_validate_warm(project, harness, env1)
    assert first.returncode == 0, first.stdout
    assert "[warm] PASS —" in first.stdout, first.stdout
    assert "cached" not in first.stdout, first.stdout  # genuine, not a cache-hit

    markers = _cache_marker_files(harness, slug)
    assert len(markers) == 1, markers
    assert markers[0].read_text(encoding="utf-8").strip() == "provenance=genuine"

    calls_after_first = docker_log.read_text(encoding="utf-8").count("run --rm")
    assert calls_after_first == 1

    # Second, ordinary production invocation, SAME content/key: must reuse the
    # genuine marker as a cached PASS, WITHOUT invoking docker's run step again
    # -- the real optimization this cache exists for still works post-fix.
    env2 = _base_env(fake_bin, docker_log, {"FAKE_DOCKER_RUN_EXIT": "1"})  # would FAIL if (wrongly) re-run
    second = _run_validate_warm(project, harness, env2)
    assert second.returncode == 0, second.stdout
    assert "PASS (cached, no-op)" in second.stdout, second.stdout

    calls_after_second = docker_log.read_text(encoding="utf-8").count("run --rm")
    assert calls_after_second == 1, (
        "a second production invocation with identical content re-ran the real "
        "docker validation instead of legitimately reusing the genuine cached PASS"
    )

    # WARM_CACHE_PRIME still works for its intended docker-free test purpose:
    # a FRESH key (different module content) can still be primed with zero
    # docker calls, in an equally-primed context.
    (project / "custom-addons" / "mod1" / "views.xml").write_text(
        "<odoo><data>v-fresh-for-prime-test</data></odoo>\n", encoding="utf-8"
    )
    # HARNESS_VALIDATE_REF defaults to HEAD (RED17b-2's immutable-snapshot
    # fix), so the edit must be COMMITTED to actually change what gets
    # materialized/hashed -- an uncommitted edit would (correctly) still hit
    # the prior genuine cache key, which is the right behavior but not what
    # this step means to exercise.
    _commit_all(project, "fresh content for prime test")
    env3 = _base_env(fake_bin, docker_log, {"WARM_CACHE_PRIME": "1", "FAKE_DOCKER_RUN_EXIT": "1"})
    third = _run_validate_warm(project, harness, env3)
    assert third.returncode == 0, third.stdout
    assert "CACHE PRIMED" in third.stdout, third.stdout
    calls_after_third = docker_log.read_text(encoding="utf-8").count("run --rm")
    assert calls_after_third == 1, "priming a fresh key must still stay docker-free"

    # And a SUBSEQUENT call in the SAME equally-primed context (WARM_CACHE_PRIME=1
    # again) legitimately reuses that primed marker -- the intended test/CI
    # cache-hit path, never available to a plain invocation (test 1 above).
    fourth = _run_validate_warm(project, harness, env3)
    assert fourth.returncode == 0, fourth.stdout
    assert "cached" in fourth.stdout or "CACHE PRIMED" in fourth.stdout, fourth.stdout
    calls_after_fourth = docker_log.read_text(encoding="utf-8").count("run --rm")
    assert calls_after_fourth == 1, "a same-context primed re-hit must stay docker-free too"


# ==========================================================================
# (5) validate-full.sh has no WARM_CACHE_PRIME hook of its own -- confirming
#     the sentence in this file's module docstring/report is accurate, not
#     just asserted.
# ==========================================================================
def test_validate_full_has_no_warm_cache_prime_hook():
    text = (HARNESS_SRC / "validate-full.sh").read_text(encoding="utf-8")
    assert "WARM_CACHE_PRIME" not in text
    assert "WARM_CACHE_KEY" not in text
    assert "WARM_CACHE_DIR" not in text


# ==========================================================================
# RED-10 finding 2 (trivial, LOW): check-schema-catalog.py must say
# explicitly "no changed modules to check" on an empty changed-module set,
# mirroring check-manifest-files.py's sibling wording, instead of the
# ambiguous "OK: screened 0 module(s)".
# ==========================================================================
def test_schema_catalog_empty_module_set_is_explicit(tmp_path):
    root = tmp_path / "custom-addons"
    root.mkdir()
    catalog = tmp_path / "catalog.json"
    catalog.write_text('{"schema": 1, "models": {}}', encoding="utf-8")

    result = subprocess.run(
        [
            "python3", str(CHECK_SCHEMA_CATALOG),
            "--root", str(root),
            "--catalog", str(catalog),
            "--modules", "doesnotexist",
        ],
        text=True, capture_output=True, check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "no changed modules to check" in result.stdout, result.stdout
    assert "screened 0 module(s)" not in result.stdout, result.stdout
