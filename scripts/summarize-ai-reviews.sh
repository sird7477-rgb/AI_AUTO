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

manifest_file() {
  local label="$1"
  local fallback_pattern="$2"
  local value=""

  if [ -n "${REVIEW_RUN_SUMMARY_FILE:-}" ] && [ -f "${REVIEW_RUN_SUMMARY_FILE}" ]; then
    value="$(sed -n "s/^- ${label}: //p" "${REVIEW_RUN_SUMMARY_FILE}" | tail -1)"
  fi

  if [ -n "${value}" ]; then
    echo "${value}"
    return 0
  fi

  latest_file "${fallback_pattern}"
}

is_failure_result() {
  local file="$1"

  awk '
    /^```/ {
      in_code = !in_code
      next
    }
    in_code {
      next
    }
    /^[A-Za-z -]+ review failed or timed out\.$/ {
      marker_line = NR
      next
    }
    marker_line && NR <= marker_line + 4 && /^Exit status: [0-9]+$/ {
      has_exit_status = 1
      next
    }
    marker_line && NR <= marker_line + 5 && /^Timeout seconds: [0-9]+$/ {
      has_timeout = 1
      next
    }
    END {
      exit !(marker_line && has_exit_status && has_timeout)
    }
  ' "${file}"
}

extract_verdict() {
  local file="$1"

  if [ -z "${file}" ] || [ ! -f "${file}" ]; then
    echo "missing"
    return 0
  fi

  if is_failure_result "${file}"; then
    echo "failed"
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

  if grep -qi '^Skipped:' "${file}"; then
    echo "skipped"
    return 0
  fi

  echo "unknown"
}

final_decision() {
  local claude="$1"
  local gemini="$2"
  local codex_architect="$3"
  local codex_test="$4"
  local external_usable_count=0
  local codex_usable_count=0

  if is_usable_review "${claude}"; then
    external_usable_count=$((external_usable_count + 1))
  fi

  if is_usable_review "${gemini}"; then
    external_usable_count=$((external_usable_count + 1))
  fi

  if is_usable_review "${codex_architect}"; then
    codex_usable_count=$((codex_usable_count + 1))
  fi

  if is_usable_review "${codex_test}"; then
    codex_usable_count=$((codex_usable_count + 1))
  fi

  # Approval/request_changes disagreement means a human should inspect the reviews.
  if is_approval "${claude}" && [ "${gemini}" = "request_changes" ]; then
    echo "review_manually"
    return 0
  fi

  if is_approval "${gemini}" && [ "${claude}" = "request_changes" ]; then
    echo "review_manually"
    return 0
  fi

  if { is_approval "${claude}" || is_approval "${gemini}"; } && \
     { [ "${codex_architect}" = "request_changes" ] || [ "${codex_test}" = "request_changes" ]; }; then
    echo "review_manually"
    return 0
  fi

  if [ "${claude}" = "request_changes" ] || [ "${gemini}" = "request_changes" ]; then
    echo "revise"
    return 0
  fi

  if [ "${codex_architect}" = "request_changes" ] || [ "${codex_test}" = "request_changes" ]; then
    echo "revise"
    return 0
  fi

  if [ "${claude}" = "failed" ] && [ "${gemini}" = "failed" ]; then
    if [ "${codex_usable_count}" -ge 2 ] && is_approval "${codex_architect}" && is_approval "${codex_test}"; then
      echo "proceed_degraded"
      return 0
    fi

    echo "blocked"
    return 0
  fi

  if [ "${claude}" = "missing" ] && [ "${gemini}" = "missing" ]; then
    if [ "${codex_usable_count}" -ge 2 ] && is_approval "${codex_architect}" && is_approval "${codex_test}"; then
      echo "proceed_degraded"
      return 0
    fi

    echo "blocked"
    return 0
  fi

  if [ "${external_usable_count}" -eq 0 ]; then
    if [ "${codex_usable_count}" -ge 2 ] && is_approval "${codex_architect}" && is_approval "${codex_test}"; then
      echo "proceed_degraded"
      return 0
    fi

    echo "blocked"
    return 0
  fi

  if is_approval "${claude}" && is_approval "${gemini}"; then
    echo "proceed"
    return 0
  fi

  if is_approval "${claude}" || is_approval "${gemini}"; then
    if [ "${codex_usable_count}" -eq 0 ]; then
      echo "review_manually"
      return 0
    fi

    echo "proceed_degraded"
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
  local codex_architect="$3"
  local codex_test="$4"
  local external_usable_count=0
  local codex_usable_count=0

  if is_usable_review "${claude}"; then
    external_usable_count=$((external_usable_count + 1))
  fi

  if is_usable_review "${gemini}"; then
    external_usable_count=$((external_usable_count + 1))
  fi

  if is_usable_review "${codex_architect}"; then
    codex_usable_count=$((codex_usable_count + 1))
  fi

  if is_usable_review "${codex_test}"; then
    codex_usable_count=$((codex_usable_count + 1))
  fi

  if [ "${external_usable_count}" -eq 2 ]; then
    echo "multi_reviewer"
    return 0
  fi

  if [ "${external_usable_count}" -eq 1 ] && [ "${codex_usable_count}" -gt 0 ]; then
    echo "single_external_plus_codex_fallback"
    return 0
  fi

  if [ "${external_usable_count}" -eq 1 ]; then
    echo "single_reviewer"
    return 0
  fi

  if [ "${codex_usable_count}" -ge 2 ]; then
    echo "codex_only_degraded"
    return 0
  fi

  if [ "${codex_usable_count}" -eq 1 ]; then
    echo "partial_codex_fallback_only"
    return 0
  fi

  echo "no_usable_review"
}

is_usable_review() {
  is_approval "$1" || [ "$1" = "request_changes" ]
}

split_context_active() {
  [ -n "${SPLIT_CONTEXT_MANIFEST_FILE:-}" ] && [ "${SPLIT_CONTEXT_MANIFEST_FILE}" != "none" ] && [ -f "${SPLIT_CONTEXT_MANIFEST_FILE}" ]
}

untracked_guard_block_reason() {
  local context_file="$1"
  local guard_text

  [ -n "${context_file}" ] && [ -f "${context_file}" ] || return 1
  guard_text="$(awk '
    /^## Untracked Review Guard$/ { in_guard=1; next }
    /^## / && in_guard { exit }
    in_guard { print }
  ' "${context_file}")"
  if ! printf '%s\n' "${guard_text}" | grep -q "^guard_status: material_untracked_artifacts_present$" && \
     ! printf '%s\n' "${guard_text}" | grep -q "Material untracked review artifacts are present, but content inclusion is disabled."; then
    return 1
  fi
  if [ "${REVIEW_UNTRACKED_MANUAL_REVIEWED:-0}" = "1" ]; then
    return 1
  fi
  echo "material_untracked_artifacts_require_manual_review"
  return 0
}

phase_scope_guard_block_reason() {
  local context_file="$1"
  local guard_text

  [ -n "${context_file}" ] && [ -f "${context_file}" ] || return 1
  guard_text="$(awk '
    /^## Phase Scope Guard$/ { in_guard=1; next }
    /^## / && in_guard { exit }
    in_guard { print }
  ' "${context_file}")"
  if ! printf '%s\n' "${guard_text}" | grep -Eq "^phase_scope_status: (out_of_phase_edit|missing_deferral_record)$"; then
    return 1
  fi
  if [ "${PHASE_SCOPE_MANUAL_REVIEWED:-0}" = "1" ]; then
    return 1
  fi
  echo "phase_scope_requires_manual_review"
  return 0
}

persona_gate_guard_block_reason() {
  local context_file="$1"
  local summary_text policy active_lenses integrator_required reasons

  [ -n "${context_file}" ] && [ -f "${context_file}" ] || return 1
  summary_text="$(awk '
    /^## Diff Scope Summary$/ { in_summary=1; next }
    /^## / && in_summary { exit }
    in_summary { print }
  ' "${context_file}")"
  [ -n "${summary_text}" ] || return 1
  if printf '%s\n' "${summary_text}" | grep -q "^No changed files detected\.$"; then
    return 1
  fi

  policy="$(printf '%s\n' "${summary_text}" | sed -n 's/^- review gate policy: //p' | head -1)"
  active_lenses="$(printf '%s\n' "${summary_text}" | sed -n 's/^- active lenses: //p' | head -1)"
  integrator_required="$(printf '%s\n' "${summary_text}" | sed -n 's/^- integrator required: //p' | head -1)"
  reasons="$(printf '%s\n' "${summary_text}" | sed -n 's/^- review gate reasons: //p' | head -1)"

  case "${policy}" in
    strict_gate|review_gate|verify_only) ;;
    "")
      echo "persona_gate_classifier_missing"
      return 0
      ;;
    *)
      echo "persona_gate_classifier_malformed"
      return 0
      ;;
  esac

  case "${integrator_required}" in
    true|false) ;;
    *)
      echo "persona_gate_classifier_malformed"
      return 0
      ;;
  esac

  [ -n "${active_lenses}" ] || {
    echo "persona_gate_classifier_malformed"
    return 0
  }
  [ -n "${reasons}" ] || {
    echo "persona_gate_classifier_malformed"
    return 0
  }

  if [ "${policy}" = "strict_gate" ]; then
    if [ "${active_lenses}" = "none" ] || ! printf '%s\n' "${reasons}" | grep -q "lenses="; then
      echo "persona_gate_classifier_malformed"
      return 0
    fi
  fi

  return 1
}

review_covers_split_context() {
  local review_file="$1"
  local manifest_file="$2"
  local part part_name part_pattern synthesis_text

  [ -n "${review_file}" ] && [ -f "${review_file}" ] || return 1
  [ -n "${manifest_file}" ] && [ -f "${manifest_file}" ] || return 1
  synthesis_text="$(
    awk '
      BEGIN { in_section = 0 }
      tolower($0) ~ /^#+[[:space:]]+.*synthesis[[:space:]:.-]*$/ { in_section = 1; next }
      in_section && /^#+[[:space:]]+/ { in_section = 0; next }
      in_section { print }
    ' "${review_file}"
  )"
  [ -n "${synthesis_text}" ] || return 1

  while IFS= read -r part; do
    [ -n "${part}" ] || continue
    part_name="$(basename "${part}")"
    part_pattern="$(printf '%s\n' "${part_name}" | sed 's/[][\\.^$*+?{}|()]/\\&/g')"
    if ! printf '%s\n' "${synthesis_text}" | grep -Eq "${part_pattern}[[:space:]]*[:;-][[:space:]]*[^[:space:]]"; then
      return 1
    fi
  done < <(grep -Eo '[^[:space:]]*split-review-context/part-[0-9]+\.md' "${manifest_file}" | sort -u)

  return 0
}

fallback_has_direct_file_inspection() {
  local review_file="$1"

  [ -n "${review_file}" ] && [ -f "${review_file}" ] || return 1

  awk '
    BEGIN { in_section = 0; has_content = 0 }
    tolower($0) ~ /^#+[[:space:]]+direct file inspection[[:space:]:.-]*$/ { in_section = 1; next }
    in_section && /^#+[[:space:]]+/ { exit }
    in_section && /^[[:space:]]*$/ { next }
    in_section {
      line = tolower($0)
      if (line !~ /no blocking findings/ && line !~ /^none[[:punct:][:space:]]*$/) {
        has_content = 1
        exit
      }
    }
    END { exit has_content ? 0 : 1 }
  ' "${review_file}"
}

policy_block_reason() {
  local claude="$1"
  local gemini="$2"
  local codex_architect="$3"
  local codex_test="$4"

  if split_context_active; then
    if is_approval "${claude}" && ! review_covers_split_context "${CLAUDE_FILE}" "${SPLIT_CONTEXT_MANIFEST_FILE}"; then
      echo "split_context_without_synthesis"
      return 0
    fi
    if is_approval "${gemini}" && ! review_covers_split_context "${GEMINI_FILE}" "${SPLIT_CONTEXT_MANIFEST_FILE}"; then
      echo "split_context_without_synthesis"
      return 0
    fi
  fi

  if [ "${CODEX_FALLBACK_REQUIRED}" -eq 1 ]; then
    if is_approval "${codex_architect}" && ! fallback_has_direct_file_inspection "${CODEX_ARCHITECT_FALLBACK_FILE}"; then
      echo "codex_fallback_missing_direct_file_inspection"
      return 0
    fi
    if is_approval "${codex_test}" && ! fallback_has_direct_file_inspection "${CODEX_TEST_FALLBACK_FILE}"; then
      echo "codex_fallback_missing_direct_file_inspection"
      return 0
    fi
  fi

  echo "none"
}

decision_reason() {
  local claude="$1"
  local gemini="$2"
  local codex_architect="$3"
  local codex_test="$4"

  if { is_approval "${claude}" && [ "${gemini}" = "request_changes" ]; } || \
     { is_approval "${gemini}" && [ "${claude}" = "request_changes" ]; }; then
    echo "reviewer_disagreement"
    return 0
  fi

  if { is_approval "${claude}" || is_approval "${gemini}"; } && \
     { [ "${codex_architect}" = "request_changes" ] || [ "${codex_test}" = "request_changes" ]; }; then
    echo "codex_fallback_requested_changes"
    return 0
  fi

  if [ "${claude}" = "request_changes" ] || [ "${gemini}" = "request_changes" ]; then
    echo "reviewer_requested_changes"
    return 0
  fi

  if [ "${codex_architect}" = "request_changes" ] || [ "${codex_test}" = "request_changes" ]; then
    echo "codex_fallback_requested_changes"
    return 0
  fi

  if [ "${claude}" = "failed" ] && [ "${gemini}" = "failed" ]; then
    if is_approval "${codex_architect}" && is_approval "${codex_test}"; then
      echo "codex_only_degraded_approval"
      return 0
    fi

    echo "all_reviewers_failed"
    return 0
  fi

  if [ "${claude}" = "missing" ] && [ "${gemini}" = "missing" ]; then
    if is_approval "${codex_architect}" && is_approval "${codex_test}"; then
      echo "codex_only_degraded_approval"
      return 0
    fi

    echo "all_reviewers_missing"
    return 0
  fi

  if ! is_usable_review "${claude}" && ! is_usable_review "${gemini}"; then
    if is_approval "${codex_architect}" && is_approval "${codex_test}"; then
      echo "codex_only_degraded_approval"
      return 0
    fi

    echo "no_usable_review"
    return 0
  fi

  if is_approval "${claude}" && is_approval "${gemini}"; then
    echo "multi_reviewer_approval"
    return 0
  fi

  if is_approval "${claude}" || is_approval "${gemini}"; then
    if is_approval "${codex_architect}" || is_approval "${codex_test}"; then
      echo "single_external_plus_codex_fallback_approval"
      return 0
    fi

    echo "single_reviewer_without_codex_fallback"
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

write_review_revision_task() {
  local timestamp="$1"
  local findings_file="${REVIEW_ACCEPTED_FINDINGS_FILE:-}"
  local cycle_count="${REVIEW_REVISION_CYCLE_COUNT:-1}"
  local verification_passed="${REVIEW_REVISION_VERIFICATION_PASSED:-1}"
  local changed_diff="${REVIEW_REVISION_CHANGED_DIFF:-1}"
  local task_file="${OUT_DIR}/review-revision-task-${timestamp}.md"
  local accepted_lines

  if [ -z "${findings_file}" ]; then
    echo "none"
    return 0
  fi

  if [ ! -f "${findings_file}" ]; then
    cat > "${task_file}" <<TASK
# Review Revision Task

status: revision_stop:missing_findings_file
source: ${findings_file}
TASK
    echo "${task_file}"
    return 0
  fi

  if [ "${cycle_count}" -gt 2 ] 2>/dev/null; then
    cat > "${task_file}" <<TASK
# Review Revision Task

status: revision_stop:cycle_limit
cycle_count: ${cycle_count}
max_cycles: 2
TASK
    echo "${task_file}"
    return 0
  fi

  if [ "${REVIEW_REVISION_UNCLEAR_REVIEW:-0}" = "1" ]; then
    cat > "${task_file}" <<TASK
# Review Revision Task

status: revision_stop:unclear_review
TASK
    echo "${task_file}"
    return 0
  fi

  if [ "${REVIEW_REVISION_REVIEWER_DISAGREEMENT:-0}" = "1" ]; then
    cat > "${task_file}" <<TASK
# Review Revision Task

status: revision_manual_review
reason: reviewer_disagreement
TASK
    echo "${task_file}"
    return 0
  fi

  if [ "${REVIEW_REVISION_REPEATED_VERIFY_FAILURE:-0}" = "1" ] || [ "${verification_passed}" != "1" ]; then
    cat > "${task_file}" <<TASK
# Review Revision Task

status: revision_stop:verification_failure
cycle_count: ${cycle_count}
TASK
    echo "${task_file}"
    return 0
  fi

  if [ "${REVIEW_REVISION_SECOND_PASS_REQUESTED:-0}" = "1" ] && [ "${changed_diff}" != "1" ]; then
    cat > "${task_file}" <<TASK
# Review Revision Task

status: revision_block:no_changed_diff
cycle_count: ${cycle_count}
TASK
    echo "${task_file}"
    return 0
  fi

  accepted_lines="$(
    awk -F'|' '
      $1 == "accepted" && $2 != "" && $3 != "" && $4 != "" && $5 != "" {
        printf "- id: %s\n  reviewer: %s\n  file: %s\n  task: %s\n", $2, $3, $4, $5
      }
    ' "${findings_file}"
  )"

  if [ -z "${accepted_lines}" ]; then
    cat > "${task_file}" <<TASK
# Review Revision Task

status: revision_task_skipped
reason: no_structured_accepted_findings
source: ${findings_file}
TASK
    echo "${task_file}"
    return 0
  fi

  cat > "${task_file}" <<TASK
# Review Revision Task

status: revision_task_created
cycle_count: ${cycle_count}
max_cycles: 2
source: ${findings_file}

## Scope

Apply only the accepted structured reviewer findings listed below. Do not apply
free-text, rejected, proposed, fixed, or deferred findings as automatic work.

## Accepted Findings

${accepted_lines}

## Required Checks

- Run ./scripts/verify.sh after the revision.
- Run a second review pass only when the revision produced a changed diff.
- Stop for manual decision if verification fails repeatedly, reviewer output is
  unclear, reviewers disagree, or a third automatic revision cycle would start.
TASK

  echo "${task_file}"
}

REVIEW_RUN_SUMMARY_FILE="$(latest_file 'review-summary-*.md')"
REVIEW_CONTEXT_FILE="$(manifest_file 'Context' 'latest-review-context.md')"
CLAUDE_FILE="$(manifest_file 'Claude result' 'claude-review-*.md')"
GEMINI_FILE="$(manifest_file 'Gemini result' 'gemini-review-*.md')"
CODEX_ARCHITECT_FALLBACK_FILE="$(manifest_file 'Codex architect fallback' 'codex-architect-fallback-*.md')"
CODEX_TEST_FALLBACK_FILE="$(manifest_file 'Codex test fallback' 'codex-test-fallback-*.md')"
CODEX_FALLBACK_SUMMARY_FILE="$(manifest_file 'Codex fallback summary' 'codex-fallback-summary-*.md')"
SPLIT_CONTEXT_MANIFEST_FILE="$(manifest_file 'Split context manifest' 'split-review-manifest.md')"
CODEX_FALLBACK_REQUIRED=0
if [ -n "${CODEX_FALLBACK_SUMMARY_FILE}" ] && [ -f "${CODEX_FALLBACK_SUMMARY_FILE}" ] && grep -q '^informational_only$' "${CODEX_FALLBACK_SUMMARY_FILE}"; then
  CODEX_FALLBACK_REQUIRED=1
fi

CLAUDE_VERDICT="$(extract_verdict "${CLAUDE_FILE}")"
GEMINI_VERDICT="$(extract_verdict "${GEMINI_FILE}")"
CODEX_ARCHITECT_VERDICT="missing"
CODEX_TEST_VERDICT="missing"
if [ "${CODEX_FALLBACK_REQUIRED}" -eq 1 ]; then
  CODEX_ARCHITECT_VERDICT="$(extract_verdict "${CODEX_ARCHITECT_FALLBACK_FILE}")"
  CODEX_TEST_VERDICT="$(extract_verdict "${CODEX_TEST_FALLBACK_FILE}")"
fi
FINAL_DECISION="$(final_decision "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}" "${CODEX_ARCHITECT_VERDICT}" "${CODEX_TEST_VERDICT}")"
REVIEW_COVERAGE="$(review_coverage "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}" "${CODEX_ARCHITECT_VERDICT}" "${CODEX_TEST_VERDICT}")"
DECISION_REASON="$(decision_reason "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}" "${CODEX_ARCHITECT_VERDICT}" "${CODEX_TEST_VERDICT}")"
POLICY_BLOCK_REASON="$(policy_block_reason "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}" "${CODEX_ARCHITECT_VERDICT}" "${CODEX_TEST_VERDICT}")"
UNTRACKED_BLOCK_REASON="$(untracked_guard_block_reason "${REVIEW_CONTEXT_FILE}" || true)"
if [ -n "${UNTRACKED_BLOCK_REASON}" ]; then
  if [ "${POLICY_BLOCK_REASON}" = "none" ]; then
    POLICY_BLOCK_REASON="${UNTRACKED_BLOCK_REASON}"
  else
    POLICY_BLOCK_REASON="${POLICY_BLOCK_REASON},${UNTRACKED_BLOCK_REASON}"
  fi
fi
PHASE_SCOPE_BLOCK_REASON="$(phase_scope_guard_block_reason "${REVIEW_CONTEXT_FILE}" || true)"
if [ -n "${PHASE_SCOPE_BLOCK_REASON}" ]; then
  if [ "${POLICY_BLOCK_REASON}" = "none" ]; then
    POLICY_BLOCK_REASON="${PHASE_SCOPE_BLOCK_REASON}"
  else
    POLICY_BLOCK_REASON="${POLICY_BLOCK_REASON},${PHASE_SCOPE_BLOCK_REASON}"
  fi
fi
PERSONA_GATE_BLOCK_REASON="$(persona_gate_guard_block_reason "${REVIEW_CONTEXT_FILE}" || true)"
if [ -n "${PERSONA_GATE_BLOCK_REASON}" ]; then
  if [ "${POLICY_BLOCK_REASON}" = "none" ]; then
    POLICY_BLOCK_REASON="${PERSONA_GATE_BLOCK_REASON}"
  else
    POLICY_BLOCK_REASON="${POLICY_BLOCK_REASON},${PERSONA_GATE_BLOCK_REASON}"
  fi
fi
if [ "${POLICY_BLOCK_REASON}" != "none" ] && { [ "${FINAL_DECISION}" = "proceed" ] || [ "${FINAL_DECISION}" = "proceed_degraded" ]; }; then
  FINAL_DECISION="review_manually"
  DECISION_REASON="${POLICY_BLOCK_REASON}"
fi
MISSING_REVIEWERS="$(missing_reviewers "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}")"
CODEX_FALLBACK_COVERAGE="none"
if is_usable_review "${CODEX_ARCHITECT_VERDICT}" || is_usable_review "${CODEX_TEST_VERDICT}"; then
  CODEX_FALLBACK_COVERAGE="available_degraded_informational_only"
elif [ "${CODEX_FALLBACK_REQUIRED}" -eq 1 ]; then
  CODEX_FALLBACK_COVERAGE="required_but_unusable"
fi

TRUST_LEVEL="degraded"
if [ "${REVIEW_COVERAGE}" = "multi_reviewer" ] && [ "${FINAL_DECISION}" = "proceed" ]; then
  TRUST_LEVEL="normal"
elif [ "${FINAL_DECISION}" = "blocked" ] || [ "${FINAL_DECISION}" = "revise" ] || [ "${FINAL_DECISION}" = "review_manually" ]; then
  TRUST_LEVEL="blocked_or_needs_attention"
fi

TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
SUMMARY_FILE="${OUT_DIR}/review-verdict-${TIMESTAMP}.md"
REVISION_TASK_FILE="$(write_review_revision_task "${TIMESTAMP}")"

cat > "${SUMMARY_FILE}" <<SUMMARY
# AI Review Verdict

Generated at: $(date -Iseconds)

## Short Summary

- decision: ${FINAL_DECISION}
- reason: ${DECISION_REASON}
- coverage: ${REVIEW_COVERAGE}
- trust: ${TRUST_LEVEL}
- missing_or_unusable_reviewers: ${MISSING_REVIEWERS}
- authority: ${FINAL_DECISION} is not commit approval unless normal verification and user commit approval are also satisfied.

## Final Decision

${FINAL_DECISION}

## Decision Reason

${DECISION_REASON}

## Review Coverage

${REVIEW_COVERAGE}

## Trust Level

${TRUST_LEVEL}

## Missing Or Unusable Reviewers

${MISSING_REVIEWERS}

## Codex Fallback Coverage

${CODEX_FALLBACK_COVERAGE}

Codex fallback coverage is degraded and informational-only. It is not independent Claude or Gemini reviewer approval.

## Split Context Manifest

${SPLIT_CONTEXT_MANIFEST_FILE:-none}

## Review Context

${REVIEW_CONTEXT_FILE:-missing}

## Untracked Artifact Guard

${UNTRACKED_BLOCK_REASON:-clear}

## Phase Scope Guard

${PHASE_SCOPE_BLOCK_REASON:-clear}

## Persona Gate Guard

${PERSONA_GATE_BLOCK_REASON:-clear}

## Review Revision Task

${REVISION_TASK_FILE}

## Disabled Reviewer Reporting

Skipped external reviewers always mean degraded coverage. A reviewer skipped by
\`RUN_CLAUDE_REVIEW=0\` or \`RUN_GEMINI_REVIEW=0\` is an intentional user opt-out,
not an external reviewer failure. A reviewer skipped because of a persisted
.omx/reviewer-state marker remains disabled until the reset hint is run.

## Reviewer Verdicts

| Reviewer | Verdict | File |
|---|---|---|
| Claude | ${CLAUDE_VERDICT} | ${CLAUDE_FILE:-missing} |
| Gemini | ${GEMINI_VERDICT} | ${GEMINI_FILE:-missing} |

## Codex Fallback Reviews

| Fallback Reviewer | Verdict | File |
|---|---|---|
| codex-architect-review | ${CODEX_ARCHITECT_VERDICT} | ${CODEX_ARCHITECT_FALLBACK_FILE:-missing} |
| codex-test-alternative-review | ${CODEX_TEST_VERDICT} | ${CODEX_TEST_FALLBACK_FILE:-missing} |
| summary | ${CODEX_FALLBACK_COVERAGE} | ${CODEX_FALLBACK_SUMMARY_FILE:-missing} |

## Interpretation

- proceed: review is sufficient to continue toward user approval or commit.
- proceed_degraded: review may continue with explicit degraded trust; at least one external reviewer is missing or only Codex fallback coverage is available.
- revise: at least one reviewer requested changes.
- blocked: no usable review result is available.
- review_manually: review output exists, but the verdict could not be confidently parsed, reviewers disagreed, Codex fallback requested changes alongside external approval, or only one external reviewer approved without usable fallback coverage.
- single_reviewer: only one external reviewer produced a usable verdict; inspect missing reviewer status before relying on multi-agent coverage.
- single_external_plus_codex_fallback: one external reviewer approved and at least one Codex fallback reviewer ran; this is degraded coverage.
- codex_only_degraded: no external reviewer produced a usable verdict; two Codex fallback reviewers ran, but this is not independent external review.
- multi_reviewer: both reviewers produced usable verdicts.

## Next Step

If the final decision is proceed or proceed_degraded, inspect the review files and continue with normal verification/commit approval. For proceed_degraded, report the degraded trust level to the user.

If the final decision is revise, inspect reviewer findings and apply only accepted feedback.

If the final decision is blocked or review_manually, inspect the raw review files before continuing.
SUMMARY

echo "${SUMMARY_FILE}"
echo
cat "${SUMMARY_FILE}"

if [ "${FINAL_DECISION}" != "proceed" ] && [ "${FINAL_DECISION}" != "proceed_degraded" ]; then
  exit 1
fi
