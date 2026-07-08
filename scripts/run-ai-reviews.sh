#!/usr/bin/env bash
set -euo pipefail

# Empty-tree OID (repo hash algo; sha1 constant fallback) for `git --attr-source=<empty-tree>`:
# the worktree `git diff --name-only` listings embedded in the reviewer prompts below run against
# the (untrusted) project worktree, where an in-repo `.gitattributes` clean filter would otherwise
# execute. `--attr-source` reads attributes from the empty tree, disarming that driver.
# R7-F1: under the review-gate / ai-auto entrypoints the process already carries the git-scrub.sh
# `core.fsmonitor=` env pin, so these worktree scans cannot run an in-repo `core.fsmonitor` hook.
# The inline `-c core.fsmonitor=` below is DEFENSE-IN-DEPTH so the same scans stay RCE-safe even if
# run-ai-reviews.sh is ever invoked directly (outside the gate) with an un-scrubbed env.
REVIEW_ATTR_NONE="$(git hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"

OUT_DIR="${OUT_DIR:-.omx/review-results}"
CONTEXT_DIR="${CONTEXT_DIR:-.omx/review-context}"
PROMPT_DIR="${PROMPT_DIR:-.omx/review-prompts}"
EXTERNAL_REVIEW_DIR="${EXTERNAL_REVIEW_DIR:-.omx/external-review}"
REVIEW_STATE_DIR="${REVIEW_STATE_DIR:-.omx/reviewer-state}"
REVIEW_EXECUTION_MODE="${REVIEW_EXECUTION_MODE:-local}"
REVIEW_TIMEOUT_SECONDS="${REVIEW_TIMEOUT_SECONDS:-180}"
REVIEW_TIMEOUT_KILL_AFTER_SECONDS="${REVIEW_TIMEOUT_KILL_AFTER_SECONDS:-5}"
CLAUDE_REVIEW_TIMEOUT_SECONDS="${CLAUDE_REVIEW_TIMEOUT_SECONDS:-300}"
GEMINI_REVIEW_TIMEOUT_SECONDS="${GEMINI_REVIEW_TIMEOUT_SECONDS:-${REVIEW_TIMEOUT_SECONDS}}"
GEMINI_REVIEW_COMMAND="${GEMINI_REVIEW_COMMAND:-agy}"
CODEX_FALLBACK_REVIEW_TIMEOUT_SECONDS="${CODEX_FALLBACK_REVIEW_TIMEOUT_SECONDS:-300}"
CLAUDE_PROMPT_ARG_MAX_BYTES="${CLAUDE_PROMPT_ARG_MAX_BYTES:-100000}"
GEMINI_PROMPT_ARG_MAX_BYTES="${GEMINI_PROMPT_ARG_MAX_BYTES:-100000}"
GEMINI_PROMPT_MAX_BYTES="${GEMINI_PROMPT_MAX_BYTES:-300000}"
REVIEW_CONTEXT_MAX_BYTES="${REVIEW_CONTEXT_MAX_BYTES:-100000}"
REVIEW_CONTEXT_DETAIL="${REVIEW_CONTEXT_DETAIL:-auto}"
REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES="${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES:-50000}"
REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES="${REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES:-80}"
REVIEW_RETRY_LIMIT="${REVIEW_RETRY_LIMIT:-3}"
# Transient reviewer disables (usage_limit / network_or_sandbox / connection
# failures) auto-recover after this cooldown so a flaky external lane self-heals
# instead of staying disabled until a manual RESET_DISABLED_AI_REVIEWERS (which
# left Codex self-substitution as the de-facto reviewer). 0 disables auto-recovery.
REVIEW_REVIEWER_DISABLE_COOLDOWN_SECONDS="${REVIEW_REVIEWER_DISABLE_COOLDOWN_SECONDS:-1800}"
# Heartbeat cadence for the multi-minute reviewer phase so the gate does not
# "look hung" (ST-P1-63). 0 disables the periodic heartbeat.
REVIEW_HEARTBEAT_SECONDS="${REVIEW_HEARTBEAT_SECONDS:-30}"

reviewer_disabled_file() {
  echo "${REVIEW_STATE_DIR}/$1.disabled"
}

# >>> principal-evidence-auth: out-of-tree HMAC key (keep identical in ai-principal-runtime.sh + run-ai-reviews.sh) >>>
# The principal-runtime evidence file is gitignored and therefore PLANTABLE by an untrusted
# project. Presence + literal-line greps alone let a plant forge the active principal (dropping a
# required reviewer / laundering proceed_degraded->proceed). We bind the evidence to an HMAC keyed
# by a secret held OUTSIDE any project tree, mirroring the review-gate provenance key discipline
# (same key precedence + [-s]/[-O]/mode + in-tree refusal). The launcher writes the HMAC because it
# holds the key; a project plant cannot. Readers recompute the HMAC over the canonical trust fields
# and REJECT any mismatch, failing closed to the codex default -- exactly as an ABSENT file behaves.
principal_evidence_key_file() {
  if [ -n "${AI_AUTO_PROVENANCE_KEY_FILE:-}" ]; then printf '%s\n' "${AI_AUTO_PROVENANCE_KEY_FILE}"
  elif [ -n "${AI_AUTO_HOME:-}" ]; then printf '%s/.provenance-key\n' "${AI_AUTO_HOME}"
  else printf '%s/.config/ai-auto/provenance.key\n' "${HOME:-/root}"; fi
}
principal_evidence_abs_path() {
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m -- "${path}" 2>/dev/null && return 0
  fi
  AI_AUTO_ABS_PATH="${path}" python3 - <<'PY' 2>/dev/null
import os
print(os.path.realpath(os.environ["AI_AUTO_ABS_PATH"]))
PY
}
# Refuse an in-tree key path (attacker-readable) via realpath+toplevel; return 0 == in-tree == REFUSE.
# Resolution failure (realpath -m and the python3 fallback both fail) also REFUSES (fail closed):
# treating an unresolvable key path as "not in tree" would let a plant escape the trust boundary.
principal_evidence_key_in_tree() {
  local kf top rp
  kf="$(principal_evidence_key_file)"
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "${top}" ] || return 1
  top="$(principal_evidence_abs_path "${top}")" || return 0
  rp="$(principal_evidence_abs_path "${kf}")" || return 0
  case "${rp}/" in "${top}/"*) return 0 ;; esac
  return 1
}
# HMAC-SHA256 of stdin keyed by the out-of-tree secret; empty output when the key is
# absent/empty/not-owned/group-or-other-accessible/in-tree/tool-missing -> caller fails closed.
principal_evidence_hmac() {
  local kf mode
  kf="$(principal_evidence_key_file)"
  principal_evidence_key_in_tree && return 0
  [ -s "${kf}" ] || return 0
  [ -O "${kf}" ] || return 0
  mode="$(stat -c '%a' "${kf}" 2>/dev/null || echo 777)"
  [ $(( 0${mode} & 077 )) -eq 0 ] || return 0
  AI_AUTO_PEV_KEYFILE="${kf}" python3 -c 'import hmac,hashlib,os,sys; k=open(os.environ["AI_AUTO_PEV_KEYFILE"],"rb").read(); sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())' 2>/dev/null
}
# Canonical trust record the evidence_hmac covers (args: principal workspace). Always PIPED
# directly into the hmac (never via $()) so writer and readers hash byte-identical input.
principal_evidence_canonical() {
  printf 'marker_type=principal_evidence\nprincipal_runtime=%s\nexecution_mode=principal\nsource=ai-auto-principal-launcher\nworkspace=%s\n' "$1" "$2"
}
# 0 iff <file> carries a framework-written evidence_hmac matching canonical(<principal>,<workspace>).
principal_evidence_hmac_ok() {
  local stored expected
  stored="$(sed -n 's/^evidence_hmac=//p' "$1" | head -n 1)"
  [ -n "${stored}" ] || return 1
  expected="$(principal_evidence_canonical "$2" "$3" | principal_evidence_hmac)"
  [ -n "${expected}" ] || return 1
  [ "${expected}" = "${stored}" ]
}
# Ensure a non-empty out-of-tree key exists (writers only). Refuses in-tree paths; publishes the
# secret only after confirming it is non-empty (same-dir mktemp+mv) so a 0-byte key is never left.
principal_evidence_ensure_key() {
  local kf dir tmp
  kf="$(principal_evidence_key_file)"
  principal_evidence_key_in_tree && return 1
  [ -s "${kf}" ] && return 0
  dir="$(dirname "${kf}")"
  mkdir -p "${dir}" 2>/dev/null || return 1
  tmp="$(mktemp "${dir}/.pevkey.XXXXXX" 2>/dev/null)" || return 1
  if ( umask 077; openssl rand -hex 32 > "${tmp}" ) 2>/dev/null && [ -s "${tmp}" ]; then
    chmod 0600 "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${kf}" 2>/dev/null && return 0
  fi
  rm -f "${tmp}" 2>/dev/null
  return 1
}
# <<< principal-evidence-auth <<<

# A reviewer .disabled marker (REVIEW_STATE_DIR/*.disabled) is ALSO gitignored/plantable: a project
# shipping claude.disabled+gemini.disabled degrades the panel to codex-only. It is authoritative
# ONLY if it carries a framework-written marker_hmac over its canonical fields keyed by the same
# out-of-tree secret. A planted/unauthenticated marker is IGNORED (the reviewer runs); disable_reviewer
# writes the HMAC so genuine runtime disables still work.
# Canonical SIGNED message ($1=reviewer identity to BIND, $2=marker file). The reviewer identity
# and live repo are bound via the ARG + live git-toplevel (NOT the file body), plus a domain-tag
# line, so a marker signed for one reviewer/repo cannot be replayed as another: a cp'd
# claude.disabled verified as gemini reconstructs reviewer=gemini and fails the HMAC, and a
# cross-repo copy reconstructs a different workspace= and fails. Domain tag keeps it non-collidable
# with the other 3 marker types under the shared key.
reviewer_marker_canonical() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
  printf 'marker_type=reviewer_disabled\nreviewer=%s\nworkspace=%s\n' "$1" "${top}"
  grep -E '^(reviewer|disabled_at|reason|details|disable_class|source_run_id|chronic_count)=' "$2" 2>/dev/null
}
reviewer_disabled_authentic() {
  local f stored expected
  f="$(reviewer_disabled_file "$1")"
  [ -f "${f}" ] || return 1
  stored="$(sed -n 's/^marker_hmac=//p' "${f}" | head -n 1)"
  [ -n "${stored}" ] || return 1
  expected="$(reviewer_marker_canonical "$1" "${f}" | principal_evidence_hmac)"
  [ -n "${expected}" ] || return 1
  [ "${expected}" = "${stored}" ]
}

# Auto-recover transient reviewer disables once their cooldown has elapsed, so a
# usage-limit / network blip does not keep an external reviewer (Claude/Gemini)
# disabled until a manual reset. Persistent or unclassified disables are left for
# explicit RESET_DISABLED_AI_REVIEWERS.
expire_transient_disabled_reviewers() {
  local cooldown="${REVIEW_REVIEWER_DISABLE_COOLDOWN_SECONDS:-0}"
  [ "${cooldown}" -gt 0 ] 2>/dev/null || return 0
  local grace="${AI_AUTO_CLOCK_SKEW_GRACE_SECONDS:-300}"
  case "${grace}" in ''|*[!0-9]*) grace=300 ;; esac
  local reviewer disabled_file disable_class disabled_at disabled_epoch now age
  now="$(date +%s)"
  for reviewer in claude gemini; do
    disabled_file="$(reviewer_disabled_file "${reviewer}")"
    [ -f "${disabled_file}" ] || continue
    disable_class="$(sed -n 's/^disable_class=//p' "${disabled_file}" 2>/dev/null | head -n 1)"
    [ "${disable_class}" = "transient" ] || continue
    disabled_at="$(sed -n 's/^disabled_at=//p' "${disabled_file}" 2>/dev/null | head -n 1)"
    disabled_epoch="$(date -d "${disabled_at}" +%s 2>/dev/null || echo 0)"
    [ "${disabled_epoch}" -gt 0 ] 2>/dev/null || continue   # unparseable -> keep disabled (fail-closed)
    age=$(( now - disabled_epoch ))
    # disabled_at is wall-clock: a backward step / future timestamp makes age NEGATIVE, and a bare
    # `age>=cooldown` would then NEVER fire -> the reviewer stays suppressed indefinitely (an
    # under-strength panel). Skew-normalize: a small backstep (-grace..0) is treated as "just
    # disabled" (age=0, cooldown counts fresh from now, still eventually elapses); an implausibly
    # future disabled_at (age < -grace, forged/large skew) is re-enabled NOW (fail toward full panel).
    if [ "${age}" -lt 0 ]; then
      if [ "${age}" -lt $(( -grace )) ]; then age="${cooldown}"; else age=0; fi
    fi
    if [ "${age}" -ge "${cooldown}" ]; then
      rm -f "${disabled_file}"
      echo "[review] ${reviewer} review auto re-enabled after ${age}s (transient disable cooldown expired)"
    fi
  done
}

review_changed_files_for_prompt() {
  if [ -n "$(printf '%s' "${REVIEW_TARGETED_RECHECK_FILES:-}" | tr -d '[:space:]')" ]; then
    printf '%s\n' "${REVIEW_TARGETED_RECHECK_FILES}" | sed '/^[[:space:]]*$/d'
    return 0
  fi
  git -c core.fsmonitor= --attr-source="${REVIEW_ATTR_NONE}" diff --name-only 2>/dev/null || true
  git -c core.fsmonitor= diff --cached --name-only 2>/dev/null || true
  git -c core.fsmonitor= ls-files --others --exclude-standard 2>/dev/null || true
}

# Fast path for tests/ops: expire stale transient disables, then exit before any
# context collection or reviewer execution.
if [ "${AI_REVIEWS_EXPIRE_ONLY:-0}" = "1" ]; then
  expire_transient_disabled_reviewers
  exit 0
