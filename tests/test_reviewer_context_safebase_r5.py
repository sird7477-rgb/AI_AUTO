"""RED10-1 (CRITICAL, .ops-game/R4-red10-gauntlet.md): the R4 fix (RED7-1) made the PUSH-TIME
BINDING HASH (scripts/review-gate-binding.sh's review_binding_committed_payload, via
review_binding_safe_base_fallback) cover the correct commit range even with no upstream
configured (octopus merge-base with every refs/remotes/* ref, else the empty tree -- never
tip-only). It did NOT port that same base resolution into
scripts/collect-review-context.sh's post_commit_upstream_ref (and the
name-status/stat/diff writers built on it) -- the function that produces
`.omx/review-context/latest-review-context.md`, the literal text a human/AI reviewer reads
(scripts/make-review-prompts.sh's sole default CONTEXT_FILE).

Net effect before this fix: on a fresh branch with no upstream, an unreviewed commit A
("add GRANT_ADMIN=true") followed by a trivial reviewed commit B was fully covered by the
push-time binding hash (correct, post-RED7-1) but INVISIBLE in latest-review-context.md
(still tip-only, post-RED3-1/pre-RED10-1) -- a reviewer approves B thinking that's the whole
change, and the resulting `proceed` verdict authorizes A too. The reviewer-facing diff and
the binding hash must always cover the identical commit range.

The fix (scripts/collect-review-context.sh): post_commit_upstream_ref now resolves
`review_binding_safe_base_fallback` (mirroring/reusing review-gate-binding.sh's helper, see
the sourcing block + fallback-mirror block near the top of collect-review-context.sh) instead
of returning empty when `@{u}` is unset, and post_commit_name_status / write_diff_stat /
write_diff (via the new post_commit_range_diff helper) apply the identical
two-dot/empty-tree special case review_binding_committed_payload already does.

Hermetic, subprocess-driven, throwaway-git-repo tests mirroring tests/test_binding_no_upstream_r4.py
(the sibling test that covers the binding-hash side of this exact scenario).
"""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLLECT = ROOT / "scripts" / "collect-review-context.sh"
GIT_HARDEN = ROOT / "scripts" / "git-harden.sh"
REVIEW_BINDING = ROOT / "scripts" / "review-gate-binding.sh"


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


def _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path: Path, env: dict[str, str]) -> Path:
    """Same PoC shape as test_binding_no_upstream_r4.py: brand-new local branch, NO
    `git push -u` ever run, so `@{u}` is unset and (nothing ever pushed/fetched) no
    refs/remotes/* exist either. Commit A sneaks in a privilege-escalation marker; commit B
    is the trivial tip that actually gets reviewed."""
    project = tmp_path / "project"
    _init_repo(project, env)
    _commit(project, env, "README.md", "hello\n", "init")

    (project / "g.txt").write_text("some setting\nGRANT_ADMIN=true\n", encoding="utf-8")
    _git(["add", "-A"], project, env)
    _git(["commit", "-q", "-m", "A: sneaky privilege escalation in g.txt"], project, env)

    (project / "f.txt").write_text("typo fixed\n", encoding="utf-8")
    _git(["add", "-A"], project, env)
    _git(["commit", "-q", "-m", "B: trivial typo fix in f.txt"], project, env)

    return project


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


def _binding_committed_payload(project: Path, env: dict[str, str], *args: str) -> str:
    """Independently recompute the push-time binding payload (the same call
    tests/test_binding_no_upstream_r4.py exercises), so we can assert the reviewer-facing
    context and the binding hash's range are the SAME commit range, not just that both happen
    to mention GRANT_ADMIN somewhere."""
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


def test_reviewer_context_covers_earlier_unreviewed_commit_with_no_upstream_at_all(tmp_path: Path) -> None:
    """The core RED10-1 regression: with NO upstream configured, latest-review-context.md
    (the actual reviewer-facing text) must contain commit A's content, not just tip commit
    B's. Pre-fix this failed (payload only ever covered the tip commit's `git show`)."""
    env = _base_env(tmp_path)
    project = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)

    context = _run_collector(project, env, tmp_path / "ctx")

    assert "GRANT_ADMIN" in context, (
        "the reviewer-facing context only covered the tip commit and missed an earlier "
        "unreviewed, unpushed commit when no upstream was configured at all (RED10-1 "
        f"regression). context={context!r}"
    )
    # Non-vacuous companion: the trivial tip commit is still there too (this is a union, not
    # a replacement of the existing tip-diff behavior).
    assert "typo fixed" in context


