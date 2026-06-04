#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
SUMMARY_SCRIPT="${REPO_ROOT}/scripts/summarize-ai-reviews.sh"
TMP_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_ROOT}"
}

trap cleanup EXIT

write_verdict() {
  local file="$1"
  local verdict="$2"

  printf '# Review\n\n## Verdict\n\n%s\n\n## Direct File Inspection\n\n- fixture.md\n' "${verdict}" > "${file}"
}

write_skipped() {
  local file="$1"

  printf '# Review\n\nSkipped: disabled for fixture\n' > "${file}"
}

write_failed_with_prompt_verdict() {
  local file="$1"

  cat > "${file}" <<'MSG'
# Reviewer Prompt Echo

## Verdict

approve_with_notes

---

Gemini review failed or timed out.
Exit status: 124
Timeout seconds: 180
RESOURCE_EXHAUSTED
MSG
}

write_failed_with_skipped_prompt() {
  local file="$1"

  cat > "${file}" <<'MSG'
# Reviewer Prompt Echo

Skipped: this text was echoed from prompt context and is not the runner status.

---

Gemini review failed or timed out.
Exit status: 124
Timeout seconds: 180
MSG
}

write_valid_with_failure_words() {
  local file="$1"

  cat > "${file}" <<'MSG'
# Review

## Verdict

approve_with_notes

## Findings

The reviewed change discusses command not found, Too Many Requests, Operation cancelled, and RESOURCE_EXHAUSTED as handled error text.
MSG
}

write_valid_with_fenced_failure_footer() {
  local file="$1"

  cat > "${file}" <<'MSG'
# Review

## Verdict

approve_with_notes

## Findings

The reviewer quotes a runner footer without failing:

```text
Gemini review failed or timed out.
Exit status: 124
Timeout seconds: 180
```
MSG
}

write_prompt_echo_choice_list() {
  local file="$1"

  # A reviewer that echoes the prompt's verdict choice list rather than choosing
  # one. The Verdict section lists every distinct token, which must be treated
  # as ambiguous (no verdict) instead of read as approval.
  cat > "${file}" <<'MSG'
# Reviewer Prompt Echo

## Verdict

approve
approve_with_notes
request_changes

## Direct File Inspection

- fixture.md
MSG
}

write_fenced_only_verdict() {
  local file="$1"

  # The only verdict token appears inside a code fence (e.g. an echoed sample),
  # so it must not be read as the reviewer's real verdict.
  cat > "${file}" <<'MSG'
# Review

## Verdict

```text
approve
```

## Direct File Inspection

- fixture.md
MSG
}

