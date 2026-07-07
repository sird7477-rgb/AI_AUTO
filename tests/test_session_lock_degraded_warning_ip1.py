"""RED3-2 regression (MED-HIGH): scripts/session-lock.sh fails OPEN with ZERO warning when
BOTH exclusivity mechanisms it knows fail for a non-contention reason -- O_EXCL not honored
(9p / Windows Z: mounts silently ignore it, per this file's own comments) AND `flock` is
absent from PATH (a stripped/minimal subprocess PATH). The prior code returned rc=2 from
`_session_lock_publish` / `_session_lock_reclaim` straight into a bare `return 0` in
`session_lock_acquire`, proceeding UNGUARDED with no stdout/stderr at all -- two concurrent
sessions could then race `.omx/reviewer-state/*` / the working tree with no diagnostic trail.

The fix keeps the degradation non-fatal (fail-open still beats hanging or hard-failing an
entire gate run over lock infra) but makes it LOUD: a `[lock] WARNING: ... proceeding
WITHOUT exclusivity ...` line on stderr.

Hermetic: builds a throwaway working directory and a minimal PATH containing exactly the
external commands session-lock.sh needs (sed/date/dirname/hostname/mkdir/rm) but NOT
`flock`, under tmp_path, then sources the real scripts/session-lock.sh as a subprocess --
mirroring tests/test_docker_config_guard.py's subprocess-driven pattern.
"""
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SESSION_LOCK = ROOT / "scripts" / "session-lock.sh"
# Resolved via the TEST RUNNER's own (unmodified) PATH -- the child's PATH is deliberately
# stripped down to a `flock`-less minimal set (see _path_without_flock), which would make a
# bare "bash" argv[0] unresolvable if subprocess had to look it up in that same stripped env.
BASH_BIN = shutil.which("bash") or "/bin/bash"


# The exact (small) set of EXTERNAL commands session-lock.sh shells out to (`kill`/`printf`
# are bash builtins, not looked up on PATH). Deliberately curated rather than mirroring the
# ambient PATH wholesale: this host's PATH also includes slow WSL/9p-mounted Windows
# directories (/mnt/c/...), and enumerating those to build a mirror bin dir made this test
# take 10s+ per case for no benefit -- a hermetic test should not pay that ambient cost.
_NEEDED_COMMANDS = ("date", "dirname", "head", "hostname", "mkdir", "rm", "sed")
_CANDIDATE_DIRS = ("/usr/bin", "/bin", "/usr/local/bin")


def _path_without_flock(tmp_path: Path) -> str:
    """A minimal bin dir containing exactly the external commands session-lock.sh needs,
    symlinked from standard Linux system dirs -- with `flock` deliberately absent, so
    `flock -w 10 ...` hits "command not found" exactly like a stripped/minimal
    container/sandbox shell missing util-linux."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    found = set()
    for name in _NEEDED_COMMANDS:
        for d in _CANDIDATE_DIRS:
            src = os.path.join(d, name)
            if os.path.isfile(src) or os.path.islink(src):
                (bindir / name).symlink_to(src)
                found.add(name)
                break
    missing = set(_NEEDED_COMMANDS) - found
    assert not missing, f"fixture PATH missing basics: {missing}"
    assert not (bindir / "flock").exists()
    return str(bindir)


def _acquire(tmp_path: Path, *, op: str = "testop") -> subprocess.CompletedProcess[str]:
    workdir = tmp_path / "work"
    workdir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["PATH"] = _path_without_flock(tmp_path)
    # Force the O_EXCL probe to report "not honored" (simulating the 9p / Z: condition)
    # without needing an actual such filesystem -- an explicit override this file supports.
    env["AI_AUTO_SESSION_LOCK_OEXCL"] = "0"
    env["SESSION_LOCK_FILE"] = str(workdir / ".omx" / "state" / "session.lock")
    script = f". '{SESSION_LOCK}'; session_lock_acquire {op}; rc=$?; echo \"ACQUIRE_RC=$rc\"; echo \"HELD=$SESSION_LOCK_HELD\""
    return subprocess.run(
        [BASH_BIN, "-c", script],
        cwd=workdir,
        env=env,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_degraded_fresh_publish_warns_loudly_and_still_proceeds(tmp_path: Path) -> None:
    """Fresh-lock path: no lock file exists yet, O_EXCL forced off, flock absent -> both
    `_session_lock_excl_publish`/`_session_lock_flock_publish` are unavailable ->
    `_session_lock_publish` returns rc=2 -> acquire must still proceed (rc=0) but MUST warn."""
    result = _acquire(tmp_path)

    assert "ACQUIRE_RC=0" in result.stdout, f"stdout={result.stdout!r} stderr={result.stderr!r}"
    assert "WARNING" in result.stderr and "exclusivity" in result.stderr, (
        "session_lock_acquire degraded to no-lock (no O_EXCL, no flock) with NO warning "
        f"(RED3-2 regression). stdout={result.stdout!r} stderr={result.stderr!r}"
    )


def test_degraded_stale_reclaim_warns_loudly_and_still_proceeds(tmp_path: Path) -> None:
    """Stale-reclaim path: a lock file already exists for a dead PID -> reclaim also hits
    the flock-less infra failure -> same rc=2 -> fail-open-but-loud contract must hold here
    too (this is a SEPARATE code path/call site from the fresh-publish one above)."""
    workdir = tmp_path / "work"
    workdir.mkdir(parents=True, exist_ok=True)
    lock_dir = workdir / ".omx" / "state"
    lock_dir.mkdir(parents=True, exist_ok=True)
    lock_file = lock_dir / "session.lock"
    # A lock held by a PID that is certainly not alive.
    lock_file.write_text(
        "holder_pid=999999\nholder_session=999999@deadhost\nholder_op=stale\nacquired_at=2000-01-01T00:00:00+00:00\n",
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["PATH"] = _path_without_flock(tmp_path)
    env["AI_AUTO_SESSION_LOCK_OEXCL"] = "0"
    env["SESSION_LOCK_FILE"] = str(lock_file)
    script = f". '{SESSION_LOCK}'; session_lock_acquire testop; rc=$?; echo \"ACQUIRE_RC=$rc\""
    result = subprocess.run(
        [BASH_BIN, "-c", script],
        cwd=workdir,
        env=env,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    assert "ACQUIRE_RC=0" in result.stdout, f"stdout={result.stdout!r} stderr={result.stderr!r}"
    assert "WARNING" in result.stderr and "exclusivity" in result.stderr, (
        "stale-lock reclaim degraded to no-lock (no O_EXCL, no flock) with NO warning "
        f"(RED3-2 regression). stdout={result.stdout!r} stderr={result.stderr!r}"
    )
