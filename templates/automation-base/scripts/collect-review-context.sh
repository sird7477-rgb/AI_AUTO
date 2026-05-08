#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-.omx/review-context}"
INCLUDE_UNTRACKED_CONTENT="${INCLUDE_UNTRACKED_CONTENT:-0}"
MAX_UNTRACKED_BYTES="${MAX_UNTRACKED_BYTES:-102400}"
mkdir -p "${OUT_DIR}"

OUT_FILE="${OUT_DIR}/latest-review-context.md"

{
  echo "# Review Context"
  echo
  echo "Generated at: $(date -Iseconds)"
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
  echo '```text'
  git diff --stat
  echo '```'
  echo
  echo "## Untracked Files"
  echo
  echo '```text'
  git ls-files --others --exclude-standard
  echo '```'
  echo
  echo "Untracked text file content is omitted by default. Set INCLUDE_UNTRACKED_CONTENT=1 to include text files up to ${MAX_UNTRACKED_BYTES} bytes after confirming .gitignore excludes secrets."
  echo
  echo "## Diff"
  echo
  echo '```diff'
  git diff
  if [ "$INCLUDE_UNTRACKED_CONTENT" = "1" ]; then
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
  fi
  echo '```'
  echo
  if [ -f "${OUT_DIR}/latest-verify-output.txt" ]; then
    echo "## Latest Verification Output"
    echo
    echo '```text'
    sed -n '1,240p' "${OUT_DIR}/latest-verify-output.txt"
    echo '```'
    echo
  fi
  echo "## Workflow Rule"
  echo
  echo "- Before completion, run ./scripts/verify.sh"
  echo "- If verification fails, the task is not complete."
  echo "- Do not commit without user approval."
  echo
  echo "## Relevant Files"
  echo
  for file in AGENTS.md docs/WORKFLOW.md docs/AI_ROLES.md; do
    if [ -f "$file" ]; then
      echo "### $file"
      echo
      echo '```markdown'
      sed -n '1,200p' "$file"
      echo '```'
      echo
    fi
  done
} > "${OUT_FILE}"

echo "${OUT_FILE}"
