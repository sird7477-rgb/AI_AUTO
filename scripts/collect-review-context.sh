#!/usr/bin/env bash
set -euo pipefail

# git-harden.sh MUST be sourced FIRST: the module-load `git status --porcelain` below runs
# during `ai-auto gate` over a potentially hostile project, so review_git (whose central
# --attr-source=<empty-tree> disarms an in-repo .gitattributes+`.git/config` clean filter)
# has to be defined before that first worktree-reading git call executes.
CRC_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=scripts/git-harden.sh
. "${AI_AUTO_GIT_HARDEN_SH:-${CRC_DIR}/git-harden.sh}"
# R21-STANDALONE: this collector is a DOCUMENTED standalone entrypoint (`./scripts/collect-review-
# context.sh`; also run mid-`ai-auto gate`). review_git closes the clean-filter vector, but several
# BARE (non-review_git) worktree-scanning calls remain — `git diff --cached --name-only` (index vs
# HEAD), `git ls-files --others`, `if git diff --cached --quiet` — each REFRESHES THE INDEX and so
# EXECUTES an untrusted project's in-repo `.git/config core.fsmonitor` HOOK-PROGRAM. `--attr-source`
# does NOT reach that fsmonitor vector. When launched via `ai-auto` the launcher sources git-scrub so
# the env pin is inherited, but a STANDALONE run had NO pin (the only standalone entrypoint sourcing
# git-harden but NOT git-scrub). Source the canonical scrub HERE — exactly as automation-doctor.sh /
# review-gate.sh do — so the process-wide GIT_CONFIG `core.fsmonitor=''` env pin covers EVERY bare
# git call in this process. Presence-guarded (ai-auto BLAST-H1 idiom) so a partial scripts/-only copy
# (no hooks/) cannot abort under set -e.
# shellcheck source=../hooks/git-scrub.sh
if [ -f "${CRC_DIR}/../hooks/git-scrub.sh" ] && bash -n "${CRC_DIR}/../hooks/git-scrub.sh" 2>/dev/null; then
  . "${CRC_DIR}/../hooks/git-scrub.sh"
fi

OUT_DIR="${OUT_DIR:-.omx/review-context}"
INCLUDE_UNTRACKED_CONTENT="${INCLUDE_UNTRACKED_CONTENT:-0}"
MAX_UNTRACKED_BYTES="${MAX_UNTRACKED_BYTES:-102400}"
# A hostile project can present thousands of untracked files; each one spawns a
# `git diff --no-index` (the per-file byte cap only skips content, still pays the spawn).
# Cap the file COUNT and emit a truncation marker, mirroring the 200-entry nested cap.
MAX_UNTRACKED_FILES="${MAX_UNTRACKED_FILES:-200}"
# Optional comma/newline-separated path allowlist (exact paths, directory
# prefixes, or globs). When set, only matching untracked artifacts count as
# blocking review material; others are reported but treated as out of the
# declared review scope. When unset and tracked files changed, the allowlist is
# derived from the changed file scope. Untracked-only states keep every material
# file in scope.
REVIEW_UNTRACKED_ALLOWLIST="${REVIEW_UNTRACKED_ALLOWLIST:-}"
REVIEW_CONTEXT_DETAIL="${REVIEW_CONTEXT_DETAIL:-auto}"
REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES="${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES:-50000}"
REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES="${REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES:-80}"
REVIEW_TARGETED_RECHECK_FILES="${REVIEW_TARGETED_RECHECK_FILES:-}"
REPO_STATUS_BEFORE_CONTEXT="${REPO_STATUS_BEFORE_CONTEXT-$(review_git status --porcelain 2>/dev/null || true)}"
# OPCOST-MED-3: one gate operates on ONE unchanging tree, yet the changed-file (name-only)
# set was recomputed via a fresh review_git+git spawn pair at ~5 downstream call sites.
# Compute each variant ONCE here — through the SAME review_git hardening and identical
# spawn order, so the bytes/ordering are unchanged — and have every call site reuse it.
# Overridable (mirrors REPO_STATUS_BEFORE_CONTEXT) so unit tests can inject a set. (The
# `status --porcelain` recomputes at write_tree_churn_audit and the micro-work audit are
# DELIBERATELY left: the former compares before-vs-after to detect churn DURING collection,
# the latter needs core.quotepath=false — both are distinct from this name-only set.)
filter_targeted_recheck_files() {
  local files="${1-}"
  if [ "$#" -eq 0 ]; then
    files="$(cat)"
  fi
  if [ -z "$(printf '%s' "${REVIEW_TARGETED_RECHECK_FILES}" | tr -d '[:space:]')" ]; then
    printf '%s\n' "${files}"
    return 0
  fi
  awk 'NR == FNR { if ($0 != "") keep[$0] = 1; next } $0 in keep' \
    <(printf '%s\n' "${REVIEW_TARGETED_RECHECK_FILES}") \
    <(printf '%s\n' "${files}")
}

targeted_recheck_file_selected() {
  local file="$1"
  [ -n "$(printf '%s' "${REVIEW_TARGETED_RECHECK_FILES}" | tr -d '[:space:]')" ] || return 0
  printf '%s\n' "${REVIEW_TARGETED_RECHECK_FILES}" | grep -Fx -- "${file}" >/dev/null
}

CHANGED_FILES_TRACKED_STAGED_RAW="${CHANGED_FILES_TRACKED_STAGED-$(
  {
    review_git diff --name-only 2>/dev/null || true
    git diff --cached --name-only 2>/dev/null || true
  } | sort -u
)}"
CHANGED_FILES_WITH_UNTRACKED_RAW="${CHANGED_FILES_WITH_UNTRACKED-$(
  {
    review_git diff --name-only 2>/dev/null || true
    git diff --cached --name-only 2>/dev/null || true
    git ls-files --others --exclude-standard 2>/dev/null || true
  } | sort -u
)}"
CHANGED_FILES_TRACKED_STAGED="$(filter_targeted_recheck_files "${CHANGED_FILES_TRACKED_STAGED_RAW}")"
CHANGED_FILES_WITH_UNTRACKED="$(filter_targeted_recheck_files "${CHANGED_FILES_WITH_UNTRACKED_RAW}")"
OUT_FILE="${OUT_DIR}/latest-review-context.md"

mkdir -p "${OUT_DIR}"

# R6 (R5-1 completion): the gate runs THIS collector unconditionally BEFORE any skip check
# (review-gate.sh), so every patch-producing git call here must be inert to a project-local
# `.gitattributes` + `.git/config` external-diff/textconv/clean driver (an in-repo RCE that env
# scrubbing cannot reach). review_git is single-sourced in scripts/git-harden.sh; callers add
# --no-ext-diff/--no-textconv. The name-only/--stat/--quiet/--exit-code WORKTREE calls DO run the
# in-repo `.gitattributes` clean filter (R9b finding) and are now ALSO routed through review_git,
# whose central `--attr-source=<empty-tree>` disarms it; only the `--cached` (tree-vs-index) calls,
# which read no worktree blob, stay as plain git. (review_git is sourced at the TOP of this
# script — see the header — so it is defined before the module-load `git status` on line 24.)

has_worktree_diff() {
  has_unstaged_diff || has_staged_diff
}

