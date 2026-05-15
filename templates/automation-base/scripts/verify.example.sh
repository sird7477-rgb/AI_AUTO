#!/usr/bin/env bash
# Generic verification placeholder installed by aiinit.
# Customize this placeholder with project-specific checks during onboarding.

set -euo pipefail

# Detection marker for automation-doctor; remove only after customizing this file.
VERIFY_TEMPLATE_UNCONFIGURED=1

echo "[verify] project verification is not configured yet."
echo
echo "Before treating this project as automation-ready:"
echo "  1. Interview the project owner for purpose, stack, and completion criteria."
echo "  2. Customize scripts/verify.sh with project-specific checks while preserving useful template safeguards."
echo "  3. Include the smallest reliable proof that the final result works."
echo
echo "Typical checks may include:"
echo "  - tests"
echo "  - lint or format check"
echo "  - typecheck"
echo "  - build"
echo "  - python syntax checks (prefer py_compile over compileall when __pycache__ churn is a concern)"
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
echo "[verify] customize this placeholder before running review-gate for real work."
exit 1
