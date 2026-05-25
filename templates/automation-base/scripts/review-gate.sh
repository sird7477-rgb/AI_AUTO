#!/usr/bin/env bash
set -euo pipefail

VERIFY_OUTPUT_FILE="${VERIFY_OUTPUT_FILE:-.omx/review-context/latest-verify-output.txt}"
mkdir -p "$(dirname "$VERIFY_OUTPUT_FILE")"

echo "[gate] running verification..."
env \
  -u RUN_CLAUDE_REVIEW \
  -u REVIEW_CONTEXT_DETAIL \
  -u REVIEW_INCLUDE_UNTRACKED_CONTENT \
  ./scripts/verify.sh 2>&1 | tee "$VERIFY_OUTPUT_FILE"

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
summary_status=0
if ! ./scripts/summarize-ai-reviews.sh; then
  echo "[gate] review gate did not proceed"
  summary_status=1
fi

if [ "${OMX_AUTO_ARCHIVE:-1}" != "0" ] && [ -x "./scripts/archive-omx-artifacts.sh" ]; then
  echo "[gate] archiving old review artifacts when retention thresholds are exceeded..."
  ./scripts/archive-omx-artifacts.sh
fi

if [ "${OMX_AUTO_CHECKPOINT:-1}" != "0" ] && [ -x "./scripts/write-session-checkpoint.sh" ]; then
  echo "[gate] writing session checkpoint..."
  ./scripts/write-session-checkpoint.sh
fi

if [ "${OMX_AUTO_KNOWLEDGE_DRAFTS:-1}" != "0" ] && [ -x "./scripts/capture-knowledge-drafts.py" ]; then
  echo "[gate] capturing local knowledge drafts..."
  if ! ./scripts/capture-knowledge-drafts.py --source review-gate --write; then
    echo "[gate] warning: knowledge draft capture failed; review gate result is unchanged"
  fi
fi

if [ "${summary_status}" -ne 0 ]; then
  exit "${summary_status}"
fi

echo "[gate] complete"
