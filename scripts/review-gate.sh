#!/usr/bin/env bash
set -euo pipefail

# Framework sibling scripts live next to this one. Resolve our own dir (following
# symlinks) so siblings are reachable from ANY cwd / PATH / temp-sandbox fixture.
AH="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# R7-F1 STANDALONE hardening: the gate is a documented standalone entrypoint. Under `ai-auto`
# the launcher sources git-scrub.sh, so the child run-ai-reviews.sh inherits the GIT_CONFIG_*
# `core.fsmonitor=` env pin; run STANDALONE there was NO pin, and run-ai-reviews.sh's
# worktree-scanning git calls (`git diff --name-only`, `git ls-files --others`) would EXECUTE
# an untrusted project's in-repo `core.fsmonitor` hook (RCE). Source the canonical scrub at
# startup — as tools/ai-auto does — so the pin (and hostile-GIT_* unset) covers this process AND
# every child it spawns (run-ai-reviews.sh, collect-review-context.sh, verify). git-harden.sh
# (review_git) is sourced below for the --attr-source call-site defense; this closes the
# fsmonitor CONFIG vector --attr-source cannot reach. hooks/ is a sibling of scripts/ and always
# present in the engine repo; source only when present AND parseable (ai-auto BLAST-H1 idiom) so
# `set -e` cannot abort the gate on a partial scripts/-only copy (a test harness copies scripts/
# without hooks/).
# shellcheck source=../hooks/git-scrub.sh
if [ -f "$AH/../hooks/git-scrub.sh" ] && bash -n "$AH/../hooks/git-scrub.sh" 2>/dev/null; then
  . "$AH/../hooks/git-scrub.sh"
fi

VERIFY_OUTPUT_FILE="${VERIFY_OUTPUT_FILE:-.omx/review-context/latest-verify-output.txt}"
mkdir -p "$(dirname "$VERIFY_OUTPUT_FILE")"
# Stable identity for THIS gate session (mirrors session-lock.sh: session.json id, else $$@host).
# The override marker is OWNED by this identity so a later gate can distinguish a genuinely-live
# same-session override from a dead one whose bare PID was recycled.
_gate_session_id() {
  local sid
  if [ -f .omx/state/session.json ]; then
    sid="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .omx/state/session.json | head -1)"
    [ -n "$sid" ] && { printf '%s' "$sid"; return; }
  fi
  printf '%s' "${AI_AUTO_SESSION_ID:-$$@$(hostname 2>/dev/null || echo host)}"
}

# Boot-unique start-time of a pid (/proc/<pid>/stat field 22), recorded in the override at acquire
# and re-checked in the stale-guard. `session.json`'s id is PER-TREE-CONSTANT, so holder_session
# alone is VACUOUS: every gate in the tree matches it and the guard collapses to `kill -0 + TTL` —
# the recyclable-PID class. Binding to start-time defeats PID recycling: a reused pid (same number,
# new process) has a different start-time -> STALE. Empty when the pid is dead/unreadable.
_pid_starttime() {
  local st
  st="$(cat /proc/"$1"/stat 2>/dev/null)" || return 1
  st="${st##*) }"           # strip 'pid (comm) ' — comm may hold spaces/parens; match to last ') '
  set -- $st                # now $1=state(field 3); starttime(field 22) is positional 20
  printf '%s' "${20:-}"
}

# Clear a STALE verify-failure override marker at gate start so an override can only ever apply
# to the run that explicitly sets it (written later, only on an approved verify failure) — but
# L1: do NOT clobber a CONCURRENT live session's approved override (summarize-ai-reviews.sh reads
# it as source of truth). Ownership is bound to a ROBUST identity (holder_session + acquired_at
# TTL + pid liveness), NOT a bare holder_pid: a bare PID is RECYCLABLE, so after the writing gate
# exits and its PID is reused by any unrelated process, `kill -0` still succeeds and the old guard
# PRESERVED the dead override — which then downgrades an unrelated clean run to proceed_degraded and
# MISATTRIBUTES the prior run's approved_by/reason onto it (audit-provenance corruption). PRESERVE
# ONLY a genuinely-live SAME-session override still within TTL (a real concurrent peer sharing this
# tree/session): matching holder_session AND holder_pid alive AND fresh acquired_at. A foreign/absent
# session, a recycled-but-unrelated PID, or a missing/expired acquired_at is STALE -> remove.
VERIFY_OVERRIDE_ENV="${VERIFY_OVERRIDE_ENV:-.omx/state/verify-override.env}"
if [ -f "$VERIFY_OVERRIDE_ENV" ]; then
  _ovr_pid="$(sed -n 's/^holder_pid=//p' "$VERIFY_OVERRIDE_ENV" 2>/dev/null | head -1)"
  _ovr_sess="$(sed -n 's/^holder_session=//p' "$VERIFY_OVERRIDE_ENV" 2>/dev/null | head -1)"
  _ovr_at="$(sed -n 's/^acquired_at=//p' "$VERIFY_OVERRIDE_ENV" 2>/dev/null | head -1)"
  _ovr_start="$(sed -n 's/^holder_starttime=//p' "$VERIFY_OVERRIDE_ENV" 2>/dev/null | head -1)"
  _ovr_ttl="${AI_AUTO_VERIFY_OVERRIDE_TTL_SECONDS:-14400}"
  case "$_ovr_ttl" in ''|*[!0-9]*) _ovr_ttl=14400 ;; esac
  _ovr_grace="${AI_AUTO_CLOCK_SKEW_GRACE_SECONDS:-300}"
  case "$_ovr_grace" in ''|*[!0-9]*) _ovr_grace=300 ;; esac
  # _ovr_age default of -(grace+1) keeps a marker with a MISSING/unparseable acquired_at STALE
  # (below the skew floor), so absent-timestamp markers are never preserved.
  _ovr_age=$(( -_ovr_grace - 1 ))
  if [ -n "$_ovr_at" ]; then
    _ovr_ts="$(date -d "$_ovr_at" +%s 2>/dev/null || echo '')"
    [ -n "$_ovr_ts" ] && _ovr_age=$(( $(date +%s) - _ovr_ts ))
  fi
  # Preserve ONLY a genuinely-live holder: matching session AND live pid AND its RECORDED start-time
  # still equals the pid's CURRENT start-time (recycled pid -> mismatch -> STALE) AND fresh acquired_at.
  # holder_starttime is required: a marker lacking it (legacy / forged / recycled) can never be honored.
  # RESERVED-PID guard: holder_pid MUST be a real user process (> 1). A planted holder_pid=1 (init) is
  # ALWAYS kill-0-alive and pid 1's start-time is stable/queryable, so with a fresh acquired_at + matching
  # session it would sail through every check and PRESERVE a forged override -> its attacker approved_by/
  # reason downgrades + corrupts a clean run. `-gt 1` also rejects 0 and negatives, whose kill -0 has
  # process-GROUP / broadcast semantics that spuriously succeed. Non-numeric -> arithmetic fails closed.
  # Age gate carries the SAME backward-clock-step grace as the session lock: a live SAME-session peer
  # whose acquired_at goes slightly negative under an NTP/WSL/VM backstep (-GRACE..0) is still FRESH,
  # so its live override is NOT rm'd (which would launder a failed-verify run to clean proceed); only
  # age > TTL (stale) or age < -GRACE (implausibly future/forged) drops it.
  if [ -n "$_ovr_sess" ] && [ "$_ovr_sess" = "$(_gate_session_id)" ] \
     && [ -n "$_ovr_pid" ] && { [ "$_ovr_pid" -gt 1 ] 2>/dev/null; } && kill -0 "$_ovr_pid" 2>/dev/null \
     && [ -n "$_ovr_start" ] && [ "$_ovr_start" = "$(_pid_starttime "$_ovr_pid")" ] \
     && [ "$_ovr_age" -ge $(( -_ovr_grace )) ] && [ "$_ovr_age" -le "$_ovr_ttl" ]; then
    : # a genuinely-live SAME-session peer (unrecycled pid) owns this override within TTL -> preserve it
  else
    rm -f "$VERIFY_OVERRIDE_ENV"
  fi
  unset _ovr_pid _ovr_sess _ovr_at _ovr_start _ovr_ttl _ovr_grace _ovr_age
  unset _ovr_ts 2>/dev/null || true
