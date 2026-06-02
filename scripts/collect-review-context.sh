#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-.omx/review-context}"
INCLUDE_UNTRACKED_CONTENT="${INCLUDE_UNTRACKED_CONTENT:-0}"
MAX_UNTRACKED_BYTES="${MAX_UNTRACKED_BYTES:-102400}"
# Optional comma/newline-separated path allowlist (exact paths, directory
# prefixes, or globs). When set, only matching untracked artifacts count as
# blocking review material; others are reported but treated as out of the
# declared review scope. Lets a docs/spec-draft targeted review avoid blocking
# on unrelated untracked files. Empty (default) keeps every material file in scope.
REVIEW_UNTRACKED_ALLOWLIST="${REVIEW_UNTRACKED_ALLOWLIST:-}"
REVIEW_CONTEXT_DETAIL="${REVIEW_CONTEXT_DETAIL:-auto}"
REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES="${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES:-50000}"
REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES="${REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES:-80}"
REPO_STATUS_BEFORE_CONTEXT="$(git status --porcelain 2>/dev/null || true)"
OUT_FILE="${OUT_DIR}/latest-review-context.md"

mkdir -p "${OUT_DIR}"

has_worktree_diff() {
  has_unstaged_diff || has_staged_diff
}

has_unstaged_diff() {
  local status
  if git diff --quiet --exit-code >/dev/null 2>&1; then
    return 1
  else
    status="$?"
  fi

  case "$status" in
    1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

has_staged_diff() {
  local status
  if git diff --cached --quiet --exit-code >/dev/null 2>&1; then
    return 1
  else
    status="$?"
  fi

  case "$status" in
    1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

has_head_commit() {
  git rev-parse --verify HEAD >/dev/null 2>&1
}

is_status_clean() {
  [ -z "${REPO_STATUS_BEFORE_CONTEXT}" ]
}

is_positive_integer() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]+$'
}

tracked_diff_bytes() {
  {
    git diff 2>/dev/null || true
    git diff --cached 2>/dev/null || true
  } | wc -c | tr -d ' '
}

use_lightweight_context() {
  case "${REVIEW_CONTEXT_DETAIL}" in
    light)
      return 0
      ;;
    full)
      return 1
      ;;
    auto)
      ;;
    *)
      echo "Unknown REVIEW_CONTEXT_DETAIL=${REVIEW_CONTEXT_DETAIL}; expected auto, light, or full" >&2
      exit 2
      ;;
  esac

  has_worktree_diff || return 1
  is_positive_integer "${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES}" || return 1

  local diff_bytes
  diff_bytes="$(tracked_diff_bytes)"
  is_positive_integer "${diff_bytes}" || return 1
  [ "${diff_bytes}" -gt 0 ] || return 1
  [ "${diff_bytes}" -le "${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES}" ]
}

write_diff_stat() {
  if has_worktree_diff; then
    if has_unstaged_diff; then
      echo "### Unstaged Diff Stat"
      echo
      echo '```text'
      git diff --stat
      echo '```'
      echo
    fi
    if has_staged_diff; then
      echo "### Staged Diff Stat"
      echo
      echo '```text'
      git diff --cached --stat
      echo '```'
      echo
    fi
    return 0
  fi

  if has_head_commit && is_status_clean; then
    echo "No working tree diff detected; showing latest commit diff for post-commit review context."
    echo
    echo '```text'
    git show --stat --oneline --decorate --find-renames HEAD
    echo '```'
    echo
    return 0
  fi

  echo "No staged or unstaged tracked diff detected. Untracked files, if any, are shown in the Untracked Files section."
}

write_diff() {
  if has_worktree_diff; then
    if has_unstaged_diff; then
      echo "### Unstaged Diff"
      echo
      echo '```diff'
      git diff
      echo '```'
      echo
    fi
    if has_staged_diff; then
      echo "### Staged Diff"
      echo
      echo '```diff'
      git diff --cached
      echo '```'
      echo
    fi
    return 0
  fi

  if has_head_commit && is_status_clean; then
    echo "No working tree diff detected; showing latest commit diff for post-commit review context."
    echo
    echo '```diff'
    git show --format= --find-renames HEAD
    echo '```'
    echo
    return 0
  fi

  echo "No staged or unstaged tracked diff detected. Untracked files, if any, are shown in the Untracked Files section."
}

