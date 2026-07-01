#!/usr/bin/env bash
# Hardened-git wrapper — single source of truth (sourced, never executed).
#
# review_git() neutralizes git's PROJECT-LOCAL code-exec surface: a `.gitattributes`
# (e.g. `a.txt diff=evil`) plus a `.git/config` external-diff `command` / `textconv` /
# `clean` filter driver runs ATTACKER code through any patch-producing git call. Env
# scrubbing (hooks/git-scrub.sh) CANNOT touch this because it lives IN the repo, so it
# must be defeated at the call site:
#   - `-c diff.external=`           kills a config-level external diff program.
#   - `-c core.attributesFile=/dev/null` ignores a user/global attributes file.
#   - `-c core.fsmonitor=`         kills an fsmonitor hook program.
#   - `--attr-source=<empty-tree>` (global, BEFORE the subcommand) makes git read .gitattributes
#     from the EMPTY TREE, so an IN-REPO `.gitattributes` (which `core.attributesFile` does NOT
#     override) cannot bind a clean/smudge/textconv/external-diff driver on ANY worktree-side diff
#     routed through this wrapper. This is the COMPREHENSIVE central fix for the clean-filter RCE
#     residual: a `--name-only`/`--stat`/`--quiet` worktree diff still runs the in-repo CLEAN
#     filter to detect a change (R9's key finding), and `--no-ext-diff`/`--no-textconv` do NOT
#     disarm `clean` — only `--attr-source` does. It is harmless on `--cached`/range/`show`/
#     `hash-object` (attributes simply come from the empty tree) and transparent to `--no-index`,
#     so it lives unconditionally in this ONE wrapper and hardens every engine worktree diff.
#   - callers ALSO pass `--no-ext-diff --no-textconv` on every patch-producing diff and
#     `--no-filters` on hash-object / `--no-index` content reads (the per-attr drivers).
#
# Single-sourced so review-gate.sh, summarize-ai-reviews.sh, and collect-review-context.sh
# share ONE implementation and a newly added patch-producing call cannot drift un-hardened.
#
# SECURITY TRADE-OFF (benign-filter false-dirty — UNAVOIDABLE, SAFE-SIDE): `--attr-source=<empty
# -tree>` ignores the IN-REPO `.gitattributes`, which is what closes the hostile-repo clean/
# smudge-filter RCE. But git cannot tell a MALICIOUS filter from a BENIGN one (EOL normalization,
# git-lfs, a legit clean filter), so it disables ALL of them. Consequence: over a NORMAL project
# that legitimately uses such a filter, a worktree-read status/diff routed through review_git may
# report a genuinely-clean tree as MODIFIED (git-lfs is the canonical victim — every lfs blob
# shows ` M`). This NEVER flips a gate verdict and NEVER loses/mutates work: it errs strictly
# toward "dirty/keep" in advisory tooling (automation-doctor WARN, ai-tmux-worktree keep:
# uncommitted, checkpoint churn). A filter-aware fallback is impossible (indistinguishable) and
# is intentionally NOT attempted; the safe over-report is accepted. See docs/NEW_PROJECT_GUIDE.md.
#
# Empty-tree OID in the repo's hash algo (sha1 constant 4b825dc6… as fallback), computed once at
# source time in the project repo's CWD — mirrors how the domain-pack validators derive it.
_REVIEW_GIT_ATTR_NONE="$(git hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"

