#!/usr/bin/env bash
set -euo pipefail

API_PORT="${API_PORT:-5001}"
BASE_URL="http://localhost:${API_PORT}"

cleanup() {
  docker compose down >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "[verify] running pytest..."
.venv/bin/python -m pytest -q

echo "[verify] checking shell script syntax..."
for script in \
  scripts/bootstrap-ai-lab.sh \
  scripts/automation-doctor.sh \
  scripts/collect-review-context.sh \
  scripts/install-automation-template.sh \
  scripts/make-review-prompts.sh \
  scripts/review-gate.sh \
  scripts/run-ai-reviews.sh \
  scripts/summarize-ai-reviews.sh \
  scripts/test-review-summary.sh \
  templates/automation-base/scripts/automation-doctor.sh \
  templates/automation-base/scripts/collect-review-context.sh \
  templates/automation-base/scripts/make-review-prompts.sh \
  templates/automation-base/scripts/review-gate.sh \
  templates/automation-base/scripts/run-ai-reviews.sh \
  templates/automation-base/scripts/summarize-ai-reviews.sh \
  templates/automation-base/scripts/test-review-summary.sh \
  templates/automation-base/scripts/verify.example.sh
do
  bash -n "${script}"
done

echo "[verify] testing review summary decisions..."
./scripts/test-review-summary.sh

echo "[verify] checking automation template sync..."
for script in \
  automation-doctor.sh \
  collect-review-context.sh \
  make-review-prompts.sh \
  review-gate.sh \
  run-ai-reviews.sh \
  summarize-ai-reviews.sh \
  test-review-summary.sh
do
  if [ ! -f "scripts/${script}" ] || [ ! -f "templates/automation-base/scripts/${script}" ]; then
    echo "[verify] automation script copy is missing: ${script}"
    exit 1
  fi

  if ! diff -u "scripts/${script}" "templates/automation-base/scripts/${script}"; then
    echo "[verify] automation script copies are out of sync: ${script}"
    echo "[verify] sync scripts/${script} and templates/automation-base/scripts/${script}, then rerun"
    exit 1
  fi
done

echo "[verify] running ai-lab bootstrap check..."
./scripts/bootstrap-ai-lab.sh

echo "[verify] starting docker compose on API_PORT=${API_PORT}..."
API_PORT="${API_PORT}" docker compose up --build -d

echo "[verify] waiting for API..."
for i in {1..30}; do
  if curl -fsS "${BASE_URL}/" >/dev/null; then
    break
  fi

  if [ "$i" -eq 30 ]; then
    echo "[verify] API did not become ready"
    docker compose ps
    docker compose logs api --tail=80
    exit 1
  fi

  sleep 1
done

echo "[verify] checking / ..."
curl -fsS "${BASE_URL}/"
echo

echo "[verify] checking /todos ..."
curl -fsS "${BASE_URL}/todos"
echo

echo "[verify] docker compose status..."
docker compose ps

echo "[verify] success"