has_unstaged_diff() {
  local status
  if review_git diff --quiet --exit-code >/dev/null 2>&1; then
    return 1
  else
    status="$?"
  fi

  case "$status" in
    1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

has_staged_diff() {
  local status
  if git diff --cached --quiet --exit-code >/dev/null 2>&1; then
    return 1
  else
    status="$?"
  fi

  case "$status" in
    1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

has_head_commit() {
  git rev-parse --verify HEAD >/dev/null 2>&1
}

is_status_clean() {
  [ -z "${REPO_STATUS_BEFORE_CONTEXT}" ]
}

post_commit_scope_files() {
  has_head_commit && is_status_clean || return 0
  post_commit_name_status | name_status_paths | sed '/^[[:space:]]*$/d' | sort -u
}

post_commit_parent_count() {
  git rev-list --parents -n 1 HEAD 2>/dev/null | awk '{ print NF - 1 }'
}

# RED3-1 fix: the tip-commit diff alone misses an earlier commit already made but not yet
# pushed (e.g. an unreviewed commit A followed by a reviewed trivial commit B -- B's tip
# diff never shows A's content, so reviewers never see A at all). Resolve the current
# branch's upstream tracking ref and union it in, mirroring the validation harness's own
# `@{u}...HEAD` fix for the identical "commits since upstream" scope gap
# (templates/domain-packs/odoo/validation-harness/validate-warm.sh / validate-full.sh).
# Empty when no upstream is configured (e.g. a fresh local-only branch) -- callers then fall
# back to the tip-commit-only behavior, which is already everything there is to review.
post_commit_upstream_ref() {
  review_git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true
}

post_commit_name_status() {
  has_head_commit && is_status_clean || return 0
  if [ "$(post_commit_parent_count)" -gt 1 ]; then
    review_git diff --name-status -M HEAD^1 HEAD 2>/dev/null
  else
    review_git show --format= --name-status -M HEAD 2>/dev/null
  fi
  local up
  up="$(post_commit_upstream_ref)"
  if [ -n "${up}" ]; then
    review_git diff --name-status -M "${up}...HEAD" 2>/dev/null
  fi
}

name_status_paths() {
  awk -F '\t' '
    /^[[:space:]]*$/ { next }
    $1 ~ /^[RC]/ && NF >= 3 { print $2; print $3; next }
    NF >= 2 { print $2 }
  '
}

is_positive_integer() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]+$'
}

tracked_diff_bytes() {
  local -a paths=()
  if [ -n "$(printf '%s' "${REVIEW_TARGETED_RECHECK_FILES}" | tr -d '[:space:]')" ]; then
    mapfile -t paths < <(printf '%s\n' "${REVIEW_TARGETED_RECHECK_FILES}" | sed '/^[[:space:]]*$/d')
    {
      review_git diff --no-ext-diff --no-textconv -- "${paths[@]}" 2>/dev/null || true
      review_git diff --cached --no-ext-diff --no-textconv -- "${paths[@]}" 2>/dev/null || true
    } | wc -c | tr -d ' '
    return 0
  fi
  {
    review_git diff --no-ext-diff --no-textconv 2>/dev/null || true
    review_git diff --cached --no-ext-diff --no-textconv 2>/dev/null || true
  } | wc -c | tr -d ' '
}

use_lightweight_context() {
  case "${REVIEW_CONTEXT_DETAIL}" in
    light)
      return 0
      ;;
    full)
      return 1
      ;;
    auto)
      ;;
    *)
      echo "Unknown REVIEW_CONTEXT_DETAIL=${REVIEW_CONTEXT_DETAIL}; expected auto, light, or full" >&2
      exit 2
      ;;
  esac

  has_worktree_diff || return 1
  is_positive_integer "${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES}" || return 1

  local diff_bytes
  diff_bytes="$(tracked_diff_bytes)"
  is_positive_integer "${diff_bytes}" || return 1
  [ "${diff_bytes}" -gt 0 ] || return 1
  [ "${diff_bytes}" -le "${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES}" ]
}

write_diff_stat() {
  local -a paths=()
  if has_worktree_diff; then
    if [ -n "$(printf '%s' "${REVIEW_TARGETED_RECHECK_FILES}" | tr -d '[:space:]')" ]; then
      mapfile -t paths < <(printf '%s\n' "${REVIEW_TARGETED_RECHECK_FILES}" | sed '/^[[:space:]]*$/d')
    fi
    if has_unstaged_diff; then
      echo "### Unstaged Diff Stat"
      echo
      echo '```text'
      if [ "${#paths[@]}" -gt 0 ]; then
        review_git diff --stat -- "${paths[@]}"
      else
        review_git diff --stat
      fi
      echo '```'
      echo
    fi
    if has_staged_diff; then
      echo "### Staged Diff Stat"
      echo
      echo '```text'
      if [ "${#paths[@]}" -gt 0 ]; then
        git diff --cached --stat -- "${paths[@]}"
      else
        git diff --cached --stat
      fi
      echo '```'
      echo
    fi
    return 0
  fi

  if has_head_commit && is_status_clean; then
    echo "No working tree diff detected; showing latest commit diff for post-commit review context."
    echo
    echo '```text'
    review_git show --stat --oneline --decorate --find-renames HEAD
    echo '```'
    echo
    # RED3-1: also surface anything already committed but not yet pushed, ahead of the
    # tip commit above (see post_commit_upstream_ref).
    local up
    up="$(post_commit_upstream_ref)"
    if [ -n "${up}" ]; then
      echo "### Unpushed Range Diff Stat (${up}...HEAD)"
      echo
      echo '```text'
      review_git diff --stat "${up}...HEAD"
      echo '```'
      echo
    fi
    return 0
  fi

  echo "No staged or unstaged tracked diff detected. Untracked files, if any, are shown in the Untracked Files section."
}

write_diff() {
  local -a paths=()
  if has_worktree_diff; then
    if [ -n "$(printf '%s' "${REVIEW_TARGETED_RECHECK_FILES}" | tr -d '[:space:]')" ]; then
      mapfile -t paths < <(printf '%s\n' "${REVIEW_TARGETED_RECHECK_FILES}" | sed '/^[[:space:]]*$/d')
    fi
    if has_unstaged_diff; then
      echo "### Unstaged Diff"
      echo
      echo '```diff'
      if [ "${#paths[@]}" -gt 0 ]; then
        review_git diff --no-ext-diff --no-textconv -- "${paths[@]}"
      else
        review_git diff --no-ext-diff --no-textconv
      fi
      echo '```'
      echo
    fi
    if has_staged_diff; then
      echo "### Staged Diff"
      echo
      echo '```diff'
      if [ "${#paths[@]}" -gt 0 ]; then
        review_git diff --cached --no-ext-diff --no-textconv -- "${paths[@]}"
      else
        review_git diff --cached --no-ext-diff --no-textconv
      fi
      echo '```'
      echo
    fi
    return 0
  fi

  if has_head_commit && is_status_clean; then
    echo "No working tree diff detected; showing latest commit diff for post-commit review context."
    echo
    echo '```diff'
    review_git show --no-ext-diff --no-textconv --format= --find-renames HEAD
    echo '```'
    echo
    # RED3-1: the tip commit alone is invisible to an earlier commit already made but not
    # yet pushed (e.g. an unreviewed commit followed by a reviewed trivial fixup commit).
    # Surface the full unpushed range too, so THIS is genuinely the reviewer-facing diff of
    # everything about to be pushed, not just the last commit.
    local up
    up="$(post_commit_upstream_ref)"
    if [ -n "${up}" ]; then
      echo "### Unpushed Range Diff (${up}...HEAD)"
      echo
      echo '```diff'
      review_git diff --no-ext-diff --no-textconv "${up}...HEAD"
      echo '```'
      echo
    fi
    return 0
  fi

  echo "No staged or unstaged tracked diff detected. Untracked files, if any, are shown in the Untracked Files section."
}

# Fence-break belt for INLINED file/verify BODIES (R26, HIGH): a body line that is a
# bare ``` (optionally ```lang, or >=3 backticks) would CLOSE the surrounding
# ```markdown/```text fence early, hoisting following attacker lines to column-0
# instruction position — an indirect prompt injection of the LLM reviewer. Indent any
# leading-backtick-fence line 4 spaces so it can never open/close a fence (mirrors the
# R24 untracked-listing `sed 's/^/    /'` belt) while the body stays fully readable.
neutralize_fence_breaks() {
  sed 's/^\( *\)```/\1    ```/'
}

write_markdown_file() {
  local file="$1"
  echo "### $file"
  echo
  echo '```markdown'
  sed -n '1,200p' "$file" | neutralize_fence_breaks
  echo '```'
  echo
}

collect_review_reference_files() {
  local file
  # D6/C1: feed the GLOBAL base AGENTS.md (engine operating rules) alongside the
  # project overlay so reviewers see full guidance in global mode. C7 dedup
  # (F9): in the source repo the project AGENTS.md IS the global base (same
  # inode) -> emit it once. A missing project AGENTS.md degrades to base-only.
  local ah base_agents
  ah="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
  base_agents="${ah}/AGENTS.md"
  if [ -f "$base_agents" ] && { [ ! -e AGENTS.md ] || ! [ "$base_agents" -ef AGENTS.md ]; }; then
    printf '%s\n' "$base_agents"
  fi
  for file in AGENTS.md docs/WORKFLOW.md docs/AI_ROLES.md; do
    if [ -f "$file" ]; then
      printf '%s\n' "$file"
    fi
  done

  if [ -d docs/runbooks ]; then
    find docs/runbooks -maxdepth 1 -type f -name '*.md' \
      ! -name '*.generated.md' \
      ! -name '*-generated.md' \
      ! -name '*.runtime.md' \
      ! -name '*-runtime.md' \
      | sort | tail -8
  fi
}

