"""Regression tests for RED5-1 (docs: .ops-game/R2-red5-reattack.md).

RED5-1 (R2 red-team, HIGH): scripts/review-gate.sh's warn_stale_disabled_reviewers() --
the "chronic-redisable LOUD warning" that round-1 shipped for D6/AC3-5 -- was defeatable
two independent ways, both PoC'd against the literal committed functions:

  Bypass A: the alarm threshold (AI_AUTO_CHRONIC_REDISABLE_THRESHOLD) was a bare env var
  with no floor/ceiling. Any caller sharing the gate's invocation environment could set it
  to e.g. 999999 and silence the alarm for good, regardless of the real chronic_count, with
  zero trace.

  Bypass B: the function read chronic_count/disable_class/etc straight off the
  `.disabled` marker with NO marker_hmac verification, while the sibling skip-decision
  consumer (run-ai-reviews.sh's reviewer_disabled_authentic()) correctly verifies the SAME
  marker's HMAC before trusting it. An attacker who can write the gitignored
  REVIEW_STATE_DIR could sign a genuine marker, then tamper ONLY chronic_count downward
  (breaking the HMAC): the skip-decision consumer rejects the tamper, but the warning
  consumer silently trusted the forged low count.

This file exercises the REAL review-gate.sh functions via subprocess, following the same
extraction technique as tests/test_reviewer_restore_ip3.py (review-gate.sh is not
library-safe to `source` directly, so the specific functions under test are pulled out of
the live script file verbatim by function-boundary text and sourced into a small,
self-contained bash harness -- editing the source functions changes what these tests
execute, with no copy to fall out of sync).

Non-vacuousness ("revert -> FAIL") is established two ways, both recorded in this file's
docstrings/comments per test:
  - Structurally: each assertion targets output/behavior that the PRE-FIX code cannot
    produce (the pre-fix code has no authenticity check and no threshold clamp at all), so
    reverting scripts/review-gate.sh to its pre-fix state makes these assertions fail.
  - Empirically: this was independently confirmed by running the same test bodies against
    `git show HEAD:scripts/review-gate.sh` (the pre-fix committed version) extracted into an
    identical harness -- see the task report for the transcript. That invocation is not
    embedded here as a live test because pinning a test's outcome to a specific git
    revision's content would make it fail again the moment the fix is committed.
"""

import hashlib
import hmac
import os
import re
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEW_GATE = ROOT / "scripts" / "review-gate.sh"
GIT_HARDEN = ROOT / "scripts" / "git-harden.sh"

assert REVIEW_GATE.is_file(), REVIEW_GATE
assert GIT_HARDEN.is_file(), GIT_HARDEN


def _run(args, *, env=None, cwd=None):
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        args,
        cwd=cwd,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=60,
    )


def _extract_bash_functions(script_path: Path, names: set) -> str:
    """Pull top-level `name() { ... }` bodies verbatim out of a bash script.

    Identical technique to tests/test_reviewer_restore_ip3.py's helper of the same name:
    a function header alone on its own line (`name() {`) and a lone closing `}` at column 0
    terminate it.
    """
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


_GATE_FUNCS = {
    "warn_stale_disabled_reviewers",
    "review_provenance_hmac",
    "review_provenance_key_file",
    "review_provenance_key_in_tree",
    "review_provenance_abs_path",
}


def _gate_functions_src() -> str:
    return _extract_bash_functions(REVIEW_GATE, _GATE_FUNCS)


def _run_bash_harness(cwd: Path, preamble: str, functions_src: str, body: str) -> str:
    """Assemble+run a bash script: preamble, extracted real functions, then the test body."""
    script = cwd / "harness.sh"
    script.write_text(
        "#!/usr/bin/env bash\nset -euo pipefail\n"
        + preamble
        + "\n"
        + functions_src
        + "\n"
        + body
        + "\n"
    )
    script.chmod(0o755)
    result = _run(["bash", str(script)], cwd=cwd)
    assert result.returncode == 0, (
        f"harness script failed (exit {result.returncode}):\n{result.stdout}"
    )
    return result.stdout


