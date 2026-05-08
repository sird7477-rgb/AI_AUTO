#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-.omx/review-results}"
CONTEXT_DIR="${CONTEXT_DIR:-.omx/review-context}"
PROMPT_DIR="${PROMPT_DIR:-.omx/review-prompts}"
EXTERNAL_REVIEW_DIR="${EXTERNAL_REVIEW_DIR:-.omx/external-review}"
REVIEW_STATE_DIR="${REVIEW_STATE_DIR:-.omx/reviewer-state}"
REVIEW_EXECUTION_MODE="${REVIEW_EXECUTION_MODE:-local}"
REVIEW_TIMEOUT_SECONDS="${REVIEW_TIMEOUT_SECONDS:-180}"
REVIEW_TIMEOUT_KILL_AFTER_SECONDS="${REVIEW_TIMEOUT_KILL_AFTER_SECONDS:-5}"
CLAUDE_REVIEW_TIMEOUT_SECONDS="${CLAUDE_REVIEW_TIMEOUT_SECONDS:-300}"
GEMINI_REVIEW_TIMEOUT_SECONDS="${GEMINI_REVIEW_TIMEOUT_SECONDS:-${REVIEW_TIMEOUT_SECONDS}}"
GEMINI_PROMPT_ARG_MAX_BYTES="${GEMINI_PROMPT_ARG_MAX_BYTES:-100000}"
REVIEW_RETRY_LIMIT="${REVIEW_RETRY_LIMIT:-3}"
REVIEW_OUTPUT_MODE="${REVIEW_OUTPUT_MODE:-file}"
SKIP_CONTEXT_GENERATION="${SKIP_CONTEXT_GENERATION:-0}"

mkdir -p "${OUT_DIR}" "${CONTEXT_DIR}" "${PROMPT_DIR}" "${EXTERNAL_REVIEW_DIR}" "${REVIEW_STATE_DIR}"

if [ "${SKIP_CONTEXT_GENERATION}" = "1" ]; then
  echo "[review] using existing review context and prompts..."
  CONTEXT_FILE="$(find "${CONTEXT_DIR}" -maxdepth 1 -type f -name 'review-context-*.md' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
  CONTEXT_FILE="${CONTEXT_FILE:-existing context in ${CONTEXT_DIR}}"
else
  echo "[review] collecting review context..."
  CONTEXT_FILE="$(OUT_DIR="${CONTEXT_DIR}" ./scripts/collect-review-context.sh)"

  echo "[review] generating review prompts..."
  OUT_DIR="${PROMPT_DIR}" ./scripts/make-review-prompts.sh "${CONTEXT_FILE}" >/dev/null
fi

CLAUDE_PROMPT="${PROMPT_DIR}/claude-review.md"
GEMINI_PROMPT="${PROMPT_DIR}/gemini-review.md"

if [ ! -f "${CLAUDE_PROMPT}" ] || [ ! -f "${GEMINI_PROMPT}" ]; then
  echo "[review] review prompts missing; regenerate context without SKIP_CONTEXT_GENERATION=1"
  exit 1
fi

TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
CLAUDE_OUT="${OUT_DIR}/claude-review-${TIMESTAMP}.md"
GEMINI_OUT="${OUT_DIR}/gemini-review-${TIMESTAMP}.md"
CODEX_SELF_REVIEW_OUT="${OUT_DIR}/codex-self-review-${TIMESTAMP}.md"
SUMMARY_OUT="${OUT_DIR}/review-summary-${TIMESTAMP}.md"
EXTERNAL_RUNNER="${EXTERNAL_REVIEW_DIR}/run-reviewers-${TIMESTAMP}.sh"
EXTERNAL_LATEST="${EXTERNAL_REVIEW_DIR}/run-reviewers-latest.sh"