fi
REVIEW_OUTPUT_MODE="${REVIEW_OUTPUT_MODE:-file}"
SKIP_CONTEXT_GENERATION="${SKIP_CONTEXT_GENERATION:-0}"
REVIEW_INCLUDE_UNTRACKED_CONTENT="${REVIEW_INCLUDE_UNTRACKED_CONTENT:-0}"
AI_MODEL_DISCOVERY="${AI_MODEL_DISCOVERY:-1}"
AI_MODEL_DISCOVERY_DIR="${AI_MODEL_DISCOVERY_DIR:-.omx/model-routing}"
AI_MODEL_ROUTING_ENV="${AI_MODEL_ROUTING_ENV:-${AI_MODEL_DISCOVERY_DIR}/latest.env}"
AI_MODEL_ROUTING_REPORT="${AI_MODEL_ROUTING_REPORT:-${AI_MODEL_DISCOVERY_DIR}/latest.md}"

# The model-routing env (${AI_MODEL_ROUTING_ENV}) lives IN-TREE and is therefore
# attacker-controllable. It is DATA, never code: we MUST NOT `source` it (that was
# an RCE — an injected `X=$(payload)` line executed on the default local review
# path, before any reviewer ran). parse_model_routing_env reads ONLY the
# whitelisted routing keys below, as literal single-quoted values; it never
# evaluates the file. If ANY non-blank/comment line is not a plain KEY='value'
# assignment the whole file is rejected (fail closed -> provider defaults), so a
# hostile/malformed env can neither inject shell nor silently force a wrong model.
AI_MODEL_ROUTING_ALLOWED_KEYS="AI_MODEL_ROUTING_DISCOVERED_AT AI_MODEL_ROUTING_DISCOVERED_EPOCH AI_MODEL_ROUTING_REPORT AI_MODEL_ROUTING_OBSERVATIONS AI_MODEL_ROUTING_CACHE_STATUS AI_MODEL_ROUTING_CACHE_AGE_SECONDS AI_MODEL_ROUTING_CACHE_TTL_SECONDS CLAUDE_REVIEW_ROLE CLAUDE_REVIEW_MODEL GEMINI_REVIEW_ROLE GEMINI_REVIEW_MODEL GEMINI_REVIEW_COMMAND CODEX_ARCHITECT_REVIEW_ROLE CODEX_ARCHITECT_REVIEW_MODEL CODEX_TEST_REVIEW_ROLE CODEX_TEST_REVIEW_MODEL"

parse_model_routing_env() {
  local file="$1" line key value
  [ -f "${file}" ] || return 1

  # Fail closed: reject the whole file if any non-blank/comment line is not a
  # literal, single-quoted KEY='value' assignment. `INJECTED=$(cmd)` is not
  # single-quoted, so a poisoned cache-hit body is refused instead of trusted.
  if grep -vE "^[[:space:]]*(#.*)?$" "${file}" \
     | grep -qvE "^[A-Za-z_][A-Za-z0-9_]*='[^']*'\$"; then
    return 1
  fi

  while IFS= read -r line; do
    case "${line}" in
      [A-Za-z_]*=\'*\') ;;
      *) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=\'}"
    value="${value%\'}"
    case " ${AI_MODEL_ROUTING_ALLOWED_KEYS} " in
      *" ${key} "*)
        # Assign the literal string; no command substitution / eval ever runs.
        printf -v "${key}" '%s' "${value}"
        export "${key?}"
        ;;
    esac
  done < "${file}"
}

# Data-only reader exposed as a subcommand so the security boundary above is
# testable in isolation (verify-machinery) without driving a full review run.
if [ "${1:-}" = "--parse-model-routing-env" ]; then
  parse_model_routing_env "${2:-${AI_MODEL_ROUTING_ENV}}" || exit 1
  for _routing_key in ${AI_MODEL_ROUTING_ALLOWED_KEYS}; do
    printf '%s=%s\n' "${_routing_key}" "${!_routing_key-}"
  done
  exit 0
fi

RUN_AI_REVIEWS_SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ADAPTER_SCRIPT="${RUNTIME_ADAPTER_SCRIPT:-${RUN_AI_REVIEWS_SCRIPT_DIR}/ai-runtime-adapter.sh}"
PRINCIPAL_RUNTIME_SCRIPT="${PRINCIPAL_RUNTIME_SCRIPT:-${RUN_AI_REVIEWS_SCRIPT_DIR}/ai-principal-runtime.sh}"
: "${RUNTIME_ADAPTER_AGY_COMMAND:=${GEMINI_REVIEW_COMMAND}}"
export RUNTIME_ADAPTER_AGY_COMMAND

mkdir -p "${OUT_DIR}" "${CONTEXT_DIR}" "${PROMPT_DIR}" "${EXTERNAL_REVIEW_DIR}" "${REVIEW_STATE_DIR}" "${AI_MODEL_DISCOVERY_DIR}"

normalize_principal_runtime() {
  if [ -x "${PRINCIPAL_RUNTIME_SCRIPT}" ]; then
    "${PRINCIPAL_RUNTIME_SCRIPT}" normalize "${AI_AUTO_PRINCIPAL:-codex}"
    return $?
  fi

  case "${AI_AUTO_PRINCIPAL:-codex}" in
    ""|codex) echo "codex" ;;
    claude) echo "claude" ;;
    gemini|agy) echo "gemini" ;;
    *)
      echo "unsupported principal runtime: ${AI_AUTO_PRINCIPAL}" >&2
      return 2
      ;;
  esac
}

principal_repo_root() {
  # Anchor evidence lookup and workspace comparison to the repo root so the
  # script behaves the same whether invoked from the root or a subdirectory.
  git rev-parse --show-toplevel 2>/dev/null || pwd -P
}

read_valid_launcher_principal() {
  # Echo the launcher-declared principal_runtime only when the evidence file is a
  # valid, launcher-owned, workspace-matched, non-symlink principal record;
  # otherwise echo nothing. This lets a recorded principal drive selection so a
  # non-codex session is not silently coerced to codex.
  local workspace declared evidence_file
  workspace="$(principal_repo_root)"
  evidence_file="${AI_AUTO_PRINCIPAL_EVIDENCE:-${workspace}/.omx/state/principal-runtime/current.env}"
  [ -f "${evidence_file}" ] || return 0
  [ ! -L "${evidence_file}" ] || return 0
  grep -Fqx "execution_mode=principal" "${evidence_file}" || return 0
  grep -Fqx "source=ai-auto-principal-launcher" "${evidence_file}" || return 0
  grep -Fqx "workspace=${workspace}" "${evidence_file}" || return 0
  declared="$(sed -n 's/^principal_runtime=//p' "${evidence_file}" | head -n 1)"
  case "${declared}" in codex|claude|gemini) ;; *) return 0 ;; esac
  # Authenticate with the out-of-tree HMAC key: a planted evidence lacking a framework-written
  # evidence_hmac is untrusted -> echo nothing, so a plant cannot drive selection to a forged
  # principal (fail closed to the codex default, exactly as an absent file).
  principal_evidence_hmac_ok "${evidence_file}" "${declared}" "${workspace}" || return 0
  printf '%s\n' "${declared}"
}

EXPLICIT_PRINCIPAL="${AI_AUTO_PRINCIPAL:-}"
EVIDENCE_PRINCIPAL="$(read_valid_launcher_principal)"

if [ -n "${EXPLICIT_PRINCIPAL}" ]; then
  if ! ACTIVE_PRINCIPAL="$(normalize_principal_runtime)"; then
    echo "[review] failed to normalize active principal runtime" >&2
    exit 2
  fi
  # An explicit selection must not contradict a valid launcher declaration.
  if [ -n "${EVIDENCE_PRINCIPAL}" ] && [ "${EVIDENCE_PRINCIPAL}" != "${ACTIVE_PRINCIPAL}" ]; then
    echo "[review] principal_unavailable: AI_AUTO_PRINCIPAL=${ACTIVE_PRINCIPAL} contradicts launcher evidence principal_runtime=${EVIDENCE_PRINCIPAL}" >&2
    exit 2
  fi
elif [ -n "${EVIDENCE_PRINCIPAL}" ]; then
  # No explicit selection: a valid launcher declaration drives selection so the
  # executing runtime is not misrouted into its own reviewer slot.
  ACTIVE_PRINCIPAL="${EVIDENCE_PRINCIPAL}"
  echo "[review] active principal ${ACTIVE_PRINCIPAL} selected from launcher evidence"
else
  # Nothing declared: default to codex, but say so out loud instead of silently.
  ACTIVE_PRINCIPAL="codex"
  echo "[review] active principal defaulted to codex; set AI_AUTO_PRINCIPAL=claude|gemini or record launcher evidence if this session is not codex"
fi

case "${ACTIVE_PRINCIPAL}" in
  codex|claude|gemini) ;;
  *)
    echo "[review] unsupported active principal: ${ACTIVE_PRINCIPAL}" >&2
    exit 2
    ;;
esac

principal_reviewers() {
  case "${ACTIVE_PRINCIPAL}" in
    codex)
      printf '%s\n' claude gemini
      ;;
    claude)
      printf '%s\n' gemini codex
      ;;
    gemini)
      printf '%s\n' claude codex
      ;;
  esac
}

principal_evidence_valid() {
  local evidence_file workspace
  workspace="$(principal_repo_root)"
  evidence_file="${AI_AUTO_PRINCIPAL_EVIDENCE:-${workspace}/.omx/state/principal-runtime/current.env}"

  if [ "${ACTIVE_PRINCIPAL}" = "codex" ]; then
    return 0
  fi

  if [ ! -f "${evidence_file}" ]; then
    echo "[review] principal_unavailable: ${ACTIVE_PRINCIPAL} principal evidence file is missing: ${evidence_file}" >&2
    return 1
  fi

  if [ -L "${evidence_file}" ]; then
    echo "[review] principal_unavailable: ${ACTIVE_PRINCIPAL} principal evidence file must not be a symlink: ${evidence_file}" >&2
    return 1
  fi

  if ! grep -Fqx "principal_runtime=${ACTIVE_PRINCIPAL}" "${evidence_file}"; then
    echo "[review] principal_unavailable: evidence file does not match active principal ${ACTIVE_PRINCIPAL}: ${evidence_file}" >&2
    return 1
  fi

  if ! grep -Fqx "execution_mode=principal" "${evidence_file}"; then
    echo "[review] principal_unavailable: evidence file does not declare execution_mode=principal: ${evidence_file}" >&2
    return 1
  fi

  if ! grep -Fqx "source=ai-auto-principal-launcher" "${evidence_file}"; then
    echo "[review] principal_unavailable: evidence file is not launcher-owned: ${evidence_file}" >&2
    return 1
  fi

  if ! grep -Fqx "workspace=${workspace}" "${evidence_file}"; then
    echo "[review] principal_unavailable: evidence file does not match workspace ${workspace}: ${evidence_file}" >&2
    return 1
  fi

  # Out-of-tree-keyed HMAC: a planted evidence lacking a framework-written evidence_hmac is a
  # forgery -> fail closed (a non-codex principal cannot ride an unauthenticated evidence file).
  if ! principal_evidence_hmac_ok "${evidence_file}" "${ACTIVE_PRINCIPAL}" "${workspace}"; then
    echo "[review] principal_unavailable: ${ACTIVE_PRINCIPAL} principal evidence HMAC does not verify (planted/unauthenticated): ${evidence_file}" >&2
    return 1
  fi
}

PRINCIPAL_REVIEWERS="$(principal_reviewers | paste -sd, -)"
export AI_AUTO_PRINCIPAL="${ACTIVE_PRINCIPAL}"

if ! principal_evidence_valid; then
  exit 2
fi

if [ "${SKIP_CONTEXT_GENERATION}" = "1" ]; then
  echo "[review] using existing review context and prompts..."
  CONTEXT_FILE="$(find "${CONTEXT_DIR}" -maxdepth 1 -type f \( -name 'review-context-*.md' -o -name 'latest-review-context.md' \) -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
  CONTEXT_FILE="${CONTEXT_FILE:-existing context in ${CONTEXT_DIR}}"
else
  echo "[review] collecting review context..."
  CONTEXT_FILE="$(OUT_DIR="${CONTEXT_DIR}" INCLUDE_UNTRACKED_CONTENT="${REVIEW_INCLUDE_UNTRACKED_CONTENT}" REVIEW_CONTEXT_DETAIL="${REVIEW_CONTEXT_DETAIL}" REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES="${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES}" REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES="${REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES}" "${RUN_AI_REVIEWS_SCRIPT_DIR}/collect-review-context.sh")"

  echo "[review] generating review prompts..."
  OUT_DIR="${PROMPT_DIR}" REVIEW_CONTEXT_MAX_BYTES="${REVIEW_CONTEXT_MAX_BYTES}" "${RUN_AI_REVIEWS_SCRIPT_DIR}/make-review-prompts.sh" "${CONTEXT_FILE}" >/dev/null
fi

CLAUDE_PROMPT="${PROMPT_DIR}/claude-review.md"
GEMINI_PROMPT="${PROMPT_DIR}/gemini-review.md"

if [ ! -f "${CLAUDE_PROMPT}" ] || [ ! -f "${GEMINI_PROMPT}" ]; then
  echo "[review] review prompts missing; regenerate context without SKIP_CONTEXT_GENERATION=1"
  exit 1
fi

TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
REVIEW_RUN_ID_RAW="${REVIEW_RUN_ID:-${TIMESTAMP}}"
REVIEW_RUN_ID="$(printf '%s' "${REVIEW_RUN_ID_RAW}" | sed 's/[^A-Za-z0-9_.-]/_/g')"
if [ -z "${REVIEW_RUN_ID}" ]; then
  REVIEW_RUN_ID="${TIMESTAMP}"