fi

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

# R5-1/R6: review_git (the hardened-git wrapper) is single-sourced in scripts/git-harden.sh
# and sourced here so review-gate.sh, summarize-ai-reviews.sh, and collect-review-context.sh
# share ONE implementation — no patch-producing call can drift un-hardened. It stays inert to a
# PROJECT-LOCAL `.gitattributes` + `.git/config` diff/filter driver (git's code-exec surface that
# env scrubbing CANNOT reach because it lives IN the repo); callers pass --no-ext-diff/--no-textconv
# on every patch-producing diff and --no-filters on hash-object. Tests that source this block
# standalone set AI_AUTO_GIT_HARDEN_SH to point at scripts/git-harden.sh.
# shellcheck source=scripts/git-harden.sh
. "${AI_AUTO_GIT_HARDEN_SH:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/git-harden.sh}"

# Working-tree-inclusive provenance hash: HEAD commit + staged + unstaged + untracked
# content. Corrects DR1 (a committed-tree SHA would false-skip unstaged edits). Never
# uses `git write-tree`, which would mutate the index.
review_provenance_hash() {
  {
    review_git rev-parse HEAD 2>/dev/null || printf 'NO_HEAD\n'
    printf '\037diff\037\n';   review_git diff --no-ext-diff --no-textconv 2>/dev/null
    printf '\037cached\037\n'; review_git diff --cached --no-ext-diff --no-textconv 2>/dev/null
    printf '\037untracked\037\n'
    # Include each untracked file's PATH next to its blob hash so a same-content
    # rename / path swap changes the hash (content-only would false-match). A nested
    # untracked git repo / worktree lists as ONE boundary DIRECTORY (gitlink): hash-object
    # cannot hash a directory, so its mutating inner content is INVISIBLE and the hash
    # would false-match a prior clean approval. FAIL CLOSED: any other-entry that is a
    # directory or that hash-object cannot hash emits a UNIQUE, un-matchable per-call nonce
    # so a tree carrying such an entry can NEVER carry forward a skip on unreviewed content.
    review_git ls-files --others --exclude-standard -z 2>/dev/null \
      | while IFS= read -r -d '' provenance_file; do
          printf '%s\t' "${provenance_file}"
          if [ -d "${provenance_file}" ] \
             || ! provenance_blob="$(review_git hash-object --no-filters "${provenance_file}" 2>/dev/null)" \
             || [ -z "${provenance_blob}" ]; then
            printf '\037UNHASHABLE\037%s.%s\n' "${RANDOM}${RANDOM}" "$(date +%s%N 2>/dev/null || printf '%s' "${RANDOM}")"
          else
            printf '%s\n' "${provenance_blob}"
          fi
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

# --- Provenance-record AUTHENTICITY (out-of-tree HMAC key) --------------------------------
# The whole project tree (incl. .omx/reviewer-state) is attacker-controlled under the
# tarball/copy threat model, so a record's authenticity CANNOT rest on anything stored in it:
# an attacker precomputes a matching approved_hash and forges every field. Authenticity is
# bound to an HMAC keyed by a secret held OUTSIDE any project tree. Path precedence:
# $AI_AUTO_PROVENANCE_KEY_FILE (tests) -> $AI_AUTO_HOME/.provenance-key -> ~/.config/ai-auto/
# provenance.key. An in-tree path (.omx/.git) is REFUSED, so the secret is never written where
# the attacker-controlled tree can read it, and an attacker who owns the tree cannot forge it.
review_provenance_key_file() {
  if [ -n "${AI_AUTO_PROVENANCE_KEY_FILE:-}" ]; then printf '%s\n' "${AI_AUTO_PROVENANCE_KEY_FILE}"
  elif [ -n "${AI_AUTO_HOME:-}" ]; then printf '%s/.provenance-key\n' "${AI_AUTO_HOME}"
  else printf '%s/.config/ai-auto/provenance.key\n' "${HOME:-/root}"; fi
}

review_provenance_abs_path() {
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m -- "${path}" 2>/dev/null && return 0
  fi
  AI_AUTO_ABS_PATH="${path}" python3 - <<'PY' 2>/dev/null
import os
print(os.path.realpath(os.environ["AI_AUTO_ABS_PATH"]))
PY
}

# Refuse an in-tree key path via realpath+toplevel (NOT a fragile substring). Returns 0
# (=in-tree, REFUSE) when the candidate key path — after resolving relative paths, `..`, and
# symlinks — lands INSIDE the project's git toplevel, where the attacker-controlled tree could
# read/forge the secret; callers then fail closed (treat as missing key => full review). A
# substring guard (*"/.omx/"*|*"/.git/"*) missed a RELATIVE path (.omx/x.key, no leading slash),
# a `..` escape, and any in-tree path OUTSIDE .omx/.git, so the stated "in-tree key is REFUSED"
# invariant was FALSE. Out-of-tree keys ($AI_AUTO_HOME/.provenance-key, ~/.config/ai-auto, an
# out-of-tree $AI_AUTO_PROVENANCE_KEY_FILE) resolve OUTSIDE the toplevel => return 1 (allowed).
# git is routed through hardened review_git (drift-guard: no bare git).
review_provenance_key_in_tree() {
  local keyfile top rp
  keyfile="$(review_provenance_key_file)"
  top="$(review_git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "${top}" ] || return 1
  top="$(review_provenance_abs_path "${top}")" || return 0
  rp="$(review_provenance_abs_path "${keyfile}")" || return 0
  case "${rp}/" in "${top}/"*) return 0 ;; esac
  return 1
}

# Generate the key once (0600) if absent-OR-EMPTY. Refuses any in-tree path (realpath inside
# toplevel). CRITICAL fail-open fix: `> "${keyfile}"` truncates the target to 0 bytes BEFORE
# openssl execs, so a missing/failing openssl (minimal container, PATH gap, transient) left a
# persistent 0-byte key that later `[ -f ]` checks accepted as valid => HMAC keyed by NO secret
# => an attacker who owns the tree could forge a valid approved_hmac. Fix: presence test is now
# `[ -s ]` (empty key == absent), and the secret is written to a SAME-DIR mktemp and mv'd into
# place ONLY after confirming it is non-empty, so a 0-byte key is never published at keyfile.
review_provenance_ensure_key() {
  local keyfile dir tmp
  keyfile="$(review_provenance_key_file)"
  review_provenance_key_in_tree && return 1
  [ -s "${keyfile}" ] && return 0
  dir="$(dirname "${keyfile}")"
  mkdir -p "${dir}" 2>/dev/null || return 1
  tmp="$(mktemp "${dir}/.provkey.XXXXXX" 2>/dev/null)" || return 1
  if ( umask 077; openssl rand -hex 32 > "${tmp}" ) 2>/dev/null && [ -s "${tmp}" ]; then
    chmod 0600 "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${keyfile}" 2>/dev/null && return 0
  fi
  rm -f "${tmp}" 2>/dev/null
  return 1
}

# HMAC-SHA256 of stdin keyed by the out-of-tree secret (key read from FILE, never argv/env, so
# it is not exposed on the process table). Empty output when the key/tool is unavailable or the
# path is in-tree -> the caller fails closed (no valid HMAC => full review), never a silent skip.
# Read-side hardening: an EMPTY key (`[ -s ]`), a key not owned by us (`[ -O ]`), or a
# group/other-accessible key (mode & 077) is UNTRUSTED (planted/leaked) -> empty output.
review_provenance_hmac() {
  local keyfile mode
  keyfile="$(review_provenance_key_file)"
  review_provenance_key_in_tree && return 0
  [ -s "${keyfile}" ] || return 0
  [ -O "${keyfile}" ] || return 0
  mode="$(stat -c '%a' "${keyfile}" 2>/dev/null || echo 777)"
  [ $(( 0${mode} & 077 )) -eq 0 ] || return 0
  AI_AUTO_PROV_KEYFILE="${keyfile}" python3 -c 'import hmac,hashlib,os,sys; k=open(os.environ["AI_AUTO_PROV_KEYFILE"],"rb").read(); sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())' 2>/dev/null
}

# Record an approved provenance record. Atomic (mktemp+mv) so a concurrent session
# never reads a half-written env. Caller gates on proceed + normal trust.
review_provenance_record() {
  local hash head flags ts tmp rec
  hash="$(review_provenance_hash)"
  head="$(review_provenance_head)"
  flags="$(review_provenance_flags)"
  ts="$(date -Iseconds)"
  # `|| return 0`: if no out-of-tree key can be ensured (in-tree path refused, or key creation
  # failed) do NOT write a record — any record we could write would carry an empty/invalid HMAC
  # and force a full review anyway, and a bare call would abort this proceed under `set -e`.
  review_provenance_ensure_key || return 0
  mkdir -p "${REVIEW_STATE_DIR}"
  tmp="$(mktemp "${REVIEW_STATE_DIR}/.approved-provenance.XXXXXX")" || return 0
  # Trap-clean the random-suffixed temp so a SIGINT/SIGTERM/timeout (the gate is exactly what
  # gets Ctrl-C'd/timed-out) in the mktemp..mv window strands NO litter in .omx/reviewer-state
  # (the suffix is NOT pid-bounded, so it would accumulate unboundedly). RETURN covers every
  # function-exit path; INT/TERM clean then honor the signal (exit) so a real interrupt is not
  # masked. All cleared after the atomic mv (temp path is gone -> the rm becomes a harmless no-op).
  trap 'rm -f "${tmp:-}"' RETURN
  trap 'rm -f "${tmp:-}"; exit 130' INT
  trap 'rm -f "${tmp:-}"; exit 143' TERM
  # Canonical record + an HMAC over it keyed by the OUT-OF-TREE secret. The attacker owns the
  # tree and can forge every field incl. a matching approved_hash, but NOT this HMAC, so a
  # forged approved-provenance.env cannot pass review_provenance_authentic (=> full review).
  rec="$(printf 'marker_type=review_provenance\napproved_hash=%s\napproved_head=%s\napproved_flags=%s\napproved_at=%s\n' \
    "${hash}" "${head}" "${flags}" "${ts}")"
  {
    printf '%s\n' "${rec}"
    printf 'approved_hmac=%s\n' "$(printf '%s' "${rec}" | review_provenance_hmac)"
  } > "${tmp}"
  mv -f "${tmp}" "${REVIEW_PROVENANCE_ENV}"
  trap - RETURN INT TERM
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
  local workspace ev declared explicit _pe_stored _pe_expected
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
    # Out-of-tree-keyed HMAC: a planted evidence lacking a framework-written evidence_hmac is a
    # forgery -> a provenance skip must not ride it (fail open to full, as an absent file would).
    _pe_stored="$(sed -n 's/^evidence_hmac=//p' "${ev}" | head -1)"
    _pe_expected="$(printf 'marker_type=principal_evidence\nprincipal_runtime=%s\nexecution_mode=principal\nsource=ai-auto-principal-launcher\nworkspace=%s\n' "${declared}" "${workspace}" | review_provenance_hmac)"
    [ -n "${_pe_stored}" ] && [ -n "${_pe_expected}" ] && [ "${_pe_stored}" = "${_pe_expected}" ] || return 1
    return 0
  fi
  # No evidence: a non-codex explicit principal would make run-ai-reviews fail, so a
  # skip in that state would bypass the failure.
  case "${explicit}" in ""|codex) return 0 ;; *) return 1 ;; esac
}