write_external_runner() {
  cat > "${EXTERNAL_RUNNER}" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail

script_dir="\$(CDPATH= cd -- "\$(dirname -- "\${BASH_SOURCE[0]}")" && pwd)"
if [ -x "\${script_dir}/../../scripts/run-ai-reviews.sh" ]; then
  repo_root="\$(CDPATH= cd -- "\${script_dir}/../.." && pwd)"
else
  repo_root="$(pwd)"
fi
cd "\${repo_root}"

: "\${OUT_DIR:=${OUT_DIR}}"
: "\${CONTEXT_DIR:=${CONTEXT_DIR}}"
: "\${PROMPT_DIR:=${PROMPT_DIR}}"
: "\${REVIEW_STATE_DIR:=${REVIEW_STATE_DIR}}"
: "\${REVIEW_TIMEOUT_SECONDS:=${REVIEW_TIMEOUT_SECONDS}}"
: "\${REVIEW_TIMEOUT_KILL_AFTER_SECONDS:=${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}}"
: "\${CLAUDE_REVIEW_TIMEOUT_SECONDS:=${CLAUDE_REVIEW_TIMEOUT_SECONDS}}"
: "\${GEMINI_REVIEW_TIMEOUT_SECONDS:=${GEMINI_REVIEW_TIMEOUT_SECONDS}}"
: "\${GEMINI_PROMPT_ARG_MAX_BYTES:=${GEMINI_PROMPT_ARG_MAX_BYTES}}"
: "\${REVIEW_RETRY_LIMIT:=${REVIEW_RETRY_LIMIT}}"
: "\${REVIEW_OUTPUT_MODE:=tee}"
: "\${SKIP_CONTEXT_GENERATION:=1}"

REVIEW_EXECUTION_MODE=local \\
OUT_DIR="\${OUT_DIR}" \\
CONTEXT_DIR="\${CONTEXT_DIR}" \\
PROMPT_DIR="\${PROMPT_DIR}" \\
REVIEW_STATE_DIR="\${REVIEW_STATE_DIR}" \\
REVIEW_TIMEOUT_SECONDS="\${REVIEW_TIMEOUT_SECONDS}" \\
REVIEW_TIMEOUT_KILL_AFTER_SECONDS="\${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}" \\
CLAUDE_REVIEW_TIMEOUT_SECONDS="\${CLAUDE_REVIEW_TIMEOUT_SECONDS}" \\
GEMINI_REVIEW_TIMEOUT_SECONDS="\${GEMINI_REVIEW_TIMEOUT_SECONDS}" \\
GEMINI_PROMPT_ARG_MAX_BYTES="\${GEMINI_PROMPT_ARG_MAX_BYTES}" \\
REVIEW_RETRY_LIMIT="\${REVIEW_RETRY_LIMIT}" \\
REVIEW_OUTPUT_MODE="\${REVIEW_OUTPUT_MODE}" \\
SKIP_CONTEXT_GENERATION="\${SKIP_CONTEXT_GENERATION}" \\
./scripts/run-ai-reviews.sh

RESULT_DIR="\${OUT_DIR}" OUT_DIR="\${OUT_DIR}" ./scripts/summarize-ai-reviews.sh
SCRIPT

  chmod +x "${EXTERNAL_RUNNER}"
  cp "${EXTERNAL_RUNNER}" "${EXTERNAL_LATEST}"
  chmod +x "${EXTERNAL_LATEST}"
}

if [ "${REVIEW_EXECUTION_MODE}" = "external" ]; then
  write_external_runner

  cat > "${SUMMARY_OUT}" <<SUMMARY
# AI Review Summary

Generated at: $(date -Iseconds)

## Inputs

- Context: ${CONTEXT_FILE}
- Claude prompt: ${CLAUDE_PROMPT}
- Gemini prompt: ${GEMINI_PROMPT}

## External Reviewer Command

Run this from an unrestricted interactive terminal:

    ${EXTERNAL_RUNNER}

Latest external reviewer command:

    ${EXTERNAL_LATEST}

## Notes

