# shellcheck shell=bash
# AI_AUTO machinery self-test memoization (OPCOST-HIGH-1) — THE single source of truth.
# Sourced (after AI_AUTO_HOME/cwd=repo-root is established) by BOTH machinery-fold call
# sites: the gate (scripts/review-gate.sh) and the engine self-host pre-commit hook
# (hooks/pre-commit). The full engine self-test (scripts/verify-machinery.sh, ~6min) used
# to run TWICE per change->commit cycle — once in the gate and again in the very next
# commit's pre-commit — over an IDENTICAL tested surface. We record a PASS marker keyed by
# a content hash of that surface; a subsequent fold on a byte-identical surface SKIPS the
# re-run. SAFE-SIDE: skip ONLY on an EXACT surface-hash match; ANY change to the tested
# surface changes the hash -> marker miss -> full run. Any hashing hiccup -> no skip.
#
# SCOPE (blue-conc — read honestly): this memo is a SAME-WINDOW TWIN-RUN OPTIMIZATION, not a
# general verification oracle. It skips the pre-commit re-run ONLY when the surface it can see is
# byte-identical to the surface the immediately-preceding gate PASSed. The covered surface is:
#   (a) the WHOLE WORKING TREE the suite can see — every tracked + untracked-non-ignored file as it
#       exists on disk — captured as a throwaway-index tree OID (`git add -A` + `write-tree`,
#       honoring .gitignore/exclude so the .omx/ marker itself is not hashed); AND
#   (b) the INTERPRETER IDENTITY that actually runs pytest — .venv/pyvenv.cfg + `python --version`
#       + the installed-package dist-info manifest — so swapping/upgrading the venv invalidates
#       the skip (verify-machinery.sh runs `.venv/bin/python -m pytest`, whose result depends on it).
# The key also folds the worktree toplevel path (--show-toplevel) so a PASS in worktree A can never
# satisfy a skip in worktree B.
#
# NOT covered (out of the memo's scope, by construction): unbounded external inputs a test could
# read that live outside the worktree tree AND outside the interpreter identity above — arbitrary
# gitignored files, $PYTHONPATH pointing elsewhere, network/clock/env. This memo does NOT claim to
# detect those; it is a twin-run cache within one edit->gate->commit window, where such inputs do
# not change between the gate PASS and the very next pre-commit. A subsequent version reasons about
# a wider surface only if that window widens. So: the tested surface EQUALS the recorded surface for
# (a)+(b) by construction, but "false-skip is impossible for ANY input" would be an OVERCLAIM.
#
# TIME-OF-RECORD (blue-conc H1): record_pass records the hash that was ACTUALLY TESTED (captured
# BEFORE verify ran and passed in), not a fresh re-hash of the live worktree. If a concurrent session
# mutates the tree during the ~6min verify window, the live hash no longer matches the tested hash and
# record_pass DECLINES to record (fail-safe -> the next fold re-verifies the new surface). The tested
# surface and the recorded surface are therefore identical by construction — a passing verdict can
# never be attributed to an untested (possibly broken) surface.
#
# The marker lives under .omx/ (gitignored, project-local); it is content-addressed, so a
# stale marker for a different surface simply never matches. All git access goes through the
# hardened review_git wrapper (scripts/git-harden.sh) — never a bare `git` — so the
# clean/textconv/external-diff/fsmonitor code-exec surface stays closed even here.

: "${MACHINERY_MEMO_MARKER:=.omx/state/machinery-last-pass.sha}"

# review_git (scripts/git-harden.sh) is the ONLY git entry point used below. The gate already
# sources it; the pre-commit context does not — so pull it in if absent (from this file's dir).
if ! command -v review_git >/dev/null 2>&1; then
  # shellcheck source=scripts/git-harden.sh
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-harden.sh"
fi

