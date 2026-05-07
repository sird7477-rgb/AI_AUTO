#!/usr/bin/env bash
set -euo pipefail

echo "[gate] running verification..."
./scripts/verify.sh

echo "[gate] running AI reviews..."
./scripts/run-ai-reviews.sh

echo "[gate] summarizing AI review verdicts..."
./scripts/summarize-ai-reviews.sh

echo "[gate] complete"
