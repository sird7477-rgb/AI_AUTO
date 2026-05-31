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

record_launcher_evidence() {
  local principal evidence_file evidence_dir workspace
  principal="$(normalize_principal "${1:-codex}")"
  evidence_file="$(evidence_path)"
  evidence_dir="$(dirname -- "${evidence_file}")"
  workspace="$(pwd -P)"

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
created_at=$(date -Iseconds)
EVIDENCE
  echo "${evidence_file}"
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