# Tested surface = the ENTIRE worktree content the suite can see. Compute a tree OID of the
# current worktree (tracked + untracked-non-ignored, exact on-disk bytes) via a THROWAWAY
# index so the real index is untouched; `git add -A` respects .gitignore/.git-info-exclude, so
# the .omx/ marker is not part of the tree. Fold the worktree toplevel path into the final hash
# (Finding-3: cross-worktree marker bleed) so an identical tree in a DIFFERENT worktree hashes
# differently. Any failure -> empty hash -> fail-closed to "do not skip".
# Interpreter identity that ACTUALLY runs pytest (H2): a change to the venv/interpreter can flip
# PASS<->FAIL while the worktree tree is byte-identical, so fold a cheap, stable digest of it into
# the key. Inputs, all CHEAP (no version resolver, no mtime): pyvenv.cfg content, `python --version`,
# and the dist-info directory NAMES under site-packages (each encodes pkg-version). Deliberately does
# NOT hash all of .venv (expensive / mtime-unstable). Missing venv -> stable empty-ish digest, so a
# sandbox with no .venv still hashes consistently across calls. Override the interpreter path for
# tests via MACHINERY_MEMO_PYTHON.
machinery_memo_interp_hash() {
  local py="${MACHINERY_MEMO_PYTHON:-.venv/bin/python}"
  {
    [ -f .venv/pyvenv.cfg ] && cat .venv/pyvenv.cfg 2>/dev/null
    [ -x "${py}" ] && "${py}" --version 2>&1
    ls -1d .venv/lib/python*/site-packages/*.dist-info 2>/dev/null \
      | sed 's#.*/##' | LC_ALL=C sort
  } 2>/dev/null | review_git hash-object --stdin 2>/dev/null || true
}

machinery_memo_surface_hash() {
  local idx tree top interp
  idx="$(mktemp 2>/dev/null)" || return 0
  rm -f "${idx}"   # git rejects a 0-byte index; remove so it writes a fresh one at this path
  GIT_INDEX_FILE="${idx}" review_git add -A >/dev/null 2>&1
  tree="$(GIT_INDEX_FILE="${idx}" review_git write-tree 2>/dev/null || true)"
  rm -f "${idx}"
  [ -n "${tree}" ] || return 0
  top="$(review_git rev-parse --show-toplevel 2>/dev/null || printf 'NO_TOP')"
  interp="$(machinery_memo_interp_hash)"
  printf '%s\037%s\037%s\n' "${top}" "${tree}" "${interp}" | review_git hash-object --stdin 2>/dev/null || true
}

# True (exit 0) when a PASS marker exists whose recorded hash EXACTLY equals the current
# surface hash. Fail-closed to "do not skip" on any missing/mismatched/unreadable state.
machinery_memo_should_skip() {
  local hash recorded
  hash="$(machinery_memo_surface_hash)"
  [ -n "${hash}" ] || return 1
  [ -f "${MACHINERY_MEMO_MARKER}" ] || return 1
  recorded="$(cat "${MACHINERY_MEMO_MARKER}" 2>/dev/null || true)"
  [ -n "${recorded}" ] && [ "${recorded}" = "${hash}" ]
}

# Record a PASS for the surface that was ACTUALLY TESTED. Call ONLY after verify-machinery.sh
# exited 0, passing the surface hash captured BEFORE verify started ($1). H1 fail-safe: re-hash the
# LIVE tree and record ONLY if it still equals the tested hash; if a concurrent session mutated the
# worktree during the verify window the live hash differs, so we DECLINE to record (the next fold
# re-verifies the changed surface) rather than attribute the PASS to an untested surface. With no
# tested hash supplied (legacy caller), fall back to recording the current live hash.
machinery_memo_record_pass() {
  local tested="${1:-}" live
  live="$(machinery_memo_surface_hash)"
  [ -n "${live}" ] || return 0
  if [ -n "${tested}" ] && [ "${tested}" != "${live}" ]; then
    return 0   # worktree changed during verify -> do NOT record an untested surface
  fi
  mkdir -p "$(dirname "${MACHINERY_MEMO_MARKER}")" 2>/dev/null || return 0
  printf '%s\n' "${tested:-${live}}" > "${MACHINERY_MEMO_MARKER}" 2>/dev/null || true
}

# The loud one-liner the fold prints when it skips (kept identical at both call sites).
machinery_memo_skip_notice() {
  local hash
  hash="$(machinery_memo_surface_hash)"
  echo "[skip] machinery unchanged since last PASS (surface ${hash:0:12})"
}
