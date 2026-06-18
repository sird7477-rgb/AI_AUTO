#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:-}"
AI_LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="${AI_LAB_ROOT}/templates/automation-base"

template_source_branch() {
  if [ -n "${AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE:-}" ]; then
    printf '%s\n' "${AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE}"
    return 0
  fi

  git -C "${AI_LAB_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown\n'
}

template_source_channel() {
  case "$1" in
    main)
      printf 'stable\n'
      ;;
    *)
      printf 'experimental\n'
      ;;
  esac
}

if [ -z "${TARGET_DIR}" ]; then
  echo "Usage: $0 /path/to/target-repo"
  exit 1
fi

if [ ! -d "${TARGET_DIR}" ]; then
  echo "Target directory does not exist: ${TARGET_DIR}"
  exit 1
fi

if ! git -C "${TARGET_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Target directory is not a git repository: ${TARGET_DIR}"
  exit 1
fi

if [ ! -d "${TEMPLATE_DIR}" ]; then
  echo "Template directory not found: ${TEMPLATE_DIR}"
  exit 1
fi

source_branch="$(template_source_branch)"
source_channel="$(template_source_channel "${source_branch}")"
if [ "${source_channel}" != "stable" ] && [ "${AI_AUTO_ALLOW_EXPERIMENTAL_TEMPLATE_SOURCE:-0}" != "1" ]; then
  echo "Refusing to install automation template from a non-stable AI_AUTO source."
  echo "source_branch: ${source_branch}"
  echo "source_channel: ${source_channel}"
  echo "target: ${TARGET_DIR}"
  echo "next_action: switch AI_AUTO to main, or perform a manual review-only merge."
  exit 3
fi

conflicts=()

for path in \
  "AI_AUTO_TEMPLATE_VERSION" \
  "AGENTS.md" \
  "docs/CHROME_CDP_ACCESS.md" \
  "docs/AI_AUTOMATION_TREND_HARDENING.md" \
  "docs/research/AI_AUTOMATION_TRENDS.md" \
  "docs/AI_RUNTIME_ADAPTERS.md" \
  "docs/AI_PRINCIPAL_RUNTIMES.md" \
  "docs/AI_MODEL_ROUTING.md" \
  "docs/AUTOMATION_OPERATING_POLICY.md" \
  "docs/DATA_COMPLETION.md" \
  "docs/DEPLOYMENT_COMPLETION.md" \
  "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" \
  "docs/DOMAIN_PACKS.md" \
  "docs/INTERVIEW_PLAN_LAYER.md" \
  "docs/INCIDENT_OPS.md" \
  "docs/OBSERVABILITY_COMPLETION.md" \
  "docs/OBSIDIAN_INTEGRATION.md" \
  "docs/PATCH_NOTES.md" \
  "docs/PERFORMANCE_COMPLETION.md" \
  "docs/PLANNING_VISUALIZATION_GUIDE.md" \
  "docs/SECURITY_COMPLETION.md" \
  "docs/SESSION_QUALITY_PLAN.md" \
  "docs/UI_COMPLETION.md" \
  "docs/WORKFLOW.md" \
  "scripts/archive-omx-artifacts.sh" \
  "scripts/ai-principal-runtime.sh" \
  "scripts/ai-runtime-adapter.sh" \
  "scripts/automation-doctor.sh" \
  "scripts/audit-obsidian-vault.py" \
  "scripts/benchmark-command.py" \
  "scripts/capture-knowledge-drafts.py" \
  "scripts/collect-odoo-docs-kb.py" \
  "scripts/collect-review-context.sh" \
  "scripts/docker-config-guard.sh" \
  "scripts/doc-budget.sh" \
  "scripts/guidance-duplicate-report.sh" \
  "scripts/discover-ai-models.sh" \
  "scripts/knowledge-notes.py" \
  "scripts/make-review-prompts.sh" \
  "scripts/record-feedback.sh" \
  "scripts/record-project-memory.sh" \
  "scripts/resolve-feedback.sh" \
  "scripts/validate-odoo-docs-kb.py" \
  "scripts/run-ai-reviews.sh" \
  "scripts/summarize-ai-reviews.sh" \
  "scripts/test-review-summary.sh" \
  "scripts/todo-report.py" \
  "scripts/review-gate.sh" \
  "scripts/write-session-checkpoint.sh" \
  "scripts/verify.sh"
