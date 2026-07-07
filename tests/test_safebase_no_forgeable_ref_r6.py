"""RED11-1 regression (CRITICAL, .ops-game/R5-red11-reattack.md): the RED7-1 fix (round 4)
made `review_binding_safe_base_fallback` (scripts/review-gate-binding.sh, mirrored in
scripts/collect-review-context.sh) resolve `git merge-base --octopus $target refs/remotes/*`
whenever no explicit base was available, so the range never silently collapsed to tip-only.
But refs/remotes/* refs are ORDINARY LOCAL refs -- any same-UID actor (the exact actor this
binding mechanism defends against) can fabricate one directly with
`git update-ref refs/remotes/origin/decoy <sha>`, no network or push involved. Planting a
decoy ref that is a DESCENDANT of the commit being pushed collapses
merge-base(target, decoy) back to target itself, so base==target, the range-diff becomes an
empty no-op, and the payload silently collapses to tip-only again -- reproducing the exact
RED7-1 defect via ref fabrication instead of "no upstream".

The fix (this change, both scripts/review-gate-binding.sh's `review_binding_safe_base_fallback`
and its byte-for-byte mirror in scripts/collect-review-context.sh): stop trusting any glob
over refs/remotes/* at all. When no authentic pre-push stdin base is available, fall back to
(1) the current branch's own specific `@{u}` upstream if one resolves, else (2) the empty
tree. A fabricated refs/remotes/* ref -- decoy or not -- can no longer influence the result.

These tests reproduce the RED11-1 PoC exactly (commit A "GRANT_ADMIN=true" + reviewed tip B
on a no-upstream branch, decoy ref planted as a descendant of B) against BOTH mirrored
copies, plus guard companions proving the authentic-stdin-remote_sha path and a real `@{u}`
path are both unaffected. Hermetic, subprocess-driven, throwaway-git-repo tests mirroring
tests/test_binding_no_upstream_r4.py / tests/test_reviewer_context_safebase_r5.py.
"""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRE_PUSH = ROOT / "hooks" / "pre-push"
GIT_HARDEN = ROOT / "scripts" / "git-harden.sh"
REVIEW_BINDING = ROOT / "scripts" / "review-gate-binding.sh"
COLLECT = ROOT / "scripts" / "collect-review-context.sh"

EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"


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
    script = (
        f". '{GIT_HARDEN}'; "
        f". '{REVIEW_BINDING}'; "
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


def _safe_base_fallback(project: Path, env: dict[str, str], target: str) -> str:
    script = (
        f". '{GIT_HARDEN}'; "
        f". '{REVIEW_BINDING}'; "
        f"review_binding_safe_base_fallback '{target}'"
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
    return result.stdout.strip()


def _committed_payload(project: Path, env: dict[str, str], *args: str) -> str:
    quoted_args = " ".join(f"'{a}'" for a in args)
    script = (
        f". '{GIT_HARDEN}'; "
        f". '{REVIEW_BINDING}'; "
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


def _run_collector(project: Path, env: dict[str, str], out_dir: Path) -> str:
    run_env = {**env, "OUT_DIR": str(out_dir)}
    subprocess.run(
        ["bash", str(COLLECT)],
        cwd=project,
        env=run_env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return (out_dir / "latest-review-context.md").read_text(encoding="utf-8")


def _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path: Path, env: dict[str, str]) -> tuple[Path, str]:
    """Exact RED11-1 PoC shape: commit A (unreviewed, sneaks in GRANT_ADMIN=true) then
    commit B (trivial, the one that gets reviewed/bound) on a brand-new local branch with no
    upstream configured and nothing ever fetched -- the everyday first-push case."""
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


def _plant_decoy_descendant_ref(project: Path, env: dict[str, str], b_sha: str, ref_name: str = "refs/remotes/origin/decoy") -> str:
    """Fabricate a LOCAL ref, exactly as RED11-1 describes, that is a child (descendant) of
    the commit being pushed -- no network, no push, just plain plumbing access."""
    _git(["checkout", "-q", "-b", "__decoy_branch__", b_sha], project, env)
    (project / "decoy.txt").write_text("innocuous decoy content\n", encoding="utf-8")
    _git(["add", "-A"], project, env)
    d_sha = _git(["commit", "-q", "-m", "D: decoy descendant of B"], project, env)
    d_sha = _git(["rev-parse", "HEAD"], project, env).stdout.strip()
    _git(["update-ref", ref_name, d_sha], project, env)
    _git(["checkout", "-q", "main"], project, env)
    _git(["branch", "-q", "-D", "__decoy_branch__"], project, env)
    return d_sha


def test_decoy_descendant_ref_does_not_collapse_binding_safe_base_fallback(tmp_path: Path) -> None:
    """Core RED11-1 PoC against review_binding_safe_base_fallback itself
    (scripts/review-gate-binding.sh): with a decoy ref planted as a descendant of B and NO
    real upstream, the resolved base must NOT be B (target) -- that would mean the decoy
    collapsed the range to empty again. It must fall through to the empty tree exactly as it
    would with no decoy present at all (the decoy has zero influence on the result)."""
    env = _base_env(tmp_path)
    project, b_sha = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)
    _plant_decoy_descendant_ref(project, env, b_sha)

    base = _safe_base_fallback(project, env, b_sha)

    assert base != b_sha, (
        "review_binding_safe_base_fallback collapsed to the target commit itself -- the "
        f"attacker-fabricated refs/remotes/origin/decoy ref re-collapsed the safe-base range "
        f"(RED11-1 regression). base={base!r} target={b_sha!r}"
    )
    assert base == EMPTY_TREE, (
        "expected the fallback to resolve to the empty tree (no @{u} configured, and the "
        f"decoy ref must be completely ignored), got base={base!r}"
    )


def test_decoy_descendant_ref_does_not_hide_grant_admin_from_binding_payload(tmp_path: Path) -> None:
    """Same PoC, but asserting the actual security property end-to-end: the committed
    payload (what both the reviewer and the push-time hash are computed over) must still
    contain commit A's GRANT_ADMIN content even with the decoy present."""
    env = _base_env(tmp_path)
    project, b_sha = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)
    _plant_decoy_descendant_ref(project, env, b_sha)

    payload = _committed_payload(project, env, b_sha, "")

    assert "GRANT_ADMIN" in payload, (
        "the binding payload only covered the tip commit and missed the earlier unreviewed "
        f"commit once a decoy descendant ref was planted under refs/remotes/* (RED11-1 "
        f"regression). payload={payload!r}"
    )


def test_decoy_descendant_ref_does_not_fool_pre_push_end_to_end(tmp_path: Path) -> None:
    """Full end-to-end RED11-1 PoC through hooks/pre-push's actual new-ref path: a bare
    remote that has never been pushed to (all-zero remote sha on stdin), a decoy descendant
    ref planted before the push runs. The push is accepted (exit 0) only because it is
    genuinely bound to content that includes GRANT_ADMIN -- verified by independently
    recomputing the exact payload pre-push's fallback resolves for this ref update."""
    env = _base_env(tmp_path)
    bare = tmp_path / "origin.git"
    _git(["init", "-q", "--bare", str(bare)], tmp_path, env)

    project, b_sha = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)
    _git(["remote", "add", "origin", str(bare)], project, env)
    _plant_decoy_descendant_ref(project, env, b_sha)

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

    fallback_base = _safe_base_fallback(project, env, b_sha)
    assert fallback_base != b_sha, (
        "pre-push's own fallback resolution collapsed to the target commit itself despite "
        f"the planted decoy descendant ref (RED11-1 regression). base={fallback_base!r}"
    )
    payload = _committed_payload(project, env, b_sha, fallback_base)
    assert "GRANT_ADMIN" in payload, (
        "pre-push accepted the brand-new-ref push, but the underlying payload/hash it "
        "actually bound to was tip-only and never covered the earlier unreviewed commit, "
        f"despite the planted decoy (RED11-1 regression). payload={payload!r}"
    )


def test_decoy_descendant_ref_does_not_collapse_reviewer_context_collector(tmp_path: Path) -> None:
    """Same RED11-1 PoC against the MIRRORED copy in scripts/collect-review-context.sh (via
    its normal sourced-review-gate-binding.sh code path): latest-review-context.md -- the
    literal text a human/AI reviewer reads -- must still contain GRANT_ADMIN once the decoy
    is planted, not just the trivial tip commit."""
    env = _base_env(tmp_path)
    project, b_sha = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)
    _plant_decoy_descendant_ref(project, env, b_sha)

    context = _run_collector(project, env, tmp_path / "ctx")

    assert "GRANT_ADMIN" in context, (
        "the reviewer-facing context collapsed to tip-only once a decoy descendant ref was "
        f"planted under refs/remotes/* (RED11-1 regression, collect-review-context.sh mirror). "
        f"context={context!r}"
    )
    assert "typo fixed" in context
    assert "no upstream known" in context, (
        "expected the collector to label this as the full-history/no-upstream/empty-tree "
        f"range, not a (decoy-influenced) narrower range. context={context!r}"
    )


