#!/usr/bin/env bash
# Generic verification placeholder installed by aiinit.
# Replace this file with project-specific checks during onboarding.

set -euo pipefail

# Detection marker for automation-doctor; remove only after replacing this file.
VERIFY_TEMPLATE_UNCONFIGURED=1

echo "[verify] project verification is not configured yet."
echo
echo "Before treating this project as automation-ready:"
echo "  1. Interview the project owner for purpose, stack, and completion criteria."
echo "  2. Replace scripts/verify.sh with project-specific checks."
echo "  3. Include the smallest reliable proof that the final result works."
echo
echo "Typical checks may include:"
echo "  - tests"
echo "  - lint or format check"
echo "  - typecheck"
echo "  - build"
echo "  - CLI/API/UI smoke checks"
echo "  - Docker or service startup checks"
echo "  - DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh"
echo

if [ -x "./scripts/test-review-summary.sh" ]; then
  echo "[verify] checking review summary fixture logic..."
  ./scripts/test-review-summary.sh || true
fi

if [ -x "./scripts/automation-doctor.sh" ]; then
  echo "[verify] checking automation files..."
  DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh || true
fi

echo
echo "[verify] replace this placeholder before running review-gate for real work."
exit 1
