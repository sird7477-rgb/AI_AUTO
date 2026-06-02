#!/usr/bin/env bash
set -euo pipefail

# Safe, home-only Obsidian auto-push for shareable knowledge drafts.
#
# Collects validated knowledge drafts across the AI_AUTO home checkout plus the
# registered projects and pushes ONLY notes whose sync_class is shareable
# (shareable_summary / external_private_vault). local_private drafts are never
# pushed: they stay local by design. A secret/redaction preflight fails closed,
# so a mislabeled shareable note with secret-like content blocks the whole push
# instead of being silently skipped.
#
# Usage:
#   scripts/obsidian-autopush.sh [--dry-run] [--vault-dir PATH]
#
# Exit codes:
#   0  pushed (or nothing to do, or safely skipped: not home / no vault)
#   1  fail-closed: a shareable candidate failed validation (possible secret)
#   2  usage error

DRY_RUN=0
VAULT_OVERRIDE=""

usage() {
  cat <<'USAGE'
Usage: scripts/obsidian-autopush.sh [--dry-run] [--vault-dir PATH]

Push only shareable knowledge drafts (shareable_summary / external_private_vault)
from the AI_AUTO home checkout and registered projects to the configured vault.
local_private drafts are never pushed. A secret preflight fails closed.

  --dry-run         list shareable candidates and skipped private counts; no push
  --vault-dir PATH  override the vault dir (default: obsidian.ai_auto_vault_dir
                    from .omx/local-config.json)
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
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

# Build the explicit project list: home checkout plus registered repos.
PROJECTS=("${HOME_ROOT}")
if [ -f "${REGISTRY_FILE}" ]; then
  while IFS=$'\t' read -r _ts path _rest; do
    [ -n "${path}" ] || continue
    [ -d "${path}" ] || continue
    PROJECTS+=("${path}")
  done < "${REGISTRY_FILE}"
fi

# Secret/redaction preflight over shareable candidates (fail closed).
shareable_count=0
failed_notes=()
for project in "${PROJECTS[@]}"; do
  drafts_dir="${project}/.omx/knowledge/drafts"
  [ -d "${drafts_dir}" ] || continue
  while IFS= read -r note; do
    [ -n "${note}" ] || continue
    sync_class="$(sed -n 's/^sync_class:[[:space:]]*//p' "${note}" | head -1)"
    case "${sync_class}" in
      shareable_summary|external_private_vault)
        shareable_count=$((shareable_count + 1))
        if ! python3 "${KNOWLEDGE_NOTES}" validate "${note}" >/dev/null 2>&1; then
          failed_notes+=("${note}")
        fi
        ;;
    esac
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

project_args=()
for project in "${PROJECTS[@]}"; do
  project_args+=(--project "${project}")
done

# Push shareable only; local_private is skipped (reported), never pushed.
"${KNOWLEDGE_COLLECT}" --push --skip-disallowed-sync-class \
  --vault-dir "${VAULT_DIR}" "${project_args[@]}"
