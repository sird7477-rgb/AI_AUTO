#!/usr/bin/env bash
set -euo pipefail

# Framework sibling scripts live next to this one. Resolve our own dir (following
# symlinks) so siblings are reachable from ANY cwd / PATH / temp-sandbox fixture.
AH="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

VERIFY_OUTPUT_FILE="${VERIFY_OUTPUT_FILE:-.omx/review-context/latest-verify-output.txt}"
mkdir -p "$(dirname "$VERIFY_OUTPUT_FILE")"
# Clear any stale verify-failure override marker at gate start so an override can
# only ever apply to the run that explicitly sets it (written later, only on an
# approved verify failure). Prevents a prior run's override leaking forward.
rm -f .omx/state/verify-override.env

# Concurrency guard: warn / soft-block when another live session shares this working tree
# (prefer one git worktree per terminal — aiwt <name>). Released on every exit path.
if [ -f "$AH/session-lock.sh" ]; then
  # shellcheck source=scripts/session-lock.sh
  . "$AH/session-lock.sh"
  trap 'session_lock_release' EXIT
fi

# >>> review-provenance-shared: keep byte-identical in review-gate.sh and summarize-ai-reviews.sh >>>
# R2 (AI_AUTO_REVIEW_GATE_EFFICIENCY): record the working-tree-inclusive hash of an
# approved change so a byte-identical re-review can skip the full AI panel (the
# measured 61% of verdicts that re-run <15min on an unchanged diff). Recorded only on
# proceed + normal trust; consumed before run-ai-reviews. Every non-exact case fails
# open to a full review.
REVIEW_STATE_DIR="${REVIEW_STATE_DIR:-.omx/reviewer-state}"
REVIEW_PROVENANCE_ENV="${REVIEW_STATE_DIR}/approved-provenance.env"
REVIEW_PROVENANCE_LOG="${REVIEW_STATE_DIR}/approved-provenance.log"

# R5-1: every provenance diff/hash MUST stay inert to a PROJECT-LOCAL `.gitattributes` +
# `.git/config` diff/filter driver — git's standard code-exec surface (an external-diff
# `command`, a `textconv`, or a `clean` filter) that env scrubbing CANNOT touch because it
# lives IN the repo. Neutralize at the call site: --no-ext-diff/--no-textconv on every
# patch-producing diff, --no-filters on hash-object, plus -c overrides defeating any
# global/attr/config-driven exec. The red team verified these flags close the RCE.
review_git() {
  git -c diff.external= -c core.fsmonitor= -c core.attributesFile=/dev/null --no-pager "$@"
}

# Working-tree-inclusive provenance hash: HEAD commit + staged + unstaged + untracked
# content. Corrects DR1 (a committed-tree SHA would false-skip unstaged edits). Never
# uses `git write-tree`, which would mutate the index.
review_provenance_hash() {
  {
    git rev-parse HEAD 2>/dev/null || printf 'NO_HEAD\n'
    printf '\037diff\037\n';   review_git diff --no-ext-diff --no-textconv 2>/dev/null
    printf '\037cached\037\n'; review_git diff --cached --no-ext-diff --no-textconv 2>/dev/null
    printf '\037untracked\037\n'
    # Include each untracked file's PATH next to its blob hash so a same-content
    # rename / path swap changes the hash (content-only would false-match).
    git ls-files --others --exclude-standard -z 2>/dev/null \
      | while IFS= read -r -d '' provenance_file; do
          printf '%s\t' "${provenance_file}"
          review_git hash-object --no-filters "${provenance_file}" 2>/dev/null
        done
  } | review_git hash-object --stdin
}

review_provenance_head() {
  git rev-parse HEAD 2>/dev/null || true
}

# Active AI_AUTO principal from launcher evidence (empty when unrecorded). Part of the
# flag fingerprint so a skip recorded under one principal does not ride a run with a
# different principal / reviewer rotation.
review_provenance_principal() {
  local ev=".omx/state/principal-runtime/current.env"
  [ -f "${ev}" ] || return 0
  sed -n 's/^principal_runtime=//p' "${ev}" | head -1
}

