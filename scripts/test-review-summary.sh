#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
SUMMARY_SCRIPT="${REPO_ROOT}/scripts/summarize-ai-reviews.sh"
TMP_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_ROOT}"
}

trap cleanup EXIT

write_verdict() {
  local file="$1"
  local verdict="$2"

  printf '# Review\n\n## Verdict\n\n%s\n' "${verdict}" > "${file}"
}

write_skipped() {
  local file="$1"

  printf '# Review\n\nSkipped: disabled for fixture\n' > "${file}"
}

write_fallback_summary() {
  local file="$1"
  local status="$2"

  printf '# Codex Fallback Review\n\n## Status\n\n%s\n' "${status}" > "${file}"
}

write_run_summary() {
  local dir="$1"
  local claude="$2"
  local gemini="$3"
  local architect="$4"
  local test_fallback="$5"
  local fallback_summary="$6"

  cat > "${dir}/review-summary-current.md" <<MSG
# AI Review Summary

## Outputs

- Claude result: ${claude}
- Gemini result: ${gemini}
- Codex architect fallback: ${architect}
- Codex test fallback: ${test_fallback}
- Codex fallback summary: ${fallback_summary}
MSG
}

summary_value() {
  local file="$1"
  local heading="$2"

  awk -v heading="## ${heading}" '
    $0 == heading {
      getline
      while ($0 == "") {
        getline
      }
      print
      exit
    }
  ' "${file}"
}

assert_summary() {
  local name="$1"
  local expected_decision="$2"
  local expected_coverage="$3"
  local expected_status="$4"
  local dir="${TMP_ROOT}/${name}"
  local out_dir="${dir}/out"
  local status=0

  mkdir -p "${out_dir}"

  set +e
  RESULT_DIR="${dir}" OUT_DIR="${out_dir}" "${SUMMARY_SCRIPT}" >/tmp/review-summary-test-output.txt 2>&1
  status=$?
  set -e

  local summary_file
  summary_file="$(find "${out_dir}" -maxdepth 1 -type f -name 'review-verdict-*.md' -print | head -1)"

  if [ -z "${summary_file}" ]; then
    echo "[summary-test] ${name}: summary file was not created"
    cat /tmp/review-summary-test-output.txt
    exit 1
  fi

  local decision coverage
  decision="$(summary_value "${summary_file}" "Final Decision")"
  coverage="$(summary_value "${summary_file}" "Review Coverage")"

  if [ "${decision}" != "${expected_decision}" ]; then
    echo "[summary-test] ${name}: expected decision ${expected_decision}, got ${decision}"
    cat "${summary_file}"
    exit 1
  fi

  if [ "${coverage}" != "${expected_coverage}" ]; then
    echo "[summary-test] ${name}: expected coverage ${expected_coverage}, got ${coverage}"
    cat "${summary_file}"
    exit 1
  fi

  if [ "${status}" -ne "${expected_status}" ]; then
    echo "[summary-test] ${name}: expected exit ${expected_status}, got ${status}"
    cat "${summary_file}"
    exit 1
  fi

  echo "[summary-test] ${name}: pass"
}

case_multi_reviewer() {
  local dir="${TMP_ROOT}/multi_reviewer"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "multi_reviewer" "proceed" "multi_reviewer" 0
}

case_single_external_plus_codex() {
  local dir="${TMP_ROOT}/single_external_plus_codex"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_verdict "${dir}/gemini-review-current.md" "approve"
  write_verdict "${dir}/codex-architect-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "single_external_plus_codex" "proceed_degraded" "single_external_plus_codex_fallback" 0
}

case_codex_only_degraded() {
  local dir="${TMP_ROOT}/codex_only_degraded"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_skipped "${dir}/gemini-review-current.md"
  write_verdict "${dir}/codex-architect-current.md" "approve"
  write_verdict "${dir}/codex-test-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/codex-test-current.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "codex_only_degraded" "proceed_degraded" "codex_only_degraded" 0
}

case_missing_fallback_blocks() {
  local dir="${TMP_ROOT}/missing_fallback_blocks"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_verdict "${dir}/gemini-review-current.md" "approve"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "missing_fallback_blocks" "review_manually" "single_reviewer" 1
}

case_request_changes_blocks() {
  local dir="${TMP_ROOT}/request_changes_blocks"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_verdict "${dir}/gemini-review-current.md" "approve"
  write_verdict "${dir}/codex-architect-current.md" "request_changes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "request_changes_blocks" "review_manually" "single_external_plus_codex_fallback" 1
}

case_stale_fallback_ignored() {
  local dir="${TMP_ROOT}/stale_fallback_ignored"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve"
  write_verdict "${dir}/codex-architect-fallback-stale.md" "request_changes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "stale_fallback_ignored" "proceed" "multi_reviewer" 0
}

case_multi_reviewer
case_single_external_plus_codex
case_codex_only_degraded
case_missing_fallback_blocks
case_request_changes_blocks
case_stale_fallback_ignored

echo "[summary-test] success"
