#!/usr/bin/env bash
set -euo pipefail

STRICT="${DOC_BUDGET_STRICT:-0}"
TEMPLATE_PATCH_MODE="${DOC_BUDGET_TEMPLATE_PATCH:-0}"
TEMPLATE_PATCH_REASON="${DOC_BUDGET_TEMPLATE_PATCH_REASON:-}"
# Integration branch the cumulative diff is measured against. On that branch (or
# with no merge-base) the measurement degrades to the uncommitted diff.
BASE_REF="${DOC_BUDGET_BASE_REF:-main}"
# Optional task/work-session baseline. When set, cumulative branch guidance
# growth is still reported, but hard failure is applied to this narrower diff.
COMPLETION_BASE_REF="${DOC_BUDGET_COMPLETION_BASE_REF:-}"
# Extra content/spec paths to exempt from the guidance budget, space separated.
EXEMPT_GLOBS="${DOC_BUDGET_EXEMPT_GLOBS:-}"

WARN_COUNT=0
FAIL_COUNT=0

doc_budget_is_exempt() {
  # Content/spec docs are not budgeted guidance: only the designated content
  # areas (docs/specs/, docs/reference/ and their template copies), files using
  # the plan/spec filename-label convention (*.plan.md / *.spec.md), and paths
  # matching DOC_BUDGET_EXEMPT_GLOBS. Other docs -- including nested guidance
  # like docs/plans/ or docs/research/ -- stay budgeted.
  local path="$1" glob
  case "${path}" in
    docs/specs/*|docs/reference/*|templates/automation-base/docs/specs/*|templates/automation-base/docs/reference/*)
      return 0
      ;;
    *.plan.md|*.spec.md)
      return 0
      ;;
  esac
  if [ -n "${EXEMPT_GLOBS}" ]; then
    # noglob: word-split EXEMPT_GLOBS into patterns without expanding them
    # against the working directory.
    set -f
    for glob in ${EXEMPT_GLOBS}; do
      # shellcheck disable=SC2254
      case "${path}" in
        ${glob}) set +f; return 0 ;;
      esac
    done
    set +f
  fi
  return 1
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '[warn] %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[fail] %s\n' "$1"
}

check_number() {
  local label="$1"
  local value="$2"
  local warn_at="$3"
  local fail_at="$4"

  printf '[budget] %s: %s\n' "$label" "$value"

  if [ "$value" -gt "$fail_at" ]; then
    fail "${label} exceeds hard limit ${fail_at}"
  elif [ "$value" -gt "$warn_at" ]; then
    warn "${label} exceeds warning budget ${warn_at}"
  fi
}

check_current_guidance_diff() {
  local value="$1" label="${2:-current guidance diff}" mode="${3:-fail}" warn_at=150 fail_at=300

  printf '[budget] %s net added lines: %s\n' "$label" "$value"

  if [ "$value" -gt "$fail_at" ]; then
    if [ "$mode" = "warn" ]; then
      warn "${label} net added lines exceeds hard limit ${fail_at}; completion-scoped budget will decide task completion"
      return
    fi
    if [ "$TEMPLATE_PATCH_MODE" = "1" ]; then
      warn "${label} net added lines exceeds hard limit ${fail_at}; DOC_BUDGET_TEMPLATE_PATCH=1 treats template patch adoption as a reported warning"
      echo "[budget] template patch mode reason: ${TEMPLATE_PATCH_REASON}"
      echo "[budget] template patch mode: verify that additions are template-owned or explicitly review-merged"
      echo "[budget] template patch mode is attestation-only; report this warning and the reviewed scope"
    else
      fail "${label} net added lines exceeds hard limit ${fail_at}"
      echo "[budget] if this is a reviewed AI_AUTO template patch with legitimate template-owned guide additions, rerun with DOC_BUDGET_TEMPLATE_PATCH=1 DOC_BUDGET_TEMPLATE_PATCH_REASON='...' and report the warning"
    fi
  elif [ "$value" -gt "$warn_at" ]; then
    if [ "$TEMPLATE_PATCH_MODE" = "1" ]; then
      echo "[budget] template patch mode reason: ${TEMPLATE_PATCH_REASON}"
      echo "[budget] template patch mode: ${label} exceeds warning budget ${warn_at} but stays within hard limit ${fail_at}"
      echo "[budget] template patch mode is accepted for reviewed template-owned or review-merged guidance"
      return
    fi
    warn "${label} net added lines exceeds warning budget ${warn_at}"
  fi
}

line_count() {
  local path="$1"
  if [ ! -f "$path" ]; then
    printf '0\n'
    return
  fi
  wc -l < "$path" | tr -d ' '
}

# The escape hatch must record a SUBSTANTIVE reason; it is not a silent
# self-attestation, and trivial / recycled placeholder reasons are rejected.
if [ "${TEMPLATE_PATCH_MODE}" = "1" ]; then
  template_patch_reason_trimmed="$(printf '%s' "${TEMPLATE_PATCH_REASON}" | tr -d '[:space:]')"
  if [ -z "${TEMPLATE_PATCH_REASON}" ]; then
    fail "DOC_BUDGET_TEMPLATE_PATCH=1 requires DOC_BUDGET_TEMPLATE_PATCH_REASON to record why the budget is bypassed"
  elif [ "${#template_patch_reason_trimmed}" -lt 12 ]; then
    fail "DOC_BUDGET_TEMPLATE_PATCH_REASON is too short (>=12 non-space chars required); placeholder/recycled reasons are not accepted"
  fi
fi

echo "[budget] checking guidance document volume..."

check_number "AGENTS.md lines" "$(line_count AGENTS.md)" 150 220
check_number "docs/WORKFLOW.md lines" "$(line_count docs/WORKFLOW.md)" 350 450
check_number "docs/AUTOMATION_OPERATING_POLICY.md lines" "$(line_count docs/AUTOMATION_OPERATING_POLICY.md)" 650 800

if [ -f "templates/automation-base/AGENTS.md" ]; then
  check_number "template AGENTS.md lines" "$(line_count templates/automation-base/AGENTS.md)" 180 240
fi

if [ -f "templates/automation-base/docs/WORKFLOW.md" ]; then
  check_number "template WORKFLOW.md lines" "$(line_count templates/automation-base/docs/WORKFLOW.md)" 380 500
fi

if [ -f "templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md" ]; then
  check_number "template AUTOMATION_OPERATING_POLICY.md lines" "$(line_count templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md)" 650 800
fi

primary_guidance_total="$(
  {
    printf '%s\n' AGENTS.md
    if [ -d docs ]; then
      find docs -name '*.md' -print
    fi
  } | while IFS= read -r path; do
    if [ -f "$path" ] && ! doc_budget_is_exempt "$path"; then
      line_count "$path"
    fi
  done | awk '{ total += $1 } END { print total + 0 }'
)"
check_number "primary guidance markdown total lines" "$primary_guidance_total" 6500 8000

template_guidance_total="$(
  {
    if [ -d templates/automation-base ]; then
      printf '%s\n' templates/automation-base/AGENTS.md templates/automation-base/README.md
      if [ -d templates/automation-base/docs ]; then
        find templates/automation-base/docs -name '*.md' -print
      fi
    fi
  } | while IFS= read -r path; do
    if [ -f "$path" ] && ! doc_budget_is_exempt "$path"; then
      line_count "$path"
    fi
  done | awk '{ total += $1 } END { print total + 0 }'
)"
check_number "template guidance markdown total lines" "$template_guidance_total" 4500 6500

guidance_total=$((primary_guidance_total + template_guidance_total))
printf '[budget] guidance markdown total lines: %s\n' "$guidance_total"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Branch-cumulative: measure against the merge-base with the integration
  # branch so splitting a guide across commits cannot evade the budget. On that
  # branch itself (or with no merge-base) this degrades to the uncommitted diff.
  base_ref="$(git merge-base "${BASE_REF}" HEAD 2>/dev/null || git rev-parse HEAD 2>/dev/null || echo HEAD)"

  # Guidance is the markdown set minus the designated content areas. The diff and
  # the totals use this same scope. Plain 'docs/*.md' pathspecs match nested
  # paths too, so the exclude pathspecs carve out content/spec areas.
  guidance_pathspecs=(
    AGENTS.md 'docs/*.md' 'templates/automation-base/*.md' 'templates/automation-base/docs/*.md'
    ':(exclude,glob)docs/specs/**' ':(exclude,glob)docs/reference/**'
    ':(exclude,glob)templates/automation-base/docs/specs/**' ':(exclude,glob)templates/automation-base/docs/reference/**'
    ':(exclude,glob)**/*.plan.md' ':(exclude,glob)**/*.spec.md'
    ':(exclude,glob)*.plan.md' ':(exclude,glob)*.spec.md'
  )
  if [ -n "${EXEMPT_GLOBS}" ]; then
    set -f
    for glob in ${EXEMPT_GLOBS}; do
      guidance_pathspecs+=(":(exclude,glob)${glob}")
    done
    set +f
  fi

  diff_numstat="$(git diff --numstat "${base_ref}" -- "${guidance_pathspecs[@]}" 2>/dev/null || true)"
  diff_added="$(printf '%s\n' "${diff_numstat}" | awk '{ added += $1 } END { print added + 0 }')"
  diff_removed="$(printf '%s\n' "${diff_numstat}" | awk '{ removed += $2 } END { print removed + 0 }')"
  untracked_added="$(
    git ls-files -z --others --exclude-standard -- AGENTS.md docs templates/automation-base 2>/dev/null |
      while IFS= read -r -d '' path; do
        if doc_budget_is_exempt "$path"; then
          continue
        fi
        case "$path" in
          AGENTS.md|docs/*.md|templates/automation-base/docs/*.md|templates/automation-base/*.md)
            if [ -f "$path" ]; then
              line_count "$path"
            fi
            ;;
        esac
      done | awk '{ total += $1 } END { print total + 0 }'
  )"
  diff_added=$((diff_added + untracked_added))
  diff_net=$((diff_added - diff_removed))
  if [ "$diff_net" -lt 0 ]; then
    diff_net=0
  fi
  printf '[budget] current guidance diff added lines: %s\n' "$diff_added"
  if [ -n "${COMPLETION_BASE_REF}" ]; then
    check_current_guidance_diff "$diff_net" "branch-cumulative guidance diff" "warn"

    completion_base_ref="$(git merge-base "${COMPLETION_BASE_REF}" HEAD 2>/dev/null || git rev-parse "${COMPLETION_BASE_REF}" 2>/dev/null || echo "")"
    if [ -z "${completion_base_ref}" ]; then
      fail "DOC_BUDGET_COMPLETION_BASE_REF=${COMPLETION_BASE_REF} could not be resolved"
    else
      completion_numstat="$(git diff --numstat "${completion_base_ref}" -- "${guidance_pathspecs[@]}" 2>/dev/null || true)"
      completion_added="$(printf '%s\n' "${completion_numstat}" | awk '{ added += $1 } END { print added + 0 }')"
      completion_removed="$(printf '%s\n' "${completion_numstat}" | awk '{ removed += $2 } END { print removed + 0 }')"
      completion_added=$((completion_added + untracked_added))
      completion_net=$((completion_added - completion_removed))
      if [ "$completion_net" -lt 0 ]; then
        completion_net=0
      fi
      printf '[budget] completion-scoped guidance diff base: %s\n' "${completion_base_ref}"
      printf '[budget] completion-scoped guidance diff added lines: %s\n' "$completion_added"
      check_current_guidance_diff "$completion_net" "completion-scoped guidance diff"
    fi
  else
    check_current_guidance_diff "$diff_net" "current guidance diff"
  fi

  # Plan/spec labeled artifacts are exempt from the guidance budget above, but
  # their net-added lines are still reported separately so the volume stays
  # visible rather than silently dropped.
  label_pathspecs=(
    ':(glob)**/*.plan.md' ':(glob)**/*.spec.md' ':(glob)*.plan.md' ':(glob)*.spec.md'
  )
  label_numstat="$(git diff --numstat "${base_ref}" -- "${label_pathspecs[@]}" 2>/dev/null || true)"
  label_added="$(printf '%s\n' "${label_numstat}" | awk '{ added += $1 } END { print added + 0 }')"
  label_removed="$(printf '%s\n' "${label_numstat}" | awk '{ removed += $2 } END { print removed + 0 }')"
  label_untracked_added="$(
    git ls-files -z --others --exclude-standard 2>/dev/null |
      while IFS= read -r -d '' path; do
        case "$path" in
          *.plan.md|*.spec.md)
            if [ -f "$path" ]; then
              line_count "$path"
            fi
            ;;
        esac
      done | awk '{ total += $1 } END { print total + 0 }'
  )"
  label_added=$((label_added + label_untracked_added))
  label_net=$((label_added - label_removed))
  if [ "$label_net" -lt 0 ]; then
    label_net=0
  fi
  printf '[budget] plan/spec labeled artifacts net added lines (exempt, reported separately): %s\n' "$label_net"
fi

duplicate_report="$(
  {
    if [ -f AGENTS.md ]; then
      printf '%s\0' AGENTS.md
    fi
    if [ -d docs ]; then
      find docs -maxdepth 1 -name '*.md' -print0
    fi
    if [ -f templates/automation-base/AGENTS.md ]; then
      printf '%s\0' templates/automation-base/AGENTS.md
    fi
    if [ -d templates/automation-base/docs ]; then
      find templates/automation-base/docs -maxdepth 1 -name '*.md' -print0
    fi
  } | xargs -0 -r awk '
    length($0) >= 90 && $0 !~ /^[[:space:]]*#/ {
      count[$0] += 1
    }
    END {
      for (line in count) {
        if (count[line] >= 3) {
          print count[line] "\t" substr(line, 1, 140)
        }
      }
    }
  ' | sort -rn | awk 'NR <= 5'
)"

if [ -n "$duplicate_report" ]; then
  warn "long guidance lines repeated 3+ times in root or template docs"
  printf '%s\n' "$duplicate_report" | sed 's/^/[budget] duplicate: /'
fi

echo "[budget] warnings=${WARN_COUNT} failures=${FAIL_COUNT}"

if [ "$WARN_COUNT" -gt 0 ]; then
  echo "[budget] recommendation: report these warnings to the user."
  echo "[budget] recommendation: run a stage-2 duplicate report only when the user asks for it."
  echo "[budget] recommendation: do not edit guidance documents from this warning alone."
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

if [ "$STRICT" = "1" ] && [ "$WARN_COUNT" -gt 0 ]; then
  echo "[budget] strict mode treats warnings as failures"
  exit 1
fi