write_markdown_file() {
  local file="$1"
  echo "### $file"
  echo
  echo '```markdown'
  sed -n '1,200p' "$file"
  echo '```'
  echo
}

collect_review_reference_files() {
  local file
  for file in AGENTS.md docs/WORKFLOW.md docs/AI_ROLES.md; do
    if [ -f "$file" ]; then
      printf '%s\n' "$file"
    fi
  done

  if [ -d docs/runbooks ]; then
    find docs/runbooks -maxdepth 1 -type f -name '*.md' \
      ! -name '*.generated.md' \
      ! -name '*-generated.md' \
      ! -name '*.runtime.md' \
      ! -name '*-runtime.md' \
      | sort | tail -8
  fi
}

classify_review_scope_for_path() {
  local file="$1"
  case "${file}" in
    templates/automation-base/*)
      echo "templates"
      ;;
    AGENTS.md|*/AGENTS.md)
      echo "guidance"
      ;;
    docs/*)
      echo "docs"
      ;;
    plans/*|.omx/plans/*)
      echo "plans"
      ;;
    scripts/*)
      echo "scripts"
      ;;
    tools/*|bin/*)
      echo "tools"
      ;;
    tests/*)
      echo "tests"
      ;;
    Dockerfile|docker-compose.yml|docker/*)
      echo "docker"
      ;;
    .github/workflows/*)
      echo "github_actions"
      ;;
    *.py|*.js|*.ts|*.tsx|*.jsx|*.html|*.css)
      echo "app"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

review_intensity_for_scopes() {
  local scopes="$1"
  case "${scopes}" in
    *guidance*|*scripts*|*templates*|*docker*|*github_actions*)
      echo "strict"
      ;;
    docs|plans|*"docs"*","*"plans"*|*"plans"*","*"docs"*)
      echo "lightweight"
      ;;
    *)
      echo "standard"
      ;;
  esac
}

required_checks_for_scopes() {
  local scopes="$1"
  local checks=("./scripts/verify.sh")

  case "${scopes}" in
    *scripts*|*tools*|*tests*)
      checks+=("targeted script/test fixtures")
      ;;
  esac
  case "${scopes}" in
    *templates*)
      checks+=("template version and patch notes")
      ;;
  esac
  case "${scopes}" in
    *guidance*)
      checks+=("guidance budget check")
      ;;
  esac
  case "${scopes}" in
    *docker*|*app*)
      checks+=("docker smoke")
      ;;
  esac

  local joined="${checks[0]}"
  local check
  for check in "${checks[@]:1}"; do
    joined="${joined}, ${check}"
  done
  echo "${joined}"
}

persona_lens_for_path() {
  case "$1" in
    AGENTS.md|*/AGENTS.md|docs/WORKFLOW.md|docs/AUTOMATION_OPERATING_POLICY.md)
      echo "policy_compliance guidance_bloat"
      ;;
    scripts/verify.sh|scripts/review-gate.sh|scripts/run-ai-reviews.sh|scripts/collect-review-context.sh|scripts/summarize-ai-reviews.sh)
      echo "policy_compliance test_strategy review_taxonomy"
      ;;
    templates/automation-base/*)
      echo "policy_compliance guidance_bloat review_taxonomy"
      ;;
    *auth*|*token*|*cookie*|*secret*|*credential*)
      echo "security"
      ;;
    *schema*|*migration*|*serialization*|*backfill*|*import*|*export*)
      echo "data_migration"
      ;;
    *deploy*|*release*|*rollback*|*monitoring*|*production*)
      echo "release"
      ;;
    scripts/*|tools/*|tests/*)
      echo "test_strategy review_taxonomy"
      ;;
    docs/*|plans/*)
      echo "docs_dx"
      ;;
    *.tsx|*.jsx|*.html|*.css)
      echo "design browser_qa"
      ;;
    *)
      echo ""
      ;;
  esac
}

persona_gate_policy_for_lenses() {
  local lenses="$1"
  case "${lenses}" in
    *policy_compliance*|*security*|*data_migration*|*release*)
      echo "strict_gate"
      ;;
    *test_strategy*|*review_taxonomy*|*design*|*browser_qa*)
      echo "review_gate"
      ;;
    docs_dx)
      echo "verify_only"
      ;;
    "")
      echo "verify_only"
      ;;
    *)
      echo "review_gate"
      ;;
  esac
}

write_diff_scope_summary() {
  local files scopes active_lenses lens_count gate_policy integrator_required
  files="$(
    {
      git diff --name-only 2>/dev/null || true
      git diff --cached --name-only 2>/dev/null || true
      git ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u
  )"

  if [ -z "${files}" ]; then
    echo "No changed files detected."
    return 0
  fi

  scopes="$(printf '%s\n' "${files}" | while IFS= read -r file; do
    [ -n "${file}" ] || continue
    classify_review_scope_for_path "${file}"
  done | sort -u | paste -sd ',' -)"

  active_lenses="$(
    printf '%s\n' "${files}" | while IFS= read -r file; do
      [ -n "${file}" ] || continue
      persona_lens_for_path "${file}" | tr ' ' '\n'
    done | sed '/^[[:space:]]*$/d' | sort -u | paste -sd ',' -
  )"
  lens_count=0
  if [ -n "${active_lenses}" ]; then
    lens_count="$(printf '%s\n' "${active_lenses}" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  fi
  integrator_required=false
  if [ "${lens_count}" -gt 1 ]; then
    integrator_required=true
    case ",${active_lenses}," in
      *,integrator,*) ;;
      *) active_lenses="${active_lenses}${active_lenses:+,}integrator" ;;
    esac
  fi
  gate_policy="$(persona_gate_policy_for_lenses "${active_lenses}")"

  echo "- scopes: ${scopes}"
  echo "- review intensity hint: $(review_intensity_for_scopes "${scopes}")"
  echo "- active lenses: ${active_lenses:-none}"
  echo "- integrator required: ${integrator_required}"
  echo "- review gate policy: ${gate_policy}"
  echo "- review gate reasons: scopes=${scopes}; lenses=${active_lenses:-none}"
  echo "- required checks: $(required_checks_for_scopes "${scopes}")"
  echo
  echo "| File | Scope |"
  echo "| --- | --- |"
  printf '%s\n' "${files}" | while IFS= read -r file; do
    [ -n "${file}" ] || continue
    echo "| ${file} | $(classify_review_scope_for_path "${file}") |"
  done
}

untracked_path_allowed() {
  local needle="$1"
  local allowlist="$2"
  local item
  while IFS= read -r item; do
    [ -n "${item}" ] || continue
    item="${item%/}"
    # Allowlist entries are intentionally treated as glob/prefix patterns: an
    # exact path or glob matches directly, and a directory entry covers its
    # whole subtree.
    # shellcheck disable=SC2254
    case "${needle}" in
      ${item}|${item}/*) return 0 ;;
    esac
  done <<EOF
${allowlist}
EOF
  return 1
}

write_untracked_review_guard() {
  local material allowlist in_scope filtered file
  material="$(
    git ls-files --others --exclude-standard 2>/dev/null |
      grep -E '^(plans|docs|scripts|tools|tests|templates/automation-base)/|^AGENTS\.md$' || true
  )"

  if [ -z "${material}" ]; then
    echo "guard_status: clear"
    echo "No material untracked review artifacts detected."
    return 0
  fi

  # Scope the blocking material to a declared path allowlist when one is set, so
  # a docs/spec-draft targeted review is not blocked by unrelated untracked
  # files. Out-of-scope files are still reported for transparency.
  filtered=""
  allowlist="$(split_csv_lines "${REVIEW_UNTRACKED_ALLOWLIST}")"
  if [ -n "${allowlist}" ]; then
    in_scope=""
    while IFS= read -r file; do
      [ -n "${file}" ] || continue
      if untracked_path_allowed "${file}" "${allowlist}"; then
        in_scope="${in_scope}${in_scope:+
}${file}"
      else
        filtered="${filtered}${filtered:+
}${file}"
      fi
    done <<EOF
${material}
EOF
    material="${in_scope}"
  fi

  if [ -z "${material}" ]; then
    echo "guard_status: clear"
    if [ -n "${filtered}" ]; then
      echo "scope_allowlist: ${REVIEW_UNTRACKED_ALLOWLIST}"
      echo "No in-scope untracked review artifacts. The following untracked files are outside the declared review scope and were not treated as blocking material:"
      echo
      echo '```text'
      printf '%s\n' "${filtered}"
      echo '```'
    else
      echo "No material untracked review artifacts detected."
    fi
    return 0
  fi

  echo "guard_status: material_untracked_artifacts_present"
  echo "manual_review_required: true"
  echo "manual_review_override: ${REVIEW_UNTRACKED_MANUAL_REVIEWED:-0}"
  if [ -n "${REVIEW_UNTRACKED_ALLOWLIST}" ]; then
    echo "scope_allowlist: ${REVIEW_UNTRACKED_ALLOWLIST}"
  fi
  if [ "${INCLUDE_UNTRACKED_CONTENT}" = "1" ]; then
    echo "content_included: true"
    echo "Material untracked review artifacts are present and content inclusion is enabled."
  else
    echo "content_included: false"
    echo "Material untracked review artifacts are present, but content inclusion is disabled."
    echo "Set INCLUDE_UNTRACKED_CONTENT=1 or require manual review before commit readiness."
  fi
  echo
  echo '```text'
  printf '%s\n' "${material}"
  echo '```'
  if [ -n "${filtered}" ]; then
    echo
    echo "Untracked files outside the declared review scope (reported, not blocking):"
    echo
    echo '```text'
    printf '%s\n' "${filtered}"
    echo '```'
  fi
}

split_csv_lines() {
  local value="$1"
  printf '%s\n' "${value}" | tr ',' '\n' | sed '/^[[:space:]]*$/d; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

path_in_list() {
  local needle="$1"
  local haystack="$2"
  local item
  while IFS= read -r item; do
    [ -n "${item}" ] || continue
    if [ "${item}" = "${needle}" ]; then
      return 0
    fi
  done <<EOF
${haystack}
EOF
  return 1
}

deferred_record_has_reason() {
  local needle="$1"
  local records="$2"
  local item path reason

  while IFS= read -r item; do
    [ -n "${item}" ] || continue
    path="${item%%|*}"
    reason="${item#*|}"
    if [ "${path}" = "${needle}" ] && [ "${reason}" != "${item}" ] && [ -n "${reason}" ]; then
      return 0
    fi
  done <<EOF
${records}
EOF
  return 1
}

write_phase_scope_guard() {
  local phase="${PHASE_SCOPE_PHASE:-}"
  local allowed deferred deferred_records changed unresolved missing_deferral file

  if [ -z "${phase}" ]; then
    echo "phase_scope_status: inactive"
    echo "No phase/scope guard requested. Set PHASE_SCOPE_PHASE and PHASE_SCOPE_ALLOWED_FILES to enable."
    return 0
  fi

  allowed="$(split_csv_lines "${PHASE_SCOPE_ALLOWED_FILES:-}")"
  deferred="$(split_csv_lines "${PHASE_SCOPE_DEFERRED_FILES:-}")"
  deferred_records="$(split_csv_lines "${PHASE_SCOPE_DEFERRED_RECORDS:-}")"
  changed="$(
    {
      git diff --name-only 2>/dev/null || true
      git diff --cached --name-only 2>/dev/null || true
      git ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u
  )"

  unresolved=""
  missing_deferral=""
  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    case "${file}" in
      .omx/review-context/*)
        continue
        ;;
    esac
    if path_in_list "${file}" "${allowed}"; then
      continue
    fi
    if path_in_list "${file}" "${deferred}"; then
      if deferred_record_has_reason "${file}" "${deferred_records}"; then
        continue
      fi
      missing_deferral="${missing_deferral}${missing_deferral:+
}${file}"
      continue
    fi
    unresolved="${unresolved}${unresolved:+
}${file}"
  done <<EOF
${changed}
EOF

  echo "phase: ${phase}"
  echo "manual_review_override: ${PHASE_SCOPE_MANUAL_REVIEWED:-0}"
  if [ -n "${missing_deferral}" ]; then
    echo "phase_scope_status: missing_deferral_record"
    echo "manual_review_required: true"
    echo "Deferred out-of-phase files require PHASE_SCOPE_DEFERRED_RECORDS entries in path|reason format."
    echo
    echo '```text'
    printf '%s\n' "${missing_deferral}"
    echo '```'
  elif [ -n "${unresolved}" ]; then
    echo "phase_scope_status: out_of_phase_edit"
    echo "manual_review_required: true"
    echo "Out-of-phase changed files require a plan update, deferral record, or manual review."
    echo
    echo '```text'
    printf '%s\n' "${unresolved}"
    echo '```'
  else
    echo "phase_scope_status: clear"
    echo "Changed files are inside the allowed or deferred phase scope."
  fi
}

completion_pack_trigger_for_shape() {
  case "$1" in
    security_review) echo "security_completion" ;;
    deployment_files) echo "deployment_completion" ;;
    persisted_data) echo "data_completion" ;;
    ui_work) echo "ui_completion" ;;
    performance_change) echo "performance_completion" ;;
    observability_change) echo "observability_completion" ;;
    docs_generation_lens) echo "reference_lens:not_completion_pack" ;;
    *) echo "" ;;
  esac
}

completion_pack_trigger_for_path() {
  case "$1" in
    docs/SECURITY_COMPLETION.md|*security*|*auth*|*secret*) echo "security_completion" ;;
    docs/DEPLOYMENT_COMPLETION.md|*deploy*|*release*) echo "deployment_completion" ;;
    docs/DATA_COMPLETION.md|*migration*|*schema*|*database*|*persist*) echo "data_completion" ;;
    docs/UI_COMPLETION.md|*frontend*|*ui*|*.tsx|*.jsx|*.css) echo "ui_completion" ;;
    docs/PERFORMANCE_COMPLETION.md|*benchmark*|*performance*|*perf*) echo "performance_completion" ;;
    docs/OBSERVABILITY_COMPLETION.md|*observability*|*monitor*|*logging*) echo "observability_completion" ;;
    *) echo "" ;;
  esac
}

write_completion_pack_routing_audit() {
  local pack missing shape trigger changed file inferred seen
  local packs="DATA DEPLOYMENT OBSERVABILITY PERFORMANCE SECURITY UI"

  missing=""
  for pack in ${packs}; do
    if [ ! -f "docs/${pack}_COMPLETION.md" ]; then
      missing="${missing}${missing:+,}${pack}"
    fi
  done

  echo "audit_status: report_only"
  if [ -n "${missing}" ]; then
    echo "packs_present: missing:${missing}"
  else
    echo "packs_present: data,deployment,observability,performance,security,ui"
  fi

  shape="${COMPLETION_PACK_INPUT_SHAPE:-}"
  trigger="$(completion_pack_trigger_for_shape "${shape}")"
  if [ -n "${shape}" ]; then
    echo "input_shape: ${shape}"
    echo "explicit_trigger: ${trigger:-none}"
  else
    echo "input_shape: none"
    echo "explicit_trigger: none"
  fi

  changed="$(
    {
      git diff --name-only 2>/dev/null || true
      git diff --cached --name-only 2>/dev/null || true
      git ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u
  )"

  inferred=""
  seen=""
  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    case "${file}" in
      .omx/review-context/*)
        continue
        ;;
    esac
    trigger="$(completion_pack_trigger_for_path "${file}")"
    [ -n "${trigger}" ] || continue
    case ",${seen}," in
      *",${trigger},"*) continue ;;
    esac
    seen="${seen}${seen:+,}${trigger}"
    inferred="${inferred}${inferred:+
}- ${trigger}: ${file}"
  done <<EOF
${changed}
EOF

  if [ -n "${inferred}" ]; then
    echo "file_scope_triggers:"
    printf '%s\n' "${inferred}"
  else
    echo "file_scope_triggers: none"
  fi
  echo "runtime_lane_added: false"
}

product_challenge_required_shape() {
  local request_shape="$1"
  local task_size="$2"

  case "${request_shape}" in
    broad_strategy|product_strategy|large_ui_workflow|unclear_value)
      return 0
      ;;
  esac
  [ "${task_size}" = "medium" ] || [ "${task_size}" = "large" ]
}

write_product_challenge_audit() {
  local request_shape="${PRODUCT_CHALLENGE_REQUEST_SHAPE:-unspecified}"
  local task_size="${PRODUCT_CHALLENGE_TASK_SIZE:-unspecified}"
  local approved_plan="${PRODUCT_CHALLENGE_APPROVED_PLAN_EXISTS:-0}"
  local reason="${PRODUCT_CHALLENGE_REASON:-}"
  local questions="${PRODUCT_CHALLENGE_QUESTIONS:-}"
  local question_count=0

  echo "audit_status: report_only"
  echo "request_shape: ${request_shape}"
  echo "task_size: ${task_size}"
  echo "approved_plan_exists: ${approved_plan}"

  if [ "${approved_plan}" = "1" ]; then
    echo "challenge_status: skipped_approved_plan"
    return 0
  fi

  if [ "${task_size}" = "small" ] && { [ "${request_shape}" = "typo" ] || [ "${request_shape}" = "narrow_bugfix" ] || [ "${request_shape}" = "routine_doc" ]; }; then
    echo "challenge_status: skipped_routine_small"
    return 0
  fi

  if product_challenge_required_shape "${request_shape}" "${task_size}"; then
    if [ -z "${reason}" ]; then
      echo "challenge_status: missing_product_challenge_reason"
      echo "manual_review_required: true"
      return 0
    fi

    if [ -n "${questions}" ]; then
      question_count="$(printf '%s\n' "${questions}" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
    fi
    if [ "${question_count}" -gt 3 ]; then
      echo "challenge_status: too_many_product_challenge_questions"
      echo "manual_review_required: true"
      return 0
    fi

    echo "challenge_status: required"
    echo "challenge_reason: ${reason}"
    echo "question_count: ${question_count}"
    return 0
  fi

  echo "challenge_status: not_required"
}

write_visual_artifact_audit() {
  local changed file spec visual_export reviewed_specs status_line any_status

  reviewed_specs="$(split_csv_lines "${VISUAL_HUMAN_REVIEWED_SPECS:-}")"
  changed="$(
    {
      git diff --name-only 2>/dev/null || true
      git diff --cached --name-only 2>/dev/null || true
      git ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u
  )"

  echo "audit_status: report_only"
  echo "runtime_tool_install_required: false"
  any_status=0

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    case "${file}" in
      .omx/review-context/*)
        continue
        ;;
      *.excalidraw)
        spec="${file%.excalidraw}-spec.md"
        visual_export="${file%.excalidraw}.svg"
        if [ ! -f "${spec}" ]; then
          status_line="visual_warning:explanatory_only ${file}"
        elif ! path_in_list "${spec}" "${reviewed_specs}"; then
          status_line="visual_warning:unreviewed_spec ${file} -> ${spec}"
        else
          status_line="visual_ok:implementation_facing_spec ${file} -> ${spec}"
        fi
        echo "${status_line}"
        any_status=1
        if [ -f "${visual_export}" ] && [ "${file}" -nt "${visual_export}" ]; then
          echo "visual_warning:stale_export ${visual_export}"
          any_status=1
        fi
        ;;
      *-spec.md)
        if ! path_in_list "${file}" "${reviewed_specs}"; then
          echo "visual_warning:unreviewed_spec ${file}"
          any_status=1
        fi
        ;;
    esac
  done <<EOF
${changed}
EOF

  if [ "${VISUAL_AMBIGUOUS_SOURCE:-0}" = "1" ]; then
    echo "visual_warning:ambiguous_source_of_truth"
    any_status=1
  fi

  if [ "${any_status}" -eq 0 ]; then
    echo "visual_status: none"
  fi
}

write_browser_qa_evidence_audit() {
  local target="${BROWSER_QA_TARGET:-}"
  local report_only="${BROWSER_QA_REPORT_ONLY:-1}"
  local attempts_patch="${BROWSER_QA_ATTEMPTS_PATCH:-0}"
  local cdp_access="${BROWSER_QA_CDP_ACCESS:-0}"
  local loopback="${BROWSER_QA_LOOPBACK_BOUND:-0}"
  local user_launched="${BROWSER_QA_USER_LAUNCHED_OR_ISOLATED:-0}"
  local approval="${BROWSER_QA_APPROVAL_RECORDED:-0}"
  local exports_credentials="${BROWSER_QA_EXPORTS_COOKIES_OR_TOKENS:-0}"
  local sensitive="${BROWSER_QA_SENSITIVE_EVIDENCE:-0}"
  local redacted="${BROWSER_QA_REDACTED:-0}"
  local visual="${BROWSER_QA_VISUAL_VERDICT:-0}"
  local verify="${BROWSER_QA_VERIFY_EVIDENCE:-0}"
  local review="${BROWSER_QA_REVIEW_GATE_EVIDENCE:-0}"
  local screenshot="${BROWSER_QA_SCREENSHOT_NOTE:-none}"
  local steps="${BROWSER_QA_STEPS:-none}"

  echo "audit_status: report_only"
  echo "target: ${target:-none}"
  echo "steps: ${steps}"
  echo "screenshot_note: ${screenshot}"

  if [ "${report_only}" != "1" ] || [ "${attempts_patch}" = "1" ]; then
    echo "qa_status: qa_block:auto_fix_not_allowed"
    return 0
  fi

  if [ "${cdp_access}" = "1" ]; then
    echo "cdp_access: requested"
    if [ "${loopback}" != "1" ] || [ "${user_launched}" != "1" ] || [ "${approval}" != "1" ] || [ "${exports_credentials}" = "1" ]; then
      echo "qa_status: qa_block:credential_boundary"
      return 0
    fi
  else
    echo "cdp_access: not_requested"
  fi

  if [ "${sensitive}" = "1" ] && [ "${redacted}" != "1" ]; then
    echo "qa_status: qa_warning:redaction_required"
    return 0
  fi

  if [ "${visual}" = "1" ] && { [ "${verify}" != "1" ] || [ "${review}" != "1" ]; }; then
    echo "qa_status: qa_warning:visual_not_completion_authority"
    return 0
  fi

  if [ "${cdp_access}" = "1" ]; then
    echo "qa_status: qa_ok:cdp_report_only"
  else
    echo "qa_status: qa_ok:report_only"
  fi
}

model_routing_lane_for_shape() {
  local shape
  # Normalize: lowercase and strip whitespace so "FAST_SCAN" or " lookup "
  # classify the same as "fast_scan"/"lookup" instead of falling to unclassified.
  shape="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "${shape}" in
    lookup|fast_scan|file_lookup|symbol_lookup|scan) echo "fast_scan" ;;
    bounded_impl|low_cost_impl|small_fix|narrow_impl) echo "low_cost_impl" ;;
    standard_impl|implementation|refactor|feature) echo "standard_impl" ;;
    review|architecture|security_review|risk_review|frontier) echo "frontier_review" ;;
    "") echo "none" ;;
    *) echo "unclassified" ;;
  esac
}

write_model_routing_lane_audit() {
  local shape principal gemini_cmd recommended

  shape="${MODEL_ROUTING_INPUT_SHAPE:-}"
  principal="${AI_AUTO_PRINCIPAL:-codex}"
  gemini_cmd="${GEMINI_REVIEW_COMMAND:-agy}"
  recommended="$(model_routing_lane_for_shape "${shape}")"

  echo "audit_status: report_only"
  echo "active_principal: ${principal}"
  if [ -n "${shape}" ]; then
    echo "input_shape: ${shape}"
  else
    echo "input_shape: none"
  fi
  echo "recommended_lane: ${recommended}"

  # Per-principal fast-class availability (observe-only; mirrors the
  # discover-ai-models.sh Principal Class Lanes contract). Gemini stays
  # honestly class-fixed because it is invoked only via its review command.
  echo "fast_lane_codex: available"
  echo "fast_lane_claude: available_when_model_flag_supported"
  echo "fast_lane_gemini: class_unavailable (invoked only via ${gemini_cmd}; gemini -m forbidden)"

  case "${recommended}" in
    fast_scan|low_cost_impl)
      case "${principal}" in
        gemini)
          echo "missed_fast_lane_opportunity: fast_lane_unavailable (gemini class-fixed)"
          ;;
        *)
          echo "missed_fast_lane_opportunity: candidate (${recommended} can use the fast class)"
          ;;
      esac
      ;;
    *)
      echo "missed_fast_lane_opportunity: none"
      ;;
  esac

  echo "runtime_lane_added: false"
  echo "routing_authority: none"
}

LIGHTWEIGHT_CONTEXT=0
if use_lightweight_context; then
  LIGHTWEIGHT_CONTEXT=1
fi

{
  echo "# Review Context"
  echo
  echo "Generated at: $(date -Iseconds)"
  echo
  echo "## Context Mode"
  echo
  if [ "${LIGHTWEIGHT_CONTEXT}" -eq 1 ]; then
    echo "lightweight"
    echo
    echo "Small staged/unstaged tracked diff detected. This context keeps reviewer input focused on the patch, git state, and verification tail."
    echo "Set REVIEW_CONTEXT_DETAIL=full to include planning artifacts and reference files."
  else
    echo "full"
    echo
    echo "Full context includes planning artifacts and repository workflow reference files."
  fi
  echo
  echo "## Repository"
  echo
  echo '```text'
  pwd
  echo '```'
  echo
  echo "## Git Status"
  echo
  echo '```text'
  git status --short
  echo '```'
  echo
  echo "## Diff Stat"
  echo
  write_diff_stat
  echo
  echo "## Diff Scope Summary"
  echo
  write_diff_scope_summary
  echo
  echo "## Untracked Files"
  echo
  echo '```text'
  git ls-files --others --exclude-standard
  echo '```'
  echo
  echo "Untracked text file content is omitted by default. Set INCLUDE_UNTRACKED_CONTENT=1 to include text files up to ${MAX_UNTRACKED_BYTES} bytes after confirming .gitignore excludes secrets."
  echo
  echo "## Untracked Review Guard"
  echo
  write_untracked_review_guard
  echo
  echo "## Phase Scope Guard"
  echo
  write_phase_scope_guard
  echo
  echo "## Completion Pack Routing Audit"
  echo
  write_completion_pack_routing_audit
  echo
  echo "## Product Challenge Audit"
  echo
  write_product_challenge_audit
  echo
  echo "## Visual Artifact Audit"
  echo
  write_visual_artifact_audit
  echo
  echo "## Browser QA Evidence Audit"
  echo
  write_browser_qa_evidence_audit
  echo
  echo "## Model Routing Lane Audit"
  echo
  write_model_routing_lane_audit
  echo
  echo "## Diff"
  echo
  write_diff
  if [ "$INCLUDE_UNTRACKED_CONTENT" = "1" ]; then
    echo "### Untracked File Content Diff"
    echo
    echo '```diff'
    while IFS= read -r -d '' file; do
      [ -f "$file" ] || continue
      grep -qI '' "$file" 2>/dev/null || continue
      size="$(wc -c < "$file" | tr -d ' ')"
      if [ "$size" -gt "$MAX_UNTRACKED_BYTES" ]; then
        echo "diff --git a/${file} b/${file}"
        echo "# skipped untracked file content: ${file} is ${size} bytes, limit is ${MAX_UNTRACKED_BYTES}"
        continue
      fi
      git diff --no-index -- /dev/null "$file" || true
    done < <(git ls-files -z --others --exclude-standard)
    echo '```'
  fi
  echo
    if [ -f "${OUT_DIR}/latest-verify-output.txt" ]; then
      echo "## Latest Verification Output"
      echo
      echo '```text'
      if [ "${LIGHTWEIGHT_CONTEXT}" -eq 1 ]; then
        echo "### Tail"
        tail -"${REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES}" "${OUT_DIR}/latest-verify-output.txt"
      else
        echo "### Head"
        sed -n '1,160p' "${OUT_DIR}/latest-verify-output.txt"
        echo
        echo "### Tail"
        tail -120 "${OUT_DIR}/latest-verify-output.txt"
      fi
      echo '```'
      echo
    fi
  echo "## Workflow Rule"
  echo
  echo "- Before completion, run ./scripts/verify.sh"
  echo "- If verification fails, the task is not complete."
  echo "- After code edits, compare the final diff with any applicable plan/spec/design artifact and report aligned, updated, not applicable, or blocked."
  echo "- User-facing reports should explain results in plain Korean before using internal technical identifiers."
  echo "- Do not commit without user approval."
  echo
  echo "## Local Planning Artifacts"
  echo
  if [ "${LIGHTWEIGHT_CONTEXT}" -eq 1 ]; then
    echo "Omitted in lightweight context. Set REVIEW_CONTEXT_DETAIL=full when planning artifacts are relevant to the review."
    echo
  else
  plan_files=()
  if [ -d ".omx/plans" ]; then
    while IFS= read -r file; do
      plan_files+=("$file")
    done < <(find .omx/plans -maxdepth 1 -type f \( -name 'prd-*.md' -o -name 'test-spec-*.md' \) | sort | tail -6)
  fi
  if [ "${#plan_files[@]}" -eq 0 ]; then
    echo "No local PRD or test-spec planning artifacts found."
    echo
  else
    for file in "${plan_files[@]}"; do
      echo "### $file"
      echo
      echo '```markdown'
      sed -n '1,240p' "$file"
      echo '```'
      echo
    done
  fi
  fi
  echo "## Relevant Files"
  echo
  if [ "${LIGHTWEIGHT_CONTEXT}" -eq 1 ]; then
    echo "Omitted in lightweight context. Set REVIEW_CONTEXT_DETAIL=full when AGENTS.md, docs/WORKFLOW.md, or docs/AI_ROLES.md content is needed."
    echo
  else
  while IFS= read -r file; do
    if [ -f "$file" ]; then
      write_markdown_file "$file"
    fi
  done < <(collect_review_reference_files)
  fi
} > "${OUT_FILE}"

echo "${OUT_FILE}"