External mode prepares the review context and prompts, then stops before invoking reviewer CLIs in this restricted agent-run context.
SUMMARY

  echo "[review] external reviewer runner: ${EXTERNAL_RUNNER}"
  echo "[review] latest external reviewer runner: ${EXTERNAL_LATEST}"
  echo "[review] summary: ${SUMMARY_OUT}"
  echo "[review] external review pending"
  exit 2
fi

reset_disabled_reviewers() {
  case "${RESET_DISABLED_AI_REVIEWERS:-}" in
    all)
      rm -f "${REVIEW_STATE_DIR}/claude.disabled" "${REVIEW_STATE_DIR}/gemini.disabled"
      ;;
    claude)
      rm -f "${REVIEW_STATE_DIR}/claude.disabled"
      ;;
    gemini)
      rm -f "${REVIEW_STATE_DIR}/gemini.disabled"
      ;;
    "")
      ;;
    *)
      echo "[review] unknown RESET_DISABLED_AI_REVIEWERS value: ${RESET_DISABLED_AI_REVIEWERS}"
      ;;
  esac
}

reset_disabled_reviewers

reviewer_disabled_file() {
  echo "${REVIEW_STATE_DIR}/$1.disabled"
}

disable_reviewer() {
  local reviewer="$1"
  local reason="$2"
  local details="$3"
  local disabled_file
  disabled_file="$(reviewer_disabled_file "${reviewer}")"

  {
    echo "reviewer=${reviewer}"
    echo "disabled_at=$(date -Iseconds)"
    echo "reason=${reason}"
    echo "details=${details}"
  } > "${disabled_file}"

  echo "[review] ${reviewer} review disabled until user re-enables it: ${reason} (${details})"
}

disabled_reason() {
  local reviewer="$1"
  local disabled_file
  disabled_file="$(reviewer_disabled_file "${reviewer}")"

  if [ ! -f "${disabled_file}" ]; then
    return 1
  fi

  local reason details disabled_at
  reason="$(sed -n 's/^reason=//p' "${disabled_file}")"
  details="$(sed -n 's/^details=//p' "${disabled_file}")"
  disabled_at="$(sed -n 's/^disabled_at=//p' "${disabled_file}")"
  echo "reason=${reason}; details=${details}; disabled_at=${disabled_at}"
}

write_disabled_result() {
  local reviewer="$1"
  local output_file="$2"
  local reason="$3"

  echo "[review] ${reviewer} review skipped: disabled until user re-enables it (${reason})"
  cat > "${output_file}" <<MSG
# ${reviewer^} Review

Skipped: ${reviewer} review is disabled until the user re-enables it.

Reason:
${reason}

To re-enable:
- RESET_DISABLED_AI_REVIEWERS=${reviewer} ./scripts/run-ai-reviews.sh
- RESET_DISABLED_AI_REVIEWERS=all ./scripts/run-ai-reviews.sh
MSG
}

is_limit_failure() {
  local output_file="$1"

  grep -qiE 'hit your limit|usage limit|session limit|weekly limit|week limit|rate limit|quota|RESOURCE_EXHAUSTED|resets [0-9]|resets [ap]m|limit reached' "${output_file}"
}

has_usable_verdict() {
  local output_file="$1"

  awk '
    BEGIN { in_verdict = 0 }
    tolower($0) ~ /^#+[[:space:]]+verdict[[:space:]:.-]*$/ { in_verdict = 1; next }
    in_verdict && /^#+[[:space:]]+/ { exit }
    in_verdict && /^[[:space:]]*$/ { next }
    in_verdict {
      verdict = tolower($0)
      gsub(/[^a-z_]/, "", verdict)
      if (verdict == "approve" || verdict == "approve_with_notes" || verdict == "request_changes") {
        found = 1
        exit
      }
    }
    END { exit found ? 0 : 1 }
  ' "${output_file}"
}

run_review_command() {
  local output_file="$1"
  shift

  if [ "${REVIEW_OUTPUT_MODE}" = "tee" ]; then
    "$@" 2>&1 | tee "${output_file}"
    return "${PIPESTATUS[0]}"
  fi

  "$@" > "${output_file}" 2>&1
}