# Flag fingerprint (D.4): a skip must run under the same untracked-content inclusion,
# allowlist, and active principal as the approving run, else it could ride coverage
# the approval lacked or misreport the reviewer rotation.
review_provenance_flags() {
  printf 'untracked=%s;allowlist=%s;manual=%s;principal=%s' \
    "${REVIEW_INCLUDE_UNTRACKED_CONTENT:-0}" \
    "${REVIEW_UNTRACKED_ALLOWLIST:-}" \
    "${REVIEW_UNTRACKED_MANUAL_REVIEWED:-0}" \
    "$(review_provenance_principal)"
}

# Any persisted reviewer-disable marker (D.9): a stale approval must not ride a
# now-degraded panel.
review_provenance_disabled_present() {
  find "${REVIEW_STATE_DIR}" -maxdepth 1 -type f -name '*.disabled' 2>/dev/null \
    | head -1 | grep -q .
}

# Record an approved provenance record. Atomic (mktemp+mv) so a concurrent session
# never reads a half-written env. Caller gates on proceed + normal trust.
review_provenance_record() {
  local hash head flags ts tmp
  hash="$(review_provenance_hash)"
  head="$(review_provenance_head)"
  flags="$(review_provenance_flags)"
  ts="$(date -Iseconds)"
  mkdir -p "${REVIEW_STATE_DIR}"
  tmp="$(mktemp "${REVIEW_STATE_DIR}/.approved-provenance.XXXXXX")" || return 0
  {
    printf 'approved_hash=%s\n' "${hash}"
    printf 'approved_head=%s\n' "${head}"
    printf 'approved_flags=%s\n' "${flags}"
    printf 'approved_at=%s\n' "${ts}"
  } > "${tmp}"
  mv -f "${tmp}" "${REVIEW_PROVENANCE_ENV}"
  printf '%s\t%s\t%s\t%s\n' "${ts}" "${head:-NO_HEAD}" "${hash}" "${flags}" >> "${REVIEW_PROVENANCE_LOG}"
}

review_provenance_field() {
  local key="$1"
  [ -f "${REVIEW_PROVENANCE_ENV}" ] || return 0
  sed -n "s/^${key}=//p" "${REVIEW_PROVENANCE_ENV}" | head -1
}

# Mirror run-ai-reviews.sh launcher-evidence validation so a provenance skip never
# rides stale / manual / mismatched / symlinked principal evidence (it skips
# run-ai-reviews, which is where that guard otherwise runs). Returns 0 only for a
# principal state run-ai-reviews would also accept; else the skip fails open to full.
review_provenance_principal_evidence_ok() {
  local workspace ev declared explicit
  workspace="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
  ev="${AI_AUTO_PRINCIPAL_EVIDENCE:-${workspace}/.omx/state/principal-runtime/current.env}"
  explicit="${AI_AUTO_PRINCIPAL:-}"
  if [ -f "${ev}" ]; then
    [ ! -L "${ev}" ] || return 1
    grep -Fqx "execution_mode=principal" "${ev}" || return 1
    grep -Fqx "source=ai-auto-principal-launcher" "${ev}" || return 1
    grep -Fqx "workspace=${workspace}" "${ev}" || return 1
    declared="$(sed -n 's/^principal_runtime=//p' "${ev}" | head -1)"
    case "${declared}" in codex|claude|gemini) ;; *) return 1 ;; esac
    [ -z "${explicit}" ] || [ "${explicit}" = "${declared}" ] || return 1
    return 0
  fi
  # No evidence: a non-codex explicit principal would make run-ai-reviews fail, so a
  # skip in that state would bypass the failure.
  case "${explicit}" in ""|codex) return 0 ;; *) return 1 ;; esac
}

