#!/usr/bin/env bash
set -euo pipefail

# ai-auto-audit.sh -- minimum-viable OUT-OF-BAND AUDITOR (spec AC1-7; RED8 Angle A).
# See .ops-game/R3-red8-auditor-observability.md ("minimum-viable out-of-band auditor spec")
# and docs/ops-audits/2026-07-07-spec-v2.md (AC1-7) for the design this implements.
#
# ============================================================================================
# WHAT THIS IS: DETECTION, NOT PREVENTION -- READ BEFORE TRUSTING A CLEAN REPORT
# ============================================================================================
# Nearly every gate artifact this script reads (HMAC-signed provenance/binding/reviewer-marker
# records, the RUNTIME_ORACLE=<state> marker, chronic_count bookkeeping, launcher evidence,
# review-history.log) is SAME-UID-forgeable: a same-UID shell can source the exact helper that
# produces an artifact and call it directly, minting a byte-identical, validly-signed record
# without ever running the code path that is supposed to produce it (see
# scripts/ai-principal-runtime.sh, scripts/review-gate-binding.sh, scripts/verify.sh's own
# RUNTIME_ORACLE comment -- all three already say this in-line; this header does not
# contradict them, it inherits the same honesty discipline).
#
# This script is deliberately run OUT-OF-BAND: a human, cron, or CI invokes it -- it is NOT
# wired into review-gate.sh / run-ai-reviews.sh / hooks/* themselves. The headline bug class
# this whole design responds to is "the gate never ran in this worktree at all" (hooks do not
# propagate to `git worktree add` / clone / push); an auditor triggered through the SAME hook
# path it audits would inherit that exact blind spot, so it must be invoked independently.
#
# WHAT THIS STRUCTURALLY CANNOT CATCH: a same-UID actor willing to fabricate EVERY artifact
# consistently -- a valid HMAC (they hold the same key file, because they run as the UID that
# owns it), a `RUNTIME_ORACLE=passed:x` line printed without ever touching the real harness, a
# hand-appended review-history.log JSON line, a binding-verdict.env whose binding_hash they
# recomputed to match whatever diff they like -- is, by construction, indistinguishable from a
# genuine run. Every artifact this script reads is itself writable by that same UID, and there
# is no residue left over from "actually executing the real logic" that a determined forger
# cannot also produce (they ARE the process class that would have produced it legitimately).
# Closing that residual gap needs a DIFFERENT TRUST DOMAIN, not more tool-side cleverness:
#   (a) a privilege boundary the attacker's UID cannot write across -- e.g. an append-only
#       receipt log kept by a separate service account/daemon that independently observes
#       process start/stop (auditd/eBPF), never trusting a self-reported marker; or
#   (b) genuine server-side re-execution (a CI required check / pre-receive hook / a remote
#       build) whose transcript the developer's own shell cannot rewrite after the fact -- this
#       is what actually caught the real historical incident this whole spec is a response to.
# That is out of THIS script's scope (jw_dev-side, per spec-v2.md's own "정본 백스톱은 궁극적으로
# 서버측" line). Calling this script "the canonical backstop" without this caveat would be
# exactly the kind of overclaim docs/ops-audits/2026-07-07-spec-v2.md's D2 correction exists to
# prevent -- so: it is A backstop against operator mistakes, unwired hooks, and low-effort
# same-UID shortcuts (the actual historical incident class), not a security boundary against a
# determined same-UID adversary.
# ============================================================================================
#
# What it DOES catch (tool-side-feasible, genuinely valuable):
#   1. OMISSION       -- HEAD has neither a review-history record nor an authenticated binding
#                        verdict at all (the gate never ran / was never recorded for this HEAD).
#   2. STALENESS/RANGE -- the latest binding verdict's recorded hash does not cover HEAD's
#                        actually-introduced commits (the tree moved on without re-review).
#   3. RUNTIME-ORACLE  -- a project that claims a runtime-oracle contract shows only the marker,
#                        not evidence a real harness ran.
#   4. AUTH-DRIFT      -- reviewer-state markers (.disabled/.chronic) whose HMAC is absent,
#                        tampered, or internally inconsistent (chronic_count vs its side file).
#   5. HISTORY         -- .omx/review-history.log is missing/empty despite commits existing.
#
# Usage: ai-auto-audit.sh [PROJECT_DIR]     (PROJECT_DIR defaults to the current directory)
# Exit 0  = clean (no HIGH flag raised; still read the WARN/SKIP lines -- they are findings too).
# Exit 1  = at least one HIGH flag (see the FLAG lines and the summary).
# Exit 2  = the auditor itself could not run (bad PROJECT_DIR / not a git repo with a commit /
#           the hardened git-exec guard REFUSED a hostile repo -- look for a LOUD
#           "HOSTILE-REPO DETECTED" line, which is a materially different finding from an
#           ordinary path mistake even though both currently share this exit code).