# Verify a record's out-of-tree-keyed HMAC. Returns 0 ONLY when a key exists and the stored
# approved_hmac equals a fresh HMAC over the record's canonical fields; else 1 (missing key,
# missing/forged HMAC, tool absent, in-tree key path) -> caller forces a full review. An
# attacker who owns the tree cannot produce a valid HMAC without the out-of-tree key.
review_provenance_authentic() {
  local keyfile stored rec expected
  keyfile="$(review_provenance_key_file)"
  review_provenance_key_in_tree && return 1
  [ -s "${keyfile}" ] || return 1
  stored="$(review_provenance_field approved_hmac)"
  [ -n "${stored}" ] || return 1
  rec="$(printf 'marker_type=review_provenance\napproved_hash=%s\napproved_head=%s\napproved_flags=%s\napproved_at=%s\n' \
    "$(review_provenance_field approved_hash)" \
    "$(review_provenance_field approved_head)" \
    "$(review_provenance_field approved_flags)" \
    "$(review_provenance_field approved_at)")"
  expected="$(printf '%s' "${rec}" | review_provenance_hmac)"
  [ -n "${expected}" ] || return 1
  [ "${expected}" = "${stored}" ]
}

# Echoes "skip" (exact match, same flags, no disabled reviewer → carry prior verdict)
# or "full" (no record / forged-or-unauthenticated record / changed tree / flag mismatch /
# disabled present). Delta is deferred until collect-review-context honors a base, so every
# non-exact case is a full review.
review_provenance_decision() {
  local approved_hash approved_flags cur_hash cur_flags
  approved_hash="$(review_provenance_field approved_hash)"
  if [ -z "${approved_hash}" ]; then printf 'full\n'; return 0; fi
  # Authenticity FIRST: a record without a valid out-of-tree-keyed HMAC is forged / legacy —
  # force a full review (never carry it forward onto an unreviewed, attacker-controlled tree).
  if ! review_provenance_authentic; then printf 'full\n'; return 0; fi
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

# SPEC-AUD-1: bind an allowed review-gate verdict to the reviewed change so the
# pre-push hook can enforce that the current push has a real proceed/proceed_degraded
# result, not a self-claim or stale verdict. Kept outside the shared provenance block
# so review-gate.sh and summarize-ai-reviews.sh remain byte-identical there.
# shellcheck source=scripts/review-gate-binding.sh
. "${AH}/review-gate-binding.sh"

verify_override_approval_evidence_ok() {
  local approved_by="$1" workspace ev declared _pe_stored _pe_expected
  [ -n "${approved_by}" ] || return 1
  workspace="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
  ev="${AI_AUTO_PRINCIPAL_EVIDENCE:-${workspace}/.omx/state/principal-runtime/current.env}"
  [ -f "${ev}" ] || return 1
  [ ! -L "${ev}" ] || return 1
  grep -Fqx "execution_mode=principal" "${ev}" || return 1
  grep -Fqx "source=ai-auto-principal-launcher" "${ev}" || return 1
  grep -Fqx "workspace=${workspace}" "${ev}" || return 1
  declared="$(sed -n 's/^principal_runtime=//p' "${ev}" | head -1)"
  case "${declared}" in codex|claude|gemini) ;; *) return 1 ;; esac
  [ "${approved_by}" = "${declared}" ] || return 1
  _pe_stored="$(sed -n 's/^evidence_hmac=//p' "${ev}" | head -1)"
  _pe_expected="$(printf 'marker_type=principal_evidence\nprincipal_runtime=%s\nexecution_mode=principal\nsource=ai-auto-principal-launcher\nworkspace=%s\n' "${declared}" "${workspace}" | review_provenance_hmac)"
  [ -n "${_pe_stored}" ] && [ -n "${_pe_expected}" ] && [ "${_pe_stored}" = "${_pe_expected}" ]
}