do
  if [ -e "${TARGET_DIR}/${path}" ]; then
    conflicts+=("${path}")
  fi
done

if [ "${#conflicts[@]}" -gt 0 ]; then
  echo "Refusing to overwrite existing files:"
  printf ' - %s\n' "${conflicts[@]}"
  echo
  echo "This looks like an existing project or an already-initialized automation setup."
  echo "aiinit is intentionally stopping before it overwrites project instructions, docs, or verification scripts."
  echo
  echo "For an existing project, ask the AI:"
  echo "  기존 프로젝트에 자동화 기반을 병합 도입해줘."
  echo "  기존 AGENTS.md, docs, scripts/verify.sh는 덮어쓰지 말고 먼저 분석한 뒤"
  echo "  필요한 자동화 파일과 지침만 제안/반영해줘."
  echo "  그리고 먼저 git status --short로 untracked 상태를 확인해줘."
  echo
  echo "If this is a new project and these files are accidental, move or review them first, then rerun aiinit."
  exit 1
fi

mkdir -p "${TARGET_DIR}/.omx/reviewer-state" "${TARGET_DIR}/docs/research" "${TARGET_DIR}/scripts"

exclude_file="$(git -C "${TARGET_DIR}" rev-parse --git-path info/exclude 2>/dev/null || true)"
case "${exclude_file}" in
  "") exclude_file="${TARGET_DIR}/.git/info/exclude" ;;
  /*) : ;;
  *) exclude_file="${TARGET_DIR}/${exclude_file}" ;;
esac
mkdir -p "$(dirname "${exclude_file}")"
if ! grep -Eq '^[.]omx/?$' "${exclude_file}" 2>/dev/null; then
  {
    echo
    echo ".omx/"
  } >> "${exclude_file}"
fi

# Install worktree-safe git hooks into the target's real hooks dir. Resolve via
# rev-parse so linked worktrees land on the shared common-dir hooks path. These
# hooks unset GIT_* before running tests (preventing the multi-worktree git-state
# corruption that drove --no-verify) and warn on review-gate bypass; see
# templates/automation-base/hooks.
hooks_dir="$(git -C "${TARGET_DIR}" rev-parse --git-path hooks 2>/dev/null || true)"
if [ -n "${hooks_dir}" ]; then
  case "${hooks_dir}" in
    /*) : ;;
    *) hooks_dir="${TARGET_DIR}/${hooks_dir}" ;;
  esac
  mkdir -p "${hooks_dir}"
  for hook in pre-commit post-commit; do
    # Fail-closed on a pre-existing NON-AI_AUTO hook: never clobber a project's
    # own commit gate (consistent with aiinit's preflight that refuses to
    # overwrite existing project files). Leave it untouched, warn loudly, and
    # tell the operator to merge manually. Only write when there is no hook or
    # it is already an AI_AUTO hook (so re-install still updates our own).
    if [ -e "${hooks_dir}/${hook}" ] && ! grep -q "AI_AUTO worktree-safe hook\|AI_AUTO post-commit guard" "${hooks_dir}/${hook}" 2>/dev/null; then
      echo "[install] WARNING: existing custom ${hook} hook left untouched: ${hooks_dir}/${hook}" >&2
      echo "[install] AI_AUTO worktree-safe ${hook} was NOT installed; merge it manually from" >&2
      echo "[install]   ${TEMPLATE_DIR}/hooks/${hook}" >&2
      echo "[install]   (it unsets GIT_* before tests to prevent multi-worktree git corruption)." >&2
      continue
    fi
    cp "${TEMPLATE_DIR}/hooks/${hook}" "${hooks_dir}/${hook}"
    chmod +x "${hooks_dir}/${hook}"
  done
fi

cp "${TEMPLATE_DIR}/AGENTS.md" "${TARGET_DIR}/AGENTS.md"
cp "${TEMPLATE_DIR}/AI_AUTO_TEMPLATE_VERSION" "${TARGET_DIR}/AI_AUTO_TEMPLATE_VERSION"
cp "${TEMPLATE_DIR}/docs/CHROME_CDP_ACCESS.md" "${TARGET_DIR}/docs/CHROME_CDP_ACCESS.md"
cp "${TEMPLATE_DIR}/docs/AI_AUTOMATION_TREND_HARDENING.md" "${TARGET_DIR}/docs/AI_AUTOMATION_TREND_HARDENING.md"
cp "${TEMPLATE_DIR}/docs/research/AI_AUTOMATION_TRENDS.md" "${TARGET_DIR}/docs/research/AI_AUTOMATION_TRENDS.md"
cp "${TEMPLATE_DIR}/docs/AI_RUNTIME_ADAPTERS.md" "${TARGET_DIR}/docs/AI_RUNTIME_ADAPTERS.md"
cp "${TEMPLATE_DIR}/docs/AI_PRINCIPAL_RUNTIMES.md" "${TARGET_DIR}/docs/AI_PRINCIPAL_RUNTIMES.md"
cp "${TEMPLATE_DIR}/docs/AI_MODEL_ROUTING.md" "${TARGET_DIR}/docs/AI_MODEL_ROUTING.md"
cp "${TEMPLATE_DIR}/docs/AUTOMATION_OPERATING_POLICY.md" "${TARGET_DIR}/docs/AUTOMATION_OPERATING_POLICY.md"
cp "${TEMPLATE_DIR}/docs/DATA_COMPLETION.md" "${TARGET_DIR}/docs/DATA_COMPLETION.md"
cp "${TEMPLATE_DIR}/docs/DEPLOYMENT_COMPLETION.md" "${TARGET_DIR}/docs/DEPLOYMENT_COMPLETION.md"
cp "${TEMPLATE_DIR}/docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "${TARGET_DIR}/docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
cp "${TEMPLATE_DIR}/docs/DOMAIN_PACKS.md" "${TARGET_DIR}/docs/DOMAIN_PACKS.md"
cp "${TEMPLATE_DIR}/docs/INTERVIEW_PLAN_LAYER.md" "${TARGET_DIR}/docs/INTERVIEW_PLAN_LAYER.md"
cp "${TEMPLATE_DIR}/docs/INCIDENT_OPS.md" "${TARGET_DIR}/docs/INCIDENT_OPS.md"
cp "${TEMPLATE_DIR}/docs/OBSERVABILITY_COMPLETION.md" "${TARGET_DIR}/docs/OBSERVABILITY_COMPLETION.md"
cp "${TEMPLATE_DIR}/docs/OBSIDIAN_INTEGRATION.md" "${TARGET_DIR}/docs/OBSIDIAN_INTEGRATION.md"
cp "${TEMPLATE_DIR}/docs/PATCH_NOTES.md" "${TARGET_DIR}/docs/PATCH_NOTES.md"
cp "${TEMPLATE_DIR}/docs/PERFORMANCE_COMPLETION.md" "${TARGET_DIR}/docs/PERFORMANCE_COMPLETION.md"
cp "${TEMPLATE_DIR}/docs/PLANNING_VISUALIZATION_GUIDE.md" "${TARGET_DIR}/docs/PLANNING_VISUALIZATION_GUIDE.md"
cp "${TEMPLATE_DIR}/docs/SECURITY_COMPLETION.md" "${TARGET_DIR}/docs/SECURITY_COMPLETION.md"
cp "${TEMPLATE_DIR}/docs/SESSION_QUALITY_PLAN.md" "${TARGET_DIR}/docs/SESSION_QUALITY_PLAN.md"
cp "${TEMPLATE_DIR}/docs/UI_COMPLETION.md" "${TARGET_DIR}/docs/UI_COMPLETION.md"
cp "${TEMPLATE_DIR}/docs/WORKFLOW.md" "${TARGET_DIR}/docs/WORKFLOW.md"

cp "${TEMPLATE_DIR}/scripts/archive-omx-artifacts.sh" "${TARGET_DIR}/scripts/archive-omx-artifacts.sh"
cp "${TEMPLATE_DIR}/scripts/ai-principal-runtime.sh" "${TARGET_DIR}/scripts/ai-principal-runtime.sh"
cp "${TEMPLATE_DIR}/scripts/ai-runtime-adapter.sh" "${TARGET_DIR}/scripts/ai-runtime-adapter.sh"
cp "${TEMPLATE_DIR}/scripts/automation-doctor.sh" "${TARGET_DIR}/scripts/automation-doctor.sh"
cp "${TEMPLATE_DIR}/scripts/audit-obsidian-vault.py" "${TARGET_DIR}/scripts/audit-obsidian-vault.py"
cp "${TEMPLATE_DIR}/scripts/benchmark-command.py" "${TARGET_DIR}/scripts/benchmark-command.py"
cp "${TEMPLATE_DIR}/scripts/capture-knowledge-drafts.py" "${TARGET_DIR}/scripts/capture-knowledge-drafts.py"
cp "${TEMPLATE_DIR}/scripts/collect-odoo-docs-kb.py" "${TARGET_DIR}/scripts/collect-odoo-docs-kb.py"
cp "${TEMPLATE_DIR}/scripts/collect-review-context.sh" "${TARGET_DIR}/scripts/collect-review-context.sh"
cp "${TEMPLATE_DIR}/scripts/docker-config-guard.sh" "${TARGET_DIR}/scripts/docker-config-guard.sh"
cp "${TEMPLATE_DIR}/scripts/doc-budget.sh" "${TARGET_DIR}/scripts/doc-budget.sh"
cp "${TEMPLATE_DIR}/scripts/guidance-duplicate-report.sh" "${TARGET_DIR}/scripts/guidance-duplicate-report.sh"
cp "${TEMPLATE_DIR}/scripts/discover-ai-models.sh" "${TARGET_DIR}/scripts/discover-ai-models.sh"
cp "${TEMPLATE_DIR}/scripts/knowledge-notes.py" "${TARGET_DIR}/scripts/knowledge-notes.py"
cp "${TEMPLATE_DIR}/scripts/make-review-prompts.sh" "${TARGET_DIR}/scripts/make-review-prompts.sh"
cp "${TEMPLATE_DIR}/scripts/record-feedback.sh" "${TARGET_DIR}/scripts/record-feedback.sh"
cp "${TEMPLATE_DIR}/scripts/record-project-memory.sh" "${TARGET_DIR}/scripts/record-project-memory.sh"
cp "${TEMPLATE_DIR}/scripts/resolve-feedback.sh" "${TARGET_DIR}/scripts/resolve-feedback.sh"
cp "${TEMPLATE_DIR}/scripts/validate-odoo-docs-kb.py" "${TARGET_DIR}/scripts/validate-odoo-docs-kb.py"
cp "${TEMPLATE_DIR}/scripts/run-ai-reviews.sh" "${TARGET_DIR}/scripts/run-ai-reviews.sh"
cp "${TEMPLATE_DIR}/scripts/summarize-ai-reviews.sh" "${TARGET_DIR}/scripts/summarize-ai-reviews.sh"
cp "${TEMPLATE_DIR}/scripts/test-review-summary.sh" "${TARGET_DIR}/scripts/test-review-summary.sh"
cp "${TEMPLATE_DIR}/scripts/todo-report.py" "${TARGET_DIR}/scripts/todo-report.py"
cp "${TEMPLATE_DIR}/scripts/review-gate.sh" "${TARGET_DIR}/scripts/review-gate.sh"
cp "${TEMPLATE_DIR}/scripts/write-session-checkpoint.sh" "${TARGET_DIR}/scripts/write-session-checkpoint.sh"
cp "${TEMPLATE_DIR}/scripts/verify.example.sh" "${TARGET_DIR}/scripts/verify.sh"

# Record the install-time guidance baseline (tracked .ai-auto/guidance-baseline.sha256):
# the sha256 of every guidance doc just copied in, byte-identical to the template.
# doc-budget.sh reads this to exclude inherited-unchanged guidance from the absolute
# budget, so a derived project's budget measures only what it authors or changes.
# Shared with the template-update flow via refresh-guidance-baseline.sh.
"${AI_LAB_ROOT}/scripts/refresh-guidance-baseline.sh" "${TARGET_DIR}"

domain_packs_dir="$(dirname "${TEMPLATE_DIR}")/domain-packs"
if [ -d "${domain_packs_dir}" ]; then
  mkdir -p "${TARGET_DIR}/.omx/domain-packs"
  mkdir -p "${TARGET_DIR}/.omx/domain-packs/.manifest"
  for pack_dir in "${domain_packs_dir}"/*; do
    if [ ! -d "${pack_dir}" ]; then
      continue
    fi

    pack_name="$(basename "${pack_dir}")"
    target_pack_dir="${TARGET_DIR}/.omx/domain-packs/${pack_name}"
    if [ -e "${target_pack_dir}" ]; then
      echo "Preserving existing optional domain pack reference: ${target_pack_dir}"
      continue
    fi

    cp -R "${pack_dir}" "${target_pack_dir}"
    python3 - "${TARGET_DIR}" "${pack_name}" "${pack_dir}" "${TEMPLATE_DIR}/AI_AUTO_TEMPLATE_VERSION" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

target_dir = Path(sys.argv[1])
pack_name = sys.argv[2]
source_dir = Path(sys.argv[3])
version_file = Path(sys.argv[4])

files = {}
for path in sorted(source_dir.rglob("*")):
    if path.is_symlink():
        raise SystemExit(f"refusing symlink in domain pack: {path}")
    if path.is_file():
        rel = path.relative_to(source_dir).as_posix()
        files[rel] = hashlib.sha256(path.read_bytes()).hexdigest()

root_digest = hashlib.sha256()
for rel, digest in sorted(files.items()):
    root_digest.update(rel.encode("utf-8"))
    root_digest.update(b"\0")
    root_digest.update(digest.encode("ascii"))
    root_digest.update(b"\n")

manifest = {
    "schema": 1,
    "pack": pack_name,
    "source": f"templates/domain-packs/{pack_name}",
    "template_version": version_file.read_text(encoding="utf-8").strip(),
    "source_root_hash": root_digest.hexdigest(),
    "installed_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "files": files,
}
manifest_path = target_dir / ".omx/domain-packs/.manifest" / f"{pack_name}.json"
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
  done
fi

# Auto-install the Odoo domain-pack git hook(s) into Odoo projects (custom-addons present),
# non-destructively, so a freshly aiinit'd Odoo project gets the pre-push validation gate.
# The hook self-skips loudly until ODOO_HARNESS_DIR is configured, so this never blocks a
# project that has not set up the local harness yet.
odoo_hooks_dir="${domain_packs_dir}/odoo/hooks"
if [ -d "${odoo_hooks_dir}" ] && [ -d "${TARGET_DIR}/custom-addons" ]; then
  mkdir -p "${TARGET_DIR}/.githooks"
  for hook_src in "${odoo_hooks_dir}"/*; do
    [ -f "${hook_src}" ] || continue
    hook_dest="${TARGET_DIR}/.githooks/$(basename "${hook_src}")"
    if [ -e "${hook_dest}" ]; then
      echo "Preserving existing git hook: ${hook_dest}"
    else
      cp "${hook_src}" "${hook_dest}"
      chmod +x "${hook_dest}"
      echo "Installed Odoo git hook: ${hook_dest}"
    fi
  done
  # Co-install the docker-free static manifest screen next to the hook so the pre-push
  # gate can run it even when ODOO_HARNESS_DIR is unset. The heavy docker warm-base
  # harness still lives in ODOO_HARNESS_DIR; this one screen is tiny and dependency-free.
  mf_screen_src="${domain_packs_dir}/odoo/validation-harness/check-manifest-files.py"
  if [ -f "${mf_screen_src}" ]; then
    mf_screen_dest="${TARGET_DIR}/.githooks/check-manifest-files.py"
    if [ -e "${mf_screen_dest}" ]; then
      echo "Preserving existing git hook helper: ${mf_screen_dest}"
    else
      cp "${mf_screen_src}" "${mf_screen_dest}"
      chmod +x "${mf_screen_dest}"
      echo "Installed Odoo manifest screen: ${mf_screen_dest}"
    fi
  fi
  if git -C "${TARGET_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -z "$(git -C "${TARGET_DIR}" config --local core.hooksPath 2>/dev/null)" ]; then
      git -C "${TARGET_DIR}" config --local core.hooksPath .githooks \
        && echo "Set core.hooksPath=.githooks (Odoo validation hook active)"
    else
      echo "Note: core.hooksPath already set; ensure it points at .githooks for the Odoo hook to run"
    fi
  else
    echo "Note: ${TARGET_DIR} is not a git repo; installed .githooks/ but did not set core.hooksPath"
  fi
fi

for script_path in "${TARGET_DIR}"/scripts/*.sh "${TARGET_DIR}"/scripts/*.py; do
  [ -e "${script_path}" ] || continue
  chmod +x "${script_path}"
done

# Record the project's domain profile (machine-local .omx/project-profile.json) for detected
# domains (currently Odoo). No-op for projects with no known domain. Read by the domain-gated
# retrieval hook; advisory metadata only.
if [ -x "${AI_LAB_ROOT}/tools/ai-project-profile" ]; then
  if "${AI_LAB_ROOT}/tools/ai-project-profile" write "${TARGET_DIR}" >/dev/null 2>&1; then
    echo "Recorded project domain profile: ${TARGET_DIR}/.omx/project-profile.json"
  fi
fi

echo "Automation template installed into: ${TARGET_DIR}"
echo "Local git exclude updated for .omx/ runtime artifacts."
if [ -d "${TARGET_DIR}/.omx/domain-packs" ]; then
  echo "Optional domain packs installed for onboarding reference: ${TARGET_DIR}/.omx/domain-packs"
fi
echo
echo "Next steps:"
echo "1. Interview the project owner for purpose, scope, stack, and completion criteria."
echo "2. Use docs/INTERVIEW_PLAN_LAYER.md to keep onboarding questions narrow, mapped, and gated."
echo "3. Confirm review intensity, feedback recording, approval-friction handling, subagent usage, resource-aware parallelism, and planning/interview intensity."
echo "4. Confirm operational readiness fail-closed rules, sandbox-vs-real-network evidence, Incident Ops monitoring/reporting, plan/TODO reconciliation, spec/design alignment, user-facing Korean report language, and AGENTS.md vs linked-docs split."
echo "5. Use ai-auto-template-status later to compare this project with newer AI_AUTO templates; review differences manually before patching."
echo "6. Select applicable completion packs under ${TARGET_DIR}/docs/*_COMPLETION.md."
echo "7. Use ${TARGET_DIR}/docs/DOMAIN_PACKS.md to check ${TARGET_DIR}/.omx/domain-packs for any applicable optional domain pack."
echo "8. Use ${TARGET_DIR}/docs/DOMAIN_PACK_AUTHORING_GUIDE.md only when creating or changing reusable domain packs."
echo "9. Use ${TARGET_DIR}/docs/OBSIDIAN_INTEGRATION.md and ${TARGET_DIR}/scripts/knowledge-notes.py for sanitized debugging notes, work-review notes, and technical references."
echo "10. Update ${TARGET_DIR}/AGENTS.md and ${TARGET_DIR}/docs/WORKFLOW.md for the target project."
echo "11. Customize ${TARGET_DIR}/scripts/verify.sh with project-specific checks while preserving useful template safeguards such as ${TARGET_DIR}/scripts/doc-budget.sh and ${TARGET_DIR}/scripts/guidance-duplicate-report.sh."
echo "12. Run:"
echo "   cd ${TARGET_DIR}"
echo "   ./scripts/automation-doctor.sh"
echo "   ./scripts/verify.sh"
echo "   ./scripts/review-gate.sh"
echo
echo "Next AI request:"
echo "  프로젝트 초기설정 해줘"
echo
echo "Equivalent detailed request:"
echo "  프로젝트 요구사항을 인터뷰하고, docs/*_COMPLETION.md 완료팩과"
echo "  .omx/domain-packs/에 설치된 도메인팩 중 적용할 항목이 있는지 확정한 뒤,"
echo "  리뷰 강도, 실패 패턴 기록, 승인 마찰 관리, 서브에이전트 사용 기준,"
echo "  docs/INTERVIEW_PLAN_LAYER.md 기준의 플랜/인터뷰 강도 기준과 질문 범위,"
echo "  운영 준비 fail-closed 기준,"
echo "  sandbox-vs-real-network evidence 기준, Incident Ops 감시/주기보고 기준,"
echo "  plan index/TODO reconciliation 기준, spec/design alignment 기준,"
echo "  사용자 보고를 쉬운 한국어로 먼저 작성하는 기준,"
echo "  AGENTS.md와 linked docs 분리 기준을 정하고"
echo "  AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 프로젝트에 맞게 설정해줘"
