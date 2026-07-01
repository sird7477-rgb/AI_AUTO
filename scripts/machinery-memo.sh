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
# The marker lives under .omx/ (gitignored, project-local); it is content-addressed, so a
# stale marker for a different surface simply never matches. Plain `git` is used (not the
# review_git hardening wrapper): this path only ever runs in the TRUSTED engine self-host
# repo (both call sites gate on AI_AUTO_HOME -ef repo-root), and the pre-commit context
# does not source git-harden.sh.

: "${MACHINERY_MEMO_MARKER:=.omx/state/machinery-last-pass.sha}"

# Tested surface = the exact paths whose breakage the machinery harness gates. A content
# hash of HEAD + the worktree-vs-HEAD diff of these paths captures the tracked+staged
# state: any staged or unstaged content change to a surface file changes the diff, hence
# the hash. (An unstaged edit reverted before commit also re-matches — correct: identical
# surface, identical result.)
machinery_memo_surface_paths() {
  printf '%s\n' scripts hooks tools templates/domain-packs tests
}

machinery_memo_surface_hash() {
  # R9-DRIFT: this worktree-vs-HEAD `git diff` reads worktree blobs, so it must be inert to an
  # in-repo `.gitattributes`+`.git/config` clean/textconv/external-diff driver. Even though this
  # path only ever runs in the TRUSTED engine self-host, carry the same defense every shipped
  # worktree diff carries: `--attr-source=<empty-tree>` (ignores in-repo .gitattributes so no
  # attribute driver binds) + `--no-ext-diff`/`--no-textconv` (close the config-level drivers).
  local et
  et="$(git hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"
  {
    git rev-parse HEAD 2>/dev/null || printf 'NO_HEAD\n'
    printf '\037machinery-surface\037\n'
    # shellcheck disable=SC2046  # word-splitting the path list is intended
    git --attr-source="${et}" diff HEAD --no-ext-diff --no-textconv -- $(machinery_memo_surface_paths) 2>/dev/null || true
  } | git hash-object --stdin 2>/dev/null || true
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