run_review_command_stdin() {
  local output_file="$1"
  local input_file="$2"
  shift 2

  if [ "${REVIEW_OUTPUT_MODE}" = "tee" ]; then
    "$@" < "${input_file}" 2>&1 | tee "${output_file}"
    return "${PIPESTATUS[0]}"
  fi

  "$@" < "${input_file}" > "${output_file}" 2>&1
}

run_with_retries() {
  local reviewer="$1"
  local output_file="$2"
  shift 2

  local attempt=1
  local status=0

  while [ "${attempt}" -le "${REVIEW_RETRY_LIMIT}" ]; do
    echo "[review] ${reviewer} attempt ${attempt}/${REVIEW_RETRY_LIMIT}"
    "$@"
    status=$?

    if [ "${status}" -eq 0 ] && has_usable_verdict "${output_file}"; then
      return 0
    fi

    if is_limit_failure "${output_file}"; then
      disable_reviewer "${reviewer}" "usage_limit" "reviewer reported a session, weekly, quota, or rate limit"
      return "${status}"
    fi

    if [ "${status}" -eq 0 ]; then
      status=1
      echo "[review] ${reviewer} produced no usable ## Verdict section"
    fi

    echo "[review] ${reviewer} attempt ${attempt}/${REVIEW_RETRY_LIMIT} failed with status ${status}"
    attempt=$((attempt + 1))
  done

  disable_reviewer "${reviewer}" "retry_exhausted" "no usable response after ${REVIEW_RETRY_LIMIT} attempts"
  return "${status}"
}

run_claude() {
  if [ "${RUN_CLAUDE_REVIEW:-1}" = "0" ]; then
    echo "[review] Claude review disabled by RUN_CLAUDE_REVIEW=0"
    cat > "${CLAUDE_OUT}" <<MSG
# Claude Review

Skipped: Claude review was disabled by RUN_CLAUDE_REVIEW=0.
MSG
    return 0
  fi

  local disabled
  if disabled="$(disabled_reason claude)"; then
    write_disabled_result "claude" "${CLAUDE_OUT}" "${disabled}"
    return 0
  fi

  if ! command -v claude >/dev/null 2>&1; then
    echo "[review] claude command not found; skipping Claude review"
    cat > "${CLAUDE_OUT}" <<MSG
# Claude Review

Skipped: claude command not found.
MSG
    return 0
  fi

  echo "[review] running Claude review..."

  set +e
  claude_help="$(claude --help 2>/dev/null)"
  if printf '%s\n' "${claude_help}" | grep -q -- '--print'; then
    claude_args=(--print)

    if printf '%s\n' "${claude_help}" | grep -q -- '--no-session-persistence'; then
      claude_args+=(--no-session-persistence)
    fi

    if printf '%s\n' "${claude_help}" | grep -q -- '--permission-mode'; then
      claude_args+=(--permission-mode plan)
    fi

    run_with_retries "claude" "${CLAUDE_OUT}" run_review_command "${CLAUDE_OUT}" timeout -k "${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}" "${CLAUDE_REVIEW_TIMEOUT_SECONDS}" claude "${claude_args[@]}" "$(cat "${CLAUDE_PROMPT}")"
  else
    run_with_retries "claude" "${CLAUDE_OUT}" run_review_command_stdin "${CLAUDE_OUT}" "${CLAUDE_PROMPT}" timeout -k "${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}" "${CLAUDE_REVIEW_TIMEOUT_SECONDS}" claude
  fi
  status=$?
  set -e

  if [ "${status}" -ne 0 ]; then
    {
      echo
      echo "---"
      echo
      echo "Claude review failed or timed out."
      echo "Exit status: ${status}"
      echo "Timeout seconds: ${CLAUDE_REVIEW_TIMEOUT_SECONDS}"
      echo
      echo "Known possible causes in agent-run contexts:"
      echo "- Anthropic API/network access is blocked or refused"
      echo "- Claude cannot write under its runtime directory"
      echo "- Claude authentication is unavailable in bare or isolated mode"
    } >> "${CLAUDE_OUT}"
    echo "[review] Claude review failed; result captured: ${CLAUDE_OUT}"
    return 0
  fi

  echo "[review] Claude result: ${CLAUDE_OUT}"
}

