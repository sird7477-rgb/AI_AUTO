#!/usr/bin/env bash
set -euo pipefail

echo "[gate] running verification..."
./scripts/verify.sh

echo "[gate] running AI reviews..."
set +e
./scripts/run-ai-reviews.sh
review_status=$?
set -e

if [ "${review_status}" -ne 0 ]; then
  if [ "${review_status}" -eq 2 ]; then
    echo "[gate] external AI review prepared; run the generated external reviewer command, then rerun ./scripts/summarize-ai-reviews.sh"
  fi
  exit "${review_status}"
fi

echo "[gate] summarizing AI review verdicts..."
if ! ./scripts/summarize-ai-reviews.sh; then
  echo "[gate] review gate did not proceed"
  exit 1
fi

echo "[gate] complete"