def _make_workspace(tmp_path: Path) -> Path:
    """A throwaway git repo (NOT this project's own worktree) so review_provenance_key_in_tree's
    `git rev-parse --show-toplevel` (and this fix's own toplevel lookup) has something to
    resolve. Mirrors verify-machinery.sh's own stale-disabled-reviewer fixture, which does the
    same `git init` inside a mktemp dir for the identical reason."""
    ws = tmp_path / "workspace"
    ws.mkdir()
    r = _run(["git", "-c", "init.defaultBranch=main", "init", "-q", str(ws)])
    assert r.returncode == 0, r.stdout
    return ws


def _make_out_of_tree_key(tmp_path: Path) -> Path:
    """An out-of-tree HMAC key -- deliberately a sibling of (not inside) the workspace git repo,
    so review_provenance_key_in_tree does not refuse it."""
    key_dir = tmp_path / "outside-key"
    key_dir.mkdir()
    key_file = key_dir / "provenance.key"
    key_file.write_bytes(os.urandom(32))
    key_file.chmod(0o600)
    return key_file


_MARKER_FIELDS_IN_ORDER = (
    "reviewer",
    "disabled_at",
    "reason",
    "details",
    "disable_class",
    "source_run_id",
    "chronic_count",
)


def _write_marker(path: Path, *, reviewer, disabled_at, reason, details, disable_class,
                   source_run_id, chronic_count, next_action, reset_hint):
    fields = {
        "reviewer": reviewer,
        "disabled_at": disabled_at,
        "reason": reason,
        "details": details,
        "disable_class": disable_class,
        "source_run_id": source_run_id,
        "chronic_count": str(chronic_count),
    }
    lines = [f"{k}={fields[k]}" for k in _MARKER_FIELDS_IN_ORDER]
    lines.append(f"next_action={next_action}")
    lines.append(f"reset_hint={reset_hint}")
    path.write_text("\n".join(lines) + "\n")


def _canonical_bytes(reviewer: str, workspace_top: str, marker_path: Path) -> bytes:
    """Byte-identical reconstruction of reviewer_marker_canonical() (run-ai-reviews.sh /
    the mirrored inline check in review-gate.sh's warn_stale_disabled_reviewers): a header
    naming the reviewer+workspace, then every canonical-field line PRESENT IN THE MARKER FILE,
    in the marker file's own line order (grep -E preserves file order, not pattern order)."""
    header = f"marker_type=reviewer_disabled\nreviewer={reviewer}\nworkspace={workspace_top}\n"
    canonical_prefixes = tuple(f"{f}=" for f in _MARKER_FIELDS_IN_ORDER)
    kept = [
        line for line in marker_path.read_text().splitlines()
        if line.startswith(canonical_prefixes)
    ]
    body = "\n".join(kept)
    if kept:
        body += "\n"
    return (header + body).encode()


def _sign_marker(marker_path: Path, *, reviewer: str, workspace_top: str, key_file: Path) -> None:
    """Independently (pure-Python hmac, NOT shelling out to review_provenance_hmac) compute the
    SAME out-of-tree-keyed HMAC the fix recomputes, and append it as marker_hmac= -- exactly
    what a genuine disable_reviewer() run would have written. Using an independent
    implementation (rather than calling the extracted bash function to sign) means this test
    does not just check that the fix's own signer agrees with itself; it checks the fix's
    verification against a HMAC computed a different way, matching the real
    principal_evidence_hmac / review_provenance_hmac algorithm: HMAC-SHA256(key_bytes,
    canonical_bytes).hexdigest()."""
    key_bytes = key_file.read_bytes()
    digest = hmac.new(key_bytes, _canonical_bytes(reviewer, workspace_top, marker_path), hashlib.sha256).hexdigest()
    with marker_path.open("a") as fh:
        fh.write(f"marker_hmac={digest}\n")