# Echoes "skip" (exact match, same flags, no disabled reviewer → carry prior verdict)
# or "full" (no record / changed tree / flag mismatch / disabled present). Delta is
# deferred until collect-review-context honors a base, so every non-exact case is a
# full review.
review_provenance_decision() {
  local approved_hash approved_flags cur_hash cur_flags
  approved_hash="$(review_provenance_field approved_hash)"
  if [ -z "${approved_hash}" ]; then printf 'full\n'; return 0; fi
  cur_hash="$(review_provenance_hash)"
  if [ "${cur_hash}" != "${approved_hash}" ]; then printf 'full\n'; return 0; fi
  approved_flags="$(review_provenance_field approved_flags)"
  cur_flags="$(review_provenance_flags)"
  if [ "${cur_flags}" != "${approved_flags}" ]; then printf 'full\n'; return 0; fi
  if review_provenance_disabled_present; then printf 'full\n'; return 0; fi
  if ! review_provenance_principal_evidence_ok; then printf 'full\n'; return 0; fi
  printf 'skip\n'
}
# <<< review-provenance-shared <<<

latest_review_context() {
  find ".omx/review-context" -maxdepth 1 -type f -name 'latest-review-context.md' -print 2>/dev/null | head -1
}

diff_scope_field() {
  local field="$1"
  local context_file
  context_file="$(latest_review_context)"
  [ -n "${context_file}" ] && [ -f "${context_file}" ] || return 0
  awk -v field="- ${field}: " '
    /^## Diff Scope Summary$/ { in_scope=1; next }
    /^## / && in_scope { exit }
    in_scope && index($0, field) == 1 {
      sub(field, "", $0)
      print
      exit
    }
  ' "${context_file}"
}

review_gate_housekeeping() {
  local summary_status="$1"

  if [ "${OMX_AUTO_ARCHIVE:-1}" != "0" ] && [ -x "$AH/archive-omx-artifacts.sh" ]; then
    echo "[gate] archiving old review artifacts when retention thresholds are exceeded..."
    "$AH/archive-omx-artifacts.sh"
  fi

  if [ "${OMX_AUTO_CHECKPOINT:-1}" != "0" ] && [ -x "$AH/write-session-checkpoint.sh" ]; then
    echo "[gate] writing session checkpoint..."
    "$AH/write-session-checkpoint.sh"
  fi

  if [ "${OMX_AUTO_KNOWLEDGE_DRAFTS:-1}" != "0" ] && [ -x "$AH/capture-knowledge-drafts.py" ]; then
    echo "[gate] capturing local knowledge drafts..."
    if ! "$AH/capture-knowledge-drafts.py" --source review-gate --write; then
      echo "[gate] warning: knowledge draft capture failed; review gate result is unchanged"
    fi
  fi

  if [ "${summary_status}" -ne 0 ]; then
    exit "${summary_status}"
  fi
}

verify_only_diff_scope_ready() {
  local context_file policy scopes guard_status phase_status scope
  context_file="$(latest_review_context)"
  [ -n "${context_file}" ] && [ -f "${context_file}" ] || return 1

  policy="$(diff_scope_field "review gate policy")"
  [ "${policy}" = "verify_only" ] || return 1

  scopes="$(diff_scope_field "scopes")"
  [ -n "${scopes}" ] || return 1
  IFS=',' read -r -a scope_parts <<< "${scopes}"
  for scope in "${scope_parts[@]}"; do
    case "${scope}" in
      docs|plans) ;;
      *) return 1 ;;
    esac
  done

  guard_status="$(sed -n 's/^guard_status: //p' "${context_file}" | head -1)"
  case "${guard_status}" in
    ""|clear) ;;
    *) return 1 ;;
  esac

  phase_status="$(sed -n 's/^phase_scope_status: //p' "${context_file}" | head -1)"
  case "${phase_status}" in
    out_of_phase_edit|missing_deferral_record) return 1 ;;
  esac
}

