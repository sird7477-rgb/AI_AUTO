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

# R22 (hook RCE): git subcommands here fire repo hooks and HONOR a repo-local `core.hooksPath`.
#   - `rebase`/`fetch` do NOT need any project hook for safe-push, so they are pinned to
#     `core.hooksPath=/dev/null` (a hostile core.hooksPath / tracked `.git/hooks/*` in a copied
#     repo would otherwise run 6 rebase hooks + fetch hooks as the operator — RCE).
#   - `push` MUST still run the INTENDED pre-push validation (never bypassed — the whole point of
#     safe-push), so it is pinned to the repo's REAL hooks dir. That defeats a hostile core.hooksPath
#     that would REDIRECT (hijack) or point away from (bypass) the validation, while preserving it.
#     The real dir is derived from `--git-common-dir` (which core.hooksPath cannot influence), so the
#     resolution itself is not hijackable; falls back to `.git/hooks` if resolution fails.
_gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
REAL_HOOKS="${_gcd:-.git}/hooks"

i=0
while : ; do
  i=$((i + 1))
  echo "[safe-push] attempt ${i}/${MAX}: git push ${REMOTE} HEAD:${BRANCH}"
  out="$(git -c core.hooksPath="${REAL_HOOKS}" push "${REMOTE}" "HEAD:${BRANCH}" 2>&1)"; rc=$?
  printf '%s\n' "${out}"
  if [ "${rc}" -eq 0 ]; then
    echo "[safe-push] pushed to ${REMOTE}/${BRANCH} on attempt ${i}."
    exit 0
  fi
  # Retry ONLY a stale/non-fast-forward rejection. Match git's OWN rejection strings
  # (`! [rejected]`, the `(non-fast-forward)`/`(fetch first)` parenthesised reasons, the
  # "Updates were rejected because" hint) — case-sensitive and shaped so a pre-push hook's
  # free-text message (e.g. "please fetch first") cannot false-trigger a retry. A hook block,
  # an auth error, or any other non-race failure surfaces as-is — a rebase would be wrong.
  if ! printf '%s' "${out}" | grep -qE '! \[rejected\]|\(non-fast-forward\)|\(fetch first\)|Updates were rejected because'; then
    echo "[safe-push] push failed for a non-race reason (validation block / auth / other) — not retrying." >&2
    exit "${rc}"
  fi
  if [ "${i}" -ge "${MAX}" ]; then
    echo "[safe-push] still non-fast-forward after ${MAX} attempts; giving up. Re-run safe-push, or rebase + push manually." >&2
    exit 1
  fi
  echo "[safe-push] non-fast-forward — fetching ${REMOTE}/${BRANCH} ..."
  before="$(git rev-parse "${REMOTE}/${BRANCH}" 2>/dev/null || echo none)"
  if ! git -c core.hooksPath=/dev/null fetch "${REMOTE}" "${BRANCH}"; then
    echo "[safe-push] fetch failed — aborting." >&2
    exit 1
  fi
  after="$(git rev-parse "${REMOTE}/${BRANCH}" 2>/dev/null || echo none)"
  # Definitive race confirmation: only rewrite local history (rebase) if the remote ref
  # ACTUALLY advanced. If it did not, the rejection was not a lost race (a stale grep match,
  # a server-side hook, a protected branch) — never rebase/loop on that.
  if [ "${before}" = "${after}" ]; then
    echo "[safe-push] ${REMOTE}/${BRANCH} did not advance — the rejection was not a race; not rebasing. Resolve the push failure above and retry." >&2
    exit 1
  fi
  echo "[safe-push] rebasing onto ${REMOTE}/${BRANCH} (${before:0:7}..${after:0:7}) ..."
  if ! git -c core.hooksPath=/dev/null rebase "${REMOTE}/${BRANCH}"; then
    git -c core.hooksPath=/dev/null rebase --abort 2>/dev/null || true
    echo "[safe-push] rebase hit a conflict the version merge driver could not auto-resolve." >&2
    echo "[safe-push] resolve it manually:  git rebase ${REMOTE}/${BRANCH}   then re-run safe-push." >&2
    exit 1
  fi
  sleep "${BACKOFF}"
done