def _git_toplevel(ws: Path) -> str:
    r = _run(["git", "rev-parse", "--show-toplevel"], cwd=ws)
    assert r.returncode == 0, r.stdout
    return r.stdout.strip()


_PREAMBLE_TEMPLATE = (
    'REVIEW_STATE_DIR="{state_dir}"\n'
    'AI_AUTO_PROVENANCE_KEY_FILE="{key_file}"\n'
    'source "{git_harden}"\n'
)


# ---------------------------------------------------------------------------
# (a) Bypass B: a marker signed genuinely, then tampered ONLY on chronic_count (breaking the
# HMAC), must NOT be trusted to suppress the loud alarm.
# ---------------------------------------------------------------------------

def test_tampered_chronic_count_does_not_suppress_loud_warning(tmp_path):
    """RED5-1 Bypass B, PoC-mirrored: sign a genuine transient-disable marker with
    chronic_count=5 (>= the default threshold of 3, so it is legitimately alarm-worthy), then
    tamper ONLY the on-disk chronic_count down to 1 (leaving the now-stale marker_hmac in
    place, exactly as the red-team PoC describes -- "edited only chronic_count down to 1,
    breaking the HMAC").

    Revert-proof: the pre-fix warn_stale_disabled_reviewers() has no marker_hmac check
    whatsoever -- it reads chronic_count straight off the file. Against that code, CASE-TAMPER
    below reads chronic_count=1 < threshold(3) and prints NOTHING (silently suppressed, the
    exact bypass). This test's fixed code must instead flag it as authenticity-failed and
    treat it as alarm-worthy regardless of the claimed (tampered) count.
    """
    ws = _make_workspace(tmp_path)
    key_file = _make_out_of_tree_key(tmp_path)
    top = _git_toplevel(ws)
    state_dir = ws / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True)

    marker = state_dir / "gemini.disabled"
    fresh_stamp = _run(["date", "-Iseconds"]).stdout.strip()
    _write_marker(
        marker,
        reviewer="gemini",
        disabled_at=fresh_stamp,
        reason="prompt_size_limit",
        details="class=prompt_size_limit; tail=large_prompt_prompt_file_fallback_failed",
        disable_class="transient",
        source_run_id="test",
        chronic_count=5,
        next_action="auto_recover_after_cooldown_300s",
        reset_hint="RESET_DISABLED_AI_REVIEWERS=gemini ./scripts/review-gate.sh",
    )
    _sign_marker(marker, reviewer="gemini", workspace_top=top, key_file=key_file)

    preamble = _PREAMBLE_TEMPLATE.format(
        state_dir=state_dir, key_file=key_file, git_harden=GIT_HARDEN
    )

    # Sanity: the genuinely-signed, untampered marker (chronic_count=5 >= 3) must alarm
    # normally -- proves the signing/verification setup itself is valid before we tamper it.
    stdout_sane = _run_bash_harness(
        ws,
        preamble=preamble,
        functions_src=_gate_functions_src(),
        body='echo "===SANE==="\nwarn_stale_disabled_reviewers\necho "===SANE-END==="\n',
    )
    sane = stdout_sane.split("===SANE===\n", 1)[1].split("===SANE-END===")[0]
    assert "CHRONICALLY RE-DISABLED" in sane, stdout_sane
    assert "AUTHENTICITY FAILED" not in sane, stdout_sane

    # Tamper: rewrite chronic_count on disk WITHOUT re-signing -- the marker_hmac line is now
    # stale relative to the (tampered) canonical fields.
    tampered_lines = []
    for line in marker.read_text().splitlines():
        if line.startswith("chronic_count="):
            tampered_lines.append("chronic_count=1")
        else:
            tampered_lines.append(line)
    marker.write_text("\n".join(tampered_lines) + "\n")

    stdout_tamper = _run_bash_harness(
        ws,
        preamble=preamble,
        functions_src=_gate_functions_src(),
        body='echo "===TAMPER==="\nwarn_stale_disabled_reviewers\necho "===TAMPER-END==="\n',
    )
    tamper = stdout_tamper.split("===TAMPER===\n", 1)[1].split("===TAMPER-END===")[0]

    # The bypass being closed: a bare, unauthenticated trust of chronic_count=1 would print
    # NOTHING here (< threshold 3). The fix must not be silent, and must not report this as an
    # ordinary low-count case.
    assert tamper.strip() != "", "tampered marker was silently trusted (RED5-1 Bypass B reopened)"
    assert "AUTHENTICITY FAILED" in tamper, tamper
    assert "gemini" in tamper, tamper


