#!/usr/bin/env bash
set -euo pipefail

# AI_AUTO template version hygiene gate (run from the repo root).
#
# Two checks:
#  1. Consistency: AI_AUTO_TEMPLATE_VERSION first line must equal the top
#     PATCH_NOTES.md `## <version>` heading.
#  2. Bump-on-change: if template-owned files (templates/automation-base/**,
#     excluding the version file and PATCH_NOTES.md) changed versus the
#     integration base, the version must be bumped (differ from the base). Since
#     check 1 forces the version to equal the top PATCH_NOTES heading, a bump
#     also guarantees a new patch-note entry. This is what stops a template
#     change from shipping without a PATCH_NOTES record.
#
# No-op outside the AI_AUTO source repo (an installed project has no template
# directory), and on the base branch itself (no diff to measure).

BASE_REF="${CHECK_TEMPLATE_BASE_REF:-main}"
VERSION_FILE="templates/automation-base/AI_AUTO_TEMPLATE_VERSION"
PATCH_NOTES="templates/automation-base/docs/PATCH_NOTES.md"

if [ ! -f "${VERSION_FILE}" ]; then
  # Not the AI_AUTO source repo (no template to govern).
  exit 0
fi

template_version="$(sed -n '1{s/\r$//; s/[[:space:]]*$//; p; q}' "${VERSION_FILE}")"
latest_patch_note="$(sed -n '/^## /{s/^## //; s/\r$//; s/[[:space:]]*$//; p; q}' "${PATCH_NOTES}" 2>/dev/null || true)"
echo "[check-template-version] version=${template_version:-<none>} latest_patch_note=${latest_patch_note:-<none>}"

# Check 1: consistency.
if [ -z "${template_version}" ] || [ -z "${latest_patch_note}" ] || [ "${latest_patch_note}" != "${template_version}" ]; then
  echo "[check-template-version] AI_AUTO_TEMPLATE_VERSION (${template_version:-<none>}) must match the top ${PATCH_NOTES} heading (got: ${latest_patch_note:-<none>})" >&2
  exit 1
fi

# Check 2: bump-on-change.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  base="$(git merge-base "${BASE_REF}" HEAD 2>/dev/null || true)"
  head="$(git rev-parse HEAD 2>/dev/null || true)"
  if [ -n "${base}" ] && [ "${base}" != "${head}" ]; then
    changed="$(git diff --name-only "${base}" -- templates/automation-base/ templates/domain-packs/ \
      ":(exclude)${VERSION_FILE}" ":(exclude)${PATCH_NOTES}" 2>/dev/null || true)"
    if [ -n "${changed}" ]; then
      base_version="$(git show "${base}:${VERSION_FILE}" 2>/dev/null | sed -n '1{s/\r$//; s/[[:space:]]*$//; p; q}' || true)"
      if [ -n "${base_version}" ] && [ "${template_version}" = "${base_version}" ]; then
        echo "[check-template-version] template-owned files changed vs ${BASE_REF} (${base}) without a version bump:" >&2
        printf '%s\n' "${changed}" | sed 's/^/  /' >&2
        echo "[check-template-version] bump ${VERSION_FILE} and add a matching '## <version>' entry to ${PATCH_NOTES}." >&2
        exit 1
      fi
    fi
  fi
fi

echo "[check-template-version] OK"
