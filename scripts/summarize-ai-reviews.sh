#!/usr/bin/env bash
set -euo pipefail

RESULT_DIR="${RESULT_DIR:-.omx/review-results}"
OUT_DIR="${OUT_DIR:-.omx/review-results}"

mkdir -p "${OUT_DIR}"

normalize_principal_runtime() {
  local principal="${1:-${AI_AUTO_PRINCIPAL:-codex}}"

  case "${principal}" in
    ""|codex) echo "codex" ;;
    claude) echo "claude" ;;
    gemini|agy) echo "gemini" ;;
    *)
      echo "unsupported principal runtime: ${principal}" >&2
      return 2
      ;;
  esac
}

ACTIVE_PRINCIPAL="$(normalize_principal_runtime)"

# R20 (HIGH): the ONLY trusted principal source besides an explicit AI_AUTO_PRINCIPAL.
# Echo the launcher-declared principal_runtime iff the evidence file is a valid,
# launcher-owned, workspace-matched, non-symlink principal record (mirrors
# run-ai-reviews.sh's read_valid_launcher_principal); otherwise echo nothing. A
# planted results/summary "Active principal:" line is NEVER consulted, so it can't
# flip the excluded self or steer the quorum. (git rev-parse is not worktree-
# scanning, so it needs no review_git hardening; matches the in-file uses below.)
trusted_launcher_principal() {
  local workspace ev declared
  workspace="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
  ev="${AI_AUTO_PRINCIPAL_EVIDENCE:-${workspace}/.omx/state/principal-runtime/current.env}"
  [ -f "${ev}" ] && [ ! -L "${ev}" ] || return 0
  grep -Fqx "execution_mode=principal" "${ev}" || return 0
  grep -Fqx "source=ai-auto-principal-launcher" "${ev}" || return 0
  grep -Fqx "workspace=${workspace}" "${ev}" || return 0
  declared="$(sed -n 's/^principal_runtime=//p' "${ev}" | head -1)"
  case "${declared}" in codex|claude|gemini) ;; *) return 0 ;; esac
  # Authenticate with the out-of-tree HMAC key (reuse the sourced provenance helper): a planted
  # evidence lacking a framework-written evidence_hmac is untrusted -> echo nothing, so it cannot
  # relabel degraded coverage (proceed_degraded/single_external_plus_codex_fallback) into a
  # normal-trust proceed/principal_rotation. ACTIVE_PRINCIPAL then stays at the full-panel default.
  local stored expected
  stored="$(sed -n 's/^evidence_hmac=//p' "${ev}" | head -1)"
  expected="$(printf 'marker_type=principal_evidence\nprincipal_runtime=%s\nexecution_mode=principal\nsource=ai-auto-principal-launcher\nworkspace=%s\n' "${declared}" "${workspace}" | review_provenance_hmac)"
  [ -n "${stored}" ] && [ -n "${expected}" ] && [ "${stored}" = "${expected}" ] || return 0
  printf '%s\n' "${declared}"
}

latest_file() {
  local pattern="$1"
  find "${RESULT_DIR}" -maxdepth 1 -type f -name "${pattern}" -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -1 \
    | cut -d' ' -f2-
}

