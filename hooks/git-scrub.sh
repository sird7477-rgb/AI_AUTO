# shellcheck shell=bash
# AI_AUTO canonical git-exec-env scrub — THE single source of truth (F1). Sourced (after
# AI_AUTO_HOME is resolved) by the launcher `tools/ai-auto`, both engine hooks
# `hooks/{pre,post}-commit`, and the baked per-project shim. Do NOT inline a copy elsewhere:
# one list, no drift.
#
# git reads these from the ENVIRONMENT and they OVERRIDE `git -C` / cwd discovery, so an
# inherited (poisoned-parent) value is wrong-repo / wrong-store / arbitrary-command execution
# through any git call the engine makes:
#   - GIT_DIR family            : redirect git at a victim repo
#   - GIT_CONFIG_* injection     : inject core.hooksPath / core.fsmonitor -> RCE
#   - command-exec vars          : GIT_EXTERNAL_DIFF/PAGER/EDITOR/SSH/PROXY/ASKPASS = run a command
#   - object-dir overrides       : read/write the wrong object store
#   - GIT_TRACE* (R5-2)          : append/clobber an attacker-chosen absolute path on every git op
#   - GIT_TEMPLATE_DIR + attr/ceiling (R5-3): inject hooks into `git init` fixtures -> RCE
# NOTE: the unset above closes the ENV surface only. The project-local `.git/config`
# `core.fsmonitor` exec vector is then closed for EVERY git call by the defensive
# GIT_CONFIG_* re-export below (env-config overrides repo-local config). The repo-local
# `diff.external` exec vector and the `.gitattributes` ATTRIBUTE-driven diff/textconv/filter
# drivers — which an EMPTY config override cannot neutralize (diff.external='' = run the
# empty program = `fatal: external diff died`) — stay closed at the call site. Note the
# clean/smudge FILTER is NOT closed by `--no-ext-diff`/`--no-textconv` alone: a worktree-vs-tree
# `git diff <base> -- <path>` still runs the in-repo `.gitattributes` clean filter through both
# flags. So the call-site defense is:
#   - engine review_git:       `--attr-source=<empty-tree> -c diff.external= --no-ext-diff
#                              --no-textconv`, plus `--no-filters` on the `--no-index` content read.
#                              The central `--attr-source` (in scripts/git-harden.sh) closes the
#                              worktree clean-filter RCE for EVERY engine worktree diff routed
#                              through review_git (incl. `--name-only`/`--stat`/`--quiet`), not just
#                              the patch-producing ones — the two flags alone do NOT disarm `clean`;
#   - odoo QC python validators + validate-warm worktree diffs: `--attr-source=<empty-tree>
#                              --no-ext-diff --no-textconv` (attr-source ignores the in-repo
#                              `.gitattributes` so clean/smudge/textconv/diff attribute drivers
#                              cannot bind; tree-vs-tree `up...HEAD` diffs need only the two flags).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_NAMESPACE \
      GIT_EXTERNAL_DIFF GIT_PAGER GIT_EDITOR GIT_SEQUENCE_EDITOR GIT_SSH GIT_SSH_COMMAND \
      GIT_PROXY_COMMAND GIT_ASKPASS GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM \
      GIT_TEMPLATE_DIR GIT_ATTR_NOSYSTEM GIT_CEILING_DIRECTORIES
for _gcv in "${!GIT_CONFIG_KEY_@}" "${!GIT_CONFIG_VALUE_@}" "${!GIT_TRACE@}"; do
  [ -n "$_gcv" ] && unset "$_gcv" || true
done
unset _gcv 2>/dev/null || true

# --- R7-F1 defensive config override (BEGIN) --------------------------------
# `core.fsmonitor` living in a malicious project's IN-REPO `.git/config` is a code-exec
# vector that fires on EVERY worktree-scanning git call (`git status`, `git ls-files`,
# `git diff --name-only/--quiet/--stat`) — not just the patch-producing calls routed
# through review_git(). The env unset above CANNOT reach an in-repo config. But env
# GIT_CONFIG_* has HIGHER precedence than repo-local `.git/config`, so after the
# anti-injection unset we re-export a CONTROLLED pair that pins `core.fsmonitor` EMPTY for
# every git call in this process AND its children. `core.fsmonitor=''` == disabled, so it
# is functionally inert except to neutralize the hook-program vector.
#
# R8-H8-1: `diff.external` is DELIBERATELY NOT pinned here. An empty env value is NOT
# equivalent to `--no-ext-diff`: git treats `diff.external=''` as "run the empty program"
# and EVERY plain patch-producing `git diff` dies with `fatal: external diff died` (exit
# 128, empty patch) — a process-wide DoS, not a defense. There is no env-config equivalent
# of `--no-ext-diff`. The config-level external-diff RCE is therefore closed at the CALL
# SITE instead: review_git() passes `-c diff.external= --no-ext-diff --no-textconv` on every
# patch-producing diff, and the shipped odoo QC validators pass `--attr-source=<empty-tree>
# --no-ext-diff --no-textconv` (the clean filter needs the attr-source, not just the two flags).
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0='core.fsmonitor' GIT_CONFIG_VALUE_0=''
# --- R7-F1 defensive config override (END) ----------------------------------
