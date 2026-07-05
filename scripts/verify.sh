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
  # L5: anchor the project verifier at the git TOPLEVEL (consistent with the gate's
  # toplevel-anchored logic), NOT pwd — so running from a subdir resolves the SAME
  # project-owned seam instead of a subdir's file or a false "absent".
  local top vp
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "${top}" ] || top="$(pwd)"
  vp="${top}/scripts/verify-project.sh"
  # M3: an EMPTY (0-byte) or syntactically-BROKEN verify-project.sh (truncated / botched
  # merge) is NOT a passing verification — fail CLOSED exactly like absent so it can never
  # read as a silent green no-op. An empty file passes `bash -n`, so gate on -s too.
  # R17: also fail CLOSED on NO-EXECUTABLE-CONTENT — a shebang-only, comment-only, or
  # whitespace-only truncation is `-s`>0 AND `bash -n`-clean yet verifies NOTHING (false-green).
  # Strip shebang/comment lines (`^[[:space:]]*#`) and blank/whitespace-only lines; if the
  # `grep -qv` finds NO remaining line, there is no statement to run -> BLOCK. (Out of scope:
  # a project deliberately opting into a trivial `exit 0`/`:` verifier — that leaves an
  # executable statement, so it runs and its exit propagates; only content-free files block.)
  # R23: the parse-gate uses `bash -n`, which is valid ONLY for a shell verifier. A verifier with
  # a NON-shell shebang (#!/usr/bin/env python3, ruby, node…) is executed via that shebang, so a
  # bash-parse would WRONGLY reject a perfectly valid verifier. Apply `bash -n` only when the
  # shebang is absent or names a shell; the empty (-s) and no-executable-content gates still apply
  # to every verifier, so the fail-closed behavior for empty/no-op/broken bash verifiers is intact.
  local apply_bashn=1 shebang base interp=""
  if [ -e "${vp}" ]; then
    IFS= read -r shebang < "${vp}" || true
    case "${shebang}" in
      '#!'*)
        interp="${shebang#\#!}"
        # shellcheck disable=SC2086  # deliberate word-split of the shebang's interpreter args
        set -- ${interp}
        base="${1##*/}"
        [ "${base}" = env ] && { base="${2:-}"; base="${base##*/}"; }
        case "${base}" in
          sh|bash|dash|ksh|zsh|'') apply_bashn=1 ;;
          *) apply_bashn=0 ;;
        esac
        ;;
    esac
  fi
  if [ -e "${vp}" ] && { [ ! -s "${vp}" ] \
      || { [ "${apply_bashn}" = 1 ] && ! bash -n "${vp}" 2>/dev/null; } \
      || ! grep -qvE '^[[:space:]]*(#|$)' "${vp}"; }; then
    echo "[verify] scripts/verify-project.sh is empty or does not parse or has no executable content — FAIL-CLOSED (NOTHING was verified)" >&2
    exit 1
  fi
  if [ -x "${vp}" ]; then
    echo "[verify] delegating to project verification: ${vp}"
    if [ "${AI_AUTO_VERIFY_DIFF_SCOPE:-0}" = "1" ]; then
      echo "[verify] diff-scope metadata: scopes=${AI_AUTO_VERIFY_SCOPES:-unknown} policy=${AI_AUTO_VERIFY_SCOPE_POLICY:-unknown}"
    fi
    "${vp}"
  elif [ -e "${vp}" ]; then
    # R24: the exec bit was lost. Dispatch by shebang so a NON-shell verifier
    # (#!/usr/bin/env python3, node, ruby…) is run by its DECLARED interpreter, not bash —
    # bash would mis-parse a valid python/node verifier and wrongly BLOCK it (fail-closed
    # robustness regression). Fall back to bash only for a shell / no-shebang script.
    if [ "${apply_bashn}" = 0 ] && [ -n "${interp}" ]; then
      echo "[verify] ${vp} present but NOT executable — dispatching via its shebang interpreter (lost exec bit)" >&2
      # shellcheck disable=SC2086  # deliberate word-split of the shebang's interpreter args
      ${interp} "${vp}"
    else
      echo "[verify] ${vp} present but NOT executable — running via bash (lost exec bit)" >&2
      bash "${vp}"
    fi
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
