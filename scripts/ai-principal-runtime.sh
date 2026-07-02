#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/ai-principal-runtime.sh normalize [codex|claude|gemini|agy]
  ./scripts/ai-principal-runtime.sh reviewers [codex|claude|gemini|agy]
  ./scripts/ai-principal-runtime.sh profile [codex|claude|gemini|agy]

Define the AI_AUTO active principal runtime contract. The principal may be
codex, claude, or gemini. Repo-local permissions are intentionally identical
across principals; only reviewer rotation changes.
USAGE
}

normalize_principal() {
  local principal="${1:-codex}"

  case "${principal}" in
    ""|codex)
      echo "codex"
      ;;
    claude)
      echo "claude"
      ;;
    gemini|agy)
      echo "gemini"
      ;;
    *)
      echo "unsupported principal runtime: ${principal}" >&2
      return 2
      ;;
  esac
}

reviewers_for_principal() {
  local principal
  principal="$(normalize_principal "${1:-codex}")"

  case "${principal}" in
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

write_profile() {
  local principal
  principal="$(normalize_principal "${1:-codex}")"

  cat <<PROFILE
principal_runtime=${principal}
repo_local_allowed_actions=read_repo,edit_files,run_local_verify,write_artifacts
requires_user_approval_for=commit,push,deploy,production,credentials
artifact_roots=.omx/state,.omx/plans,.omx/review-context,.omx/review-prompts,.omx/review-results,.omx/logs
reviewer_runtimes=$(reviewers_for_principal "${principal}" | paste -sd, -)
PROFILE
}

evidence_path() {
  echo "${AI_AUTO_PRINCIPAL_EVIDENCE:-.omx/state/principal-runtime/current.env}"
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
# Refuse an in-tree key path (attacker-readable) via realpath+toplevel; return 0 == in-tree == REFUSE.
principal_evidence_key_in_tree() {
  local kf top rp
  kf="$(principal_evidence_key_file)"
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "${top}" ] || return 1
  top="$(realpath -m -- "${top}" 2>/dev/null)" || return 1
  rp="$(realpath -m -- "${kf}" 2>/dev/null)" || return 1
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
  printf 'principal_runtime=%s\nexecution_mode=principal\nsource=ai-auto-principal-launcher\nworkspace=%s\n' "$1" "$2"
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

record_launcher_evidence() {
  local principal evidence_file evidence_dir workspace launch_base_commit _ev_hmac
  principal="$(normalize_principal "${1:-codex}")"
  evidence_file="$(evidence_path)"
  evidence_dir="$(dirname -- "${evidence_file}")"
  # Anchor to the repo root so a launch recorded from a subdirectory still
  # matches the workspace the runner derives (git rev-parse), with a pwd-P
  # fallback outside a git work tree.
  workspace="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
  # Capture the task/run start commit so downstream gates (e.g. doc-budget
  # completion-scope) can attribute only this run's authored changes. Empty on
  # first commit / detached pre-commit / outside a work tree -> consumers fall
  # back to their default (branch-cumulative) measurement.
  launch_base_commit="$(git -C "${workspace}" rev-parse HEAD 2>/dev/null || true)"

  if [ "${AI_AUTO_PRINCIPAL_LAUNCHER:-0}" != "1" ]; then
    echo "principal evidence can only be recorded by an AI_AUTO principal launcher" >&2
    return 2
  fi

  mkdir -p "${evidence_dir}"
  cat > "${evidence_file}" <<EVIDENCE
principal_runtime=${principal}
execution_mode=principal
source=ai-auto-principal-launcher
workspace=${workspace}
repo_local_allowed_actions=read_repo,edit_files,run_local_verify,write_artifacts
artifact_roots=.omx/state,.omx/plans,.omx/review-context,.omx/review-prompts,.omx/review-results,.omx/logs
launch_base_commit=${launch_base_commit}
created_at=$(date -Iseconds)
EVIDENCE
  # Bind the evidence to the out-of-tree HMAC key so a project plant of this gitignored file
  # cannot forge the active principal. Readers reject any evidence whose evidence_hmac does not
  # verify (fail closed to codex). The launcher holds the key, so it can write the HMAC.
  if principal_evidence_ensure_key; then
    _ev_hmac="$(principal_evidence_canonical "${principal}" "${workspace}" | principal_evidence_hmac)"
    if [ -n "${_ev_hmac}" ]; then printf 'evidence_hmac=%s\n' "${_ev_hmac}" >> "${evidence_file}"; fi
  fi
  echo "${evidence_file}"
}

# Print the validated task/run start commit for completion-scoped gates
# (doc-budget). Mirrors the review-gate launcher-evidence guard so a gate never
# trusts stale / manual / mismatched / symlinked evidence, and only emits a
# commit that is a real ancestor of HEAD (so it can never SILENTLY narrow a
# hard-fail to a non-ancestor base). Any failure -> no output + nonzero, so the
# caller falls back to its default (branch-cumulative) measurement.
completion_base_from_evidence() {
  local ev workspace lb
  workspace="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
  ev="${AI_AUTO_PRINCIPAL_EVIDENCE:-${workspace}/.omx/state/principal-runtime/current.env}"
  [ -f "${ev}" ] && [ ! -L "${ev}" ] || return 1
  grep -Fqx "execution_mode=principal" "${ev}" || return 1
  grep -Fqx "source=ai-auto-principal-launcher" "${ev}" || return 1
  grep -Fqx "workspace=${workspace}" "${ev}" || return 1
  lb="$(sed -n 's/^launch_base_commit=//p' "${ev}" | head -1)"
  [ -n "${lb}" ] || return 1
  git rev-parse --verify --quiet "${lb}^{commit}" >/dev/null 2>&1 || return 1
  git merge-base --is-ancestor "${lb}" HEAD 2>/dev/null || return 1
  printf '%s\n' "${lb}"
}

main() {
  local command="${1:-}"
  shift || true

  case "${command}" in
    normalize)
      normalize_principal "${1:-codex}"
      ;;
    reviewers)
      reviewers_for_principal "${1:-codex}"
      ;;
    profile)
      write_profile "${1:-codex}"
      ;;
    record-launch)
      record_launcher_evidence "${1:-codex}"
      ;;
    completion-base)
      completion_base_from_evidence
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      echo "unknown command: ${command}" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