# R20 (CRITICAL): consume ONLY the CURRENT run's summary labels. A verdict-bearing
# file is NEVER re-discovered by modification time here: mtime discovery let an
# attacker plant future-mtime result files that summarize selected over the real
# run. REVIEW_RUN_SUMMARY_FILE is bound to the current run below (by run id, not
# mtime). When the bound summary or a label is absent, return empty so the verdict
# fails CLOSED (missing -> blocked) rather than binding to a foreign/stale file.
manifest_file() {
  local label="$1"
  # $2 (legacy mtime fallback pattern) is intentionally ignored: mtime is refused.
  [ -n "${REVIEW_RUN_SUMMARY_FILE:-}" ] && [ -f "${REVIEW_RUN_SUMMARY_FILE}" ] || return 0
  sed -n "s/^- ${label}: //p" "${REVIEW_RUN_SUMMARY_FILE}" | tail -1
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
      # Skip code-fenced blocks so a reviewer that echoes the prompt or a fenced
      # verdict sample is not read as its real verdict.
      /^```/ { in_code = !in_code; next }
      in_code { next }
      # Only the first real (non-fenced) verdict heading is analyzed.
      !seen_section && tolower($0) ~ /^#+[[:space:]]+verdict[[:space:]:.-]*$/ {
        in_verdict = 1; seen_section = 1; next
      }
      in_verdict && /^#+[[:space:]]+/ { in_verdict = 0 }
      in_verdict && /^[[:space:]]*$/ { next }
      in_verdict {
        tok = tolower($0)
        gsub(/[^a-z_]/, "", tok)
        if (tok == "approve" || tok == "approve_with_notes" || tok == "request_changes") {
          if (found != "" && found != tok) { ambiguous = 1 }
          found = tok
        }
      }
      END {
        # An echoed prompt choice list lists several distinct verdicts; that is
        # not a real verdict, so refuse to read it as one (fail safe).
        if (ambiguous) { exit }
        if (found != "") { print found }
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

  if [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ]; then
    case "${ACTIVE_PRINCIPAL}" in
      codex)
        if { is_approval "${claude}" || principal_substitute_covers_claude; } && \
           { is_approval "${gemini}" || principal_substitute_covers_gemini; }; then
          echo "proceed"
          return 0
        fi
        ;;
      claude)
        if codex_principal_approval && { is_approval "${gemini}" || principal_substitute_covers_gemini; }; then
          echo "proceed"
          return 0
        fi
        ;;
      gemini)
        if codex_principal_approval && { is_approval "${claude}" || principal_substitute_covers_claude; }; then
          echo "proceed"
          return 0
        fi
        ;;
    esac
  fi

  case "${ACTIVE_PRINCIPAL}" in
    claude)
      if is_approval "${gemini}" && codex_principal_approval; then
        echo "proceed"
      elif is_usable_review "${gemini}" || codex_principal_usable; then
        echo "proceed_degraded"
      else
        echo "blocked"
      fi
      return 0
      ;;
    gemini)
      if is_approval "${claude}" && codex_principal_approval; then
        echo "proceed"
      elif is_usable_review "${claude}" || codex_principal_usable; then
        echo "proceed_degraded"
      else
        echo "blocked"
      fi
      return 0
      ;;
  esac

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

principal_substitute_covers_claude() {
  [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ] || return 1
  case "${ACTIVE_PRINCIPAL}" in
    codex)
      is_approval "${CODEX_ARCHITECT_VERDICT:-missing}"
      ;;
    gemini)
      is_approval "${CODEX_ARCHITECT_VERDICT:-missing}"
      ;;
    *)
      return 1
      ;;
  esac
}

principal_substitute_covers_gemini() {
  [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ] || return 1
  case "${ACTIVE_PRINCIPAL}" in
    codex|claude)
      is_approval "${CODEX_TEST_VERDICT:-missing}"
      ;;
    *)
      return 1
      ;;
  esac
}

codex_principal_approval() {
  case "${ACTIVE_PRINCIPAL}" in
    gemini)
      if [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ] && ! is_usable_review "${CLAUDE_VERDICT:-missing}"; then
        is_approval "${CODEX_TEST_VERDICT:-missing}"
      else
        is_approval "${CODEX_ARCHITECT_VERDICT:-missing}"
      fi
      ;;
    *)
      is_approval "${CODEX_ARCHITECT_VERDICT:-missing}"
      ;;
  esac
}

codex_principal_usable() {
  case "${ACTIVE_PRINCIPAL}" in
    gemini)
      if [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ] && ! is_usable_review "${CLAUDE_VERDICT:-missing}"; then
        is_usable_review "${CODEX_TEST_VERDICT:-missing}"
      else
        is_usable_review "${CODEX_ARCHITECT_VERDICT:-missing}"
      fi
      ;;
    *)
      is_usable_review "${CODEX_ARCHITECT_VERDICT:-missing}"
      ;;
  esac
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

  if [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ]; then
    case "${ACTIVE_PRINCIPAL}" in
      codex)
        if { is_usable_review "${claude}" || principal_substitute_covers_claude; } && \
           { is_usable_review "${gemini}" || principal_substitute_covers_gemini; }; then
          echo "principal_subagent_substitute"
          return 0
        fi
        ;;
      claude)
        if codex_principal_usable && { is_usable_review "${gemini}" || principal_substitute_covers_gemini; }; then
          echo "principal_rotation_with_substitute"
          return 0
        fi
        ;;
      gemini)
        if codex_principal_usable && { is_usable_review "${claude}" || principal_substitute_covers_claude; }; then
          echo "principal_rotation_with_substitute"
          return 0
        fi
        ;;
    esac
  fi

  case "${ACTIVE_PRINCIPAL}" in
    claude)
      if is_usable_review "${gemini}" && codex_principal_usable; then
        echo "principal_rotation"
        return 0
      fi
      ;;
    gemini)
      if is_usable_review "${claude}" && codex_principal_usable; then
        echo "principal_rotation"
        return 0
      fi
      ;;
  esac

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
  guard_text="$(LC_ALL=C awk '
    # R20 (MED): skip fenced code blocks (mirrors extract_verdict) so a forged
    # "## Untracked Review Guard" section injected inside raw untracked-file bodies
    # (embedded in ```markdown fences by collect-review-context.sh) cannot suppress
    # a real material-untracked block.
    # R24 (HIGH): a fence CLOSES only on a BARE ``` line; a ```<info> line while
    # in-fence is content, not a toggle. Git leaves a printable-ASCII backtick-
    # leading untracked filename (e.g. ```zzz) unquoted inside the ```text listing;
    # under a naive !in_code toggle it desynced in_code and skipped this real (later)
    # heading -> empty guard_text -> bypass. Bare-only close keeps the listing (and
    # any balanced ```markdown forgery) correctly delimited so this heading is read.
    in_code && /^```[[:space:]]*$/ { in_code = 0; next }
    /^```/ { in_code = 1; next }
    in_code { next }
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
  guard_text="$(LC_ALL=C awk '
    # R20 (MED): skip fenced code blocks so a forged "## Phase Scope Guard" section
    # inside raw untracked-file bodies cannot suppress a real out-of-phase block.
    # R24 (HIGH): close a fence only on a BARE ``` line so a backtick-leading
    # untracked filename (```zzz) cannot desync in_code and skip this heading.
    in_code && /^```[[:space:]]*$/ { in_code = 0; next }
    /^```/ { in_code = 1; next }
    in_code { next }
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
  summary_text="$(LC_ALL=C awk '
    # R20 (MED): skip fenced code blocks so a forged "## Diff Scope Summary" section
    # inside raw untracked-file bodies cannot flip the persona-gate classifier.
    # R24 (HIGH): close a fence only on a BARE ``` line so a backtick-leading
    # untracked filename (```zzz) cannot desync in_code across sections.
    in_code && /^```[[:space:]]*$/ { in_code = 0; next }
    /^```/ { in_code = 1; next }
    in_code { next }
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

