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
  "scripts/automation-doctor.sh" \
  "scripts/collect-review-context.sh" \
  "scripts/discover-ai-models.sh" \
  "scripts/make-review-prompts.sh" \
  "scripts/run-ai-reviews.sh" \
  "scripts/summarize-ai-reviews.sh" \
  "scripts/test-review-summary.sh" \
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
  echo "This looks like an existing project or an already-initialized automation setup."
  echo "aiinit is intentionally stopping before it overwrites project instructions, docs, or verification scripts."
  echo
  echo "For an existing project, ask the AI:"
  echo "  기존 프로젝트에 자동화 기반을 병합 도입해줘."
  echo "  기존 AGENTS.md, docs, scripts/verify.sh는 덮어쓰지 말고 먼저 분석한 뒤"
  echo "  필요한 자동화 파일과 지침만 제안/반영해줘."
  echo
  echo "If this is a new project and these files are accidental, move or review them first, then rerun aiinit."
  exit 1
fi

mkdir -p "${TARGET_DIR}/.omx/reviewer-state" "${TARGET_DIR}/docs" "${TARGET_DIR}/scripts"

exclude_file="${TARGET_DIR}/.git/info/exclude"
if ! grep -Eq '^[.]omx/?$' "${exclude_file}" 2>/dev/null; then
  {
    echo
    echo ".omx/"
  } >> "${exclude_file}"
fi

cp "${TEMPLATE_DIR}/AGENTS.md" "${TARGET_DIR}/AGENTS.md"
cp "${TEMPLATE_DIR}/docs/WORKFLOW.md" "${TARGET_DIR}/docs/WORKFLOW.md"

cp "${TEMPLATE_DIR}/scripts/automation-doctor.sh" "${TARGET_DIR}/scripts/automation-doctor.sh"
cp "${TEMPLATE_DIR}/scripts/collect-review-context.sh" "${TARGET_DIR}/scripts/collect-review-context.sh"
cp "${TEMPLATE_DIR}/scripts/discover-ai-models.sh" "${TARGET_DIR}/scripts/discover-ai-models.sh"
cp "${TEMPLATE_DIR}/scripts/make-review-prompts.sh" "${TARGET_DIR}/scripts/make-review-prompts.sh"
cp "${TEMPLATE_DIR}/scripts/run-ai-reviews.sh" "${TARGET_DIR}/scripts/run-ai-reviews.sh"
cp "${TEMPLATE_DIR}/scripts/summarize-ai-reviews.sh" "${TARGET_DIR}/scripts/summarize-ai-reviews.sh"
cp "${TEMPLATE_DIR}/scripts/test-review-summary.sh" "${TARGET_DIR}/scripts/test-review-summary.sh"
cp "${TEMPLATE_DIR}/scripts/review-gate.sh" "${TARGET_DIR}/scripts/review-gate.sh"
cp "${TEMPLATE_DIR}/scripts/verify.example.sh" "${TARGET_DIR}/scripts/verify.sh"

chmod +x "${TARGET_DIR}"/scripts/*.sh

echo "Automation template installed into: ${TARGET_DIR}"
echo "Local git exclude updated for .omx/ runtime artifacts."
echo
echo "Next steps:"
echo "1. Interview the project owner for purpose, scope, stack, and completion criteria."
echo "2. Update ${TARGET_DIR}/AGENTS.md and ${TARGET_DIR}/docs/WORKFLOW.md for the target project."
echo "3. Customize ${TARGET_DIR}/scripts/verify.sh with project-specific checks while preserving useful template safeguards."
echo "4. Run:"
echo "   cd ${TARGET_DIR}"
echo "   ./scripts/automation-doctor.sh"
echo "   ./scripts/verify.sh"
echo "   ./scripts/review-gate.sh"
echo
echo "Next AI request:"
echo "  프로젝트 초기설정 해줘"
echo
echo "Equivalent detailed request:"
echo "  프로젝트 요구사항 인터뷰하고 AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 프로젝트에 맞게 설정해줘"
