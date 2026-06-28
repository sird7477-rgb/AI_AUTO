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
  local principal evidence_file evidence_dir workspace launch_base_commit
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