# F2 fail-open fix: the three block-guards above each `return 1` (no block) when the context file
# is empty/missing, so a context-collection infra failure silently disabled EVERY policy guard and
# let a change that should block `proceed`. Fire ONLY when a REAL review run summary declared a
# `- Context:` line (run-ai-reviews.sh always emits one) whose VALUE is EMPTY/blank -- i.e.
# collect-review-context.sh produced NO file at all (CONTEXT_FILE=""). That is the true infra-
# failure signal, and it is distinct from a run that names its context (present OR a since-removed
# path, which the individual guards handle) so a legitimate run is never over-blocked. Emitting a
# block here routes the verdict to review_manually instead of a silent context-blind proceed.
policy_guard_context_missing_block_reason() {
  local context_file="$1"
  [ -n "${REVIEW_RUN_SUMMARY_FILE:-}" ] && [ -f "${REVIEW_RUN_SUMMARY_FILE}" ] || return 1
  grep -q '^- Context:' "${REVIEW_RUN_SUMMARY_FILE}" || return 1
  [ -z "${context_file}" ] || return 1
  echo "policy_guard_context_missing"
  return 0
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

  if [ "${CODEX_FALLBACK_REQUIRED}" -eq 1 ] || [ "${CODEX_PRINCIPAL_REVIEW_REQUIRED}" -eq 1 ] || [ "${PRINCIPAL_SUBSTITUTE_REQUIRED}" -eq 1 ]; then
    if is_approval "${codex_architect}" && ! fallback_has_direct_file_inspection "${CODEX_ARCHITECT_FALLBACK_FILE}"; then
      if [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ]; then
        echo "principal_subagent_substitute_missing_direct_file_inspection"
      else
        echo "codex_fallback_missing_direct_file_inspection"
      fi
      return 0
    fi
  fi

  if [ "${CODEX_FALLBACK_REQUIRED}" -eq 1 ] || [ "${PRINCIPAL_SUBSTITUTE_REQUIRED}" -eq 1 ]; then
    if is_approval "${codex_test}" && ! fallback_has_direct_file_inspection "${CODEX_TEST_FALLBACK_FILE}"; then
      if [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ]; then
        echo "principal_subagent_substitute_missing_direct_file_inspection"
      else
        echo "codex_fallback_missing_direct_file_inspection"
      fi
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
    if [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ]; then
      echo "principal_subagent_substitute_requested_changes"
    else
      echo "codex_fallback_requested_changes"
    fi
    return 0
  fi

  if [ "${claude}" = "request_changes" ] || [ "${gemini}" = "request_changes" ]; then
    echo "reviewer_requested_changes"
    return 0
  fi

  if [ "${codex_architect}" = "request_changes" ] || [ "${codex_test}" = "request_changes" ]; then
    if [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ]; then
      echo "principal_subagent_substitute_requested_changes"
    else
      echo "codex_fallback_requested_changes"
    fi
    return 0
  fi

  if [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ]; then
    case "${ACTIVE_PRINCIPAL}" in
      codex)
        if { is_approval "${claude}" || principal_substitute_covers_claude; } && \
           { is_approval "${gemini}" || principal_substitute_covers_gemini; }; then
          echo "principal_subagent_substitute_approval"
          return 0
        fi
        ;;
      claude)
        if codex_principal_approval && { is_approval "${gemini}" || principal_substitute_covers_gemini; }; then
          echo "principal_rotation_with_substitute_approval"
          return 0
        fi
        ;;
      gemini)
        if codex_principal_approval && { is_approval "${claude}" || principal_substitute_covers_claude; }; then
          echo "principal_rotation_with_substitute_approval"
          return 0
        fi
        ;;
    esac
  fi

  case "${ACTIVE_PRINCIPAL}" in
    claude)
      if is_approval "${gemini}" && codex_principal_approval; then
        echo "principal_rotation_approval"
        return 0
      fi
      ;;
    gemini)
      if is_approval "${claude}" && codex_principal_approval; then
        echo "principal_rotation_approval"
        return 0
      fi
      ;;
  esac

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
  local codex_architect="${3:-missing}"
  local missing=()

  if [ "${ACTIVE_PRINCIPAL}" != "claude" ]; then
    case "${claude}" in
      skipped|missing|failed|unknown)
        if ! principal_substitute_covers_claude; then
          missing+=("claude:${claude}")
        fi
        ;;
    esac
  fi

  if [ "${ACTIVE_PRINCIPAL}" != "gemini" ]; then
    case "${gemini}" in
      skipped|missing|failed|unknown)
        if ! principal_substitute_covers_gemini; then
          missing+=("gemini:${gemini}")
        fi
        ;;
    esac
  fi

  if [ "${ACTIVE_PRINCIPAL}" != "codex" ]; then
    local codex_reviewer_verdict="${codex_architect}"
    if [ "${ACTIVE_PRINCIPAL}" = "gemini" ] && [ "${PRINCIPAL_SUBSTITUTE_REQUIRED:-0}" -eq 1 ] && ! is_usable_review "${claude}"; then
      codex_reviewer_verdict="${CODEX_TEST_VERDICT:-${codex_test:-missing}}"
    fi
    case "${codex_reviewer_verdict}" in
      skipped|missing|failed|unknown) missing+=("codex:${codex_reviewer_verdict}") ;;
    esac
  fi

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

# >>> review-provenance-shared: keep byte-identical in review-gate.sh and summarize-ai-reviews.sh >>>
# R2 (AI_AUTO_REVIEW_GATE_EFFICIENCY): record the working-tree-inclusive hash of an
# approved change so a byte-identical re-review can skip the full AI panel (the
# measured 61% of verdicts that re-run <15min on an unchanged diff). Recorded only on
# proceed + normal trust; consumed before run-ai-reviews. Every non-exact case fails
# open to a full review.
REVIEW_STATE_DIR="${REVIEW_STATE_DIR:-.omx/reviewer-state}"
REVIEW_PROVENANCE_ENV="${REVIEW_STATE_DIR}/approved-provenance.env"
REVIEW_PROVENANCE_LOG="${REVIEW_STATE_DIR}/approved-provenance.log"

# R5-1/R6: review_git (the hardened-git wrapper) is single-sourced in scripts/git-harden.sh
# and sourced here so review-gate.sh, summarize-ai-reviews.sh, and collect-review-context.sh
# share ONE implementation — no patch-producing call can drift un-hardened. It stays inert to a
# PROJECT-LOCAL `.gitattributes` + `.git/config` diff/filter driver (git's code-exec surface that
# env scrubbing CANNOT reach because it lives IN the repo); callers pass --no-ext-diff/--no-textconv
# on every patch-producing diff and --no-filters on hash-object. Tests that source this block
# standalone set AI_AUTO_GIT_HARDEN_SH to point at scripts/git-harden.sh.
# shellcheck source=scripts/git-harden.sh
. "${AI_AUTO_GIT_HARDEN_SH:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/git-harden.sh}"

# Working-tree-inclusive provenance hash: HEAD commit + staged + unstaged + untracked
# content. Corrects DR1 (a committed-tree SHA would false-skip unstaged edits). Never
# uses `git write-tree`, which would mutate the index.
review_provenance_hash() {
  {
    review_git rev-parse HEAD 2>/dev/null || printf 'NO_HEAD\n'
    printf '\037diff\037\n';   review_git diff --no-ext-diff --no-textconv 2>/dev/null
    printf '\037cached\037\n'; review_git diff --cached --no-ext-diff --no-textconv 2>/dev/null
    printf '\037untracked\037\n'
    # Include each untracked file's PATH next to its blob hash so a same-content
    # rename / path swap changes the hash (content-only would false-match). A nested
    # untracked git repo / worktree lists as ONE boundary DIRECTORY (gitlink): hash-object
    # cannot hash a directory, so its mutating inner content is INVISIBLE and the hash
    # would false-match a prior clean approval. FAIL CLOSED: any other-entry that is a
    # directory or that hash-object cannot hash emits a UNIQUE, un-matchable per-call nonce
    # so a tree carrying such an entry can NEVER carry forward a skip on unreviewed content.
    review_git ls-files --others --exclude-standard -z 2>/dev/null \
      | while IFS= read -r -d '' provenance_file; do
          printf '%s\t' "${provenance_file}"
          if [ -d "${provenance_file}" ] \
             || ! provenance_blob="$(review_git hash-object --no-filters "${provenance_file}" 2>/dev/null)" \
             || [ -z "${provenance_blob}" ]; then
            printf '\037UNHASHABLE\037%s.%s\n' "${RANDOM}${RANDOM}" "$(date +%s%N 2>/dev/null || printf '%s' "${RANDOM}")"
          else
            printf '%s\n' "${provenance_blob}"
          fi
        done
  } | review_git hash-object --stdin
}

review_provenance_head() {
  git rev-parse HEAD 2>/dev/null || true
}

# Active AI_AUTO principal from launcher evidence (empty when unrecorded). Part of the
# flag fingerprint so a skip recorded under one principal does not ride a run with a
# different principal / reviewer rotation.
review_provenance_principal() {
  local ev=".omx/state/principal-runtime/current.env"
  [ -f "${ev}" ] || return 0
  sed -n 's/^principal_runtime=//p' "${ev}" | head -1
}