fi
CLAUDE_OUT="${OUT_DIR}/claude-review-${TIMESTAMP}.md"
GEMINI_OUT="${OUT_DIR}/gemini-review-${TIMESTAMP}.md"
CODEX_ARCHITECT_FALLBACK_OUT="${OUT_DIR}/codex-architect-fallback-${TIMESTAMP}.md"
CODEX_TEST_FALLBACK_OUT="${OUT_DIR}/codex-test-fallback-${TIMESTAMP}.md"
CODEX_FALLBACK_SUMMARY_OUT="${OUT_DIR}/codex-fallback-summary-${TIMESTAMP}.md"
# R20: name the verdict-bearing summary by REVIEW_RUN_ID (not a bare timestamp) so
# summarize-ai-reviews.sh can select THIS run's summary deterministically by run id
# instead of by modification time. A planted future-mtime summary for a different /
# unknown run id is therefore not selectable as the current run's verdict source.
SUMMARY_OUT="${OUT_DIR}/review-summary-${REVIEW_RUN_ID}.md"
MANIFEST_OUT="${OUT_DIR}/review-run-${REVIEW_RUN_ID}.md"
EXTERNAL_RUNNER="${EXTERNAL_REVIEW_DIR}/run-reviewers-${TIMESTAMP}.sh"
EXTERNAL_LATEST="${EXTERNAL_REVIEW_DIR}/run-reviewers-latest.sh"
SPLIT_CONTEXT_MANIFEST="${PROMPT_DIR}/split-review-manifest.md"
if [ ! -f "${SPLIT_CONTEXT_MANIFEST}" ]; then
  SPLIT_CONTEXT_MANIFEST="none"
fi
# make-review-prompts.sh drops this flag when the context would split into more parts than
# REVIEW_MAX_PARTS. Fail CLOSED: short-circuit each reviewer to a single request_changes
# verdict with NO model call, instead of fanning out one call per part (denial-of-wallet).
OVERSIZED_CONTEXT_FLAG="${PROMPT_DIR}/oversized-review-context.flag"

reset_disabled_reviewers() {
  # A manual reset is an explicit human judgment that the underlying cause is addressed, so it
  # also clears the chronic-redisable streak (scripts/run-ai-reviews.sh:reviewer_chronic_file) --
  # otherwise a resolved issue would still carry a stale chronic_count into the next disable.
  case "${RESET_DISABLED_AI_REVIEWERS:-}" in
    all)
      rm -f "${REVIEW_STATE_DIR}/claude.disabled" "${REVIEW_STATE_DIR}/gemini.disabled"
      rm -f "${REVIEW_STATE_DIR}/claude.chronic" "${REVIEW_STATE_DIR}/gemini.chronic"
      ;;
    claude)
      rm -f "${REVIEW_STATE_DIR}/claude.disabled" "${REVIEW_STATE_DIR}/claude.chronic"
      ;;
    gemini)
      rm -f "${REVIEW_STATE_DIR}/gemini.disabled" "${REVIEW_STATE_DIR}/gemini.chronic"
      ;;
    "")
      ;;
    *)
      echo "[review] unknown RESET_DISABLED_AI_REVIEWERS value: ${RESET_DISABLED_AI_REVIEWERS}"
      ;;
  esac
}

disabled_reason() {
  local reviewer="$1"
  local disabled_file
  disabled_file="$(reviewer_disabled_file "${reviewer}")"

  # A marker is authoritative only if it carries a valid out-of-tree-keyed HMAC. A planted /
  # unauthenticated marker is treated as ABSENT (no reason) so the reviewer runs instead of the
  # panel silently degrading to codex-only.
  if ! reviewer_disabled_authentic "${reviewer}"; then
    return 1
  fi

  local reason details disabled_at source_run_id next_action reset_hint
  reason="$(sed -n 's/^reason=//p' "${disabled_file}" 2>/dev/null | head -n 1)"
  details="$(sed -n 's/^details=//p' "${disabled_file}" 2>/dev/null | head -n 1)"
  disabled_at="$(sed -n 's/^disabled_at=//p' "${disabled_file}" 2>/dev/null | head -n 1)"
  source_run_id="$(sed -n 's/^source_run_id=//p' "${disabled_file}" 2>/dev/null | head -n 1)"
  next_action="$(sed -n 's/^next_action=//p' "${disabled_file}" 2>/dev/null | head -n 1)"
  reset_hint="$(sed -n 's/^reset_hint=//p' "${disabled_file}" 2>/dev/null | head -n 1)"

  echo "reason=${reason}; details=${details}; disabled_at=${disabled_at}; source_run_id=${source_run_id:-unknown}; next_action=${next_action:-user_reset_required}; reset_hint=${reset_hint:-RESET_DISABLED_AI_REVIEWERS=${reviewer} ./scripts/review-gate.sh}"
}

disabled_reviewers_summary() {
  local found=0
  local reviewer reason

  for reviewer in claude gemini; do
    if reason="$(disabled_reason "${reviewer}")"; then
      found=1
      echo "- ${reviewer}: ${reason}"
    fi
  done

  if [ "${found}" -eq 0 ]; then
    echo "- none"
  fi
}

write_run_manifest() {
  cat > "${MANIFEST_OUT}" <<MANIFEST
# AI Review Run Manifest

Generated at: $(date -Iseconds)

## Run

- Review run id: ${REVIEW_RUN_ID}
- Execution mode: ${REVIEW_EXECUTION_MODE}
- Active principal: ${ACTIVE_PRINCIPAL}
- Reviewer runtimes: ${PRINCIPAL_REVIEWERS}
- Context: ${CONTEXT_FILE}
- Claude prompt: ${CLAUDE_PROMPT}
- Gemini prompt: ${GEMINI_PROMPT}
- Split context manifest: ${SPLIT_CONTEXT_MANIFEST}
- Model routing report: ${AI_MODEL_ROUTING_REPORT}
- Model routing cache status: ${AI_MODEL_ROUTING_CACHE_STATUS:-unknown}
- Model routing cache age seconds: ${AI_MODEL_ROUTING_CACHE_AGE_SECONDS:-unknown}
- Model routing cache TTL seconds: ${AI_MODEL_ROUTING_CACHE_TTL_SECONDS:-unknown}

## Outputs

- Claude result: ${CLAUDE_OUT}
- Gemini result: ${GEMINI_OUT}
- Codex architect fallback: ${CODEX_ARCHITECT_FALLBACK_OUT}
- Codex test fallback: ${CODEX_TEST_FALLBACK_OUT}
- Principal review summary: ${CODEX_FALLBACK_SUMMARY_OUT}
- Review summary: ${SUMMARY_OUT}
- External runner: ${EXTERNAL_RUNNER}
- Latest external runner: ${EXTERNAL_LATEST}

## Disabled Reviewers At Manifest Time

$(disabled_reviewers_summary)
MANIFEST
}

reset_disabled_reviewers
expire_transient_disabled_reviewers

write_external_runner() {
  cat > "${EXTERNAL_RUNNER}" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail

# The runner always lives at <project>/.omx/external-review/, so its grandparent is the
# project root (true in self-host AND in a globalized project). The engine scripts are
# invoked below by ABSOLUTE path baked from the engine home, so a globalized project that
# carries ZERO scripts/ still resolves them (E: external mode broke on ./scripts/...).
script_dir="\$(CDPATH= cd -- "\$(dirname -- "\${BASH_SOURCE[0]}")" && pwd)"
repo_root="\$(CDPATH= cd -- "\${script_dir}/../.." && pwd)"
cd "\${repo_root}"

: "\${OUT_DIR:=${OUT_DIR}}"
: "\${CONTEXT_DIR:=${CONTEXT_DIR}}"
: "\${PROMPT_DIR:=${PROMPT_DIR}}"
: "\${REVIEW_STATE_DIR:=${REVIEW_STATE_DIR}}"
: "\${REVIEW_TIMEOUT_SECONDS:=${REVIEW_TIMEOUT_SECONDS}}"
: "\${REVIEW_TIMEOUT_KILL_AFTER_SECONDS:=${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}}"
: "\${CLAUDE_REVIEW_TIMEOUT_SECONDS:=${CLAUDE_REVIEW_TIMEOUT_SECONDS}}"
: "\${GEMINI_REVIEW_TIMEOUT_SECONDS:=${GEMINI_REVIEW_TIMEOUT_SECONDS}}"
: "\${GEMINI_REVIEW_COMMAND:=${GEMINI_REVIEW_COMMAND}}"
: "\${CODEX_FALLBACK_REVIEW_TIMEOUT_SECONDS:=${CODEX_FALLBACK_REVIEW_TIMEOUT_SECONDS}}"
: "\${CLAUDE_PROMPT_ARG_MAX_BYTES:=${CLAUDE_PROMPT_ARG_MAX_BYTES}}"
: "\${GEMINI_PROMPT_ARG_MAX_BYTES:=${GEMINI_PROMPT_ARG_MAX_BYTES}}"
: "\${GEMINI_PROMPT_MAX_BYTES:=${GEMINI_PROMPT_MAX_BYTES}}"
: "\${REVIEW_CONTEXT_MAX_BYTES:=${REVIEW_CONTEXT_MAX_BYTES}}"
: "\${REVIEW_CONTEXT_DETAIL:=${REVIEW_CONTEXT_DETAIL}}"
: "\${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES:=${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES}}"
: "\${REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES:=${REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES}}"
: "\${REVIEW_RETRY_LIMIT:=${REVIEW_RETRY_LIMIT}}"
: "\${REVIEW_OUTPUT_MODE:=tee}"
: "\${SKIP_CONTEXT_GENERATION:=1}"
: "\${REVIEW_INCLUDE_UNTRACKED_CONTENT:=${REVIEW_INCLUDE_UNTRACKED_CONTENT}}"
: "\${AI_MODEL_DISCOVERY:=${AI_MODEL_DISCOVERY}}"
: "\${AI_MODEL_DISCOVERY_DIR:=${AI_MODEL_DISCOVERY_DIR}}"
: "\${AI_MODEL_ROUTING_ENV:=${AI_MODEL_ROUTING_ENV}}"
: "\${AI_MODEL_ROUTING_REPORT:=${AI_MODEL_ROUTING_REPORT}}"
: "\${AI_MODEL_ROUTING_OBSERVATIONS:=}"
: "\${AI_MODEL_DISCOVERY_REFRESH:=${AI_MODEL_DISCOVERY_REFRESH:-0}}"
: "\${AI_MODEL_ROUTING_TTL_SECONDS:=${AI_MODEL_ROUTING_TTL_SECONDS:-43200}}"
: "\${CLAUDE_REVIEW_MODEL_AUTO:=${CLAUDE_REVIEW_MODEL_AUTO:-0}}"
: "\${AI_AUTO_PRINCIPAL:=${ACTIVE_PRINCIPAL}}"
: "\${AI_AUTO_PRINCIPAL_EVIDENCE:=${AI_AUTO_PRINCIPAL_EVIDENCE:-}}"
: "\${REVIEW_RUN_ID:=${REVIEW_RUN_ID}}"
# R20: export so the summarize-ai-reviews.sh call below (unchanged invocation) inherits
# REVIEW_RUN_ID and binds to THIS run's summary by run id instead of by mtime.
export REVIEW_RUN_ID
: "\${RUNTIME_ADAPTER_SCRIPT:=${RUNTIME_ADAPTER_SCRIPT}}"
: "\${RUNTIME_ADAPTER_CLAUDE_COMMAND:=${RUNTIME_ADAPTER_CLAUDE_COMMAND:-claude}}"
: "\${RUNTIME_ADAPTER_AGY_COMMAND:=${RUNTIME_ADAPTER_AGY_COMMAND}}"
: "\${RUNTIME_ADAPTER_CODEX_COMMAND:=${RUNTIME_ADAPTER_CODEX_COMMAND:-codex}}"

REVIEW_EXECUTION_MODE=local \\
OUT_DIR="\${OUT_DIR}" \\
CONTEXT_DIR="\${CONTEXT_DIR}" \\
PROMPT_DIR="\${PROMPT_DIR}" \\
REVIEW_STATE_DIR="\${REVIEW_STATE_DIR}" \\
REVIEW_TIMEOUT_SECONDS="\${REVIEW_TIMEOUT_SECONDS}" \\
REVIEW_TIMEOUT_KILL_AFTER_SECONDS="\${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}" \\
CLAUDE_REVIEW_TIMEOUT_SECONDS="\${CLAUDE_REVIEW_TIMEOUT_SECONDS}" \\
GEMINI_REVIEW_TIMEOUT_SECONDS="\${GEMINI_REVIEW_TIMEOUT_SECONDS}" \\
GEMINI_REVIEW_COMMAND="\${GEMINI_REVIEW_COMMAND}" \\
CODEX_FALLBACK_REVIEW_TIMEOUT_SECONDS="\${CODEX_FALLBACK_REVIEW_TIMEOUT_SECONDS}" \\
CLAUDE_PROMPT_ARG_MAX_BYTES="\${CLAUDE_PROMPT_ARG_MAX_BYTES}" \\
GEMINI_PROMPT_ARG_MAX_BYTES="\${GEMINI_PROMPT_ARG_MAX_BYTES}" \\
GEMINI_PROMPT_MAX_BYTES="\${GEMINI_PROMPT_MAX_BYTES}" \\
REVIEW_CONTEXT_MAX_BYTES="\${REVIEW_CONTEXT_MAX_BYTES}" \\
REVIEW_CONTEXT_DETAIL="\${REVIEW_CONTEXT_DETAIL}" \\
REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES="\${REVIEW_LIGHTWEIGHT_DIFF_MAX_BYTES}" \\
REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES="\${REVIEW_LIGHTWEIGHT_VERIFY_TAIL_LINES}" \\
REVIEW_RETRY_LIMIT="\${REVIEW_RETRY_LIMIT}" \\
REVIEW_OUTPUT_MODE="\${REVIEW_OUTPUT_MODE}" \\
SKIP_CONTEXT_GENERATION="\${SKIP_CONTEXT_GENERATION}" \\
REVIEW_INCLUDE_UNTRACKED_CONTENT="\${REVIEW_INCLUDE_UNTRACKED_CONTENT}" \\
AI_MODEL_DISCOVERY="\${AI_MODEL_DISCOVERY}" \\
AI_MODEL_DISCOVERY_DIR="\${AI_MODEL_DISCOVERY_DIR}" \\
AI_MODEL_ROUTING_ENV="\${AI_MODEL_ROUTING_ENV}" \\
AI_MODEL_ROUTING_REPORT="\${AI_MODEL_ROUTING_REPORT}" \\
AI_MODEL_ROUTING_OBSERVATIONS="\${AI_MODEL_ROUTING_OBSERVATIONS}" \\
AI_MODEL_DISCOVERY_REFRESH="\${AI_MODEL_DISCOVERY_REFRESH}" \\
AI_MODEL_ROUTING_TTL_SECONDS="\${AI_MODEL_ROUTING_TTL_SECONDS}" \\
CLAUDE_REVIEW_MODEL_AUTO="\${CLAUDE_REVIEW_MODEL_AUTO}" \\
AI_AUTO_PRINCIPAL="\${AI_AUTO_PRINCIPAL}" \\
AI_AUTO_PRINCIPAL_EVIDENCE="\${AI_AUTO_PRINCIPAL_EVIDENCE}" \\
REVIEW_RUN_ID="\${REVIEW_RUN_ID}" \\
RUNTIME_ADAPTER_SCRIPT="\${RUNTIME_ADAPTER_SCRIPT}" \\
RUNTIME_ADAPTER_CLAUDE_COMMAND="\${RUNTIME_ADAPTER_CLAUDE_COMMAND}" \\
RUNTIME_ADAPTER_AGY_COMMAND="\${RUNTIME_ADAPTER_AGY_COMMAND}" \\
RUNTIME_ADAPTER_CODEX_COMMAND="\${RUNTIME_ADAPTER_CODEX_COMMAND}" \\
"${RUN_AI_REVIEWS_SCRIPT_DIR}/run-ai-reviews.sh"

AI_AUTO_PRINCIPAL="\${AI_AUTO_PRINCIPAL}" RESULT_DIR="\${OUT_DIR}" OUT_DIR="\${OUT_DIR}" "${RUN_AI_REVIEWS_SCRIPT_DIR}/summarize-ai-reviews.sh"
SCRIPT

  chmod +x "${EXTERNAL_RUNNER}"
  cp "${EXTERNAL_RUNNER}" "${EXTERNAL_LATEST}"
  chmod +x "${EXTERNAL_LATEST}"
}

