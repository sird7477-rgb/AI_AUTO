"""Regression tests for RED8-1 and RED8-3 (docs: .ops-game/R3-red8-auditor-observability.md).

RED8-1 (HIGH): scripts/review-gate.sh's R20 purge (search "bind this gate run's verdict to
a fresh, purged results dir") unconditionally deletes every prior review-verdict-*.md under
.omx/review-results/ at the START of every gate run, BEFORE the archive-on-threshold safety
net (archive-omx-artifacts.sh, invoked from review_gate_housekeeping at the END of a run) can
ever act on them -- the purge resets the file count back near zero every run, so the default
120-file threshold is essentially never crossed in ordinary operation. Net effect: no
durable, append-only record of past gate verdicts existed anywhere on disk for a worktree.

The fix (review_gate_record_history(), defined in scripts/review-gate.sh immediately above
review_gate_housekeeping()) appends one JSON-line record per verdict to
".omx/review-history.log" -- a path OUTSIDE REVIEW_RESULTS_DIR, so the purge's
`find "${REVIEW_RESULTS_DIR}" ...` command never touches it -- at every verdict-producing
exit point in the gate. This does not change any verdict decision logic.

RED8-3 (MEDIUM-HIGH): hooks/post-commit's "may have bypassed review-gate" warning (the one
signal for a --no-verify commit) was stderr-only, which vanishes for an unattended terminal
or an automated/background commit. The fix appends the same event to the same durable log
(source: post-commit) alongside the existing stderr warning.

Both fixes are same-UID-writable, exactly like every other artifact in this system -- see
the HONEST LIMIT comments at both fix sites. These tests establish durability against
non-adversarial loss (the purge, a lost terminal), not forgery-resistance against a same-UID
attacker.

Non-vacuousness ("revert -> FAIL"):
  - Structurally: test_history_function_survives_purge_of_review_results_dir and
    test_history_function_is_defined_in_review_gate extract review_gate_record_history()
    BY NAME out of the live scripts/review-gate.sh source (same _extract_bash_functions
    technique as tests/test_chronic_alarm_authentic_r3.py). Reverting the RED8-1 fix removes
    that function entirely, so extraction raises "function(s) not found" -- a hard FAIL, not
    a silent skip.
  - test_post_commit_bypass_is_logged_durably greps hooks/post-commit's actual source for the
    history-append line before running it, so a revert that deletes the append (but leaves
    the stderr-only warning intact) fails the grep assertion AND the file-appeared assertion.
  - Empirically confirmed by temporarily swapping in the pre-fix (`git show HEAD:...`)
    versions of both files and re-running this file: all four tests below failed as expected
    (see task report for the transcript); the pre-fix stdout/stderr warnings are unchanged
    (still fire), only the durable-log assertions fail. Not embedded as a live test here
    because pinning to a specific git revision's content would make it fail again once the
    fix lands, mirroring test_chronic_alarm_authentic_r3.py's stated rationale.
"""

import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEW_GATE = ROOT / "scripts" / "review-gate.sh"
POST_COMMIT = ROOT / "hooks" / "post-commit"

assert REVIEW_GATE.is_file(), REVIEW_GATE
assert POST_COMMIT.is_file(), POST_COMMIT


def _run(args, *, cwd=None, env=None, input_text=None):
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        args,
        cwd=cwd,
        env=merged_env,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=60,
    )


def _extract_bash_functions(script_path: Path, names: set) -> str:
    """Pull top-level `name() { ... }` bodies verbatim out of a bash script. Identical
    technique to tests/test_chronic_alarm_authentic_r3.py / test_reviewer_restore_ip3.py: a
    function header alone on its own line (`name() {`) and a lone closing `}` at column 0
    terminate it."""
    out = []
    capturing = False
    found = set()
    for line in script_path.read_text().splitlines():
        if not capturing:
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{", line)
            if m and m.group(1) in names:
                capturing = True
                found.add(m.group(1))
                out.append(line)
            continue
        out.append(line)
        if line == "}":
            capturing = False
    missing = names - found
    assert not missing, f"function(s) not found in {script_path}: {missing}"
    return "\n".join(out) + "\n"


def _extract_purge_snippet() -> str:
    """Pull the ACTUAL R20 purge block verbatim out of review-gate.sh (not a hand-copied
    guess), so this test tracks the real purge command and cannot silently drift from it."""
    text = REVIEW_GATE.read_text()
    start_marker = 'REVIEW_RESULTS_DIR="${OUT_DIR:-.omx/review-results}"'
    end_marker = "\nREVIEW_RUN_ID="
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    snippet = text[start:end]
    assert 'find "${REVIEW_RESULTS_DIR}"' in snippet, snippet
    assert "-exec rm -rf {} +" in snippet, snippet
    return snippet + "\n"


def _run_bash_harness(cwd: Path, body: str, *, functions_src: str = "") -> subprocess.CompletedProcess:
    script = cwd / "harness.sh"
    script.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + functions_src + "\n" + body + "\n")
    script.chmod(0o755)
    return _run(["bash", str(script)], cwd=cwd)