# Flag fingerprint (D.4): a skip must run under the same untracked-content inclusion,
# allowlist, and active principal as the approving run, else it could ride coverage
# the approval lacked or misreport the reviewer rotation.
review_provenance_flags() {
  printf 'untracked=%s;allowlist=%s;manual=%s;principal=%s' \
    "${REVIEW_INCLUDE_UNTRACKED_CONTENT:-0}" \
    "${REVIEW_UNTRACKED_ALLOWLIST:-}" \
    "${REVIEW_UNTRACKED_MANUAL_REVIEWED:-0}" \
    "$(review_provenance_principal)"
}

# Any persisted reviewer-disable marker (D.9): a stale approval must not ride a
# now-degraded panel.
review_provenance_disabled_present() {
  find "${REVIEW_STATE_DIR}" -maxdepth 1 -type f -name '*.disabled' 2>/dev/null \
    | head -1 | grep -q .
}

# --- Provenance-record AUTHENTICITY (out-of-tree HMAC key) --------------------------------
# The whole project tree (incl. .omx/reviewer-state) is attacker-controlled under the
# tarball/copy threat model, so a record's authenticity CANNOT rest on anything stored in it:
# an attacker precomputes a matching approved_hash and forges every field. Authenticity is
# bound to an HMAC keyed by a secret held OUTSIDE any project tree. Path precedence:
# $AI_AUTO_PROVENANCE_KEY_FILE (tests) -> $AI_AUTO_HOME/.provenance-key -> ~/.config/ai-auto/
# provenance.key. An in-tree path (.omx/.git) is REFUSED, so the secret is never written where
# the attacker-controlled tree can read it, and an attacker who owns the tree cannot forge it.
review_provenance_key_file() {
  if [ -n "${AI_AUTO_PROVENANCE_KEY_FILE:-}" ]; then printf '%s\n' "${AI_AUTO_PROVENANCE_KEY_FILE}"
  elif [ -n "${AI_AUTO_HOME:-}" ]; then printf '%s/.provenance-key\n' "${AI_AUTO_HOME}"
  else printf '%s/.config/ai-auto/provenance.key\n' "${HOME:-/root}"; fi
}

# Refuse an in-tree key path via realpath+toplevel (NOT a fragile substring). Returns 0
# (=in-tree, REFUSE) when the candidate key path — after resolving relative paths, `..`, and
# symlinks — lands INSIDE the project's git toplevel, where the attacker-controlled tree could
# read/forge the secret; callers then fail closed (treat as missing key => full review). A
# substring guard (*"/.omx/"*|*"/.git/"*) missed a RELATIVE path (.omx/x.key, no leading slash),
# a `..` escape, and any in-tree path OUTSIDE .omx/.git, so the stated "in-tree key is REFUSED"
# invariant was FALSE. Out-of-tree keys ($AI_AUTO_HOME/.provenance-key, ~/.config/ai-auto, an
# out-of-tree $AI_AUTO_PROVENANCE_KEY_FILE) resolve OUTSIDE the toplevel => return 1 (allowed).
# git is routed through hardened review_git (drift-guard: no bare git).
review_provenance_key_in_tree() {
  local keyfile top rp
  keyfile="$(review_provenance_key_file)"
  top="$(review_git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "${top}" ] || return 1
  top="$(realpath -m -- "${top}" 2>/dev/null)" || return 1
  rp="$(realpath -m -- "${keyfile}" 2>/dev/null)" || return 1
  case "${rp}/" in "${top}/"*) return 0 ;; esac
  return 1
}

# Generate the key once (0600) if absent-OR-EMPTY. Refuses any in-tree path (realpath inside
# toplevel). CRITICAL fail-open fix: `> "${keyfile}"` truncates the target to 0 bytes BEFORE
# openssl execs, so a missing/failing openssl (minimal container, PATH gap, transient) left a
# persistent 0-byte key that later `[ -f ]` checks accepted as valid => HMAC keyed by NO secret
# => an attacker who owns the tree could forge a valid approved_hmac. Fix: presence test is now
# `[ -s ]` (empty key == absent), and the secret is written to a SAME-DIR mktemp and mv'd into
# place ONLY after confirming it is non-empty, so a 0-byte key is never published at keyfile.
review_provenance_ensure_key() {
  local keyfile dir tmp
  keyfile="$(review_provenance_key_file)"
  review_provenance_key_in_tree && return 1
  [ -s "${keyfile}" ] && return 0
  dir="$(dirname "${keyfile}")"
  mkdir -p "${dir}" 2>/dev/null || return 1
  tmp="$(mktemp "${dir}/.provkey.XXXXXX" 2>/dev/null)" || return 1
  if ( umask 077; openssl rand -hex 32 > "${tmp}" ) 2>/dev/null && [ -s "${tmp}" ]; then
    chmod 0600 "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${keyfile}" 2>/dev/null && return 0
  fi
  rm -f "${tmp}" 2>/dev/null
  return 1
}

# HMAC-SHA256 of stdin keyed by the out-of-tree secret (key read from FILE, never argv/env, so
# it is not exposed on the process table). Empty output when the key/tool is unavailable or the
# path is in-tree -> the caller fails closed (no valid HMAC => full review), never a silent skip.
# Read-side hardening: an EMPTY key (`[ -s ]`), a key not owned by us (`[ -O ]`), or a
# group/other-accessible key (mode & 077) is UNTRUSTED (planted/leaked) -> empty output.
review_provenance_hmac() {
  local keyfile mode
  keyfile="$(review_provenance_key_file)"
  review_provenance_key_in_tree && return 0
  [ -s "${keyfile}" ] || return 0
  [ -O "${keyfile}" ] || return 0
  mode="$(stat -c '%a' "${keyfile}" 2>/dev/null || echo 777)"
  [ $(( 0${mode} & 077 )) -eq 0 ] || return 0
  AI_AUTO_PROV_KEYFILE="${keyfile}" python3 -c 'import hmac,hashlib,os,sys; k=open(os.environ["AI_AUTO_PROV_KEYFILE"],"rb").read(); sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())' 2>/dev/null
}