if [ "${REVIEW_EXECUTION_MODE}" = "external" ]; then
  write_external_runner

  cat > "${SUMMARY_OUT}" <<SUMMARY
# AI Review Summary

Generated at: $(date -Iseconds)

## Inputs

- Context: ${CONTEXT_FILE}
- Claude prompt: ${CLAUDE_PROMPT}
- Gemini prompt: ${GEMINI_PROMPT}
- Split context manifest: ${SPLIT_CONTEXT_MANIFEST}

## External Reviewer Command

Run this from an unrestricted interactive terminal:

    ${EXTERNAL_RUNNER}

Latest external reviewer command:

    ${EXTERNAL_LATEST}

## Notes

External mode prepares the review context and prompts, then stops before invoking reviewer CLIs in this restricted agent-run context.

Disabled reviewer state is shared with the generated external runner. If a reviewer is listed below, the external runner will also skip it until reset.

$(disabled_reviewers_summary)
SUMMARY

  write_run_manifest
  echo "[review] external reviewer runner: ${EXTERNAL_RUNNER}"
  echo "[review] latest external reviewer runner: ${EXTERNAL_LATEST}"
  echo "[review] run manifest: ${MANIFEST_OUT}"
  echo "[review] summary: ${SUMMARY_OUT}"
  echo "[review] disabled reviewers for external runner:"
  disabled_reviewers_summary
  echo "[review] external review pending"
  exit 2
fi

load_model_routing() {
  if [ "${AI_MODEL_DISCOVERY}" = "0" ]; then
    echo "[review] AI model discovery disabled by AI_MODEL_DISCOVERY=0"
    return 0
  fi

  if [ ! -x "${RUN_AI_REVIEWS_SCRIPT_DIR}/discover-ai-models.sh" ]; then
    echo "[review] AI model discovery script missing; using provider defaults"
    return 0
  fi

  echo "[review] discovering AI model routing..."
  if AI_MODEL_DISCOVERY_DIR="${AI_MODEL_DISCOVERY_DIR}" \
    AI_MODEL_ROUTING_ENV="${AI_MODEL_ROUTING_ENV}" \
    AI_MODEL_ROUTING_REPORT="${AI_MODEL_ROUTING_REPORT}" \
    "${RUN_AI_REVIEWS_SCRIPT_DIR}/discover-ai-models.sh" >/dev/null; then
    # Strict-parse the in-tree routing env as DATA (never source it).
    if parse_model_routing_env "${AI_MODEL_ROUTING_ENV}"; then
      echo "[review] model routing report: ${AI_MODEL_ROUTING_REPORT}"
      if [ -n "${AI_MODEL_ROUTING_DISCOVERED_EPOCH:-}" ] && printf '%s\n' "${AI_MODEL_ROUTING_DISCOVERED_EPOCH}" | grep -Eq '^[0-9]+$'; then
        routing_age=$(( $(date +%s) - AI_MODEL_ROUTING_DISCOVERED_EPOCH ))
        if [ "${routing_age}" -ge 0 ]; then
          echo "[review] model routing cache: ${AI_MODEL_ROUTING_CACHE_STATUS:-unknown}, age=${routing_age}s, ttl=${AI_MODEL_ROUTING_CACHE_TTL_SECONDS:-unknown}s"
        fi
      fi
      echo "[review] selected models: claude(${CLAUDE_REVIEW_ROLE:-review})=${CLAUDE_REVIEW_MODEL:-provider-default} gemini(${GEMINI_REVIEW_ROLE:-review})=${GEMINI_REVIEW_MODEL:-provider-default} codex_architect(${CODEX_ARCHITECT_REVIEW_ROLE:-fallback})=${CODEX_ARCHITECT_REVIEW_MODEL:-provider-default} codex_test(${CODEX_TEST_REVIEW_ROLE:-fallback})=${CODEX_TEST_REVIEW_MODEL:-provider-default}"
    else
      echo "[review] model routing env rejected (not a literal KEY='value' data file); using provider defaults" >&2
    fi
  else
    echo "[review] AI model discovery failed; using provider defaults"
  fi
}

help_supports_flag() {
  local help_text="$1"
  local flag="$2"

  printf '%s\n' "${help_text}" | grep -Eq "(^|[^[:alnum:]_-])${flag}($|[^[:alnum:]_-])"
}

command_help_text() {
  local command_name="$1"
  local output=""

  if ! command -v timeout >/dev/null 2>&1; then
    printf '%s\n' "runtime_unavailable: timeout command not found; help probe skipped"
    return
  fi

  output="$(timeout 10 "${command_name}" --help 2>&1 || true)"
  if [ -n "${output}" ]; then
    printf '%s\n' "${output}"
    return
  fi
  output="$(timeout 10 "${command_name}" help 2>&1 || true)"
  if [ -n "${output}" ]; then
    printf '%s\n' "${output}"
    return
  fi
  output="$(timeout 10 "${command_name}" -h 2>&1 || true)"
  printf '%s\n' "${output}"
}

runtime_adapter_command() {
  case "$1" in
    claude)
      printf '%s\n' "${RUNTIME_ADAPTER_CLAUDE_COMMAND:-claude}"
      ;;
    agy|gemini)
      printf '%s\n' "${RUNTIME_ADAPTER_AGY_COMMAND:-agy}"
      ;;
    codex)
      printf '%s\n' "${RUNTIME_ADAPTER_CODEX_COMMAND:-codex}"
      ;;
    *)
      return 1
      ;;
  esac
}

# AC3-5 (IP-3', D6): the chronic-redisable counter lives OUTSIDE the .disabled marker's own
# lifecycle. expire_transient_disabled_reviewers() deletes a transient marker once its cooldown
# elapses, so a counter stored only inside the marker would reset to zero every time the same
# root cause re-trips it -- which is precisely the regression D6 warned about ("disabled_at reset
# every run, stale alarm never fires"). This side file survives marker delete/recreate cycles and
# is reset only when the reason genuinely changes or a human runs RESET_DISABLED_AI_REVIEWERS.
reviewer_chronic_file() {
  echo "${REVIEW_STATE_DIR}/$1.chronic"
}

disable_reviewer() {
  local reviewer="$1"
  local reason="$2"
  local details="$3"
  local disabled_file disable_class next_action _mk_hmac
  local chronic_file prev_reason prev_count chronic_count
  local _hist_head _hist_file
  disabled_file="$(reviewer_disabled_file "${reviewer}")"

  # Classify: usage-limit / network-sandbox / connection-style / prompt-size-ceiling failures are
  # transient and auto-recover after the cooldown; anything else is persistent
  # and waits for a manual reset.
  case "${reason}" in
    usage_limit|network_or_sandbox|prompt_size_limit) disable_class="transient" ;;
    *)
      if printf '%s' "${details}" | grep -qiE 'connectionrefused|connection refused|network|timeout|timed out|rate.?limit|usage.?limit|temporarily|large_prompt_requires_prompt_file|large_prompt_prompt_file_fallback_failed'; then
        disable_class="transient"
      else
        disable_class="persistent"
      fi
      ;;
  esac
  if [ "${disable_class}" = "transient" ] && [ "${REVIEW_REVIEWER_DISABLE_COOLDOWN_SECONDS:-0}" -gt 0 ] 2>/dev/null; then
    next_action="auto_recover_after_cooldown_${REVIEW_REVIEWER_DISABLE_COOLDOWN_SECONDS}s"
  else
    next_action="user_reset_required"
  fi

  # Chronic-redisable bookkeeping: count consecutive same-reason disables regardless of whether
  # the marker in between was deleted by cooldown auto-recovery. A reason change (a genuinely
  # different failure) resets the streak to 1.
  chronic_file="$(reviewer_chronic_file "${reviewer}")"
  prev_reason=""
  prev_count=0
  if [ -f "${chronic_file}" ]; then
    prev_reason="$(sed -n 's/^reason=//p' "${chronic_file}" 2>/dev/null | head -n 1)"
    prev_count="$(sed -n 's/^count=//p' "${chronic_file}" 2>/dev/null | head -n 1)"
  fi
  case "${prev_count}" in ''|*[!0-9]*) prev_count=0 ;; esac
  if [ "${prev_reason}" = "${reason}" ]; then
    chronic_count=$((prev_count + 1))
  else
    chronic_count=1
  fi
  {
    echo "reason=${reason}"
    echo "count=${chronic_count}"
    echo "last_disabled_at=$(date -Iseconds)"
  } > "${chronic_file}"

  {
    echo "reviewer=${reviewer}"
    echo "disabled_at=$(date -Iseconds)"
    echo "reason=${reason}"
    echo "details=${details}"
    echo "disable_class=${disable_class}"
    echo "source_run_id=${REVIEW_RUN_ID}"
    echo "next_action=${next_action}"
    echo "chronic_count=${chronic_count}"
    echo "reset_hint=RESET_DISABLED_AI_REVIEWERS=${reviewer} ./scripts/review-gate.sh"
  } > "${disabled_file}"

  # HMAC-authenticate the marker with the out-of-tree key so a planted .disabled (gitignored,
  # project-controlled) cannot force a codex-only panel; only the framework, holding the key,
  # writes an authoritative marker. A genuine runtime disable ensures the key so it stays honored.
  if principal_evidence_ensure_key; then
    _mk_hmac="$(reviewer_marker_canonical "${reviewer}" "${disabled_file}" | principal_evidence_hmac)"
    if [ -n "${_mk_hmac}" ]; then printf 'marker_hmac=%s\n' "${_mk_hmac}" >> "${disabled_file}"; fi
  fi

  # RED2-2 durable disable-event trail: append every disable to the SAME append-only
  # .omx/review-history.log review-gate.sh's review_gate_record_history writes proceed/blocked
  # verdicts to (a distinct "event":"reviewer_disable" line, never "verdict":"proceed...", so
  # CHECK1-OMISSION's proceed/proceed_degraded grep is unaffected). Closes the chronic-reset
  # erasure gap named in review-gate.sh's own RED9-2 comment ("needs an out-of-band auditor
  # tracking chronic_file history/deltas"): ai-auto-audit.sh's CHECK4 can now compare the
  # CURRENT .disabled marker's chronic_count against how many disable events this reviewer+
  # reason pair has actually accumulated in this durable trail, so a same-UID actor who deletes
  # BOTH .disabled and .chronic and re-disables fresh (chronic_count resets to 1) leaves behind
  # a trail that still shows the true, larger count -- the delta is the tell. Best-effort:
  # 2>/dev/null and no `set -e` propagation, since a logging failure must never block the real
  # disable action this function exists to perform.
  _hist_file=".omx/review-history.log"
  _hist_head="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  mkdir -p .omx 2>/dev/null || true
  printf '{"ts":"%s","head_sha":"%s","event":"reviewer_disable","reviewer":"%s","reason":"%s","chronic_count":%s,"source":"run-ai-reviews"}\n' \
    "$(date -Iseconds)" "${_hist_head}" "${reviewer}" "${reason}" "${chronic_count}" >> "${_hist_file}" 2>/dev/null || true

  echo "[review] ${reviewer} review disabled (${disable_class}): ${reason} (${details}) [chronic_count=${chronic_count}]"
}

failure_details() {
  local output_file="$1"
  local status="$2"
  local class
  local tail_text

  class="$(failure_class "${output_file}" "${status}")"

  tail_text="$(tail -20 "${output_file}" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-500)"
  printf 'class=%s; exit_status=%s; tail=%s' "${class}" "${status}" "${tail_text:-none}"
  if [ -n "${REVIEWER_PREFLIGHT_DETAILS:-}" ]; then
    printf '; preflight=%s' "${REVIEWER_PREFLIGHT_DETAILS}"
  fi
}

