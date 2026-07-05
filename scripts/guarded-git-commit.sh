#!/usr/bin/env bash
# Guard git commit calls against silent no-commit outcomes.
#
# This wrapper is intentionally thin: it preserves normal git commit behavior,
# including the repository's real hooks, then asserts that a commit attempt with
# staged content actually moved HEAD.
set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hooks/git-scrub.sh
. "${script_dir}/../hooks/git-scrub.sh"

git_without_scrubbed_hookspath() {
  env -u GIT_CONFIG_PARAMETERS \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=core.fsmonitor \
    GIT_CONFIG_VALUE_0= \
    git "$@"
}

top_level="$(git_without_scrubbed_hookspath rev-parse --show-toplevel 2>/dev/null || true)"
common_dir="$(git_without_scrubbed_hookspath rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
configured_hooks="$(git_without_scrubbed_hookspath config --path --get core.hooksPath 2>/dev/null || true)"
if [ -n "${configured_hooks}" ] && [ -n "${top_level}" ] && [ -n "${common_dir}" ]; then
  case "${configured_hooks}" in
    /*) configured_hooks_abs="${configured_hooks}" ;;
    *) configured_hooks_abs="${top_level}/${configured_hooks}" ;;
  esac
  configured_hooks_abs="$(realpath -m -- "${configured_hooks_abs}")"
  default_hooks_abs="$(realpath -m -- "${common_dir}/hooks")"
  if [ "${configured_hooks_abs}" != "${default_hooks_abs}" ]; then
    printf '[guarded-git-commit] refusing non-default core.hooksPath: %s\n' "${configured_hooks}" >&2
    exit 1
  fi
fi

before_head="$(git rev-parse --verify HEAD 2>/dev/null || true)"

staged_before=0
if ! git -c core.fsmonitor= diff --cached --quiet --exit-code >/dev/null 2>&1; then
  staged_before=1
fi

if [ "${staged_before}" -eq 1 ] && [ -x "${script_dir}/worktree-write-guard.sh" ]; then
  "${script_dir}/worktree-write-guard.sh" check commit || exit $?
fi

set +e
git_without_scrubbed_hookspath commit "$@"
commit_rc=$?
set -e

after_head="$(git rev-parse --verify HEAD 2>/dev/null || true)"

staged_after=0
if ! git -c core.fsmonitor= diff --cached --quiet --exit-code >/dev/null 2>&1; then
  staged_after=1
fi

if [ "${staged_before}" -eq 1 ] && [ "${before_head}" = "${after_head}" ]; then
  if [ "${staged_after}" -eq 1 ]; then
    printf '[guarded-git-commit] no new HEAD after commit attempt; staged changes remain. Check the commit message source/quoting and retry.\n' >&2
  else
    printf '[guarded-git-commit] no new HEAD after commit attempt even though staged changes existed before the command.\n' >&2
  fi
  exit 1
fi

exit "${commit_rc}"