# Record an approved provenance record. Atomic (mktemp+mv) so a concurrent session
# never reads a half-written env. Caller gates on proceed + normal trust.
review_provenance_record() {
  local hash head flags ts tmp rec
  hash="$(review_provenance_hash)"
  head="$(review_provenance_head)"
  flags="$(review_provenance_flags)"
  ts="$(date -Iseconds)"
  # `|| return 0`: if no out-of-tree key can be ensured (in-tree path refused, or key creation
  # failed) do NOT write a record — any record we could write would carry an empty/invalid HMAC
  # and force a full review anyway, and a bare call would abort this proceed under `set -e`.
  review_provenance_ensure_key || return 0
  mkdir -p "${REVIEW_STATE_DIR}"
  tmp="$(mktemp "${REVIEW_STATE_DIR}/.approved-provenance.XXXXXX")" || return 0
  # Trap-clean the random-suffixed temp so a SIGINT/SIGTERM/timeout (the gate is exactly what
  # gets Ctrl-C'd/timed-out) in the mktemp..mv window strands NO litter in .omx/reviewer-state
  # (the suffix is NOT pid-bounded, so it would accumulate unboundedly). RETURN covers every
  # function-exit path; INT/TERM clean then honor the signal (exit) so a real interrupt is not
  # masked. All cleared after the atomic mv (temp path is gone -> the rm becomes a harmless no-op).
  trap 'rm -f "${tmp:-}"' RETURN
  trap 'rm -f "${tmp:-}"; exit 130' INT
  trap 'rm -f "${tmp:-}"; exit 143' TERM
  # Canonical record + an HMAC over it keyed by the OUT-OF-TREE secret. The attacker owns the
  # tree and can forge every field incl. a matching approved_hash, but NOT this HMAC, so a
  # forged approved-provenance.env cannot pass review_provenance_authentic (=> full review).
  rec="$(printf 'marker_type=review_provenance\napproved_hash=%s\napproved_head=%s\napproved_flags=%s\napproved_at=%s\n' \
    "${hash}" "${head}" "${flags}" "${ts}")"
  {
    printf '%s\n' "${rec}"
    printf 'approved_hmac=%s\n' "$(printf '%s' "${rec}" | review_provenance_hmac)"
  } > "${tmp}"
  mv -f "${tmp}" "${REVIEW_PROVENANCE_ENV}"
  trap - RETURN INT TERM
  printf '%s\t%s\t%s\t%s\n' "${ts}" "${head:-NO_HEAD}" "${hash}" "${flags}" >> "${REVIEW_PROVENANCE_LOG}"
}

review_provenance_field() {
  local key="$1"
  [ -f "${REVIEW_PROVENANCE_ENV}" ] || return 0
  sed -n "s/^${key}=//p" "${REVIEW_PROVENANCE_ENV}" | head -1
}

# Mirror run-ai-reviews.sh launcher-evidence validation so a provenance skip never
# rides stale / manual / mismatched / symlinked principal evidence (it skips
# run-ai-reviews, which is where that guard otherwise runs). Returns 0 only for a
# principal state run-ai-reviews would also accept; else the skip fails open to full.
review_provenance_principal_evidence_ok() {
  local workspace ev declared explicit _pe_stored _pe_expected
  workspace="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
  ev="${AI_AUTO_PRINCIPAL_EVIDENCE:-${workspace}/.omx/state/principal-runtime/current.env}"
  explicit="${AI_AUTO_PRINCIPAL:-}"
  if [ -f "${ev}" ]; then
    [ ! -L "${ev}" ] || return 1
    grep -Fqx "execution_mode=principal" "${ev}" || return 1
    grep -Fqx "source=ai-auto-principal-launcher" "${ev}" || return 1
    grep -Fqx "workspace=${workspace}" "${ev}" || return 1
    declared="$(sed -n 's/^principal_runtime=//p' "${ev}" | head -1)"
    case "${declared}" in codex|claude|gemini) ;; *) return 1 ;; esac
    [ -z "${explicit}" ] || [ "${explicit}" = "${declared}" ] || return 1
    # Out-of-tree-keyed HMAC: a planted evidence lacking a framework-written evidence_hmac is a
    # forgery -> a provenance skip must not ride it (fail open to full, as an absent file would).
    _pe_stored="$(sed -n 's/^evidence_hmac=//p' "${ev}" | head -1)"
    _pe_expected="$(printf 'marker_type=principal_evidence\nprincipal_runtime=%s\nexecution_mode=principal\nsource=ai-auto-principal-launcher\nworkspace=%s\n' "${declared}" "${workspace}" | review_provenance_hmac)"
    [ -n "${_pe_stored}" ] && [ -n "${_pe_expected}" ] && [ "${_pe_stored}" = "${_pe_expected}" ] || return 1
    return 0
  fi
  # No evidence: a non-codex explicit principal would make run-ai-reviews fail, so a
  # skip in that state would bypass the failure.
  case "${explicit}" in ""|codex) return 0 ;; *) return 1 ;; esac
}

# Verify a record's out-of-tree-keyed HMAC. Returns 0 ONLY when a key exists and the stored
# approved_hmac equals a fresh HMAC over the record's canonical fields; else 1 (missing key,
# missing/forged HMAC, tool absent, in-tree key path) -> caller forces a full review. An
# attacker who owns the tree cannot produce a valid HMAC without the out-of-tree key.
review_provenance_authentic() {
  local keyfile stored rec expected
  keyfile="$(review_provenance_key_file)"
  review_provenance_key_in_tree && return 1
  [ -s "${keyfile}" ] || return 1
  stored="$(review_provenance_field approved_hmac)"
  [ -n "${stored}" ] || return 1
  rec="$(printf 'marker_type=review_provenance\napproved_hash=%s\napproved_head=%s\napproved_flags=%s\napproved_at=%s\n' \
    "$(review_provenance_field approved_hash)" \
    "$(review_provenance_field approved_head)" \
    "$(review_provenance_field approved_flags)" \
    "$(review_provenance_field approved_at)")"
  expected="$(printf '%s' "${rec}" | review_provenance_hmac)"
  [ -n "${expected}" ] || return 1
  [ "${expected}" = "${stored}" ]
}

# Echoes "skip" (exact match, same flags, no disabled reviewer → carry prior verdict)
# or "full" (no record / forged-or-unauthenticated record / changed tree / flag mismatch /
# disabled present). Delta is deferred until collect-review-context honors a base, so every
# non-exact case is a full review.
review_provenance_decision() {
  local approved_hash approved_flags cur_hash cur_flags
  approved_hash="$(review_provenance_field approved_hash)"
  if [ -z "${approved_hash}" ]; then printf 'full\n'; return 0; fi
  # Authenticity FIRST: a record without a valid out-of-tree-keyed HMAC is forged / legacy —
  # force a full review (never carry it forward onto an unreviewed, attacker-controlled tree).
  if ! review_provenance_authentic; then printf 'full\n'; return 0; fi
  cur_hash="$(review_provenance_hash)"
  if [ "${cur_hash}" != "${approved_hash}" ]; then printf 'full\n'; return 0; fi
  approved_flags="$(review_provenance_field approved_flags)"
  cur_flags="$(review_provenance_flags)"
  if [ "${cur_flags}" != "${approved_flags}" ]; then printf 'full\n'; return 0; fi
  if review_provenance_disabled_present; then printf 'full\n'; return 0; fi
  if ! review_provenance_principal_evidence_ok; then printf 'full\n'; return 0; fi
  printf 'skip\n'
}
# <<< review-provenance-shared <<<