first_pass_reviewer_posture() {
  case "$1" in
    codex) echo "read_only_sandbox" ;;
    claude) echo "plan_permission_mode" ;;
    gemini) echo "sandboxed_prompt" ;;
    *) echo "unknown" ;;
  esac
}

failure_class() {
  local output_file="$1"
  local status="${2:-1}"

  if grep -qiE 'heap out of memory|JavaScript heap|allocation failed|out of memory|ENOMEM' "${output_file}" 2>/dev/null; then
    echo "oom"
  elif grep -qiE 'trust folder|trusted folder|trust.*workspace|workspace.*trust|skip-trust' "${output_file}" 2>/dev/null; then
    echo "trust_required"
  elif grep -qiE 'ECONNREFUSED|ConnectionRefused|connection refused|network.*blocked|sandbox|read-only file system|EROFS' "${output_file}" 2>/dev/null; then
    echo "network_or_sandbox"
  elif grep -qiE 'large_prompt_requires_prompt_file|large_prompt_prompt_file_fallback_failed' "${output_file}" 2>/dev/null; then
    # AC3-3 (IP-3', 2026-07-07): an oversized-prompt runtime_unavailable from
    # ai-runtime-adapter.sh's agy path is a structural argv-length ceiling, not a persistent
    # reviewer outage -- classify it distinctly so disable_reviewer() below treats it as
    # transient (auto-recovers) instead of falling through to command_failed (persistent).
    echo "prompt_size_limit"
  elif grep -qiE 'timed out|timeout|SIGTERM|Killed' "${output_file}" 2>/dev/null; then
    echo "timeout_or_killed"
  elif grep -qiE 'auth|login|credential|permission denied|unauthorized|forbidden' "${output_file}" 2>/dev/null; then
    echo "auth_or_permission"
  elif is_limit_failure "${output_file}"; then
    echo "usage_limit"
  elif [ "${status}" -eq 0 ]; then
    echo "no_usable_verdict"
  else
    echo "command_failed"
  fi
}

preflight_details() {
  local reviewer="$1"
  local help_text="$2"
  local prompt_file="$3"
  local prompt_bytes
  prompt_bytes="$(wc -c < "${prompt_file}")"

  case "${reviewer}" in
    gemini)
      printf 'prompt_bytes=%s,first_pass_posture=%s' "${prompt_bytes}" "$(first_pass_reviewer_posture gemini)"
      if help_supports_flag "${help_text}" "--prompt"; then
        printf ',prompt_flag=yes'
      else
        printf ',prompt_flag=no'
      fi
      if help_supports_flag "${help_text}" "--skip-trust"; then
        printf ',skip_trust=yes'
      else
        printf ',skip_trust=no'
      fi
      if [ -n "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}" ]; then
        printf ',api_env=present'
      else
        printf ',api_env=missing'
      fi
      ;;
    claude)
      printf 'prompt_bytes=%s,first_pass_posture=%s' "${prompt_bytes}" "$(first_pass_reviewer_posture claude)"
      if printf '%s\n' "${help_text}" | grep -q -- '--print'; then
        printf ',print_flag=yes'
      else
        printf ',print_flag=no'
      fi
      if printf '%s\n' "${help_text}" | grep -q -- '--permission-mode'; then
        printf ',permission_mode=yes'
      else
        printf ',permission_mode=no'
      fi
      ;;
  esac
}

write_disabled_result() {
  local reviewer="$1"
  local output_file="$2"
  local reason="$3"

  echo "[review] ${reviewer} review skipped: disabled (${reason})"
  cat > "${output_file}" <<MSG
# ${reviewer^} Review

Skipped: ${reviewer} review is disabled.

Reason:
${reason}

Recovery: a transient disable (disable_class=transient -- usage/session/weekly/
quota/rate limit or network) auto-recovers after
REVIEW_REVIEWER_DISABLE_COOLDOWN_SECONDS on a later run. A persistent disable, or
to re-enable immediately:
- RESET_DISABLED_AI_REVIEWERS=${reviewer} ./scripts/run-ai-reviews.sh
- RESET_DISABLED_AI_REVIEWERS=all ./scripts/run-ai-reviews.sh
MSG
}

is_limit_failure() {
  local output_file="$1"

  # large_prompt_* is deliberately included here even though it isn't a usage/rate limit: it is
  # equally deterministic (retrying the same oversized prompt without a code change always fails
  # the same way), so short-circuit straight to disable_reviewer() with an accurate
  # prompt_size_limit reason instead of burning REVIEW_RETRY_LIMIT identical, doomed attempts.
  grep -qiE 'hit your limit|usage limit|session limit|weekly limit|week limit|rate limit|quota|RESOURCE_EXHAUSTED|resets [0-9]|resets [ap]m|limit reached|large_prompt_requires_prompt_file|large_prompt_prompt_file_fallback_failed' "${output_file}"
}

has_usable_verdict() {
  local output_file="$1"

  awk '
    BEGIN { in_verdict = 0 }
    tolower($0) ~ /^#+[[:space:]]+verdict[[:space:]:.-]*$/ { in_verdict = 1; next }
    in_verdict && /^#+[[:space:]]+/ { exit }
    in_verdict && /^[[:space:]]*$/ { next }
    in_verdict {
      verdict = tolower($0)
      gsub(/[^a-z_]/, "", verdict)
      if (verdict == "approve" || verdict == "approve_with_notes" || verdict == "request_changes") {
        found = 1
        exit
      }
    }
    END { exit found ? 0 : 1 }
  ' "${output_file}"
}

extract_review_verdict() {
  local output_file="$1"

  awk '
    BEGIN { in_verdict = 0 }
    tolower($0) ~ /^#+[[:space:]]+verdict[[:space:]:.-]*$/ { in_verdict = 1; next }
    in_verdict && /^#+[[:space:]]+/ { exit }
    in_verdict && /^[[:space:]]*$/ { next }
    in_verdict {
      verdict = tolower($0)
      gsub(/[^a-z_]/, "", verdict)
      if (verdict == "approve" || verdict == "approve_with_notes" || verdict == "request_changes") {
        print verdict
        exit
      }
    }
  ' "${output_file}"
}

