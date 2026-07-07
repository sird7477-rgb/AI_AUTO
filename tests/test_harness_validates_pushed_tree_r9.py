"""R9 ops-defense game (BLUE) fix for RED17b-2 (HIGH, TOCTOU), the one
carry-over finding from .ops-game/R8-red17b-final-convergence.md:

  RED17b-2  templates/domain-packs/odoo/validation-harness/validate-warm.sh /
            validate-full.sh bind-mounted the LIVE $PROJECT/custom-addons
            working directory into the docker validation container (via
            docker-compose.validate.yml's ${PROJECT_ADDONS} volume) -- never an
            immutable snapshot of the commit under test. hooks/pre-push
            correctly derives the pushed COMMITS' changed modules from git
            objects (the RED15-2 fix), but the actual registry-load container
            reads whatever bytes are on disk at container-read time (~tens of
            seconds to ~2 minutes into the run) -- a same-UID or merely
            concurrent (non-adversarial) edit to custom-addons/ WHILE
            validation runs makes the container test different content than
            the commit `git push` actually transmits, so a real "Odoo
            validation passed" certifies bytes that were never the pushed
            tree.

  Fix: both scripts now materialize an immutable snapshot of a target
  commit-ish (HARNESS_VALIDATE_REF env, default HEAD) via
  `git archive <ref> -- custom-addons | tar -x -C <tmpdir>` and point
  PROJECT_ADDONS at that snapshot instead of the live tree, with a cleanup
  trap dropping the tmpdir on every exit path. hooks/pre-push threads the
  exact pushed local sha(s) (from the same authentic stdin `<lsha>` the
  RED15-2 fix already established) through as HARNESS_VALIDATE_REF, so a push
  validates precisely what it transmits. serve.sh (hands-on dev) is
  deliberately left as a live mount -- out of scope, untouched.

These tests are hermetic and never touch a real docker daemon:
validate-warm.sh is driven down its WARM_CACHE_PRIME test hook (an existing,
pre-fix mechanism -- see its own "fixturable offline" comment), which computes
and records a content hash purely from the filesystem before ever reaching a
`docker compose` call; check-parity.sh/harness-slug.sh/harness-lock.sh also
need no docker. `docker` itself is faked as a harmless no-op on PATH only to
satisfy harness-preflight.sh's availability probe (mirrors the existing
`_fake_docker_bin` pattern in tests/test_odoo_harness_honesty_r2.py). The
harness scripts under test are copied into a per-test tmp_path "harness" dir
(never the real shared worktree) so every artifact they write (cache/lock/
epoch files, the materialized snapshot itself) is fully isolated.

Non-vacuousness: each assertion targets behavior that is only true of the
FIXED script content. Reverting validate-warm.sh / validate-full.sh /
hooks/pre-push to their pre-fix content (`git show HEAD:<path>`, since these
edits are uncommitted in this worktree at authoring time) makes the
corresponding assertion fail -- see the session's final report for the
revert/rerun proof of each.
"""
from __future__ import annotations

import hashlib
import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
HARNESS_SRC = ODOO_PACK / "validation-harness"
PRE_PUSH = ODOO_PACK / "hooks" / "pre-push"

# Files validate-warm.sh needs on disk next to it (sourced or exec'd as
# siblings via $HERE) to reach the WARM_CACHE_PRIME hook without touching a
# real docker daemon.
_HARNESS_FILES = [
    "validate-warm.sh",
    "validate-full.sh",
    "harness-preflight.sh",
    "harness-slug.sh",
    "harness-lock.sh",
    "check-parity.sh",
]


# --------------------------------------------------------------------------
# shared fixture helpers
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
    """A hermetic, no-op fake `docker` on PATH: succeeds unconditionally for
    any subcommand (info/version/compose...), never touches a real daemon.
    Same pattern as tests/test_odoo_harness_honesty_r2.py."""
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    _make_executable(docker)
    return bin_dir


def _copy_harness(tmp_path: Path) -> Path:
    """Copy just the harness files validate-warm.sh/validate-full.sh need
    (see _HARNESS_FILES) into a fresh, isolated tmp_path directory -- so
    $HERE/$HARNESS_DIR resolve there, and every artifact the scripts write
    (cache dir, lock file, epoch file, the materialized snapshot) lands in
    this throwaway dir, never in the real shared worktree."""
    harness = tmp_path / "harness"
    harness.mkdir()
    for name in _HARNESS_FILES:
        dst = harness / name
        shutil.copy2(HARNESS_SRC / name, dst)
        _make_executable(dst)
    return harness