write_review_revision_task() {
  local timestamp="$1"
  local findings_file="${REVIEW_ACCEPTED_FINDINGS_FILE:-}"
  local cycle_count="${REVIEW_REVISION_CYCLE_COUNT:-1}"
  local verification_passed="${REVIEW_REVISION_VERIFICATION_PASSED:-1}"
  local changed_diff="${REVIEW_REVISION_CHANGED_DIFF:-1}"
  local targeted_recheck="${REVIEW_TARGETED_RECHECK:-1}"
  local targeted_scope_ok="${REVIEW_TARGETED_RECHECK_SCOPE_OK:-1}"
  local targeted_evidence="${REVIEW_TARGETED_RECHECK_EVIDENCE:-}"
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

  if [ "${targeted_recheck}" = "1" ] && [ "${targeted_scope_ok}" != "1" ]; then
    cat > "${task_file}" <<TASK
# Review Revision Task

status: revision_manual_review
reason: targeted_recheck_scope_expanded
targeted_recheck: requested
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
targeted_recheck: ${targeted_recheck}
targeted_recheck_evidence: ${targeted_evidence:-none}

## Scope

Apply only the accepted structured reviewer findings listed below. Do not apply
free-text, rejected, proposed, fixed, or deferred findings as automatic work.

## Accepted Findings

${accepted_lines}

## Required Checks

- Run ./scripts/verify.sh after the revision.
- Run a second review pass only when the revision produced a changed diff.
- Use targeted recheck only for the accepted finding scope listed above; if the
  changed files exceed that scope, run the full review gate or stop for manual
  review.
- Stop for manual decision if verification fails repeatedly, reviewer output is
  unclear, reviewers disagree, or a third automatic revision cycle would start.
TASK

  echo "${task_file}"
}

# R20 (CRITICAL): bind the verdict-bearing summary to the CURRENT run. When the run
# id is known (the gate and the external runner always export REVIEW_RUN_ID) select
# the summary by run id — NEVER by modification time — so a planted future-mtime
# summary for a different / unknown run id can't be chosen. If that file is absent,
# leave the binding empty so every verdict reads "missing" and the gate fails CLOSED.
# The gate also PURGES foreign/stale entries from the results dir at run start, so a
# planted set cannot survive into (or be named as) the current run.
if [ -z "${REVIEW_RUN_SUMMARY_FILE:-}" ]; then
  if [ -n "${REVIEW_RUN_ID:-}" ]; then
    REVIEW_RUN_SUMMARY_FILE="${RESULT_DIR}/review-summary-${REVIEW_RUN_ID}.md"
    [ -f "${REVIEW_RUN_SUMMARY_FILE}" ] || REVIEW_RUN_SUMMARY_FILE=""
  else
    # Legacy / isolated invocation with no run id: the caller owns RESULT_DIR (single-
    # run fixtures, archive housekeeping) so its sole summary is the current run's.
    REVIEW_RUN_SUMMARY_FILE="$(latest_file 'review-summary-*.md')"
  fi
fi

# R20 (HIGH): derive the active principal from a TRUSTED source in strict precedence:
#   1. explicit AI_AUTO_PRINCIPAL (already applied to ACTIVE_PRINCIPAL above);
#   2. the validated launcher-owned principal-runtime evidence file;
#   3. only then the "Active principal:" line of the CURRENT-RUN-BOUND summary.
# The old code read (3) from an mtime-selected summary, so a planted future-mtime
# results file could inject "Active principal: claude" and flip the excluded self /
# steer the quorum. (3) is now safe ONLY because the summary is bound to this run
# (run-id selected + results dir purged by the gate) and is written by run-ai-reviews
# from ITS trusted principal derivation, never from an attacker file. If none of the
# sources resolve, ACTIVE_PRINCIPAL stays at the default codex, which requires the
# FULL external panel (claude AND gemini) and so fails SAFE (no reduced quorum).
if [ -z "${AI_AUTO_PRINCIPAL:-}" ]; then
  INFERRED_ACTIVE_PRINCIPAL="$(trusted_launcher_principal)"
  if [ -z "${INFERRED_ACTIVE_PRINCIPAL}" ] && \
     [ -n "${REVIEW_RUN_SUMMARY_FILE:-}" ] && [ -f "${REVIEW_RUN_SUMMARY_FILE}" ]; then
    # Strip a trailing CR so a CRLF-written summary does not yield an unsupported token.
    INFERRED_ACTIVE_PRINCIPAL="$(sed -n 's/^- Active principal: //p' "${REVIEW_RUN_SUMMARY_FILE}" | tail -1 | tr -d '\r')"
  fi
  if [ -n "${INFERRED_ACTIVE_PRINCIPAL}" ]; then
    if INFERRED_NORMALIZED_PRINCIPAL="$(normalize_principal_runtime "${INFERRED_ACTIVE_PRINCIPAL}" 2>/dev/null)"; then
      ACTIVE_PRINCIPAL="${INFERRED_NORMALIZED_PRINCIPAL}"
    fi
  fi
fi
REVIEW_CONTEXT_FILE="$(manifest_file 'Context' 'latest-review-context.md')"
CLAUDE_FILE="$(manifest_file 'Claude result' 'claude-review-*.md')"
GEMINI_FILE="$(manifest_file 'Gemini result' 'gemini-review-*.md')"
CODEX_ARCHITECT_FALLBACK_FILE="$(manifest_file 'Codex architect fallback' 'codex-architect-fallback-*.md')"
CODEX_TEST_FALLBACK_FILE="$(manifest_file 'Codex test fallback' 'codex-test-fallback-*.md')"
CODEX_FALLBACK_SUMMARY_FILE="$(manifest_file 'Principal review summary' 'codex-fallback-summary-*.md')"
if [ -z "${CODEX_FALLBACK_SUMMARY_FILE}" ]; then
  CODEX_FALLBACK_SUMMARY_FILE="$(manifest_file 'Codex fallback summary' 'codex-fallback-summary-*.md')"
fi
SPLIT_CONTEXT_MANIFEST_FILE="$(manifest_file 'Split context manifest' 'split-review-manifest.md')"
CODEX_FALLBACK_REQUIRED=0
CODEX_PRINCIPAL_REVIEW_REQUIRED=0
PRINCIPAL_SUBSTITUTE_REQUIRED=0
if [ -n "${CODEX_FALLBACK_SUMMARY_FILE}" ] && [ -f "${CODEX_FALLBACK_SUMMARY_FILE}" ] && grep -q '^informational_only$' "${CODEX_FALLBACK_SUMMARY_FILE}"; then
  CODEX_FALLBACK_REQUIRED=1
fi
if [ -n "${CODEX_FALLBACK_SUMMARY_FILE}" ] && [ -f "${CODEX_FALLBACK_SUMMARY_FILE}" ] && grep -q '^principal_subagent_substitute$' "${CODEX_FALLBACK_SUMMARY_FILE}"; then
  PRINCIPAL_SUBSTITUTE_REQUIRED=1