classify_review_scope_for_path() {
  local file="$1"
  case "${file}" in
    templates/*)
      echo "templates"
      ;;
    AGENTS.md|*/AGENTS.md)
      echo "guidance"
      ;;
    docs/*)
      echo "docs"
      ;;
    plans/*|.omx/plans/*)
      echo "plans"
      ;;
    scripts/*)
      echo "scripts"
      ;;
    tools/*|bin/*)
      echo "tools"
      ;;
    tests/*)
      echo "tests"
      ;;
    Dockerfile|docker-compose.yml|docker/*)
      echo "docker"
      ;;
    .github/workflows/*)
      echo "github_actions"
      ;;
    *.py|*.js|*.ts|*.tsx|*.jsx|*.html|*.css)
      echo "app"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

review_intensity_for_scopes() {
  local scopes="$1"
  case "${scopes}" in
    *guidance*|*scripts*|*templates*|*docker*|*github_actions*)
      echo "strict"
      ;;
    docs|plans|*"docs"*","*"plans"*|*"plans"*","*"docs"*)
      echo "lightweight"
      ;;
    *)
      echo "standard"
      ;;
  esac
}

required_checks_for_scopes() {
  local scopes="$1"
  local checks=("ai-auto verify")

  case "${scopes}" in
    *scripts*|*tools*|*tests*)
      checks+=("targeted script/test fixtures")
      ;;
  esac
  case "${scopes}" in
    *templates*)
      checks+=("template version and patch notes")
      ;;
  esac
  case "${scopes}" in
    *guidance*)
      checks+=("guidance budget check")
      ;;
  esac
  case "${scopes}" in
    *docker*|*app*)
      checks+=("docker smoke")
      ;;
  esac

  local joined="${checks[0]}"
  local check
  for check in "${checks[@]:1}"; do
    joined="${joined}, ${check}"
  done
  echo "${joined}"
}

persona_lens_for_path() {
  case "$1" in
    AGENTS.md|*/AGENTS.md|docs/WORKFLOW.md|docs/AUTOMATION_OPERATING_POLICY.md)
      echo "policy_compliance guidance_bloat"
      ;;
    scripts/verify.sh|scripts/review-gate.sh|scripts/run-ai-reviews.sh|scripts/collect-review-context.sh|scripts/summarize-ai-reviews.sh)
      echo "policy_compliance test_strategy review_taxonomy"
      ;;
    templates/*)
      echo "policy_compliance guidance_bloat review_taxonomy"
      ;;
    *auth*|*token*|*cookie*|*secret*|*credential*)
      echo "security"
      ;;
    *schema*|*migration*|*serialization*|*backfill*|*import*|*export*)
      echo "data_migration"
      ;;
    *deploy*|*release*|*rollback*|*monitoring*|*production*)
      echo "release"
      ;;
    scripts/*|tools/*|tests/*)
      echo "test_strategy review_taxonomy"
      ;;
    docs/*|plans/*)
      echo "docs_dx"
      ;;
    *.tsx|*.jsx|*.html|*.css)
      echo "design browser_qa"
      ;;
    *)
      echo ""
      ;;
  esac
}

persona_gate_policy_for_lenses() {
  local lenses="$1"
  case "${lenses}" in
    *policy_compliance*|*security*|*data_migration*|*release*)
      echo "strict_gate"
      ;;
    *test_strategy*|*review_taxonomy*|*design*|*browser_qa*)
      echo "review_gate"
      ;;
    docs_dx)
      echo "verify_only"
      ;;
    "")
      echo "verify_only"
      ;;
    *)
      echo "review_gate"
      ;;
  esac
}

write_diff_scope_summary() {
  local files scopes active_lenses lens_count gate_policy integrator_required
  files="${CHANGED_FILES_WITH_UNTRACKED}"  # OPCOST-MED-3: computed once at module load
  if [ -z "${files}" ]; then
    files="$(post_commit_scope_files)"
  fi

  if [ -z "${files}" ]; then
    echo "No changed files detected."
    return 0
  fi

  scopes="$(printf '%s\n' "${files}" | while IFS= read -r file; do
    [ -n "${file}" ] || continue
    classify_review_scope_for_path "${file}"
  done | sort -u | paste -sd ',' -)"

  active_lenses="$(
    printf '%s\n' "${files}" | while IFS= read -r file; do
      [ -n "${file}" ] || continue
      persona_lens_for_path "${file}" | tr ' ' '\n'
    done | sed '/^[[:space:]]*$/d' | sort -u | paste -sd ',' -
  )"
  lens_count=0
  if [ -n "${active_lenses}" ]; then
    lens_count="$(printf '%s\n' "${active_lenses}" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  fi
  integrator_required=false
  if [ "${lens_count}" -gt 1 ]; then
    integrator_required=true
    case ",${active_lenses}," in
      *,integrator,*) ;;
      *) active_lenses="${active_lenses}${active_lenses:+,}integrator" ;;
    esac
  fi
  gate_policy="$(persona_gate_policy_for_lenses "${active_lenses}")"

  echo "- scopes: ${scopes}"
  echo "- review intensity hint: $(review_intensity_for_scopes "${scopes}")"
  echo "- active lenses: ${active_lenses:-none}"
  echo "- integrator required: ${integrator_required}"
  echo "- review gate policy: ${gate_policy}"
  echo "- review gate reasons: scopes=${scopes}; lenses=${active_lenses:-none}"
  echo "- required checks: $(required_checks_for_scopes "${scopes}")"
  if command -v base64 >/dev/null 2>&1; then
    printf '%s' "- changed paths b64: "
    printf '%s\n' "${files}" | base64 | tr -d '\n'
    echo
  fi
  echo
  echo "| File | Scope |"
  echo "| --- | --- |"
  printf '%s\n' "${files}" | while IFS= read -r file; do
    [ -n "${file}" ] || continue
    # F4 (R26): a filename may carry `|`; escape the cell delimiter so a hostile path
    # cannot forge extra table columns or break out of the table cell.
    local safe_file
    safe_file="$(printf '%s' "${file}" | sed 's/|/\\|/g')"
    echo "| ${safe_file} | $(classify_review_scope_for_path "${file}") |"
  done
}

write_tree_churn_audit() {
  local current_status before_untracked current_untracked new_untracked
  current_status="$(review_git status --porcelain 2>/dev/null || true)"

  echo "audit_status: report_only"
  if [ "${current_status}" = "${REPO_STATUS_BEFORE_CONTEXT}" ]; then
    echo "tree_churn_status: stable"
    echo "No working tree status changes were detected while collecting review context."
    return 0
  fi

  echo "tree_churn_status: changed"
  echo "Working tree status changed while collecting review context. Reviewers should treat this as a concurrency warning, not an automatic blocker."

  before_untracked="$(printf '%s\n' "${REPO_STATUS_BEFORE_CONTEXT}" | sed -n 's/^?? //p' | sort -u)"
  current_untracked="$(printf '%s\n' "${current_status}" | sed -n 's/^?? //p' | sort -u)"
  new_untracked="$(comm -13 <(printf '%s\n' "${before_untracked}") <(printf '%s\n' "${current_untracked}") | sed '/^[[:space:]]*$/d')"

  if [ -n "${new_untracked}" ]; then
    echo "new_untracked_during_context:"
    printf '%s\n' "${new_untracked}" | sed 's/^/- /'
  else
    echo "new_untracked_during_context: none"
  fi
}

tracked_review_scope_allowlist() {
  local file
  # OPCOST-MED-3: reuse the module-load tracked+staged name-only set (identical bytes).
  printf '%s\n' "${CHANGED_FILES_TRACKED_STAGED}" | while IFS= read -r file; do
    [ -n "${file}" ] || continue
    case "${file}" in
      templates/*)
        echo "templates/"
        ;;
      AGENTS.md|*/AGENTS.md)
        echo "AGENTS.md"
        ;;
      docs/*)
        echo "docs/"
        ;;
      plans/*|.omx/plans/*)
        echo "plans/"
        ;;
      scripts/*)
        echo "scripts/"
        ;;
      tools/*)
        echo "tools/"
        ;;
      bin/*)
        echo "bin/"
        ;;
      tests/*)
        echo "tests/"
        ;;
    esac
  done | sort -u
}

untracked_path_allowed() {
  local needle="$1"
  local allowlist="$2"
  local item
  while IFS= read -r item; do
    [ -n "${item}" ] || continue
    item="${item%/}"
    # Allowlist entries are intentionally treated as glob/prefix patterns: an
    # exact path or glob matches directly, and a directory entry covers its
    # whole subtree.
    # shellcheck disable=SC2254
    case "${needle}" in
      ${item}|${item}/*) return 0 ;;
    esac
  done <<EOF
${allowlist}
EOF
  return 1
}

default_untracked_doc_plan_allowed() {
  local path="$1"
  case "${path}" in
    docs/*.md|docs/*.mdx|docs/*.txt|plans/*.md|plans/*.mdx|plans/*.txt)
      return 0
      ;;
  esac
  return 1
}

write_untracked_review_guard() {
  local material allowlist allowlist_source in_scope filtered file default_relaxed remaining
  material="$(
    git ls-files --others --exclude-standard 2>/dev/null |
      grep -E '^(plans|docs|scripts|tools|tests|templates)/|^AGENTS\.md$' || true
  )"

  if [ -z "${material}" ]; then
    echo "guard_status: clear"
    echo "No material untracked review artifacts detected."
    return 0
  fi

  default_relaxed=""
  remaining=""
  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    if default_untracked_doc_plan_allowed "${file}"; then
      default_relaxed="${default_relaxed}${default_relaxed:+
}${file}"
    else
      remaining="${remaining}${remaining:+
}${file}"
    fi
  done <<EOF
${material}
EOF
  material="${remaining}"

  # Scope blocking material to an explicit allowlist, or derive one from tracked
  # changed paths. Out-of-scope files are still reported for transparency.
  filtered="${default_relaxed}"
  allowlist="$(split_csv_lines "${REVIEW_UNTRACKED_ALLOWLIST}")"
  allowlist_source="explicit"
  if [ -z "${allowlist}" ]; then
    allowlist="$(tracked_review_scope_allowlist)"
    allowlist_source="auto_changed_scope"
  fi
  if [ -n "${allowlist}" ]; then
    in_scope=""
    while IFS= read -r file; do
      [ -n "${file}" ] || continue
      if untracked_path_allowed "${file}" "${allowlist}"; then
        in_scope="${in_scope}${in_scope:+
}${file}"
      else
        filtered="${filtered}${filtered:+
}${file}"
      fi
    done <<EOF
${material}
EOF
    material="${in_scope}"
  fi

  if [ -z "${material}" ]; then
    echo "guard_status: clear"
    if [ -n "${filtered}" ]; then
      if [ -n "${default_relaxed}" ]; then
        echo "default_docs_plans_allowlist: document_files_only"
      fi
      echo "scope_allowlist_source: ${allowlist_source}"
      echo "scope_allowlist: $(printf '%s\n' "${allowlist}" | paste -sd ',' -)"
      echo "No in-scope untracked review artifacts. The following untracked files are outside the declared review scope and were not treated as blocking material:"
      echo
      echo '```text'
      printf '%s\n' "${filtered}"
      echo '```'
    else
      echo "No material untracked review artifacts detected."
    fi
    return 0
  fi

  echo "guard_status: material_untracked_artifacts_present"
  echo "manual_review_required: true"
  echo "manual_review_override: ${REVIEW_UNTRACKED_MANUAL_REVIEWED:-0}"
  if [ -n "${default_relaxed}" ]; then
    echo "default_docs_plans_allowlist: document_files_only"
  fi
  if [ -n "${allowlist}" ]; then
    echo "scope_allowlist_source: ${allowlist_source}"
    echo "scope_allowlist: $(printf '%s\n' "${allowlist}" | paste -sd ',' -)"
  fi
  if [ "${INCLUDE_UNTRACKED_CONTENT}" = "1" ]; then
    echo "content_included: true"
    echo "Material untracked review artifacts are present and content inclusion is enabled."
  else
    echo "content_included: false"
    echo "Material untracked review artifacts are present, but content inclusion is disabled."
    echo "Set INCLUDE_UNTRACKED_CONTENT=1 or require manual review before commit readiness."
  fi
  echo
  echo '```text'
  printf '%s\n' "${material}"
  echo '```'
  if [ -n "${filtered}" ]; then
    echo
    echo "Untracked files outside the declared review scope (reported, not blocking):"
    echo
    echo '```text'
    printf '%s\n' "${filtered}"
    echo '```'
  fi
}

split_csv_lines() {
  local value="$1"
  printf '%s\n' "${value}" | tr ',' '\n' | sed '/^[[:space:]]*$/d; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

path_in_list() {
  local needle="$1"
  local haystack="$2"
  local item
  while IFS= read -r item; do
    [ -n "${item}" ] || continue
    if [ "${item}" = "${needle}" ]; then
      return 0
    fi
  done <<EOF
${haystack}
EOF
  return 1
}

deferred_record_has_reason() {
  local needle="$1"
  local records="$2"
  local item path reason

  while IFS= read -r item; do
    [ -n "${item}" ] || continue
    path="${item%%|*}"
    reason="${item#*|}"
    if [ "${path}" = "${needle}" ] && [ "${reason}" != "${item}" ] && [ -n "${reason}" ]; then
      return 0
    fi
  done <<EOF
${records}
EOF
  return 1
}

write_phase_scope_guard() {
  local phase="${PHASE_SCOPE_PHASE:-}"
  local allowed deferred deferred_records changed unresolved missing_deferral file

  if [ -z "${phase}" ]; then
    echo "phase_scope_status: inactive"
    echo "No phase/scope guard requested. Set PHASE_SCOPE_PHASE and PHASE_SCOPE_ALLOWED_FILES to enable."
    return 0
  fi

  allowed="$(split_csv_lines "${PHASE_SCOPE_ALLOWED_FILES:-}")"
  deferred="$(split_csv_lines "${PHASE_SCOPE_DEFERRED_FILES:-}")"
  deferred_records="$(split_csv_lines "${PHASE_SCOPE_DEFERRED_RECORDS:-}")"
  changed="${CHANGED_FILES_WITH_UNTRACKED}"  # OPCOST-MED-3: computed once at module load

  unresolved=""
  missing_deferral=""
  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    case "${file}" in
      .omx/review-context/*)
        continue
        ;;
    esac
    if path_in_list "${file}" "${allowed}"; then
      continue
    fi
    if path_in_list "${file}" "${deferred}"; then
      if deferred_record_has_reason "${file}" "${deferred_records}"; then
        continue
      fi
      missing_deferral="${missing_deferral}${missing_deferral:+
}${file}"
      continue
    fi
    unresolved="${unresolved}${unresolved:+
}${file}"
  done <<EOF
${changed}
EOF

  echo "phase: ${phase}"
  echo "manual_review_override: ${PHASE_SCOPE_MANUAL_REVIEWED:-0}"
  if [ -n "${missing_deferral}" ]; then
    echo "phase_scope_status: missing_deferral_record"
    echo "manual_review_required: true"
    echo "Deferred out-of-phase files require PHASE_SCOPE_DEFERRED_RECORDS entries in path|reason format."
    echo
    echo '```text'
    printf '%s\n' "${missing_deferral}"
    echo '```'
  elif [ -n "${unresolved}" ]; then
    echo "phase_scope_status: out_of_phase_edit"
    echo "manual_review_required: true"
    echo "Out-of-phase changed files require a plan update, deferral record, or manual review."
    echo
    echo '```text'
    printf '%s\n' "${unresolved}"
    echo '```'
  else
    echo "phase_scope_status: clear"
    echo "Changed files are inside the allowed or deferred phase scope."
  fi
}

completion_pack_trigger_for_shape() {
  case "$1" in
    security_review) echo "security_completion" ;;
    deployment_files) echo "deployment_completion" ;;
    persisted_data) echo "data_completion" ;;
    ui_work) echo "ui_completion" ;;
    performance_change) echo "performance_completion" ;;
    observability_change) echo "observability_completion" ;;
    docs_generation_lens) echo "reference_lens:not_completion_pack" ;;
    *) echo "" ;;
  esac
}

completion_pack_trigger_for_path() {
  case "$1" in
    docs/SECURITY_COMPLETION.md|*security*|*auth*|*secret*) echo "security_completion" ;;
    docs/DEPLOYMENT_COMPLETION.md|*deploy*|*release*) echo "deployment_completion" ;;
    docs/DATA_COMPLETION.md|*migration*|*schema*|*database*|*persist*) echo "data_completion" ;;
    docs/UI_COMPLETION.md|*frontend*|*ui*|*.tsx|*.jsx|*.css) echo "ui_completion" ;;
    docs/PERFORMANCE_COMPLETION.md|*benchmark*|*performance*|*perf*) echo "performance_completion" ;;
    docs/OBSERVABILITY_COMPLETION.md|*observability*|*monitor*|*logging*) echo "observability_completion" ;;
    *) echo "" ;;
  esac
}

write_completion_pack_routing_audit() {
  local pack missing shape trigger changed file inferred seen
  local packs="DATA DEPLOYMENT OBSERVABILITY PERFORMANCE SECURITY UI"

  missing=""
  for pack in ${packs}; do
    if [ ! -f "docs/${pack}_COMPLETION.md" ]; then
      missing="${missing}${missing:+,}${pack}"
    fi
  done

  echo "audit_status: report_only"
  if [ -n "${missing}" ]; then
    echo "packs_present: missing:${missing}"
  else
    echo "packs_present: data,deployment,observability,performance,security,ui"
  fi

  shape="${COMPLETION_PACK_INPUT_SHAPE:-}"
  trigger="$(completion_pack_trigger_for_shape "${shape}")"
  if [ -n "${shape}" ]; then
    echo "input_shape: ${shape}"
    echo "explicit_trigger: ${trigger:-none}"
  else
    echo "input_shape: none"
    echo "explicit_trigger: none"
  fi

  changed="${CHANGED_FILES_WITH_UNTRACKED}"  # OPCOST-MED-3: computed once at module load

  inferred=""
  seen=""
  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    case "${file}" in
      .omx/review-context/*)
        continue
        ;;
    esac
    trigger="$(completion_pack_trigger_for_path "${file}")"
    [ -n "${trigger}" ] || continue
    case ",${seen}," in
      *",${trigger},"*) continue ;;
    esac
    seen="${seen}${seen:+,}${trigger}"
    inferred="${inferred}${inferred:+
}- ${trigger}: ${file}"
  done <<EOF
${changed}
EOF

  if [ -n "${inferred}" ]; then
    echo "file_scope_triggers:"
    printf '%s\n' "${inferred}"
  else
    echo "file_scope_triggers: none"
  fi
  echo "runtime_lane_added: false"
}

product_challenge_required_shape() {
  local request_shape="$1"
  local task_size="$2"

  case "${request_shape}" in
    broad_strategy|product_strategy|large_ui_workflow|unclear_value)
      return 0
      ;;
  esac
  [ "${task_size}" = "medium" ] || [ "${task_size}" = "large" ]
}

write_product_challenge_audit() {
  local request_shape="${PRODUCT_CHALLENGE_REQUEST_SHAPE:-unspecified}"
  local task_size="${PRODUCT_CHALLENGE_TASK_SIZE:-unspecified}"
  local approved_plan="${PRODUCT_CHALLENGE_APPROVED_PLAN_EXISTS:-0}"
  local reason="${PRODUCT_CHALLENGE_REASON:-}"
  local questions="${PRODUCT_CHALLENGE_QUESTIONS:-}"
  local question_count=0

  echo "audit_status: report_only"
  echo "request_shape: ${request_shape}"
  echo "task_size: ${task_size}"
  echo "approved_plan_exists: ${approved_plan}"

  if [ "${approved_plan}" = "1" ]; then
    echo "challenge_status: skipped_approved_plan"
    return 0
  fi

  if [ "${task_size}" = "small" ] && { [ "${request_shape}" = "typo" ] || [ "${request_shape}" = "narrow_bugfix" ] || [ "${request_shape}" = "routine_doc" ]; }; then
    echo "challenge_status: skipped_routine_small"
    return 0
  fi

  if product_challenge_required_shape "${request_shape}" "${task_size}"; then
    if [ -z "${reason}" ]; then
      echo "challenge_status: missing_product_challenge_reason"
      echo "manual_review_required: true"
      return 0
    fi

    if [ -n "${questions}" ]; then
      question_count="$(printf '%s\n' "${questions}" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
    fi
    if [ "${question_count}" -gt 3 ]; then
      echo "challenge_status: too_many_product_challenge_questions"
      echo "manual_review_required: true"
      return 0
    fi

    echo "challenge_status: required"
    echo "challenge_reason: ${reason}"
    echo "question_count: ${question_count}"
    return 0
  fi

  echo "challenge_status: not_required"
}

write_visual_artifact_audit() {
  local changed file spec visual_export reviewed_specs status_line any_status

  reviewed_specs="$(split_csv_lines "${VISUAL_HUMAN_REVIEWED_SPECS:-}")"
  changed="${CHANGED_FILES_WITH_UNTRACKED}"  # OPCOST-MED-3: computed once at module load

  echo "audit_status: report_only"
  echo "runtime_tool_install_required: false"
  any_status=0

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    case "${file}" in
      .omx/review-context/*)
        continue
        ;;
      *.excalidraw)
        spec="${file%.excalidraw}-spec.md"
        visual_export="${file%.excalidraw}.svg"
        if [ ! -f "${spec}" ]; then
          status_line="visual_warning:explanatory_only ${file}"
        elif ! path_in_list "${spec}" "${reviewed_specs}"; then
          status_line="visual_warning:unreviewed_spec ${file} -> ${spec}"
        else
          status_line="visual_ok:implementation_facing_spec ${file} -> ${spec}"
        fi
        echo "${status_line}"
        any_status=1
        if [ -f "${visual_export}" ] && [ "${file}" -nt "${visual_export}" ]; then
          echo "visual_warning:stale_export ${visual_export}"
          any_status=1
        fi
        ;;
      *-spec.md)
        if ! path_in_list "${file}" "${reviewed_specs}"; then
          echo "visual_warning:unreviewed_spec ${file}"
          any_status=1
        fi
        ;;
    esac
  done <<EOF
${changed}
EOF

  if [ "${VISUAL_AMBIGUOUS_SOURCE:-0}" = "1" ]; then
    echo "visual_warning:ambiguous_source_of_truth"
    any_status=1
  fi

  if [ "${any_status}" -eq 0 ]; then
    echo "visual_status: none"
  fi
}

write_standard_flow_preservation_audit() {
  local hides="${STANDARD_FLOW_HIDES_STANDARD_FIELD:-0}"
  local relationship="${STANDARD_FLOW_CUSTOM_RELATIONSHIP:-syncs_with_standard}"

  echo "audit_status: report_only"
  echo "runtime_tool_install_required: false"
  echo "hides_or_replaces_standard_field: ${hides}"

  if [ "${hides}" != "1" ]; then
    echo "standard_flow_status: not_affected"
    return 0
  fi

  echo "custom_field_relationship: ${relationship}"
  case "${relationship}" in
    syncs_with_standard|extends_standard|parallel_replacement) ;;
    *)
      echo "standard_flow_status: invalid_custom_field_relationship"
      echo "manual_review_required: true"
      return 0
      ;;
  esac

  if [ "${STANDARD_FLOW_IMPACT_MAP_RECORDED:-0}" != "1" ]; then
    echo "standard_flow_status: impact_map_required"
    echo "manual_review_required: true"
    return 0
  fi
  if [ "${STANDARD_FLOW_REGRESSION_EVIDENCE:-0}" != "1" ]; then
    echo "standard_flow_status: regression_required"
    echo "manual_review_required: true"
    return 0
  fi
  if [ "${relationship}" = "parallel_replacement" ]; then
    echo "standard_flow_status: parallel_replacement_blocked"
    echo "manual_review_required: true"
    return 0
  fi
  echo "standard_flow_status: preserved"
}

write_spec_code_alignment_audit() {
  local patch_size="${SPEC_ALIGN_PATCH_SIZE:-small}"
  local applying="${SPEC_ALIGN_APPLYING_SCOPE_CHANGE:-0}"
  local rows="${SPEC_ALIGN_ROWS:-}"
  local triggered=0 row id status unresolved="" invalid="" mapped=0

  echo "audit_status: report_only"
  echo "runtime_tool_install_required: false"
  echo "patch_size: ${patch_size}"
  echo "applying_reviewer_scope_change: ${applying}"

  # Mirror the contract: an unknown patch size is rejected rather than silently
  # treated as not-required.
  case "${patch_size}" in
    small|medium|large) ;;
    *)
      echo "spec_code_alignment_status: invalid_patch_size"
      echo "manual_review_required: true"
      return 0
      ;;
  esac

  case "${patch_size}" in
    medium|large) triggered=1 ;;
  esac
  [ "${applying}" = "1" ] && triggered=1

  if [ "${triggered}" -eq 0 ]; then
    echo "spec_code_alignment_status: not_required"
    return 0
  fi

  # Rows are "id:status" pairs separated by commas. A malformed row (no colon,
  # empty id, or a status outside the contract's allowed set) is reported as
  # invalid rather than counted as a clear mapping.
  local IFS=','
  for row in ${rows}; do
    row="$(printf '%s' "${row}" | sed 's/^ *//; s/ *$//')"
    [ -n "${row}" ] || continue
    case "${row}" in
      *:*) ;;
      *) invalid="${invalid} ${row}"; continue ;;
    esac
    id="$(printf '%s' "${row%%:*}" | sed 's/ *$//')"
    status="$(printf '%s' "${row#*:}" | sed 's/^ *//')"
    if [ -z "${id}" ]; then
      invalid="${invalid} ${row}"
      continue
    fi
    case "${status}" in
      aligned|updated|not_applicable) mapped=1 ;;
      blocked|needs_user_confirmation) mapped=1; unresolved="${unresolved} ${id}" ;;
      *) invalid="${invalid} ${id}" ;;
    esac
  done
  unset IFS

  invalid="$(printf '%s' "${invalid}" | sed 's/^ *//')"
  if [ -n "${invalid}" ]; then
    echo "invalid_rows: ${invalid}"
    echo "spec_code_alignment_status: invalid_rows"
    echo "manual_review_required: true"
    return 0
  fi

  if [ "${mapped}" -eq 0 ]; then
    echo "spec_code_alignment_status: mapping_required"
    echo "manual_review_required: true"
    return 0
  fi

  unresolved="$(printf '%s' "${unresolved}" | sed 's/^ *//')"
  if [ -n "${unresolved}" ]; then
    echo "unresolved_rows: ${unresolved}"
    echo "spec_code_alignment_status: attention"
  else
    echo "spec_code_alignment_status: clear"
  fi
}