# >>> blue-r17-provenance-failclosed >>>
# HIGH fail-closed override of the shared review_provenance_hash. The shared implementation
# reads the working tree through the REAL .git/index and SWALLOWS git errors (2>/dev/null). A
# truncated/corrupt index -- the R13 exit-128 condition, realistic under WSL2/9p multi-session
# load -- makes its `git diff` / `git ls-files` calls go FATAL (empirically exit 128), the diff
# sections empty, and the hash COLLAPSES to the constant a clean checkout hashes to. A dirty
# (malicious) tree then hashes identical to a prior clean approval => review_provenance_decision
# returns `skip` => the gate emits proceed / carried_forward on a tree the AI panel NEVER saw.
# This lives OUTSIDE the shared block so the block stays byte-identical with summarize-ai-reviews.sh
# (the provenance_block_identical invariant) and the recorded-vs-decided hash stay value-identical
# on a HEALTHY tree (the skip optimization is preserved): the override probes the exact index reads
# the shared hash depends on and, only when they all succeed, delegates to the UNCHANGED shared
# algorithm. On ANY nonzero git rc (index corruption OR a sandbox where every git call panics
# >=100) it emits NOTHING, so the decision cannot match a prior approval and forces a full
# re-review -- never a carried-forward skip on an unverified tree.
eval "$(declare -f review_provenance_hash | sed '1s/^review_provenance_hash /_review_provenance_hash_shared /')"
review_provenance_hash() {
  local rc
  review_git diff --cached --quiet --no-ext-diff --no-textconv >/dev/null 2>&1; rc=$?
  case "${rc}" in 0|1) ;; *) return 1 ;; esac   # 0=no staged, 1=staged; anything else = git fatal
  review_git diff --quiet --no-ext-diff --no-textconv >/dev/null 2>&1; rc=$?
  case "${rc}" in 0|1) ;; *) return 1 ;; esac   # 0=no unstaged, 1=unstaged; else = fatal
  review_git ls-files --others --exclude-standard >/dev/null 2>&1 || return 1
  _review_provenance_hash_shared
}
# <<< blue-r17-provenance-failclosed <<<