def test_untampered_marker_with_hmac_present_stays_authentic(tmp_path):
    """Guard rail: a genuinely-signed marker with a LOW chronic_count (below threshold) that is
    NOT tampered must still stay fully silent -- the new authenticity check must not itself
    become a source of false alarms on ordinary genuine markers."""
    ws = _make_workspace(tmp_path)
    key_file = _make_out_of_tree_key(tmp_path)
    top = _git_toplevel(ws)
    state_dir = ws / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True)

    marker = state_dir / "gemini.disabled"
    fresh_stamp = _run(["date", "-Iseconds"]).stdout.strip()
    _write_marker(
        marker,
        reviewer="gemini",
        disabled_at=fresh_stamp,
        reason="prompt_size_limit",
        details="class=prompt_size_limit; tail=large_prompt_prompt_file_fallback_failed",
        disable_class="transient",
        source_run_id="test",
        chronic_count=1,
        next_action="auto_recover_after_cooldown_300s",
        reset_hint="RESET_DISABLED_AI_REVIEWERS=gemini ./scripts/review-gate.sh",
    )
    _sign_marker(marker, reviewer="gemini", workspace_top=top, key_file=key_file)

    stdout = _run_bash_harness(
        ws,
        preamble=_PREAMBLE_TEMPLATE.format(state_dir=state_dir, key_file=key_file, git_harden=GIT_HARDEN),
        functions_src=_gate_functions_src(),
        body='echo "===CASE==="\nwarn_stale_disabled_reviewers\necho "===CASE-END==="\n',
    )
    case = stdout.split("===CASE===\n", 1)[1].split("===CASE-END===")[0]
    assert case.strip() == "", stdout


# ---------------------------------------------------------------------------
# (b) Bypass A: an over-large AI_AUTO_CHRONIC_REDISABLE_THRESHOLD override must not fully
# silence an authentic chronic condition, and must leave a trace when it suppresses anything.
# ---------------------------------------------------------------------------

def test_oversized_threshold_override_cannot_fully_silence_high_chronic_count(tmp_path):
    """RED5-1 Bypass A, PoC-mirrored: `AI_AUTO_CHRONIC_REDISABLE_THRESHOLD=999999` used to
    silence the alarm unconditionally, no matter how chronic the real streak was ("no output --
    suppressed" against a genuine chronic_count=50 marker in the red-team transcript).

    Revert-proof: the pre-fix code takes the raw env var with only a digit-sanity check and no
    ceiling -- chronic_count=50 < 999999 always fails the `-ge` test, so NOTHING prints. This
    fix must still alarm because the effective threshold is clamped well below 50.
    """
    ws = _make_workspace(tmp_path)
    key_file = _make_out_of_tree_key(tmp_path)
    top = _git_toplevel(ws)
    state_dir = ws / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True)

    marker = state_dir / "gemini.disabled"
    fresh_stamp = _run(["date", "-Iseconds"]).stdout.strip()
    _write_marker(
        marker,
        reviewer="gemini",
        disabled_at=fresh_stamp,
        reason="prompt_size_limit",
        details="class=prompt_size_limit; tail=large_prompt_prompt_file_fallback_failed",
        disable_class="transient",
        source_run_id="test",
        chronic_count=50,
        next_action="auto_recover_after_cooldown_300s",
        reset_hint="RESET_DISABLED_AI_REVIEWERS=gemini ./scripts/review-gate.sh",
    )
    _sign_marker(marker, reviewer="gemini", workspace_top=top, key_file=key_file)

    stdout = _run_bash_harness(
        ws,
        preamble=_PREAMBLE_TEMPLATE.format(state_dir=state_dir, key_file=key_file, git_harden=GIT_HARDEN)
        + "AI_AUTO_CHRONIC_REDISABLE_THRESHOLD=999999\n",
        functions_src=_gate_functions_src(),
        body='echo "===CASE==="\nwarn_stale_disabled_reviewers\necho "===CASE-END==="\n',
    )
    case = stdout.split("===CASE===\n", 1)[1].split("===CASE-END===")[0]
    assert "CHRONICALLY RE-DISABLED" in case, (
        f"a chronic_count=50 marker was fully silenced by an oversized threshold override "
        f"(RED5-1 Bypass A reopened):\n{stdout}"
    )