write_planning_visual_gate_audit() {
  local stage="${PLANNING_VISUAL_STAGE:-planning}"
  local complexity="${PLANNING_VISUAL_COMPLEXITY_SIGNALS:-}"
  local layout="${PLANNING_VISUAL_LAYOUT_SIGNALS:-}"
  local has_complexity=0 has_layout=0 proposed=""

  echo "audit_status: report_only"
  echo "runtime_tool_install_required: false"
  echo "stage: ${stage}"

  if [ "${PLANNING_VISUAL_OVERRIDES_SPEC:-0}" = "1" ]; then
    echo "planning_visual_status: spec_must_stay_authoritative"
    echo "manual_review_required: true"
    return 0
  fi

  [ -n "$(printf '%s' "${complexity}" | tr -d '[:space:],')" ] && has_complexity=1
  [ -n "$(printf '%s' "${layout}" | tr -d '[:space:],')" ] && has_layout=1

  if [ "${has_complexity}" -eq 0 ] && [ "${has_layout}" -eq 0 ]; then
    echo "planning_visual_status: not_required"
    return 0
  fi

  if [ "${has_complexity}" -eq 1 ]; then
    [ "${PLANNING_VISUAL_STRUCTURE_PRESENT:-0}" = "1" ] || proposed="${proposed} structure_model"
    [ "${PLANNING_VISUAL_FLOW_PRESENT:-0}" = "1" ] || proposed="${proposed} flow_visual"
    [ "${PLANNING_VISUAL_OPTIMIZER_DONE:-0}" = "1" ] || proposed="${proposed} optimizer_pass"
  fi
  if [ "${has_layout}" -eq 1 ] && [ "${PLANNING_VISUAL_WIREFRAME_PRESENT:-0}" != "1" ]; then
    proposed="${proposed} ui_wireframe"
  fi

  proposed="$(printf '%s' "${proposed}" | sed 's/^ *//')"
  if [ -z "${proposed}" ]; then
    echo "planning_visual_status: satisfied"
    return 0
  fi
  echo "proposed_artifacts: ${proposed}"
  if [ "${PLANNING_VISUAL_PROPOSAL_RECORDED:-0}" = "1" ]; then
    echo "planning_visual_status: proposed"
  else
    echo "planning_visual_status: proposal_required"
    echo "manual_review_required: true"
  fi
}

