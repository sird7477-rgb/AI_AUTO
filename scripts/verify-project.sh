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

# RED7-4 / RED12 dogfood (2026-07-07 R6 ops-defense, MEDIUM): scripts/verify.sh's
# run_product reads a `[verify-project] RUNTIME_ORACLE=<state>[:<detail>]` marker on this
# verifier's own captured stdout/stderr to tell "a real runtime oracle actually ran and
# passed" apart from "verify-project.sh only did static checks" (the contract is documented
# at scripts/verify.sh's run_product, above the oracle-check block). Before this fix, this
# repo's OWN verifier -- despite genuinely bringing up a docker-compose flask+postgres app
# and hitting its endpoints below -- never emitted that marker, so the contract was inert
# even on the engine repo dogfooding itself. Fixed by emitting the marker on every terminal
# path of the smoke test: `passed:ai-lab-app-smoke` only once the smoke test above has
# actually run to completion and succeeded; `docker-down` when docker itself is unavailable
# (binary missing or daemon unreachable) so the smoke test is skipped rather than crashing
# on a confusing raw docker error; `skipped` on the docs/plans-only scoped fast-path where
# skipping is a deliberate, correct scope decision, not a docker problem. No existing
# assertion (pytest, curl endpoint checks, docker compose ps/logs) is loosened -- this only
# ADDS the marker line alongside the pre-existing behavior.
docker_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

run_product_smoke() {
  if ! docker_available; then
    echo "[verify-project] docker unavailable (not installed or daemon unreachable) -- skipping runtime smoke test"
    echo "[verify-project] RUNTIME_ORACLE=docker-down"
    return 0
  fi

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
  echo "[verify-project] RUNTIME_ORACLE=passed:ai-lab-app-smoke"
}

changed_paths() {
  printf '%s\n' "${AI_AUTO_VERIFY_CHANGED_PATHS:-}" | sed '/^[[:space:]]*$/d'
}

changed_paths_are_docs_plans_only() {
  local path saw=0
  while IFS= read -r path; do
    [ -n "${path}" ] || continue
    saw=1
    case "${path}" in
      docs/*|plans/*|*.md) ;;
      *) return 1 ;;
    esac
  done <<EOF
$(changed_paths)
EOF
  [ "${saw}" -eq 1 ]
}

changed_paths_are_known_product_scope() {
  local path saw=0
  while IFS= read -r path; do
    [ -n "${path}" ] || continue
    saw=1
    case "${path}" in
      app.py|tests/test_app.py|requirements.txt|Dockerfile|docker-compose.yml|docker/*)
        ;;
      *) return 1 ;;
    esac
  done <<EOF
$(changed_paths)
EOF
  [ "${saw}" -eq 1 ]
}

run_scoped_product_verification() {
  if [ "${AI_AUTO_VERIFY_INJECT_SCOPED_FAILURE:-0}" = "1" ]; then
    echo "[verify-project] scoped verification failure injected"
    return 1
  fi

  if changed_paths_are_docs_plans_only; then
    echo "[verify-project] scoped verification: docs/plans-only change; skipping product pytest and docker smoke"
    printf '%s\n' "${AI_AUTO_VERIFY_CHANGED_PATHS}" | sed 's/^/[verify-project] scoped path: /'
    echo "[verify-project] RUNTIME_ORACLE=skipped"
    return 0
  fi

  if changed_paths_are_known_product_scope; then
    echo "[verify-project] scoped verification: known sample-app mapping; running tests/test_app.py and docker smoke"
    printf '%s\n' "${AI_AUTO_VERIFY_CHANGED_PATHS}" | sed 's/^/[verify-project] scoped path: /'
    run_product_pytest
    run_product_smoke
    return 0
  fi

  echo "[verify-project] scoped verification: mapping unknown; falling back to full product verification"
  return 2
}

cleanup() {
  docker compose down >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [ "${AI_AUTO_VERIFY_DIFF_SCOPE:-0}" = "1" ] && [ -n "${AI_AUTO_VERIFY_CHANGED_PATHS:-}" ]; then
  scoped_rc=0
  run_scoped_product_verification || scoped_rc=$?
  case "${scoped_rc}" in
    0) exit 0 ;;
    2) ;;
    *) exit "${scoped_rc}" ;;
  esac
fi

run_product_pytest
run_product_smoke