def test_decoy_descendant_ref_does_not_collapse_reviewer_context_fallback_mirror(tmp_path: Path) -> None:
    """Same RED11-1 PoC, but exercised via the FALLBACK-MIRROR code path (an isolated
    fixture copying ONLY collect-review-context.sh, no sibling review-gate-binding.sh) --
    proves the byte-for-byte mirrored review_binding_safe_base_fallback defined near the top
    of collect-review-context.sh got the identical RED11-1 fix, not just the sourced-helper
    path exercised by the test above."""
    env = _base_env(tmp_path)
    isolated_scripts = tmp_path / "isolated" / "scripts"
    isolated_scripts.mkdir(parents=True)
    isolated_collect = isolated_scripts / "collect-review-context.sh"
    isolated_collect.write_text(COLLECT.read_text(encoding="utf-8"), encoding="utf-8")
    env["AI_AUTO_GIT_HARDEN_SH"] = str(GIT_HARDEN)

    project, b_sha = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)
    _plant_decoy_descendant_ref(project, env, b_sha)

    out_dir = tmp_path / "ctx-isolated"
    run_env = {**env, "OUT_DIR": str(out_dir)}
    subprocess.run(
        ["bash", str(isolated_collect)],
        cwd=project,
        env=run_env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    context = (out_dir / "latest-review-context.md").read_text(encoding="utf-8")

    assert "GRANT_ADMIN" in context, (
        "the fallback-mirror code path (no sibling review-gate-binding.sh reachable) did not "
        f"apply the same RED11-1 fix as the sourced-helper path. context={context!r}"
    )
    assert "no upstream known" in context


def test_authentic_stdin_remote_sha_path_unaffected_by_decoy(tmp_path: Path) -> None:
    """Guard/non-vacuousness companion: when pre-push has an AUTHENTIC remote_sha from the
    real push negotiation (not all-zero), it must never even reach
    review_binding_safe_base_fallback -- a decoy planted alongside a real, already-pushed
    remote tip must have zero effect on an ordinary already-upstreamed push."""
    env = _base_env(tmp_path)
    bare = tmp_path / "origin.git"
    _git(["init", "-q", "--bare", str(bare)], tmp_path, env)

    project = tmp_path / "project"
    _init_repo(project, env)
    _git(["remote", "add", "origin", str(bare)], project, env)
    root_sha = _commit(project, env, "README.md", "hello\n", "init")
    _git(["push", "-q", "-u", "origin", "main"], project, env)

    main_sha = _commit(project, env, "app.py", "print('trivial safe change')\n", "clean reviewed commit")
    _plant_decoy_descendant_ref(project, env, main_sha, ref_name="refs/remotes/origin/decoy")
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


def test_real_upstream_still_works_and_ignores_the_decoy(tmp_path: Path) -> None:
    """Guard/non-vacuousness companion: when a real `@{u}` IS configured (an ordinary
    already-upstreamed branch), review_binding_safe_base_fallback must still resolve via
    that real upstream -- and a decoy ref planted elsewhere under refs/remotes/* (not the
    branch's own configured upstream) must have zero effect on the result."""
    env = _base_env(tmp_path)
    bare = tmp_path / "origin.git"
    _git(["init", "-q", "--bare", str(bare)], tmp_path, env)

    project = tmp_path / "project"
    _init_repo(project, env)
    _git(["remote", "add", "origin", str(bare)], project, env)
    root_sha = _commit(project, env, "README.md", "hello\n", "init")
    _git(["push", "-q", "-u", "origin", "main"], project, env)

    main_sha = _commit(project, env, "app.py", "print('trivial safe change')\n", "clean reviewed commit")
    # Plant a decoy descendant of main_sha under a DIFFERENT remote-tracking name -- it must
    # not be consulted at all now that the fallback only ever looks at the current branch's
    # own specific @{u} (origin/main here, already correctly tracking root_sha).
    _plant_decoy_descendant_ref(project, env, main_sha, ref_name="refs/remotes/origin/decoy")

    base = _safe_base_fallback(project, env, main_sha)

    assert base == root_sha, (
        f"expected the real @{{u}} (origin/main -> {root_sha!r}) to govern the fallback base, "
        f"unaffected by the unrelated decoy ref, got base={base!r}"
    )