is_review_approval() {
  case "$1" in
    approve|approve_with_notes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_review_command() {
  local output_file="$1"
  shift

  if [ "${REVIEW_OUTPUT_MODE}" = "tee" ]; then
    "$@" 2>&1 | tee "${output_file}"
    return "${PIPESTATUS[0]}"
  fi

  "$@" > "${output_file}" 2>&1
}

run_review_command_stdin() {
  local output_file="$1"
  local input_file="$2"
  shift 2

  if [ "${REVIEW_OUTPUT_MODE}" = "tee" ]; then
    "$@" < "${input_file}" 2>&1 | tee "${output_file}"
    return "${PIPESTATUS[0]}"
  fi

  "$@" < "${input_file}" > "${output_file}" 2>&1
}

write_oversized_context_verdict() {
  # Fail-closed request_changes for an over-ceiling context; no external model call.
  local reviewer="$1"
  local output_file="$2"
  local reason
  reason="$(head -n 2 "${OVERSIZED_CONTEXT_FLAG}" 2>/dev/null | tr '\n' ' ')"
  {
    echo "# ${reviewer} Review"
    echo
    echo "## Verdict"
    echo
    echo "request_changes"
    echo
    echo "## Findings"
    echo
    echo "- severity: high"
    echo "- file or area: review context"
    echo "- reason: ${reason:-Review context exceeds REVIEW_MAX_PARTS; not reviewed to avoid unbounded reviewer fan-out.}"
    echo "- suggested fix: narrow the change scope or split it into smaller reviewable commits."
    echo
    echo "## Final Recommendation"
    echo
    echo "Do not proceed: the review context is too large for bounded external review."
  } > "${output_file}"
  echo "[review] ${reviewer} context over REVIEW_MAX_PARTS; wrote fail-closed request_changes with no model call: ${output_file}"
}

run_claude_prompt_file() {
  local output_file="$1"
  local prompt_file="$2"
  if [ -f "${OVERSIZED_CONTEXT_FLAG}" ]; then
    write_oversized_context_verdict "Claude" "${output_file}"
    return 0
  fi
  local adapter_args=(
    run-readonly
    --runtime claude
    --capability review
    --prompt-file "${prompt_file}"
    --output "${output_file}"
    --timeout "${CLAUDE_REVIEW_TIMEOUT_SECONDS}"
    --kill-after "${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}"
    --cd "$(pwd)"
  )

  if [ -n "${CLAUDE_REVIEW_MODEL:-}" ]; then
    adapter_args+=(--model "${CLAUDE_REVIEW_MODEL}")
  fi

  run_with_retries "claude" "${output_file}" "${RUNTIME_ADAPTER_SCRIPT}" "${adapter_args[@]}"
}

run_gemini_prompt_file() {
  local output_file="$1"
  local prompt_file="$2"
  local prompt_bytes
  local adapter_args=()

  if [ -f "${OVERSIZED_CONTEXT_FLAG}" ]; then
    write_oversized_context_verdict "Gemini" "${output_file}"
    return 0
  fi

  prompt_bytes="$(wc -c < "${prompt_file}")"

  if [ "${prompt_bytes}" -gt "${GEMINI_PROMPT_MAX_BYTES}" ]; then
    {
      echo "# Gemini Review"
      echo
      echo "## Verdict"
      echo
      echo "request_changes"
      echo
      echo "## Findings"
      echo
      echo "- severity: high"
      echo "- file or area: review context"
      echo "- reason: Gemini prompt is ${prompt_bytes} bytes and exceeds GEMINI_PROMPT_MAX_BYTES=${GEMINI_PROMPT_MAX_BYTES}; the review pipeline must not truncate the prompt and accept a normal verdict."
      echo "- suggested fix: use split review artifacts or a reviewer surface that can process the full context."
      echo
      echo "## Final Recommendation"
      echo
      echo "Do not proceed with Gemini approval until the full context is reviewed."
    } > "${output_file}"
    echo "[review] Gemini prompt too large; wrote request_changes without truncating: ${output_file}"
    return 0
  fi

  adapter_args=(
    run-readonly
    --runtime gemini
    --capability review
    --prompt-file "${prompt_file}"
    --output "${output_file}"
    --timeout "${GEMINI_REVIEW_TIMEOUT_SECONDS}"
    --kill-after "${REVIEW_TIMEOUT_KILL_AFTER_SECONDS}"
    --cd "$(pwd)"
  )
  if [ -n "${GEMINI_REVIEW_MODEL:-}" ]; then
    adapter_args+=(--model "${GEMINI_REVIEW_MODEL}")
  fi

  RUNTIME_ADAPTER_PROMPT_ARG_MAX_BYTES="${GEMINI_PROMPT_ARG_MAX_BYTES}" \
    run_with_retries "gemini" "${output_file}" "${RUNTIME_ADAPTER_SCRIPT}" "${adapter_args[@]}"
}

run_with_retries() {
  local reviewer="$1"
  local output_file="$2"
  shift 2

  local attempt=1
  local status=0
  local attempt_log=""
  # Clean the random-suffixed adapter log on EVERY function-exit path (incl. a set -e abort
  # between mktemp and the explicit rm), so an interrupted retry loop leaves no unbounded litter
  # under OUT_DIR. RETURN (not INT/TERM) to avoid disturbing the heartbeat's own signal traps.
  trap 'rm -f "${attempt_log:-}"' RETURN

  while [ "${attempt}" -le "${REVIEW_RETRY_LIMIT}" ]; do
    echo "[review] ${reviewer} attempt ${attempt}/${REVIEW_RETRY_LIMIT}"
    attempt_log="$(mktemp "${OUT_DIR}/.${reviewer}-adapter-${attempt}.XXXXXX.log")"
    "$@" > "${attempt_log}" 2>&1
    status=$?

    if [ "${status}" -eq 0 ] && has_usable_verdict "${output_file}"; then
      rm -f "${attempt_log}"
      return 0
    fi

    {
      echo
      echo "---"
      echo
      echo "Adapter execution diagnostics:"
      echo "Exit status: ${status}"
      echo "Attempt: ${attempt}/${REVIEW_RETRY_LIMIT}"
      echo
      tail -80 "${attempt_log}" 2>/dev/null || true
    } >> "${output_file}"
    rm -f "${attempt_log}"

    if is_limit_failure "${output_file}"; then
      local reason
      reason="$(failure_class "${output_file}" "${status}")"
      disable_reviewer "${reviewer}" "${reason}" "$(failure_details "${output_file}" "${status}")"
      return "${status}"
    fi

    if [ "${status}" -eq 0 ]; then
      status=1
      echo "[review] ${reviewer} produced no usable ## Verdict section"
    fi

    echo "[review] ${reviewer} attempt ${attempt}/${REVIEW_RETRY_LIMIT} failed with status ${status}"
    attempt=$((attempt + 1))
  done

  disable_reviewer "${reviewer}" "retry_exhausted" "$(failure_details "${output_file}" "${status}")"
  return "${status}"
}

run_claude_split_review() {
  local split_dir="${PROMPT_DIR}/split-review-context"
  local split_work_dir="${OUT_DIR}/claude-split-${TIMESTAMP}"
  local part part_name part_prompt part_out
  local split_parts=()
  local part_count=0
  local part_request_changes=0
  local part_verdict
  local synthesis_prompt="${split_work_dir}/synthesis-prompt.md"

  if [ "${SPLIT_CONTEXT_MANIFEST}" = "none" ] || [ ! -d "${split_dir}" ]; then
    return 1
  fi

  mkdir -p "${split_work_dir}"
  mapfile -t split_parts < <(find "${split_dir}" -maxdepth 1 -type f -name 'part-*.md' | sort)

  if [ "${#split_parts[@]}" -eq 0 ]; then
    return 1
  fi

  for part in "${split_parts[@]}"; do
    [ -n "${part}" ] || continue
    part_count=$((part_count + 1))
    part_name="$(basename "${part}")"
    part_prompt="${split_work_dir}/${part_name%.md}-prompt.md"
    part_out="${split_work_dir}/${part_name%.md}-review.md"

    cat > "${part_prompt}" <<MSG
# Claude Split Review Part

You are reviewing one ordered part of a larger review context.

Use only the review context embedded in this prompt. Do not run shell commands,
inspect repository files, invoke tools, or start a fresh verification run.

This is ${part_name}. Do not issue a final whole-change approval from this part
alone. Return a verdict for this part and one non-empty observation that can be
used by the final synthesis review.

Return exactly this Markdown structure:

## Verdict

Choose one:

- approve
- approve_with_notes
- request_changes

## Findings

List concrete findings for this part only. If no blocking findings exist, say
"No blocking findings."

## Part Observation

${part_name}: one concise, non-empty observation about this part.

## Final Recommendation

State whether this part can be included in final synthesis.

---

MSG
    cat "${part}" >> "${part_prompt}"

    echo "[review] running Claude split review for ${part_name}..."
    if ! run_claude_prompt_file "${part_out}" "${part_prompt}"; then
      local disabled
      if disabled="$(disabled_reason claude)"; then
        write_disabled_result "claude" "${CLAUDE_OUT}" "${disabled}"
        return 0
      fi
      {
        echo "# Claude Review"
        echo
        echo "## Verdict"
        echo
        echo "request_changes"
        echo
        echo "## Findings"
        echo
        echo "- severity: high"
        echo "- file or area: ${part_name}"
        echo "- reason: Claude split review failed before all parts could be reviewed."
        echo "- suggested fix: inspect ${part_out} and rerun the split review."
        echo
        echo "## Final Recommendation"
        echo
        echo "Do not proceed until every split part has a usable review result."
      } > "${CLAUDE_OUT}"
      return 0
    fi

    part_verdict="$(extract_review_verdict "${part_out}")"
    if [ "${part_verdict}" = "request_changes" ]; then
      part_request_changes=1
    fi
  done

  if [ "${part_count}" -eq 0 ]; then
    return 1
  fi

  {
    echo "# Claude Split Review Synthesis Request"
    echo
    echo "You are synthesizing ordered Claude split-review results into one final"
    echo "whole-change review verdict."
    echo
    echo "Use only the split manifest and per-part review results embedded below."
    echo "Do not run shell commands, inspect repository files, invoke tools, or start"
    echo "a fresh verification run."
    echo
    echo "If any part requested changes, the final verdict must be request_changes"
    echo "unless the part result is internally malformed and cannot be trusted."
    echo
    echo "Return exactly this Markdown structure:"
    echo
    echo "## Verdict"
    echo
    echo "Choose one:"
    echo
    echo "- approve"
    echo "- approve_with_notes"
    echo "- request_changes"
    echo
    echo "## Findings"
    echo
    echo "List whole-change findings. If no blocking findings exist, say \"No blocking findings.\""
    echo
    echo "## Synthesis"
    echo
    echo "Include one non-empty observation line for every split part, formatted exactly like:"
    echo
    echo "- part-0001.md: observation"
    echo
    echo "## Final Recommendation"
    echo
    echo "Give a short final recommendation."
    echo
    echo "---"
    echo
    echo "## Split Manifest"
    echo
    cat "${SPLIT_CONTEXT_MANIFEST}"
    echo
    echo "## Per-Part Reviews"
    echo
    for part in "${split_parts[@]}"; do
      part_name="$(basename "${part}")"
      part_out="${split_work_dir}/${part_name%.md}-review.md"
      echo
      echo "### ${part_name}"
      echo
      cat "${part_out}"
    done
  } > "${synthesis_prompt}"

  echo "[review] running Claude split synthesis over ${part_count} parts..."
  if ! run_claude_prompt_file "${CLAUDE_OUT}" "${synthesis_prompt}"; then
    local disabled
    if disabled="$(disabled_reason claude)"; then
      write_disabled_result "claude" "${CLAUDE_OUT}" "${disabled}"
      return 0
    fi
    {
      echo "# Claude Review"
      echo
      echo "## Verdict"
      echo
      echo "request_changes"
      echo
      echo "## Findings"
      echo
      echo "- severity: high"
      echo "- file or area: split synthesis"
      echo "- reason: Claude split synthesis failed after ${part_count} part reviews."
      echo "- suggested fix: inspect ${split_work_dir} and rerun the review."
      echo
      echo "## Final Recommendation"
      echo
      echo "Do not proceed until split synthesis produces a usable verdict."
    } > "${CLAUDE_OUT}"
    return 0
  fi

  if [ "${part_request_changes}" -eq 1 ] && is_review_approval "$(extract_review_verdict "${CLAUDE_OUT}")"; then
    {
      echo "# Claude Review"
      echo
      echo "## Verdict"
      echo
      echo "request_changes"
      echo
      echo "## Findings"
      echo
      echo "- severity: high"
      echo "- file or area: split synthesis"
      echo "- reason: at least one split part requested changes, but synthesis returned an approval."
      echo "- suggested fix: inspect ${split_work_dir} and address the part-level finding."
      echo
      echo "## Synthesis"
      echo
      for part in "${split_parts[@]}"; do
        part_name="$(basename "${part}")"
        echo "- ${part_name}: reviewed; see ${split_work_dir}/${part_name%.md}-review.md"
      done
      echo
      echo "## Final Recommendation"
      echo
      echo "Do not proceed until request_changes part findings are resolved."
    } > "${CLAUDE_OUT}"
  fi

  echo "[review] Claude split review result: ${CLAUDE_OUT}"
  return 0
}

run_gemini_split_review() {
  local split_dir="${PROMPT_DIR}/split-review-context"
  local split_work_dir="${OUT_DIR}/gemini-split-${TIMESTAMP}"
  local part part_name part_prompt part_out
  local split_parts=()
  local part_count=0
  local part_request_changes=0
  local part_verdict
  local synthesis_prompt="${split_work_dir}/synthesis-prompt.md"

  if [ "${SPLIT_CONTEXT_MANIFEST}" = "none" ] || [ ! -d "${split_dir}" ]; then
    return 1
  fi

  mkdir -p "${split_work_dir}"
  mapfile -t split_parts < <(find "${split_dir}" -maxdepth 1 -type f -name 'part-*.md' | sort)

  if [ "${#split_parts[@]}" -eq 0 ]; then
    return 1
  fi

  for part in "${split_parts[@]}"; do
    [ -n "${part}" ] || continue
    part_count=$((part_count + 1))
    part_name="$(basename "${part}")"
    part_prompt="${split_work_dir}/${part_name%.md}-prompt.md"
    part_out="${split_work_dir}/${part_name%.md}-review.md"

    cat > "${part_prompt}" <<MSG
# Gemini Split Review Part

You are reviewing one ordered part of a larger review context.

Use only the review context embedded in this prompt. Do not run shell commands,
inspect repository files, invoke tools, or start a fresh verification run.

This is ${part_name}. Do not issue a final whole-change approval from this part
alone. Return a verdict for this part and one non-empty observation that can be
used by the final synthesis review.

Return exactly this Markdown structure:

## Verdict

Choose one:

- approve
- approve_with_notes
- request_changes

## Findings

List concrete findings for this part only. If no blocking findings exist, say
"No blocking findings."

## Part Observation

${part_name}: one concise, non-empty observation about this part.

## Final Recommendation

State whether this part can be included in final synthesis.

---

MSG
    cat "${part}" >> "${part_prompt}"

    echo "[review] running Gemini split review for ${part_name}..."
    if ! run_gemini_prompt_file "${part_out}" "${part_prompt}"; then
      local disabled
      if disabled="$(disabled_reason gemini)"; then
        write_disabled_result "gemini" "${GEMINI_OUT}" "${disabled}"
        return 0
      fi
      {
        echo "# Gemini Review"
        echo
        echo "## Verdict"
        echo
        echo "request_changes"
        echo
        echo "## Findings"
        echo
        echo "- severity: high"
        echo "- file or area: ${part_name}"
        echo "- reason: Gemini split review failed before all parts could be reviewed."
        echo "- suggested fix: inspect ${part_out} and rerun the split review."
        echo
        echo "## Final Recommendation"
        echo
        echo "Do not proceed until every split part has a usable review result."
      } > "${GEMINI_OUT}"
      return 0
    fi

    part_verdict="$(extract_review_verdict "${part_out}")"
    if [ "${part_verdict}" = "request_changes" ]; then
      part_request_changes=1
    fi
  done

  if [ "${part_count}" -eq 0 ]; then
    return 1
  fi

  {
    echo "# Gemini Split Review Synthesis Request"
    echo
    echo "You are synthesizing ordered Gemini split-review results into one final"
    echo "whole-change review verdict."
    echo
    echo "Use only the split manifest and per-part review results embedded below."
    echo "Do not run shell commands, inspect repository files, invoke tools, or start"
    echo "a fresh verification run."
    echo
    echo "If any part requested changes, the final verdict must be request_changes"
    echo "unless the part result is internally malformed and cannot be trusted."
    echo
    echo "Return exactly this Markdown structure:"
    echo
    echo "## Verdict"
    echo
    echo "Choose one:"
    echo
    echo "- approve"
    echo "- approve_with_notes"
    echo "- request_changes"
    echo
    echo "## Findings"
    echo
    echo "List whole-change findings. If no blocking findings exist, say \"No blocking findings.\""
    echo
    echo "## Synthesis"
    echo
    echo "Include one non-empty observation line for every split part, formatted exactly like:"
    echo
    echo "- part-0001.md: observation"
    echo
    echo "## Final Recommendation"
    echo
    echo "Give a short final recommendation."
    echo
    echo "---"
    echo
    echo "## Split Manifest"
    echo
    cat "${SPLIT_CONTEXT_MANIFEST}"
    echo
    echo "## Per-Part Reviews"
    echo
    for part in "${split_parts[@]}"; do
      part_name="$(basename "${part}")"
      part_out="${split_work_dir}/${part_name%.md}-review.md"
      echo
      echo "### ${part_name}"
      echo
      cat "${part_out}"
    done
  } > "${synthesis_prompt}"

  echo "[review] running Gemini split synthesis over ${part_count} parts..."
  if ! run_gemini_prompt_file "${GEMINI_OUT}" "${synthesis_prompt}"; then
    local disabled
    if disabled="$(disabled_reason gemini)"; then
      write_disabled_result "gemini" "${GEMINI_OUT}" "${disabled}"
      return 0
    fi
    {
      echo "# Gemini Review"
      echo
      echo "## Verdict"
      echo
      echo "request_changes"
      echo
      echo "## Findings"
      echo
      echo "- severity: high"
      echo "- file or area: split synthesis"
      echo "- reason: Gemini split synthesis failed after ${part_count} part reviews."
      echo "- suggested fix: inspect ${split_work_dir} and rerun the review."
      echo
      echo "## Final Recommendation"
      echo
      echo "Do not proceed until split synthesis produces a usable verdict."
    } > "${GEMINI_OUT}"
    return 0
  fi

  if [ "${part_request_changes}" -eq 1 ] && is_review_approval "$(extract_review_verdict "${GEMINI_OUT}")"; then
    {
      echo "# Gemini Review"
      echo
      echo "## Verdict"
      echo
      echo "request_changes"
      echo
      echo "## Findings"
      echo
      echo "- severity: high"
      echo "- file or area: split synthesis"
      echo "- reason: at least one split part requested changes, but synthesis returned an approval."
      echo "- suggested fix: inspect ${split_work_dir} and address the part-level finding."
      echo
      echo "## Synthesis"
      echo
      for part in "${split_parts[@]}"; do
        part_name="$(basename "${part}")"
        echo "- ${part_name}: reviewed; see ${split_work_dir}/${part_name%.md}-review.md"
      done
      echo
      echo "## Final Recommendation"
      echo
      echo "Do not proceed until request_changes part findings are resolved."
    } > "${GEMINI_OUT}"
  fi

  echo "[review] Gemini split review result: ${GEMINI_OUT}"
  return 0
}

run_claude() {
  if [ "${ACTIVE_PRINCIPAL}" = "claude" ]; then
    echo "[review] Claude review skipped: active principal cannot self-review"
    cat > "${CLAUDE_OUT}" <<MSG
# Claude Review

Skipped: Claude is the active principal runtime and cannot self-review this run.
MSG
    return 0
  fi

  if [ "${RUN_CLAUDE_REVIEW:-1}" = "0" ]; then
    echo "[review] Claude review disabled by RUN_CLAUDE_REVIEW=0"
    cat > "${CLAUDE_OUT}" <<MSG
# Claude Review

Skipped: Claude review was disabled by RUN_CLAUDE_REVIEW=0.
MSG
    return 0
  fi

  local disabled
  if disabled="$(disabled_reason claude)"; then
    write_disabled_result "claude" "${CLAUDE_OUT}" "${disabled}"
    return 0
  fi

  local claude_command
  claude_command="$(runtime_adapter_command claude)"

  if ! command -v "${claude_command}" >/dev/null 2>&1; then
    echo "[review] ${claude_command} command not found; skipping Claude review"
    cat > "${CLAUDE_OUT}" <<MSG
# Claude Review

Skipped: ${claude_command} command not found.
MSG
    return 0
  fi

  echo "[review] running Claude review..."

  set +e
  claude_help="$(command_help_text "${claude_command}")"
  REVIEWER_PREFLIGHT_DETAILS="$(preflight_details claude "${claude_help}" "${CLAUDE_PROMPT}")"
  if run_claude_split_review; then
    status=0
  else
    run_claude_prompt_file "${CLAUDE_OUT}" "${CLAUDE_PROMPT}"
    status=$?
  fi
  set -e

  if [ "${status}" -ne 0 ]; then
    {
      echo
      echo "---"
      echo
      echo "Claude review failed or timed out."
      echo "Exit status: ${status}"
      echo "Timeout seconds: ${CLAUDE_REVIEW_TIMEOUT_SECONDS}"
      echo
      echo "Known possible causes in agent-run contexts:"
      echo "- Anthropic API/network access is blocked or refused"
      echo "- Claude cannot write under its runtime directory"
      echo "- Claude authentication is unavailable in bare or isolated mode"
    } >> "${CLAUDE_OUT}"
    echo "[review] Claude review failed; result captured: ${CLAUDE_OUT}"
    return 0
  fi

  echo "[review] Claude result: ${CLAUDE_OUT}"
}

run_gemini() {
  if [ "${ACTIVE_PRINCIPAL}" = "gemini" ]; then
    echo "[review] Gemini review skipped: active principal cannot self-review"
    cat > "${GEMINI_OUT}" <<MSG
# Gemini Review

Skipped: Gemini is the active principal runtime and cannot self-review this run.
MSG
    return 0
  fi

  if [ "${RUN_GEMINI_REVIEW:-1}" = "0" ]; then
    echo "[review] Gemini review disabled; unset RUN_GEMINI_REVIEW or set RUN_GEMINI_REVIEW=1 to enable"
    cat > "${GEMINI_OUT}" <<MSG
# Gemini Review

Skipped: Gemini review was disabled by RUN_GEMINI_REVIEW=0.

Reason:
- Gemini CLI may enter interactive or agent mode.
- Previous runs hung or failed with capacity/tool errors.
- The default is to run Gemini; set RUN_GEMINI_REVIEW=0 to opt out for a specific gate run.
MSG
    return 0
  fi

  local disabled
  if disabled="$(disabled_reason gemini)"; then
    write_disabled_result "gemini" "${GEMINI_OUT}" "${disabled}"
    return 0
  fi

  local gemini_command
  gemini_command="$(runtime_adapter_command gemini)"

  if ! command -v "${gemini_command}" >/dev/null 2>&1; then
    echo "[review] ${gemini_command} command not found; skipping Gemini review"
    cat > "${GEMINI_OUT}" <<MSG
# Gemini Review

Skipped: ${gemini_command} command not found.
MSG
    return 0
  fi

  echo "[review] running Gemini review via ${gemini_command}..."

  set +e
  gemini_help="$(command_help_text "${gemini_command}")"
  gemini_prompt_file="${GEMINI_PROMPT}"
  REVIEWER_PREFLIGHT_DETAILS="$(preflight_details gemini "${gemini_help}" "${GEMINI_PROMPT}")"
  if run_gemini_split_review; then
    status=0
  else
    run_gemini_prompt_file "${GEMINI_OUT}" "${gemini_prompt_file}"
    status=$?
  fi
  set -e

  if [ "${status}" -ne 0 ]; then
    {
      echo
      echo "---"
      echo
      echo "Gemini review failed or timed out."
      echo "Exit status: ${status}"
      echo "Timeout seconds: ${GEMINI_REVIEW_TIMEOUT_SECONDS}"
      echo
      echo "Known possible causes:"
      echo "- Gemini model capacity exhausted"
      echo "- Gemini authentication is unavailable in the current context"
      echo "- Gemini stdin fallback was consumed by an auth prompt instead of review input"
      echo "- CLI tool permissions differ from this repository workflow"
      echo "- Gemini CLI entered an agent/tool mode instead of plain review mode"
    } >> "${GEMINI_OUT}"
    echo "[review] Gemini review failed; result captured: ${GEMINI_OUT}"
    return 0
  fi

  echo "[review] Gemini result: ${GEMINI_OUT}"
}

reviewer_fallback_needed() {
  local reviewer="$1"

  case "${reviewer}" in
    claude)
      [ "${RUN_CLAUDE_REVIEW:-1}" = "0" ] || reviewer_disabled_authentic claude
      ;;
    gemini)
      [ "${RUN_GEMINI_REVIEW:-1}" = "0" ] || reviewer_disabled_authentic gemini
      ;;
    *)
      return 1
      ;;
  esac
}

