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
# Empty-tree OID in the repo's hash algo (sha1 constant 4b825dc6… as fallback), computed once at
# source time in the project repo's CWD — mirrors how the domain-pack validators derive it.
_REVIEW_GIT_ATTR_NONE="$(git hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"
review_git() {
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