def _init_repo(path: Path) -> dict:
    path.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    _run(["git", "init", "-q", "-b", "main"], cwd=path, env=env)
    _run(["git", "config", "user.email", "t@example.invalid"], cwd=path, env=env)
    _run(["git", "config", "user.name", "T"], cwd=path, env=env)
    return env


def _commit(path: Path, env: dict, filename: str, content: str, message: str) -> str:
    (path / filename).write_text(content)
    r = _run(["git", "add", "-A"], cwd=path, env=env)
    assert r.returncode == 0, r.stderr
    r = _run(["git", "commit", "-q", "-m", message], cwd=path, env=env)
    assert r.returncode == 0, r.stderr
    r = _run(["git", "rev-parse", "HEAD"], cwd=path, env=env)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def _read_history_lines(repo: Path) -> list:
    history = repo / ".omx" / "review-history.log"
    assert history.is_file(), f"{history} was not created"
    lines = [ln for ln in history.read_text().splitlines() if ln.strip()]
    return [json.loads(ln) for ln in lines]


# ---------------------------------------------------------------------------
# RED8-1: review_gate_record_history() writes a durable record, and that record
# survives the exact purge command review-gate.sh runs at the start of every run.
# ---------------------------------------------------------------------------

def test_history_function_is_defined_in_review_gate():
    """Guard rail / non-vacuousness anchor: the fix function must exist under this exact
    name. Pre-fix, this raises AssertionError (function not found) -- a hard FAIL."""
    src = _extract_bash_functions(REVIEW_GATE, {"review_gate_record_history"})
    assert "review-history.log" in src
    assert "head_sha" in src


def test_history_record_written_with_required_fields(tmp_path):
    """A single call records timestamp, HEAD sha, and verdict/reason -- the minimum fields
    the task requires for a durable verdict record."""
    repo = tmp_path / "repo"
    env = _init_repo(repo)
    head_sha = _commit(repo, env, "f.txt", "x\n", "init")

    functions_src = _extract_bash_functions(REVIEW_GATE, {"review_gate_record_history"})
    result = _run_bash_harness(
        repo,
        'review_gate_record_history "blocked" "verify_failed"\n',
        functions_src=functions_src,
    )
    assert result.returncode == 0, result.stderr

    records = _read_history_lines(repo)
    assert len(records) == 1, records
    rec = records[0]
    assert rec["head_sha"] == head_sha, rec
    assert rec["verdict"] == "blocked", rec
    assert rec["reason"] == "verify_failed", rec
    assert rec["source"] == "review-gate", rec
    assert "ts" in rec and rec["ts"], rec


def test_history_survives_the_real_purge_that_wipes_review_results(tmp_path):
    """The RED8-1 PoC, closed: append a verdict record, simulate a leftover
    review-results/ from a prior run, then run the ACTUAL purge command extracted from
    review-gate.sh. The purge must still remove the leftover results-dir file (its
    security behavior is unchanged) but the durable history log -- living outside
    REVIEW_RESULTS_DIR -- must survive intact.

    Revert-proof: pre-fix, review_gate_record_history does not exist, so the harness
    build step fails immediately (function not found) rather than reaching the
    (still-passing) purge assertion alone -- this test cannot pass vacuously against
    the pre-fix source.
    """
    repo = tmp_path / "repo"
    env = _init_repo(repo)
    _commit(repo, env, "f.txt", "x\n", "init")

    functions_src = _extract_bash_functions(REVIEW_GATE, {"review_gate_record_history"})
    purge_snippet = _extract_purge_snippet()

    # 1) Record a verdict for "this run" (mirrors a prior gate invocation that finished).
    result = _run_bash_harness(
        repo,
        'review_gate_record_history "proceed" "full_review"\n',
        functions_src=functions_src,
    )
    assert result.returncode == 0, result.stderr
    before = _read_history_lines(repo)
    assert len(before) == 1, before

    # 2) Simulate the leftover review-results/ a prior run left behind (the exact class of
    # file the purge exists to remove every run).
    results_dir = repo / ".omx" / "review-results"
    results_dir.mkdir(parents=True, exist_ok=True)
    leftover = results_dir / "review-verdict-19990101T000000.md"
    leftover.write_text("- decision: proceed\n")
    archive_dir = results_dir / "archive"
    archive_dir.mkdir()
    archive_marker = archive_dir / "keepme.md"
    archive_marker.write_text("archived\n")

    # 3) Run the REAL purge command (verbatim from review-gate.sh) with the same
    # REVIEW_RESULTS_DIR default the gate uses.
    result = _run_bash_harness(repo, purge_snippet)
    assert result.returncode == 0, result.stderr

    # Purge behavior itself is unchanged: the non-archive leftover is gone, archive/ is kept.
    assert not leftover.exists(), "purge did not remove the leftover review-results file"
    assert archive_marker.exists(), "purge incorrectly touched archive/"

    # The durable history record, living OUTSIDE review-results/, survives the purge.
    after = _read_history_lines(repo)
    assert after == before, (
        f"durable history log did not survive the review-results/ purge: "
        f"before={before} after={after}"
    )