def test_oversized_threshold_override_leaves_a_trace_note(tmp_path):
    """RED5-1 Bypass A, second half: even where the clamp DOES let the override suppress the
    main loud alarm (a chronic_count that clears the default threshold of 3 but not the clamped
    ceiling), the override's use must be surfaced somewhere -- silencing must never be silent
    about itself.

    Revert-proof: the pre-fix code has no override-tracking state at all, so no NOTE of any
    kind is ever printed regardless of chronic_count or the env var's value.
    """
    ws = _make_workspace(tmp_path)
    key_file = _make_out_of_tree_key(tmp_path)
    top = _git_toplevel(ws)
    state_dir = ws / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True)

    marker = state_dir / "gemini.disabled"
    fresh_stamp = _run(["date", "-Iseconds"]).stdout.strip()
    _write_marker(
        marker,
        reviewer="gemini",
        disabled_at=fresh_stamp,
        reason="prompt_size_limit",
        details="class=prompt_size_limit; tail=large_prompt_prompt_file_fallback_failed",
        disable_class="transient",
        source_run_id="test",
        chronic_count=10,  # clears the default(3), stays below the clamp ceiling(20)
        next_action="auto_recover_after_cooldown_300s",
        reset_hint="RESET_DISABLED_AI_REVIEWERS=gemini ./scripts/review-gate.sh",
    )
    _sign_marker(marker, reviewer="gemini", workspace_top=top, key_file=key_file)

    stdout = _run_bash_harness(
        ws,
        preamble=_PREAMBLE_TEMPLATE.format(state_dir=state_dir, key_file=key_file, git_harden=GIT_HARDEN)
        + "AI_AUTO_CHRONIC_REDISABLE_THRESHOLD=999999\n",
        functions_src=_gate_functions_src(),
        body='echo "===CASE==="\nwarn_stale_disabled_reviewers\necho "===CASE-END==="\n',
    )
    case = stdout.split("===CASE===\n", 1)[1].split("===CASE-END===")[0]
    # The main "CHRONICALLY RE-DISABLED" alarm is legitimately suppressed here (10 < clamped
    # ceiling 20) -- but the override's presence must be on record, not silent.
    assert "CHRONICALLY RE-DISABLED" not in case, case
    assert "AI_AUTO_CHRONIC_REDISABLE_THRESHOLD" in case, (
        f"an active threshold override left NO trace at all:\n{stdout}"
    )
    assert case.strip() != "", stdout