run_gemini() {
  if [ "${RUN_GEMINI_REVIEW:-1}" = "0" ]; then
    echo "[review] Gemini review disabled; unset RUN_GEMINI_REVIEW or set RUN_GEMINI_REVIEW=1 to enable"
    cat > "${GEMINI_OUT}" <<MSG
# Gemini Review

Skipped: Gemini review was disabled by RUN_GEMINI_REVIEW=0.

Reason:
- Gemini CLI may enter interactive or agent mode.
- Previous runs hung or failed with capacity/tool errors.
- The default is to run Gemini; set RUN_GEMINI_REVIEW=0 to opt out for a specific gate run.
MSG
    return 0
  fi

  local disabled
  if disabled="$(disabled_reason gemini)"; then
    write_disabled_result "gemini" "${GEMINI_OUT}" "${disabled}"
    return 0
  fi

  if ! command -v gemini >/dev/null 2>&1; then
    echo "[review] gemini command not found; skipping Gemini review"
    cat > "${GEMINI_OUT}" <<MSG
# Gemini Review

Skipped: gemini command not found.
MSG
    return 0
  fi

  echo "[review] running Gemini review..."

  set +e
  gemini_help="$(gemini --help 2>/dev/null)"
  if printf '%s\n' "${gemini_help}" | grep -q -- '--prompt'; then
    gemini_prompt_bytes="$(wc -c < "${GEMINI_PROMPT}")"

    if [ "${gemini_prompt_bytes}" -gt "${GEMINI_PROMPT_ARG_MAX_BYTES}" ]; then
      gemini_args=(--prompt "Review the Markdown prompt provided on stdin.")
      gemini_stdin_mode=1
    else
      gemini_args=(--prompt "$(cat "${GEMINI_PROMPT}")")
      gemini_stdin_mode=0
    fi

    if printf '%s\n' "${gemini_help}" | grep -q -- '--approval-mode'; then
      gemini_args+=(--approval-mode plan)
    fi

    if printf '%s\n' "${gemini_help}" | grep -q -- '--skip-trust'; then
      gemini_args+=(--skip-trust)
    fi

    if printf '%s\n' "${gemini_help}" | grep -q -- '--output-format'; then
      gemini_args+=(--output-format text)
    fi

    if [ "${gemini_stdin_mode}" -eq 1 ]; then
      run_with_retries "gemini" "${GEMINI_OUT}" run_review_command_stdin "${GEMINI_OUT}" "${GEMINI_PROMPT}" timeout -k "${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}" "${GEMINI_REVIEW_TIMEOUT_SECONDS}" gemini "${gemini_args[@]}"
    else
      run_with_retries "gemini" "${GEMINI_OUT}" run_review_command "${GEMINI_OUT}" timeout -k "${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}" "${GEMINI_REVIEW_TIMEOUT_SECONDS}" gemini "${gemini_args[@]}"
    fi
  else
    run_with_retries "gemini" "${GEMINI_OUT}" run_review_command_stdin "${GEMINI_OUT}" "${GEMINI_PROMPT}" timeout -k "${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}" "${GEMINI_REVIEW_TIMEOUT_SECONDS}" gemini
  fi
  status=$?
  set -e

  if [ "${status}" -ne 0 ]; then
    {
      echo
      echo "---"
      echo
      echo "Gemini review failed or timed out."
      echo "Exit status: ${status}"
      echo "Timeout seconds: ${GEMINI_REVIEW_TIMEOUT_SECONDS}"
      echo
      echo "Known possible causes:"
      echo "- Gemini model capacity exhausted"
      echo "- Gemini authentication is unavailable in the current context"
      echo "- Gemini stdin fallback was consumed by an auth prompt instead of review input"
      echo "- CLI tool permissions differ from this repository workflow"
      echo "- Gemini CLI entered an agent/tool mode instead of plain review mode"
    } >> "${GEMINI_OUT}"
    echo "[review] Gemini review failed; result captured: ${GEMINI_OUT}"
    return 0
  fi

  echo "[review] Gemini result: ${GEMINI_OUT}"
}