# >>> blue-r18-provenance-blindbits >>>
# MED fail-closed override: `git update-index --assume-unchanged` / `--skip-worktree` on a TRACKED
# file makes git BLIND to a later (malicious) edit — `diff` / `ls-files` omit it, so the provenance
# hash COLLAPSES to the prior clean value and review_provenance_decision returns `skip` on UNREVIEWED
# content. The R17 override targets a corrupt INDEX; here the index is perfectly VALID, just flagged,
# so it does not catch this. `git ls-files -v` tags such a file with a LOWERCASE letter
# (assume-unchanged, e.g. `h`) or `S` (skip-worktree); if ANY tracked file carries such a bit the
# hash cannot be trusted, so emit NOTHING (empty output != any prior approval => FULL review, never a
# carried-forward skip). Routed through review_git (drift-guard: no bare `git`). A HEALTHY tree with
# no such bits delegates to the unchanged algorithm, preserving the R2 exact-match skip optimization.
# Lives OUTSIDE the shared block so it stays byte-identical with summarize-ai-reviews.sh; layers on
# top of the R17 override (chain: blindbits -> failclosed -> shared).
eval "$(declare -f review_provenance_hash | sed '1s/^review_provenance_hash /_review_provenance_hash_preblind /')"
review_provenance_hash() {
  if review_git ls-files -v 2>/dev/null | grep -Eq '^([[:lower:]]|S) '; then
    return 1
  fi
  _review_provenance_hash_preblind
}
# <<< blue-r18-provenance-blindbits <<<

# Broken-sandbox vs missing-repo diagnostic (HIGH). Distinguish "git ABSENT" from "git PRESENT
# but every call FATAL" (the codex >=0.142.4 panic exits 101; a corrupt env exits >=128). The
# provenance/root probes swallow git stderr (2>/dev/null) and silently mis-root to $PWD, so a
# broken sandbox looks like the agent ignoring guidelines. Surface it LOUDLY at gate start; never
# blocks (fail-closed provenance + verify already handle the coverage).
# >>> blue-r18-broken-sandbox >>>
# LOW FIX: `git rev-parse --is-inside-work-tree` exits 128 for BOTH a corrupt/broken sandbox AND a
# plain NON-git dir, so the old unconditional message fired the PANIC branch ("do NOT git init") on
# a LEGIT non-repo — actively-wrong advice. Only a repo that ACTUALLY EXISTS but whose git ops fail
# is the broken-sandbox class: rev-parse having FAILED, a `.git` still present in cwd (a FILESYSTEM
# check — git itself is what is failing — at the gate's invocation root, where `.git` lives) means
# it is corrupt/unusable OR git is broken. A plain non-repo (no `.git`) gets normal non-repo handling
# (silent): erring toward silence is the safe side (the diagnostic never blocks; provenance still
# fails closed), and it avoids a stray ancestor `.git` false-firing an unbounded upward walk.
warn_broken_git_sandbox() {
  command -v git >/dev/null 2>&1 || return 0     # git genuinely absent: not this class
  local rc=0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || rc=$?
  [ "${rc}" -eq 0 ] && return 0                   # git healthy
  [ -e ".git" ] || return 0                        # plain non-repo: normal handling, NOT the panic
  echo "" >&2
  echo "[gate] GIT PRESENT BUT FAILING (git rev-parse exited ${rc}): your sandbox/environment is broken, NOT a missing repo." >&2
  [ "${rc}" -ge 100 ] && echo "[gate]   exit >=100 is a tool/sandbox PANIC (e.g. codex >=0.142.4 with a socket in writable_roots). Fix the sandbox; do NOT 'git init'." >&2
  echo "[gate]   The gate cannot trust git-derived paths here; provenance fails closed to a full review and paths may mis-root to \$PWD." >&2
  return 0
}
# <<< blue-r18-broken-sandbox <<<

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

