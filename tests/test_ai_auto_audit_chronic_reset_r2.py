"""R2 (RED2/.ops-game2/R1-red2-auditor.md): closing three findings against the out-of-band
auditor (scripts/ai-auto-audit.sh):

1. CHECK4-AUTH-DRIFT chronic-reset erasure (finding #2, HIGH): a same-UID attacker who deletes
   BOTH a reviewer's `.disabled` marker and its `.chronic` side file, then calls the real
   `disable_reviewer()` once more, gets a fresh, validly-signed `chronic_count=1` marker that
   is byte-for-byte indistinguishable from a genuine reviewer's first-ever disable -- a real
   12-run chronic streak vanishes with no HMAC to forge, because CHECK4 as originally shipped
   kept no history and read no delta (review-gate.sh's own RED9-2 comment names exactly this
   as needing "an out-of-band auditor tracking chronic_file history/deltas independently").
   Fix: `disable_reviewer()` (scripts/run-ai-reviews.sh) now appends a durable
   `"event":"reviewer_disable"` line to the SAME append-only `.omx/review-history.log` on every
   disable; `ai-auto-audit.sh`'s CHECK4 flags whenever a `.disabled` marker's current
   `chronic_count` for a reviewer+reason is LOWER than the number of disable-events already
   recorded for that exact reviewer+reason in the durable trail.

2. CHECK2-STALENESS `@{u}` decoy caveat (finding #1, HIGH): CHECK2's PASS message used to state
   "the verdict's range covers HEAD" as unconditional fact, with no signal that the range's base
   resolution rests on `@{u}` (a same-UID-forgeable ordinary local ref -- documented in-line in
   review-gate-binding.sh itself). Fix: the PASS message now always carries an explicit CAVEAT.

3. Swallowed git-exec guard message (finding #6, LOW/MEDIUM): the attr-guard's refusal (rc 3,
   the most security-relevant signal `_review_git_attr_guard` can produce) used to be discarded
   by the auditor's own entry-point `2>/dev/null`, surfacing only as a generic, non-actionable
   "not inside a git repository" / exit 2. Fix: both entry-point `review_git` calls now capture
   stderr and surface a distinct, LOUD "HOSTILE-REPO DETECTED" line (with the guard's own
   message inlined) whenever the failure is actually a guard refusal.

Hermetic, subprocess-driven, throwaway-git-repo tests mirroring tests/test_ai_auto_audit_r5.py's
fixture/helper idiom exactly (same `_base_env`/`_init_repo`/`_commit`/`_record_proceed_binding`/
`_record_history_entry`/`_run_audit` helpers, duplicated here rather than imported, per the
established per-file-hermetic-fixture pattern already used by test_auditor_check3_flag_r7.py).
"""

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "scripts" / "ai-auto-audit.sh"
GIT_HARDEN = ROOT / "scripts" / "git-harden.sh"
REVIEW_GATE_BINDING = ROOT / "scripts" / "review-gate-binding.sh"
RUN_AI_REVIEWS = ROOT / "scripts" / "run-ai-reviews.sh"


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
    # .omx/ (where every artifact this auditor reads lives) must be gitignored, exactly as a
    # real project sets it up -- otherwise it shows up as untracked content and derails
    # review_binding_dirty()'s clean/dirty classification inside review_binding_record.
    (path / ".gitignore").write_text(".omx/\n", encoding="utf-8")


def _commit(path: Path, env: dict[str, str], filename: str, content: str, message: str) -> str:
    (path / filename).write_text(content, encoding="utf-8")
    _git(["add", "-A"], path, env)
    _git(["commit", "-q", "-m", message], path, env)
    return _git(["rev-parse", "HEAD"], path, env).stdout.strip()


