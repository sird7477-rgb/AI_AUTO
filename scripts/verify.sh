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
bash -n scripts/bootstrap-ai-lab.sh
bash -n scripts/automation-doctor.sh
bash -n templates/automation-base/scripts/automation-doctor.sh

if [ ! -f scripts/automation-doctor.sh ] || [ ! -f templates/automation-base/scripts/automation-doctor.sh ]; then
  echo "[verify] automation doctor copy is missing"
  echo "[verify] expected scripts/automation-doctor.sh and templates/automation-base/scripts/automation-doctor.sh"
  exit 1
fi

echo "[verify] checking automation doctor template sync..."
if ! diff -u scripts/automation-doctor.sh templates/automation-base/scripts/automation-doctor.sh; then
  echo "[verify] automation doctor copies are out of sync"
  echo "[verify] sync scripts/automation-doctor.sh and templates/automation-base/scripts/automation-doctor.sh, then rerun"
  exit 1
fi

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