# Sibling-resolve our own dir the same way review-gate.sh/hooks/post-commit do, so this script
# is invocable from any cwd/PATH/symlink and always finds its real siblings.
AH="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# BLAST-H1 idiom (ai-auto convention): source a hardening sibling only when present AND
# parseable, so a partial/broken engine copy cannot abort THIS advisory tool via `set -e`.
if [ -f "$AH/../hooks/git-scrub.sh" ] && bash -n "$AH/../hooks/git-scrub.sh" 2>/dev/null; then
  # shellcheck source=../hooks/git-scrub.sh
  . "$AH/../hooks/git-scrub.sh"
else
  printf '[audit] WARNING: hooks/git-scrub.sh missing or unparseable; continuing WITHOUT the git-exec-env scrub.\n' >&2
fi

# review_git (scripts/git-harden.sh) -- the single hardened-git wrapper every git call below
# routes through, closing the project-local .gitattributes/.git-config diff/filter RCE surface
# on every worktree-side git call this auditor makes over a (potentially untrusted) project tree.
# shellcheck source=scripts/git-harden.sh
. "${AI_AUTO_GIT_HARDEN_SH:-$AH/git-harden.sh}"

# review_binding_* -- the real, shipped binding-hash/authenticity primitives (review-gate-binding.sh
# is written to be library-safe to source: function definitions only, no top-level side effects).
# shellcheck source=scripts/review-gate-binding.sh
. "${AI_AUTO_REVIEW_GATE_BINDING_SH:-$AH/review-gate-binding.sh}"

# run-ai-reviews.sh is NOT library-safe to source whole (it runs the review pipeline at the
# bottom of the file with no BASH_SOURCE guard). Extract just the principal-evidence-auth HMAC
# primitives + reviewer-marker helpers verbatim by boundary text, mirroring the established
# pattern in scripts/verify-machinery.sh's BLUE-R25-PRINCIPAL-AUTH self-tests and
# tests/test_reviewer_restore_ip3.py's _extract_bash_functions -- this still tests/uses the
# real, current function bodies (no copy to drift out of sync).
RUN_AI_REVIEWS_SH="${AI_AUTO_RUN_AI_REVIEWS_SH:-$AH/run-ai-reviews.sh}"
if [ -f "${RUN_AI_REVIEWS_SH}" ]; then
  # shellcheck disable=SC1090
  source <(sed -n '/# >>> principal-evidence-auth/,/# <<< principal-evidence-auth/p' "${RUN_AI_REVIEWS_SH}")
  # shellcheck disable=SC1090
  source <(awk '/^reviewer_disabled_file\(\)/,/^}/' "${RUN_AI_REVIEWS_SH}")
  # shellcheck disable=SC1090
  source <(awk '/^reviewer_marker_canonical\(\)/,/^}/' "${RUN_AI_REVIEWS_SH}")
  # shellcheck disable=SC1090
  source <(awk '/^reviewer_disabled_authentic\(\)/,/^}/' "${RUN_AI_REVIEWS_SH}")
else
  printf '[audit] WARNING: %s not found; CHECK4-AUTH-DRIFT cannot verify reviewer-marker HMACs.\n' "${RUN_AI_REVIEWS_SH}" >&2
fi

# --- resolve target -------------------------------------------------------------------------
PROJECT_DIR_ARG="${1:-.}"
PROJECT_DIR="$(cd "${PROJECT_DIR_ARG}" 2>/dev/null && pwd)" || {
  printf '[audit] ERROR: cannot cd into project dir %q\n' "${PROJECT_DIR_ARG}" >&2
  exit 2
}

