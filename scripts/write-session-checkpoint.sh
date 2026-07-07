#!/usr/bin/env bash
set -euo pipefail

# Route the worktree `git status` below through the CANONICAL hardened review_git wrapper
# (scripts/git-harden.sh). An inline `git --attr-source=<empty-tree> status` only neutralizes the
# IN-TREE `.gitattributes`; it OMITS the fail-closed `$GIT_DIR/info/attributes` guard, the
# `core.fsmonitor=` pin, and `diff.external=`, so a hostile project repo still runs its
# `.git/config` clean driver on a stat-dirty tracked blob (RCE — this checkpoint is written by
# review-gate.sh over the untrusted project repo). review_git carries the full defense. Source
# the sibling when present+parseable (BLAST-H1 idiom, so `set -e` cannot abort a partial copy).
_hd="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-harden.sh"
# shellcheck source=scripts/git-harden.sh
if [ -f "${_hd}" ] && bash -n "${_hd}" 2>/dev/null; then . "${_hd}"; fi

CHECKPOINT_FILE="${OMX_SESSION_CHECKPOINT_FILE:-.omx/state/session-checkpoint.md}"
CHECKPOINT_STATUS_LIMIT="${OMX_SESSION_CHECKPOINT_STATUS_LIMIT:-40}"
CHECKPOINT_FIELD_LIMIT="${OMX_SESSION_CHECKPOINT_FIELD_LIMIT:-300}"
# RED9-5 fix: same default + override precedence as scripts/run-ai-reviews.sh:18 and
# scripts/review-gate.sh:118 (and the RED6-2 fix already applied to
# scripts/automation-doctor.sh:737) -- honor REVIEW_STATE_DIR so this checkpoint inspects the
# SAME reviewer-state directory the gate/reviewer actually read and write. Before this fix the
# "## Reviewer State" section below hardcoded ".omx/reviewer-state" and reported a false "none"
# for a genuinely disabled reviewer whenever REVIEW_STATE_DIR was overridden -- a false-green in
# a file explicitly documented as "resume evidence" an agent/operator is meant to trust.
REVIEW_STATE_DIR="${REVIEW_STATE_DIR:-.omx/reviewer-state}"
mkdir -p "$(dirname "$CHECKPOINT_FILE")"

# Symlink-safe: a bare `> "$CHECKPOINT_FILE"` FOLLOWS a pre-existing symlink, so a hostile repo
# shipping .omx/state/session-checkpoint.md as a symlink to ~/.bashrc gets that target overwritten
# on the first gate-driven checkpoint. REFUSE when the fixed path is a symlink.
if [ -L "$CHECKPOINT_FILE" ]; then
  echo "[checkpoint] REFUSING: ${CHECKPOINT_FILE} is a symlink; an untrusted repo could redirect this write to an arbitrary file. Remove the symlink and re-run." >&2
  exit 2
fi

case "$CHECKPOINT_STATUS_LIMIT" in
  ''|*[!0-9]*)
    echo "[checkpoint] invalid OMX_SESSION_CHECKPOINT_STATUS_LIMIT='${CHECKPOINT_STATUS_LIMIT}'" >&2
    exit 2
    ;;
esac

case "$CHECKPOINT_FIELD_LIMIT" in
  ''|*[!0-9]*)
    echo "[checkpoint] invalid OMX_SESSION_CHECKPOINT_FIELD_LIMIT='${CHECKPOINT_FIELD_LIMIT}'" >&2
    exit 2
    ;;
esac

latest_file() {
  local dir="$1"
  local pattern="$2"

  [ -d "$dir" ] || return 0
  ls -t "$dir"/$pattern 2>/dev/null | head -1 || true
}

generated_at="$(date -Iseconds)"
latest_manifest="$(latest_file ".omx/review-results" "review-run-*.md")"
latest_verdict="$(latest_file ".omx/review-results" "review-verdict-*.md")"
latest_routing=".omx/model-routing/latest.md"

write_field() {
  local label="$1"
  local value="$2"
  local fallback="$3"

  if [ -n "$value" ]; then
    echo "- ${label}: $(compact_value "$value")"
  else
    echo "- ${label}: ${fallback}"
  fi
}

compact_value() {
  local value="$1"
  local limit="$CHECKPOINT_FIELD_LIMIT"

  value="$(printf '%s' "$value" | tr '\n' ' ')"
  if [ "${#value}" -gt "$limit" ]; then
    printf '%s... [truncated]\n' "${value:0:limit}"
  else
    printf '%s\n' "$value"
  fi
}

