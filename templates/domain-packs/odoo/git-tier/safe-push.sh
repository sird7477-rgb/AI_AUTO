#!/usr/bin/env bash
# safe-push: push to a shared branch with automatic fetch+rebase retry on a lost race
# (ST-P1-73(B)). On a busy shared branch (many concurrent AI sessions) a push is often
# rejected non-fast-forward because a sibling pushed first; the manual fix is fetch ->
# rebase -> push, repeated. This wraps that loop with a bounded retry. It composes with:
#   - the pre-push hook (validation still runs on EVERY push attempt — never bypassed),
#     made cheap on a pure rebase by the validate-warm warm-PASS cache (ST-P1-73(A));
#   - the __manifest__.py version merge driver (ST-P1-74), which auto-resolves the
#     per-commit version-line conflict that otherwise stalls every rebase.
#
# It NEVER force-pushes and NEVER skips validation. A rebase conflict the merge driver
# cannot resolve, or a push failure that is NOT a race (a validation block, an auth error),
# stops the loop immediately and hands back to you — retrying those would be wrong.
#
# Usage:  safe-push.sh [remote] [branch]      (defaults: origin, current branch)
# Env:    SAFE_PUSH_MAX_TRIES (default 5), SAFE_PUSH_BACKOFF seconds (default 2)
set -uo pipefail

REMOTE="${1:-origin}"
BRANCH="${2:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)}"
MAX="${SAFE_PUSH_MAX_TRIES:-5}"
BACKOFF="${SAFE_PUSH_BACKOFF:-2}"

[ "$BRANCH" = "HEAD" ] && { echo "[safe-push] detached HEAD — refusing to guess a target branch." >&2; exit 2; }

i=0
while : ; do
  i=$((i + 1))
  echo "[safe-push] attempt ${i}/${MAX}: git push ${REMOTE} HEAD:${BRANCH}"
  out="$(git push "${REMOTE}" "HEAD:${BRANCH}" 2>&1)"; rc=$?
  printf '%s\n' "${out}"
  if [ "${rc}" -eq 0 ]; then
    echo "[safe-push] pushed to ${REMOTE}/${BRANCH} on attempt ${i}."
    exit 0
  fi
  # Retry ONLY a stale/non-fast-forward rejection. A hook block (validation failure), an
  # auth error, or any other non-race failure must surface as-is — a rebase would not help
  # and re-pushing would be wrong.
  if ! printf '%s' "${out}" | grep -qiE 'non-fast-forward|fetch first|\[rejected\]|tip of your current branch is behind'; then
    echo "[safe-push] push failed for a non-race reason (validation block / auth / other) — not retrying." >&2
    exit "${rc}"
  fi
  if [ "${i}" -ge "${MAX}" ]; then
    echo "[safe-push] still non-fast-forward after ${MAX} attempts; giving up. Re-run safe-push, or rebase + push manually." >&2
    exit 1
  fi
  echo "[safe-push] non-fast-forward — fetching and rebasing onto ${REMOTE}/${BRANCH} ..."
  if ! git fetch "${REMOTE}" "${BRANCH}"; then
    echo "[safe-push] fetch failed — aborting." >&2
    exit 1
  fi
  if ! git rebase "${REMOTE}/${BRANCH}"; then
    git rebase --abort 2>/dev/null || true
    echo "[safe-push] rebase hit a conflict the version merge driver could not auto-resolve." >&2
    echo "[safe-push] resolve it manually:  git rebase ${REMOTE}/${BRANCH}   then re-run safe-push." >&2
    exit 1
  fi
  sleep "${BACKOFF}"
done
