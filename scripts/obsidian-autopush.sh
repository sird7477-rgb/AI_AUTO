#!/usr/bin/env bash
set -euo pipefail

# Safe, home-only Obsidian auto-push for shareable knowledge drafts.
#
# Collects validated knowledge drafts across the AI_AUTO home checkout plus the
# registered projects and pushes ONLY shareable notes. By default it also
# auto-promotes local_private drafts to shareable_summary by rule: the draft's
# surface must be on the allowlist and the note must be sanitized and pass the
# secret/redaction preflight. Anything off the allowlist (or unsanitized, or
# secret-like) stays local_private and is never pushed. A secret preflight fails
# closed, so a mislabeled candidate with secret-like content blocks the whole
# push instead of being silently skipped.
#
# Usage:
#   scripts/obsidian-autopush.sh [--dry-run] [--no-auto-promote] [--vault-dir PATH]
#
# Exit codes:
#   0  pushed (or nothing to do, or safely skipped: not home / no vault)
#   1  fail-closed: a shareable candidate failed validation (possible secret)
#   2  usage error

DRY_RUN=0
VAULT_OVERRIDE=""
AUTO_PROMOTE=1
# Surfaces whose local_private drafts may be auto-promoted to shareable_summary.
# AI_AUTO tooling surfaces only; project-specific surfaces are intentionally off
# the list (default-deny). Override with AI_AUTO_AUTOPROMOTE_SURFACES.
AUTOPROMOTE_SURFACES="${AI_AUTO_AUTOPROMOTE_SURFACES:-review-gate,workflow,ai-review,model-routing,ai-auto-template,domain-pack,obsidian,shell-integration,verification,browser-verification}"

usage() {
  cat <<'USAGE'
Usage: scripts/obsidian-autopush.sh [--dry-run] [--vault-dir PATH]

Publish shareable knowledge drafts from the AI_AUTO home checkout and registered
projects to the configured vault. By default it auto-promotes local_private
drafts to shareable_summary when their surface is on the allowlist and they are
sanitized; off-allowlist, unsanitized, or secret-like drafts stay local. A secret
preflight fails closed.

  --dry-run          list publish candidates and skipped counts; no push
  --no-auto-promote  do not auto-promote local_private drafts; publish only notes
                     already classified shareable
  --vault-dir PATH   override the vault dir (default: obsidian.ai_auto_vault_dir
                     from .omx/local-config.json)

Allowlist: AI_AUTO_AUTOPROMOTE_SURFACES (comma-separated) overrides the default
AI_AUTO tooling-surface set.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --no-auto-promote)
      AUTO_PROMOTE=0
      ;;
    --vault-dir)
      VAULT_OVERRIDE="${2:-}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[obsidian-autopush] unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOME_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"

# Home-checkout guard: only the AI_AUTO home repo collects and pushes centrally.
if [ -z "${HOME_ROOT}" ] || [ ! -f "${HOME_ROOT}/templates/automation-base/AI_AUTO_TEMPLATE_VERSION" ]; then
  echo "[obsidian-autopush] skip: not the AI_AUTO home checkout"
  exit 0
fi

KNOWLEDGE_COLLECT="${HOME_ROOT}/tools/knowledge-collect"
KNOWLEDGE_NOTES="${HOME_ROOT}/scripts/knowledge-notes.py"
LOCAL_CONFIG="${HOME_ROOT}/.omx/local-config.json"
REGISTRY_FILE="${AI_AUTO_PROJECT_REGISTRY_FILE:-${HOME}/.local/state/ai-auto/projects.tsv}"

# Resolve the vault dir from local-config.json unless overridden.
VAULT_DIR="${VAULT_OVERRIDE}"
if [ -z "${VAULT_DIR}" ] && [ -f "${LOCAL_CONFIG}" ]; then
  VAULT_DIR="$(python3 - "${LOCAL_CONFIG}" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    sys.exit(0)
obsidian = data.get("obsidian") or {}
value = obsidian.get("ai_auto_vault_dir") or ""
print(value)
PY
)"
fi

if [ -z "${VAULT_DIR}" ] || [ ! -d "${VAULT_DIR}" ]; then
  echo "[obsidian-autopush] skip: vault not configured (obsidian.ai_auto_vault_dir in ${LOCAL_CONFIG})"
  exit 0
fi

# Vault preflight (Stage 1A.2): fail loud rather than push into a non-writable vault, and WARN
# when a more-recently-touched AI_AUTO_Vault exists on a sibling drive — the config-drift class
# found 2026-06-11 (config pointed at /mnt/c while the live vault was /mnt/z). The configured
# vault is still honoured; the warning surfaces a likely stale-config so it is never silent.
if [ ! -w "${VAULT_DIR}" ]; then
  echo "[obsidian-autopush] FAIL: configured vault is not writable: ${VAULT_DIR}" >&2
  exit 1
