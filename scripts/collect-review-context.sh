#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-.omx/review-context}"
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
  echo "## Diff"
  echo
  echo '```diff'
  git diff
  echo '```'
  echo
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