fi
if [ "${ACTIVE_PRINCIPAL}" != "codex" ]; then
  CODEX_PRINCIPAL_REVIEW_REQUIRED=1
fi

CLAUDE_VERDICT="$(extract_verdict "${CLAUDE_FILE}")"
GEMINI_VERDICT="$(extract_verdict "${GEMINI_FILE}")"
CODEX_ARCHITECT_VERDICT="missing"
CODEX_TEST_VERDICT="missing"
if [ "${CODEX_FALLBACK_REQUIRED}" -eq 1 ] || [ "${CODEX_PRINCIPAL_REVIEW_REQUIRED}" -eq 1 ] || [ "${PRINCIPAL_SUBSTITUTE_REQUIRED}" -eq 1 ]; then
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
CONTEXT_MISSING_BLOCK_REASON="$(policy_guard_context_missing_block_reason "${REVIEW_CONTEXT_FILE}" || true)"
if [ -n "${CONTEXT_MISSING_BLOCK_REASON}" ]; then
  if [ "${POLICY_BLOCK_REASON}" = "none" ]; then
    POLICY_BLOCK_REASON="${CONTEXT_MISSING_BLOCK_REASON}"
  else
    POLICY_BLOCK_REASON="${POLICY_BLOCK_REASON},${CONTEXT_MISSING_BLOCK_REASON}"
  fi
fi
if [ "${POLICY_BLOCK_REASON}" != "none" ] && { [ "${FINAL_DECISION}" = "proceed" ] || [ "${FINAL_DECISION}" = "proceed_degraded" ]; }; then
  FINAL_DECISION="review_manually"
  DECISION_REASON="${POLICY_BLOCK_REASON}"
fi
MISSING_REVIEWERS="$(missing_reviewers "${CLAUDE_VERDICT}" "${GEMINI_VERDICT}" "${CODEX_ARCHITECT_VERDICT}")"
CODEX_FALLBACK_COVERAGE="none"
if [ "${PRINCIPAL_SUBSTITUTE_REQUIRED}" -eq 1 ]; then
  CODEX_FALLBACK_COVERAGE="principal_subagent_substitute_degraded"
elif [ "${CODEX_PRINCIPAL_REVIEW_REQUIRED}" -eq 1 ] && is_usable_review "${CODEX_ARCHITECT_VERDICT}"; then
  CODEX_FALLBACK_COVERAGE="principal_rotation_not_fallback"
elif is_usable_review "${CODEX_ARCHITECT_VERDICT}" || is_usable_review "${CODEX_TEST_VERDICT}"; then
  CODEX_FALLBACK_COVERAGE="available_degraded_informational_only"
elif [ "${CODEX_FALLBACK_REQUIRED}" -eq 1 ]; then
  CODEX_FALLBACK_COVERAGE="required_but_unusable"
fi

# Substitute-trust honesty: coverage that relies on the active principal's own
# subagent substitute for a decision-relevant lane is NOT independent external
# review (if both externals were usable, multi_reviewer fires first). Downgrade
# proceed -> proceed_degraded so it is reported as degraded trust, never as normal
# multi-reviewer trust.
if [ "${FINAL_DECISION}" = "proceed" ] && { [ "${REVIEW_COVERAGE}" = "principal_subagent_substitute" ] || [ "${REVIEW_COVERAGE}" = "principal_rotation_with_substitute" ]; }; then
  FINAL_DECISION="proceed_degraded"
fi

# Verify-failure override: review-gate proceeded past a failed verify.sh only with
# a recorded reason + approver. The marker reaches us via env (inline gate) OR via
# .omx/state/verify-override.env (the external-runner path, where exported env does
# not cross the generated runner boundary). Either source: never a clean proceed.
VERIFY_OVERRIDE_ACTIVE=0
VERIFY_OVERRIDE_BY=""
VERIFY_OVERRIDE_REASON=""
if [ "${AI_AUTO_VERIFY_FAILED_OVERRIDE:-0}" = "1" ]; then
  VERIFY_OVERRIDE_ACTIVE=1
  VERIFY_OVERRIDE_BY="${AI_AUTO_VERIFY_FAILED_OVERRIDE_BY:-}"
  VERIFY_OVERRIDE_REASON="${AI_AUTO_VERIFY_FAILED_OVERRIDE_REASON:-}"
elif [ -f .omx/state/verify-override.env ]; then
  VERIFY_OVERRIDE_ACTIVE=1
  VERIFY_OVERRIDE_BY="$(sed -n 's/^approved_by=//p' .omx/state/verify-override.env 2>/dev/null | head -n 1)"
  VERIFY_OVERRIDE_REASON="$(sed -n 's/^reason=//p' .omx/state/verify-override.env 2>/dev/null | head -n 1)"
fi
if [ "${VERIFY_OVERRIDE_ACTIVE}" = "1" ] && [ "${FINAL_DECISION}" = "proceed" ]; then
  FINAL_DECISION="proceed_degraded"
fi

VERIFY_OVERRIDE_FIELD="none"
if [ "${VERIFY_OVERRIDE_ACTIVE}" = "1" ]; then
  VERIFY_OVERRIDE_FIELD="verify_failed; approved_by=${VERIFY_OVERRIDE_BY:-unknown}; reason=${VERIFY_OVERRIDE_REASON:-unspecified}"
fi

TRUST_LEVEL="degraded"
if { [ "${REVIEW_COVERAGE}" = "multi_reviewer" ] || [ "${REVIEW_COVERAGE}" = "principal_rotation" ]; } && [ "${FINAL_DECISION}" = "proceed" ]; then
  TRUST_LEVEL="normal"
elif [ "${FINAL_DECISION}" = "blocked" ] || [ "${FINAL_DECISION}" = "revise" ] || [ "${FINAL_DECISION}" = "review_manually" ]; then
  TRUST_LEVEL="blocked_or_needs_attention"
fi

# U1 fail-closed self-check (audit AI_AUTO_OVERENGINEERING_AUDIT_2026-06-05 lever U1).
# The review_gate_short_summary contract is the single validated spec for this
# summary's shape; run it against the record we are about to emit so an internally
# inconsistent verdict (field drift / future bug) blocks instead of being published.
# In normal operation the contract mirrors this script's own invariants, so it never
# false-blocks. Fail OPEN only when python3 or the contract file is missing (minimal
# test fixtures) -- never on an actual rejection.
SELF_DEMO_CONTRACTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/self_demo_contracts.py"
if command -v python3 >/dev/null 2>&1 && [ -f "${SELF_DEMO_CONTRACTS}" ]; then
  SUMMARY_CONTRACT_DEGRADED=""
  [ "${FINAL_DECISION}" = "proceed_degraded" ] && SUMMARY_CONTRACT_DEGRADED="1"
  SUMMARY_RECORD_JSON="$(
    SUM_FD="${FINAL_DECISION}" \
    SUM_DR="${DECISION_REASON}" \
    SUM_RC="${REVIEW_COVERAGE}" \
    SUM_TL="${TRUST_LEVEL}" \
    SUM_MR="${MISSING_REVIEWERS}" \
    SUM_DEGRADED="${SUMMARY_CONTRACT_DEGRADED}" \
    python3 - <<'PY'