fi
case "${VAULT_DIR}" in
  /mnt/*/*)
    cur_drive="$(printf '%s' "${VAULT_DIR}" | cut -d/ -f3)"
    vault_rel="${VAULT_DIR#/mnt/"${cur_drive}"/}"
    ref_file="${VAULT_DIR}/AI_AUTO_INDEX.md"
    [ -f "${ref_file}" ] || ref_file="${VAULT_DIR}"
    for drive_dir in /mnt/*/; do
      other_drive="$(basename "${drive_dir}")"
      [ "${other_drive}" = "${cur_drive}" ] && continue
      cand="/mnt/${other_drive}/${vault_rel}"
      [ -d "${cand}" ] || continue
      cand_file="${cand}/AI_AUTO_INDEX.md"
      [ -f "${cand_file}" ] || cand_file="${cand}"
      if [ "${cand_file}" -nt "${ref_file}" ]; then
        echo "[obsidian-autopush] WARNING: a more recently modified AI_AUTO_Vault exists on another drive:" >&2
        echo "    configured (push target): ${VAULT_DIR}" >&2
        echo "    more recent:              ${cand}" >&2
        echo "    If the configured vault is stale, fix obsidian.ai_auto_vault_dir in ${LOCAL_CONFIG} before pushing." >&2
      fi
    done
    ;;
esac

# Build the explicit project list: home checkout plus registered repos.
PROJECTS=("${HOME_ROOT}")
if [ -f "${REGISTRY_FILE}" ]; then
  while IFS=$'\t' read -r _ts path _rest; do
    [ -n "${path}" ] || continue
    [ -d "${path}" ] || continue
    PROJECTS+=("${path}")
  done < "${REGISTRY_FILE}"
fi

# Read one frontmatter value, tolerating surrounding quotes (knowledge-collect's
# Python YAML parser ignores them, so the shell preflight must match).
fm_value() {
  local key="$1" file="$2" value
  value="$(sed -n "s/^${key}:[[:space:]]*//p" "${file}" | head -1)"
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  printf '%s' "${value}"
}

# Allowlist match, ignoring spaces so "review-gate, workflow" works like the
# Python side which strips each entry.
AUTOPROMOTE_SURFACES_NORM="${AUTOPROMOTE_SURFACES// /}"
surface_allowed() {
  local needle="$1"
  case ",${AUTOPROMOTE_SURFACES_NORM}," in
    *",${needle},"*) return 0 ;;
  esac
  return 1
}

# Secret/redaction preflight over publish candidates (fail closed). A candidate
# is a note that will be pushed: already shareable, or a local_private draft that
# auto-promotion will reclassify (allowlisted surface + sanitized).
shareable_count=0
failed_notes=()
for project in "${PROJECTS[@]}"; do
  drafts_dir="${project}/.omx/knowledge/drafts"
  [ -d "${drafts_dir}" ] || continue
  while IFS= read -r note; do
    [ -n "${note}" ] || continue
    sync_class="$(fm_value sync_class "${note}")"
    is_candidate=0
    case "${sync_class}" in
      shareable_summary|external_private_vault)
        is_candidate=1
        ;;
      local_private)
        if [ "${AUTO_PROMOTE}" -eq 1 ]; then
          surface="$(fm_value surface "${note}")"
          redaction="$(fm_value redaction_status "${note}")"
          if [ "${redaction}" = "sanitized" ] && surface_allowed "${surface}"; then
            is_candidate=1
          fi
        fi
        ;;
    esac
    if [ "${is_candidate}" -eq 1 ]; then
      shareable_count=$((shareable_count + 1))
      if ! python3 "${KNOWLEDGE_NOTES}" validate "${note}" >/dev/null 2>&1; then
        failed_notes+=("${note}")
      fi
    fi
  done < <(find "${drafts_dir}" -maxdepth 1 -type f -name '*.md' ! -name 'AI_AUTO_INDEX.md' 2>/dev/null | sort)
done

if [ "${#failed_notes[@]}" -gt 0 ]; then
  echo "[obsidian-autopush] FAIL-CLOSED: ${#failed_notes[@]} shareable note(s) failed validation (possible secret/redaction issue); nothing pushed:" >&2
  for note in "${failed_notes[@]}"; do
    echo "[obsidian-autopush]   - ${note}" >&2
  done
  exit 1
fi

echo "[obsidian-autopush] vault: ${VAULT_DIR}"
echo "[obsidian-autopush] shareable candidates: ${shareable_count} across ${#PROJECTS[@]} project(s)"

# Nothing shareable: do not invoke the push at all, so the vault (including its
# index) is left untouched when only local_private drafts are pending.
if [ "${shareable_count}" -eq 0 ]; then
  echo "[obsidian-autopush] nothing to push: no shareable drafts (local_private stays local)"
  exit 0
fi

if [ "${DRY_RUN}" -eq 1 ]; then
  echo "[obsidian-autopush] dry-run: would push shareable notes; local_private stays local"
  exit 0
fi

push_args=(--push --skip-disallowed-sync-class --vault-dir "${VAULT_DIR}")
if [ "${AUTO_PROMOTE}" -eq 1 ]; then
  push_args+=(--auto-promote-shareable --promote-surfaces "${AUTOPROMOTE_SURFACES}")
fi
for project in "${PROJECTS[@]}"; do
  push_args+=(--project "${project}")
done

# Push shareable (and rule-promoted) drafts; local_private off the allowlist is
# skipped (reported), never pushed.
"${KNOWLEDGE_COLLECT}" "${push_args[@]}"
