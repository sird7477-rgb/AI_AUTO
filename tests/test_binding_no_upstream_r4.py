"""RED7-1 regression (CRITICAL, re-attack on the R2 RED3-1 fix): the R2 fix unioned the tip
diff with `@{u}...HEAD` so an earlier unreviewed commit couldn't hide behind a reviewed
trivial tip -- but the union only ever fires when `@{u}` resolves. `@{u}` is UNSET on the
ordinary first push of any new local branch (`git checkout -b feature`, commit, commit,
`git push` -- no prior `git push -u` ever run), which is the common case, not an edge case.
In that state, `review_binding_committed_payload` (scripts/review-gate-binding.sh) and
`hooks/pre-push`'s per-ref loop both fell straight through to "just the tip commit", so an
earlier unreviewed commit (e.g. one adding `GRANT_ADMIN=true`) hidden under a trivial
reviewed tip commit sailed onto the remote on a genuine `git push`, exit 0.

See .ops-game/R3-red7-reattack.md (finding RED7-1) and .ops-game/R1-red3-conc-opcost.md
(RED3-1, the original this re-attacks).

The fix (this change): whenever no explicit base is available (no pre-push-supplied
remote sha; no `@{u}`), resolve `review_binding_safe_base_fallback` instead of collapsing to
tip-only -- the octopus merge-base with every known `refs/remotes/*` branch, or (nothing
known at all) the empty tree, so the range never silently narrows.

Hermetic, subprocess-driven, throwaway-git-repo tests mirroring
tests/test_binding_range_ip1.py / tests/test_pre_push_binding_ref_ip1.py.
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


def _base_env(tmp_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["AI_AUTO_HOME"] = str(ROOT)
    home = tmp_path / "home"
    home.mkdir(parents=True, exist_ok=True)
    env["HOME"] = str(home)
    env["AI_AUTO_PROVENANCE_KEY_FILE"] = str(tmp_path / "provenance.key")
    return env


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


def _record_proceed_binding(project: Path, env: dict[str, str]) -> None:
    """Mirror exactly what review-gate.sh does on a human 'proceed' verdict."""
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


def _committed_payload(project: Path, env: dict[str, str], *args: str) -> str:
    """Call review_binding_committed_payload directly (mirrors what both review-gate.sh's
    reviewer-facing flow and the push-time hash are computed over)."""
    quoted_args = " ".join(f"'{a}'" for a in args)
    script = (
        f". '{ROOT / 'scripts' / 'git-harden.sh'}'; "
        f". '{ROOT / 'scripts' / 'review-gate-binding.sh'}'; "
        f"review_binding_committed_payload {quoted_args}"
    )
    result = subprocess.run(
        ["bash", "-c", script],
        cwd=project,
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout


def _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path: Path, env: dict[str, str]) -> tuple[Path, str]:
    """Commit A (unreviewed, sneaks in GRANT_ADMIN=true) then commit B (trivial, the one
    that gets reviewed/bound) -- exactly the RED7-1 PoC scenario: a brand-new local branch,
    NO `git push -u` ever run, so `@{u}` is unset and (since nothing has ever been
    pushed/fetched) no refs/remotes/* exist either."""
    project = tmp_path / "project"
    _init_repo(project, env)
    _commit(project, env, "README.md", "hello\n", "init")

    (project / "g.txt").write_text("some setting\nGRANT_ADMIN=true\n", encoding="utf-8")
    _git(["add", "-A"], project, env)
    _git(["commit", "-q", "-m", "A: sneaky privilege escalation in g.txt"], project, env)

    (project / "f.txt").write_text("typo fixed\n", encoding="utf-8")
    _git(["add", "-A"], project, env)
    b_sha = _git(["commit", "-q", "-m", "B: trivial typo fix in f.txt"], project, env)
    b_sha = _git(["rev-parse", "HEAD"], project, env).stdout.strip()

    return project, b_sha


def test_committed_payload_covers_earlier_commit_with_no_upstream_at_all(tmp_path: Path) -> None:
    """Ambient-HEAD/interactive shape (review-gate.sh's own call: default target=HEAD,
    no explicit base) -- with NO upstream configured (`@{u}` unset), the payload must still
    surface commit A's content, not just tip commit B's."""
    env = _base_env(tmp_path)
    project, _b_sha = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)

    payload = _committed_payload(project, env)

    assert "GRANT_ADMIN" in payload, (
        "the binding payload only covered the tip commit and missed an earlier unreviewed, "
        f"unpushed commit when no upstream was configured at all (RED7-1 regression). "
        f"payload={payload!r}"
    )


def test_committed_payload_covers_earlier_commit_for_an_explicit_pushed_sha(tmp_path: Path) -> None:
    """The exact shape hooks/pre-push actually uses: target is a literal pushed sha (never
    the string "HEAD"), base is whatever pre-push resolved for a brand-new remote ref. This
    is the precise RED7-1 gap -- the old code's `[ "${target}" = "HEAD" ]` gate meant the
    `@{u}` fallback attempt (and, before this fix, ANY fallback at all) never even fired for
    this call shape."""
    env = _base_env(tmp_path)
    project, b_sha = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)

    payload = _committed_payload(project, env, b_sha, "")

    assert "GRANT_ADMIN" in payload, (
        "the binding payload only covered the tip commit and missed an earlier unreviewed, "
        f"unpushed commit for an explicit (non-HEAD) pushed sha with no base (RED7-1 "
        f"regression). payload={payload!r}"
    )


def test_pre_push_accepts_brand_new_ref_only_because_earlier_commit_was_actually_bound(tmp_path: Path) -> None:
    """Real-push shape end-to-end PoC: a bare remote that has NEVER been pushed to (so git's
    real stdin line reports the all-zero remote sha for this ref -- a genuinely new remote
    ref), no `git push -u` ever run beforehand. The human reviews/approves at tip B; the
    push of local_sha=B against remote_sha=all-zero must be accepted -- but ONLY because the
    recorded/rechecked hash actually covers commit A's content, not because pre-push
    degraded to a narrow, blind check. We prove the latter directly: an independently
    recomputed payload for this exact (target, pre-push-resolved-base) pair must contain
    GRANT_ADMIN -- if it didn't, the push would have been accepted based on a binding that
    never actually saw the smuggled commit (the exact RED7-1 bypass)."""
    env = _base_env(tmp_path)
    bare = tmp_path / "origin.git"
    _git(["init", "-q", "--bare", str(bare)], tmp_path, env)

    project, b_sha = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)
    _git(["remote", "add", "origin", str(bare)], project, env)

    _record_proceed_binding(project, env)

    zero_sha = "0" * 40
    stdin = f"refs/heads/main {b_sha} refs/heads/main {zero_sha}\n"
    result = subprocess.run(
        ["bash", str(PRE_PUSH)],
        cwd=project,
        env=env,
        input=stdin,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert result.returncode == 0, (
        f"a legitimately-recorded proceed verdict was rejected. stdout={result.stdout!r} "
        f"stderr={result.stderr!r}"
    )

    # Independently recompute the exact payload pre-push's fallback resolves for this ref
    # update and assert it is NOT tip-only -- this is what makes the exit-0 above meaningful
    # rather than a blind pass-through (RED7-1's actual failure mode).
    fallback_base = subprocess.run(
        ["bash", "-c",
         f". '{ROOT / 'scripts' / 'git-harden.sh'}'; "
         f". '{ROOT / 'scripts' / 'review-gate-binding.sh'}'; "
         f"review_binding_safe_base_fallback '{b_sha}'"],
        cwd=project, env=env, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    ).stdout.strip()
    payload = _committed_payload(project, env, b_sha, fallback_base)
    assert "GRANT_ADMIN" in payload, (
        "pre-push accepted the brand-new-ref push, but the underlying payload/hash it "
        "actually bound to was tip-only and never covered the earlier unreviewed commit "
        f"(RED7-1 regression). payload={payload!r}"
    )


def test_pre_push_accepts_a_normal_already_upstreamed_push_unaffected_by_the_fallback(tmp_path: Path) -> None:
    """Guard/non-vacuousness companion: an ordinary push over an ALREADY-upstreamed branch
    (a real remote sha, not all-zero) must still work exactly as before -- the RED7-1 fix
    only changes the no-base fallback path, it must not touch the already-correct
    explicit-remote-sha path."""
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

    stdin = f"refs/heads/main {main_sha} refs/heads/main {root_sha}\n"
    result = subprocess.run(
        ["bash", str(PRE_PUSH)],
        cwd=project,
        env=env,
        input=stdin,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert result.returncode == 0, f"stdout={result.stdout!r} stderr={result.stderr!r}"