def _slug_of(project: Path, harness: Path) -> str:
    cmd = f'. "{harness / "harness-slug.sh"}"; harness_proj_slug "{project}"'
    result = subprocess.run(["bash", "-c", cmd], text=True, capture_output=True, check=True)
    return result.stdout.strip()


def _stamp_parity(harness: Path, slug: str, base_db: str, modules_csv: str) -> None:
    """Write the parity stamp check-parity.sh requires to PASS (it only
    compares the MODULE NAME SET, never file content -- a narrower, separate
    concern than RED17b-2, and check-parity.sh is out of this fix's scope)."""
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


def _content_hash_reference(base_dir: Path, modules: list[str]) -> str:
    """Independent re-implementation of validate-warm.sh's warm_content_hash()
    (find + `LC_ALL=C sort -z` + sha256sum-per-file + sha256 of the joined
    listing) so tests can assert what the FIXED script's cache-hash *should*
    be for a given directory's content, without calling the script's own
    function (that would be circular)."""
    files: list[Path] = []
    for m in modules:
        mod_dir = base_dir / m
        if not mod_dir.is_dir():
            continue
        for p in mod_dir.rglob("*"):
            if not p.is_file():
                continue
            if "__pycache__" in p.parts or p.name.endswith(".pyc"):
                continue
            files.append(p)
    files.sort(key=lambda p: str(p).encode("utf-8"))  # LC_ALL=C byte-order, matches `sort -z`
    lines = []
    for p in files:
        digest = hashlib.sha256(p.read_bytes()).hexdigest()
        rel = str(p.relative_to(base_dir))
        lines.append(f"{digest}  {rel}\n")
    blob = "".join(lines).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def _run_warm_cache_prime(
    project: Path, harness: Path, fake_bin: Path, *, ref: str | None
) -> subprocess.CompletedProcess[str]:
    slug = _slug_of(project, harness)
    base_db = "base"
    _stamp_parity(harness, slug, base_db, "mod1")
    _stamp_epoch(harness, slug, base_db)
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
    env["WARM_CACHE_PRIME"] = "1"
    env.pop("HARNESS_VALIDATE_REF", None)
    if ref is not None:
        env["HARNESS_VALIDATE_REF"] = ref
    return subprocess.run(
        ["bash", str(harness / "validate-warm.sh"), str(project), "mod1"],
        cwd=harness,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def _cache_primed_hash(result: subprocess.CompletedProcess[str]) -> str:
    """Extract the 12-hex-char WARM_CACHE_KEY prefix the script printed --
    either from a fresh '[warm] CACHE PRIMED <hash>' (first time this exact
    key is seen) or from a repeat '... (key <hash>); -u not re-run.' (a
    SUBSEQUENT run whose (modset, content hash, epoch) key already matches a
    prior PRIMED run -- itself a positive signal, not a test failure: it is
    only possible when the validated content is byte-identical both times)."""
    import re

    m = re.search(r"CACHE PRIMED ([0-9a-f]{12})", result.stdout)
    if m:
        return m.group(1)
    m = re.search(r"\(key ([0-9a-f]{12})\)", result.stdout)
    if m:
        return m.group(1)
    raise AssertionError(
        f"no 'CACHE PRIMED <hash>' or '(key <hash>)' line in output:\n{result.stdout}"
    )


def _expected_cache_key(content_hash_hex: str, modset: str = "mod1", epoch: str = "1") -> str:
    """Reproduces validate-warm.sh's own formula (see its comment: the key is
    sha256(sorted modset | on-disk content hash | base epoch)) so a test can
    assert the EXACT printed key, not just relative (in)equality between two
    runs -- ties the observed output to the precise fixed-content bytes."""
    return hashlib.sha256(f"{modset}|{content_hash_hex}|{epoch}".encode("utf-8")).hexdigest()[:12]


# ==========================================================================
# (1) mutating the live custom-addons after resolution does NOT change the
#     bytes the harness would mount -- PROJECT_ADDONS points at a SNAPSHOT.
# ==========================================================================
def test_warm_live_mutation_after_commit_does_not_change_validated_bytes(tmp_path):
    project = _make_module_project(tmp_path)
    c1 = _commit_all(project, "v1")
    # Captured NOW, while the live tree still equals c1's content (right after
    # a clean commit, before any further edit) -- the independent oracle for
    # what SHOULD be validated, computed from the same directory the pre-fix
    # code would have bind-mounted live, before it gets mutated below.
    expected_c1_content_hash = _content_hash_reference(project / "custom-addons", ["mod1"])
    harness = _copy_harness(tmp_path)
    fake_bin = _fake_docker_bin(tmp_path)

    # Pin validation to c1 explicitly (the "pushed commit").
    before = _run_warm_cache_prime(project, harness, fake_bin, ref=c1)
    assert before.returncode == 0, before.stdout
    hash_before = _cache_primed_hash(before)

    # MUTATE the live working tree (uncommitted) -- simulates a concurrent
    # same-UID edit landing while a docker validation run is mid-flight.
    (project / "custom-addons" / "mod1" / "views.xml").write_text(
        "<odoo><data>MUTATED-WHILE-VALIDATING</data></odoo>\n", encoding="utf-8"
    )

    after = _run_warm_cache_prime(project, harness, fake_bin, ref=c1)
    assert after.returncode == 0, after.stdout
    hash_after = _cache_primed_hash(after)

    assert hash_before == hash_after, (
        "the live-tree mutation changed the bytes the harness would validate for "
        f"the SAME pinned ref {c1} -- PROJECT_ADDONS is not an immutable snapshot "
        f"(before={hash_before} after={hash_after})"
    )
    # Positive corroboration: the printed key really does equal the formula
    # applied to c1's OWN (pre-mutation) content, not some constant/degenerate
    # value that happens to be stable for the wrong reason.
    assert hash_before == _expected_cache_key(expected_c1_content_hash)


# ==========================================================================
# (2) the harness validates the PASSED ref's content, not HEAD/working-tree,
#     when they differ.
# ==========================================================================
def test_warm_validates_passed_ref_not_head_or_worktree(tmp_path):
    project = _make_module_project(tmp_path)
    c1 = _commit_all(project, "v1")
    (project / "custom-addons" / "mod1" / "views.xml").write_text(
        "<odoo><data>v2-on-head</data></odoo>\n", encoding="utf-8"
    )
    c2 = _commit_all(project, "v2")  # HEAD is now c2, content differs from c1
    assert c1 != c2

    harness = _copy_harness(tmp_path)
    fake_bin = _fake_docker_bin(tmp_path)

    # Independently materialize each commit's own custom-addons to compute the
    # ground-truth expected hash for each -- an oracle independent of the
    # script under test.
    def _archive_hash(ref: str) -> str:
        scratch = tmp_path / f"scratch-{ref}"
        scratch.mkdir()
        subprocess.run(
            f'git -C "{project}" archive {ref} -- custom-addons | tar -x -C "{scratch}"',
            shell=True, check=True,
        )
        return _content_hash_reference(scratch / "custom-addons", ["mod1"])

    expected_c1_content = _archive_hash(c1)
    expected_c2_content = _archive_hash(c2)
    assert expected_c1_content != expected_c2_content, "test setup bug: c1/c2 content hash the same"
    expected_key_c1 = _expected_cache_key(expected_c1_content)
    expected_key_c2 = _expected_cache_key(expected_c2_content)

    # Explicit ref = c1, even though HEAD (and the live worktree) is at c2.
    result_c1 = _run_warm_cache_prime(project, harness, fake_bin, ref=c1)
    assert result_c1.returncode == 0, result_c1.stdout
    assert _cache_primed_hash(result_c1) == expected_key_c1

    # Default (no HARNESS_VALIDATE_REF) -> HEAD, i.e. c2's content (also the
    # live worktree's content here, since it is unmodified since the c2 commit).
    result_head = _run_warm_cache_prime(project, harness, fake_bin, ref=None)
    assert result_head.returncode == 0, result_head.stdout
    assert _cache_primed_hash(result_head) == expected_key_c2
    assert _cache_primed_hash(result_head) != expected_key_c1


# ==========================================================================
# (3) cleanup removes the materialized snapshot tmpdir.
# ==========================================================================
def test_warm_cleanup_removes_snapshot_tmpdir(tmp_path):
    project = _make_module_project(tmp_path)
    c1 = _commit_all(project, "v1")
    harness = _copy_harness(tmp_path)
    fake_bin = _fake_docker_bin(tmp_path)

    def _snapshots() -> list[Path]:
        return sorted(harness.glob(".odoo-harness-snap.*"))

    assert _snapshots() == []
    # WARM_CACHE_PRIME exits well before `trap cleanup_warm EXIT` is (re-)installed
    # further down the script, so this exercises the EARLY simple trap installed
    # right after materialization (`trap 'rm -rf "$HARNESS_SNAPSHOT_DIR" ...' EXIT`),
    # not the later docker-run cleanup -- i.e. it proves the tmpdir is reclaimed on
    # this early-exit path too, not only the full validation path.
    result = _run_warm_cache_prime(project, harness, fake_bin, ref=c1)
    assert result.returncode == 0, result.stdout
    assert _snapshots() == [], (
        "a .odoo-harness-snap.* tmpdir survived the script's exit -- the "
        "cleanup trap did not remove the materialized commit snapshot"
    )


# ==========================================================================
# (4) hooks/pre-push threads the pushed local sha through as
#     HARNESS_VALIDATE_REF.
# ==========================================================================
def _stub_validate_warm(harness: Path, record: Path) -> None:
    """A fake validate-warm.sh that records ($PROJECT, $HARNESS_VALIDATE_REF,
    $*) for each invocation and exits 0 -- isolates the pre-push threading
    contract from the real (heavier) script."""
    harness.mkdir(parents=True, exist_ok=True)
    stub = harness / "validate-warm.sh"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        f'printf \'PROJECT=%s REF=%s MODS=%s\\n\' "$1" "${{HARNESS_VALIDATE_REF:-<unset>}}" '
        '"${*:2}" >> "' + str(record) + '"\n'
        "exit 0\n",
        encoding="utf-8",
    )
    _make_executable(stub)


