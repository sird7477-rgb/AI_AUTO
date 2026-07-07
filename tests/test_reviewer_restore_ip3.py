"""Regression tests for SPEC IP-3' (docs/ops-audits/2026-07-07-spec-v2.md).

Covers audit finding A3 (docs/ops-audits/2026-07-07-codex-session-audit.md): Gemini via `agy`
failing on an oversized prompt (`large_prompt_requires_prompt_file`) got classified as a
persistent, non-auto-recovering disable, degrading every gate to codex self-review for 21 days.

- AC3-1: ai-runtime-adapter.sh's agy path must fall back to `--prompt-file` for an oversized
  prompt instead of erroring, since the arg-max ceiling is about argv length, not file size.
- AC3-3 / AC3-5: a size/prompt-file failure must classify as TRANSIENT (auto-recovers), but a
  chronic same-reason re-disable streak must still trip a loud alarm even though the class is
  transient and `disabled_at` resets on every cycle (D6 guard against a silently-vacuous fix).
- Item 3: an api_env=missing-style failure is not code-fixable and must stay honestly persistent
  (not swept into transient by the new classification regex).

These tests exercise the REAL scripts via subprocess, not reimplementations:
- scripts/ai-runtime-adapter.sh is run as a full subprocess (its own CLI) with a fake `agy`.
- scripts/run-ai-reviews.sh and scripts/review-gate.sh define their target functions inline in
  the same file as many other top-level statements with side effects (they are not
  library-safe to `source` directly), so the specific functions under test are extracted
  verbatim (by function-boundary text) from the live script file and sourced into a small,
  self-contained bash harness. This still tests the real, current function bodies -- editing
  the source functions changes what these tests execute, with no copy to fall out of sync.
"""

import os
import re
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / "scripts" / "ai-runtime-adapter.sh"
RUN_AI_REVIEWS = ROOT / "scripts" / "run-ai-reviews.sh"
REVIEW_GATE = ROOT / "scripts" / "review-gate.sh"


def _run(args, *, env=None, cwd=None):
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        args,
        cwd=cwd or ROOT,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=60,
    )


def _extract_bash_functions(script_path: Path, names: set) -> str:
    """Pull top-level `name() { ... }` bodies verbatim out of a bash script.

    Matches this codebase's consistent style: a function header alone on its own line
    (`name() {`) and a lone closing `}` at column 0 terminating it -- confirmed for every
    function name used below via `awk`/manual inspection of the real files.
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


def _run_bash_harness(tmp_path: Path, preamble: str, functions_src: str, body: str) -> str:
    """Assemble+run a bash script: preamble, extracted real functions, then the test body."""
    script = tmp_path / "harness.sh"
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
    result = _run(["bash", str(script)], cwd=tmp_path)
    assert result.returncode == 0, (
        f"harness script failed (exit {result.returncode}):\n{result.stdout}"
    )
    return result.stdout


# ---------------------------------------------------------------------------
# AC3-1: adapter must fall back to --prompt-file for an oversized prompt.
# ---------------------------------------------------------------------------

_FAKE_AGY = """#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --help)
    cat <<'EOF'
Usage: agy [--prompt TEXT] [--sandbox] [--approval-mode MODE] [--skip-trust] \\
           [--output-format FMT] [--print-timeout SEC] [--model MODEL]
EOF
    exit 0
    ;;
esac

found_file=""
found_prompt_arg=0
prev=""
for arg in "$@"; do
  if [ "${prev}" = "--prompt-file" ]; then found_file="${arg}"; fi
  if [ "${prev}" = "--prompt" ]; then found_prompt_arg=1; fi
  prev="${arg}"
done

if [ -n "${found_file}" ]; then
  echo "FAKE_AGY_PROMPT_FILE_INVOKED file=${found_file} bytes=$(wc -c < "${found_file}")"
  echo "## Verdict"
  echo "approve"
  exit 0
fi

if [ "${found_prompt_arg}" -eq 1 ]; then
  echo "FAKE_AGY_PROMPT_ARG_INVOKED"
  echo "## Verdict"
  echo "approve"
  exit 0
fi