codex_persona_needed() {
  [ -f "$(reviewer_disabled_file claude)" ] || [ -f "$(reviewer_disabled_file gemini)" ]
}

generate_codex_self_review() {
  if ! codex_persona_needed; then
    cat > "${CODEX_SELF_REVIEW_OUT}" <<MSG
# Codex Self-Review Persona Fallback

Generated at: $(date -Iseconds)

## Status

none

## Assigned Personas

none

## Gate Policy

No Codex persona fallback was needed for this run.
MSG
    return 0
  fi

  echo "[review] generating Codex self-review persona fallback: ${CODEX_SELF_REVIEW_OUT}"

  cat > "${CODEX_SELF_REVIEW_OUT}" <<MSG
# Codex Self-Review Persona Fallback

Generated at: $(date -Iseconds)

## Status

informational_only

## Independence Boundary

This is Codex self-review coverage. It compensates for missing reviewer perspectives, but it is not an independent Claude or Gemini approval.

## Assigned Personas
MSG

  if [ -f "$(reviewer_disabled_file claude)" ]; then
    cat >> "${CODEX_SELF_REVIEW_OUT}" <<MSG

- codex-architect-review
  - compensates for disabled Claude coverage
  - focus: correctness, maintainability, scope control, hidden risk, AGENTS.md and workflow compliance
  - disabled reason: $(disabled_reason claude)
MSG
  fi

  if [ -f "$(reviewer_disabled_file gemini)" ]; then
    cat >> "${CODEX_SELF_REVIEW_OUT}" <<MSG

- codex-test-alternative-review
  - compensates for disabled Gemini coverage
  - focus: missed edge cases, simpler alternatives, test coverage gaps, documentation clarity, future automation friction
  - disabled reason: $(disabled_reason gemini)
MSG
  fi

  if [ -f "$(reviewer_disabled_file claude)" ] && [ -f "$(reviewer_disabled_file gemini)" ]; then
    cat >> "${CODEX_SELF_REVIEW_OUT}" <<MSG

- codex-operator-review
  - compensates for complete independent reviewer outage
  - focus: execution flow, recovery path, state management, operator-visible warnings, reset instructions
MSG
  fi

  cat >> "${CODEX_SELF_REVIEW_OUT}" <<MSG

## Required Checklist

- Verify disabled reviewer reasons are visible in every run.
- Verify remaining reviewer prompts include additional coverage for disabled reviewer roles.
- Verify summary still reports single_reviewer or no_usable_review instead of multi_reviewer.
- Verify Codex self-review is not counted as independent AI reviewer approval.
- Verify re-enable instructions are present for disabled reviewers.

## Gate Policy

Codex self-review can reduce blind spots during reviewer outages, but it does not upgrade review coverage to multi_reviewer.
MSG
}

run_claude
run_gemini
generate_codex_self_review

cat > "${SUMMARY_OUT}" <<SUMMARY
# AI Review Summary

Generated at: $(date -Iseconds)

## Inputs

- Context: ${CONTEXT_FILE}
- Claude prompt: ${CLAUDE_PROMPT}
- Gemini prompt: ${GEMINI_PROMPT}

## Outputs

- Claude result: ${CLAUDE_OUT}
- Gemini result: ${GEMINI_OUT}
- Codex self-review fallback: ${CODEX_SELF_REVIEW_OUT}

## Notes

A reviewer failure does not fail this script. Failures are captured in the corresponding result file.
SUMMARY

echo "[review] summary: ${SUMMARY_OUT}"
echo "[review] done"