# ---------------------------------------------------------------------------
# RED8-3: hooks/post-commit durably logs a bypass event, not just to stderr.
# ---------------------------------------------------------------------------

def test_post_commit_source_appends_history_on_bypass_warning():
    """Anchor check: the append must be sourced from the SAME branch that prints the
    stderr bypass warning (not a separate, potentially-dead code path), and the record's
    reason text must literally be "bypass: no binding verdict" per the task spec."""
    src = POST_COMMIT.read_text()
    assert "may have bypassed review-gate" in src
    warn_idx = src.index("may have bypassed review-gate")
    append_idx = src.index("bypass: no binding verdict")
    assert append_idx > warn_idx, "durable append is not inside the bypass-warning branch"
    assert ".omx/review-history.log" in src or "review-history.log" in src


def test_post_commit_bypass_is_logged_durably(tmp_path):
    """A commit with no recent review-gate proceed verdict on disk (the --no-verify /
    unreviewed-bypass scenario) must leave a durable trace, not just a stderr line that
    disappears with the terminal.

    Revert-proof: pre-fix, hooks/post-commit prints the WARNING to stderr (still
    asserted below, unchanged) but writes nothing to disk -- .omx/review-history.log is
    never created, so the `_read_history_lines` call fails with "was not created".
    """
    repo = tmp_path / "repo"
    env = _init_repo(repo)
    env["AI_AUTO_HOME"] = str(ROOT)
    home = tmp_path / "home"
    home.mkdir()
    env["HOME"] = str(home)
    head_sha = _commit(repo, env, "f.txt", "x\n", "init commit, no gate run")

    result = _run(["bash", str(POST_COMMIT)], cwd=repo, env=env)
    assert result.returncode == 0, result.stderr
    assert "may have bypassed review-gate" in result.stderr, result.stderr

    records = _read_history_lines(repo)
    bypass_records = [r for r in records if r.get("source") == "post-commit"]
    assert len(bypass_records) == 1, records
    rec = bypass_records[0]
    assert rec["head_sha"] == head_sha, rec
    assert rec["verdict"] == "unreviewed", rec
    assert rec["reason"] == "bypass: no binding verdict", rec


def test_post_commit_does_not_log_bypass_when_a_recent_proceed_verdict_exists(tmp_path):
    """Guard rail / non-vacuousness: a genuine recent proceed verdict must NOT be flagged
    as a bypass -- the fix must not spam the durable log on ordinary reviewed commits."""
    repo = tmp_path / "repo"
    env = _init_repo(repo)
    env["AI_AUTO_HOME"] = str(ROOT)
    home = tmp_path / "home"
    home.mkdir()
    env["HOME"] = str(home)
    _commit(repo, env, "f.txt", "x\n", "init commit, reviewed")

    results_dir = repo / ".omx" / "review-results"
    results_dir.mkdir(parents=True)
    (results_dir / "review-verdict-20990101T000000.md").write_text(
        "# AI Review Verdict\n\n## Short Summary\n\n- decision: proceed\n"
    )

    result = _run(["bash", str(POST_COMMIT)], cwd=repo, env=env)
    assert result.returncode == 0, result.stderr
    assert "may have bypassed review-gate" not in result.stderr, result.stderr

    history = repo / ".omx" / "review-history.log"
    assert not history.exists(), "a genuine proceed verdict must not produce a bypass record"