write_browser_qa_evidence_audit() {
  local target="${BROWSER_QA_TARGET:-}"
  local report_only="${BROWSER_QA_REPORT_ONLY:-1}"
  local attempts_patch="${BROWSER_QA_ATTEMPTS_PATCH:-0}"
  local cdp_access="${BROWSER_QA_CDP_ACCESS:-0}"
  local loopback="${BROWSER_QA_LOOPBACK_BOUND:-0}"
  local user_launched="${BROWSER_QA_USER_LAUNCHED_OR_ISOLATED:-0}"
  local approval="${BROWSER_QA_APPROVAL_RECORDED:-0}"
  local exports_credentials="${BROWSER_QA_EXPORTS_COOKIES_OR_TOKENS:-0}"
  local sensitive="${BROWSER_QA_SENSITIVE_EVIDENCE:-0}"
  local redacted="${BROWSER_QA_REDACTED:-0}"
  local visual="${BROWSER_QA_VISUAL_VERDICT:-0}"
  local verify="${BROWSER_QA_VERIFY_EVIDENCE:-0}"
  local review="${BROWSER_QA_REVIEW_GATE_EVIDENCE:-0}"
  local screenshot="${BROWSER_QA_SCREENSHOT_NOTE:-none}"
  local steps="${BROWSER_QA_STEPS:-none}"
  local detailed="${BROWSER_QA_DETAILED_BEHAVIOR_REQUEST:-0}"
  local micro_plan="${BROWSER_QA_MICRO_PLAN:-}"

  echo "audit_status: report_only"
  echo "target: ${target:-none}"
  echo "steps: ${steps}"
  echo "screenshot_note: ${screenshot}"
  if [ "${report_only}" != "1" ] || [ "${attempts_patch}" = "1" ]; then
    echo "qa_status: qa_block:auto_fix_not_allowed"
    return 0
  fi

  if [ "${cdp_access}" = "1" ]; then
    echo "cdp_access: requested"
    if [ "${loopback}" != "1" ] || [ "${user_launched}" != "1" ] || [ "${approval}" != "1" ] || [ "${exports_credentials}" = "1" ]; then
      echo "qa_status: qa_block:credential_boundary"
      return 0
    fi
  else
    echo "cdp_access: not_requested"
  fi

  if [ "${sensitive}" = "1" ] && [ "${redacted}" != "1" ]; then
    echo "qa_status: qa_warning:redaction_required"
    return 0
  fi

  if [ "${visual}" = "1" ] && { [ "${verify}" != "1" ] || [ "${review}" != "1" ]; }; then
    echo "qa_status: qa_warning:visual_not_completion_authority"
    return 0
  fi

  if [ "${detailed}" = "1" ] || [ "${cdp_access}" = "1" ]; then
    echo "micro_plan_required: true"
    local required_rows="layout click_targets input_handling alerts_errors sync_update business_mapping"
    local missing_rows=""
    local row
    for row in ${required_rows}; do
      case ",${micro_plan}," in
        *",${row}:evidence,"*|*",${row}:not_applicable,"*) ;;
        *) missing_rows="${missing_rows} ${row}" ;;
      esac
    done
    if [ -n "${missing_rows}" ]; then
      echo "micro_plan_status: missing_rows"
      echo "missing_micro_plan_rows:${missing_rows}"
      echo "qa_status: qa_attention:micro_plan_required"
      return 0
    fi
    echo "micro_plan_status: complete"
  else
    echo "micro_plan_required: false"
  fi

  if [ "${cdp_access}" = "1" ]; then
    echo "qa_status: qa_ok:cdp_report_only"
  else
    echo "qa_status: qa_ok:report_only"
  fi
}