import json, os
d = {
    "final_decision": os.environ["SUM_FD"],
    "decision_reason": os.environ["SUM_DR"],
    "review_coverage": os.environ["SUM_RC"],
    "trust_level": os.environ["SUM_TL"],
    "missing_or_unusable_reviewers": os.environ["SUM_MR"],
    "authority_statement": os.environ["SUM_FD"]
    + " is not commit approval unless normal verification and user commit approval are also satisfied.",
}
if os.environ.get("SUM_DEGRADED"):
    d["degraded_trust_reported"] = True
    d["missing_reviewers_reported"] = True
print(json.dumps(d))
PY
  )"
  set +e
  SUMMARY_CONTRACT_ERR="$(printf '%s' "${SUMMARY_RECORD_JSON}" | python3 "${SELF_DEMO_CONTRACTS}" review_gate_short_summary 2>&1 1>/dev/null)"
  SUMMARY_CONTRACT_RC=$?
  set -e
  # F4 fail-open fix: rc==0 is the ONLY pass. rc==1 is a contract violation; any OTHER nonzero rc
  # (2+ = argparse/uncaught exception/crash) previously left the verdict UNCHANGED (fail-open) —
  # a crashed self-check silently vanished. Treat rc NOT in {0} as a block (fail-closed).
  if [ "${SUMMARY_CONTRACT_RC}" -ne 0 ]; then
    FINAL_DECISION="review_manually"
    if [ "${SUMMARY_CONTRACT_RC}" -eq 1 ]; then
      DECISION_REASON="summary_contract_violation:${SUMMARY_CONTRACT_ERR}"
    else
      DECISION_REASON="summary_contract_error_rc${SUMMARY_CONTRACT_RC}:${SUMMARY_CONTRACT_ERR}"
    fi
    TRUST_LEVEL="blocked_or_needs_attention"
  fi
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
- active_principal: ${ACTIVE_PRINCIPAL}
- missing_or_unusable_reviewers: ${MISSING_REVIEWERS}
- verify_override: ${VERIFY_OVERRIDE_FIELD}
- authority: ${FINAL_DECISION} is not commit approval unless normal verification and user commit approval are also satisfied.

## Final Decision

${FINAL_DECISION}

## Decision Reason

${DECISION_REASON}

## Review Coverage

${REVIEW_COVERAGE}

## Active Principal

${ACTIVE_PRINCIPAL}

## Trust Level

${TRUST_LEVEL}

## Missing Or Unusable Reviewers

${MISSING_REVIEWERS}

## Principal/Codex Review Coverage

${CODEX_FALLBACK_COVERAGE}

When the active principal is not Codex, Codex coverage may be a normal
principal-rotation reviewer lane instead of degraded fallback coverage.
When a reviewer is unavailable, an approval from the active principal's
subagent substitute is degraded coverage, not independent external review. It is
reported as proceed_degraded with degraded trust even when direct file inspection
is present.

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

Skipped external reviewers are covered by the active principal's subagent
substitute as degraded coverage (not independent external review), or reported as
degraded coverage when no valid substitute exists. A reviewer skipped by \`RUN_CLAUDE_REVIEW=0\` or \`RUN_GEMINI_REVIEW=0\`
is an intentional user opt-out, not an external reviewer failure. A reviewer
skipped because of a persisted .omx/reviewer-state marker remains disabled until
the reset hint is run.

## Reviewer Verdicts

| Reviewer | Verdict | File |
|---|---|---|
| Claude | ${CLAUDE_VERDICT} | ${CLAUDE_FILE:-missing} |
| Gemini | ${GEMINI_VERDICT} | ${GEMINI_FILE:-missing} |

## Principal Substitute / Codex Reviews

| Reviewer Lane | Verdict | File |
|---|---|---|
| codex-architect-review | ${CODEX_ARCHITECT_VERDICT} | ${CODEX_ARCHITECT_FALLBACK_FILE:-missing} |
| codex-test-alternative-review | ${CODEX_TEST_VERDICT} | ${CODEX_TEST_FALLBACK_FILE:-missing} |
| summary | ${CODEX_FALLBACK_COVERAGE} | ${CODEX_FALLBACK_SUMMARY_FILE:-missing} |

## Interpretation

- proceed: review is sufficient to continue toward user approval or commit.
- proceed_degraded: review may continue with explicit degraded trust; at least one external reviewer is missing or only degraded Codex substitute coverage is available.
- revise: at least one reviewer requested changes.
- blocked: no usable review result is available.
- review_manually: review output exists, but the verdict could not be confidently parsed, reviewers disagreed, Codex fallback requested changes alongside external approval, or only one external reviewer approved without usable fallback coverage.
- single_reviewer: only one external reviewer produced a usable verdict; inspect missing reviewer status before relying on multi-agent coverage.
- single_external_plus_codex_fallback: one external reviewer approved and at least one degraded Codex substitute reviewer ran; this is degraded coverage.
- codex_only_degraded: no external reviewer produced a usable verdict; two degraded Codex substitute reviewers ran, but this is not independent external review.
- multi_reviewer: both reviewers produced usable verdicts.
- principal_rotation: the active principal was excluded from self-review and the remaining expected runtimes reviewed.
- principal_subagent_substitute: unavailable reviewer lanes were covered by the active principal's subagent substitute; this is degraded coverage (proceed_degraded / degraded trust), not independent external review.
- principal_rotation_with_substitute: a non-Codex principal used Codex as the normal reviewer lane and the principal subagent covered an unavailable external lane; the substitute lane makes this degraded coverage (proceed_degraded / degraded trust).

## Next Step

If the final decision is proceed or proceed_degraded, inspect the review files and continue with normal verification/commit approval. For proceed_degraded, report the degraded trust level to the user.

If the final decision is revise, inspect reviewer findings and apply only accepted feedback.

If the final decision is blocked or review_manually, inspect the raw review files before continuing.
SUMMARY

echo "${SUMMARY_FILE}"
echo
cat "${SUMMARY_FILE}"

# R2: record approved provenance ONLY on proceed + normal trust (multi_reviewer /
# principal_rotation / substitute lanes set TRUST_LEVEL=normal above). Never on
# proceed_degraded, revise, blocked, or review_manually — those must not seed a skip.
if [ "${FINAL_DECISION}" = "proceed" ] && [ "${TRUST_LEVEL}" = "normal" ]; then
  review_provenance_record
fi

if [ "${FINAL_DECISION}" != "proceed" ] && [ "${FINAL_DECISION}" != "proceed_degraded" ]; then
  exit 1
fi
