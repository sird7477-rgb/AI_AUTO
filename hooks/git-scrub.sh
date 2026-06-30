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
# NOTE: this closes the ENV surface only; the project-local `.gitattributes`/`.git/config`
# diff/filter-driver RCE is closed at the call site (review-gate.sh provenance: --no-ext-diff
# / --no-textconv / --no-filters), since env scrubbing cannot touch in-repo config.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_NAMESPACE \
      GIT_EXTERNAL_DIFF GIT_PAGER GIT_EDITOR GIT_SEQUENCE_EDITOR GIT_SSH GIT_SSH_COMMAND \
      GIT_PROXY_COMMAND GIT_ASKPASS GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM \
      GIT_TEMPLATE_DIR GIT_ATTR_NOSYSTEM GIT_CEILING_DIRECTORIES
for _gcv in "${!GIT_CONFIG_KEY_@}" "${!GIT_CONFIG_VALUE_@}" "${!GIT_TRACE@}"; do
  [ -n "$_gcv" ] && unset "$_gcv" || true
done
unset _gcv 2>/dev/null || true