echo "FAKE_AGY_UNEXPECTED_INVOCATION argv=$*"
exit 1
"""


def _write_fake_agy(tmp_path: Path) -> Path:
    fake_agy = tmp_path / "fake_agy.sh"
    fake_agy.write_text(_FAKE_AGY)
    fake_agy.chmod(fake_agy.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return fake_agy


def test_adapter_falls_back_to_prompt_file_when_help_omits_it(tmp_path):
    """AC3-1: --help advertising only --prompt (not --prompt-file, a D6 false-negative) must
    still get an oversized prompt routed through --prompt-file, not an error.

    Revert-proof: with the AC3-1 fix removed, ai-runtime-adapter.sh's agy path errors with
    `reason=large_prompt_requires_prompt_file` and returns 4 *before* ever invoking agy, so the
    fake agy's marker text is absent and the exit code is 4 -- this test fails on that revert.
    """
    fake_agy = _write_fake_agy(tmp_path)
    work_dir = tmp_path / "work"
    work_dir.mkdir()
    prompt_file = tmp_path / "prompt.txt"
    prompt_file.write_text("X" * 500)  # comfortably over the 100-byte test ceiling below
    output_file = tmp_path / "out.md"

    result = _run(
        [
            str(ADAPTER),
            "run-readonly",
            "--runtime",
            "agy",
            "--capability",
            "review",
            "--prompt-file",
            str(prompt_file),
            "--output",
            str(output_file),
            "--timeout",
            "10",
            "--kill-after",
            "3",
            "--cd",
            str(work_dir),
        ],
        env={
            "RUNTIME_ADAPTER_AGY_COMMAND": str(fake_agy),
            "RUNTIME_ADAPTER_PROMPT_ARG_MAX_BYTES": "100",
        },
    )

    assert result.returncode == 0, result.stdout
    assert "large_prompt_requires_prompt_file" not in result.stdout
    out_content = output_file.read_text()
    assert "FAKE_AGY_PROMPT_FILE_INVOKED" in out_content, out_content
    assert "FAKE_AGY_UNEXPECTED_INVOCATION" not in out_content


def test_adapter_still_uses_prompt_arg_for_small_prompts(tmp_path):
    """Guard rail: the AC3-1 fallback must only trigger over the size ceiling; a small prompt
    still goes through the plain --prompt argv path (unchanged behavior)."""
    fake_agy = _write_fake_agy(tmp_path)
    work_dir = tmp_path / "work"
    work_dir.mkdir()
    prompt_file = tmp_path / "prompt.txt"
    prompt_file.write_text("small prompt")
    output_file = tmp_path / "out.md"

    result = _run(
        [
            str(ADAPTER),
            "run-readonly",
            "--runtime",
            "agy",
            "--capability",
            "review",
            "--prompt-file",
            str(prompt_file),
            "--output",
            str(output_file),
            "--timeout",
            "10",
            "--kill-after",
            "3",
            "--cd",
            str(work_dir),
        ],
        env={
            "RUNTIME_ADAPTER_AGY_COMMAND": str(fake_agy),
            "RUNTIME_ADAPTER_PROMPT_ARG_MAX_BYTES": "100000",
        },
    )

    assert result.returncode == 0, result.stdout
    out_content = output_file.read_text()
    assert "FAKE_AGY_PROMPT_FILE_INVOKED" not in out_content
    assert "FAKE_AGY_PROMPT_ARG_INVOKED" in out_content
    assert "## Verdict" in out_content


# ---------------------------------------------------------------------------
# AC3-3 / AC3-5: classification + chronic-redisable counter (run-ai-reviews.sh).
# ---------------------------------------------------------------------------

_RUN_AI_REVIEWS_FUNCS = {
    "reviewer_disabled_file",
    "reviewer_chronic_file",
    "disable_reviewer",
    "failure_class",
    "is_limit_failure",
    "reset_disabled_reviewers",
}


def _run_ai_reviews_functions_src() -> str:
    return _extract_bash_functions(RUN_AI_REVIEWS, _RUN_AI_REVIEWS_FUNCS)


def test_large_prompt_output_classifies_as_prompt_size_limit_and_is_limit_failure(tmp_path):
    """AC3-3: failure_class() must tag the adapter's large-prompt runtime_unavailable text as
    `prompt_size_limit` (not the generic `command_failed`), and is_limit_failure() must
    recognize it so run_with_retries short-circuits to disable_reviewer() immediately instead
    of burning REVIEW_RETRY_LIMIT identical, doomed retries.

    Revert-proof: without the AC3-3 failure_class()/is_limit_failure() additions, REASON prints
    `command_failed` and IS_LIMIT prints `no`.
    """
    state_dir = tmp_path / "state"
    output_file = tmp_path / "adapter-output.txt"
    output_file.write_text(
        "runtime_unavailable: runtime=agy reason=large_prompt_prompt_file_fallback_failed "
        "prompt_bytes=150000 prompt_arg_max_bytes=100000 fallback_exit=4\n"
    )

    stdout = _run_bash_harness(
        tmp_path,
        preamble=f'REVIEW_STATE_DIR="{state_dir}"\nmkdir -p "${{REVIEW_STATE_DIR}}"\n'
        f'REVIEW_RUN_ID="test-run"\n'
        "principal_evidence_ensure_key() { return 1; }\n",
        functions_src=_run_ai_reviews_functions_src(),
        body=f"""