diff_scope_changed_paths() {
  local encoded
  encoded="$(diff_scope_field "changed paths b64")"
  [ -n "${encoded}" ] || return 0
  printf '%s' "${encoded}" | base64 -d 2>/dev/null || return 1
}

machinery_scope_requires_verify() {
  local unstaged_rc="$1" unstaged="$2" staged_rc="$3" staged="$4" context_paths="$5"
  [ "${unstaged_rc}" -ne 0 ] && return 0
  [ "${staged_rc}" -ne 0 ] && return 0
  printf '%s\n%s\n' "${unstaged}" "${staged}" | grep -Eq '^(scripts/|hooks/)' && return 0
  printf '%s\n' "${context_paths}" | grep -Eq '^(scripts/|hooks/)' && return 0
  return 1
}

if [ "${1:-}" = "--test-machinery-scope" ]; then
  shift
  [ "${AI_AUTO_REVIEW_GATE_TEST_MACHINERY_SCOPE:-0}" = "1" ] || {
    echo "test seam disabled" >&2
    exit 64
  }
  if machinery_scope_requires_verify \
    "${AI_AUTO_TEST_MACHINERY_UNSTAGED_RC:-0}" \
    "${AI_AUTO_TEST_MACHINERY_UNSTAGED:-}" \
    "${AI_AUTO_TEST_MACHINERY_STAGED_RC:-0}" \
    "${AI_AUTO_TEST_MACHINERY_STAGED:-}" \
    "${AI_AUTO_TEST_MACHINERY_CONTEXT_PATHS:-}"; then
    echo "machinery_scope"
  else
    echo "product_scope"
  fi
  exit 0
fi

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
- active_principal: $(review_provenance_principal)
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
    # Clock-skew guard: a FUTURE disabled_at makes age_days negative, which is < stale_days and
    # would silently SUPPRESS this persistent-degraded warning. A future marker is itself
    # suspicious (skew / tampering) and still means a non-transient disabled reviewer, so surface
    # it instead of hiding it.
    if [ "${when_s}" -gt "${now_s}" ]; then
      reviewer="$(basename "${marker}" .disabled)"
      echo ""
      echo "[gate] EXTERNAL REVIEW PERSISTENTLY DEGRADED: reviewer '${reviewer}' has a FUTURE disabled_at (${when}) -- clock skew or tampering; not auto-recovering. Investigate and re-enable."
      continue
    fi
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
  local timestamp verdict_file summary_file run_file scopes changed_paths
  timestamp="$(date +%Y%m%dT%H%M%S)"
  mkdir -p .omx/review-results
  verdict_file=".omx/review-results/review-verdict-${timestamp}.md"
  summary_file=".omx/review-results/review-summary-${timestamp}.md"
  run_file=".omx/review-results/review-run-${timestamp}.md"
  scopes="$(diff_scope_field "scopes")"
  changed_paths="$(diff_scope_changed_paths || true)"

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

## Verify Scope

policy: $(diff_scope_field "review gate policy")
scopes: ${scopes}
changed paths:
$(printf '%s\n' "${changed_paths:-none}" | sed 's/^/- /')

## Reviewer Verdicts

review skipped: docs-only
EOF

  cat > "${summary_file}" <<EOF
# AI Review Summary

review skipped: docs-only

- decision: proceed
- reason: verify_only_diff_scope
- scopes: ${scopes}
- verify_scope_changed_paths: $(printf '%s\n' "${changed_paths:-none}" | paste -sd ';' -)
EOF

  cat > "${run_file}" <<EOF
# Review Run

Review run id: ${timestamp}
Mode: verify_only_diff_scope
Review context: $(latest_review_context)
Verify scopes: ${scopes}
Verify changed paths: $(printf '%s\n' "${changed_paths:-none}" | paste -sd ';' -)
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

