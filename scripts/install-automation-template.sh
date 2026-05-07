#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:-}"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/templates/automation-base"

if [ -z "${TARGET_DIR}" ]; then
  echo "Usage: $0 /path/to/target-repo"
  exit 1
fi

if [ ! -d "${TARGET_DIR}" ]; then
  echo "Target directory does not exist: ${TARGET_DIR}"
  exit 1
fi

if [ ! -d "${TARGET_DIR}/.git" ]; then
  echo "Target directory is not a git repository: ${TARGET_DIR}"
  exit 1
fi

if [ ! -d "${TEMPLATE_DIR}" ]; then
  echo "Template directory not found: ${TEMPLATE_DIR}"
  exit 1
fi

conflicts=()

for path in \
  "AGENTS.md" \
  "docs/WORKFLOW.md" \
  "scripts/collect-review-context.sh" \
  "scripts/make-review-prompts.sh" \
  "scripts/run-ai-reviews.sh" \
  "scripts/summarize-ai-reviews.sh" \
  "scripts/review-gate.sh" \
  "scripts/verify.sh"
do
  if [ -e "${TARGET_DIR}/${path}" ]; then
    conflicts+=("${path}")
  fi
done

if [ "${#conflicts[@]}" -gt 0 ]; then
  echo "Refusing to overwrite existing files:"
  printf ' - %s\n' "${conflicts[@]}"
  echo
  echo "Move or review these files first, then rerun."
  exit 1
fi

mkdir -p "${TARGET_DIR}/docs" "${TARGET_DIR}/scripts"

cp "${TEMPLATE_DIR}/AGENTS.md" "${TARGET_DIR}/AGENTS.md"
cp "${TEMPLATE_DIR}/docs/WORKFLOW.md" "${TARGET_DIR}/docs/WORKFLOW.md"

cp "${TEMPLATE_DIR}/scripts/collect-review-context.sh" "${TARGET_DIR}/scripts/collect-review-context.sh"
cp "${TEMPLATE_DIR}/scripts/make-review-prompts.sh" "${TARGET_DIR}/scripts/make-review-prompts.sh"
cp "${TEMPLATE_DIR}/scripts/run-ai-reviews.sh" "${TARGET_DIR}/scripts/run-ai-reviews.sh"
cp "${TEMPLATE_DIR}/scripts/summarize-ai-reviews.sh" "${TARGET_DIR}/scripts/summarize-ai-reviews.sh"
cp "${TEMPLATE_DIR}/scripts/review-gate.sh" "${TARGET_DIR}/scripts/review-gate.sh"
cp "${TEMPLATE_DIR}/scripts/verify.example.sh" "${TARGET_DIR}/scripts/verify.sh"

chmod +x "${TARGET_DIR}"/scripts/*.sh

echo "Automation template installed into: ${TARGET_DIR}"
echo
echo "Next steps:"
echo "1. Edit ${TARGET_DIR}/scripts/verify.sh for the target project."
echo "2. Review ${TARGET_DIR}/AGENTS.md and ${TARGET_DIR}/docs/WORKFLOW.md."
echo "3. Run:"
echo "   cd ${TARGET_DIR}"
echo "   ./scripts/verify.sh"
echo "   ./scripts/review-gate.sh"
