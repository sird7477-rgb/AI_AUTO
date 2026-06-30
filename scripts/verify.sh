#!/usr/bin/env bash
set -euo pipefail

# Framework siblings resolve via our own dir (symlink-followed) so they are reachable
# from ANY cwd / PATH / temp-sandbox fixture; project context stays $(pwd).
AH="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# H1: ENGINE-AWARE default scope. `full` runs the engine's verify-machinery.sh, which is
# meaningful ONLY on the engine repo itself; in a DERIVED project it would run against the
# project cwd and exit 127. So default to `full` ONLY when this IS the engine self-host —
# mirror the gate's machinery-fold guard (review-gate.sh:506): the engine's own
# verify-machinery.sh is present AND the engine root ($AH/..) is the current repo.
# OTHERWISE default to `product` (the fail-closed verify-project.sh seam). Explicit env wins.
# R4-2: anchor "this IS the engine self-host" on the git TOPLEVEL of the cwd, not on cwd
# being EXACTLY the engine root — so ANY cwd inside the engine repo (a subdir, a secondary
# worktree path that resolves to the same root) still folds machinery, while a derived
# project (whose toplevel != the engine root) still gets product.
if [ -z "${AI_AUTO_VERIFY_SCOPE:-}" ]; then
  if [ -f "$AH/verify-machinery.sh" ] && [ "$(git rev-parse --show-toplevel 2>/dev/null)" -ef "$(dirname "$AH")" ]; then
    AI_AUTO_VERIFY_SCOPE=full
  else
    AI_AUTO_VERIFY_SCOPE=product
  fi
fi

if [ -f "$AH/docker-config-guard.sh" ]; then
  # shellcheck source=scripts/docker-config-guard.sh
  . "$AH/docker-config-guard.sh"
  ai_auto_configure_docker_config
fi

# Concurrency guard: a standalone verify in a second terminal on the SAME tree warns /
# soft-blocks; nested under review-gate it is re-entrant (shared AI_AUTO_SESSION_ID).
if [ -f "$AH/session-lock.sh" ]; then
  # shellcheck source=scripts/session-lock.sh
  . "$AH/session-lock.sh"
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

# The "product" step is the PROJECT's own real verification: an OPTIONAL,
# project-owned hook at ./scripts/verify-project.sh (pwd-relative — project context,
# NOT a framework sibling). Present + executable -> run it. ABSENT -> FAIL-CLOSED so a
# derived project's verify is never a silent green no-op.
run_product() {
  if [ -x ./scripts/verify-project.sh ]; then
    echo "[verify] delegating to project verification: ./scripts/verify-project.sh"
    ./scripts/verify-project.sh
  elif [ -e ./scripts/verify-project.sh ]; then
    echo "[verify] scripts/verify-project.sh present but NOT executable — running via bash (lost exec bit)" >&2
    bash ./scripts/verify-project.sh
  else
    echo "[verify] no project verification: scripts/verify-project.sh is absent — NOTHING was verified" >&2
    exit 1
  fi
}

case "${AI_AUTO_VERIFY_SCOPE}" in
  full)
    "$AH/verify-machinery.sh"
    run_product
    ;;
  product)
    run_product
    ;;
  machinery)
    "$AH/verify-machinery.sh"
    ;;
  *)
    echo "[verify] unknown AI_AUTO_VERIFY_SCOPE=${AI_AUTO_VERIFY_SCOPE}; expected full, product, or machinery" >&2
    exit 2
    ;;
esac