def _base_env(tmp_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["AI_AUTO_HOME"] = str(ROOT)
    env["AI_AUTO_GIT_HARDEN_SH"] = str(GIT_HARDEN)
    env["AI_AUTO_REVIEW_GATE_BINDING_SH"] = str(REVIEW_GATE_BINDING)
    env["AI_AUTO_RUN_AI_REVIEWS_SH"] = str(RUN_AI_REVIEWS)
    home = tmp_path / "home"
    home.mkdir(parents=True, exist_ok=True)
    env["HOME"] = str(home)
    env["AI_AUTO_PROVENANCE_KEY_FILE"] = str(tmp_path / "provenance.key")
    return env


def _record_proceed_binding(project: Path, env: dict[str, str]) -> None:
    """Mirror exactly what review-gate.sh does on a human 'proceed' verdict."""
    script = (
        f". '{GIT_HARDEN}'; "
        f". '{REVIEW_GATE_BINDING}'; "
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


def _record_history_entry(project: Path, head_sha: str, verdict: str = "proceed") -> None:
    omx = project / ".omx"
    omx.mkdir(parents=True, exist_ok=True)
    with (omx / "review-history.log").open("a", encoding="utf-8") as fh:
        fh.write(
            '{"ts":"2026-07-08T00:00:00+00:00","head_sha":"%s","verdict":"%s","reason":"","source":"review-gate"}\n'
            % (head_sha, verdict)
        )


def _run_audit(project: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(AUDIT), str(project)],
        env=env,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )


def _call_disable_reviewer(
    project: Path, env: dict[str, str], reviewer: str, reason: str, details: str
) -> None:
    """Call the REAL disable_reviewer() (scripts/run-ai-reviews.sh), extracted verbatim by
    boundary text -- the same technique ai-auto-audit.sh itself uses to reach this function
    (run-ai-reviews.sh is not library-safe to source whole; it runs the review pipeline at the
    bottom of the file with no BASH_SOURCE guard)."""
    script = (
        f"cd '{project}' || exit 1; "
        "REVIEW_STATE_DIR=.omx/reviewer-state; REVIEW_RUN_ID=r2test; "
        "mkdir -p \"${REVIEW_STATE_DIR}\"; "
        f". '{GIT_HARDEN}'; "
        f"source <(sed -n '/# >>> principal-evidence-auth/,/# <<< principal-evidence-auth/p' '{RUN_AI_REVIEWS}'); "
        f"source <(awk '/^reviewer_disabled_file\\(\\)/,/^}}/' '{RUN_AI_REVIEWS}'); "
        f"source <(awk '/^reviewer_marker_canonical\\(\\)/,/^}}/' '{RUN_AI_REVIEWS}'); "
        f"source <(awk '/^reviewer_disabled_authentic\\(\\)/,/^}}/' '{RUN_AI_REVIEWS}'); "
        f"source <(awk '/^reviewer_chronic_file\\(\\)/,/^}}/' '{RUN_AI_REVIEWS}'); "
        f"source <(awk '/^disable_reviewer\\(\\)/,/^}}/' '{RUN_AI_REVIEWS}'); "
        f"disable_reviewer '{reviewer}' '{reason}' '{details}'"
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


# ---------------------------------------------------------------------------------------------
# 1a. Non-vacuousness control: a genuine chronic streak built ONLY through real disable_reviewer()
#     calls (no delete-and-reset in between) must NOT be flagged -- current chronic_count equals
#     the number of durable disable-events for that reviewer+reason, no discontinuity.
# ---------------------------------------------------------------------------------------------
def test_genuine_chronic_streak_not_flagged(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")
    _record_proceed_binding(project, env)
    _record_history_entry(project, head_sha, "proceed")

    for _ in range(3):
        _call_disable_reviewer(project, env, "gemini", "usage_limit", "synthetic transient failure")

    result = _run_audit(project, env)

    assert result.returncode == 0, f"a genuine chronic streak (no reset) was flagged:\n{result.stdout}"
    assert "CHECK4-AUTH-DRIFT" in result.stdout
    assert "chronic-reset erasure" not in result.stdout, (
        f"non-vacuousness control failed -- a genuine 3-in-a-row streak must not read as a "
        f"reset:\n{result.stdout}"
    )


# ---------------------------------------------------------------------------------------------
# 1b. The actual RED2-2 attack: 3 genuine same-reason disables (chronic_count would reach 3),
#     then the attacker deletes BOTH gemini.disabled and gemini.chronic and calls the real
#     disable_reviewer() once more -- chronic_count resets to 1 with a fresh, validly-signed
#     marker. The durable review-history.log trail (4 disable-events total for gemini+
#     usage_limit) still shows the truth -- CHECK4 must flag the discontinuity.
# ---------------------------------------------------------------------------------------------
def test_chronic_reset_erasure_flagged(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")
    _record_proceed_binding(project, env)
    _record_history_entry(project, head_sha, "proceed")

    for _ in range(3):
        _call_disable_reviewer(project, env, "gemini", "usage_limit", "synthetic transient failure")

    # Sanity: at this point (no reset yet) the audit must be clean re: CHECK4.
    pre_reset = _run_audit(project, env)
    assert pre_reset.returncode == 0, f"unexpected flag before the reset attack:\n{pre_reset.stdout}"

    # Attacker: same-UID delete of BOTH state files, then one ordinary, real disable call.
    state_dir = project / ".omx" / "reviewer-state"
    (state_dir / "gemini.disabled").unlink()
    (state_dir / "gemini.chronic").unlink()
    _call_disable_reviewer(project, env, "gemini", "usage_limit", "synthetic transient failure")

    marker_text = (state_dir / "gemini.disabled").read_text(encoding="utf-8")
    assert "chronic_count=1" in marker_text, "reset did not actually collapse chronic_count to 1 (test bug)"

    result = _run_audit(project, env)

    assert result.returncode != 0, f"expected a nonzero exit for a chronic-reset erasure:\n{result.stdout}"
    assert "CHECK4-AUTH-DRIFT" in result.stdout
    assert "FLAG (HIGH)" in result.stdout
    assert "chronic-reset erasure" in result.stdout
    assert "chronic_count=1" in result.stdout


# ---------------------------------------------------------------------------------------------
# 2. CHECK2-STALENESS PASS must always carry the @{u} same-UID-forgeability caveat -- do not
#    overclaim CLEAN. Non-vacuous: a clean fixture (no unreviewed commits) still hits the PASS
#    branch, and that branch's text is what is asserted on.
# ---------------------------------------------------------------------------------------------
def test_check2_pass_carries_at_u_caveat(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")
    _record_proceed_binding(project, env)
    _record_history_entry(project, head_sha, "proceed")

    result = _run_audit(project, env)

    assert result.returncode == 0, f"expected a clean exit 0:\n{result.stdout}"
    check2_lines = [line for line in result.stdout.splitlines() if "CHECK2-STALENESS" in line]
    assert check2_lines, f"CHECK2-STALENESS did not print at all:\n{result.stdout}"
    assert any("PASS" in line for line in check2_lines)
    joined = "\n".join(check2_lines)
    assert "CAVEAT" in joined, f"CHECK2 PASS carries no caveat:\n{joined}"
    assert "@{u}" in joined, f"CHECK2 PASS caveat omits the @{{u}} ref it trusts:\n{joined}"
    assert "same-UID-forgeable" in joined, f"CHECK2 PASS caveat omits the forgeability admission:\n{joined}"


# ---------------------------------------------------------------------------------------------
# 3. A hostile repo (planted .git/info/attributes binding a filter/diff driver) makes the
#    entry-point review_git call fail via the attr-guard's refusal (rc 3) -- this must surface
#    as a distinct, LOUD "HOSTILE-REPO DETECTED" finding carrying the guard's own REFUSING
#    message, not be swallowed into the generic "not inside a git repository" line. Non-vacuous
#    control: the SAME repo before the hostile file is planted gets the ordinary message.
# ---------------------------------------------------------------------------------------------
def test_hostile_repo_guard_refusal_surfaces_loud(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)

    # Control: no commits yet and no hostile attributes -- ordinary "no HEAD commit" message,
    # no HOSTILE-REPO text, still nonzero (proves this test isn't vacuously matching everything).
    control = _run_audit(project, env)
    assert control.returncode != 0
    assert "HOSTILE-REPO DETECTED" not in control.stdout, (
        f"non-vacuousness control failed -- an ordinary empty repo must not read as hostile:\n"
        f"{control.stdout}"
    )

    # Plant the RCE-capable info/attributes binding + its .git/config filter driver (the exact
    # PoC shape from .ops-game2/R1-red2-auditor.md finding #5/#6: git's HIGHEST-precedence
    # attributes file, un-neutralizable by --attr-source/core.attributesFile/GIT_ATTR_NOSYSTEM).
    sentinel = tmp_path / "RED2_R2_PWNED"
    git_dir = project / ".git"
    (git_dir / "info").mkdir(parents=True, exist_ok=True)
    (git_dir / "info" / "attributes").write_text("* filter=evil\n", encoding="utf-8")
    _git(["config", "filter.evil.clean", f"touch {sentinel}"], project, env)

    result = _run_audit(project, env)

    assert result.returncode == 2, f"expected the same exit 2 auditor-could-not-run code:\n{result.stdout}"
    assert "HOSTILE-REPO DETECTED" in result.stdout, (
        f"guard refusal was not surfaced loud:\n{result.stdout}"
    )
    assert "review_git: REFUSING" in result.stdout, (
        f"the guard's own actionable message was not inlined:\n{result.stdout}"
    )
    assert "is not inside a git repository" not in result.stdout, (
        f"guard refusal still fell through to the generic swallowed message:\n{result.stdout}"
    )
    assert not sentinel.exists(), "the planted clean filter actually executed -- RCE, not just a message bug"
