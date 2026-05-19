#!/usr/bin/env bash
set -euo pipefail

STRICT="${DOC_BUDGET_STRICT:-0}"

WARN_COUNT=0
FAIL_COUNT=0

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

line_count() {
  local path="$1"
  if [ ! -f "$path" ]; then
    printf '0\n'
    return
  fi
  wc -l < "$path" | tr -d ' '
}

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

guidance_total="$(
  {
    printf '%s\n' AGENTS.md
    if [ -d docs ]; then
      find docs -maxdepth 1 -name '*.md' -print
    fi
    if [ -d templates/automation-base ]; then
      printf '%s\n' templates/automation-base/AGENTS.md templates/automation-base/README.md
      if [ -d templates/automation-base/docs ]; then
        find templates/automation-base/docs -maxdepth 1 -name '*.md' -print
      fi
    fi
  } | while IFS= read -r path; do
    if [ -f "$path" ]; then
      line_count "$path"
    fi
  done | awk '{ total += $1 } END { print total + 0 }'
)"
check_number "guidance markdown total lines" "$guidance_total" 9000 11000

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  diff_added="$(
    {
      git diff --numstat -- AGENTS.md 'docs/*.md' 'templates/automation-base/*.md' 'templates/automation-base/docs/*.md' 2>/dev/null
      git diff --cached --numstat -- AGENTS.md 'docs/*.md' 'templates/automation-base/*.md' 'templates/automation-base/docs/*.md' 2>/dev/null
    } | awk '{ added += $1 } END { print added + 0 }'
  )"
  diff_removed="$(
    {
      git diff --numstat -- AGENTS.md 'docs/*.md' 'templates/automation-base/*.md' 'templates/automation-base/docs/*.md' 2>/dev/null
      git diff --cached --numstat -- AGENTS.md 'docs/*.md' 'templates/automation-base/*.md' 'templates/automation-base/docs/*.md' 2>/dev/null
    } | awk '{ removed += $2 } END { print removed + 0 }'
  )"
  untracked_added="$(
    git ls-files -z --others --exclude-standard -- AGENTS.md docs templates/automation-base 2>/dev/null |
      while IFS= read -r -d '' path; do
        case "$path" in
          AGENTS.md|docs/*.md|templates/automation-base/*.md|templates/automation-base/docs/*.md)
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
  check_number "current guidance diff net added lines" "$diff_net" 150 300
fi

duplicate_report="$(
  {
    if [ -f AGENTS.md ]; then
      printf '%s\0' AGENTS.md
    fi
    if [ -d docs ]; then
      find docs -maxdepth 1 -name '*.md' -print0
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
  warn "long guidance lines repeated 3+ times in root docs"
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