model_routing_lane_for_shape() {
  local shape
  # Normalize: lowercase and strip whitespace so "FAST_SCAN" or " lookup "
  # classify the same as "fast_scan"/"lookup" instead of falling to unclassified.
  shape="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "${shape}" in
    lookup|fast_scan|file_lookup|symbol_lookup|scan) echo "fast_scan" ;;
    bounded_impl|low_cost_impl|small_fix|narrow_impl) echo "low_cost_impl" ;;
    standard_impl|implementation|refactor|feature) echo "standard_impl" ;;
    review|architecture|security_review|risk_review|frontier) echo "frontier_review" ;;
    "") echo "none" ;;
    *) echo "unclassified" ;;
  esac
}

write_model_routing_lane_audit() {
  local shape principal gemini_cmd recommended

  shape="${MODEL_ROUTING_INPUT_SHAPE:-}"
  principal="${AI_AUTO_PRINCIPAL:-codex}"
  gemini_cmd="${GEMINI_REVIEW_COMMAND:-agy}"
  recommended="$(model_routing_lane_for_shape "${shape}")"

  echo "audit_status: report_only"
  echo "active_principal: ${principal}"
  if [ -n "${shape}" ]; then
    echo "input_shape: ${shape}"
  else
    echo "input_shape: none"
  fi
  echo "recommended_lane: ${recommended}"

  # Per-principal fast-class availability (observe-only; mirrors the
  # discover-ai-models.sh Principal Class Lanes contract). Gemini stays
  # honestly class-fixed because it is invoked only via its review command.
  echo "fast_lane_codex: available"
  echo "fast_lane_claude: available_when_model_flag_supported"
  echo "fast_lane_gemini: class_unavailable (invoked only via ${gemini_cmd}; gemini -m forbidden)"

  case "${recommended}" in
    fast_scan|low_cost_impl)
      case "${principal}" in
        gemini)
          echo "missed_fast_lane_opportunity: fast_lane_unavailable (gemini class-fixed)"
          ;;
        *)
          echo "missed_fast_lane_opportunity: candidate (${recommended} can use the fast class)"
          ;;
      esac
      ;;
    *)
      echo "missed_fast_lane_opportunity: none"
      ;;
  esac

  echo "runtime_lane_added: false"
  echo "routing_authority: none"
}