changed_checksheet_files() {
  {
    review_git diff --name-only 2>/dev/null || true
    git diff --cached --name-only 2>/dev/null || true
    git ls-files --others --exclude-standard 2>/dev/null || true
  } | sort -u | while IFS= read -r file; do
    case "${file}" in
      *.checksheet.json|*.registry.json|checksheets/*.json)
        printf '%s\n' "${file}"
        ;;
    esac
  done
}

run_changed_checksheet_gate() {
  local file rc found=0 failed=0
  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    found=1
    if [ ! -f "${file}" ]; then
      echo "[gate] checksheet artifact changed but missing: ${file}" >&2
      failed=1
      continue
    fi
    echo "[gate] running checksheet artifact: ${file}"
    rc=0
    case "${file}" in
      *.registry.json) "$AH/checksheet-run.sh" --regression-registry "${file}" || rc=$? ;;
      *) "$AH/checksheet-run.sh" "${file}" || rc=$? ;;
    esac
    if [ "${rc}" -ne 0 ]; then
      echo "[gate] checksheet artifact FAILED (${file}, exit ${rc})" >&2
      failed=1
    fi
  done < <(changed_checksheet_files)

  [ "${found}" -eq 1 ] || return 0
  [ "${failed}" -eq 0 ] || return 1
  echo "[gate] checksheet artifacts passed"
}

# FIX-M3: run_changed_checksheet_gate only runs the closed-defect registry when a
# registry FILE appears in the diff. A merge that reopens a closed defect in a
# NON-registry file would then skip the registry entirely, defeating the
# "any regression = BLOCK" contract. Re-assert every in-repo closed-defect
# registry on EVERY gate run, unconditionally, regardless of what the diff touched.
# Fast/scoped: the registry runner is deterministic and only replays the recorded
# guards. (When a registry file ALSO changed, run_changed_checksheet_gate has
# already blocked above, so this path runs only when the diff left registries
# untouched — the exact case the changed-file gate misses.)
run_registry_reassertion() {
  local reg rc found=0 failed=0
  for reg in checksheets/*.registry.json; do
    [ -f "${reg}" ] || continue
    found=1
    echo "[gate] re-asserting closed-defect registry (unconditional): ${reg}"
    rc=0
    "$AH/checksheet-run.sh" --regression-registry "${reg}" || rc=$?
    if [ "${rc}" -ne 0 ]; then
      echo "[gate] closed-defect registry re-assertion FAILED (${reg}, exit ${rc})" >&2
      failed=1
    fi
  done
  [ "${found}" -eq 1 ] || return 0
  [ "${failed}" -eq 0 ] || return 1
  echo "[gate] closed-defect registry re-assertion passed"
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

accepted_finding_files() {
  local findings_file="${REVIEW_ACCEPTED_FINDINGS_FILE:-}"
  [ -n "${findings_file}" ] || return 0
  [ -f "${findings_file}" ] || return 0
  awk -F'|' '$1 == "accepted" && $4 != "" { print $4 }' "${findings_file}" | sort -u
}

current_changed_files_for_targeted_recheck() {
  {
    review_git diff --name-only 2>/dev/null || true
    git diff --cached --name-only 2>/dev/null || true
    git ls-files --others --exclude-standard 2>/dev/null || true
  } | sort -u
}

prepare_targeted_recheck_scope() {
  local targeted="${REVIEW_TARGETED_RECHECK:-1}"
  local cycle_count="${REVIEW_REVISION_CYCLE_COUNT:-1}"
  local accepted changed out_of_scope

  unset REVIEW_TARGETED_RECHECK_FILES

  [ "${REVIEW_DECISION_GATE:-0}" != "1" ] || return 0
  [ "${targeted}" = "1" ] || return 0
  [ -f "${REVIEW_ACCEPTED_FINDINGS_FILE:-}" ] || return 0
  case "${cycle_count}" in
    1|2) ;;
    *) return 0 ;;
  esac

  accepted="$(accepted_finding_files)"
  [ -n "${accepted}" ] || return 0
  changed="$(current_changed_files_for_targeted_recheck)"
  [ -n "${changed}" ] || return 0

  out_of_scope="$(
    awk 'NR == FNR { if ($0 != "") accepted[$0] = 1; next } $0 != "" && !($0 in accepted)' \
      <(printf '%s\n' "${accepted}") \
      <(printf '%s\n' "${changed}")
  )"
  if [ -n "${out_of_scope}" ]; then
    export REVIEW_TARGETED_RECHECK_SCOPE_OK=0
    echo "[gate] targeted recheck scope expanded; falling back to full review target"
    return 0
  fi

  export REVIEW_TARGETED_RECHECK_SCOPE_OK=1
  export REVIEW_TARGETED_RECHECK_FILES="${accepted}"
  echo "[gate] targeted recheck scope: accepted finding file set"
}

warn_broken_git_sandbox
warn_stale_disabled_reviewers
prepare_targeted_recheck_scope

echo "[gate] collecting review context for diff-scope policy..."
"$AH/collect-review-context.sh"
print_diff_scope_gate

echo "[gate] running verification..."
verify_scope_scopes="$(diff_scope_field "scopes")"
verify_scope_policy="$(diff_scope_field "review gate policy")"
verify_scope_changed_paths="$(diff_scope_changed_paths || true)"
if [ -n "${verify_scope_scopes}" ] || [ -n "${verify_scope_changed_paths}" ]; then
  echo "[gate] passing diff scope to verify: scopes=${verify_scope_scopes:-unknown}"
fi
set +e
env \
  -u RUN_CLAUDE_REVIEW \
  -u REVIEW_CONTEXT_DETAIL \
  -u REVIEW_INCLUDE_UNTRACKED_CONTENT \
  -u REVIEW_UNTRACKED_ALLOWLIST \
  -u REVIEW_UNTRACKED_MANUAL_REVIEWED \
  AI_AUTO_IN_REVIEW_GATE=1 \
  AI_AUTO_VERIFY_SCOPE=product \
  AI_AUTO_VERIFY_DIFF_SCOPE=1 \
  AI_AUTO_VERIFY_SCOPES="${verify_scope_scopes}" \
  AI_AUTO_VERIFY_SCOPE_POLICY="${verify_scope_policy}" \
  AI_AUTO_VERIFY_CHANGED_PATHS="${verify_scope_changed_paths}" \
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
  # F3: route BOTH the unstaged and STAGED diffs through the hardened review_git (the staged side
  # was a bare, un-hardened `git`), and capture each rc. A swallowed git error used to drop the
  # staged list and MISS a machinery-scope change; fail-closed instead — EITHER git error => treat
  # as in-scope and run the machinery self-test. (rc captured via `|| rc=$?` so set -e does not abort.)
  machinery_scope_unstaged_rc=0
  machinery_scope_unstaged="$(review_git diff --name-only 2>/dev/null)" || machinery_scope_unstaged_rc=$?
  machinery_scope_staged_rc=0
  machinery_scope_staged="$(review_git diff --cached --name-only 2>/dev/null)" || machinery_scope_staged_rc=$?
  # Comes from collect-review-context's Diff Scope Summary; in a clean post-commit
  # review it names the latest commit's paths, not this gate script's own files.
  machinery_scope_context_paths="${verify_scope_changed_paths}"
  if machinery_scope_requires_verify \
    "${machinery_scope_unstaged_rc}" \
    "${machinery_scope_unstaged}" \
    "${machinery_scope_staged_rc}" \
    "${machinery_scope_staged}" \
    "${machinery_scope_context_paths}"; then
    echo "[gate] automation scripts changed; running machinery-scope verify..."
    # OPCOST-HIGH-1: this ~6min self-test also runs in the VERY NEXT commit's pre-commit
    # hook over an IDENTICAL surface, so it ran TWICE per change->commit cycle. Memoize:
    # skip the re-run when a PASS marker for the exact tested-surface hash already exists
    # (scripts/machinery-memo.sh). Any change to the surface misses the marker -> full run.
    # BLAST-H1 pattern: source the (engine-internal) helper only if present AND parseable.
    if [ -f "$AH/machinery-memo.sh" ] && bash -n "$AH/machinery-memo.sh" 2>/dev/null; then
      # shellcheck source=scripts/machinery-memo.sh
      . "$AH/machinery-memo.sh"
    fi
    if command -v machinery_memo_should_skip >/dev/null 2>&1 && machinery_memo_should_skip; then
      machinery_memo_skip_notice | tee -a "$VERIFY_OUTPUT_FILE"
      machinery_status=0
    else
      # H1 (time-of-record false-skip): capture the surface hash that is about to be TESTED,
      # BEFORE verify runs, and record THAT exact hash on PASS — never a fresh re-hash of the live
      # tree ~6min later (a concurrent session could have mutated it during the verify window).
      machinery_tested_hash=""
      if command -v machinery_memo_surface_hash >/dev/null 2>&1; then
        machinery_tested_hash="$(machinery_memo_surface_hash)"
      fi
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
      # Record the PASS so the imminent pre-commit machinery-fold can skip the twin run —
      # keyed to the TESTED surface (H1), not a fresh re-hash (record_pass declines if the live
      # tree drifted during verify).
      if [ "${machinery_status}" -eq 0 ] && command -v machinery_memo_record_pass >/dev/null 2>&1; then
        machinery_memo_record_pass "${machinery_tested_hash}"
      fi
    fi
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
  if ! verify_override_approval_evidence_ok "${verify_override_by}"; then
    echo "[gate] verification FAILED (exit ${verify_status}); override approval rejected because no matching launcher-owned approval evidence exists for '${verify_override_by}'." >&2
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
  # Ownership tag bound to a ROBUST identity (session id + holder start-time + timestamp), not a
  # recyclable bare PID, so a later gate distinguishes a genuinely-live same-session override from a
  # dead one whose PID was reused (which must NOT downgrade+misattribute an unrelated clean run).
  # Consumed by the gate-start stale-guard above; summarize-ai-reviews.sh still reads only reason/approved_by.
  # Written via same-dir mktemp+mv (like review_provenance_record) so a concurrent reader/stale-guard
  # sees the OLD-complete or NEW-complete file, never a truncated one (no lost proceed_degraded marker).
  _ovr_dst="${VERIFY_OVERRIDE_ENV:-.omx/state/verify-override.env}"
  _ovr_tmp="$(mktemp "$(dirname "$_ovr_dst")/.verify-override.XXXXXX")"
  {
    printf 'reason=%s\n' "${verify_override_reason}"
    printf 'approved_by=%s\n' "${verify_override_by}"
    printf 'holder_pid=%s\n' "$$"
    printf 'holder_session=%s\n' "$(_gate_session_id)"
    printf 'holder_starttime=%s\n' "$(_pid_starttime "$$")"
    printf 'acquired_at=%s\n' "$(date -Iseconds)"
  } > "$_ovr_tmp"
  mv -f "$_ovr_tmp" "$_ovr_dst"
  unset _ovr_dst _ovr_tmp
fi

if ! run_changed_checksheet_gate; then
  echo "[gate] checksheet gate failed; stopping before external review." >&2
  review_gate_housekeeping 1
  echo "[gate] complete"
  exit 1
fi

# FIX-M3: unconditional closed-defect registry re-assertion (runs even when the diff
# touched no registry file), so a reopened defect in a non-registry file is caught.
if ! run_registry_reassertion; then
  echo "[gate] closed-defect registry re-assertion failed; stopping before external review." >&2
  review_gate_housekeeping 1
  echo "[gate] complete"
  exit 1
fi

if [ "${REVIEW_DECISION_GATE:-0}" != "1" ] && [ "${AI_AUTO_VERIFY_FAILED_OVERRIDE:-0}" != "1" ] && verify_only_diff_scope_ready; then
  echo "[gate] review skipped: docs-only"
  verify_only_verdict="$(write_verify_only_skip_verdict)"
  review_binding_record "proceed" "normal" "${verify_only_verdict}"
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
  provenance_verdict="$(write_provenance_skip_verdict)"
  review_binding_record "proceed" "normal" "${provenance_verdict}"
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

# R20 (CRITICAL): bind this gate run's verdict to a fresh, purged results dir.
# (1) A copy/tarball tree can carry a hostile .omx/review-results/ holding `approve`
# result files + a redirecting summary stamped at a FUTURE mtime; the old mtime-based
# discovery in summarize-ai-reviews.sh would select that planted set over the real
# reviewers and mint a genuine `proceed`. So PURGE every foreign/stale entry (keep only
# the archive/ subdir) before the panel runs. (2) Export a unique REVIEW_RUN_ID so
# run-ai-reviews.sh names its summary review-summary-<run-id>.md and summarize consumes
# THAT exact file by run id (never by mtime). A planted file for any other/unknown run
# id is neither retained by the purge nor selectable by run id.
REVIEW_RESULTS_DIR="${OUT_DIR:-.omx/review-results}"
if [ -d "${REVIEW_RESULTS_DIR}" ]; then
  find "${REVIEW_RESULTS_DIR}" -mindepth 1 -maxdepth 1 ! -name 'archive' -exec rm -rf {} + 2>/dev/null || true
fi
REVIEW_RUN_ID="gate-$$-$(date +%s)-${RANDOM}"
export REVIEW_RUN_ID

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

if [ "${summary_status}" -eq 0 ]; then
  latest_verdict="$(review_binding_latest_verdict)"
  latest_decision="$(review_binding_verdict_decision "${latest_verdict}")"
  latest_trust=""
  if [ -n "${latest_verdict}" ] && [ -f "${latest_verdict}" ]; then
    latest_trust="$(sed -n 's/^- trust: //p' "${latest_verdict}" 2>/dev/null | head -1)"
  fi
  review_binding_record "${latest_decision}" "${latest_trust:-unknown}" "${latest_verdict}"
fi

review_gate_housekeeping "${summary_status}"

echo "[gate] complete"