def test_reviewer_context_range_matches_binding_hash_range_with_no_upstream(tmp_path: Path) -> None:
    """The actual asymmetry RED10-1 named: the reviewer diff and the push-time binding hash
    must cover the SAME range. Independently resolve the binding side's fallback base and
    recompute its payload; every line of its range-diff section must also appear in the
    collector's own range-diff section (both are diffing the same base...HEAD)."""
    env = _base_env(tmp_path)
    project = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)

    context = _run_collector(project, env, tmp_path / "ctx")
    binding_payload = _binding_committed_payload(project, env)

    # The binding side's range-diff section (marked \037range-diff\037) is the ground truth
    # for what range the push-time hash actually covers.
    assert "\037range-diff\037" in binding_payload
    binding_range_diff = binding_payload.split("\037range-diff\037\n", 1)[1]

    # Every changed file the binding hash's range-diff touched must also show up in the
    # collector's reviewer-facing range-diff section, i.e. the same base...HEAD range.
    for marker in ("+GRANT_ADMIN=true", "diff --git a/g.txt", "diff --git a/f.txt"):
        assert marker in binding_range_diff, f"test fixture assumption failed: {marker!r} not in binding payload"
        assert marker in context, (
            f"reviewer context is missing {marker!r}, which the binding hash's range-diff "
            "covers -- the reviewer-facing range and the binding range have diverged again "
            f"(RED10-1). context={context!r}"
        )

    # And the collector must explicitly label this as a full-history/no-upstream range (not
    # silently a same-looking-but-narrower range) -- this is the empty-tree fallback path.
    assert "no upstream known" in context


def test_reviewer_context_unaffected_on_an_already_upstreamed_branch(tmp_path: Path) -> None:
    """Guard/non-vacuousness companion: an ordinary already-upstreamed branch (a real
    `@{u}`) must keep using that upstream ref directly -- the RED10-1 fix only changes the
    no-`@{u}` fallback path, it must not touch the already-correct explicit-upstream path."""
    env = _base_env(tmp_path)
    bare = tmp_path / "origin.git"
    _git(["init", "-q", "--bare", str(bare)], tmp_path, env)

    project = tmp_path / "project"
    _init_repo(project, env)
    _git(["remote", "add", "origin", str(bare)], project, env)
    _commit(project, env, "README.md", "hello\n", "init")
    _git(["push", "-q", "-u", "origin", "main"], project, env)

    _commit(project, env, "app.py", "print('trivial safe change')\n", "clean reviewed commit")

    context = _run_collector(project, env, tmp_path / "ctx")

    assert "origin/main...HEAD" in context, (
        f"an already-upstreamed branch should still range-diff against its real @{{u}} "
        f"(origin/main...HEAD), not fall through to the no-upstream fallback. context={context!r}"
    )
    assert "no upstream known" not in context
    assert "print('trivial safe change')" in context


def test_reviewer_context_matches_binding_hash_range_for_an_isolated_fixture_copy(tmp_path: Path) -> None:
    """Same RED10-1 scenario as above, but exercised via the FALLBACK-MIRROR code path: a
    fixture that copies ONLY collect-review-context.sh (no sibling review-gate-binding.sh),
    matching the pattern several pre-existing tests in this suite already use (e.g.
    tests/test_tree_churn_context.py). This proves the mirrored fallback functions
    (review_binding_empty_tree / review_binding_remote_tracking_refs /
    review_binding_safe_base_fallback, defined near the top of collect-review-context.sh)
    produce the identical fix, not just the sourced-helper code path."""
    env = _base_env(tmp_path)
    isolated_scripts = tmp_path / "isolated" / "scripts"
    isolated_scripts.mkdir(parents=True)
    (isolated_scripts / "collect-review-context.sh").write_text(
        COLLECT.read_text(encoding="utf-8"), encoding="utf-8"
    )
    isolated_collect = isolated_scripts / "collect-review-context.sh"
    # AI_AUTO_GIT_HARDEN_SH is how this suite's tests/conftest.py already points isolated
    # copies at the real hardened-git helper (see its docstring); no equivalent override is
    # introduced for review-gate-binding.sh here on purpose -- the point of this test is that
    # NONE is needed, because the fallback mirror activates automatically when the sibling
    # file is simply absent.
    env["AI_AUTO_GIT_HARDEN_SH"] = str(GIT_HARDEN)

    project = _make_no_upstream_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)
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
        f"apply the same RED10-1 fix as the sourced-helper path. context={context!r}"
    )
    assert "no upstream known" in context
