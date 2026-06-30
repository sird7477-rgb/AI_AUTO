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
# CONFIG-key exec vectors (core.fsmonitor / diff.external) are then closed for EVERY git call
# by the defensive GIT_CONFIG_* re-export below (env-config overrides repo-local config). The
# `.gitattributes` ATTRIBUTE-driven diff/textconv/filter drivers, which a config override
# cannot fully neutralize, stay closed at the call site (review_git: --no-ext-diff /
# --no-textconv / --no-filters).
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
# `core.fsmonitor` / `diff.external` living in a malicious project's IN-REPO `.git/config`
# are a code-exec vector that fires on EVERY worktree-scanning git call (`git status`,
# `git ls-files`, `git diff --name-only/--quiet/--stat`) — not just the patch-producing
# calls routed through review_git(). The env unset above CANNOT reach an in-repo config.
# But env GIT_CONFIG_* has HIGHER precedence than repo-local `.git/config`, so after the
# anti-injection unset we re-export a CONTROLLED pair set that pins those exec keys EMPTY
# for every git call in this process AND its children. One process-level chokepoint thus
# neutralizes the config-driven exec vectors at ~15 plain-`git` sites without touching any
# call site. (review_git ALSO keeps --no-ext-diff/--no-textconv/--no-filters for the
# `.gitattributes` attribute-driven drivers that a config override cannot fully neutralize.)
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0='core.fsmonitor' GIT_CONFIG_VALUE_0=''
export GIT_CONFIG_KEY_1='diff.external'  GIT_CONFIG_VALUE_1=''
# --- R7-F1 defensive config override (END) ----------------------------------
