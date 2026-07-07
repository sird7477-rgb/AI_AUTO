"""RED3-1 regression (HIGH): both the reviewer-facing diff (collect-review-context.sh's
post_commit_name_status / write_diff) and the push-time binding hash
(review-gate-binding.sh's review_binding_committed_payload) used to cover ONLY the tip
commit (`git show HEAD` / `HEAD^1..HEAD`), never unioned with the full range of commits
already made but not yet pushed (`@{u}...HEAD`).

PoC (see .ops-game/R1-red3-conc-opcost.md, finding RED3-1): commit A adds
`GRANT_ADMIN=true` to an unrelated file and is never reviewed; commit B is a trivial,
reviewed fixup on top. Because both the collector and the binding hash only ever looked at
B's own diff, A's content was invisible to reviewers AND uncorrelated with the recorded
binding hash -- both commits still ship together on the next `git push`.

The validation harness (templates/domain-packs/odoo/validation-harness/validate-warm.sh /
validate-full.sh) already fixes the identical "commits since upstream" scope gap by unioning
`git diff --name-only HEAD` with `git diff --name-only "$up...HEAD"` (`up` = `@{u}`); this
fix ports that same pattern to the review/binding path.

Hermetic, subprocess-driven, throwaway-git-repo tests mirroring
tests/test_docker_config_guard.py / tests/test_doctor_bootstrap_ip2.py / the existing
tests/test_tree_churn_context.py collect-review-context.sh harness.
"""
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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


def _make_upstream_tracked_repo_with_unreviewed_then_reviewed_commit(
    tmp_path: Path, env: dict[str, str], *, with_collector: bool = False
) -> Path:
    """Commit A (unreviewed, sneaks in GRANT_ADMIN=true) then commit B (trivial, the one
    that gets reviewed/bound), with `main` tracking a real `origin/main` so `@{u}`
    resolves -- exactly the RED3-1 PoC scenario. `with_collector` tracks (and commits) a
    copy of collect-review-context.sh in the BASELINE commit, before A/B, so copying it in
    never itself makes the tree "dirty" (which would derail is_status_clean() and hide the
    very post-commit branch under test)."""
    bare = tmp_path / "origin.git"
    _git(["init", "-q", "--bare", str(bare)], tmp_path, env)

    project = tmp_path / "project"
    project.mkdir(parents=True)
    _git(["init", "-q", "-b", "main"], project, env)
    _git(["config", "user.email", "t@example.invalid"], project, env)
    _git(["config", "user.name", "T"], project, env)
    (project / ".gitignore").write_text(".omx/\n", encoding="utf-8")
    (project / "README.md").write_text("hello\n", encoding="utf-8")
    if with_collector:
        (project / "scripts").mkdir(exist_ok=True)
        shutil.copy(ROOT / "scripts" / "collect-review-context.sh", project / "scripts" / "collect-review-context.sh")
    _git(["add", "-A"], project, env)
    _git(["commit", "-q", "-m", "init"], project, env)
    _git(["remote", "add", "origin", str(bare)], project, env)
    _git(["push", "-q", "-u", "origin", "main"], project, env)

    # Commit A: unreviewed, sneaks a privilege-escalation-shaped line into an unrelated file.
    (project / "g.txt").write_text("some setting\nGRANT_ADMIN=true\n", encoding="utf-8")
    _git(["add", "-A"], project, env)
    _git(["commit", "-q", "-m", "A: sneaky privilege escalation in g.txt"], project, env)

    # Commit B: trivial, the one that actually gets reviewed/bound.
    (project / "f.txt").write_text("typo fixed\n", encoding="utf-8")
    _git(["add", "-A"], project, env)
    _git(["commit", "-q", "-m", "B: trivial typo fix in f.txt"], project, env)

    return project


def test_binding_committed_payload_covers_earlier_unpushed_commit(tmp_path: Path) -> None:
    """review_binding_committed_payload / review_binding_hash must see commit A's content
    (GRANT_ADMIN), not just commit B's tip diff -- otherwise the recorded/checked binding
    hash is blind to it."""
    env = _base_env(tmp_path)
    project = _make_upstream_tracked_repo_with_unreviewed_then_reviewed_commit(tmp_path, env)

    script = (
        f". '{ROOT / 'scripts' / 'git-harden.sh'}'; "
        f". '{ROOT / 'scripts' / 'review-gate-binding.sh'}'; "
        "review_binding_committed_payload"
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

    assert "GRANT_ADMIN" in result.stdout, (
        "the binding payload only covered the tip commit and missed an earlier unreviewed, "
        f"unpushed commit (RED3-1 regression). payload={result.stdout!r}"
    )


def test_reviewer_facing_diff_covers_earlier_unpushed_commit(tmp_path: Path) -> None:
    """collect-review-context.sh's reviewer-facing diff (write_diff's post-commit branch,
    fed by post_commit_name_status) must show commit A's content too, not just commit B's."""
    env = _base_env(tmp_path)
    # Mirror tests/test_tree_churn_context.py's convention: the collector lives (tracked,
    # committed) inside the throwaway repo's own scripts/ dir so its `$0`-relative
    # resolution behaves normally; tests/conftest.py points AI_AUTO_GIT_HARDEN_SH at the
    # real engine's git-harden.sh so `review_git` is available without copying that file too.
    project = _make_upstream_tracked_repo_with_unreviewed_then_reviewed_commit(tmp_path, env, with_collector=True)

    run_env = dict(env)
    run_env["OUT_DIR"] = str(project / ".omx" / "review-context")
    result = subprocess.run(
        ["bash", "scripts/collect-review-context.sh"],
        cwd=project,
        env=run_env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    context = (project / ".omx" / "review-context" / "latest-review-context.md").read_text(encoding="utf-8")

    assert "GRANT_ADMIN" in context, (
        "the reviewer-facing diff only covered the tip commit and missed an earlier "
        f"unreviewed, unpushed commit (RED3-1 regression). collector stderr={result.stderr!r}"
    )