# RED2-2 finding #6: _review_git_attr_guard (scripts/git-harden.sh) fires on EVERY review_git
# call regardless of subcommand -- including these two bare entry-point rev-parses -- and
# refuses (rc 3) with an actionable `review_git: REFUSING -- .../info/attributes binds a
# filter/diff driver ...` message when it detects a hostile repo (e.g. a planted
# `.git/info/attributes` RCE vector). Both calls used to route stderr straight to /dev/null, so
# that message never reached the operator: a genuine hostile-repo detection surfaced as a
# generic "not a git repository"/exit 2, indistinguishable from an ordinary path mistake --
# under-alarming the single most security-relevant signal this script can produce. Capture each
# call's stderr instead of discarding it, so a guard refusal can be told apart and surfaced LOUD.
AUDIT_TMPDIR="$(mktemp -d 2>/dev/null || true)"
if [ -n "${AUDIT_TMPDIR}" ]; then
  trap 'rm -rf "${AUDIT_TMPDIR}" 2>/dev/null || true' EXIT
fi
_audit_stderr_capture() {
  # Path to redirect an entry-point review_git call's stderr into. Falls back to /dev/null
  # (losing only the loud-surfacing upgrade below, not the underlying fail-closed exit) if a
  # scratch dir could not be created.
  if [ -n "${AUDIT_TMPDIR}" ]; then
    printf '%s/%s\n' "${AUDIT_TMPDIR}" "$1"
  else
    printf '/dev/null\n'
  fi
}
_audit_report_hostile_repo_if_guard_refused() {
  local stderr_file="$1" target="$2"
  if grep -q 'review_git: REFUSING' "${stderr_file}" 2>/dev/null; then
    printf '[audit] HOSTILE-REPO DETECTED (LOUD): the hardened git-exec guard REFUSED to operate on %q -- this is a BLOCKED filter/diff-driver RCE attempt (e.g. a planted .git/info/attributes), NOT a path/environment mistake. Guard message:\n' "${target}" >&2
    sed 's/^/[audit]   /' "${stderr_file}" >&2
    return 0
  fi
  return 1
}

_repo_root_stderr="$(_audit_stderr_capture repo-root)"
REPO_ROOT="$(review_git -C "${PROJECT_DIR}" rev-parse --show-toplevel 2>"${_repo_root_stderr}" || true)"
if [ -z "${REPO_ROOT}" ]; then
  if ! _audit_report_hostile_repo_if_guard_refused "${_repo_root_stderr}" "${PROJECT_DIR}"; then
    printf '[audit] ERROR: %q is not inside a git repository.\n' "${PROJECT_DIR}" >&2
  fi
  exit 2
fi
cd "${REPO_ROOT}"

_head_sha_stderr="$(_audit_stderr_capture head-sha)"
HEAD_SHA="$(review_git rev-parse HEAD 2>"${_head_sha_stderr}" || true)"
if [ -z "${HEAD_SHA}" ]; then
  if ! _audit_report_hostile_repo_if_guard_refused "${_head_sha_stderr}" "${REPO_ROOT}"; then
    printf '[audit] ERROR: %q has no HEAD commit (empty repo) -- nothing to audit yet.\n' "${REPO_ROOT}" >&2
  fi
  exit 2
fi

REVIEW_STATE_DIR="${REVIEW_STATE_DIR:-.omx/reviewer-state}"
VERIFY_OUTPUT_FILE="${VERIFY_OUTPUT_FILE:-.omx/review-context/latest-verify-output.txt}"
HISTORY_FILE=".omx/review-history.log"

printf '[audit] ai-auto-audit.sh -- out-of-band auditor (DETECTION, not PREVENTION -- see header)\n'
printf '[audit] target repo: %s\n' "${REPO_ROOT}"
printf '[audit] HEAD: %s\n\n' "${HEAD_SHA}"

# --- report plumbing -------------------------------------------------------------------------
HIGH_COUNT=0
WARN_COUNT=0
FLAG_LINES=()

flag_high() {
  local check="$1" msg="$2"
  HIGH_COUNT=$((HIGH_COUNT + 1))
  FLAG_LINES+=("HIGH ${check}: ${msg}")
  printf '[audit] %-24s FLAG (HIGH)  %s\n' "${check}" "${msg}"
}
flag_warn() {
  local check="$1" msg="$2"
  WARN_COUNT=$((WARN_COUNT + 1))
  FLAG_LINES+=("WARN ${check}: ${msg}")
  printf '[audit] %-24s FLAG (WARN)  %s\n' "${check}" "${msg}"
}
pass_check() {
  local check="$1" msg="$2"
  printf '[audit] %-24s PASS         %s\n' "${check}" "${msg}"
}
skip_check() {
  local check="$1" msg="$2"
  printf '[audit] %-24s SKIP         %s\n' "${check}" "${msg}"
}

