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
# CRITICAL (blue-memo): the tested surface is the WHOLE WORKING TREE, not a path-allowlist.
# verify-machinery.sh's FIRST step is `pytest -q`, and pytest.ini sets `pythonpath = .`, so
# the suite imports this repo's PRODUCT code from the ROOT (app.py, incident_ops.py,
# repository.py, config/, ...) — files OUTSIDE any hand-picked path list. A previous version
# hashed only `scripts hooks tools templates/domain-packs tests`; breaking a root product
# file left that hash byte-identical -> FALSE SKIP -> a broken tree committed green. The fix:
# hash the exact content the suite can see — every tracked + untracked-non-ignored file as it
# exists on disk — by writing a throwaway-index tree of the worktree (`git add -A` +
# `write-tree`, honoring .gitignore/exclude so the .omx/ marker itself is not hashed). This
# makes the hashed surface EQUAL the tested surface, so false-skip is structurally impossible,
# and it deletes the drift-prone allowlist. The marker key also folds in the worktree identity
# (--show-toplevel) so a PASS in worktree A can never satisfy a skip in worktree B.
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
machinery_memo_surface_hash() {
  local idx tree top
  idx="$(mktemp 2>/dev/null)" || return 0
  rm -f "${idx}"   # git rejects a 0-byte index; remove so it writes a fresh one at this path
  GIT_INDEX_FILE="${idx}" review_git add -A >/dev/null 2>&1
  tree="$(GIT_INDEX_FILE="${idx}" review_git write-tree 2>/dev/null || true)"
  rm -f "${idx}"
  [ -n "${tree}" ] || return 0
  top="$(review_git rev-parse --show-toplevel 2>/dev/null || printf 'NO_TOP')"
  printf '%s\037%s\n' "${top}" "${tree}" | review_git hash-object --stdin 2>/dev/null || true
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

# Record a PASS for the CURRENT surface. Call ONLY after verify-machinery.sh exited 0.
machinery_memo_record_pass() {
  local hash
  hash="$(machinery_memo_surface_hash)"
  [ -n "${hash}" ] || return 0
  mkdir -p "$(dirname "${MACHINERY_MEMO_MARKER}")" 2>/dev/null || return 0
  printf '%s\n' "${hash}" > "${MACHINERY_MEMO_MARKER}" 2>/dev/null || true
}

# The loud one-liner the fold prints when it skips (kept identical at both call sites).
machinery_memo_skip_notice() {
  local hash
  hash="$(machinery_memo_surface_hash)"
  echo "[skip] machinery unchanged since last PASS (surface ${hash:0:12})"
}