reason="$(failure_class "{output_file}" 4)"
echo "REASON=${{reason}}"
if is_limit_failure "{output_file}"; then echo "IS_LIMIT=yes"; else echo "IS_LIMIT=no"; fi
""",
    )

    assert "REASON=prompt_size_limit" in stdout, stdout
    assert "IS_LIMIT=yes" in stdout, stdout


def test_prompt_size_limit_disable_is_transient_with_chronic_counter(tmp_path):
    """AC3-3: a prompt_size_limit disable must be disable_class=transient (auto-recovers).

    AC3-5 (D6 guard): the chronic_count must keep incrementing across delete/recreate cycles of
    the .disabled marker (simulating expire_transient_disabled_reviewers' cooldown-expiry
    `rm -f`), because the counter lives in a side file, not the marker itself. If it only lived
    in the marker (or wasn't tracked at all), chronic_count would stay 1 forever.

    Revert-proof: without AC3-3, disable_class prints `persistent`. Without AC3-5's side-file
    counter, chronic_count would read 1 on every cycle instead of 1, 2, 3.
    """
    state_dir = tmp_path / "state"

    stdout = _run_bash_harness(
        tmp_path,
        preamble=f'REVIEW_STATE_DIR="{state_dir}"\nmkdir -p "${{REVIEW_STATE_DIR}}"\n'
        f'REVIEW_RUN_ID="test-run"\n'
        "principal_evidence_ensure_key() { return 1; }\n",
        functions_src=_run_ai_reviews_functions_src(),
        body="""
disable_reviewer gemini prompt_size_limit "class=prompt_size_limit; tail=large_prompt run 1"
echo "===1==="
cat "${REVIEW_STATE_DIR}/gemini.disabled"

# Simulate expire_transient_disabled_reviewers()'s cooldown-expiry cleanup: it rm -f's the
# .disabled marker but never touches the chronic side file.
rm -f "${REVIEW_STATE_DIR}/gemini.disabled"
disable_reviewer gemini prompt_size_limit "class=prompt_size_limit; tail=large_prompt run 2"
echo "===2==="
cat "${REVIEW_STATE_DIR}/gemini.disabled"

rm -f "${REVIEW_STATE_DIR}/gemini.disabled"
disable_reviewer gemini prompt_size_limit "class=prompt_size_limit; tail=large_prompt run 3"
echo "===3==="
cat "${REVIEW_STATE_DIR}/gemini.disabled"
""",
    )

    blocks = re.split(r"===\d===\n", stdout)
    # blocks[0] is the disable_reviewer stdout chatter before the first marker dump
    assert len(blocks) == 4, stdout
    assert "disable_class=transient" in blocks[1]
    assert "chronic_count=1" in blocks[1], blocks[1]
    assert "disable_class=transient" in blocks[2]
    assert "chronic_count=2" in blocks[2], blocks[2]
    assert "disable_class=transient" in blocks[3]
    assert "chronic_count=3" in blocks[3], blocks[3]


def test_reset_disabled_reviewers_clears_chronic_streak(tmp_path):
    """A manual RESET_DISABLED_AI_REVIEWERS reset must also clear the chronic-redisable
    streak: a human fixing the root cause should not leave the reviewer one disable away from
    a stale chronic P0 forever.

    Revert-proof: without clearing the .chronic side file in reset_disabled_reviewers(), the
    post-reset disable would read chronic_count=4 instead of resetting to 1.
    """
    state_dir = tmp_path / "state"

    stdout = _run_bash_harness(
        tmp_path,
        preamble=f'REVIEW_STATE_DIR="{state_dir}"\nmkdir -p "${{REVIEW_STATE_DIR}}"\n'
        f'REVIEW_RUN_ID="test-run"\n'
        "principal_evidence_ensure_key() { return 1; }\n",
        functions_src=_run_ai_reviews_functions_src(),
        body="""
disable_reviewer gemini prompt_size_limit "run 1"
rm -f "${REVIEW_STATE_DIR}/gemini.disabled"
disable_reviewer gemini prompt_size_limit "run 2"
rm -f "${REVIEW_STATE_DIR}/gemini.disabled"

RESET_DISABLED_AI_REVIEWERS=gemini reset_disabled_reviewers
echo "===post-reset-files==="
ls "${REVIEW_STATE_DIR}" | grep -c gemini || true

disable_reviewer gemini prompt_size_limit "run after reset"
echo "===post-reset-disable==="
cat "${REVIEW_STATE_DIR}/gemini.disabled"
""",
    )

    post_reset_files = stdout.split("===post-reset-files===\n", 1)[1].split(
        "===post-reset-disable===\n"
    )[0]
    # The `ls | grep -c` count is the first line; disable_reviewer's own [review] chatter
    # follows it (interleaved before the next marker), so only assert on that first line.
    assert post_reset_files.splitlines()[0].strip() == "0", stdout
    post_reset_disable = stdout.split("===post-reset-disable===\n", 1)[1]
    assert "chronic_count=1" in post_reset_disable, stdout


def test_unrelated_persistent_failure_is_not_swept_into_transient(tmp_path):
    """Honesty guard (item 3 / regex-overreach guard): a credential/auth-shaped failure (the
    agy api_env=missing shape) must remain disable_class=persistent, and the api_env=missing
    lineage must survive verbatim in `details=` -- the AC3-3 regex additions must not broaden
    transient classification to swallow this.

    Revert-proof: a sloppy fix that classifies transient by presence of any adapter chatter
    (rather than specifically large_prompt text) would flip this to transient; this test
    catches that overreach.
    """
    state_dir = tmp_path / "state"
    output_file = tmp_path / "adapter-output2.txt"
    output_file.write_text(
        "runtime_unavailable: runtime=agy reason=missing_noninteractive_prompt_mode\n"
        "credential expired, unauthorized, api_env=missing\n"
    )

    stdout = _run_bash_harness(
        tmp_path,
        preamble=f'REVIEW_STATE_DIR="{state_dir}"\nmkdir -p "${{REVIEW_STATE_DIR}}"\n'
        f'REVIEW_RUN_ID="test-run"\n'
        "principal_evidence_ensure_key() { return 1; }\n",
        functions_src=_run_ai_reviews_functions_src(),
        body=f"""
reason="$(failure_class "{output_file}" 1)"
echo "REASON=${{reason}}"
disable_reviewer gemini "${{reason}}" "class=${{reason}}; tail=$(tr '\\n' ' ' < "{output_file}")"
cat "${{REVIEW_STATE_DIR}}/gemini.disabled"
""",
    )

    assert "REASON=auth_or_permission" in stdout, stdout
    assert "disable_class=persistent" in stdout, stdout
    assert "api_env=missing" in stdout, stdout  # lineage recorded honestly, not swallowed


# ---------------------------------------------------------------------------
# AC3-5: review-gate.sh's warn_stale_disabled_reviewers must alarm on a chronic transient
# re-disable even though disabled_at is fresh and the class is transient.
# ---------------------------------------------------------------------------

def test_warn_stale_disabled_reviewers_alarms_on_chronic_transient(tmp_path):
    """AC3-5 / D6: a fresh, disable_class=transient marker is normally fully silent (it will
    auto-recover on its own). But once chronic_count crosses the threshold -- the same root
    cause re-tripping the disable run after run -- the staleness guard must still speak up,
    because the ordinary freshness check (disabled_at) can never fire for a marker that keeps
    getting deleted and recreated every cooldown cycle.

    Revert-proof: with the pre-AC3-5 code (`[ "${cls}" = "transient" ] && continue`
    unconditionally), CASE1 below produces no warning at all and this assertion fails.
    """
    state_dir = tmp_path / "state"
    state_dir.mkdir()
    functions_src = _extract_bash_functions(
        REVIEW_GATE, {"warn_stale_disabled_reviewers"}
    )

    fresh_stamp = _run(["date", "-Iseconds"]).stdout.strip()
    marker_chronic = state_dir / "gemini.disabled"
    marker_chronic.write_text(
        "reviewer=gemini\n"
        f"disabled_at={fresh_stamp}\n"
        "reason=prompt_size_limit\n"
        "details=class=prompt_size_limit; tail=large_prompt_prompt_file_fallback_failed\n"
        "disable_class=transient\n"
        "source_run_id=test\n"
        "next_action=auto_recover_after_cooldown_300s\n"
        "chronic_count=3\n"
        "reset_hint=RESET_DISABLED_AI_REVIEWERS=gemini ./scripts/review-gate.sh\n"
    )

    stdout = _run_bash_harness(
        tmp_path,
        preamble=f'REVIEW_STATE_DIR="{state_dir}"\n'
        "AI_AUTO_CHRONIC_REDISABLE_THRESHOLD=3\n",
        functions_src=functions_src,
        body="""
echo "===CASE1==="
warn_stale_disabled_reviewers
echo "===CASE1-END==="
""",
    )

    case1 = stdout.split("===CASE1===\n", 1)[1].split("===CASE1-END===")[0]
    assert "CHRONICALLY RE-DISABLED" in case1, stdout


def test_warn_stale_disabled_reviewers_silent_for_ordinary_transient_disable(tmp_path):
    """Guard rail: an ordinary, fresh, low-chronic-count transient disable must stay fully
    silent (unchanged pre-existing behavior) -- the chronic alarm must not fire on every
    routine transient disable."""
    state_dir = tmp_path / "state"
    state_dir.mkdir()
    functions_src = _extract_bash_functions(
        REVIEW_GATE, {"warn_stale_disabled_reviewers"}
    )

    marker = state_dir / "gemini.disabled"
    fresh_stamp = _run(["date", "-Iseconds"]).stdout.strip()
    marker.write_text(
        "reviewer=gemini\n"
        f"disabled_at={fresh_stamp}\n"
        "reason=prompt_size_limit\n"
        "details=class=prompt_size_limit; tail=large_prompt_prompt_file_fallback_failed\n"
        "disable_class=transient\n"
        "source_run_id=test\n"
        "next_action=auto_recover_after_cooldown_300s\n"
        "chronic_count=1\n"
        "reset_hint=RESET_DISABLED_AI_REVIEWERS=gemini ./scripts/review-gate.sh\n"
    )

    stdout = _run_bash_harness(
        tmp_path,
        preamble=f'REVIEW_STATE_DIR="{state_dir}"\n'
        "AI_AUTO_CHRONIC_REDISABLE_THRESHOLD=3\n",
        functions_src=functions_src,
        body="""
echo "===CASE2==="
warn_stale_disabled_reviewers
echo "===CASE2-END==="
""",
    )

    case2 = stdout.split("===CASE2===\n", 1)[1].split("===CASE2-END===")[0]
    assert "CHRONICALLY RE-DISABLED" not in case2, stdout
    assert "PERSISTENTLY DEGRADED" not in case2, stdout
    assert case2.strip() == "", stdout
