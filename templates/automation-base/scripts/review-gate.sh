#!/usr/bin/env bash
set -euo pipefail

VERIFY_OUTPUT_FILE="${VERIFY_OUTPUT_FILE:-.omx/review-context/latest-verify-output.txt}"
mkdir -p "$(dirname "$VERIFY_OUTPUT_FILE")"

latest_review_context() {
  find ".omx/review-context" -maxdepth 1 -type f -name 'latest-review-context.md' -print 2>/dev/null | head -1
}

diff_scope_field() {
  local field="$1"
  local context_file
  context_file="$(latest_review_context)"
  [ -n "${context_file}" ] && [ -f "${context_file}" ] || return 0
  awk -v field="- ${field}: " '
    /^## Diff Scope Summary$/ { in_scope=1; next }
    /^## / && in_scope { exit }
    in_scope && index($0, field) == 1 {
      sub(field, "", $0)
      print
      exit
    }
  ' "${context_file}"
}

review_gate_housekeeping() {
  local summary_status="$1"

  if [ "${OMX_AUTO_ARCHIVE:-1}" != "0" ] && [ -x "./scripts/archive-omx-artifacts.sh" ]; then
    echo "[gate] archiving old review artifacts when retention thresholds are exceeded..."
    ./scripts/archive-omx-artifacts.sh
  fi

  if [ "${OMX_AUTO_CHECKPOINT:-1}" != "0" ] && [ -x "./scripts/write-session-checkpoint.sh" ]; then
    echo "[gate] writing session checkpoint..."
    ./scripts/write-session-checkpoint.sh
  fi

  if [ "${OMX_AUTO_KNOWLEDGE_DRAFTS:-1}" != "0" ] && [ -x "./scripts/capture-knowledge-drafts.py" ]; then
    echo "[gate] capturing local knowledge drafts..."
    if ! ./scripts/capture-knowledge-drafts.py --source review-gate --write; then
      echo "[gate] warning: knowledge draft capture failed; review gate result is unchanged"
    fi
  fi

  if [ "${summary_status}" -ne 0 ]; then
    exit "${summary_status}"
  fi
}

verify_only_diff_scope_ready() {
  local context_file policy scopes guard_status phase_status scope
  context_file="$(latest_review_context)"
  [ -n "${context_file}" ] && [ -f "${context_file}" ] || return 1

  policy="$(diff_scope_field "review gate policy")"
  [ "${policy}" = "verify_only" ] || return 1

  scopes="$(diff_scope_field "scopes")"
  [ -n "${scopes}" ] || return 1
  IFS=',' read -r -a scope_parts <<< "${scopes}"
  for scope in "${scope_parts[@]}"; do
    case "${scope}" in
      docs|plans) ;;
      *) return 1 ;;
    esac
  done

  guard_status="$(sed -n 's/^guard_status: //p' "${context_file}" | head -1)"
  case "${guard_status}" in
    ""|clear) ;;
    *) return 1 ;;
  esac

  phase_status="$(sed -n 's/^phase_scope_status: //p' "${context_file}" | head -1)"
  case "${phase_status}" in
    out_of_phase_edit|missing_deferral_record) return 1 ;;
  esac
}

write_verify_only_skip_verdict() {
  local timestamp verdict_file summary_file run_file scopes
  timestamp="$(date +%Y%m%dT%H%M%S)"
  mkdir -p .omx/review-results
  verdict_file=".omx/review-results/review-verdict-${timestamp}.md"
  summary_file=".omx/review-results/review-summary-${timestamp}.md"
  run_file=".omx/review-results/review-run-${timestamp}.md"
  scopes="$(diff_scope_field "scopes")"

  cat > "${verdict_file}" <<EOF
# AI Review Verdict

Generated at: $(date -Iseconds)

## Short Summary

- decision: proceed
- reason: verify_only_diff_scope
- coverage: external_review_skipped
- trust: normal
- active_principal: codex
- missing_or_unusable_reviewers: none
- authority: proceed is not commit approval unless normal verification and user commit approval are also satisfied.

## Final Decision

proceed

## Decision Reason

verify_only_diff_scope

## Review Coverage

external_review_skipped

## Diff Scope

${scopes}

## Reviewer Verdicts

review skipped: docs-only
EOF

  cat > "${summary_file}" <<EOF
# AI Review Summary

review skipped: docs-only

- decision: proceed
- reason: verify_only_diff_scope
- scopes: ${scopes}
EOF

  cat > "${run_file}" <<EOF
# Review Run

Review run id: ${timestamp}
Mode: verify_only_diff_scope
Review context: $(latest_review_context)
EOF

  echo "${verdict_file}"
}

print_diff_scope_gate() {
  local context_file
  context_file="$(latest_review_context)"
  [ -n "${context_file}" ] && [ -f "${context_file}" ] || return 0

  local scope_summary
  scope_summary="$(
    awk '
      /^## Diff Scope Summary$/ { in_scope=1; next }
      /^## / && in_scope { exit }
      in_scope && /^- / { print }
    ' "${context_file}"
  )"
  [ -n "${scope_summary}" ] || return 0

  echo "[gate] consuming diff scope summary..."
  printf '%s\n' "${scope_summary}" | sed 's/^/[gate] /'
}

echo "[gate] running verification..."
env \
  -u RUN_CLAUDE_REVIEW \
  -u REVIEW_CONTEXT_DETAIL \
  -u REVIEW_INCLUDE_UNTRACKED_CONTENT \
  -u REVIEW_UNTRACKED_ALLOWLIST \
  -u REVIEW_UNTRACKED_MANUAL_REVIEWED \
  AI_AUTO_IN_REVIEW_GATE=1 \
  AI_AUTO_VERIFY_SCOPE=product \
  ./scripts/verify.sh 2>&1 | tee "$VERIFY_OUTPUT_FILE"

echo "[gate] collecting review context for diff-scope policy..."
./scripts/collect-review-context.sh
print_diff_scope_gate

if verify_only_diff_scope_ready; then
  echo "[gate] review skipped: docs-only"
  write_verify_only_skip_verdict
  review_gate_housekeeping 0
  echo "[gate] complete"
  exit 0
fi

echo "[gate] running AI reviews..."
set +e
./scripts/run-ai-reviews.sh
review_status=$?
set -e

if [ "${review_status}" -ne 0 ]; then
  if [ "${review_status}" -eq 2 ]; then
    echo "[gate] external AI review prepared; run the generated external reviewer command, then rerun ./scripts/summarize-ai-reviews.sh"
  fi
  exit "${review_status}"
fi

echo "[gate] summarizing AI review verdicts..."
summary_status=0
if ! ./scripts/summarize-ai-reviews.sh; then
  echo "[gate] review gate did not proceed"
  summary_status=1
fi

review_gate_housekeeping "${summary_status}"

echo "[gate] complete"