write_micro_work_audit() {
  # Report-only MicroWork scope audit. Self-contained (no dependency on the
  # home-only contract module) so it stays portable in downstream template
  # copies. Active only when a micro-unit file is present; never blocks.
  local file="${MICRO_WORK_FILE:-.omx/micro/current.json}"
  echo "audit_status: report_only"
  if [ ! -f "${file}" ]; then
    echo "micro_work_status: no_micro_unit"
    echo "No MicroWork unit file at ${file}; set MICRO_WORK_FILE to enable the scope audit."
    return 0
  fi
  local changed
  changed="$(review_git -c core.quotepath=false status --porcelain 2>/dev/null || true)"
  MICRO_WORK_CHANGED="${changed}" python3 - "${file}" <<'PY'
import json, os, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as handle:
        rec = json.load(handle)
except Exception as exc:  # noqa: BLE001
    print("micro_work_status: invalid_micro_unit")
    print(f"could not parse {path}: {exc}")
    sys.exit(0)
if not isinstance(rec, dict):
    # Report-only contract: never crash review-context generation on non-object JSON.
    print("micro_work_status: invalid_micro_unit")
    print("micro-unit file is not a JSON object")
    sys.exit(0)
required = ["id", "goal", "scope_paths", "smallest_useful_wedge", "non_goals", "required_evidence", "completion_criteria"]
list_fields = {"scope_paths", "non_goals", "required_evidence", "completion_criteria"}
ne_str = lambda v: isinstance(v, str) and v.strip() != ""
ne_list = lambda v: isinstance(v, (list, tuple)) and any(ne_str(x) for x in v)
missing = [f for f in required if not (ne_list(rec.get(f)) if f in list_fields else ne_str(rec.get(f)))]
if missing:
    print("micro_work_status: incomplete_micro_unit")
    print("missing_fields: " + ", ".join(sorted(missing)))
    sys.exit(0)
def under(p, e):
    e = e.rstrip("/")
    return p == e or p.startswith(e + "/")
scope = [s.strip() for s in rec["scope_paths"] if ne_str(s)]
non_goals = [s.strip() for s in rec["non_goals"] if ne_str(s)]
changed = []
for line in os.environ.get("MICRO_WORK_CHANGED", "").split("\n"):
    if len(line) < 4:
        continue
    status = line[:2]
    p = line[3:]  # strip the 2-char XY status + space
    if ("R" in status or "C" in status) and " -> " in p:  # rename/copy: keep destination
        p = p.split(" -> ")[-1]
    p = p.strip().strip('"')
    if p:
        changed.append(p)
drift = [p for p in changed if not any(under(p, s) for s in scope)]
leak = [p for p in changed if any(under(p, g) for g in non_goals)]
print("micro_work_status: ready")
print("smallest_useful_wedge: present")
print("required_evidence: present")
print("scope_drift: " + (", ".join(drift) if drift else "none"))
print("non_goal_leak: " + (", ".join(leak) if leak else "none"))
PY
}

LIGHTWEIGHT_CONTEXT=0
if use_lightweight_context; then
  LIGHTWEIGHT_CONTEXT=1
fi

# Fail-closed on a corrupt/unreadable repository (e.g. truncated .git/index): otherwise a git
# call downstream dies mid-write with a raw exit 128 under `set -e`, and a reviewer could trust
# the partial/misleading context that was already emitted. Probe through the hardened review_git
# (drift-guard: no bare git); `status --porcelain` reads the index+worktree, so a corrupt index
# makes it exit non-zero HERE, before any context is written. A fresh/empty repo exits 0.
if ! review_git status --porcelain >/dev/null 2>&1; then
  echo "collect-review-context: FAIL-CLOSED — git could not read repository state (corrupt/truncated .git/index or unreadable repo). Refusing to emit partial or misleading review context. Repair the repository (e.g. restore .git/index) and re-run." >&2
  exit 1
fi

# Atomic, symlink-safe write: a bare `> "${OUT_FILE}"` FOLLOWS a pre-existing symlink at that
# fixed path and clobbers whatever it targets, and a mid-run crash leaves a truncated file a
# reviewer might trust as complete. Refuse a symlinked target, render into a sibling temp on the
# SAME filesystem, then atomically rename into place.
if [ -L "${OUT_FILE}" ]; then
  echo "collect-review-context: FAIL-CLOSED — ${OUT_FILE} exists as a symlink; refusing to write through it." >&2
  exit 1
fi
_OUT_TMP="$(mktemp "${OUT_DIR}/.latest-review-context.XXXXXX")"
trap 'rm -f "${_OUT_TMP}"' EXIT

