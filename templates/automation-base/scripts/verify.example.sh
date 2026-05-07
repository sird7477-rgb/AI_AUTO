#!/usr/bin/env bash
# Example verification script.
# Copy this file to scripts/verify.sh in a target project and customize it.
# Project-specific checks belong here:
# - tests
# - lint
# - Docker/Compose startup
# - API smoke checks
# - Odoo module install/test checks

set -euo pipefail

API_PORT="${API_PORT:-5001}"
BASE_URL="http://localhost:${API_PORT}"

cleanup() {
  docker compose down >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "[verify] running pytest..."
.venv/bin/python -m pytest -q

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