# FAIL-CLOSED guard for the ONE attributes source `--attr-source` CANNOT redirect:
# `$GIT_DIR/info/attributes`, git's HIGHEST-precedence attributes file. `--attr-source` /
# `GIT_ATTR_SOURCE` only relocate the IN-TREE `.gitattributes` lookup; `core.attributesFile`
# only overrides the GLOBAL file and `GIT_ATTR_NOSYSTEM` only the SYSTEM file — EMPIRICALLY
# (git 2.43, canary-tested) NO per-invocation switch neutralizes `info/attributes`, and a
# clean/smudge/textconv driver bound there still executes its `.git/config` command through a
# hardened worktree read (e.g. `review_git diff --quiet` runs the clean filter to detect a
# change). Under this tool's threat model the repo directory is untrusted (tarball/copy carries
# `.git/info/attributes` + `.git/config`; the same model the core.fsmonitor env-pin already
# defends), so this is a CRITICAL RCE. A `filter`/`diff` driver bound via `info/attributes` can
# only be HOSTILE-OR-USELESS here: LEGITIMATE filters (git-lfs, EOL normalization) bind via the
# TRACKED `.gitattributes`, NEVER `info/attributes`, and this review/inspection path wants RAW,
# UNFILTERED content anyway. So REFUSE before the op touches worktree content — no false positive
# on any real project. (`git clone` never transfers `info/attributes`; only a directory copy does,
# which is exactly the untrusted-input case.) `rev-parse` reads no worktree blob and runs no attr
# driver (git's own FILTER-SAFE class), so resolving the git dir through it is safe.
_review_git_attr_guard() {
  local _gd _ia
  # A linked worktree reads info/attributes from the COMMON dir, a plain repo from the git dir;
  # check both. Either resolution failing (e.g. a `--no-index` compare outside any repo) is fine.
  for _gd in "$(git rev-parse --git-dir 2>/dev/null)" "$(git rev-parse --git-common-dir 2>/dev/null)"; do
    [ -n "${_gd}" ] && _ia="${_gd}/info/attributes" && [ -f "${_ia}" ] || continue
    # A non-comment line binding a `filter=`/`diff=` DRIVER to ANY non-empty driver NAME is the RCE.
    # Match a POSITIVE name token `=[^[:space:]]` (`=` + ANY non-space, INCLUDING a leading `-`).
    # A negated class that also excluded `-` (`=[^[:space:]-]`) let a driver NAMED with a leading
    # dash slip through: `filter=-x` binds `[filter "-x"]` and git EXECUTES its .git/config clean
    # driver (canary-proven RCE); `diff=-y` external-diff/textconv evades identically on a patch-
    # producing read. `-i` also refuses uppercase `FILTER=`/`DIFF=` (git attr names are case-
    # sensitive so these do NOT bind — refusing is safe-side, no legit line uses them) and the
    # match spans every evasion shape: leading/trailing whitespace or tabs (`[[:space:]]` anchor),
    # the attr as a 2nd+ token, a quoted value (`=` + `"`), and a macro definition
    # (`[attr]m filter=evil` — the driver name appears on the macro line and is caught there).
    # EXEMPT (no exec driver, no refusal): comments (`#`), unset/boolean attrs (`-text`, `text`,
    # `eol=lf`), an attribute-unset `-filter` (no `=value`), an empty `filter=` (no name token),
    # and a git-lfs/EOL filter — which bind via the TRACKED `.gitattributes`, NEVER info/attributes.
    # `merge=` is NOT matched: empirically no merge driver execs on any op review_git reaches
    # (add/diff/status/rm/show/hash-object/rev-parse; merge drivers run only on `git merge`/
    # `checkout -m`, which the review path never invokes), so binding it here is inert.
    #
    # CRITICAL — LC_ALL=C (byte semantics): git's attribute parser splits `info/attributes` lines
    # on ASCII whitespace ONLY (space, tab, newline, CR, VT, FF — see git's `attr.c` isspace/strtok
    # over the raw bytes). But GNU grep's `[[:space:]]`/`[^[:space:]]` follow the LOCALE ctype table
    # under a MULTIBYTE locale (LC_ALL=*.UTF-8): it classifies Unicode whitespace codepoints — U+00A0
    # NBSP, U+2000, U+202F, U+3000, … (which of them depends on the libc's ctype table) — as space.
    # So a driver NAMED with a leading Unicode-space codepoint (`filter=<U+2000>x`, `[filter "<U+2000>x"]`
    # in .git/config) made `=[^[:space:]]` NOT match under a UTF-8 locale → the guard ALLOWED, yet git
    # kept those non-ASCII bytes AS the driver name and EXECUTED the clean/diff driver (canary-proven
    # RCE — the 3rd bypass of this guard after env-GIT_CONFIG and leading-dash `-x`). Forcing LC_ALL=C
    # makes `[[:space:]]` = ASCII whitespace ONLY — EXACTLY git's split set — so a name led by ANY
    # non-ASCII-space byte (0xC2/0xE2/0xE3/… of NBSP/U+2000/U+3000/U+202F/every other codepoint) is
    # correctly a non-space driver-name char → `=[^[:space:]]` MATCHES → REFUSE. Byte matching closes
    # the WHOLE class, not one codepoint: any name that git accepts is now a name the guard rejects,
    # independent of the ambient locale's Unicode ctype table. BOTH greps run under LC_ALL=C so the
    # comment/blank strip (`^[[:space:]]*(#|$)`) also uses ASCII-only leading-whitespace, mirroring
    # git (a line led by a Unicode-space byte is NOT a comment/blank to git, and must not be dropped).
    if LC_ALL=C grep -Ev '^[[:space:]]*(#|$)' "${_ia}" 2>/dev/null \
         | LC_ALL=C grep -Eiq '(^|[[:space:]])(filter|diff)=[^[:space:]]'; then
      printf 'review_git: REFUSING — %s binds a filter/diff driver. That is git'"'"'s highest-precedence attributes file, which NO per-invocation switch (--attr-source/GIT_ATTR_SOURCE/core.attributesFile/GIT_ATTR_NOSYSTEM) can neutralize, so an untrusted repo can execute arbitrary clean/smudge/diff .git/config commands through this hardened read. Legit filters bind via the tracked .gitattributes; the review path needs raw content. Refusing.\n' "${_ia}" >&2
      return 3
    fi
  done
  return 0
}

review_git() {
  # Fail-closed: refuse if the untrusted repo carries a hostile info/attributes driver binding —
  # the residual RCE that bypasses the --attr-source neutralization below (see guard rationale).
  _review_git_attr_guard || return
  # `--no-index` content reads (two raw filesystem paths, not a worktree-vs-tree diff) are NOT
  # given --attr-source: their attribute-driver defense is the `--no-filters` flag the caller
  # already passes (which fully disables clean/smudge/textconv). attr-source is irrelevant there
  # and would only mask whether --no-filters is doing its job. Every OTHER form (worktree diff,
  # --cached, range, show, hash-object) gets the central --attr-source — harmless on the non-
  # worktree ones, and the comprehensive clean/textconv/external defense on worktree diffs.
  case " $* " in
    *" --no-index "*)
      git -c diff.external= -c core.fsmonitor= -c core.attributesFile=/dev/null --no-pager "$@" ;;
    *)
      git --attr-source="${_REVIEW_GIT_ATTR_NONE}" -c diff.external= -c core.fsmonitor= -c core.attributesFile=/dev/null --no-pager "$@" ;;
  esac
}