write_valid_request_changes_with_skipped_word() {
  local file="$1"

  cat > "${file}" <<'MSG'
# Review

## Verdict

request_changes

## Findings

The review context mentions Skipped: output from disabled reviewers, but this review itself requested changes.
MSG
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
  local split_manifest="${7:-none}"
  local context_file="${8:-none}"
  local active_principal="${9:-none}"

  cat > "${dir}/review-summary-current.md" <<MSG
# AI Review Summary

## Inputs

- Context: ${context_file}

## Outputs

- Claude result: ${claude}
- Gemini result: ${gemini}
- Codex architect fallback: ${architect}
- Codex test fallback: ${test_fallback}
- Codex fallback summary: ${fallback_summary}
- Split context manifest: ${split_manifest}
MSG
  if [ "${active_principal}" != "none" ]; then
    printf -- '- Active principal: %s\n' "${active_principal}" >> "${dir}/review-summary-current.md"
  fi
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
  local expected_missing="${5:-}"
  local dir="${TMP_ROOT}/${name}"
  local out_dir="${dir}/out"
  local status=0

  mkdir -p "${out_dir}"

  set +e
  REVIEW_UNTRACKED_MANUAL_REVIEWED="${REVIEW_UNTRACKED_MANUAL_REVIEWED_FOR_TEST:-0}" \
    PHASE_SCOPE_MANUAL_REVIEWED="${PHASE_SCOPE_MANUAL_REVIEWED_FOR_TEST:-0}" \
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

  local decision coverage missing trust
  decision="$(summary_value "${summary_file}" "Final Decision")"
  coverage="$(summary_value "${summary_file}" "Review Coverage")"
  missing="$(summary_value "${summary_file}" "Missing Or Unusable Reviewers")"
  trust="$(summary_value "${summary_file}" "Trust Level")"

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

  if [ -n "${expected_missing}" ] && [ "${missing}" != "${expected_missing}" ]; then
    echo "[summary-test] ${name}: expected missing reviewers ${expected_missing}, got ${missing}"
    cat "${summary_file}"
    exit 1
  fi

  if [ -n "${expected_missing}" ] && ! grep -q "Disabled Reviewer Reporting" "${summary_file}"; then
    echo "[summary-test] ${name}: missing disabled reviewer reporting section"
    cat "${summary_file}"
    exit 1
  fi

  if [ "${decision}" = "proceed" ] && { { [ "${coverage}" != "multi_reviewer" ] && [ "${coverage}" != "principal_rotation" ] && [ "${coverage}" != "principal_subagent_substitute" ] && [ "${coverage}" != "principal_rotation_with_substitute" ]; } || [ "${trust}" != "normal" ]; }; then
    echo "[summary-test] ${name}: proceed must require regular review coverage and normal trust"
    cat "${summary_file}"
    exit 1
  fi

  if [ "${decision}" = "proceed_degraded" ] && [ "${trust}" != "degraded" ]; then
    echo "[summary-test] ${name}: proceed_degraded must report degraded trust"
    cat "${summary_file}"
    exit 1
  fi

  grep -q "## Short Summary" "${summary_file}"
  grep -q -- "- decision: ${expected_decision}" "${summary_file}"
  grep -q -- "- reason:" "${summary_file}"
  grep -q -- "- coverage: ${expected_coverage}" "${summary_file}"
  grep -q -- "- trust: ${trust}" "${summary_file}"
  grep -q -- "- authority:" "${summary_file}"

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

case_principal_subagent_substitute() {
  local dir="${TMP_ROOT}/principal_subagent_substitute"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_verdict "${dir}/codex-architect-current.md" "approve"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "principal_subagent_substitute"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "principal_subagent_substitute" "proceed" "principal_subagent_substitute" 0
}

case_principal_subagent_two_substitutes() {
  local dir="${TMP_ROOT}/principal_subagent_two_substitutes"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_skipped "${dir}/gemini-review-current.md"
  write_verdict "${dir}/codex-architect-current.md" "approve"
  write_verdict "${dir}/codex-test-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "principal_subagent_substitute"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/codex-test-current.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "principal_subagent_two_substitutes" "proceed" "principal_subagent_substitute" 0
}

case_principal_inferred_from_run_summary() {
  local dir="${TMP_ROOT}/principal_inferred_from_run_summary"
  mkdir -p "${dir}"

  # With AI_AUTO_PRINCIPAL unset, summarize infers the active principal from the
  # run summary's "Active principal:" line. Here it is claude, so claude is the
  # self-skipped principal and gemini + codex provide principal_rotation coverage.
  write_skipped "${dir}/claude-review-current.md"
  write_verdict "${dir}/gemini-review-current.md" "approve"
  write_verdict "${dir}/codex-architect-current.md" "approve"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" "none" "claude"

  AI_AUTO_PRINCIPAL='' assert_summary "principal_inferred_from_run_summary" "proceed" "principal_rotation" 0
}

case_principal_inferred_unsupported_token_keeps_default() {
  local dir="${TMP_ROOT}/principal_inferred_unsupported_token"
  mkdir -p "${dir}"

  # An unsupported "Active principal:" token must not blank the principal: the
  # default (codex) is kept, so claude-skipped + gemini-approve + codex-approve
  # is read as degraded single-external-plus-codex coverage, not a clean rotation.
  write_skipped "${dir}/claude-review-current.md"
  write_verdict "${dir}/gemini-review-current.md" "approve"
  write_verdict "${dir}/codex-architect-current.md" "approve"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" "none" "bogus-principal"

  AI_AUTO_PRINCIPAL='' assert_summary "principal_inferred_unsupported_token" "proceed_degraded" "single_external_plus_codex_fallback" 0
}

case_principal_rotation_with_substitute() {
  local dir="${TMP_ROOT}/principal_rotation_with_substitute"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_skipped "${dir}/gemini-review-current.md"
  write_verdict "${dir}/codex-architect-current.md" "approve_with_notes"
  write_verdict "${dir}/codex-test-current.md" "approve"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "principal_subagent_substitute"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/codex-test-current.md" \
    "${dir}/codex-fallback-summary-current.md"

  AI_AUTO_PRINCIPAL=claude assert_summary "principal_rotation_with_substitute" "proceed" "principal_rotation_with_substitute" 0
}

case_gemini_principal_rotation_with_substitute() {
  local dir="${TMP_ROOT}/gemini_principal_rotation_with_substitute"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_skipped "${dir}/gemini-review-current.md"
  write_verdict "${dir}/codex-architect-current.md" "approve"
  write_verdict "${dir}/codex-test-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "principal_subagent_substitute"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/codex-test-current.md" \
    "${dir}/codex-fallback-summary-current.md"

  AI_AUTO_PRINCIPAL=gemini assert_summary "gemini_principal_rotation_with_substitute" "proceed" "principal_rotation_with_substitute" 0
}

case_failed_external_codex_only_degraded() {
  local dir="${TMP_ROOT}/failed_external_codex_only_degraded"
  mkdir -p "${dir}"

  write_failed_with_prompt_verdict "${dir}/claude-review-current.md"
  write_failed_with_prompt_verdict "${dir}/gemini-review-current.md"
  write_verdict "${dir}/codex-architect-current.md" "approve"
  write_verdict "${dir}/codex-test-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/codex-test-current.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "failed_external_codex_only_degraded" "proceed_degraded" "codex_only_degraded" 0 "claude:failed, gemini:failed"
}

case_missing_external_codex_only_degraded() {
  local dir="${TMP_ROOT}/missing_external_codex_only_degraded"
  mkdir -p "${dir}"

  write_verdict "${dir}/codex-architect-current.md" "approve"
  write_verdict "${dir}/codex-test-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/missing-claude.md" \
    "${dir}/missing-gemini.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/codex-test-current.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "missing_external_codex_only_degraded" "proceed_degraded" "codex_only_degraded" 0 "claude:missing, gemini:missing"
}

case_partial_codex_fallback_blocks() {
  local dir="${TMP_ROOT}/partial_codex_fallback_blocks"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_skipped "${dir}/gemini-review-current.md"
  write_verdict "${dir}/codex-architect-current.md" "approve"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "partial_codex_fallback_blocks" "blocked" "partial_codex_fallback_only" 1 "claude:skipped, gemini:skipped"
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

case_failed_reviewer_prompt_text_ignored() {
  local dir="${TMP_ROOT}/failed_reviewer_prompt_text_ignored"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_failed_with_prompt_verdict "${dir}/gemini-review-current.md"
  write_verdict "${dir}/codex-test-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/codex-test-current.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "failed_reviewer_prompt_text_ignored" "proceed_degraded" "single_external_plus_codex_fallback" 0
}

case_failed_reviewer_skipped_text_ignored() {
  local dir="${TMP_ROOT}/failed_reviewer_skipped_text_ignored"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_failed_with_skipped_prompt "${dir}/gemini-review-current.md"
  write_verdict "${dir}/codex-test-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/codex-test-current.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "failed_reviewer_skipped_text_ignored" "proceed_degraded" "single_external_plus_codex_fallback" 0 "gemini:failed"
}

case_valid_review_with_failure_words() {
  local dir="${TMP_ROOT}/valid_review_with_failure_words"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_valid_with_failure_words "${dir}/gemini-review-current.md"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "valid_review_with_failure_words" "proceed" "multi_reviewer" 0
}

case_valid_review_with_fenced_failure_footer() {
  local dir="${TMP_ROOT}/valid_review_with_fenced_failure_footer"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_valid_with_fenced_failure_footer "${dir}/gemini-review-current.md"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "valid_review_with_fenced_failure_footer" "proceed" "multi_reviewer" 0
}

case_prompt_echo_choice_list_not_read_as_verdict() {
  local dir="${TMP_ROOT}/prompt_echo_choice_list_not_read_as_verdict"
  mkdir -p "${dir}"

  # Before the parser fix this echoed choice list was read as claude=approve,
  # so the run wrongly became multi_reviewer/proceed/0. With the fix it is
  # ambiguous (no verdict), leaving gemini as the only usable reviewer.
  write_prompt_echo_choice_list "${dir}/claude-review-current.md"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "prompt_echo_choice_list_not_read_as_verdict" "review_manually" "single_reviewer" 1
}

case_fenced_only_verdict_not_read() {
  local dir="${TMP_ROOT}/fenced_only_verdict_not_read"
  mkdir -p "${dir}"

  # The claude verdict token only exists inside a code fence; it must not be
  # read, leaving gemini as the only usable reviewer.
  write_fenced_only_verdict "${dir}/claude-review-current.md"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "fenced_only_verdict_not_read" "review_manually" "single_reviewer" 1
}

case_valid_request_changes_with_skipped_word() {
  local dir="${TMP_ROOT}/valid_request_changes_with_skipped_word"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_skipped "${dir}/gemini-review-current.md"
  write_verdict "${dir}/codex-architect-current.md" "approve_with_notes"
  write_valid_request_changes_with_skipped_word "${dir}/codex-test-current.md"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/codex-test-current.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "valid_request_changes_with_skipped_word" "revise" "codex_only_degraded" 1 "claude:skipped, gemini:skipped"
}

case_split_manifest_approval_blocks_without_synthesis() {
  local dir="${TMP_ROOT}/split_manifest_approval_blocks_without_synthesis"
  mkdir -p "${dir}/split-review-context"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  printf '# Split Review Manifest\n\n## Parts\n\n- %s/split-review-context/part-0001.md\n- %s/split-review-context/part-0002.md\n' "${dir}" "${dir}" > "${dir}/split-review-manifest.md"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "${dir}/split-review-manifest.md"

  assert_summary "split_manifest_approval_blocks_without_synthesis" "review_manually" "multi_reviewer" 1
}

case_split_manifest_prompt_echo_blocks_without_synthesis_section() {
  local dir="${TMP_ROOT}/split_manifest_prompt_echo_blocks_without_synthesis_section"
  mkdir -p "${dir}/split-review-context"

  cat > "${dir}/claude-review-current.md" <<'MSG'
# Prompt Echo

# Review Context Overflow

Return request_changes unless a synthesis review explicitly lists every part used.

## Parts

- /tmp/fixture/split-review-context/part-0001.md
- /tmp/fixture/split-review-context/part-0002.md

## Verdict

approve
MSG
  cp "${dir}/claude-review-current.md" "${dir}/gemini-review-current.md"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  printf '# Split Review Manifest\n\n## Parts\n\n- /tmp/fixture/split-review-context/part-0001.md\n- /tmp/fixture/split-review-context/part-0002.md\n' > "${dir}/split-review-manifest.md"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "${dir}/split-review-manifest.md"

  assert_summary "split_manifest_prompt_echo_blocks_without_synthesis_section" "review_manually" "multi_reviewer" 1
}

case_split_manifest_synthesis_lists_only_blocks() {
  local dir="${TMP_ROOT}/split_manifest_synthesis_lists_only_blocks"
  mkdir -p "${dir}/split-review-context"

  cat > "${dir}/claude-review-current.md" <<'MSG'
# Review

## Verdict

approve

## Synthesis

Processed split-review-context/part-0001.md and split-review-context/part-0002.md.
MSG
  cp "${dir}/claude-review-current.md" "${dir}/gemini-review-current.md"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  printf '# Split Review Manifest\n\n## Parts\n\n- %s/split-review-context/part-0001.md\n- %s/split-review-context/part-0002.md\n' "${dir}" "${dir}" > "${dir}/split-review-manifest.md"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "${dir}/split-review-manifest.md"

  assert_summary "split_manifest_synthesis_lists_only_blocks" "review_manually" "multi_reviewer" 1
}

case_split_manifest_synthesis_allows_approval() {
  local dir="${TMP_ROOT}/split_manifest_synthesis_allows_approval"
  mkdir -p "${dir}/split-review-context"

  cat > "${dir}/claude-review-current.md" <<'MSG'
# Review

## Verdict

approve

## Synthesis

- split-review-context/part-0001.md: reviewed with no blocking findings.
- split-review-context/part-0002.md: reviewed with no blocking findings.
MSG
  cat > "${dir}/gemini-review-current.md" <<'MSG'
# Review

## Verdict

approve_with_notes

## Synthesis

- split-review-context/part-0001.md: reviewed with no blocking findings.
- split-review-context/part-0002.md: reviewed with no blocking findings.
MSG
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  printf '# Split Review Manifest\n\n## Parts\n\n- %s/split-review-context/part-0001.md\n- %s/split-review-context/part-0002.md\n' "${dir}" "${dir}" > "${dir}/split-review-manifest.md"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "${dir}/split-review-manifest.md"

  assert_summary "split_manifest_synthesis_allows_approval" "proceed" "multi_reviewer" 0
}

case_codex_fallback_without_direct_inspection_blocks() {
  local dir="${TMP_ROOT}/codex_fallback_without_direct_inspection_blocks"
  mkdir -p "${dir}"

  write_skipped "${dir}/claude-review-current.md"
  write_skipped "${dir}/gemini-review-current.md"
  printf '# Review\n\n## Verdict\n\napprove\n' > "${dir}/codex-architect-current.md"
  write_verdict "${dir}/codex-test-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "informational_only"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/codex-architect-current.md" \
    "${dir}/codex-test-current.md" \
    "${dir}/codex-fallback-summary-current.md"

  assert_summary "codex_fallback_without_direct_inspection_blocks" "review_manually" "codex_only_degraded" 1 "claude:skipped, gemini:skipped"
}

case_untracked_guard_blocks_omitted_material_artifacts() {
  local dir="${TMP_ROOT}/untracked_guard_blocks_omitted_material_artifacts"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  cat > "${dir}/latest-review-context.md" <<'CTX'
# Review Context

## Untracked Review Guard

guard_status: material_untracked_artifacts_present
manual_review_required: true
manual_review_override: 0
content_included: false
Material untracked review artifacts are present, but content inclusion is disabled.
Set INCLUDE_UNTRACKED_CONTENT=1 or require manual review before commit readiness.
CTX
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" \
    "${dir}/latest-review-context.md"

  assert_summary "untracked_guard_blocks_omitted_material_artifacts" "review_manually" "multi_reviewer" 1
}

case_untracked_guard_blocks_enabled_content_without_manual_review() {
  local dir="${TMP_ROOT}/untracked_guard_blocks_enabled_content_without_manual_review"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  cat > "${dir}/latest-review-context.md" <<'CTX'
# Review Context

## Untracked Review Guard

guard_status: material_untracked_artifacts_present
manual_review_required: true
manual_review_override: 0
content_included: true
Material untracked review artifacts are present and content inclusion is enabled.

## Diff

+Material untracked review artifacts are present, but content inclusion is disabled.
CTX
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" \
    "${dir}/latest-review-context.md"

  assert_summary "untracked_guard_blocks_enabled_content_without_manual_review" "review_manually" "multi_reviewer" 1
}

case_untracked_guard_allows_manual_review_override() {
  local dir="${TMP_ROOT}/untracked_guard_allows_manual_review_override"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  cat > "${dir}/latest-review-context.md" <<'CTX'
# Review Context

## Untracked Review Guard

guard_status: material_untracked_artifacts_present
manual_review_required: true
manual_review_override: 1
content_included: true
Material untracked review artifacts are present and content inclusion is enabled.

## Diff

+Material untracked review artifacts are present, but content inclusion is disabled.
CTX
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" \
    "${dir}/latest-review-context.md"

  REVIEW_UNTRACKED_MANUAL_REVIEWED_FOR_TEST=1 assert_summary "untracked_guard_allows_manual_review_override" "proceed" "multi_reviewer" 0
}

case_phase_scope_guard_blocks_out_of_phase_edits() {
  local dir="${TMP_ROOT}/phase_scope_guard_blocks_out_of_phase_edits"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  cat > "${dir}/latest-review-context.md" <<'CTX'
# Review Context

## Phase Scope Guard

phase: docs
manual_review_override: 0
phase_scope_status: out_of_phase_edit
manual_review_required: true
Out-of-phase changed files require a plan update, deferral record, or manual review.
CTX
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" \
    "${dir}/latest-review-context.md"

  assert_summary "phase_scope_guard_blocks_out_of_phase_edits" "review_manually" "multi_reviewer" 1
}

case_phase_scope_guard_allows_manual_review_override() {
  local dir="${TMP_ROOT}/phase_scope_guard_allows_manual_review_override"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  cat > "${dir}/latest-review-context.md" <<'CTX'
# Review Context

## Phase Scope Guard

phase: docs
manual_review_override: 1
phase_scope_status: out_of_phase_edit
manual_review_required: true
Out-of-phase changed files require a plan update, deferral record, or manual review.
CTX
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" \
    "${dir}/latest-review-context.md"

  PHASE_SCOPE_MANUAL_REVIEWED_FOR_TEST=1 assert_summary "phase_scope_guard_allows_manual_review_override" "proceed" "multi_reviewer" 0
}

case_phase_scope_guard_blocks_missing_deferral_record() {
  local dir="${TMP_ROOT}/phase_scope_guard_blocks_missing_deferral_record"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  cat > "${dir}/latest-review-context.md" <<'CTX'
# Review Context

## Phase Scope Guard

phase: docs
manual_review_override: 0
phase_scope_status: missing_deferral_record
manual_review_required: true
Deferred out-of-phase files require PHASE_SCOPE_DEFERRED_RECORDS entries in path|reason format.
CTX
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" \
    "${dir}/latest-review-context.md"

  assert_summary "phase_scope_guard_blocks_missing_deferral_record" "review_manually" "multi_reviewer" 1
}

case_persona_gate_blocks_missing_policy() {
  local dir="${TMP_ROOT}/persona_gate_blocks_missing_policy"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  cat > "${dir}/latest-review-context.md" <<'CTX'
# Review Context

## Diff Scope Summary

- scopes: scripts
- review intensity hint: strict
- active lenses: policy_compliance,test_strategy
- integrator required: true
- review gate reasons: scopes=scripts; lenses=policy_compliance,test_strategy
- required checks: verify,review-gate
CTX
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" \
    "${dir}/latest-review-context.md"

  assert_summary "persona_gate_blocks_missing_policy" "review_manually" "multi_reviewer" 1
}

case_persona_gate_blocks_malformed_strict_policy() {
  local dir="${TMP_ROOT}/persona_gate_blocks_malformed_strict_policy"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  cat > "${dir}/latest-review-context.md" <<'CTX'
# Review Context

## Diff Scope Summary

- scopes: scripts
- review intensity hint: strict
- active lenses: none
- integrator required: maybe
- review gate policy: strict_gate
- review gate reasons: scopes=scripts; lenses=none
- required checks: verify,review-gate
CTX
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" \
    "${dir}/latest-review-context.md"

  assert_summary "persona_gate_blocks_malformed_strict_policy" "review_manually" "multi_reviewer" 1
}

case_persona_gate_allows_valid_strict_policy() {
  local dir="${TMP_ROOT}/persona_gate_allows_valid_strict_policy"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  cat > "${dir}/latest-review-context.md" <<'CTX'
# Review Context

## Diff Scope Summary

- scopes: scripts
- review intensity hint: strict
- active lenses: policy_compliance,review_taxonomy,test_strategy,integrator
- integrator required: true
- review gate policy: strict_gate
- review gate reasons: scopes=scripts; lenses=policy_compliance,review_taxonomy,test_strategy,integrator
- required checks: verify,review-gate
CTX
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" \
    "${dir}/latest-review-context.md"

  assert_summary "persona_gate_allows_valid_strict_policy" "proceed" "multi_reviewer" 0
}

case_persona_gate_allows_docs_verify_only() {
  local dir="${TMP_ROOT}/persona_gate_allows_docs_verify_only"
  mkdir -p "${dir}"

  write_verdict "${dir}/claude-review-current.md" "approve"
  write_verdict "${dir}/gemini-review-current.md" "approve_with_notes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  cat > "${dir}/latest-review-context.md" <<'CTX'
# Review Context

## Diff Scope Summary

- scopes: docs
- review intensity hint: light
- active lenses: docs_dx
- integrator required: false
- review gate policy: verify_only
- review gate reasons: scopes=docs; lenses=docs_dx
- required checks: verify
CTX
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md" \
    "none" \
    "${dir}/latest-review-context.md"

  assert_summary "persona_gate_allows_docs_verify_only" "proceed" "multi_reviewer" 0
}

case_review_revision_task_created_from_accepted_finding() {
  local dir="${TMP_ROOT}/review_revision_task_created_from_accepted_finding"
  local out_dir="${dir}/out"
  mkdir -p "${dir}" "${out_dir}"

  write_verdict "${dir}/claude-review-current.md" "request_changes"
  write_verdict "${dir}/gemini-review-current.md" "request_changes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  printf 'accepted|R1|claude|scripts/example.sh|Quote path variables safely\n' > "${dir}/accepted-findings.psv"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  set +e
  REVIEW_ACCEPTED_FINDINGS_FILE="${dir}/accepted-findings.psv" \
    REVIEW_REVISION_CYCLE_COUNT=2 \
    RESULT_DIR="${dir}" OUT_DIR="${out_dir}" "${SUMMARY_SCRIPT}" >/tmp/review-summary-test-output.txt 2>&1
  status=$?
  set -e

  if [ "${status}" -ne 1 ]; then
    echo "[summary-test] review_revision_task_created_from_accepted_finding: expected exit 1, got ${status}"
    cat /tmp/review-summary-test-output.txt
    exit 1
  fi

  local task_file
  task_file="$(find "${out_dir}" -maxdepth 1 -type f -name 'review-revision-task-*.md' -print | head -1)"
  if [ -z "${task_file}" ]; then
    echo "[summary-test] review_revision_task_created_from_accepted_finding: missing task file"
    cat /tmp/review-summary-test-output.txt
    exit 1
  fi

  grep -q "status: revision_task_created" "${task_file}"
  grep -q "reviewer: claude" "${task_file}"
  grep -q "file: scripts/example.sh" "${task_file}"
  grep -q "Run ./scripts/verify.sh" "${task_file}"

  echo "[summary-test] review_revision_task_created_from_accepted_finding: pass"
}

case_review_revision_task_stops_at_cycle_limit() {
  local dir="${TMP_ROOT}/review_revision_task_stops_at_cycle_limit"
  local out_dir="${dir}/out"
  mkdir -p "${dir}" "${out_dir}"

  write_verdict "${dir}/claude-review-current.md" "request_changes"
  write_verdict "${dir}/gemini-review-current.md" "request_changes"
  write_fallback_summary "${dir}/codex-fallback-summary-current.md" "none"
  printf 'accepted|R1|gemini|scripts/example.sh|Tighten summary parsing\n' > "${dir}/accepted-findings.psv"
  write_run_summary "${dir}" \
    "${dir}/claude-review-current.md" \
    "${dir}/gemini-review-current.md" \
    "${dir}/missing-architect.md" \
    "${dir}/missing-test.md" \
    "${dir}/codex-fallback-summary-current.md"

  set +e
  REVIEW_ACCEPTED_FINDINGS_FILE="${dir}/accepted-findings.psv" \
    REVIEW_REVISION_CYCLE_COUNT=3 \
    RESULT_DIR="${dir}" OUT_DIR="${out_dir}" "${SUMMARY_SCRIPT}" >/tmp/review-summary-test-output.txt 2>&1
  status=$?
  set -e

  if [ "${status}" -ne 1 ]; then
    echo "[summary-test] review_revision_task_stops_at_cycle_limit: expected exit 1, got ${status}"
    cat /tmp/review-summary-test-output.txt
    exit 1
  fi

  local task_file
  task_file="$(find "${out_dir}" -maxdepth 1 -type f -name 'review-revision-task-*.md' -print | head -1)"
  if [ -z "${task_file}" ]; then
    echo "[summary-test] review_revision_task_stops_at_cycle_limit: missing task file"
    cat /tmp/review-summary-test-output.txt
    exit 1
  fi

  grep -q "status: revision_stop:cycle_limit" "${task_file}"
  grep -q "max_cycles: 2" "${task_file}"

  echo "[summary-test] review_revision_task_stops_at_cycle_limit: pass"
}

case_multi_reviewer
case_single_external_plus_codex
case_codex_only_degraded
case_principal_subagent_substitute
case_principal_subagent_two_substitutes
case_principal_inferred_from_run_summary
case_principal_inferred_unsupported_token_keeps_default
case_principal_rotation_with_substitute
case_gemini_principal_rotation_with_substitute
case_failed_external_codex_only_degraded
case_missing_external_codex_only_degraded
case_partial_codex_fallback_blocks
case_missing_fallback_blocks
case_request_changes_blocks
case_stale_fallback_ignored
case_failed_reviewer_prompt_text_ignored
case_failed_reviewer_skipped_text_ignored
case_valid_review_with_failure_words
case_valid_review_with_fenced_failure_footer
case_prompt_echo_choice_list_not_read_as_verdict
case_fenced_only_verdict_not_read
case_valid_request_changes_with_skipped_word
case_split_manifest_approval_blocks_without_synthesis
case_split_manifest_prompt_echo_blocks_without_synthesis_section
case_split_manifest_synthesis_lists_only_blocks
case_split_manifest_synthesis_allows_approval
case_codex_fallback_without_direct_inspection_blocks
case_untracked_guard_blocks_omitted_material_artifacts
case_untracked_guard_blocks_enabled_content_without_manual_review
case_untracked_guard_allows_manual_review_override
case_phase_scope_guard_blocks_out_of_phase_edits
case_phase_scope_guard_allows_manual_review_override
case_phase_scope_guard_blocks_missing_deferral_record
case_persona_gate_blocks_missing_policy
case_persona_gate_blocks_malformed_strict_policy
case_persona_gate_allows_valid_strict_policy
case_persona_gate_allows_docs_verify_only
case_review_revision_task_created_from_accepted_finding
case_review_revision_task_stops_at_cycle_limit

echo "[summary-test] success"