# --- CHECK1: OMISSION -------------------------------------------------------------------------
# Is there a review-history.log record AND/OR an authenticated binding verdict for HEAD? If
# neither exists, HEAD was never gated (or the gate's evidence trail is missing/unauthenticated)
# -- this is the literal headline-incident class (gate never ran / hooks not installed).
HAS_BINDING=0
BINDING_DECISION=""

check_omission() {
  local check="CHECK1-OMISSION"
  local has_history=0

  if [ -f "${HISTORY_FILE}" ] \
    && grep -F "\"head_sha\":\"${HEAD_SHA}\"" "${HISTORY_FILE}" 2>/dev/null \
      | grep -Eq '"verdict":"proceed(_degraded)?"'; then
    has_history=1
  fi

  if review_binding_authentic 2>/dev/null; then
    BINDING_DECISION="$(review_binding_field binding_decision)"
    case "${BINDING_DECISION}" in
      proceed | proceed_degraded) HAS_BINDING=1 ;;
    esac
  fi

  if [ "${has_history}" -eq 1 ] || [ "${HAS_BINDING}" -eq 1 ]; then
    pass_check "${check}" "HEAD ${HEAD_SHA:0:12} has $( [ "${HAS_BINDING}" -eq 1 ] && printf 'an authenticated binding verdict (%s)' "${BINDING_DECISION}" || printf 'no authenticated binding verdict' ), $( [ "${has_history}" -eq 1 ] && printf 'a matching' || printf 'no matching' ) ${HISTORY_FILE} entry"
  else
    flag_high "${check}" "HEAD ${HEAD_SHA:0:12} is unaudited: no ${HISTORY_FILE} entry with verdict proceed/proceed_degraded for this sha, AND no authenticated binding-verdict.env with decision proceed/proceed_degraded. This commit was never gated, or its evidence trail is missing/unauthenticated."
  fi
}

# --- CHECK2: STALENESS/RANGE -------------------------------------------------------------------
# Does the latest recorded binding verdict actually cover HEAD's introduced commits? Recompute
# the SAME hash review-gate-binding.sh would (mirroring the safe-base/remote-tracking idea via
# the real, shipped review_binding_hash/review_binding_committed_payload) and compare against
# what was recorded. A mismatch means the tree moved on without a fresh review binding it.
check_staleness() {
  local check="CHECK2-STALENESS"
  if [ "${HAS_BINDING}" -ne 1 ]; then
    skip_check "${check}" "no authenticated proceed/proceed_degraded binding verdict to check a range against (see CHECK1-OMISSION)"
    return
  fi
  local recorded current
  recorded="$(review_binding_field binding_hash)"
  current="$(review_binding_hash HEAD "" 2>/dev/null || true)"
  if [ -z "${current}" ] || [ -z "${recorded}" ]; then
    flag_high "${check}" "could not recompute/compare a binding hash for HEAD ${HEAD_SHA:0:12} (recorded='${recorded:-<empty>}', recomputed='${current:-<empty>}')"
    return
  fi
  if [ "${current}" = "${recorded}" ]; then
    # RED2-2 finding #1: this PASS's range trust rests on review_binding_committed_payload's
    # base-resolution fallback chain (@{u} first, else the empty tree -- see
    # review-gate-binding.sh's own in-line "documented residual, not a closed hole" comment).
    # @{u} is an ordinary local ref, same-UID-settable via `git branch --set-upstream-to=<decoy>`
    # or a raw `update-ref`; a same-UID actor who points it at a descendant of HEAD before this
    # check runs collapses merge-base(HEAD, decoy) back to HEAD, making the range-diff section
    # empty and any earlier unreviewed commit's content vanish from the very hash this PASS calls
    # "matches" -- reproduced end-to-end in .ops-game2/R1-red2-auditor.md finding #1. Say so
    # every time, not just when review-gate-binding.sh's own comments happen to be read: an
    # honest PASS here is only as good as @{u}, and this check cannot tell a genuine upstream
    # from a same-UID-planted decoy.
    pass_check "${check}" "recorded binding_hash matches the recomputed HEAD range hash (the verdict's range covers HEAD) -- CAVEAT: this range's base resolves via '@{u}' (or the empty-tree fallback), an ordinary local ref that is same-UID-forgeable (git branch --set-upstream-to=<decoy>); a genuine same-UID @{u} forge collapsing the range to hide an unreviewed commit is NOT caught by this check. PASS reflects internal consistency with @{u}, not proof against that forgery."
  else
    flag_high "${check}" "recorded binding_hash (${recorded:0:16}...) does NOT match the recomputed range hash for HEAD ${HEAD_SHA:0:12} (${current:0:16}...) -- stale/mismatched proof: the tree moved on without a fresh review covering it."
  fi
}