write_git_status() {
  local status_output
  local total_lines

  # review_git (scripts/git-harden.sh, sourced above) disarms an in-repo .gitattributes /
  # info/attributes + `.git/config` clean-filter driver + core.fsmonitor that `git status` would
  # otherwise run on a stat-dirty tracked blob (RCE), and fail-closed REFUSES a hostile
  # info/attributes binding — the residual --attr-source could not cover.
  status_output="$(review_git status --short)"
  if [ -z "$status_output" ]; then
    echo "  clean"
    return 0
  fi

  total_lines="$(printf '%s\n' "$status_output" | wc -l | tr -d ' ')"
  if [ "$CHECKPOINT_STATUS_LIMIT" -gt 0 ]; then
    printf '%s\n' "$status_output" | sed -n "1,${CHECKPOINT_STATUS_LIMIT}p" | sed 's/^/  /'
  fi
  if [ "$total_lines" -gt "$CHECKPOINT_STATUS_LIMIT" ]; then
    echo "  ... truncated $((total_lines - CHECKPOINT_STATUS_LIMIT)) additional status lines"
  fi
}

# Atomic write (mktemp in the same dir + `mv -f`, the review_provenance_record pattern): a
# concurrent reader never sees a half-written checkpoint, and `mv -f` replaces the name itself
# (never follows a symlink target). trap-clean the temp on any early exit.
_ck_dir="$(dirname "$CHECKPOINT_FILE")"
_ck_tmp="$(mktemp "${_ck_dir}/.session-checkpoint.XXXXXX")"
trap 'rm -f "${_ck_tmp}"' EXIT
{
  echo "# Session Checkpoint"
  echo
  echo "Generated at: ${generated_at}"
  echo
  echo "## Git"
  echo
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "- Branch: $(git branch --show-current 2>/dev/null || true)"
    echo "- Status:"
    write_git_status
  else
    echo "- Not inside a git repository"
  fi
  echo
  echo "## Current Work"
  echo
  write_field "Objective" "${OMX_SESSION_OBJECTIVE:-}" "not set"
  write_field "Plan file" "${OMX_PLAN_FILE:-}" "not set"
  write_field "Current step" "${OMX_PLAN_STEP:-}" "not set"
  write_field "Completed steps" "${OMX_COMPLETED_STEPS:-}" "not set"
  write_field "Next step" "${OMX_NEXT_STEP:-}" "not set"
  write_field "Blockers" "${OMX_BLOCKERS:-}" "none recorded"
  echo
  echo "## Continue Or Escalate"
  echo
  write_field "Decision" "${OMX_CONTINUE_OR_ESCALATE:-}" "continue"
  write_field "Reason" "${OMX_CONTINUATION_REASON:-}" "within current scope unless a blocker is recorded"
  echo
  echo "## Resource Profile"
  echo
  write_field "Mode" "${OMX_RESOURCE_PROFILE:-}" "normal"
  write_field "Parallelism notes" "${OMX_PARALLELISM_NOTES:-}" "not set"
  echo
  echo "## Latest Review Evidence"
  echo
  echo "- Manifest: ${latest_manifest:-none}"
  echo "- Verdict: ${latest_verdict:-none}"
  echo "- Model routing: $([ -f "$latest_routing" ] && echo "$latest_routing" || echo none)"
  echo
  echo "## Reviewer State"
  echo
  if [ -d "${REVIEW_STATE_DIR}" ] && ls "${REVIEW_STATE_DIR}"/*.disabled >/dev/null 2>&1; then
    for marker in "${REVIEW_STATE_DIR}"/*.disabled; do
      reviewer="$(sed -n 's/^reviewer=//p' "$marker" | head -1)"
      reason="$(sed -n 's/^reason=//p' "$marker" | head -1)"
      echo "- ${reviewer:-unknown}: ${reason:-disabled}"
    done
  else
    echo "- none"
  fi
  echo
  echo "## Resume Notes"
  echo
  echo "- Treat this checkpoint as resume evidence, not as a replacement for current git status."
  echo "- Re-read the latest user request before continuing."
} > "$_ck_tmp"
mv -f "$_ck_tmp" "$CHECKPOINT_FILE"
trap - EXIT

echo "[checkpoint] wrote ${CHECKPOINT_FILE}"
