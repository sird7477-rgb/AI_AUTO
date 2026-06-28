#!/usr/bin/env bash
set -euo pipefail

API_PORT="${API_PORT:-5001}"
BASE_URL="http://localhost:${API_PORT}"
repo_root="$(pwd)"
AI_AUTO_VERIFY_SCOPE="${AI_AUTO_VERIFY_SCOPE:-full}"

if [ -f "${repo_root}/scripts/docker-config-guard.sh" ]; then
  # shellcheck source=scripts/docker-config-guard.sh
  . "${repo_root}/scripts/docker-config-guard.sh"
  ai_auto_configure_docker_config
fi

# Concurrency guard: a standalone verify in a second terminal on the SAME tree warns /
# soft-blocks; nested under review-gate it is re-entrant (shared AI_AUTO_SESSION_ID).
if [ -f "${repo_root}/scripts/session-lock.sh" ]; then
  # shellcheck source=scripts/session-lock.sh
  . "${repo_root}/scripts/session-lock.sh"
fi

cleanup() {
  docker compose down >/dev/null 2>&1 || true
  command -v session_lock_release >/dev/null 2>&1 && session_lock_release
}

trap cleanup EXIT

if command -v session_lock_acquire >/dev/null 2>&1; then
  # Propagate the acquire code (do NOT collapse to 1): a live sibling holding the tree
  # returns 75 (retryable contention), which a caller must distinguish from a real
  # verification failure. Standalone verify exits 75; under review-gate this is re-entrant
  # (returns 0) so the gate never sees 75 from here.
  _lock_rc=0
  session_lock_acquire validate || _lock_rc=$?   # `|| ` so set -e does not exit before capture
  [ "${_lock_rc}" -eq 0 ] || exit "${_lock_rc}"
fi

run_product_pytest() {
  echo "[verify] running product pytest..."
  .venv/bin/python -m pytest -q tests/test_app.py
}

run_product_smoke() {
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
}

case "${AI_AUTO_VERIFY_SCOPE}" in
  full)
    ./scripts/verify-machinery.sh
    run_product_smoke
    ;;
  product)
    run_product_pytest
    run_product_smoke
    ;;
  machinery)
    ./scripts/verify-machinery.sh
    ;;
  *)
    echo "[verify] unknown AI_AUTO_VERIFY_SCOPE=${AI_AUTO_VERIFY_SCOPE}; expected full, product, or machinery" >&2
    exit 2
    ;;
esac