write_verify_failed_blocked_verdict() {
  local verify_status="$1"
  local timestamp verdict_file
  timestamp="$(date +%Y%m%dT%H%M%S)"
  mkdir -p .omx/review-results
  verdict_file=".omx/review-results/review-verdict-${timestamp}.md"

  cat > "${verdict_file}" <<EOF
# AI Review Verdict

Generated at: $(date -Iseconds)

## Short Summary

- decision: blocked
- reason: verify_failed (ai-auto verify exit ${verify_status})
- coverage: none
- trust: blocked_or_needs_attention
- active_principal: ${ACTIVE_PRINCIPAL:-unknown}
- missing_or_unusable_reviewers: not_evaluated
- verify_override: none
- authority: blocked is not commit approval. Fix the failing ai-auto verify, or re-run with both AI_AUTO_VERIFY_OVERRIDE_REASON and AI_AUTO_VERIFY_OVERRIDE_APPROVED_BY to proceed degraded.

## Final Decision

blocked

## Decision Reason

ai-auto verify failed with exit ${verify_status}; the AI review panel was not run. See ${VERIFY_OUTPUT_FILE} for the failing output.

## Next Step

Fix the verification failure and re-run ai-auto gate. To proceed past a known-unrelated failure, re-run with BOTH AI_AUTO_VERIFY_OVERRIDE_REASON="..." and AI_AUTO_VERIFY_OVERRIDE_APPROVED_BY="..."; the result is recorded as proceed_degraded with a verify_override note, never a clean proceed.
EOF

  echo "[gate] blocked verdict written (verify failed, exit ${verify_status}): ${verdict_file}"
}