# --- CHECK3: RUNTIME-ORACLE ---------------------------------------------------------------------
# If the captured verify-output log shows the project opted into the runtime-oracle contract
# (scripts/verify.sh's `[verify-project] RUNTIME_ORACLE=<state>` line), is there evidence a real
# harness actually ran (state == passed(:*)) vs. just the log/marker being present?
check_runtime_oracle() {
  local check="CHECK3-RUNTIME-ORACLE"
  local require="${AI_AUTO_REQUIRE_RUNTIME_ORACLE:-0}"
  if [ ! -f "${VERIFY_OUTPUT_FILE}" ]; then
    # RED13-4: under an opted-in REQUIRE contract, an absent verify-output log is NOT the same
    # as "this project doesn't use runtime-oracle" -- it is indistinguishable from "the log was
    # deleted (same-UID) after a real run, or verify was never invoked at all", i.e. NO EVIDENCE
    # the oracle ran. Under REQUIRE, no-evidence must fail closed (FLAG), not vanish as a SKIP.
    if [ "${require}" = "1" ]; then
      flag_high "${check}" "AI_AUTO_REQUIRE_RUNTIME_ORACLE=1 is set for this project but no captured verify-output log exists at ${VERIFY_OUTPUT_FILE} -- no evidence the runtime-oracle harness ran at all (log missing or deleted); a required contract with no evidence is NOT-VALIDATED, not exempt."
    else
      skip_check "${check}" "no captured verify-output log at ${VERIFY_OUTPUT_FILE} -- cannot assess a runtime-oracle claim (see CHECK1/CHECK5 for whether verify ran at all)"
    fi
    return
  fi
  local oracle_line oracle_state
  oracle_line="$(grep -E '^\[verify-project\] RUNTIME_ORACLE=' "${VERIFY_OUTPUT_FILE}" 2>/dev/null | tail -n1 || true)"
  oracle_state="${oracle_line#*RUNTIME_ORACLE=}"
  case "${oracle_state}" in
    passed | passed:*)
      pass_check "${check}" "verify-output log shows RUNTIME_ORACLE=${oracle_state} (a real harness marker, not merely the log's presence)"
      ;;
    *)
      if grep -Fq 'NOT-VALIDATED (runtime oracle did not run)' "${VERIFY_OUTPUT_FILE}" 2>/dev/null; then
        if [ "${require}" = "1" ]; then
          flag_high "${check}" "verify-output log's own NOT-VALIDATED signal is present (saw RUNTIME_ORACLE='${oracle_state:-absent}') and AI_AUTO_REQUIRE_RUNTIME_ORACLE=1 is set for this project -- a runtime-oracle contract is required but evidence it ran is absent."
        else
          flag_warn "${check}" "verify-output log's own NOT-VALIDATED signal is present (saw RUNTIME_ORACLE='${oracle_state:-absent}'); AI_AUTO_REQUIRE_RUNTIME_ORACLE is not 1 for this project so this is advisory only -- 'verify green' here does NOT imply runtime-oracle-validated."
        fi
      else
        # Sibling of the RED13-4 gap above: a log can be PRESENT (so the first branch is not
        # hit) yet have had its RUNTIME_ORACLE= line specifically stripped/truncated -- same
        # "no evidence" shape, just a different deletion granularity. Same REQUIRE-gated rule.
        if [ "${require}" = "1" ]; then
          flag_high "${check}" "AI_AUTO_REQUIRE_RUNTIME_ORACLE=1 is set for this project but verify-output log at ${VERIFY_OUTPUT_FILE} has no RUNTIME_ORACLE= line at all and no NOT-VALIDATED signal -- no evidence the required oracle contract ran or was even checked (line missing/stripped)."
        else
          skip_check "${check}" "verify-output log has no RUNTIME_ORACLE= line at all (this project likely does not opt into the runtime-oracle contract)"
        fi
      fi
      ;;
  esac
}