def test_default_threshold_unaffected_when_no_override_present(tmp_path):
    """Guard rail: with no AI_AUTO_CHRONIC_REDISABLE_THRESHOLD set at all, the clamp/override
    bookkeeping must not itself print a trace note -- there is nothing overridden to report."""
    ws = _make_workspace(tmp_path)
    key_file = _make_out_of_tree_key(tmp_path)
    top = _git_toplevel(ws)
    state_dir = ws / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True)

    marker = state_dir / "gemini.disabled"
    fresh_stamp = _run(["date", "-Iseconds"]).stdout.strip()
    _write_marker(
        marker,
        reviewer="gemini",
        disabled_at=fresh_stamp,
        reason="prompt_size_limit",
        details="class=prompt_size_limit; tail=large_prompt_prompt_file_fallback_failed",
        disable_class="transient",
        source_run_id="test",
        chronic_count=1,
        next_action="auto_recover_after_cooldown_300s",
        reset_hint="RESET_DISABLED_AI_REVIEWERS=gemini ./scripts/review-gate.sh",
    )
    _sign_marker(marker, reviewer="gemini", workspace_top=top, key_file=key_file)

    stdout = _run_bash_harness(
        ws,
        preamble=_PREAMBLE_TEMPLATE.format(state_dir=state_dir, key_file=key_file, git_harden=GIT_HARDEN),
        functions_src=_gate_functions_src(),
        body='echo "===CASE==="\nwarn_stale_disabled_reviewers\necho "===CASE-END==="\n',
    )
    case = stdout.split("===CASE===\n", 1)[1].split("===CASE-END===")[0]
    assert case.strip() == "", stdout


# ---------------------------------------------------------------------------
# (c) RED9-1 (R4 red-team re-attack, docs: .ops-game/R4-red9-reattack.md): an ABSENT marker_hmac
# must NOT be trusted to justify silence -- it must be treated the same as a tampered one.
# ---------------------------------------------------------------------------

def test_absent_marker_hmac_does_not_silence_alarm(tmp_path):
    """RED9-1, PoC-mirrored: the round-3 fix only rejected a marker_hmac that was PRESENT but
    did not verify; a marker that OMITS the field entirely fell through to trusting the raw
    chronic_count -- LESS effort for an attacker than tampering a signed one, and it disagreed
    with run-ai-reviews.sh's reviewer_disabled_authentic(), which already treats an absent
    marker_hmac as not authentic.

    This marker is genuinely chronic (chronic_count=5 >= default threshold 3) but was never
    signed at all (no marker_hmac line, no key file needed -- the simplest possible plant/
    legacy-no-infra shape). The fixed code must not let its absence justify silence: it must
    take the loud authenticity-failed branch, exactly as it would for a present-but-tampered
    marker_hmac.

    Revert-proof: the pre-RED9-1 code treats an absent field as "no claim to check" and falls
    through to `chronic -ge chronic_threshold`, which is true here (5 >= 3), printing
    "CHRONICALLY RE-DISABLED" and never "AUTHENTICITY FAILED". Against that code this test's
    "AUTHENTICITY FAILED" assertion fails, and its "CHRONICALLY RE-DISABLED" absence assertion
    also fails (that string IS printed pre-fix).
    """
    ws = _make_workspace(tmp_path)
    key_file = _make_out_of_tree_key(tmp_path)
    state_dir = ws / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True)

    marker = state_dir / "gemini.disabled"
    fresh_stamp = _run(["date", "-Iseconds"]).stdout.strip()
    _write_marker(
        marker,
        reviewer="gemini",
        disabled_at=fresh_stamp,
        reason="prompt_size_limit",
        details="class=prompt_size_limit; tail=large_prompt_prompt_file_fallback_failed",
        disable_class="transient",
        source_run_id="test",
        chronic_count=5,
        next_action="auto_recover_after_cooldown_300s",
        reset_hint="RESET_DISABLED_AI_REVIEWERS=gemini ./scripts/review-gate.sh",
    )
    # Deliberately NOT calling _sign_marker -- this marker has no marker_hmac line at all.

    stdout = _run_bash_harness(
        ws,
        preamble=_PREAMBLE_TEMPLATE.format(state_dir=state_dir, key_file=key_file, git_harden=GIT_HARDEN),
        functions_src=_gate_functions_src(),
        body='echo "===CASE==="\nwarn_stale_disabled_reviewers\necho "===CASE-END==="\n',
    )
    case = stdout.split("===CASE===\n", 1)[1].split("===CASE-END===")[0]
    assert case.strip() != "", "an absent marker_hmac silently trusted chronic_count (RED9-1 reopened)"
    assert "AUTHENTICITY FAILED" in case, stdout
    # The authenticity-failed branch mentions "CHRONICALLY RE-DISABLED" inline as part of its
    # own message ("Treating as CHRONICALLY RE-DISABLED regardless..."); what must NOT appear is
    # the separate, dedicated alarm line the (never-reached) trusted-count branch would emit.
    assert "[gate] EXTERNAL REVIEW CHRONICALLY RE-DISABLED:" not in case, stdout
    assert "gemini" in case, stdout