def _run_prepush(
    project: Path, stdin: str, env_extra: dict, fake_bin: Path
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.pop("SKIP_ODOO_VALIDATE", None)
    # Fake `docker` on PATH: pre-push's own `docker info` availability gate
    # must not depend on a real daemon being reachable in whatever environment
    # runs this test (this sandbox happens to have one; CI may not).
    env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
    env.update(env_extra)
    return subprocess.run(
        ["bash", str(PRE_PUSH)], cwd=project, input=stdin, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
    )


def test_prepush_threads_pushed_local_sha_as_harness_validate_ref(tmp_path):
    project = _make_module_project(tmp_path)
    base_sha = _commit_all(project, "base")
    (project / "custom-addons" / "mod1" / "views.xml").write_text(
        "<odoo><data>v2</data></odoo>\n", encoding="utf-8"
    )
    new_sha = _commit_all(project, "add a view")

    harness_dir = tmp_path / "stub-harness"
    record = tmp_path / "record.txt"
    _stub_validate_warm(harness_dir, record)
    fake_bin = _fake_docker_bin(tmp_path)

    stdin = f"refs/heads/main {new_sha} refs/heads/main {base_sha}\n"
    result = _run_prepush(project, stdin, {"ODOO_HARNESS_DIR": str(harness_dir)}, fake_bin)

    assert result.returncode == 0, result.stdout
    assert record.exists(), result.stdout
    lines = record.read_text(encoding="utf-8").strip().splitlines()
    assert len(lines) == 1, lines
    assert f"REF={new_sha}" in lines[0], (
        f"pre-push did not pass the pushed local sha ({new_sha}) through as "
        f"HARNESS_VALIDATE_REF: {lines[0]!r}"
    )
    assert "REF=<unset>" not in lines[0], lines[0]


def test_prepush_validates_each_pushed_local_sha_on_multi_ref_push(tmp_path):
    """A single `git push` can feed pre-push more than one ref line (pushing
    several branches at once). Each pushed local sha must be validated
    individually against ITS OWN snapshot -- not silently collapsed to one."""
    project = _make_module_project(tmp_path)
    base_sha = _commit_all(project, "base")
    (project / "custom-addons" / "mod1" / "views.xml").write_text(
        "<odoo><data>branch-a</data></odoo>\n", encoding="utf-8"
    )
    sha_a = _commit_all(project, "branch a change")
    _git(["branch", "other", base_sha], project)
    _git(["checkout", "-q", "other"], project)
    (project / "custom-addons" / "mod1" / "views.xml").write_text(
        "<odoo><data>branch-b</data></odoo>\n", encoding="utf-8"
    )
    sha_b = _commit_all(project, "branch b change")

    harness_dir = tmp_path / "stub-harness"
    record = tmp_path / "record.txt"
    _stub_validate_warm(harness_dir, record)
    fake_bin = _fake_docker_bin(tmp_path)

    stdin = (
        f"refs/heads/a {sha_a} refs/heads/a {base_sha}\n"
        f"refs/heads/b {sha_b} refs/heads/b {base_sha}\n"
    )
    result = _run_prepush(project, stdin, {"ODOO_HARNESS_DIR": str(harness_dir)}, fake_bin)

    assert result.returncode == 0, result.stdout
    lines = record.read_text(encoding="utf-8").strip().splitlines()
    refs_seen = {ln.split()[1].split("=", 1)[1] for ln in lines}
    assert refs_seen == {sha_a, sha_b}, (
        f"expected both pushed local shas to be validated individually, got {refs_seen}"
    )


# ==========================================================================
# validate-full.sh gets the same materialization fix -- prove it separately
# (pre-push never calls validate-full.sh itself; it is the on-demand/pre-PR
# tier, but ships the identical live-mount TOCTOU per RED17b-2's own wording).
# Observable here without any docker-hash hook: the reverse-dependency SCOPE
# line is computed by reading __manifest__.py files out of $PROJECT_ADDONS, so
# whether a dependent module shows up in the printed scope directly reveals
# which commit's tree was actually materialized.
# ==========================================================================
def _run_full_scope_only(
    project: Path, harness: Path, fake_bin: Path, *, ref: str | None
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
    # Skip both sub-passes explicitly -- isolates the (pre-docker) reverse-dep
    # SCOPE computation from needing a real odoo/docker backend at all.
    env["SKIP_TEST_PASS"] = "1"
    env["SKIP_DEMO_PASS"] = "1"
    env.pop("HARNESS_VALIDATE_REF", None)
    if ref is not None:
        env["HARNESS_VALIDATE_REF"] = ref
    return subprocess.run(
        ["bash", str(harness / "validate-full.sh"), str(project), "mod1"],
        cwd=harness,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def _full_scope(result: subprocess.CompletedProcess[str]) -> str:
    import re

    m = re.search(r"scope \(with reverse-deps\): (\S+)", result.stdout)
    assert m, f"no '... scope (with reverse-deps): ...' line in output:\n{result.stdout}"
    return m.group(1)


def test_full_validates_passed_ref_not_head_or_worktree(tmp_path):
    project = _make_module_project(tmp_path)
    c1 = _commit_all(project, "v1")  # only mod1 exists at c1

    # mod2 (added at c2) depends on mod1 -- a reverse-dependent that can only
    # show up in the "changed: mod1 -> scope (with reverse-deps): ..." line if
    # the SNAPSHOT actually materialized c2's tree, not c1's.
    mod2 = project / "custom-addons" / "mod2"
    mod2.mkdir(parents=True)
    (mod2 / "__manifest__.py").write_text(
        "{'name': 'mod2', 'depends': ['mod1']}\n", encoding="utf-8"
    )
    c2 = _commit_all(project, "add mod2 depending on mod1")
    assert c1 != c2

    harness = _copy_harness(tmp_path)
    fake_bin = _fake_docker_bin(tmp_path)

    result_c1 = _run_full_scope_only(project, harness, fake_bin, ref=c1)
    assert result_c1.returncode == 0, result_c1.stdout
    assert _full_scope(result_c1) == "mod1", (
        "mod2 (which only exists at c2) leaked into the scope computed while "
        f"pinned to c1 -- validate-full.sh is not reading a c1 snapshot:\n{result_c1.stdout}"
    )

    # Default (no HARNESS_VALIDATE_REF) -> HEAD, i.e. c2 -- mod2 (a reverse-dep
    # of the changed mod1) must now be pulled into scope.
    result_head = _run_full_scope_only(project, harness, fake_bin, ref=None)
    assert result_head.returncode == 0, result_head.stdout
    assert _full_scope(result_head) == "mod1,mod2", (
        f"expected mod2's reverse-dep to be pulled in at HEAD (c2):\n{result_head.stdout}"
    )