{
  echo "# Review Context"
  echo
  echo "Generated at: $(date -Iseconds)"
  echo
  echo "## Context Mode"
  echo
  if [ "${LIGHTWEIGHT_CONTEXT}" -eq 1 ]; then
    echo "lightweight"
    echo
    echo "Small staged/unstaged tracked diff detected. This context keeps reviewer input focused on the patch, git state, and verification tail."
    echo "Set REVIEW_CONTEXT_DETAIL=full to include planning artifacts and reference files."
  else
    echo "full"
    echo
    echo "Full context includes planning artifacts and repository workflow reference files."
  fi
  echo
  if [ "${REVIEW_INTEGRATION_ONLY:-0}" = "1" ]; then
    echo "## Integration-Only Review Focus"
    echo
    echo "This is a combine pass: each underlying task diff was already approved on its"
    echo "own. Review ONLY the cross-task interaction — conflicts, collisions, or"
    echo "regressions that arise from combining the already-approved changes (duplicate"
    echo "definitions, ordering, shared-state contention, cross-module name clashes)."
    echo "Do not re-litigate findings already settled in the per-task reviews."
    echo
  fi
  echo "## Repository"
  echo
  echo '```text'
  pwd
  echo '```'
  echo
  echo "## Git Status"
  echo
  echo '```text'
  review_git status --short
  echo '```'
  echo
  echo "## Diff Stat"
  echo
  write_diff_stat
  echo
  echo "## Diff Scope Summary"
  echo
  write_diff_scope_summary
  echo
  echo "## Untracked Files"
  echo
  echo '```text'
  # R24 (HIGH) belt: git leaves a printable-ASCII backtick-leading filename
  # unquoted, so an untracked file named ```zzz would emit a fence-opening line
  # inside this listing and desync the guard parsers. Indent every listing line so
  # no line can open/close a code fence (^``` no longer matches).
  git ls-files --others --exclude-standard | filter_targeted_recheck_files | sed 's/^/    /'
  echo '```'
  echo
  echo "Untracked text file content is omitted by default. Set INCLUDE_UNTRACKED_CONTENT=1 to include text files up to ${MAX_UNTRACKED_BYTES} bytes after confirming .gitignore excludes secrets."
  echo
  echo "## Untracked Review Guard"
  echo
  write_untracked_review_guard
  echo
  echo "## Phase Scope Guard"
  echo
  write_phase_scope_guard
  echo
  echo "## Tree Churn Audit"
  echo
  write_tree_churn_audit
  echo
  echo "## Completion Pack Routing Audit"
  echo
  write_completion_pack_routing_audit
  echo
  echo "## Product Challenge Audit"
  echo
  write_product_challenge_audit
  echo
  echo "## Visual Artifact Audit"
  echo
  write_visual_artifact_audit
  echo
  echo "## Planning Visual Gate Audit"
  echo
  write_planning_visual_gate_audit
  echo
  echo "## Spec Code Alignment Audit"
  echo
  write_spec_code_alignment_audit
  echo
  echo "## Standard Flow Preservation Audit"
  echo
  write_standard_flow_preservation_audit
  echo
  echo "## Browser QA Evidence Audit"
  echo
  write_browser_qa_evidence_audit
  echo
  echo "## Model Routing Lane Audit"
  echo
  write_model_routing_lane_audit
  echo
  echo "## MicroWork Audit"
  echo
  write_micro_work_audit
  echo
  echo "## Diff"
  echo
  write_diff
  if [ "$INCLUDE_UNTRACKED_CONTENT" = "1" ]; then
    echo "### Untracked File Content Diff"
    echo
    echo '```diff'
    untracked_n=0
    while IFS= read -r -d '' file; do
      targeted_recheck_file_selected "${file}" || continue
      untracked_n=$((untracked_n + 1))
      if [ "$untracked_n" -gt "$MAX_UNTRACKED_FILES" ]; then
        echo "# untracked file listing truncated at ${MAX_UNTRACKED_FILES} files (more untracked files present but not expanded)"
        break
      fi
      # Nested untracked git repo / gitlink boundary: `git ls-files --others` reports it as ONE
      # directory entry (trailing slash) and never descends, so code stashed in a nested .git is
      # invisible to reviewers. Fail-closed against silent omission: emit a clear present-but-not-
      # expanded marker and list its untracked entries (read-only, bounded), never skip it.
      # Refuse to descend into a SYMLINKED entry: `cd "$file"` would escape into an external
      # directory and leak that repo's untracked filenames into the review context. Skip symlinks.
      if [ -d "$file" ] && [ ! -L "$file" ]; then
        echo "# nested untracked repo present-but-not-expanded: ${file}"
        echo "# (content lives in a nested .git; not inlined in this diff — listing entries)"
        nested_n=0
        while IFS= read -r -d '' nf; do
          nested_n=$((nested_n + 1))
          if [ "$nested_n" -gt 200 ]; then echo "#   … (nested listing truncated at 200)"; break; fi
          echo "#   ${file}${nf}"
        # Pin core.fsmonitor= so a hostile nested `.git/config core.fsmonitor=<prog>` cannot execute
        # when this runs STANDALONE (no inherited git-scrub env pin from the gate path).
        done < <(cd "$file" 2>/dev/null && git -c core.fsmonitor= ls-files -z --others --exclude-standard 2>/dev/null || true)
        continue
      fi
      [ -f "$file" ] || continue
      grep -qI '' "$file" 2>/dev/null || continue
      size="$(wc -c < "$file" | tr -d ' ')"
      if [ "$size" -gt "$MAX_UNTRACKED_BYTES" ]; then
        echo "diff --git a/${file} b/${file}"
        echo "# skipped untracked file content: ${file} is ${size} bytes, limit is ${MAX_UNTRACKED_BYTES}"
        continue
      fi
      # `--no-filters` is INVALID on `git diff --no-index` (exit 129, swallowed by `|| true`) — it
      # silently dropped ALL untracked content, so opt-in reviewers saw an EMPTY fence. Remove it
      # and disarm the in-repo .gitattributes clean/smudge/textconv driver another way: review_git's
      # --no-index branch intentionally omits --attr-source, so the caller supplies the env
      # equivalent GIT_ATTR_SOURCE=<empty tree> (which git diff --no-index DOES honour), keeping the
      # read raw + hardened while the content now actually appears.
      GIT_ATTR_SOURCE="${_REVIEW_GIT_ATTR_NONE}" review_git diff --no-ext-diff --no-textconv --no-index -- /dev/null "$file" || true
    done < <(git ls-files -z --others --exclude-standard)
    echo '```'
  fi
  echo
    if [ -f "${OUT_DIR}/latest-verify-output.txt" ]; then
      echo "## Latest Verification Output"
      echo
      echo '```text'
      if [ "${LIGHTWEIGHT_CONTEXT}" -eq 1 ]; then
        echo "### Tail"
        tail -"${REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES}" "${OUT_DIR}/latest-verify-output.txt" | neutralize_fence_breaks
      else
        echo "### Head"
        sed -n '1,160p' "${OUT_DIR}/latest-verify-output.txt" | neutralize_fence_breaks
        echo
        echo "### Tail"
        tail -120 "${OUT_DIR}/latest-verify-output.txt" | neutralize_fence_breaks
      fi
      echo '```'
      echo
    fi
  echo "## Workflow Rule"
  echo
  echo "- Before completion, run ai-auto verify"
  echo "- If verification fails, the task is not complete."
  echo "- After code edits, compare the final diff with any applicable plan/spec/design artifact and report aligned, updated, not applicable, or blocked."
  echo "- User-facing reports should explain results in plain Korean before using internal technical identifiers."
  echo "- Do not commit without user approval."
  echo
  echo "## Local Planning Artifacts"
  echo
  if [ "${LIGHTWEIGHT_CONTEXT}" -eq 1 ]; then
    echo "Omitted in lightweight context. Set REVIEW_CONTEXT_DETAIL=full when planning artifacts are relevant to the review."
    echo
  else
  plan_files=()
  if [ -d ".omx/plans" ]; then
    while IFS= read -r file; do
      plan_files+=("$file")
    done < <(find .omx/plans -maxdepth 1 -type f \( -name 'prd-*.md' -o -name 'test-spec-*.md' \) | sort | tail -6)
  fi
  if [ "${#plan_files[@]}" -eq 0 ]; then
    echo "No local PRD or test-spec planning artifacts found."
    echo
  else
    for file in "${plan_files[@]}"; do
      echo "### $file"
      echo
      echo '```markdown'
      sed -n '1,240p' "$file" | neutralize_fence_breaks
      echo '```'
      echo
    done
  fi
  fi
  echo "## Relevant Files"
  echo
  if [ "${LIGHTWEIGHT_CONTEXT}" -eq 1 ]; then
    echo "Omitted in lightweight context. Set REVIEW_CONTEXT_DETAIL=full when AGENTS.md, docs/WORKFLOW.md, or docs/AI_ROLES.md content is needed."
    echo
  else
  while IFS= read -r file; do
    if [ -f "$file" ]; then
      write_markdown_file "$file"
    fi
  done < <(collect_review_reference_files)
  fi
} > "${_OUT_TMP}"
mv -f "${_OUT_TMP}" "${OUT_FILE}"

echo "${OUT_FILE}"