# Persistent disabled-reviewer staleness warning (warn-only). A transient disable
# (network/sandbox/usage) auto-recovers after a cooldown, so it is skipped here; this surfaces
# a NON-transient marker that has sat for more than N days and is silently keeping every gate
# degraded. The end-of-run trust report already flags degradation -- this front-loads it at
# gate start so a stuck reviewer does not quietly become the steady state. Never blocks.
warn_stale_disabled_reviewers() {
  local state_dir="${REVIEW_STATE_DIR:-.omx/reviewer-state}"
  local stale_days="${AI_AUTO_DISABLED_REVIEWER_STALE_DAYS:-7}"
  [ -d "${state_dir}" ] || return 0
  command -v date >/dev/null 2>&1 || return 0
  local now_s marker reviewer cls when when_s age_days hint
  now_s="$(date +%s)"
  for marker in "${state_dir}"/*.disabled; do
    [ -e "${marker}" ] || continue
    cls="$(sed -n 's/^disable_class=//p' "${marker}" | head -1)"
    [ "${cls}" = "transient" ] && continue   # auto-recovery (cooldown) owns transient disables
    when="$(sed -n 's/^disabled_at=//p' "${marker}" | head -1)"
    [ -n "${when}" ] || continue
    when_s="$(date -d "${when}" +%s 2>/dev/null || echo 0)"
    [ "${when_s}" -gt 0 ] || continue
    age_days=$(( (now_s - when_s) / 86400 ))
    [ "${age_days}" -lt "${stale_days}" ] && continue
    reviewer="$(basename "${marker}" .disabled)"
    hint="$(sed -n 's/^reset_hint=//p' "${marker}" | head -1)"
    echo ""
    echo "[gate] EXTERNAL REVIEW PERSISTENTLY DEGRADED: reviewer '${reviewer}' disabled ${age_days}d ago (> ${stale_days}d) and not auto-recovering;"
    echo "       gates keep passing as proceed_degraded with reduced trust."
    [ -n "${hint}" ] && echo "       re-enable: ${hint}"
  done
  return 0
}

write_verify_only_skip_verdict() {
  local timestamp verdict_file summary_file run_file scopes
  timestamp="$(date +%Y%m%dT%H%M%S)"
  mkdir -p .omx/review-results
  verdict_file=".omx/review-results/review-verdict-${timestamp}.md"
  summary_file=".omx/review-results/review-summary-${timestamp}.md"
  run_file=".omx/review-results/review-run-${timestamp}.md"
  scopes="$(diff_scope_field "scopes")"

  cat > "${verdict_file}" <<EOF
# AI Review Verdict

Generated at: $(date -Iseconds)

## Short Summary

- decision: proceed
- reason: verify_only_diff_scope
- coverage: external_review_skipped
- trust: normal
- active_principal: codex
- missing_or_unusable_reviewers: none
- authority: proceed is not commit approval unless normal verification and user commit approval are also satisfied.

## Final Decision

proceed

## Decision Reason

verify_only_diff_scope

## Review Coverage

external_review_skipped

## Diff Scope

${scopes}

## Reviewer Verdicts

review skipped: docs-only
EOF

  cat > "${summary_file}" <<EOF
# AI Review Summary

review skipped: docs-only

- decision: proceed
- reason: verify_only_diff_scope
- scopes: ${scopes}
EOF

  cat > "${run_file}" <<EOF
# Review Run

Review run id: ${timestamp}
Mode: verify_only_diff_scope
Review context: $(latest_review_context)
EOF

  echo "${verdict_file}"
}

write_provenance_skip_verdict() {
  local timestamp verdict_file summary_file run_file approved_at approved_head principal
  timestamp="$(date +%Y%m%dT%H%M%S)"
  mkdir -p .omx/review-results
  verdict_file=".omx/review-results/review-verdict-${timestamp}.md"
  summary_file=".omx/review-results/review-summary-${timestamp}.md"
  run_file=".omx/review-results/review-run-${timestamp}.md"
  approved_at="$(review_provenance_field approved_at)"
  approved_head="$(review_provenance_field approved_head)"
  # Report the actual active principal, not a hardcoded runtime — the skip carries the
  # prior approval's coverage, which the principal fingerprint (D.4) has confirmed.
  principal="$(review_provenance_principal)"
  principal="${principal:-codex}"

  cat > "${verdict_file}" <<EOF
# AI Review Verdict

Generated at: $(date -Iseconds)

## Short Summary

- decision: proceed
- reason: provenance_exact_match
- coverage: carried_forward_from_prior_approval
- trust: normal
- active_principal: ${principal}
- missing_or_unusable_reviewers: none
- authority: proceed is not commit approval unless normal verification and user commit approval are also satisfied.

## Final Decision

proceed

## Decision Reason

provenance_exact_match

## Review Coverage

carried_forward_from_prior_approval

## Prior Approval

- approved_at: ${approved_at:-unknown}
- approved_head: ${approved_head:-unknown}

## Reviewer Verdicts

review skipped: provenance exact-match (working tree byte-identical to a prior normal-trust approval)
EOF

  cat > "${summary_file}" <<EOF
# AI Review Summary

review skipped: provenance exact-match

- decision: proceed
- reason: provenance_exact_match
- approved_at: ${approved_at:-unknown}
EOF

  cat > "${run_file}" <<EOF
# Review Run

Review run id: ${timestamp}
Mode: provenance_exact_match
Review context: $(latest_review_context)
EOF

  echo "${verdict_file}"
}

print_diff_scope_gate() {
  local context_file
  context_file="$(latest_review_context)"
  [ -n "${context_file}" ] && [ -f "${context_file}" ] || return 0

  local scope_summary
  scope_summary="$(
    awk '
      /^## Diff Scope Summary$/ { in_scope=1; next }
      /^## / && in_scope { exit }
      in_scope && /^- / { print }
    ' "${context_file}"
  )"
  [ -n "${scope_summary}" ] || return 0

  echo "[gate] consuming diff scope summary..."
  printf '%s\n' "${scope_summary}" | sed 's/^/[gate] /'
}

if command -v session_lock_acquire >/dev/null 2>&1; then
  # The gate's own acquire happens BEFORE verify. A live sibling holding this tree returns
  # 75 (retryable contention) — surface it as a clear "deferred, use aiwt" and exit 75
  # WITHOUT recording a verdict, instead of the old opaque `exit 1` an operator misread as
  # a verification failure (then reached for --no-verify). Any other nonzero is propagated.
  _gate_lock_rc=0
  session_lock_acquire review-gate || _gate_lock_rc=$?   # `|| ` so set -e does not exit before capture
  if [ "${_gate_lock_rc}" -eq 75 ]; then
    echo "[gate] deferred (retryable): another live session holds this working tree. Re-run after it finishes, or use a separate worktree (aiwt). No verdict recorded — this is lock contention, not a verification failure." >&2
    exit 75
  elif [ "${_gate_lock_rc}" -ne 0 ]; then
    exit "${_gate_lock_rc}"
  fi
fi

# R4: a decision gate (PR / pre-merge, set by the agent) forces the full unanimous
# panel. It turns OFF every reduction so the decisive review is never a skipped,
# targeted, or narrowed pass — including the docs-only verify_only skip below, which is
# also bypassed under the decision gate so the contract is "full panel, no exceptions".
if [ "${REVIEW_DECISION_GATE:-0}" = "1" ]; then
  export REVIEW_CONTEXT_DETAIL="full"
  export REVIEW_PROVENANCE_SKIP="0"
  export REVIEW_INTEGRATION_ONLY="0"
  export REVIEW_TARGETED_RECHECK="0"
  echo "[gate] decision gate: full unanimous panel (provenance skip / targeted recheck / integration-only OFF, context=full)"
fi

warn_stale_disabled_reviewers

echo "[gate] running verification..."
set +e
env \
  -u RUN_CLAUDE_REVIEW \
  -u REVIEW_CONTEXT_DETAIL \
  -u REVIEW_INCLUDE_UNTRACKED_CONTENT \
  -u REVIEW_UNTRACKED_ALLOWLIST \
  -u REVIEW_UNTRACKED_MANUAL_REVIEWED \
  AI_AUTO_IN_REVIEW_GATE=1 \
  AI_AUTO_VERIFY_SCOPE=product \
  "$AH/verify.sh" 2>&1 | tee "$VERIFY_OUTPUT_FILE"
verify_status="${PIPESTATUS[0]}"
set -e

# #3: the product-scope verify above (and the pre-commit pytest hook) never run the
# machinery harness, so a regression in the automation scripts -- the P3
# write_disabled_result text-drift class -- slips past both the gate and the hook.
# When this change touches the automation scripts AND a machinery harness is present
# (the AI_AUTO source repo only: verify-machinery.sh is not installed into derived
# projects), run it too and fold its status into verify_status so a machinery
# failure takes the same recorded-blocked / override path as any other red verify.
if [ "${verify_status}" -eq 0 ] && [ -f scripts/verify-machinery.sh ] \
   && [ -f "$AH/verify-machinery.sh" ] \
   && [ "$(git rev-parse --show-toplevel 2>/dev/null)" -ef "$(dirname "$AH")" ]; then
  if { git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } \
       | grep -Eq '^(scripts/|hooks/)'; then
    echo "[gate] automation scripts changed; running machinery-scope verify..."
    set +e
    # Run the harness as a clean standalone: scrub the gate-context REVIEW_* vars
    # (the REVIEW_DECISION_GATE block exports REVIEW_TARGETED_RECHECK=0 etc.) so they
    # do NOT leak into verify-machinery's own env-sensitive review-gate sub-tests and
    # flip their expected behavior. (verify-in-gate-flakes-under-leaked-env.)
    env \
      -u REVIEW_DECISION_GATE \
      -u REVIEW_CONTEXT_DETAIL \
      -u REVIEW_PROVENANCE_SKIP \
      -u REVIEW_INTEGRATION_ONLY \
      -u REVIEW_TARGETED_RECHECK \
      -u REVIEW_INCLUDE_UNTRACKED_CONTENT \
      -u REVIEW_UNTRACKED_ALLOWLIST \
      -u REVIEW_UNTRACKED_MANUAL_REVIEWED \
      -u RUN_CLAUDE_REVIEW \
      -u AI_AUTO_IN_REVIEW_GATE \
      "$AH/verify-machinery.sh" 2>&1 | tee -a "$VERIFY_OUTPUT_FILE"
    machinery_status="${PIPESTATUS[0]}"
    set -e
    if [ "${machinery_status}" -ne 0 ]; then
      echo "[gate] machinery-scope verify FAILED (exit ${machinery_status})." >&2
      verify_status="${machinery_status}"
    fi
  fi
fi

# ST-P1-73(C): an INFRA precondition failure -- the gate's own working directory was
# removed out from under it (a concurrent session pruned this temp/shared worktree) --
# must NOT be recorded as a false `blocked` verify failure. getcwd() then fails and git
# emits "fatal: Unable to read current working directory", surfacing as a nonzero
# verify_status the red-signal branch below would turn into a blocked verdict (which an
# operator misreads as a code failure and reaches for --no-verify). We corroborate the
# condition DIRECTLY -- `pwd -P` runs getcwd(3), the same call git failed on -- rather
# than string-matching verify output, so a real verification failure that merely prints
# the phrase can never be mis-deferred. A genuinely-unreadable cwd is also one where we
# cannot reliably WRITE a verdict file, so deferring as retryable (exit 75, no verdict) is
# the only safe action, mirroring the lock-contention path. Distinct from the ST-P1-69
# decision not to special-case a 75 FROM verify (that is about lock 75s); this is the
# gate's own cwd being unreadable, detected independently of verify's exit meaning.
if [ "${verify_status}" -ne 0 ] && ! pwd -P >/dev/null 2>&1; then
  echo "[gate] deferred (retryable): this working tree was removed mid-run -- cwd is unreadable (getcwd failed). No verdict recorded -- this is an infrastructure failure, not a verification failure. Re-run from a stable worktree (aiwt)." >&2
  exit 75
fi

# Red-signal handling: a failed verify.sh must never silently turn into a proceed.
# (No special-casing of a 75 from verify here: under the gate, nested verify is re-entrant
# or shared-tree, so it never legitimately exits 75 from lock contention — any 75 reaching
# this point is a genuine tool failure and MUST block. Real contention is handled at the
# gate's own acquire above, before verify runs. Standalone verify exits 75 to its operator
# directly and never reaches this branch.)
# Default: record an explicit `blocked` verdict (not an opaque set -e crash that
# pushed operators to --no-verify). Override: proceed only when BOTH a recorded
# reason and a separate approver token are supplied; that path is loud, recorded,
# and forced to proceed_degraded by summarize-ai-reviews (never a clean proceed).
if [ "${verify_status}" -ne 0 ]; then
  verify_override_reason="${AI_AUTO_VERIFY_OVERRIDE_REASON:-}"
  verify_override_by="${AI_AUTO_VERIFY_OVERRIDE_APPROVED_BY:-}"
  if [ -z "${verify_override_reason}" ] || [ -z "${verify_override_by}" ]; then
    echo "[gate] verification FAILED (exit ${verify_status}); recording blocked verdict and stopping." >&2
    write_verify_failed_blocked_verdict "${verify_status}"
    review_gate_housekeeping 1
    echo "[gate] complete"
    exit 1
  fi
  echo "[gate] ===================================================================" >&2
  echo "[gate] WARNING: verify.sh FAILED (exit ${verify_status}) and is being OVERRIDDEN." >&2
  echo "[gate]   approved_by: ${verify_override_by}" >&2
  echo "[gate]   reason: ${verify_override_reason}" >&2
  echo "[gate]   The verdict will be recorded as proceed_degraded with a verify_override" >&2
  echo "[gate]   note. This is NOT a clean pass." >&2
  echo "[gate] ===================================================================" >&2
  export AI_AUTO_VERIFY_FAILED_OVERRIDE=1
  export AI_AUTO_VERIFY_FAILED_OVERRIDE_REASON="${verify_override_reason}"
  export AI_AUTO_VERIFY_FAILED_OVERRIDE_BY="${verify_override_by}"
  # Persist the override so it survives the REVIEW_EXECUTION_MODE=external path,
  # where the generated runner invokes summarize-ai-reviews.sh in a separate
  # process that does not inherit the exported env. A file keyed in .omx/state is
  # read by summarize as the override source of truth. Cleared at gate start so a
  # stale override can never apply to a later, unrelated run.
  mkdir -p .omx/state
  {
    printf 'reason=%s\n' "${verify_override_reason}"
    printf 'approved_by=%s\n' "${verify_override_by}"
  } > .omx/state/verify-override.env
fi

echo "[gate] collecting review context for diff-scope policy..."
"$AH/collect-review-context.sh"
print_diff_scope_gate

if [ "${REVIEW_DECISION_GATE:-0}" != "1" ] && [ "${AI_AUTO_VERIFY_FAILED_OVERRIDE:-0}" != "1" ] && verify_only_diff_scope_ready; then
  echo "[gate] review skipped: docs-only"
  write_verify_only_skip_verdict
  review_gate_housekeeping 0
  echo "[gate] complete"
  exit 0
fi

# R2: skip the AI panel when the working tree is byte-identical to a prior
# normal-trust approval (carries that verdict forward). Any change, flag mismatch
# (D.4), or disabled reviewer (D.9) fails open to a full review below. verify.sh has
# already run above, so this only skips the external AI panel, never verification.
# R3: an integration-only pass is mandatory — it must NOT be short-circuited by an
# exact-match skip, so the cross-task interaction review always runs.
if [ "${REVIEW_INTEGRATION_ONLY:-0}" != "1" ] \
   && [ "${AI_AUTO_VERIFY_FAILED_OVERRIDE:-0}" != "1" ] \
   && [ "${REVIEW_PROVENANCE_SKIP:-1}" = "1" ] \
   && [ "$(review_provenance_decision)" = "skip" ]; then
  echo "[gate] review skipped: provenance exact-match (carrying prior approval)"
  write_provenance_skip_verdict
  review_gate_housekeeping 0
  echo "[gate] complete"
  exit 0
fi

# R3: integration-only combine pass. When ≥2 already-approved task diffs are combined
# into one commit, the safe-but-expensive default is a full re-review (R2 fails open
# because the combined tree matches no single approval). This mode keeps that review
# mandatory but cheaper: a light, cross-task-interaction-focused context (the banner is
# emitted by collect-review-context.sh). The reviewer panel and trust logic are
# unchanged — only the context is narrowed.
if [ "${REVIEW_INTEGRATION_ONLY:-0}" = "1" ]; then
  export REVIEW_INTEGRATION_ONLY
  export REVIEW_CONTEXT_DETAIL="${REVIEW_CONTEXT_DETAIL:-light}"
  echo "[gate] integration-only pass: cross-task interaction review on light context (REVIEW_CONTEXT_DETAIL=${REVIEW_CONTEXT_DETAIL})"
fi

echo "[gate] running AI reviews..."
set +e
"$AH/run-ai-reviews.sh"
review_status=$?
set -e

if [ "${review_status}" -ne 0 ]; then
  if [ "${review_status}" -eq 2 ]; then
    echo "[gate] external AI review prepared; run the generated external reviewer command, then rerun ./scripts/summarize-ai-reviews.sh"
  fi
  exit "${review_status}"
fi

echo "[gate] summarizing AI review verdicts..."
summary_status=0
if ! "$AH/summarize-ai-reviews.sh"; then
  echo "[gate] review gate did not proceed"
  summary_status=1
fi

review_gate_housekeeping "${summary_status}"

echo "[gate] complete"