reviewer_fallback_reason() {
  local reviewer="$1"

  case "${reviewer}" in
    claude)
      if [ "${RUN_CLAUDE_REVIEW:-1}" = "0" ]; then
        echo "reviewer skipped by RUN_CLAUDE_REVIEW=0"
      else
        disabled_reason claude
      fi
      ;;
    gemini)
      if [ "${RUN_GEMINI_REVIEW:-1}" = "0" ]; then
        echo "reviewer skipped by RUN_GEMINI_REVIEW=0"
      else
        disabled_reason gemini
      fi
      ;;
    *)
      echo "unknown reviewer: ${reviewer}"
      return 1
      ;;
  esac
}

principal_substitute_needed() {
  case "${ACTIVE_PRINCIPAL}" in
    codex)
      reviewer_fallback_needed claude || reviewer_fallback_needed gemini
      ;;
    claude)
      reviewer_fallback_needed gemini
      ;;
    gemini)
      reviewer_fallback_needed claude
      ;;
  esac
}

codex_persona_needed() {
  [ "${ACTIVE_PRINCIPAL}" != "codex" ] || principal_substitute_needed
}

generate_codex_fallback_summary() {
  if ! codex_persona_needed; then
    cat > "${CODEX_FALLBACK_SUMMARY_OUT}" <<MSG
# Codex Fallback Review

Generated at: $(date -Iseconds)

## Status

none

## Assigned Fallback Reviewers

none

## Gate Policy

No principal substitute or Codex reviewer coverage was needed for this run.
MSG
    return 0
  fi

  echo "[review] generating principal review summary: ${CODEX_FALLBACK_SUMMARY_OUT}"

  if [ "${ACTIVE_PRINCIPAL}" != "codex" ] && ! principal_substitute_needed; then
    cat > "${CODEX_FALLBACK_SUMMARY_OUT}" <<MSG
# Codex Principal-Rotation Review

Generated at: $(date -Iseconds)

## Status

principal_rotation

## Independence Boundary

Codex is reviewing because the active principal runtime is ${ACTIVE_PRINCIPAL}.
This is an expected reviewer rotation lane, not degraded fallback coverage for a
disabled external reviewer.

## Assigned Reviewers

- codex-principal-review
  - covers the Codex reviewer lane for active principal ${ACTIVE_PRINCIPAL}
  - focus: correctness, maintainability, scope control, hidden risk, AGENTS.md and workflow compliance
  - artifact: ${CODEX_ARCHITECT_FALLBACK_OUT}
MSG
    return 0
  fi

  if principal_substitute_needed; then
    cat > "${CODEX_FALLBACK_SUMMARY_OUT}" <<MSG
# Principal Subagent Substitute Review

Generated at: $(date -Iseconds)

## Status

principal_subagent_substitute

## Independence Boundary

When a reviewer is unavailable, the active principal's subagent covers that lane
as a substitute reviewer. This is degraded coverage, not independent external
review: even with a usable verdict and direct file inspection evidence the run is
reported as proceed_degraded with degraded trust.

## Assigned Substitute Reviewers
MSG

    if reviewer_fallback_needed claude; then
      local claude_substitute_artifact="${CODEX_ARCHITECT_FALLBACK_OUT}"
      cat >> "${CODEX_FALLBACK_SUMMARY_OUT}" <<MSG

- principal-subagent-architect-review
  - covers the disabled Claude lane
  - principal runtime: ${ACTIVE_PRINCIPAL}
  - focus: correctness, maintainability, scope control, hidden risk, AGENTS.md and workflow compliance
  - disabled reason: $(reviewer_fallback_reason claude)
  - artifact: ${claude_substitute_artifact}
MSG
    fi

    if reviewer_fallback_needed gemini; then
      cat >> "${CODEX_FALLBACK_SUMMARY_OUT}" <<MSG

- principal-subagent-test-review
  - covers the disabled Gemini lane
  - principal runtime: ${ACTIVE_PRINCIPAL}
  - focus: missed edge cases, simpler alternatives, test coverage gaps, documentation clarity, future automation friction
  - disabled reason: $(reviewer_fallback_reason gemini)
  - artifact: ${CODEX_TEST_FALLBACK_OUT}
MSG
    fi

    if [ "${ACTIVE_PRINCIPAL}" != "codex" ]; then
      local codex_principal_artifact="${CODEX_ARCHITECT_FALLBACK_OUT}"
      if [ "${ACTIVE_PRINCIPAL}" = "gemini" ] && reviewer_fallback_needed claude; then
        codex_principal_artifact="${CODEX_TEST_FALLBACK_OUT}"
      fi
      cat >> "${CODEX_FALLBACK_SUMMARY_OUT}" <<MSG

- codex-principal-review
  - covers the Codex reviewer lane for active principal ${ACTIVE_PRINCIPAL}
  - artifact: ${codex_principal_artifact}
MSG
    fi

    cat >> "${CODEX_FALLBACK_SUMMARY_OUT}" <<MSG

## Gate Policy

Principal subagent substitute reviews are degraded coverage, not independent
external review. Even with an approval verdict and direct file inspection
evidence, the run is reported as proceed_degraded with degraded trust.
MSG
    return 0
  fi

  cat >> "${CODEX_FALLBACK_SUMMARY_OUT}" <<MSG

## Required Checklist

- Verify disabled reviewer reasons are visible in every run.
- Verify external reviewer prompts stay role-pure and do not simulate another model's perspective.
- Verify summary reports degraded coverage instead of multi_reviewer when external reviewers are missing.
- Verify degraded Codex coverage is not counted as independent Claude or Gemini reviewer approval.
- Verify re-enable instructions are present for disabled reviewers.

## Gate Policy

No substitute review was assigned.
MSG
}

write_codex_fallback_skipped() {
  local output_file="$1"
  local persona="$2"
  local reason="$3"

  cat > "${output_file}" <<MSG
# ${persona}

## Status

skipped

Skipped: ${reason}

## Reason

${reason}

## Verdict

missing
MSG
}

write_codex_fallback_prompt() {
  local prompt_file="$1"
  local persona="$2"
  local disabled_reviewer="$3"
  local focus="$4"

  case "${persona}" in
    principal-subagent-*)
      local reason
      reason="$(reviewer_fallback_reason "${disabled_reviewer}")"

      cat > "${prompt_file}" <<MSG
# ${persona}

You are running as the active principal runtime's subagent substitute reviewer.
Active principal: ${ACTIVE_PRINCIPAL}
Unavailable reviewer lane: ${disabled_reviewer}

This is principal-subagent substitute coverage for this review gate: degraded
coverage, not independent external review. Even with a usable verdict and direct
file inspection evidence, the run is reported as proceed_degraded with degraded trust.

Focus:
${focus}

Return exactly this Markdown structure:

## Verdict

Choose one:

- approve
- approve_with_notes
- request_changes

## Findings

List concrete issues only. If no blocking issues exist, say "No blocking findings."

## Direct File Inspection

List the repository files you inspected directly before giving the verdict. If a relevant changed file could not be inspected, list it here with the reason.

## Principal Subagent Substitute Boundary

State that this is ${ACTIVE_PRINCIPAL} principal-subagent substitute coverage for the unavailable ${disabled_reviewer} lane.

## Final Recommendation

Give a short recommendation for the review gate.

Unavailable reviewer reason:
${reason}

## Direct File Review

You are a principal-subagent substitute reviewer running in this repository. The
embedded review context may be partial, split, or optimized for external
reviewers. Treat it as orientation only.

Before issuing a verdict, read the referenced files directly from the workspace whenever they are relevant to the change. Include tracked, staged, and untracked text files that are part of the review scope. Do not rely only on compressed review prompts.

Changed files visible to git:

\`\`\`text
$(review_changed_files_for_prompt)
\`\`\`

You may use read-only inspection commands such as sed, rg, git diff, and git status. In the Direct File Inspection section, state which files you inspected and which relevant files were not inspected.

---

MSG
      if [ -f "${CONTEXT_FILE}" ]; then
        cat "${CONTEXT_FILE}" >> "${prompt_file}"
      else
        cat >> "${prompt_file}" <<MSG
Review context file is unavailable: ${CONTEXT_FILE}
MSG
      fi
      return 0
      ;;
  esac

  if [ "${ACTIVE_PRINCIPAL}" != "codex" ] && [ "${disabled_reviewer}" = "principal-rotation" ]; then
    cat > "${prompt_file}" <<MSG
# ${persona}

You are running as the Codex reviewer because the active AI_AUTO principal is ${ACTIVE_PRINCIPAL}.

This is normal principal-runtime reviewer rotation. Do not describe this as a
degraded fallback review.

Focus:
${focus}

Return exactly this Markdown structure:

## Verdict

Choose one:

- approve
- approve_with_notes
- request_changes

## Findings

List concrete issues only. If no blocking issues exist, say "No blocking findings."

## Direct File Inspection

List the repository files you inspected directly before giving the verdict. If a relevant changed file could not be inspected, list it here with the reason.

## Reviewer Boundary

State that this is Codex reviewer coverage for active principal ${ACTIVE_PRINCIPAL}.

## Final Recommendation

Give a short recommendation for the review gate.

## Direct File Review

You are a Codex/GPT reviewer running in this repository. The embedded review
context may be partial, split, or optimized for external reviewers. Treat it as
orientation only.

Before issuing a verdict, read the referenced files directly from the workspace whenever they are relevant to the change. Include tracked, staged, and untracked text files that are part of the review scope. Do not rely only on compressed review prompts.

Changed files visible to git:

\`\`\`text
$(review_changed_files_for_prompt)
\`\`\`

You may use read-only inspection commands such as sed, rg, git diff, and git status. In the Direct File Inspection section, state which files you inspected and which relevant files were not inspected.

---

MSG
    if [ -f "${CONTEXT_FILE}" ]; then
      cat "${CONTEXT_FILE}" >> "${prompt_file}"
    else
      cat >> "${prompt_file}" <<MSG
Review context file is unavailable: ${CONTEXT_FILE}
MSG
    fi
    return 0
  fi

  local reason
  reason="$(reviewer_fallback_reason "${disabled_reviewer}")"

  cat > "${prompt_file}" <<MSG
# ${persona}

You are running as a degraded Codex/GPT substitute reviewer because ${disabled_reviewer} is disabled.

This is degraded substitute review. Do not claim to be an independent external Claude or Gemini reviewer.

Focus:
${focus}

Return exactly this Markdown structure:

## Verdict

Choose one:

- approve
- approve_with_notes
- request_changes

## Findings

List concrete issues only. If no blocking issues exist, say "No blocking findings."

## Direct File Inspection

List the repository files you inspected directly before giving the verdict. If a relevant changed file could not be inspected, list it here with the reason.

## Fallback Boundary

State that this is degraded Codex/GPT substitute coverage and not independent external review.

## Final Recommendation

Give a short recommendation for the review gate.

Disabled reviewer reason:
${reason}

## Direct File Review

You are a degraded Codex/GPT substitute reviewer running in this repository. The embedded review context may be partial, split, or optimized for external reviewers. Treat it as orientation only.

Before issuing a verdict, read the referenced files directly from the workspace whenever they are relevant to the change. Include tracked, staged, and untracked text files that are part of the review scope. Do not rely only on compressed review prompts.

Changed files visible to git:

\`\`\`text
$(review_changed_files_for_prompt)
\`\`\`

You may use read-only inspection commands such as sed, rg, git diff, and git status. In the Direct File Inspection section, state which files you inspected and which relevant files were not inspected.

---

MSG

  if [ -f "${CONTEXT_FILE}" ]; then
    cat "${CONTEXT_FILE}" >> "${prompt_file}"
  else
    cat >> "${prompt_file}" <<MSG
Review context file is unavailable: ${CONTEXT_FILE}
MSG
  fi
}

run_codex_fallback_review() {
  local persona="$1"
  local output_file="$2"
  local disabled_reviewer="$3"
  local focus="$4"
  local prompt_file="${OUT_DIR}/${persona}-${TIMESTAMP}-prompt.md"
  local log_file="${output_file}.log"
  local codex_model=""
  local adapter_args=()

  case "${persona}" in
    codex-architect-review)
      codex_model="${CODEX_ARCHITECT_REVIEW_MODEL:-}"
      ;;
    codex-test-alternative-review)
      codex_model="${CODEX_TEST_REVIEW_MODEL:-}"
      ;;
  esac

  if [ "${RUN_CODEX_FALLBACK_REVIEW:-1}" = "0" ]; then
    write_codex_fallback_skipped "${output_file}" "${persona}" "RUN_CODEX_FALLBACK_REVIEW=0"
    return 0
  fi

  if [ ! -x "${RUNTIME_ADAPTER_SCRIPT}" ]; then
    write_codex_fallback_skipped "${output_file}" "${persona}" "${RUNTIME_ADAPTER_SCRIPT} not found"
    return 0
  fi

  write_codex_fallback_prompt "${prompt_file}" "${persona}" "${disabled_reviewer}" "${focus}"
  echo "[review] running ${persona} degraded Codex substitute review..."

  adapter_args=(
    run-readonly
    --runtime codex
    --capability review
    --prompt-file "${prompt_file}"
    --output "${output_file}"
    --timeout "${CODEX_FALLBACK_REVIEW_TIMEOUT_SECONDS}"
    --cd "$(pwd)"
  )
  if [ -n "${codex_model}" ]; then
    adapter_args+=(--model "${codex_model}")
  fi

  set +e
  "${RUNTIME_ADAPTER_SCRIPT}" "${adapter_args[@]}" > "${log_file}" 2>&1
  status=$?
  set -e

  if [ "${status}" -ne 0 ]; then
    {
      echo "# ${persona}"
      echo
      echo "## Status"
      echo
      echo "failed"
      echo
      echo "Degraded Codex substitute review failed or timed out."
      echo
      echo "Exit status: ${status}"
      echo "Timeout seconds: ${CODEX_FALLBACK_REVIEW_TIMEOUT_SECONDS}"
      echo "Log file: ${log_file}"
      echo
      echo "Adapter execution diagnostics:"
      echo
      tail -80 "${log_file}" 2>/dev/null || true
      echo
      echo "## Verdict"
      echo
      echo "failed"
    } > "${output_file}"
    echo "[review] ${persona} Codex fallback failed; result captured: ${output_file}"
    return 0
  fi

  if ! has_usable_verdict "${output_file}"; then
    {
      echo
      echo "---"
      echo
      echo "Degraded Codex substitute review produced no usable ## Verdict section."
      echo "Log file: ${log_file}"
    } >> "${output_file}"
  fi

  echo "[review] ${persona} Codex fallback result: ${output_file}"
}

run_principal_subagent_substitute_review() {
  local persona="$1"
  local output_file="$2"
  local disabled_reviewer="$3"
  local focus="$4"
  local prompt_file="${OUT_DIR}/${persona}-${TIMESTAMP}-prompt.md"
  local log_file="${output_file}.log"
  local runtime="${ACTIVE_PRINCIPAL}"
  local adapter_args=()
  local model=""

  case "${runtime}:${persona}" in
    codex:principal-subagent-architect-review)
      model="${CODEX_ARCHITECT_REVIEW_MODEL:-}"
      ;;
    codex:principal-subagent-test-review)
      model="${CODEX_TEST_REVIEW_MODEL:-}"
      ;;
    claude:*)
      model="${CLAUDE_REVIEW_MODEL:-}"
      ;;
    gemini:*|agy:*)
      model="${GEMINI_REVIEW_MODEL:-}"
      ;;
  esac

  if [ "${RUN_PRINCIPAL_SUBAGENT_SUBSTITUTE_REVIEW:-1}" = "0" ]; then
    write_codex_fallback_skipped "${output_file}" "${persona}" "RUN_PRINCIPAL_SUBAGENT_SUBSTITUTE_REVIEW=0"
    return 0
  fi

  if [ ! -x "${RUNTIME_ADAPTER_SCRIPT}" ]; then
    write_codex_fallback_skipped "${output_file}" "${persona}" "${RUNTIME_ADAPTER_SCRIPT} not found"
    return 0
  fi

  write_codex_fallback_prompt "${prompt_file}" "${persona}" "${disabled_reviewer}" "${focus}"
  echo "[review] running ${persona} via ${runtime} principal subagent substitute..."

  adapter_args=(
    run-readonly
    --runtime "${runtime}"
    --capability review
    --prompt-file "${prompt_file}"
    --output "${output_file}"
    --timeout "${CODEX_FALLBACK_REVIEW_TIMEOUT_SECONDS}"
    --cd "$(pwd)"
  )
  if [ -n "${model}" ]; then
    adapter_args+=(--model "${model}")
  fi

  set +e
  "${RUNTIME_ADAPTER_SCRIPT}" "${adapter_args[@]}" > "${log_file}" 2>&1
  status=$?
  set -e

  if [ "${status}" -ne 0 ]; then
    {
      echo "# ${persona}"
      echo
      echo "## Status"
      echo
      echo "failed"
      echo
      echo "Principal subagent substitute review failed or timed out."
      echo
      echo "Active principal: ${runtime}"
      echo "Unavailable reviewer lane: ${disabled_reviewer}"
      echo "Exit status: ${status}"
      echo "Timeout seconds: ${CODEX_FALLBACK_REVIEW_TIMEOUT_SECONDS}"
      echo "Log file: ${log_file}"
      echo
      echo "Adapter execution diagnostics:"
      echo
      tail -80 "${log_file}" 2>/dev/null || true
      echo
      echo "## Verdict"
      echo
      echo "failed"
    } > "${output_file}"
    echo "[review] ${persona} principal subagent substitute failed; result captured: ${output_file}"
    return 0
  fi

  if ! has_usable_verdict "${output_file}"; then
    {
      echo
      echo "---"
      echo
      echo "Principal subagent substitute review produced no usable ## Verdict section."
      echo "Log file: ${log_file}"
    } >> "${output_file}"
  fi

  echo "[review] ${persona} principal subagent substitute result: ${output_file}"
}

run_codex_fallback_reviews() {
  if ! codex_persona_needed; then
    return 0
  fi

  if [ "${ACTIVE_PRINCIPAL}" != "codex" ]; then
    local codex_principal_output="${CODEX_ARCHITECT_FALLBACK_OUT}"
    if [ "${ACTIVE_PRINCIPAL}" = "gemini" ] && reviewer_fallback_needed claude; then
      codex_principal_output="${CODEX_TEST_FALLBACK_OUT}"
    fi
    run_codex_fallback_review \
      "codex-principal-review" \
      "${codex_principal_output}" \
      "principal-rotation" \
      "- correctness
- maintainability
- scope control
- hidden risk
- AGENTS.md and docs/WORKFLOW.md compliance
- active principal runtime parity"
  fi

  if [ "${ACTIVE_PRINCIPAL}" = "codex" ] && reviewer_fallback_needed claude; then
    run_principal_subagent_substitute_review \
      "principal-subagent-architect-review" \
      "${CODEX_ARCHITECT_FALLBACK_OUT}" \
      "claude" \
      "- correctness
- maintainability
- scope control
- hidden risk
- AGENTS.md and docs/WORKFLOW.md compliance"
  fi

  if [ "${ACTIVE_PRINCIPAL}" = "codex" ] && reviewer_fallback_needed gemini; then
    run_principal_subagent_substitute_review \
      "principal-subagent-test-review" \
      "${CODEX_TEST_FALLBACK_OUT}" \
      "gemini" \
      "- missed edge cases
- simpler alternatives
- test coverage gaps
- documentation clarity
- future automation friction"
  fi

  if [ "${ACTIVE_PRINCIPAL}" = "claude" ] && reviewer_fallback_needed gemini; then
    run_principal_subagent_substitute_review \
      "principal-subagent-test-review" \
      "${CODEX_TEST_FALLBACK_OUT}" \
      "gemini" \
      "- missed edge cases
- simpler alternatives
- test coverage gaps
- documentation clarity
- future automation friction"
  fi

  if [ "${ACTIVE_PRINCIPAL}" = "gemini" ] && reviewer_fallback_needed claude; then
    run_principal_subagent_substitute_review \
      "principal-subagent-architect-review" \
      "${CODEX_ARCHITECT_FALLBACK_OUT}" \
      "claude" \
      "- correctness
- maintainability
- scope control
- hidden risk
- AGENTS.md and docs/WORKFLOW.md compliance"
  fi
}

# with_heartbeat <label> <command...>
# Runs <command> in THIS shell (return code, globals, and file writes preserved)
# while a backgrounded printer emits a periodic
# "[review] <label> still running… (elapsed Ns)" line, so an operator can tell the
# multi-minute reviewer phase is alive rather than hung. Only the printer is
# backgrounded — no daemon. Set REVIEW_HEARTBEAT_SECONDS=0 to silence the periodic
# line (start/finish lines are always emitted).
with_heartbeat() {
  local label="$1"
  shift
  local interval="${REVIEW_HEARTBEAT_SECONDS:-30}"
  local start_ts hb_pid="" rc
  start_ts="$(date +%s 2>/dev/null || echo 0)"
  echo "[review] ${label} starting…"

  if [ "${interval}" -gt 0 ] 2>/dev/null; then
    (
      # Self-terminate within one interval if the parent shell is gone. A
      # SIGKILL / OOM-kill of the parent cannot run its EXIT trap, so this
      # liveness check is the load-bearing guard that stops this backgrounded
      # printer from being reparented to init and looping forever. ("$$" keeps
      # the parent shell's PID inside a subshell — it is this printer's real
      # parent — whereas $PPID would resolve to the grandparent.)
      while kill -0 "$$" 2>/dev/null; do
        sleep "${interval}"
        hb_now="$(date +%s 2>/dev/null || echo 0)"
        echo "[review] ${label} still running… (elapsed $(( hb_now - start_ts ))s)"
      done
    ) &
    hb_pid=$!
    # If the parent is signalled/exits while the reviewer phase runs, reap the
    # printer instead of leaking it.
    trap 'kill "${hb_pid}" 2>/dev/null' EXIT INT TERM
  fi

  if "$@"; then
    rc=0
  else
    rc=$?
  fi

  if [ -n "${hb_pid}" ]; then
    # Normal return: clear the trap first so it cannot double-kill or fire on a
    # later (already-reaped) hb_pid, then reap exactly once.
    trap - EXIT INT TERM
    kill "${hb_pid}" 2>/dev/null || true
    wait "${hb_pid}" 2>/dev/null || true
  fi

  local end_ts
  end_ts="$(date +%s 2>/dev/null || echo 0)"
  echo "[review] ${label} phase finished in $(( end_ts - start_ts ))s"
  return "${rc}"
}

load_model_routing
with_heartbeat "Claude review" run_claude
with_heartbeat "Gemini review" run_gemini
with_heartbeat "Codex fallback reviews" run_codex_fallback_reviews
generate_codex_fallback_summary

cat > "${SUMMARY_OUT}" <<SUMMARY
# AI Review Summary

Generated at: $(date -Iseconds)

## Inputs

- Active principal: ${ACTIVE_PRINCIPAL}
- Reviewer runtimes: ${PRINCIPAL_REVIEWERS}
- Context: ${CONTEXT_FILE}
- Claude prompt: ${CLAUDE_PROMPT}
- Gemini prompt: ${GEMINI_PROMPT}
- Split context manifest: ${SPLIT_CONTEXT_MANIFEST}
- Model routing report: ${AI_MODEL_ROUTING_REPORT}

## Outputs

- Claude result: ${CLAUDE_OUT}
- Gemini result: ${GEMINI_OUT}
- Codex architect fallback: ${CODEX_ARCHITECT_FALLBACK_OUT}
- Codex test fallback: ${CODEX_TEST_FALLBACK_OUT}
- Principal review summary: ${CODEX_FALLBACK_SUMMARY_OUT}

## Notes

A reviewer failure does not fail this script. Failures are captured in the corresponding result file.
SUMMARY

write_run_manifest
echo "[review] run manifest: ${MANIFEST_OUT}"
echo "[review] summary: ${SUMMARY_OUT}"
echo "[review] done"
