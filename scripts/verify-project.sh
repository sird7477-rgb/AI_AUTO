#!/usr/bin/env bash
set -euo pipefail

# ai-lab's OWN project verification hook (ai-lab-as-just-another-project).
# The global framework verify.sh delegates the "product" step to this file when it
# is present + executable in the project. The sample-app pytest + docker smoke that
# used to live inline in verify.sh now live here.

API_PORT="${API_PORT:-5001}"
BASE_URL="http://localhost:${API_PORT}"

run_product_pytest() {
  echo "[verify-project] running product pytest..."
  .venv/bin/python -m pytest -q tests/test_app.py
}

run_product_smoke() {
  echo "[verify-project] starting docker compose on API_PORT=${API_PORT}..."
  API_PORT="${API_PORT}" docker compose up --build -d

  echo "[verify-project] waiting for API..."
  for i in {1..30}; do
    if curl -fsS "${BASE_URL}/" >/dev/null; then
      break
    fi

    if [ "$i" -eq 30 ]; then
      echo "[verify-project] API did not become ready"
      docker compose ps
      docker compose logs api --tail=80
      exit 1
    fi

    sleep 1
  done

  echo "[verify-project] checking / ..."
  curl -fsS "${BASE_URL}/"
  echo

  echo "[verify-project] checking /todos ..."
  curl -fsS "${BASE_URL}/todos"
  echo

  echo "[verify-project] docker compose status..."
  docker compose ps

  echo "[verify-project] success"
}

cleanup() {
  docker compose down >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_product_pytest
run_product_smoke