# ---------------------------------------------------------------------------
# (d) RED9-3 (R4 red-team re-attack): AI_AUTO_CHRONIC_REDISABLE_THRESHOLD_MAX is itself capped
# by an in-code literal constant that no env var can raise past.
# ---------------------------------------------------------------------------

def test_threshold_max_hard_cap_cannot_be_env_silenced(tmp_path):
    """RED9-3, PoC-mirrored: round-3's clamp bounded AI_AUTO_CHRONIC_REDISABLE_THRESHOLD by
    AI_AUTO_CHRONIC_REDISABLE_THRESHOLD_MAX, but that ceiling was itself only digit-sanitized
    with no upper bound -- a caller who can set one env var (the accepted threat model) can set
    two: THRESHOLD=<huge> together with THRESHOLD_MAX=<huge> fully mutes a genuinely high
    chronic_count, defeating the clamp's own stated goal.

    This marker carries a genuinely high, validly-signed chronic_count (5000 -- comfortably
    above any reasonable ceiling) with BOTH env vars set to an enormous value. The fix's
    in-code hard cap (chronic_threshold_hard_cap) must still bound the effective threshold well
    below 5000, so the alarm fires regardless of what the two env vars claim.

    Revert-proof: the pre-RED9-3 code clamps chronic_threshold_max to whatever
    AI_AUTO_CHRONIC_REDISABLE_THRESHOLD_MAX says (999999999 here, digit-sanity only), so
    chronic_threshold ends up 999999999 and `5000 -ge 999999999` is false -- nothing prints at
    all against that code, and this test's "CHRONICALLY RE-DISABLED" assertion fails.
    """
    ws = _make_workspace(tmp_path)
    key_file = _make_out_of_tree_key(tmp_path)
    top = _git_toplevel(ws)
    state_dir = ws / ".omx" / "reviewer-state"
    state_dir.mkdir(parents=True)

    marker = state_dir / "gemini.disabled"
    fresh_stamp = _run(["date", "-Iseconds"]).stdout.strip()
    _write_marker(
        marker,
        reviewer="gemini",
        disabled_at=fresh_stamp,
        reason="prompt_size_limit",
        details="class=prompt_size_limit; tail=large_prompt_prompt_file_fallback_failed",
        disable_class="transient",
        source_run_id="test",
        chronic_count=5000,
        next_action="auto_recover_after_cooldown_300s",
        reset_hint="RESET_DISABLED_AI_REVIEWERS=gemini ./scripts/review-gate.sh",
    )
    _sign_marker(marker, reviewer="gemini", workspace_top=top, key_file=key_file)

    stdout = _run_bash_harness(
        ws,
        preamble=_PREAMBLE_TEMPLATE.format(state_dir=state_dir, key_file=key_file, git_harden=GIT_HARDEN)
        + "AI_AUTO_CHRONIC_REDISABLE_THRESHOLD=999999999\n"
        + "AI_AUTO_CHRONIC_REDISABLE_THRESHOLD_MAX=999999999\n",
        functions_src=_gate_functions_src(),
        body='echo "===CASE==="\nwarn_stale_disabled_reviewers\necho "===CASE-END==="\n',
    )
    case = stdout.split("===CASE===\n", 1)[1].split("===CASE-END===")[0]
    assert "CHRONICALLY RE-DISABLED" in case, (
        f"a chronic_count=5000 marker was fully silenced by maxing out BOTH "
        f"AI_AUTO_CHRONIC_REDISABLE_THRESHOLD and _THRESHOLD_MAX (RED9-3 reopened):\n{stdout}"
    )
    assert "AUTHENTICITY FAILED" not in case, stdout