# --- CHECK4: AUTH-DRIFT / consistency -----------------------------------------------------------
# For every reviewer-state *.disabled marker: does its marker_hmac verify (reviewer_disabled_
# authentic, the SAME primitive run-ai-reviews.sh's skip-decision path trusts)? And is its
# chronic_count consistent with the (unauthenticated, HMAC-free) sibling *.chronic side file for
# the same reason? Either an absent/tampered HMAC or a cross-file mismatch is unverifiable/
# inconsistent state an operator should look at by hand -- flag it.
check_auth_drift() {
  local check="CHECK4-AUTH-DRIFT"
  if [ ! -d "${REVIEW_STATE_DIR}" ]; then
    skip_check "${check}" "no ${REVIEW_STATE_DIR} directory -- nothing to authenticate"
    return
  fi
  if ! command -v reviewer_disabled_authentic >/dev/null 2>&1; then
    flag_warn "${check}" "reviewer_disabled_authentic helper unavailable (run-ai-reviews.sh missing/unreadable at audit time) -- cannot verify any marker HMAC"
    return
  fi
  local marker found=0
  for marker in "${REVIEW_STATE_DIR}"/*.disabled; do
    [ -e "${marker}" ] || continue
    found=1
    local reviewer_name marker_hmac_stored chronic reason chronic_file chronic_file_reason chronic_file_count hist_disable_count
    reviewer_name="$(basename "${marker}" .disabled)"
    marker_hmac_stored="$(sed -n 's/^marker_hmac=//p' "${marker}" | head -n1)"
    chronic="$(sed -n 's/^chronic_count=//p' "${marker}" | head -n1)"
    reason="$(sed -n 's/^reason=//p' "${marker}" | head -n1)"

    if [ -z "${marker_hmac_stored}" ]; then
      flag_high "${check}" "reviewer-state marker '${marker}' (reviewer=${reviewer_name}) has NO marker_hmac -- unauthenticated; its chronic_count=${chronic:-<none>}/reason=${reason:-<none>} cannot be trusted as framework-written."
    elif reviewer_disabled_authentic "${reviewer_name}" 2>/dev/null; then
      pass_check "${check}" "reviewer-state marker '${marker}' (reviewer=${reviewer_name}) marker_hmac verifies"
    else
      flag_high "${check}" "reviewer-state marker '${marker}' (reviewer=${reviewer_name}) carries a marker_hmac that does NOT verify (tampered or forged) -- its chronic_count=${chronic:-<none>} cannot be trusted."
    fi

    # Cross-check chronic_count against the sibling .chronic side file (which carries NO hmac at
    # all) when both agree on the same `reason` -- a mismatch means one was edited without the
    # other, independent of whether the .disabled's own HMAC happens to verify.
    chronic_file="${REVIEW_STATE_DIR}/${reviewer_name}.chronic"
    if [ -f "${chronic_file}" ]; then
      chronic_file_reason="$(sed -n 's/^reason=//p' "${chronic_file}" | head -n1)"
      chronic_file_count="$(sed -n 's/^count=//p' "${chronic_file}" | head -n1)"
      if [ -n "${reason}" ] && [ "${reason}" = "${chronic_file_reason}" ] \
        && [ -n "${chronic}" ] && [ "${chronic}" != "${chronic_file_count}" ]; then
        flag_high "${check}" "reviewer '${reviewer_name}': .disabled chronic_count=${chronic} disagrees with sibling ${chronic_file} count=${chronic_file_count} for the same reason='${reason}' -- one was edited without the other."
      fi
    fi

    # RED2-2 chronic-RESET erasure detection (the CHECK4 gap R1-red2-auditor.md's finding #2
    # named: review-gate.sh's own RED9-2 comment calls for exactly this -- "an out-of-band
    # auditor tracking chronic_file history/deltas independently"). A same-UID attacker who
    # deletes BOTH the .disabled marker AND its .chronic side file, then calls the real
    # disable_reviewer() once more, gets a fresh, validly-signed chronic_count=1 marker that the
    # checks above cannot distinguish from a reviewer's genuine first-ever disable -- the prior
    # streak (e.g. 12) is completely erased with no HMAC to forge, because there is nothing left
    # to compare against. scripts/run-ai-reviews.sh's disable_reviewer() now appends a durable,
    # append-only "event":"reviewer_disable" line to .omx/review-history.log on every disable
    # (a reset-and-redisable call included), so a reset LEAVES A TRAIL even though the side
    # files themselves were wiped: the number of disable-event lines recorded for this exact
    # reviewer+reason pair only ever grows, while a wiped-and-fresh marker's chronic_count drops
    # back to 1. current_chronic_count < recorded_disable_event_count for the same reviewer+
    # reason is exactly that discontinuity -- flag it.
    if [ -n "${reason}" ] && [ -f "${HISTORY_FILE}" ]; then
      case "${chronic}" in
        ''|*[!0-9]*) : ;; # non-numeric/absent chronic_count -- nothing to compare, skip silently
        *)
          hist_disable_count="$(grep -F '"event":"reviewer_disable"' "${HISTORY_FILE}" 2>/dev/null \
            | grep -F "\"reviewer\":\"${reviewer_name}\"" \
            | grep -F "\"reason\":\"${reason}\"" \
            | grep -c '.' 2>/dev/null || true)"
          case "${hist_disable_count}" in ''|*[!0-9]*) hist_disable_count=0 ;; esac
          if [ "${hist_disable_count}" -gt 0 ] && [ "${chronic}" -lt "${hist_disable_count}" ]; then
            flag_high "${check}" "reviewer '${reviewer_name}': current chronic_count=${chronic} (reason='${reason}') is LOWER than the ${hist_disable_count} disable-event(s) already recorded for this reviewer+reason in the durable ${HISTORY_FILE} trail -- consistent with a chronic-reset erasure (the .disabled/.chronic side files were deleted and re-disabled fresh, silently dropping a genuine chronic streak, whether by attack or by an unlogged manual reset). See ${HISTORY_FILE} for the true event count."
          fi
          ;;
      esac
    fi
  done
  [ "${found}" -eq 1 ] || skip_check "${check}" "no *.disabled markers present in ${REVIEW_STATE_DIR}"
}

# --- CHECK5: HISTORY presence --------------------------------------------------------------------
# Is .omx/review-history.log present and append-looking (not truncated/absent despite commits
# existing)? This is the durable trail RED8-1/RED8-3 exist to leave behind; its outright absence
# or emptiness in a non-trivial repo means there is nothing for CHECK1 (or a human) to read.
check_history_presence() {
  local check="CHECK5-HISTORY"
  local commit_count
  commit_count="$(review_git rev-list --count HEAD 2>/dev/null || echo 0)"
  if [ ! -f "${HISTORY_FILE}" ]; then
    if [ "${commit_count}" -gt 0 ] 2>/dev/null; then
      flag_high "${check}" "${commit_count} commit(s) exist but ${HISTORY_FILE} is absent -- no durable review-history trail for this repo at all."
    else
      skip_check "${check}" "no commits yet"
    fi
    return
  fi
  local n
  n="$(grep -c '.' "${HISTORY_FILE}" 2>/dev/null || echo 0)"
  if [ "${n}" -gt 0 ] 2>/dev/null; then
    pass_check "${check}" "${HISTORY_FILE} present with ${n} recorded entries"
  else
    flag_high "${check}" "${HISTORY_FILE} exists but is EMPTY despite ${commit_count} commit(s) -- truncated or never appended to (no durable review-history trail)."
  fi
}

# --- run all checks, then summarize --------------------------------------------------------------
check_omission
check_staleness
check_runtime_oracle
check_auth_drift
check_history_presence

printf '\n'
if [ "${HIGH_COUNT}" -gt 0 ]; then
  printf '[audit] SUMMARY: %d HIGH flag(s), %d WARN -- NOT CLEAN.\n' "${HIGH_COUNT}" "${WARN_COUNT}"
  for f in "${FLAG_LINES[@]}"; do
    case "${f}" in
      HIGH*) printf '  - %s\n' "${f}" ;;
    esac
  done
  printf '[audit] this is a DETECTION report, not a forgery-proof one -- see the header comment for what it structurally cannot catch.\n'
  exit 1
else
  printf '[audit] SUMMARY: 0 HIGH flags, %d WARN -- CLEAN.\n' "${WARN_COUNT}"
  printf '[audit] CLEAN means no flagged omission/staleness/auth-drift was found by THIS detector, not that every artifact is genuine -- see the header comment.\n'
  exit 0
fi
