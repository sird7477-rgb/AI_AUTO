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

  local verdict
  verdict="$(
    awk '
      BEGIN { in_verdict = 0 }
      tolower($0) ~ /^#+[[:space:]]+verdict[[:space:]:.-]*$/ { in_verdict = 1; next }
      in_verdict && /^#+[[:space:]]+/ { exit }
      in_verdict && /^[[:space:]]*$/ { next }
      in_verdict {
        verdict = tolower($0)
        gsub(/[^a-z_]/, "", verdict)
        if (verdict == "approve" || verdict == "approve_with_notes" || verdict == "request_changes") {
          print verdict
          exit
        }
      }
    ' "${file}"
  )"

  if [ -n "${verdict}" ]; then
    echo "${verdict}"
    return 0
  fi

  if grep -qiE 'failed|timed out|RESOURCE_EXHAUSTED|429|Operation cancelled|not found' "${file}"; then
    echo "failed"
    return 0
  fi

  echo "unknown"
}

final_decision() {
  local claude="$1"
  local gemini="$2"

  # Approval/request_changes disagreement means a human should inspect the reviews.
  if is_approval "${claude}" && [ "${gemini}" = "request_changes" ]; then
    echo "review_manually"
    return 0
  fi

  if is_approval "${gemini}" && [ "${claude}" = "request_changes" ]; then
    echo "review_manually"
    return 0
  fi

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

  if ! is_usable_review "${claude}" && ! is_usable_review "${gemini}"; then
    echo "blocked"
    return 0
  fi

  if is_approval "${claude}"; then
    echo "proceed"
    return 0
  fi

  if is_approval "${gemini}"; then
    echo "proceed"
    return 0
  fi

  echo "review_manually"
}

is_approval() {
  [ "$1" = "approve" ] || [ "$1" = "approve_with_notes" ]
}

review_coverage() {
  local claude="$1"
  local gemini="$2"

  if is_usable_review "${claude}" && is_usable_review "${gemini}"; then
    echo "multi_reviewer"
    return 0
  fi

  if is_usable_review "${claude}" || is_usable_review "${gemini}"; then
    echo "single_reviewer"
    return 0
  fi

  echo "no_usable_review"
}

is_usable_review() {
  is_approval "$1" || [ "$1" = "request_changes" ]
}

decision_reason() {
  local claude="$1"
  local gemini="$2"

  if { is_approval "${claude}" && [ "${gemini}" = "request_changes" ]; } || \
     { is_approval "${gemini}" && [ "${claude}" = "request_changes" ]; }; then
    echo "reviewer_disagreement"
    return 0
  fi

  if [ "${claude}" = "request_changes" ] || [ "${gemini}" = "request_changes" ]; then
    echo "reviewer_requested_changes"
    return 0
  fi

  if [ "${claude}" = "failed" ] && [ "${gemini}" = "failed" ]; then
    echo "all_reviewers_failed"
    return 0
  fi

  if [ "${claude}" = "missing" ] && [ "${gemini}" = "missing" ]; then
    echo "all_reviewers_missing"
    return 0
  fi

  if ! is_usable_review "${claude}" && ! is_usable_review "${gemini}"; then
    echo "no_usable_review"
    return 0
  fi

  if is_approval "${claude}" && is_approval "${gemini}"; then
    echo "multi_reviewer_approval"
    return 0
  fi

  if is_approval "${claude}" || is_approval "${gemini}"; then
    echo "single_reviewer_approval"
    return 0
  fi

  echo "unclassified_review_output"
}

missing_reviewers() {
  local claude="$1"
  local gemini="$2"
  local missing=()

  case "${claude}" in
    skipped|missing|failed|unknown) missing+=("claude:${claude}") ;;
  esac

  case "${gemini}" in
    skipped|missing|failed|unknown) missing+=("gemini:${gemini}") ;;
  esac

  if [ "${#missing[@]}" -eq 0 ]; then
    echo "none"
  else
    local joined="${missing[0]}"
    local item
    for item in "${missing[@]:1}"; do
      joined="${joined}, ${item}"
    done
    echo "${joined}"
  fi
}

CLAUDE_FILE="$(latest_file 'claude-review-*.md')"
GEMINI_FILE="$(latest_file 'gemini-review-*.md')"
CODEX_SELF_REVIEW_FILE="$(latest_file 'codex-self-review-*.md')"

CLAUDE_VERDICT="$(extract_verdict "${CLAUDE_FILE}")"
GEMINI_VERDICT="$(extract_verdict "${GEMINI_FILE}")"
FINAL_DECISION="$(final_decision "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}")"
REVIEW_COVERAGE="$(review_coverage "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}")"
DECISION_REASON="$(decision_reason "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}")"
MISSING_REVIEWERS="$(missing_reviewers "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}")"
CODEX_SELF_REVIEW_COVERAGE="none"
if [ -n "${CODEX_SELF_REVIEW_FILE}" ] && [ -f "${CODEX_SELF_REVIEW_FILE}" ]; then
  if grep -q '^informational_only$' "${CODEX_SELF_REVIEW_FILE}"; then
    CODEX_SELF_REVIEW_COVERAGE="available_informational_only"
  fi
fi

TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
SUMMARY_FILE="${OUT_DIR}/review-verdict-${TIMESTAMP}.md"

cat > "${SUMMARY_FILE}" <<SUMMARY
# AI Review Verdict

Generated at: $(date -Iseconds)

## Final Decision

${FINAL_DECISION}

## Decision Reason

${DECISION_REASON}

## Review Coverage

${REVIEW_COVERAGE}

## Missing Or Unusable Reviewers

${MISSING_REVIEWERS}

## Codex Self-Review Coverage

${CODEX_SELF_REVIEW_COVERAGE}

Codex self-review coverage compensates for missing perspectives, but it is not independent Claude or Gemini reviewer approval.

## Reviewer Verdicts

| Reviewer | Verdict | File |
|---|---|---|
| Claude | ${CLAUDE_VERDICT} | ${CLAUDE_FILE:-missing} |
| Gemini | ${GEMINI_VERDICT} | ${GEMINI_FILE:-missing} |

## Codex Self-Review

| Coverage | File |
|---|---|
| ${CODEX_SELF_REVIEW_COVERAGE} | ${CODEX_SELF_REVIEW_FILE:-missing} |

## Interpretation

- proceed: review is sufficient to continue toward user approval or commit.
- revise: at least one reviewer requested changes.
- blocked: no usable review result is available.
- review_manually: review output exists, but the verdict could not be confidently parsed, or reviewers disagreed.
- single_reviewer: only one reviewer produced a usable verdict; inspect missing reviewer status before relying on multi-agent coverage.
- multi_reviewer: both reviewers produced usable verdicts.

## Next Step

If the final decision is proceed, inspect the review file and continue with normal verification/commit approval.

If the final decision is revise, inspect reviewer findings and apply only accepted feedback.

If the final decision is blocked or review_manually, inspect the raw review files before continuing.
SUMMARY

echo "${SUMMARY_FILE}"
echo
cat "${SUMMARY_FILE}"

if [ "${FINAL_DECISION}" != "proceed" ]; then
  exit 1
fi
