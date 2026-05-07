#!/usr/bin/env bash
set -euo pipefail

RESULT_DIR="${RESULT_DIR:-.omx/review-results}"
OUT_DIR="${OUT_DIR:-.omx/review-results}"

mkdir -p "${OUT_DIR}"

latest_file() {
  local pattern="$1"
  find "${RESULT_DIR}" -maxdepth 1 -type f -name "${pattern}" -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -1 \
    | cut -d' ' -f2-
}

extract_verdict() {
  local file="$1"

  if [ -z "${file}" ] || [ ! -f "${file}" ]; then
    echo "missing"
    return 0
  fi

  if grep -qi 'Skipped:' "${file}"; then
    echo "skipped"
    return 0
  fi

  if grep -qiE 'failed|timed out|RESOURCE_EXHAUSTED|429|Operation cancelled|not found' "${file}"; then
    echo "failed"
    return 0
  fi

  if grep -qi 'request_changes' "${file}"; then
    echo "request_changes"
    return 0
  fi

  if grep -qi 'approve_with_notes' "${file}"; then
    echo "approve_with_notes"
    return 0
  fi

  if grep -qi 'approve' "${file}"; then
    echo "approve"
    return 0
  fi

  echo "unknown"
}

final_decision() {
  local claude="$1"
  local gemini="$2"

  if [ "${claude}" = "request_changes" ] || [ "${gemini}" = "request_changes" ]; then
    echo "revise"
    return 0
  fi

  if [ "${claude}" = "failed" ] && [ "${gemini}" = "failed" ]; then
    echo "blocked"
    return 0
  fi

  if [ "${claude}" = "missing" ] && [ "${gemini}" = "missing" ]; then
    echo "blocked"
    return 0
  fi

  if [ "${claude}" = "approve" ] || [ "${claude}" = "approve_with_notes" ]; then
    echo "proceed"
    return 0
  fi

  if [ "${gemini}" = "approve" ] || [ "${gemini}" = "approve_with_notes" ]; then
    echo "proceed"
    return 0
  fi

  echo "review_manually"
}

CLAUDE_FILE="$(latest_file 'claude-review-*.md')"
GEMINI_FILE="$(latest_file 'gemini-review-*.md')"

CLAUDE_VERDICT="$(extract_verdict "${CLAUDE_FILE}")"
GEMINI_VERDICT="$(extract_verdict "${GEMINI_FILE}")"
FINAL_DECISION="$(final_decision "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}")"

TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
SUMMARY_FILE="${OUT_DIR}/review-verdict-${TIMESTAMP}.md"

cat > "${SUMMARY_FILE}" <<SUMMARY
# AI Review Verdict

Generated at: $(date -Iseconds)

## Final Decision

${FINAL_DECISION}

## Reviewer Verdicts

| Reviewer | Verdict | File |
|---|---|---|
| Claude | ${CLAUDE_VERDICT} | ${CLAUDE_FILE:-missing} |
| Gemini | ${GEMINI_VERDICT} | ${GEMINI_FILE:-missing} |

## Interpretation

- proceed: review is sufficient to continue toward user approval or commit.
- revise: at least one reviewer requested changes.
- blocked: no usable review result is available.
- review_manually: review output exists, but the verdict could not be confidently parsed.

## Next Step

If the final decision is proceed, inspect the review file and continue with normal verification/commit approval.

If the final decision is revise, inspect reviewer findings and apply only accepted feedback.

If the final decision is blocked or review_manually, inspect the raw review files before continuing.
SUMMARY

echo "${SUMMARY_FILE}"
echo
cat "${SUMMARY_FILE}"
