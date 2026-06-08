#!/usr/bin/env bash
set -euo pipefail

repo_root="$(pwd)"

echo "[verify] running pytest..."
.venv/bin/python -m pytest -q

echo "[verify] checking shell script syntax..."
for script in \
  scripts/bootstrap-ai-lab.sh \
  scripts/archive-omx-artifacts.sh \
  scripts/ai-principal-runtime.sh \
  scripts/ai-runtime-adapter.sh \
  scripts/automation-doctor.sh \
  scripts/collect-review-context.sh \
  scripts/docker-config-guard.sh \
  scripts/doc-budget.sh \
  scripts/guidance-duplicate-report.sh \
  scripts/discover-ai-models.sh \
  scripts/install-ubuntu-prereqs.sh \
  scripts/install-global-files.sh \
  scripts/install-automation-template.sh \
  scripts/make-review-prompts.sh \
  scripts/record-feedback.sh \
  scripts/record-project-memory.sh \
  scripts/resolve-feedback.sh \
  scripts/review-gate.sh \
  scripts/run-ai-reviews.sh \
  scripts/summarize-ai-reviews.sh \
  scripts/test-review-summary.sh \
  scripts/verify-machinery.sh \
  scripts/write-session-checkpoint.sh \
  templates/automation-base/scripts/archive-omx-artifacts.sh \
  templates/automation-base/scripts/ai-principal-runtime.sh \
  templates/automation-base/scripts/ai-runtime-adapter.sh \
  templates/automation-base/scripts/automation-doctor.sh \
  templates/automation-base/scripts/collect-review-context.sh \
  templates/automation-base/scripts/docker-config-guard.sh \
  templates/automation-base/scripts/doc-budget.sh \
  templates/automation-base/scripts/guidance-duplicate-report.sh \
  templates/automation-base/scripts/discover-ai-models.sh \
  templates/automation-base/scripts/make-review-prompts.sh \
  templates/automation-base/scripts/record-feedback.sh \
  templates/automation-base/scripts/record-project-memory.sh \
  templates/automation-base/scripts/resolve-feedback.sh \
  templates/automation-base/scripts/review-gate.sh \
  templates/automation-base/scripts/run-ai-reviews.sh \
  templates/automation-base/scripts/summarize-ai-reviews.sh \
  templates/automation-base/scripts/test-review-summary.sh \
  templates/automation-base/scripts/verify-machinery.sh \
  templates/automation-base/scripts/write-session-checkpoint.sh \
  templates/automation-base/scripts/verify.example.sh
do
  bash -n "${script}"
done
shellcheck -S warning scripts/*.sh templates/automation-base/scripts/*.sh
# Global helper commands in tools/ are extensionless scripts that the
# scripts/*.sh glob above cannot reach, yet they are the code installed onto
# other machines. Discover them by shebang so adding, removing, or renaming a
# tool never silently bypasses linting and never breaks a hardcoded list.
tools_shell=()
tools_python=()
while IFS= read -r tool; do
  # Read the shebang with head: a bare `read` returns non-zero on a file whose
  # only line has no trailing newline and would then discard the line, silently
  # skipping linting. head classifies such files correctly.
  shebang="$(head -n1 "${tool}")"
  case "${shebang}" in
    *python*) tools_python+=("${tool}") ;;
    *sh*) tools_shell+=("${tool}") ;;
  esac
done < <(git ls-files tools | sort)
if [ "${#tools_shell[@]}" -gt 0 ]; then
  shellcheck -S warning "${tools_shell[@]}"
  for tool in "${tools_shell[@]}"; do
    bash -n "${tool}"
  done
fi
for tool in "${tools_python[@]}"; do
  python3 -m py_compile "${tool}"
done
python3 -m py_compile scripts/benchmark-command.py
python3 -m py_compile scripts/todo-report.py
python3 -m py_compile scripts/capture-knowledge-drafts.py
python3 -m py_compile scripts/knowledge-notes.py
python3 -m py_compile scripts/validate-odoo-kb.py
python3 -m py_compile scripts/validate-odoo-docs-kb.py
python3 -m py_compile scripts/record-lane-decision.py
python3 -m py_compile scripts/micro_work_contracts.py
python3 -m py_compile tools/ai-domain-pack
python3 -m py_compile tools/micro-work
python3 -m py_compile templates/automation-base/scripts/benchmark-command.py
python3 -m py_compile templates/automation-base/scripts/todo-report.py
python3 -m py_compile templates/automation-base/scripts/capture-knowledge-drafts.py
python3 -m py_compile templates/automation-base/scripts/knowledge-notes.py
python3 -m py_compile templates/automation-base/scripts/validate-odoo-docs-kb.py
python3 -m py_compile templates/automation-base/scripts/record-lane-decision.py

echo "[verify] checking secret hygiene..."
# Secret-bearing files must stay untracked. .gitignore already excludes them,
# but a single broken ignore rule would otherwise commit credentials with no
# guard. This check has no external dependency: it asks git what is tracked.
# The :(glob)**/ prefix matches at any depth so a secret committed in a
# subdirectory (e.g. config/.env) cannot slip past a root-anchored pattern.
tracked_secrets="$(
  git ls-files -- \
    ':(glob)**/.env' ':(glob)**/.env.*' \
    ':(glob)**/*.pem' ':(glob)**/*.key' ':(glob)**/*.p12' ':(glob)**/*.pfx' \
    ':(glob)**/id_rsa' ':(glob)**/id_rsa.*' \
    ':(glob)**/*.sqlite3' \
    | grep -vE '(^|/)\.env\.example$' || true
)"
if [ -n "${tracked_secrets}" ]; then
  echo "[verify] ERROR: secret-like files are tracked by git:" >&2
  printf '  %s\n' ${tracked_secrets} >&2
  echo "[verify] remove them from the index and confirm .gitignore covers them" >&2
  exit 1
fi
if command -v gitleaks >/dev/null 2>&1; then
  echo "[verify] running gitleaks deep secret scan..."
  gitleaks detect --no-banner --redact --exit-code 1
else
  echo "[verify] gitleaks not installed; tracked-file guard only (install gitleaks for deep scan)"
fi

echo "[verify] checking python security tooling..."
# Scan the tracked repo-root application modules rather than a hardcoded list,
# so renaming or adding a top-level module keeps the scan in sync with the code
# and a removed module never breaks the gate with a missing path.
mapfile -t python_security_targets < <(git ls-files -- '*.py' | grep -vE '/')
if command -v bandit >/dev/null 2>&1; then
  if [ "${#python_security_targets[@]}" -gt 0 ]; then
    echo "[verify] running bandit static security scan..."
    bandit -q -ll "${python_security_targets[@]}"
  fi
else
  echo "[verify] bandit not installed; skipping python static security scan (optional)"
fi
if command -v pip-audit >/dev/null 2>&1; then
  echo "[verify] running pip-audit dependency audit..."
  pip-audit -r requirements.txt || echo "[verify] WARNING: pip-audit reported advisories (review above)"
else
  echo "[verify] pip-audit not installed; skipping dependency vulnerability audit (optional)"
fi

echo "[verify] checking canonical TODO report..."
python3 scripts/todo-report.py --fail-on-active >/dev/null

echo "[verify] testing GStack contract helper..."
python3 - <<'PY'
import json
import subprocess
import sys

cases = [
    (
        "product",
        {
            "flags": ["strategic"],
            "problem": "broad rebuild",
            "smallest_wedge": "contract only",
            "non_goals": ["runtime"],
            "risks": ["scope"],
            "acceptance_evidence": ["tests"],
            "decision": "narrow",
        },
        True,
        "product_challenge_ready",
    ),
    (
        "browser-qa",
        {
            "route": "/todos",
            "viewports": ["desktop"],
            "screenshots": ["desktop.png"],
            "console_checked": True,
            "network_checked": True,
            "user_path": "open list",
            "regression_decision": "smoke",
            "mode": "report_only",
            "source_of_truth": "user_template",
        },
        True,
        "browser_qa_ready",
    ),
    (
        "retro",
        {
            "repeated_failure": "late finding",
            "gate_caught": "review-gate",
            "gate_missed": "manual artifact sync",
            "evidence": "review note",
            "proposed_update": "add sync check",
        },
        True,
        "retro_draft_ready",
    ),
    (
        "persona",
        {
            "requested_lenses": ["product"],
            "task_shapes": ["broad_product_work"],
        },
        True,
        "persona_lenses_ready",
    ),
    (
        "security-release",
        {"triggers": ["tokens"]},
        True,
        "security_release_ops_ready",
    ),
    (
        "parallel",
        {
            "research_only": True,
            "worktree_owner": "owner",
            "branch_owner": "branch",
            "conductor": "integrator",
            "integration_gate": "review-gate",
            "lock_strategy": "exclusive",
            "duplicate_draft_strategy": "dedupe",
            "reviewer_coverage": "defined",
        },
        True,
        "parallel_conductor_contract_ready",
    ),
    (
        "browser-qa",
        {"route": "/todos"},
        False,
        "missing_browser_qa_evidence",
    ),
]

for name, payload, accepted, reason in cases:
    proc = subprocess.run(
        ["tools/ai-gstack-contract", name],
        input=json.dumps(payload),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    try:
        output = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        print(f"invalid JSON from ai-gstack-contract {name}: {exc}", file=sys.stderr)
        print(proc.stdout, file=sys.stderr)
        sys.exit(1)
    if output.get("accepted") is not accepted or output.get("reason") != reason:
        print(f"unexpected ai-gstack-contract result for {name}: {output}", file=sys.stderr)
        sys.exit(1)
    if accepted and proc.returncode != 0:
        print(f"accepted ai-gstack-contract case failed for {name}: {proc.stderr}", file=sys.stderr)
        sys.exit(1)
    if not accepted and proc.returncode == 0:
        print(f"rejected ai-gstack-contract case exited 0 for {name}", file=sys.stderr)
        sys.exit(1)

invalid = subprocess.run(
    ["tools/ai-gstack-contract", "product"],
    input="{",
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    check=False,
)
try:
    invalid_output = json.loads(invalid.stdout)
except json.JSONDecodeError as exc:
    print(f"invalid JSON case did not return JSON: {exc}", file=sys.stderr)
    print(invalid.stdout, file=sys.stderr)
    sys.exit(1)
if invalid.returncode == 0 or invalid_output.get("reason") != "invalid_json":
    print(f"unexpected invalid JSON result: rc={invalid.returncode} out={invalid_output}", file=sys.stderr)
    sys.exit(1)
PY

echo "[verify] checking Playwright CDP safety guidance..."
for ui_completion_doc in \
  docs/UI_COMPLETION.md \
  templates/automation-base/docs/UI_COMPLETION.md
do
  grep -q "Playwright CDP Access" "${ui_completion_doc}"
  grep -q "credential-equivalent" "${ui_completion_doc}"
  grep -q "docs/CHROME_CDP_ACCESS.md" "${ui_completion_doc}"
done
grep -q "Chrome CDP Access" docs/CHROME_CDP_ACCESS.md
grep -q "credential-equivalent" docs/CHROME_CDP_ACCESS.md
grep -q "project-owned wrapper scripts" docs/CHROME_CDP_ACCESS.md
cmp -s docs/CHROME_CDP_ACCESS.md templates/automation-base/docs/CHROME_CDP_ACCESS.md
cmp -s docs/OBSIDIAN_INTEGRATION.md templates/automation-base/docs/OBSIDIAN_INTEGRATION.md
cmp -s docs/PLANNING_VISUALIZATION_GUIDE.md templates/automation-base/docs/PLANNING_VISUALIZATION_GUIDE.md

echo "[verify] checking guidance document budget..."
./scripts/doc-budget.sh

echo "[verify] checking Codex native goal mode boundary guidance..."
(
  goal_boundary_tmp="$(mktemp -d)"
  cleanup_goal_boundary_tmp() {
    rm -rf "${goal_boundary_tmp}"
  }
  trap cleanup_goal_boundary_tmp EXIT

  extract_goal_boundary_section() {
    awk '
      /^## [0-9]+\. Codex Native Goal Mode Boundary$/ { printing = 1 }
      printing && /^## [0-9]+\. / && !/^## [0-9]+\. Codex Native Goal Mode Boundary$/ { exit }
      printing { print }
    ' "$1"
  }
  extract_goal_boundary_section docs/SESSION_QUALITY_PLAN.md \
    > "${goal_boundary_tmp}/root.md"
  extract_goal_boundary_section templates/automation-base/docs/SESSION_QUALITY_PLAN.md \
    > "${goal_boundary_tmp}/template.md"
  test -s "${goal_boundary_tmp}/root.md"
  test -s "${goal_boundary_tmp}/template.md"
  grep -qF "Codex Native Goal Mode Boundary" "${goal_boundary_tmp}/root.md"
  grep -qF "State authority matrix" "${goal_boundary_tmp}/root.md"
  grep -qF "AI_AUTO/OMX state" "${goal_boundary_tmp}/root.md"
  grep -qF ".omx/state/session-checkpoint.md" "${goal_boundary_tmp}/root.md"
  grep -qF "update_goal" "${goal_boundary_tmp}/root.md"
  diff -u "${goal_boundary_tmp}/root.md" "${goal_boundary_tmp}/template.md"
)

template_version="$(
  sed -n '1{s/\r$//; s/[[:space:]]*$//; p; q}' templates/automation-base/AI_AUTO_TEMPLATE_VERSION
)"
latest_patch_note="$(
  sed -n '/^## /{s/^## //; s/\r$//; s/[[:space:]]*$//; p; q}' templates/automation-base/docs/PATCH_NOTES.md
)"
echo "[verify] latest template patch note: ${latest_patch_note:-<none>}"
if test -z "${template_version}" || test -z "${latest_patch_note}" || test "${latest_patch_note}" != "${template_version}"; then
  echo "[verify] template version ${template_version:-<none>} must match the top PATCH_NOTES heading (got: ${latest_patch_note:-<none>})" >&2
  exit 1
fi
grep -qF "When the user asks \`AI_AUTO 최신 패치 적용해줘\`" AGENTS.md
grep -qF "When the user asks \`AI_AUTO 최신 패치 적용해줘\`" templates/automation-base/AGENTS.md
grep -qF "action: AI_AUTO 최신 패치 적용해줘" docs/GLOBAL_TOOLS.md
grep -qF "action: AI_AUTO 최신 패치 적용해줘" docs/NEW_PROJECT_GUIDE.md

echo "[verify] testing guidance document budget accounting..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_doc_budget_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_doc_budget_tmp EXIT

  git -c init.defaultBranch=main init -q "${tmp_dir}"
  cd "${tmp_dir}"
  mkdir -p docs templates/automation-base/docs scripts
  printf '# Agents\n' > AGENTS.md
  printf '# Workflow\n' > docs/WORKFLOW.md
  printf '# Policy\n' > docs/AUTOMATION_OPERATING_POLICY.md
  printf '# Template Agents\n' > templates/automation-base/AGENTS.md
  printf '# Template Readme\n' > templates/automation-base/README.md
  printf '# Template Workflow\n' > templates/automation-base/docs/WORKFLOW.md
  printf '# Template Policy\n' > templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md
  cp "${repo_root}/scripts/doc-budget.sh" scripts/doc-budget.sh
  cp "${repo_root}/scripts/guidance-duplicate-report.sh" scripts/guidance-duplicate-report.sh
  chmod +x scripts/doc-budget.sh
  chmod +x scripts/guidance-duplicate-report.sh
  git add .
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m "seed doc budget fixture"

  printf 'unstaged guidance line\n' >> AGENTS.md
  printf 'staged guidance line\n' >> docs/WORKFLOW.md
  git add docs/WORKFLOW.md
  printf 'new guidance line\n' > docs/NEW_GUIDE.md

  ./scripts/doc-budget.sh > "${tmp_dir}/budget.out"
  grep -q "current guidance diff added lines: 3" "${tmp_dir}/budget.out"
  grep -q "current guidance diff net added lines: 3" "${tmp_dir}/budget.out"

  printf 'new spaced guidance line\n' > "docs/SPACE GUIDE.md"
  ./scripts/doc-budget.sh > "${tmp_dir}/budget-space.out"
  grep -q "current guidance diff added lines: 4" "${tmp_dir}/budget-space.out"
  grep -q "current guidance diff net added lines: 4" "${tmp_dir}/budget-space.out"

  # Content/spec docs in a subdirectory are exempt: a 50-line spec table must not
  # change the net (stays 4, not 54).
  mkdir -p docs/specs
  : > docs/specs/big.md
  for i in $(seq 1 50); do
    printf 'spec table row %s\n' "$i" >> docs/specs/big.md
  done
  ./scripts/doc-budget.sh > "${tmp_dir}/budget-exempt.out"
  grep -q "current guidance diff net added lines: 4" "${tmp_dir}/budget-exempt.out"
  # DOC_BUDGET_EXEMPT_GLOBS can exempt a top-level doc too (drops NEW_GUIDE: 4 -> 3).
  DOC_BUDGET_EXEMPT_GLOBS='docs/NEW_GUIDE.md' ./scripts/doc-budget.sh > "${tmp_dir}/budget-exempt-glob.out"
  grep -q "current guidance diff net added lines: 3" "${tmp_dir}/budget-exempt-glob.out"

  # Plan/spec filename-labeled artifacts (*.plan.md / *.spec.md) are exempt by
  # default without any DOC_BUDGET_EXEMPT_GLOBS config (net stays 4), and their
  # volume is reported separately rather than dropped silently.
  : > docs/feature.plan.md
  for i in $(seq 1 30); do
    printf 'plan row %s\n' "$i" >> docs/feature.plan.md
  done
  ./scripts/doc-budget.sh > "${tmp_dir}/budget-label.out"
  grep -q "current guidance diff net added lines: 4" "${tmp_dir}/budget-label.out"
  grep -q "plan/spec labeled artifacts net added lines (exempt, reported separately): 30" "${tmp_dir}/budget-label.out"
  rm -f docs/feature.plan.md

  rm -rf docs/specs

  git restore --staged docs/WORKFLOW.md
  git restore AGENTS.md docs/WORKFLOW.md
  rm -f docs/NEW_GUIDE.md "docs/SPACE GUIDE.md"

  printf 'old guidance line 1\nold guidance line 2\n' > docs/MIXED.md
  git add docs/MIXED.md
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m "seed mixed guidance fixture"
  printf 'new guidance line 1\nnew guidance line 2\n' > docs/MIXED.md
  ./scripts/doc-budget.sh > "${tmp_dir}/budget-mixed.out"
  grep -q "current guidance diff added lines: 2" "${tmp_dir}/budget-mixed.out"
  grep -q "current guidance diff net added lines: 0" "${tmp_dir}/budget-mixed.out"

  git restore docs/MIXED.md
  : > docs/LONG.md
  for i in $(seq 1 400); do
    printf 'moved guidance line %s\n' "$i" >> docs/LONG.md
  done
  git add docs/LONG.md
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m "seed refactor guidance fixture"
  mv docs/LONG.md docs/MOVED.md
  ./scripts/doc-budget.sh > "${tmp_dir}/budget-refactor.out"
  grep -q "current guidance diff added lines: 400" "${tmp_dir}/budget-refactor.out"
  grep -q "current guidance diff net added lines: 0" "${tmp_dir}/budget-refactor.out"

  : > docs/TEMPLATE_PATCH.md
  for i in $(seq 1 310); do
    printf 'template patch guidance line %s\n' "$i" >> docs/TEMPLATE_PATCH.md
  done
	  if env -u DOC_BUDGET_TEMPLATE_PATCH ./scripts/doc-budget.sh > "${tmp_dir}/budget-template-patch-fail.out" 2>&1; then
    echo "[verify] doc-budget accepted large template patch diff without explicit mode"
    exit 1
  fi
  grep -q "DOC_BUDGET_TEMPLATE_PATCH=1" "${tmp_dir}/budget-template-patch-fail.out"
  DOC_BUDGET_TEMPLATE_PATCH=1 DOC_BUDGET_TEMPLATE_PATCH_REASON='verify fixture: reviewed template-owned guide additions' ./scripts/doc-budget.sh > "${tmp_dir}/budget-template-patch-mode.out"
  grep -q "template patch mode" "${tmp_dir}/budget-template-patch-mode.out"
  grep -q "template patch mode reason: verify fixture" "${tmp_dir}/budget-template-patch-mode.out"
  grep -q "warnings=" "${tmp_dir}/budget-template-patch-mode.out"
  # The escape hatch requires a reason: omitting it must fail closed.
  if env -u DOC_BUDGET_TEMPLATE_PATCH_REASON DOC_BUDGET_TEMPLATE_PATCH=1 ./scripts/doc-budget.sh > "${tmp_dir}/budget-template-patch-noreason.out" 2>&1; then
    echo "[verify] doc-budget accepted template patch mode without a reason"
    exit 1
  fi
  grep -q "requires DOC_BUDGET_TEMPLATE_PATCH_REASON" "${tmp_dir}/budget-template-patch-noreason.out"
)

echo "[verify] testing guidance document budget cumulative-vs-base accounting..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_doc_budget_cumulative_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_doc_budget_cumulative_tmp EXIT

  git -c init.defaultBranch=main init -q "${tmp_dir}"
  cd "${tmp_dir}"
  mkdir -p docs scripts
  printf '# Agents\n' > AGENTS.md
  printf '# Workflow\n' > docs/WORKFLOW.md
  cp "${repo_root}/scripts/doc-budget.sh" scripts/doc-budget.sh
  chmod +x scripts/doc-budget.sh
  git add .
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m "seed cumulative fixture"

  # A COMMITTED guidance change on a feature branch must be counted against the
  # main merge-base even though the working tree is clean (no commit-split evasion).
  git checkout -q -b feature
  printf 'committed line 1\ncommitted line 2\ncommitted line 3\n' >> docs/WORKFLOW.md
  git add docs/WORKFLOW.md
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m "feature guidance change"
  ./scripts/doc-budget.sh > "${tmp_dir}/budget-cumulative.out"
  grep -q "current guidance diff net added lines: 3" "${tmp_dir}/budget-cumulative.out"

  # On the base branch the same change is part of the base, so net is 0.
  git checkout -q main
  git merge -q --ff-only feature
  ./scripts/doc-budget.sh > "${tmp_dir}/budget-cumulative-main.out"
  grep -q "current guidance diff net added lines: 0" "${tmp_dir}/budget-cumulative-main.out"

  # A task/run baseline can narrow the hard-fail decision to the current work
  # while still reporting the branch-cumulative bloat as a warning.
  git checkout -q -b bloated-feature
  : > docs/BLOAT.md
  for i in $(seq 1 310); do
    printf 'branch guidance line %s\n' "$i" >> docs/BLOAT.md
  done
  git add docs/BLOAT.md
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m "seed branch guidance bloat"
  completion_base="$(git rev-parse HEAD)"
  printf 'small current-work guidance line\n' >> docs/WORKFLOW.md
  DOC_BUDGET_COMPLETION_BASE_REF="${completion_base}" ./scripts/doc-budget.sh > "${tmp_dir}/budget-completion-scope-pass.out"
  grep -q "branch-cumulative guidance diff net added lines: 311" "${tmp_dir}/budget-completion-scope-pass.out"
  grep -q "completion-scoped guidance diff net added lines: 1" "${tmp_dir}/budget-completion-scope-pass.out"
  grep -q "warnings=" "${tmp_dir}/budget-completion-scope-pass.out"

  : > docs/TASK_BLOAT.md
  for i in $(seq 1 310); do
    printf 'task guidance line %s\n' "$i" >> docs/TASK_BLOAT.md
  done
  if DOC_BUDGET_COMPLETION_BASE_REF="${completion_base}" ./scripts/doc-budget.sh > "${tmp_dir}/budget-completion-scope-fail.out" 2>&1; then
    echo "[verify] doc-budget accepted completion-scoped guidance bloat"
    exit 1
  fi
  grep -q "completion-scoped guidance diff net added lines exceeds hard limit" "${tmp_dir}/budget-completion-scope-fail.out"
)

echo "[verify] testing guidance document budget missing-file tolerance..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_doc_budget_missing_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_doc_budget_missing_tmp EXIT

  mkdir -p "${tmp_dir}/scripts"
  cp "${repo_root}/scripts/doc-budget.sh" "${tmp_dir}/scripts/doc-budget.sh"
  chmod +x "${tmp_dir}/scripts/doc-budget.sh"
  cd "${tmp_dir}"

  ./scripts/doc-budget.sh > "${tmp_dir}/budget-missing.out"
  grep -q "AGENTS.md lines: 0" "${tmp_dir}/budget-missing.out"
  grep -q "guidance markdown total lines: 0" "${tmp_dir}/budget-missing.out"
)

grep -q "stage-2 duplicate report only when the user asks" scripts/doc-budget.sh
grep -q "stage-2 duplicate report only when the user asks" templates/automation-base/scripts/doc-budget.sh
grep -q "DOC_BUDGET_TEMPLATE_PATCH=1" scripts/doc-budget.sh
grep -q "DOC_BUDGET_TEMPLATE_PATCH=1" templates/automation-base/scripts/doc-budget.sh
grep -q "absorbed, rejected, or deferred" AGENTS.md
grep -q "absorbed, rejected, or deferred" templates/automation-base/AGENTS.md
grep -q "Guidance Budget Escalation" docs/AUTOMATION_OPERATING_POLICY.md
grep -q "Guidance Budget Escalation" templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md
grep -q "Stage 2 is a read-only duplicate or consolidation" templates/automation-base/README.md
grep -q "Tool Adoption Before Custom Development" docs/AUTOMATION_OPERATING_POLICY.md
grep -q "Tool Adoption Before Custom Development" templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md

echo "[verify] testing Stage 2 guidance duplicate reporter fallback..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_guidance_duplicate_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_guidance_duplicate_tmp EXIT

  report_output="$(
    GUIDANCE_DUPLICATE_REPORT_DIR="${tmp_dir}/reports" \
      ./scripts/guidance-duplicate-report.sh AGENTS.md docs
  )"
  report_path="${report_output##*: }"
  test -f "${report_path}"
  grep -q "2단계 지침 중복 리포트" "${report_path}"
  grep -Eq "기존 도구 분석|로컬 경량 분석" "${report_path}"
  grep -q "문서 수정 없이" "${report_path}"

  mkdir -p "${tmp_dir}/space docs"
  {
    printf '# Space Doc\n'
    printf '### Shared Setup\n'
    printf 'This repeated guidance line is intentionally long enough for duplicate reporting with paths that contain spaces.\n'
  } > "${tmp_dir}/space docs/one file.md"
  {
    printf '# Space Doc Copy\n'
    printf '### Shared Setup\n'
    printf 'This repeated guidance line is intentionally long enough for duplicate reporting with paths that contain spaces.\n'
  } > "${tmp_dir}/space docs/two file.md"
  space_output="$(
    PATH="/usr/bin:/bin" GUIDANCE_DUPLICATE_REPORT_DIR="${tmp_dir}/space reports" \
      ./scripts/guidance-duplicate-report.sh "${tmp_dir}/space docs"
  )"
  space_report_path="${space_output##*: }"
  test -f "${space_report_path}"
  grep -q "paths that contain spaces" "${space_report_path}"
  grep -q "### Shared Setup" "${space_report_path}"
)

echo "[verify] testing review summary decisions..."
./scripts/test-review-summary.sh

echo "[verify] testing AI runtime adapter contract..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_runtime_adapter_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_runtime_adapter_tmp EXIT

  prompt_file="${tmp_dir}/prompt.md"
  output_file="${tmp_dir}/out/review.md"
  printf '# Review Prompt\n\nCheck this fixture.\n' > "${prompt_file}"
  mkdir -p "${tmp_dir}/bin"

  cat > "${tmp_dir}/bin/claude" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: claude --print"
  exit 0
fi
if [ "${1:-}" = "--print" ]; then
  cat > "${CLAUDE_STDIN_CAPTURE}"
  printf '# Claude Review\n\n## Verdict\n\napprove\n'
  exit 0
fi
exit 64
SH

  cat > "${tmp_dir}/bin/agy" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: agy --prompt-file PATH --output-format text --sandbox"
  exit 0
fi
printf '%s\n' "$@" > "${AGY_ARGV_CAPTURE}"
prompt_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prompt-file)
      prompt_file="$2"
      shift 2
      ;;
    --output-format)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
cat "${prompt_file}" > "${AGY_PROMPT_CAPTURE}"
printf '# Gemini Review\n\n## Verdict\n\napprove_with_notes\n'
SH

  chmod +x "${tmp_dir}/bin/claude" "${tmp_dir}/bin/agy"

  ./scripts/ai-runtime-adapter.sh capability claude review > "${tmp_dir}/claude-capability.out"
  grep -q "supported: yes" "${tmp_dir}/claude-capability.out"
  grep -q "execution_mode: logical_readonly" "${tmp_dir}/claude-capability.out"

  ./scripts/ai-runtime-adapter.sh capability codex review > "${tmp_dir}/codex-capability.out"
  grep -q "execution_mode: readonly_sandbox" "${tmp_dir}/codex-capability.out"

  if ./scripts/ai-runtime-adapter.sh capability agy commit > "${tmp_dir}/agy-commit.out"; then
    echo "[verify] agy commit capability unexpectedly succeeded"
    exit 1
  fi
  grep -q "supported: no" "${tmp_dir}/agy-commit.out"

  if ./scripts/ai-runtime-adapter.sh capability codex edit_files > "${tmp_dir}/codex-edit.out"; then
    echo "[verify] codex edit_files capability should not be executable through runtime adapter"
    exit 1
  fi
  grep -q "supported: no" "${tmp_dir}/codex-edit.out"

  PATH="${tmp_dir}/bin:${PATH}" \
  CLAUDE_STDIN_CAPTURE="${tmp_dir}/claude.stdin" \
    ./scripts/ai-runtime-adapter.sh run-readonly \
      --runtime claude \
      --capability review \
      --prompt-file "${prompt_file}" \
      --output "${output_file}"
  grep -q "## Verdict" "${output_file}"
  grep -q "Check this fixture" "${tmp_dir}/claude.stdin"

  rm -f "${output_file}"
  PATH="${tmp_dir}/bin:${PATH}" \
  AGY_PROMPT_CAPTURE="${tmp_dir}/agy.prompt" \
  AGY_ARGV_CAPTURE="${tmp_dir}/agy.argv" \
    ./scripts/ai-runtime-adapter.sh run-readonly \
      --runtime agy \
      --capability review \
      --prompt-file "${prompt_file}" \
      --output "${output_file}"
  grep -q "approve_with_notes" "${output_file}"
  grep -q "Check this fixture" "${tmp_dir}/agy.prompt"
  grep -qx -- "--sandbox" "${tmp_dir}/agy.argv"

  # The raw `gemini` CLI's --sandbox needs a container runtime (Docker/podman);
  # on a host without one (WSL, desktop AI runtime) it must be dropped so the
  # review still runs. GEMINI_SANDBOX gives a deterministic override either way.
  # agy and other wrappers keep --sandbox (asserted above).
  cat > "${tmp_dir}/bin/gemini" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ] || [ "${2:-}" = "--help" ]; then
  echo "usage: gemini --prompt-file FILE --sandbox --approval-mode MODE --output-format text"
  exit 0
fi
: > "${GEMINI_ARGV_CAPTURE}"
for arg in "$@"; do printf '%s\n' "${arg}" >> "${GEMINI_ARGV_CAPTURE}"; done
printf '# Gemini Review\n\n## Verdict\n\napprove\n'
SH
  chmod +x "${tmp_dir}/bin/gemini"

  rm -f "${output_file}"
  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_AGY_COMMAND=gemini \
  GEMINI_SANDBOX=0 \
  GEMINI_ARGV_CAPTURE="${tmp_dir}/gemini-nosandbox.argv" \
    ./scripts/ai-runtime-adapter.sh run-readonly \
      --runtime agy \
      --capability review \
      --prompt-file "${prompt_file}" \
      --output "${output_file}"
  grep -q "## Verdict" "${output_file}"
  if grep -qx -- "--sandbox" "${tmp_dir}/gemini-nosandbox.argv"; then
    echo "[verify] raw gemini received --sandbox while GEMINI_SANDBOX=0 (would fail without Docker)"
    exit 1
  fi

  # GEMINI_SANDBOX matching is case-insensitive, so an uppercase opt-out still
  # drops --sandbox instead of falling through to runtime auto-detection.
  rm -f "${output_file}"
  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_AGY_COMMAND=gemini \
  GEMINI_SANDBOX=FALSE \
  GEMINI_ARGV_CAPTURE="${tmp_dir}/gemini-upper.argv" \
    ./scripts/ai-runtime-adapter.sh run-readonly \
      --runtime agy \
      --capability review \
      --prompt-file "${prompt_file}" \
      --output "${output_file}"
  if grep -qx -- "--sandbox" "${tmp_dir}/gemini-upper.argv"; then
    echo "[verify] raw gemini received --sandbox while GEMINI_SANDBOX=FALSE (case-insensitive opt-out failed)"
    exit 1
  fi

  # Auto-detect (GEMINI_SANDBOX unset): an installed-but-unusable container
  # runtime (CLI present, daemon down) must NOT count as a usable sandbox, so
  # --sandbox is still dropped. This is the common WSL/desktop failure state.
  cat > "${tmp_dir}/bin/docker" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "info" ] && exit 1
exit 0
SH
  chmod +x "${tmp_dir}/bin/docker"
  rm -f "${output_file}"
  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_AGY_COMMAND=gemini \
  GEMINI_ARGV_CAPTURE="${tmp_dir}/gemini-daemon-down.argv" \
    ./scripts/ai-runtime-adapter.sh run-readonly \
      --runtime agy \
      --capability review \
      --prompt-file "${prompt_file}" \
      --output "${output_file}"
  if grep -qx -- "--sandbox" "${tmp_dir}/gemini-daemon-down.argv"; then
    echo "[verify] raw gemini received --sandbox with an installed-but-unusable docker daemon"
    exit 1
  fi

  # A usable container runtime (daemon answers) keeps --sandbox on auto-detect.
  cat > "${tmp_dir}/bin/docker" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "${tmp_dir}/bin/docker"
  rm -f "${output_file}"
  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_AGY_COMMAND=gemini \
  GEMINI_ARGV_CAPTURE="${tmp_dir}/gemini-daemon-up.argv" \
    ./scripts/ai-runtime-adapter.sh run-readonly \
      --runtime agy \
      --capability review \
      --prompt-file "${prompt_file}" \
      --output "${output_file}"
  grep -qx -- "--sandbox" "${tmp_dir}/gemini-daemon-up.argv"

  rm -f "${tmp_dir}/bin/docker"

  rm -f "${output_file}"
  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_AGY_COMMAND=gemini \
  GEMINI_SANDBOX=1 \
  GEMINI_ARGV_CAPTURE="${tmp_dir}/gemini-sandbox.argv" \
    ./scripts/ai-runtime-adapter.sh run-readonly \
      --runtime agy \
      --capability review \
      --prompt-file "${prompt_file}" \
      --output "${output_file}"
  grep -qx -- "--sandbox" "${tmp_dir}/gemini-sandbox.argv"

  cat > "${tmp_dir}/bin/prompt-only-agy" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: agy --prompt --sandbox"
  exit 0
fi
printf 'prompt-only agy should not run for oversized prompts\n' >&2
exit 64
SH
  chmod +x "${tmp_dir}/bin/prompt-only-agy"

  printf '# Large Review Prompt\n\nCheck this oversized fixture.\n' > "${tmp_dir}/large-prompt.md"
  if PATH="${tmp_dir}/bin:${PATH}" \
    RUNTIME_ADAPTER_AGY_COMMAND=prompt-only-agy \
    RUNTIME_ADAPTER_PROMPT_ARG_MAX_BYTES=10 \
      ./scripts/ai-runtime-adapter.sh run-readonly \
        --runtime agy \
        --capability review \
        --prompt-file "${tmp_dir}/large-prompt.md" \
        --output "${tmp_dir}/large-review.md" > "${tmp_dir}/large-prompt.out" 2>&1; then
    echo "[verify] prompt-only agy unexpectedly accepted an oversized prompt"
    exit 1
  fi
  grep -q "large_prompt_requires_prompt_file" "${tmp_dir}/large-prompt.out"
  test ! -f "${tmp_dir}/large-review.md"

  # A runtime that advertises only --prompt (no --prompt-file) must receive the
  # real prompt text on that fallback path, never a placeholder, when the prompt
  # is within the arg-size budget.
  cat > "${tmp_dir}/bin/prompt-only-real-agy" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: agy --prompt TEXT --sandbox --output-format text --skip-trust --approval-mode plan"
  exit 0
fi
prompt_value=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prompt)
      prompt_value="${2:-}"
      shift 2
      ;;
    --output-format|--approval-mode|--print-timeout|--model)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s' "${prompt_value}" > "${AGY_PROMPT_ARG_CAPTURE}"
printf '# Gemini Review\n\n## Verdict\n\napprove\n'
SH
  chmod +x "${tmp_dir}/bin/prompt-only-real-agy"

  rm -f "${output_file}"
  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_AGY_COMMAND=prompt-only-real-agy \
  AGY_PROMPT_ARG_CAPTURE="${tmp_dir}/agy-prompt-arg.txt" \
    ./scripts/ai-runtime-adapter.sh run-readonly \
      --runtime agy \
      --capability review \
      --prompt-file "${prompt_file}" \
      --output "${output_file}"
  grep -q "## Verdict" "${output_file}"
  grep -q "Check this fixture" "${tmp_dir}/agy-prompt-arg.txt"

  if PATH="${tmp_dir}/bin:${PATH}" ./scripts/ai-runtime-adapter.sh run-readonly \
    --runtime claude \
    --capability edit_files \
    --prompt-file "${prompt_file}" \
    --output "${tmp_dir}/write.md" > "${tmp_dir}/write-refusal.out" 2>&1; then
    echo "[verify] write-capable adapter mode unexpectedly succeeded"
    exit 1
  fi
  grep -q "capability_refused" "${tmp_dir}/write-refusal.out"
  test ! -f "${tmp_dir}/write.md"

  cat > "${tmp_dir}/bin/no-prompt-runtime" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: no-prompt-runtime"
  exit 0
fi
printf 'should not run without a noninteractive prompt flag\n'
exit 64
SH
  chmod +x "${tmp_dir}/bin/no-prompt-runtime"

  if PATH="${tmp_dir}/bin:${PATH}" RUNTIME_ADAPTER_CLAUDE_COMMAND=no-prompt-runtime \
    ./scripts/ai-runtime-adapter.sh run-readonly \
      --runtime claude \
      --capability review \
      --prompt-file "${prompt_file}" \
      --output "${tmp_dir}/no-prompt.md" > "${tmp_dir}/no-prompt.out" 2>&1; then
    echo "[verify] adapter ran a runtime without noninteractive prompt support"
    exit 1
  fi
  grep -q "missing_noninteractive_prompt_mode" "${tmp_dir}/no-prompt.out"
  test ! -f "${tmp_dir}/no-prompt.md"

  mkdir -p "${tmp_dir}/relative/prompts" "${tmp_dir}/relative/work"
  printf '# Relative Prompt\n\nCheck absolute path handling.\n' > "${tmp_dir}/relative/prompts/in.md"
  (
    cd "${tmp_dir}/relative"
    PATH="${tmp_dir}/bin:${PATH}" \
    CLAUDE_STDIN_CAPTURE="${tmp_dir}/relative/claude-relative.stdin" \
      "${repo_root}/scripts/ai-runtime-adapter.sh" run-readonly \
        --runtime claude \
        --capability review \
        --prompt-file prompts/in.md \
        --output out/review.md \
        --cd work
  )
  test -f "${tmp_dir}/relative/out/review.md"
  grep -q "Check absolute path handling" "${tmp_dir}/relative/claude-relative.stdin"
)

if [ "${AI_AUTO_IN_REVIEW_GATE:-0}" = "1" ]; then
  echo "[verify] skipping nested review-runner self-tests inside review-gate..."
else
echo "[verify] testing Codex fallback uses runtime adapter read-only mode..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_codex_adapter_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_codex_adapter_tmp EXIT

  mkdir -p "${tmp_dir}/repo/.omx/review-prompts" "${tmp_dir}/repo/.omx/review-context" "${tmp_dir}/repo/scripts" "${tmp_dir}/bin"
  cd "${tmp_dir}/repo"
  git -c init.defaultBranch=main init -q
  cp "${repo_root}/scripts/ai-runtime-adapter.sh" scripts/ai-runtime-adapter.sh
  cp "${repo_root}/scripts/run-ai-reviews.sh" scripts/run-ai-reviews.sh
  cp "${repo_root}/scripts/summarize-ai-reviews.sh" scripts/summarize-ai-reviews.sh
  chmod +x scripts/ai-runtime-adapter.sh
  chmod +x scripts/run-ai-reviews.sh scripts/summarize-ai-reviews.sh

  printf '# Claude Review\n' > .omx/review-prompts/claude-review.md
  printf '# Gemini Review\n' > .omx/review-prompts/gemini-review.md
  printf '# Context\n\nsrc/runtime-target.py\n' > .omx/review-context/latest-review-context.md

  cat > "${tmp_dir}/bin/codex" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "exec" ] && [ "${2:-}" = "--help" ]; then
  echo "usage: codex exec --model --cd --sandbox --ephemeral -o"
  exit 0
fi
printf '%s\n' "$@" > "${CODEX_ARGV_CAPTURE}"
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done
cat > "${CODEX_STDIN_CAPTURE}"
cat > "${out}" <<'MSG'
# Codex Fallback

## Verdict

approve_with_notes

## Direct File Inspection

- src/runtime-target.py
MSG
SH
  chmod +x "${tmp_dir}/bin/codex"

  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_CODEX_COMMAND="${tmp_dir}/bin/codex" \
  CODEX_ARGV_CAPTURE="${tmp_dir}/codex.argv" \
  CODEX_STDIN_CAPTURE="${tmp_dir}/codex.stdin" \
  SKIP_CONTEXT_GENERATION=1 \
  AI_MODEL_DISCOVERY=0 \
  RUN_CLAUDE_REVIEW=0 \
  RUN_GEMINI_REVIEW=0 \
  OUT_DIR=.omx/review-results \
  CONTEXT_DIR=.omx/review-context \
  PROMPT_DIR=.omx/review-prompts \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/run.out"

  grep -qx "exec" "${tmp_dir}/codex.argv"
  grep -qx -- "--cd" "${tmp_dir}/codex.argv"
  grep -qx "$(pwd)" "${tmp_dir}/codex.argv"
  grep -qx -- "--sandbox" "${tmp_dir}/codex.argv"
  grep -qx "read-only" "${tmp_dir}/codex.argv"
  grep -qx -- "--ephemeral" "${tmp_dir}/codex.argv"
  grep -qx -- "-o" "${tmp_dir}/codex.argv"
  ! grep -q "workspace-write" "${tmp_dir}/codex.argv"
  ! grep -q "danger-full-access" "${tmp_dir}/codex.argv"
  grep -q "principal-subagent substitute reviewer" "${tmp_dir}/codex.stdin"
)

echo "[verify] testing review runner honors runtime adapter command overrides..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_review_override_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_review_override_tmp EXIT

  mkdir -p "${tmp_dir}/repo/.omx/review-prompts" "${tmp_dir}/repo/.omx/review-context" "${tmp_dir}/repo/scripts" "${tmp_dir}/bin"
  cd "${tmp_dir}/repo"
  git -c init.defaultBranch=main init -q
  cp "${repo_root}/scripts/ai-runtime-adapter.sh" scripts/ai-runtime-adapter.sh
  cp "${repo_root}/scripts/run-ai-reviews.sh" scripts/run-ai-reviews.sh
  cp "${repo_root}/scripts/summarize-ai-reviews.sh" scripts/summarize-ai-reviews.sh
  chmod +x scripts/ai-runtime-adapter.sh scripts/run-ai-reviews.sh scripts/summarize-ai-reviews.sh

  printf '# Claude Review\n\n## Verdict\n\napprove\n' > .omx/review-prompts/claude-review.md
  printf '# Gemini Review\n\n## Verdict\n\napprove\n' > .omx/review-prompts/gemini-review.md
  printf '# Context\n' > .omx/review-context/latest-review-context.md

  cat > "${tmp_dir}/bin/custom-claude" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: custom-claude --print"
  exit 0
fi
printf '%s\n' "$@" > "${CUSTOM_CLAUDE_ARGV_CAPTURE}"
cat > "${CUSTOM_CLAUDE_STDIN_CAPTURE}"
printf '# Claude Review\n\n## Verdict\n\napprove\n'
SH
  chmod +x "${tmp_dir}/bin/custom-claude"

  cat > "${tmp_dir}/bin/custom-agy" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: custom-agy --prompt --sandbox --output-format"
  exit 0
fi
printf '%s\n' "$@" > "${CUSTOM_AGY_ARGV_CAPTURE}"
printf '# Gemini Review\n\n## Verdict\n\napprove_with_notes\n'
SH
  chmod +x "${tmp_dir}/bin/custom-agy"

  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_CLAUDE_COMMAND=custom-claude \
  GEMINI_REVIEW_COMMAND=custom-agy \
  CUSTOM_CLAUDE_ARGV_CAPTURE="${tmp_dir}/custom-claude.argv" \
  CUSTOM_CLAUDE_STDIN_CAPTURE="${tmp_dir}/custom-claude.stdin" \
  CUSTOM_AGY_ARGV_CAPTURE="${tmp_dir}/custom-agy.argv" \
  SKIP_CONTEXT_GENERATION=1 \
  AI_MODEL_DISCOVERY=0 \
  RUN_CODEX_FALLBACK_REVIEW=0 \
  RUN_PRINCIPAL_SUBAGENT_SUBSTITUTE_REVIEW=0 \
  OUT_DIR=.omx/review-results \
  CONTEXT_DIR=.omx/review-context \
  PROMPT_DIR=.omx/review-prompts \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/run.out"

  grep -q "running Gemini review via custom-agy" "${tmp_dir}/run.out"
  grep -qx -- "--print" "${tmp_dir}/custom-claude.argv"
  grep -q "Claude Review" "${tmp_dir}/custom-claude.stdin"
  grep -qx -- "--sandbox" "${tmp_dir}/custom-agy.argv"

  rm -f "${tmp_dir}/custom-claude.argv" "${tmp_dir}/custom-claude.stdin" "${tmp_dir}/custom-agy.argv"
  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_CLAUDE_COMMAND=custom-claude \
  GEMINI_REVIEW_COMMAND=custom-agy \
  CUSTOM_CLAUDE_ARGV_CAPTURE="${tmp_dir}/custom-claude.argv" \
  CUSTOM_CLAUDE_STDIN_CAPTURE="${tmp_dir}/custom-claude.stdin" \
  CUSTOM_AGY_ARGV_CAPTURE="${tmp_dir}/custom-agy.argv" \
  SKIP_CONTEXT_GENERATION=1 \
  AI_MODEL_DISCOVERY=0 \
  REVIEW_EXECUTION_MODE=external \
  RUN_CODEX_FALLBACK_REVIEW=0 \
  RUN_PRINCIPAL_SUBAGENT_SUBSTITUTE_REVIEW=0 \
  OUT_DIR=.omx/review-results \
  CONTEXT_DIR=.omx/review-context \
  PROMPT_DIR=.omx/review-prompts \
  EXTERNAL_REVIEW_DIR=.omx/external-review \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/external.out" 2>&1 || test "$?" -eq 2

  grep -q 'RUNTIME_ADAPTER_CLAUDE_COMMAND="${RUNTIME_ADAPTER_CLAUDE_COMMAND}"' .omx/external-review/run-reviewers-latest.sh
  grep -q 'RUNTIME_ADAPTER_AGY_COMMAND="${RUNTIME_ADAPTER_AGY_COMMAND}"' .omx/external-review/run-reviewers-latest.sh
  grep -q 'RUNTIME_ADAPTER_CODEX_COMMAND="${RUNTIME_ADAPTER_CODEX_COMMAND}"' .omx/external-review/run-reviewers-latest.sh
  PATH="${tmp_dir}/bin:${PATH}" \
  CUSTOM_CLAUDE_ARGV_CAPTURE="${tmp_dir}/custom-claude.argv" \
  CUSTOM_CLAUDE_STDIN_CAPTURE="${tmp_dir}/custom-claude.stdin" \
  CUSTOM_AGY_ARGV_CAPTURE="${tmp_dir}/custom-agy.argv" \
    .omx/external-review/run-reviewers-latest.sh > "${tmp_dir}/external-run.out" || true
  grep -q "running Gemini review via custom-agy" "${tmp_dir}/external-run.out"
  grep -qx -- "--print" "${tmp_dir}/custom-claude.argv"
  grep -qx -- "--sandbox" "${tmp_dir}/custom-agy.argv"
)

echo "[verify] testing adapter failure diagnostics reach review artifacts..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_review_diagnostics_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_review_diagnostics_tmp EXIT

  mkdir -p "${tmp_dir}/repo/.omx/review-prompts" "${tmp_dir}/repo/.omx/review-context" "${tmp_dir}/repo/scripts" "${tmp_dir}/bin"
  cd "${tmp_dir}/repo"
  git -c init.defaultBranch=main init -q
  cp "${repo_root}/scripts/ai-runtime-adapter.sh" scripts/ai-runtime-adapter.sh
  chmod +x scripts/ai-runtime-adapter.sh

  printf '# Claude Review\n\nadapter diagnostics fixture\n' > .omx/review-prompts/claude-review.md
  printf '# Gemini Review\n\n## Verdict\n\napprove\n' > .omx/review-prompts/gemini-review.md
  printf '# Context\n' > .omx/review-context/latest-review-context.md

  cat > "${tmp_dir}/bin/no-print-claude" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: no-print-claude"
  exit 0
fi
printf 'should not execute without --print support\n'
exit 64
SH
  chmod +x "${tmp_dir}/bin/no-print-claude"

  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_CLAUDE_COMMAND=no-print-claude \
  SKIP_CONTEXT_GENERATION=1 \
  AI_MODEL_DISCOVERY=0 \
  RUN_GEMINI_REVIEW=0 \
  RUN_CODEX_FALLBACK_REVIEW=0 \
  RUN_PRINCIPAL_SUBAGENT_SUBSTITUTE_REVIEW=0 \
  REVIEW_RETRY_LIMIT=1 \
  OUT_DIR=.omx/review-results \
  CONTEXT_DIR=.omx/review-context \
  PROMPT_DIR=.omx/review-prompts \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/run.out"

  latest_claude="$(find .omx/review-results -maxdepth 1 -name 'claude-review-*.md' -print | sort | tail -1)"
  grep -q "Adapter execution diagnostics" "${latest_claude}"
  grep -q "missing_noninteractive_prompt_mode" "${latest_claude}"
  grep -q "tail=.*missing_noninteractive_prompt_mode" .omx/reviewer-state/claude.disabled

  cat > "${tmp_dir}/bin/bad-codex" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "exec" ] && [ "${2:-}" = "--help" ]; then
  echo "usage: bad-codex exec --cd --sandbox --ephemeral -o"
  exit 0
fi
printf 'codex adapter diagnostic marker\n'
exit 64
SH
  chmod +x "${tmp_dir}/bin/bad-codex"

  rm -f .omx/reviewer-state/claude.disabled
  PATH="${tmp_dir}/bin:${PATH}" \
  RUNTIME_ADAPTER_CLAUDE_COMMAND=no-print-claude \
  RUNTIME_ADAPTER_CODEX_COMMAND=bad-codex \
  SKIP_CONTEXT_GENERATION=1 \
  AI_MODEL_DISCOVERY=0 \
  RUN_GEMINI_REVIEW=0 \
  REVIEW_RETRY_LIMIT=1 \
  OUT_DIR=.omx/review-results \
  CONTEXT_DIR=.omx/review-context \
  PROMPT_DIR=.omx/review-prompts \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/codex-fallback.out"

  latest_codex="$(find .omx/review-results -maxdepth 1 -name 'codex-architect-fallback-*.md' -print | sort | tail -1)"
  grep -q "Adapter execution diagnostics" "${latest_codex}"
  grep -q "codex adapter diagnostic marker" "${latest_codex}"
)
fi

echo "[verify] testing ai-refactor-scan..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_refactor_scan_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_refactor_scan_tmp EXIT

  mkdir -p "${tmp_dir}/src"
  {
    printf 'import os\nimport sys\n\n'
    printf 'def compact():\n    return 1\n\n'
    printf 'def oversized():\n'
    for i in $(seq 1 12); do
      printf '    value_%s = %s\n' "$i" "$i"
    done
    printf '    return value_12\n'
  } > "${tmp_dir}/src/monolith.py"

  ./tools/ai-refactor-scan --top 5 --min-lines 5 --min-block-lines 10 "${tmp_dir}" > "${tmp_dir}/scan.out"
  grep -q "AI_AUTO Refactor Scan:" "${tmp_dir}/scan.out"
  grep -q "Large Files" "${tmp_dir}/scan.out"
  grep -q "src/monolith.py" "${tmp_dir}/scan.out"
  grep -q "oversized" "${tmp_dir}/scan.out"

  if ./tools/ai-refactor-scan --top 0 "${tmp_dir}" > "${tmp_dir}/invalid.out" 2>&1; then
    echo "[verify] ai-refactor-scan accepted invalid --top"
    exit 1
  fi
)

echo "[verify] testing ai-rebuild-plan..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_rebuild_plan_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_rebuild_plan_tmp EXIT

  target_dir="${tmp_dir}/target"
  mkdir -p "${target_dir}/docs" "${target_dir}/scripts" "${target_dir}/src" "${target_dir}/.omx/domain-packs/sample"
  git -C "${tmp_dir}" init target >/dev/null
  printf '# Agent\n' > "${target_dir}/AGENTS.md"
  printf '# Workflow\n' > "${target_dir}/docs/WORKFLOW.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${target_dir}/scripts/verify.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${target_dir}/scripts/review-gate.sh"
  {
    printf 'import os\nimport sys\n\n'
    printf 'def oversized():\n'
    for i in $(seq 1 12); do
      printf '    value_%s = %s\n' "$i" "$i"
    done
    printf '    return value_12\n'
  } > "${target_dir}/src/monolith.py"

  ./tools/ai-rebuild-plan "${target_dir}" > "${tmp_dir}/rebuild-plan.out"
  grep -q "AI_AUTO Rebuild Plan" "${tmp_dir}/rebuild-plan.out"
  grep -q "read-only diagnosis and planning only" "${tmp_dir}/rebuild-plan.out"
  grep -q "리빌드 실행" "${tmp_dir}/rebuild-plan.out"
  grep -q "selected / rejected / deferred domain packs" "${tmp_dir}/rebuild-plan.out"
  grep -q "AI_AUTO Refactor Scan:" "${tmp_dir}/rebuild-plan.out"
  grep -q "ai-split-plan" "${tmp_dir}/rebuild-plan.out"

  if ./tools/ai-rebuild-plan -- "${target_dir}" extra > "${tmp_dir}/invalid-extra.out" 2>&1; then
    echo "[verify] ai-rebuild-plan accepted an extra argument after --"
    exit 1
  fi
  grep -q "Unexpected extra argument: extra" "${tmp_dir}/invalid-extra.out"
)

echo "[verify] testing ai-split Python rebuild helpers..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_split_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_split_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  mkdir -p "${target_dir}/src" "${target_dir}/.omx/domain-packs/trading"
  cat > "${target_dir}/src/monolith.py" <<'PY'
import math


def place_order(symbol):
    return f"order:{symbol}"


class RiskManager:
    def score(self, symbol):
        return len(symbol)


def helper():
    return math.pi


def outer():
    def nested_risk():
        return "nested"
    return nested_risk()
PY
  cat > "${target_dir}/.omx/domain-packs/trading/split-rules.json" <<'JSON'
{
  "module_rules": [
    {
      "name": "orders",
      "destination": "{source_dir}/orders.py",
      "name_contains": ["order"]
    },
    {
      "name": "risk",
      "destination": "{source_dir}/risk.py",
      "name_contains": ["risk"]
    }
  ]
}
JSON

  plan_file="${target_dir}/.omx/rebuild/split-plan.json"
  mkdir -p "$(dirname "${plan_file}")"
  ./tools/ai-split-plan --source "${target_dir}/src/monolith.py" --domain-pack trading --output "${plan_file}" > "${tmp_dir}/split-plan.out"
  grep -q "wrote split plan" "${tmp_dir}/split-plan.out"

  python3 - "${plan_file}" <<'PY'
import json
import sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
names = {row["name"] for row in plan["candidate_symbols"]}
assert {"place_order", "RiskManager", "helper", "outer"} <= names, names
assert "nested_risk" not in names, names
moves = {move["destination_file"]: set(move["symbols"]) for move in plan["moves"]}
assert moves["src/orders.py"] == {"place_order"}, moves
assert moves["src/risk.py"] == {"RiskManager"}, moves
assert plan["proposed_moves"], plan
assert plan["approved_execution_gate"]["reviewed_dry_run"] is False
PY

  cp "${target_dir}/src/monolith.py" "${tmp_dir}/monolith.before"
  ./tools/ai-split-dry-run --plan "${plan_file}" > "${tmp_dir}/split-dry-run.out"
  grep -q "AI_AUTO Python Split Dry Run" "${tmp_dir}/split-dry-run.out"
  grep -q "place_order" "${tmp_dir}/split-dry-run.out"
  grep -q "RiskManager" "${tmp_dir}/split-dry-run.out"
  test ! -e "${target_dir}/src/orders.py"
  cmp "${tmp_dir}/monolith.before" "${target_dir}/src/monolith.py"

  cat > "${target_dir}/src/decorated.py" <<'PY'
def trace(fn):
    return fn


@trace
def decorated_order(symbol):
    return f"decorated:{symbol}"
PY
  decorated_plan_file="${target_dir}/.omx/rebuild/decorated-plan.json"
  ./tools/ai-split-plan --source "${target_dir}/src/decorated.py" --domain-pack trading --output "${decorated_plan_file}" >/dev/null
  if ./tools/ai-split-dry-run --plan "${decorated_plan_file}" > "${tmp_dir}/split-decorated.out" 2>&1; then
    echo "[verify] ai-split-dry-run accepted a source-local decorator dependency"
    exit 1
  fi
  grep -q "source-local top-level symbols" "${tmp_dir}/split-decorated.out"

  cat > "${target_dir}/src/global_dep.py" <<'PY'
RISK_LIMIT = 7


def risk_score(symbol):
    return len(symbol) + RISK_LIMIT
PY
  global_dep_plan_file="${target_dir}/.omx/rebuild/global-dep-plan.json"
  ./tools/ai-split-plan --source "${target_dir}/src/global_dep.py" --domain-pack trading --output "${global_dep_plan_file}" >/dev/null
  if ./tools/ai-split-dry-run --plan "${global_dep_plan_file}" > "${tmp_dir}/split-global-dep.out" 2>&1; then
    echo "[verify] ai-split-dry-run accepted a source-local global dependency"
    exit 1
  fi
  grep -q "risk_score needs RISK_LIMIT" "${tmp_dir}/split-global-dep.out"

  if ./tools/ai-split-apply --plan "${plan_file}" > "${tmp_dir}/split-apply-no-flag.out" 2>&1; then
    echo "[verify] ai-split-apply ran without explicit execution flag"
    exit 1
  fi
  grep -q "requires --execute-approved-plan" "${tmp_dir}/split-apply-no-flag.out"

  if ./tools/ai-split-apply --plan "${plan_file}" --execute-approved-plan > "${tmp_dir}/split-apply-no-gate.out" 2>&1; then
    echo "[verify] ai-split-apply ran without completed approval gate"
    exit 1
  fi
  grep -q "approved_execution_gate.approved_by" "${tmp_dir}/split-apply-no-gate.out"

  python3 - "${plan_file}" <<'PY'
import json
import sys
path = sys.argv[1]
plan = json.load(open(path, encoding="utf-8"))
plan["approved_execution_gate"] = {
    "approved_by": "verify",
    "approved_scope": "src/monolith.py -> src/orders.py, src/risk.py",
    "reviewed_dry_run": True,
    "rollback_path": ".omx/rebuild/backups",
    "post_apply_verification": [
        "python3 -m py_compile src/monolith.py src/orders.py src/risk.py"
    ],
}
json.dump(plan, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(path, "a", encoding="utf-8").write("\n")
PY

  python3 - "${plan_file}" "${target_dir}/.omx/rebuild/wrong-rollback-plan.json" <<'PY'
import json
import sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
plan["approved_execution_gate"]["rollback_path"] = ".omx/rebuild/custom-backups"
json.dump(plan, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(sys.argv[2], "a", encoding="utf-8").write("\n")
PY
  if ./tools/ai-split-apply --plan "${target_dir}/.omx/rebuild/wrong-rollback-plan.json" --execute-approved-plan > "${tmp_dir}/split-wrong-rollback.out" 2>&1; then
    echo "[verify] ai-split-apply accepted an unsupported rollback path"
    exit 1
  fi
  grep -q "rollback_path must be .omx/rebuild/backups" "${tmp_dir}/split-wrong-rollback.out"

  ./tools/ai-split-apply --plan "${plan_file}" --execute-approved-plan > "${tmp_dir}/split-apply.out"
  grep -q "AI_AUTO Python Split Applied" "${tmp_dir}/split-apply.out"
  grep -q "backup:" "${tmp_dir}/split-apply.out"
  grep -q "def place_order" "${target_dir}/src/orders.py"
  grep -q "class RiskManager" "${target_dir}/src/risk.py"
  grep -q "def helper" "${target_dir}/src/monolith.py"
  if grep -q "def place_order" "${target_dir}/src/monolith.py"; then
    echo "[verify] moved function remained in source"
    exit 1
  fi
  if grep -q "class RiskManager" "${target_dir}/src/monolith.py"; then
    echo "[verify] moved class remained in source"
    exit 1
  fi
  test -f "$(find "${target_dir}/.omx/rebuild/backups" -path '*/src/monolith.py' -type f | head -n 1)"
  grep -q "src/orders.py" "$(find "${target_dir}/.omx/rebuild/backups" -name created-files.txt | head -n 1)"
  python3 -m py_compile "${target_dir}/src/monolith.py" "${target_dir}/src/orders.py" "${target_dir}/src/risk.py"
  PYTHONPATH="${target_dir}/src" python3 -c "import orders, risk"

  cat > "${target_dir}/src/future_source.py" <<'PY'
from __future__ import annotations

import math


def future_order(symbols: list[str]) -> float:
    return math.pi + len(symbols)
PY
  future_plan_file="${target_dir}/.omx/rebuild/future-plan.json"
  ./tools/ai-split-plan --source "${target_dir}/src/future_source.py" --domain-pack trading --output "${future_plan_file}" >/dev/null
  python3 - "${future_plan_file}" <<'PY'
import json
import sys
path = sys.argv[1]
plan = json.load(open(path, encoding="utf-8"))
plan["approved_execution_gate"] = {
    "approved_by": "verify",
    "approved_scope": "src/future_source.py -> src/orders.py",
    "reviewed_dry_run": True,
    "rollback_path": ".omx/rebuild/backups",
    "post_apply_verification": [
        "python3 -m py_compile src/future_source.py src/orders.py"
    ],
}
json.dump(plan, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(path, "a", encoding="utf-8").write("\n")
PY
  ./tools/ai-split-dry-run --plan "${future_plan_file}" > "${tmp_dir}/split-future.out"
  grep -q "+from __future__ import annotations" "${tmp_dir}/split-future.out"
  ./tools/ai-split-apply --plan "${future_plan_file}" --execute-approved-plan > "${tmp_dir}/split-future-apply.out"
  python3 -m py_compile "${target_dir}/src/future_source.py" "${target_dir}/src/orders.py"

  outside_rules="${tmp_dir}/outside-rules.json"
  cp "${target_dir}/.omx/domain-packs/trading/split-rules.json" "${outside_rules}"
  if ./tools/ai-split-plan --source "${target_dir}/src/monolith.py" --rules "${outside_rules}" > "${tmp_dir}/split-outside-rules.out" 2>&1; then
    echo "[verify] ai-split-plan accepted a rules file outside the repository"
    exit 1
  fi
  grep -q "Split rules path must stay inside the git repository" "${tmp_dir}/split-outside-rules.out"

  bad_plan_file="${target_dir}/.omx/rebuild/bad-plan.json"
  python3 - "${plan_file}" "${bad_plan_file}" <<'PY'
import json
import sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
plan["moves"] = [
    {"destination_file": "src/a.py", "symbols": ["helper"]},
    {"destination_file": "src/b.py", "symbols": ["helper"]},
]
json.dump(plan, open(sys.argv[2], "w", encoding="utf-8"))
PY
  if ./tools/ai-split-dry-run --plan "${bad_plan_file}" > "${tmp_dir}/split-duplicate.out" 2>&1; then
    echo "[verify] ai-split-dry-run accepted duplicate symbols across moves"
    exit 1
  fi
  grep -q "unique across all moves" "${tmp_dir}/split-duplicate.out"

  duplicate_dest_plan_file="${target_dir}/.omx/rebuild/duplicate-dest-plan.json"
  python3 - "${plan_file}" "${duplicate_dest_plan_file}" <<'PY'
import json
import sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
plan["moves"] = [
    {"destination_file": "src/shared.py", "symbols": ["helper"]},
    {"destination_file": "src/shared.py", "symbols": ["outer"]},
]
json.dump(plan, open(sys.argv[2], "w", encoding="utf-8"))
PY
  if ./tools/ai-split-dry-run --plan "${duplicate_dest_plan_file}" > "${tmp_dir}/split-duplicate-dest.out" 2>&1; then
    echo "[verify] ai-split-dry-run accepted duplicate destination files"
    exit 1
  fi
  grep -q "destination_file must be unique" "${tmp_dir}/split-duplicate-dest.out"

  cat > "${target_dir}/src/helpers.py" <<'PY'
"""Existing helper module."""


def existing_helper():
    return "existing"
PY
  existing_dest_plan_file="${target_dir}/.omx/rebuild/existing-dest-plan.json"
  python3 - "${plan_file}" "${existing_dest_plan_file}" <<'PY'
import json
import sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
plan["moves"] = [
    {"destination_file": "src/helpers.py", "symbols": ["helper"]},
]
plan["approved_execution_gate"] = {
    "approved_by": "verify",
    "approved_scope": "src/monolith.py -> src/helpers.py",
    "reviewed_dry_run": True,
    "rollback_path": ".omx/rebuild/backups",
    "post_apply_verification": [
        "python3 -m py_compile src/monolith.py src/helpers.py"
    ],
}
json.dump(plan, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(sys.argv[2], "a", encoding="utf-8").write("\n")
PY
  ./tools/ai-split-dry-run --plan "${existing_dest_plan_file}" > "${tmp_dir}/split-existing-dest.out"
  grep -q "+import math" "${tmp_dir}/split-existing-dest.out"
  grep -q "def existing_helper" "${tmp_dir}/split-existing-dest.out"
  ./tools/ai-split-apply --plan "${existing_dest_plan_file}" --execute-approved-plan > "${tmp_dir}/split-existing-dest-apply.out"
  grep -q "import math" "${target_dir}/src/helpers.py"
  grep -q "def helper" "${target_dir}/src/helpers.py"
  if grep -q "def helper" "${target_dir}/src/monolith.py"; then
    echo "[verify] helper remained in source after existing-destination split"
    exit 1
  fi
  python3 -m py_compile "${target_dir}/src/monolith.py" "${target_dir}/src/helpers.py"
  PYTHONPATH="${target_dir}/src" python3 -c "import helpers; assert helpers.helper() == 3.141592653589793"
)

echo "[verify] testing ai-plan interview/status helpers..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_plan_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_plan_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  mkdir -p "${target_dir}/.omx/plans" "${target_dir}/docs" "${target_dir}/scripts"
  printf '# Evidence\n' > "${target_dir}/docs/evidence.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${target_dir}/scripts/verify.sh"

  (cd "${target_dir}" && "${repo_root}/tools/ai-plan-status" --json > "${tmp_dir}/missing-status.json")
  grep -q '"status": "missing"' "${tmp_dir}/missing-status.json"
  grep -q '"ready_to_execute": false' "${tmp_dir}/missing-status.json"

  draft_plan="${target_dir}/.omx/plans/draft.json"
  "${repo_root}/tools/ai-interview-record" \
    --plan "${draft_plan}" \
    --field user_decisions \
    --question "Execution scope?" \
    --answer "Local files only" > "${tmp_dir}/record.out"
  grep -q "does not approve execution" "${tmp_dir}/record.out"
  grep -q '"source": "user"' "${draft_plan}"

  if "${repo_root}/tools/ai-interview-record" \
    --plan "${draft_plan}" \
    --field user_decisions \
    --source ai \
    --answer "AI inferred approval" > "${tmp_dir}/bad-record.out" 2>&1; then
    echo "[verify] ai-interview-record accepted AI-sourced user decision"
    exit 1
  fi
  grep -q "user_decisions can only be recorded" "${tmp_dir}/bad-record.out"

  "${repo_root}/tools/ai-plan-status" --json "${draft_plan}" > "${tmp_dir}/draft-status.json"
  grep -q '"status": "missing"' "${tmp_dir}/draft-status.json"
  grep -q '"approved_execution_gate_missing"' "${tmp_dir}/draft-status.json"
  "${repo_root}/tools/ai-plan-review" "${draft_plan}" > "${tmp_dir}/draft-review.out"
  grep -q "verdict: needs_work" "${tmp_dir}/draft-review.out"
  grep -q "plan review is not execution approval" "${tmp_dir}/draft-review.out"

  ready_plan="${target_dir}/.omx/plans/ready.json"
  cat > "${ready_plan}" <<'JSON'
{
  "goal": "Ship a local-only planning status helper.",
  "non_goals": ["No code execution approval"],
  "success_criteria": ["Status is computed", "Review is not approval"],
  "constraints": ["No new external dependencies"],
  "risk_gates": ["Plan/run boundary remains separate"],
  "assumptions": [],
  "user_decisions": [
    {
      "id": "scope",
      "source": "user",
      "answer": "Local files only"
    }
  ],
  "open_questions": [],
  "execution_boundaries": ["Read-only status unless export path is explicitly provided"],
  "verification_plan": ["./scripts/verify.sh"],
  "rollback_or_stop_condition": ["Stop if status reports missing required fields"],
  "ambiguity_index": {
    "critical_open_decisions": 0,
    "total_critical_decisions": 1,
    "overall_open_decisions": 0,
    "overall_total_decisions": 4
  },
  "evidence_references": ["docs/evidence.md"],
  "ready_to_execute_gate": {
    "approved_execution_gate": {
      "approved_by": "verify",
      "approved_at": "2026-05-15T00:00:00Z",
      "approved_scope": "plan-status test fixture",
      "plan_artifact": ".omx/plans/ready.json",
      "readiness": true,
      "exclusions": ["No production or external execution"]
    },
    "verification_commands": ["./scripts/verify.sh"],
    "stop_conditions": ["status != ready"]
  }
}
JSON

  weak_gate_plan="${target_dir}/.omx/plans/weak-gate.json"
  cp "${ready_plan}" "${weak_gate_plan}"
  python3 - "${weak_gate_plan}" <<'PY'
import json
import sys
path = sys.argv[1]
plan = json.load(open(path, encoding="utf-8"))
gate = plan["ready_to_execute_gate"]["approved_execution_gate"]
gate.pop("approved_at")
gate.pop("exclusions")
json.dump(plan, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(path, "a", encoding="utf-8").write("\n")
PY
  "${repo_root}/tools/ai-plan-status" --json "${weak_gate_plan}" > "${tmp_dir}/weak-gate-status.json"
  grep -q '"status": "blocked"' "${tmp_dir}/weak-gate-status.json"
  grep -q "approved_execution_gate.approved_at" "${tmp_dir}/weak-gate-status.json"
  grep -q "approved_execution_gate.exclusions" "${tmp_dir}/weak-gate-status.json"

  mismatch_gate_plan="${target_dir}/.omx/plans/mismatch-gate.json"
  cp "${ready_plan}" "${mismatch_gate_plan}"
  python3 - "${mismatch_gate_plan}" <<'PY'
import json
import sys
path = sys.argv[1]
plan = json.load(open(path, encoding="utf-8"))
plan["ready_to_execute_gate"]["approved_execution_gate"]["plan_artifact"] = ".omx/plans/some-other-plan.json"
json.dump(plan, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(path, "a", encoding="utf-8").write("\n")
PY
  "${repo_root}/tools/ai-plan-status" --json "${mismatch_gate_plan}" > "${tmp_dir}/mismatch-gate-status.json"
  grep -q '"status": "blocked"' "${tmp_dir}/mismatch-gate-status.json"
  grep -q "approved_execution_gate.plan_artifact_mismatch" "${tmp_dir}/mismatch-gate-status.json"

  (cd "${target_dir}" && "${repo_root}/tools/ai-plan-status" --write-state --json ".omx/plans/ready.json" > "${tmp_dir}/ready-status.json")
  grep -q '"status": "ready"' "${tmp_dir}/ready-status.json"
  grep -q '"ready_to_execute": true' "${tmp_dir}/ready-status.json"
  test -f "${target_dir}/.omx/state/plan-status.json"

  "${repo_root}/tools/ai-plan-review" --json "${ready_plan}" > "${tmp_dir}/ready-review.json"
  grep -q '"verdict": "pass"' "${tmp_dir}/ready-review.json"
  grep -q "plan review is not execution approval" "${tmp_dir}/ready-review.json"

  export_path="${target_dir}/.omx/plans/ready-export.md"
  "${repo_root}/tools/ai-plan-export" "${ready_plan}" --output "${export_path}" > "${tmp_dir}/export.out"
  grep -q "export does not approve execution" "${tmp_dir}/export.out"
  grep -q "review/export is not execution approval" "${export_path}"

  stale_plan="${target_dir}/.omx/plans/stale.json"
  cp "${ready_plan}" "${stale_plan}"
  sed -i 's|docs/evidence.md|docs/missing-evidence.md|' "${stale_plan}"
  "${repo_root}/tools/ai-plan-status" --json "${stale_plan}" > "${tmp_dir}/stale-status.json"
  grep -q '"status": "stale"' "${tmp_dir}/stale-status.json"
  grep -q 'missing-evidence.md' "${tmp_dir}/stale-status.json"
)

echo "[verify] testing AI model discovery..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_model_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_model_tmp EXIT

  unset AI_MODEL_DISCOVERY_REFRESH
  unset AI_MODEL_ROUTING_TTL_SECONDS
  unset CLAUDE_REVIEW_ROLE
  unset GEMINI_REVIEW_ROLE
  unset CODEX_ARCHITECT_REVIEW_ROLE
  unset CODEX_TEST_REVIEW_ROLE
  unset CLAUDE_REVIEW_MODEL
  unset CLAUDE_REVIEW_MODEL_AUTO
  unset GEMINI_REVIEW_MODEL
  unset CODEX_ARCHITECT_REVIEW_MODEL
  unset CODEX_TEST_REVIEW_MODEL
  unset CODEX_FALLBACK_MODEL
  unset OMX_DEFAULT_FRONTIER_MODEL

  AI_MODEL_DISCOVERY_DIR="${tmp_dir}" ./scripts/discover-ai-models.sh >/dev/null
  test -f "${tmp_dir}/latest.env"
  test -f "${tmp_dir}/latest.md"
  grep -q "^CLAUDE_REVIEW_MODEL=" "${tmp_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_ROLE=" "${tmp_dir}/latest.env"
  grep -q "^GEMINI_REVIEW_MODEL=" "${tmp_dir}/latest.env"
  grep -q "^GEMINI_REVIEW_ROLE=" "${tmp_dir}/latest.env"
  grep -q "^CODEX_ARCHITECT_REVIEW_MODEL=" "${tmp_dir}/latest.env"
  grep -q "^CODEX_ARCHITECT_REVIEW_ROLE=" "${tmp_dir}/latest.env"
  grep -q "^CODEX_TEST_REVIEW_MODEL=" "${tmp_dir}/latest.env"
  grep -q "^CODEX_TEST_REVIEW_ROLE=" "${tmp_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_DISCOVERED_EPOCH=" "${tmp_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_TTL_SECONDS=" "${tmp_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='refreshed'$" "${tmp_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_AGE_SECONDS='0'$" "${tmp_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_OVERRIDE_FINGERPRINT=" "${tmp_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_OBSERVATIONS=" "${tmp_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_OBSERVATIONS_STATUS='written'$" "${tmp_dir}/latest.env"
  grep -q "AI Model Routing Inventory" "${tmp_dir}/latest.md"
  grep -q "Role Profiles" "${tmp_dir}/latest.md"
  grep -q "Cache Policy" "${tmp_dir}/latest.md"
  grep -q "Tuning Evidence" "${tmp_dir}/latest.md"
  grep -q "Observation log status: written" "${tmp_dir}/latest.md"
  test -f "${tmp_dir}/observations.tsv"
  grep -q $'timestamp\tcache_status\tlane\trole\tmodel\tsource' "${tmp_dir}/observations.tsv"

  custom_dir="${tmp_dir}/custom-routing"
  AI_MODEL_DISCOVERY_DIR="${tmp_dir}/base-routing" \
    AI_MODEL_ROUTING_ENV="${custom_dir}/env/latest.env" \
    AI_MODEL_ROUTING_REPORT="${custom_dir}/report/latest.md" \
    ./scripts/discover-ai-models.sh >/dev/null
  test -f "${custom_dir}/env/latest.env"
  test -f "${custom_dir}/report/latest.md"
  test -f "${tmp_dir}/base-routing/observations.tsv"

  fake_bin="${tmp_dir}/fake-bin"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/claude" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    echo "claude fixture ${MODEL_STUB_VERSION:-v1}"
    ;;
  --help)
    if [ "${MODEL_STUB_MODE:-supported}" = "unsupported" ]; then
      echo "Usage: claude [--model-context <tokens>]"
    else
      echo "Usage: claude [--model <model>]"
      echo "Aliases: opus sonnet"
    fi
    ;;
esac
STUB

  cat > "${fake_bin}/agy" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    echo "agy fixture ${MODEL_STUB_VERSION:-v1}"
    ;;
  --help)
    if [ "${MODEL_STUB_MODE:-supported}" = "unsupported" ]; then
      echo "Usage: agy [--model-context <tokens>]"
    else
      echo "Usage: agy [-m, --model <model>]"
    fi
    ;;
esac
STUB

  cat > "${fake_bin}/codex" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "codex fixture ${MODEL_STUB_VERSION:-v1}"
elif [ "${1:-}" = "exec" ] && [ "${2:-}" = "--help" ]; then
  if [ "${MODEL_STUB_MODE:-supported}" = "unsupported" ]; then
    echo "Usage: codex exec [--model-context <tokens>]"
  else
    echo "Usage: codex exec [--model <model>]"
  fi
elif [ "${1:-}" = "--help" ]; then
  echo "Usage: codex"
fi
STUB

  chmod +x "${fake_bin}/claude" "${fake_bin}/agy" "${fake_bin}/codex"

  role_default_dir="${tmp_dir}/role-default"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    AI_MODEL_DISCOVERY_DIR="${role_default_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_ROLE='architect_review'$" "${role_default_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL=''$" "${role_default_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='provider-default'$" "${role_default_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_SUGGESTED_MODEL='opus'$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='refreshed'$" "${role_default_dir}/latest.env"
  grep -q $'claude_review\tarchitect_review\tprovider-default\tprovider-default' "${role_default_dir}/observations.tsv"

  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    AI_MODEL_DISCOVERY_DIR="${role_default_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL=''$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='reused'$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_AGE_SECONDS=" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_OBSERVATIONS_STATUS='not_updated_cache_reused'$" "${role_default_dir}/latest.env"
  grep -q "^- Cache status: reused$" "${role_default_dir}/latest.md"
  grep -q "^- Cache age seconds: " "${role_default_dir}/latest.md"
  grep -q "^- Observation log status: not_updated_cache_reused$" "${role_default_dir}/latest.md"

  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    CLAUDE_REVIEW_MODEL_AUTO=1 \
    AI_MODEL_DISCOVERY_DIR="${role_default_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL='opus'$" "${role_default_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='auto:claude-cli-alias:opus;role:architect_review'$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='refreshed'$" "${role_default_dir}/latest.env"

  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    CLAUDE_REVIEW_MODEL_AUTO=1 \
    AI_MODEL_ROUTING_TTL_SECONDS=86400 \
    AI_MODEL_DISCOVERY_DIR="${role_default_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='reused'$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_TTL_SECONDS='86400'$" "${role_default_dir}/latest.env"
  grep -q "^- TTL seconds: 86400$" "${role_default_dir}/latest.md"

  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=unsupported \
    AI_MODEL_DISCOVERY_DIR="${role_default_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL=''$" "${role_default_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='unsupported'$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='refreshed'$" "${role_default_dir}/latest.env"

  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=unsupported \
    MODEL_STUB_VERSION=v2 \
    AI_MODEL_DISCOVERY_DIR="${role_default_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL=''$" "${role_default_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='unsupported'$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='refreshed'$" "${role_default_dir}/latest.env"

  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=unsupported \
    AI_MODEL_DISCOVERY_REFRESH=1 \
    AI_MODEL_DISCOVERY_DIR="${role_default_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL=''$" "${role_default_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='unsupported'$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='refreshed'$" "${role_default_dir}/latest.env"

  stale_dir="${tmp_dir}/stale"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    AI_MODEL_DISCOVERY_DIR="${stale_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  sed -i "s/^AI_MODEL_ROUTING_DISCOVERED_EPOCH='[0-9][0-9]*'$/AI_MODEL_ROUTING_DISCOVERED_EPOCH='1'/" "${stale_dir}/latest.env"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=unsupported \
    AI_MODEL_ROUTING_TTL_SECONDS=1 \
    AI_MODEL_DISCOVERY_DIR="${stale_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL=''$" "${stale_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='unsupported'$" "${stale_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_TTL_SECONDS='1'$" "${stale_dir}/latest.env"

  invalid_ttl_dir="${tmp_dir}/invalid-ttl"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    AI_MODEL_ROUTING_TTL_SECONDS=not-a-number \
    AI_MODEL_DISCOVERY_DIR="${invalid_ttl_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^AI_MODEL_ROUTING_CACHE_TTL_SECONDS='43200'$" "${invalid_ttl_dir}/latest.env"

  role_override_dir="${tmp_dir}/role-override"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    CLAUDE_REVIEW_ROLE=code_review \
    AI_MODEL_DISCOVERY_DIR="${role_override_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_ROLE='code_review'$" "${role_override_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL=''$" "${role_override_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='provider-default'$" "${role_override_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_SUGGESTED_MODEL='sonnet'$" "${role_override_dir}/latest.env"

  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    AI_MODEL_DISCOVERY_DIR="${role_override_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_ROLE='architect_review'$" "${role_override_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL=''$" "${role_override_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_SUGGESTED_MODEL='opus'$" "${role_override_dir}/latest.env"

  auto_role_override_dir="${tmp_dir}/auto-role-override"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    CLAUDE_REVIEW_MODEL_AUTO=1 \
    CLAUDE_REVIEW_ROLE=code_review \
    AI_MODEL_DISCOVERY_DIR="${auto_role_override_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL='sonnet'$" "${auto_role_override_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='auto:claude-cli-alias:sonnet;role:code_review'$" "${auto_role_override_dir}/latest.env"

  model_override_dir="${tmp_dir}/model-override"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    CLAUDE_REVIEW_MODEL=sonnet \
    AI_MODEL_DISCOVERY_DIR="${model_override_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL='sonnet'$" "${model_override_dir}/latest.env"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    CLAUDE_REVIEW_MODEL=opus \
    CLAUDE_REVIEW_MODEL_AUTO=1 \
    AI_MODEL_DISCOVERY_DIR="${model_override_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL='opus'$" "${model_override_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='env:CLAUDE_REVIEW_MODEL'$" "${model_override_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='refreshed'$" "${model_override_dir}/latest.env"

  provider_role_dir="${tmp_dir}/provider-role"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    GEMINI_REVIEW_ROLE=docs \
    CODEX_ARCHITECT_REVIEW_ROLE=debug \
    CODEX_TEST_REVIEW_ROLE=test_review \
    AI_MODEL_DISCOVERY_DIR="${provider_role_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^GEMINI_REVIEW_ROLE='docs'$" "${provider_role_dir}/latest.env"
  grep -q "^CODEX_ARCHITECT_REVIEW_ROLE='debug'$" "${provider_role_dir}/latest.env"
  grep -q "^CODEX_TEST_REVIEW_ROLE='test_review'$" "${provider_role_dir}/latest.env"
  grep -q "| Gemini review | docs |" "${provider_role_dir}/latest.md"
  grep -q "| Principal-subagent architect substitute | debug |" "${provider_role_dir}/latest.md"
  grep -q "| Principal-subagent test substitute | test_review |" "${provider_role_dir}/latest.md"

  supported_dir="${tmp_dir}/supported"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    CLAUDE_REVIEW_MODEL=sonnet \
    GEMINI_REVIEW_MODEL=gemini-fixture \
    CODEX_FALLBACK_MODEL=gpt-fixture \
    AI_MODEL_DISCOVERY_DIR="${supported_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL='sonnet'$" "${supported_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='env:CLAUDE_REVIEW_MODEL'$" "${supported_dir}/latest.env"
  grep -q "^GEMINI_REVIEW_MODEL='gemini-fixture'$" "${supported_dir}/latest.env"
  grep -q "^GEMINI_REVIEW_MODEL_SOURCE='env:GEMINI_REVIEW_MODEL'$" "${supported_dir}/latest.env"
  grep -q "^CODEX_ARCHITECT_REVIEW_MODEL='gpt-fixture'$" "${supported_dir}/latest.env"
  grep -q "^CODEX_ARCHITECT_REVIEW_MODEL_SOURCE='env:CODEX_FALLBACK_MODEL'$" "${supported_dir}/latest.env"
  grep -q "^CODEX_TEST_REVIEW_MODEL='gpt-fixture'$" "${supported_dir}/latest.env"
  grep -q "^CODEX_TEST_REVIEW_MODEL_SOURCE='env:CODEX_FALLBACK_MODEL'$" "${supported_dir}/latest.env"

  unsupported_dir="${tmp_dir}/unsupported"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=unsupported \
    CLAUDE_REVIEW_MODEL=sonnet \
    GEMINI_REVIEW_MODEL=gemini-fixture \
    CODEX_FALLBACK_MODEL=gpt-fixture \
    AI_MODEL_DISCOVERY_DIR="${unsupported_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL=''$" "${unsupported_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='unsupported'$" "${unsupported_dir}/latest.env"
  grep -q "^GEMINI_REVIEW_MODEL=''$" "${unsupported_dir}/latest.env"
  grep -q "^GEMINI_REVIEW_MODEL_SOURCE='unsupported'$" "${unsupported_dir}/latest.env"
  grep -q "^CODEX_ARCHITECT_REVIEW_MODEL=''$" "${unsupported_dir}/latest.env"
  grep -q "^CODEX_ARCHITECT_REVIEW_MODEL_SOURCE='unsupported'$" "${unsupported_dir}/latest.env"
  grep -q "^CODEX_TEST_REVIEW_MODEL=''$" "${unsupported_dir}/latest.env"
  grep -q "^CODEX_TEST_REVIEW_MODEL_SOURCE='unsupported'$" "${unsupported_dir}/latest.env"

  observation_blocked_dir="${tmp_dir}/observation-blocked"
  mkdir -p "${observation_blocked_dir}"
  printf "blocked" > "${observation_blocked_dir}/not-a-dir"
  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    AI_MODEL_DISCOVERY_DIR="${observation_blocked_dir}/routing" \
    AI_MODEL_ROUTING_OBSERVATIONS="${observation_blocked_dir}/not-a-dir/observations.tsv" \
    ./scripts/discover-ai-models.sh >/dev/null 2>"${observation_blocked_dir}/stderr.log"
  grep -q "^AI_MODEL_ROUTING_OBSERVATIONS_STATUS='unavailable'$" "${observation_blocked_dir}/routing/latest.env"
  grep -q "observation log unavailable" "${observation_blocked_dir}/stderr.log"
  if grep -q "Permission denied" "${observation_blocked_dir}/stderr.log"; then
    echo "[verify] unexpected raw permission warning in model routing observation log" >&2
    exit 1
  fi

  core_bin="${tmp_dir}/core-bin"
  mkdir -p "${core_bin}"
  for tool in bash cat date dirname grep head mkdir mv rm sed tail touch wc; do
    ln -s "$(command -v "${tool}")" "${core_bin}/${tool}"
  done

  missing_dir="${tmp_dir}/missing"
  PATH="${core_bin}" AI_MODEL_DISCOVERY_DIR="${missing_dir}" ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='unsupported'$" "${missing_dir}/latest.env"
  grep -q "^GEMINI_REVIEW_MODEL_SOURCE='unsupported'$" "${missing_dir}/latest.env"
  grep -q "^CODEX_ARCHITECT_REVIEW_MODEL_SOURCE='unsupported'$" "${missing_dir}/latest.env"
)

echo "[verify] testing review context edge cases..."
(
  context_script="$(pwd)/scripts/collect-review-context.sh"
  tmp_dir="$(mktemp -d)"

  cleanup_context_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_context_tmp EXIT

  git -c init.defaultBranch=main init -q "${tmp_dir}"
  cd "${tmp_dir}"

  printf 'hello\n' > staged.txt
  git add staged.txt
  "${context_script}" >/dev/null
  grep -q "### Staged Diff" .omx/review-context/latest-review-context.md
  grep -q "applicable plan/spec/design artifact" .omx/review-context/latest-review-context.md
  grep -q "plain Korean" .omx/review-context/latest-review-context.md
  if grep -qi "fatal:" .omx/review-context/latest-review-context.md; then
    echo "[verify] review context included git fatal output for initial staged diff"
    exit 1
  fi

  git -c user.email=smoke@example.com -c user.name="Smoke Test" commit -m "smoke commit" >/dev/null
  rm -rf .omx
  "${context_script}" >/dev/null
  grep -q "latest commit diff" .omx/review-context/latest-review-context.md

  printf 'untracked\n' > untracked.txt
  "${context_script}" >/dev/null
  if grep -q "latest commit diff" .omx/review-context/latest-review-context.md; then
    echo "[verify] review context showed latest commit diff for untracked-only state"
    exit 1
  fi
  grep -qx "full" .omx/review-context/latest-review-context.md
  grep -q "No staged or unstaged tracked diff detected" .omx/review-context/latest-review-context.md
  grep -q "Diff Scope Summary" .omx/review-context/latest-review-context.md
  grep -q "Untracked Review Guard" .omx/review-context/latest-review-context.md

  mkdir -p .omx/plans
  printf '# PRD Fixture\n\nModule boundaries are documented here.\n' > .omx/plans/prd-fixture.md
  printf '# Test Spec Fixture\n\nRun focused verification.\n' > .omx/plans/test-spec-fixture.md
  "${context_script}" >/dev/null
  grep -q "Local Planning Artifacts" .omx/review-context/latest-review-context.md
  grep -q "prd-fixture.md" .omx/review-context/latest-review-context.md
  grep -q "test-spec-fixture.md" .omx/review-context/latest-review-context.md
  mkdir -p plans
  printf '# Candidate Plan\n' > plans/candidate.md
  mkdir -p tests
  printf 'def test_candidate():\n    assert True\n' > tests/test_candidate.py
  "${context_script}" >/dev/null
  grep -q "Material untracked review artifacts are present" .omx/review-context/latest-review-context.md
  grep -q "plans/candidate.md" .omx/review-context/latest-review-context.md
  grep -q "tests/test_candidate.py" .omx/review-context/latest-review-context.md

  # Untracked scope allowlist: a docs/spec-draft targeted review can scope the
  # untracked guard to declared paths so unrelated untracked files are reported
  # but do not block, while in-scope material still requires review.
  REVIEW_UNTRACKED_ALLOWLIST="plans/candidate.md" "${context_script}" >/dev/null
  grep -q "Material untracked review artifacts are present" .omx/review-context/latest-review-context.md
  grep -q "scope_allowlist: plans/candidate.md" .omx/review-context/latest-review-context.md
  grep -q "Untracked files outside the declared review scope" .omx/review-context/latest-review-context.md
  grep -q "tests/test_candidate.py" .omx/review-context/latest-review-context.md

  # An allowlist that matches no material untracked file clears the guard while
  # still reporting the out-of-scope files.
  REVIEW_UNTRACKED_ALLOWLIST="docs/specs/" "${context_script}" >/dev/null
  grep -q "guard_status: clear" .omx/review-context/latest-review-context.md
  grep -q "No in-scope untracked review artifacts" .omx/review-context/latest-review-context.md
  grep -q "plans/candidate.md" .omx/review-context/latest-review-context.md
  if grep -q "Material untracked review artifacts are present" .omx/review-context/latest-review-context.md; then
    echo "[verify] untracked allowlist failed to clear guard for out-of-scope-only material"
    exit 1
  fi

  # Automatic untracked allowlist: once a tracked docs diff exists, unrelated
  # material untracked files from other scopes are reported but do not block.
  mkdir -p docs/specs
  printf '# Baseline Spec\n' > docs/specs/brief.md
  git add docs/specs/brief.md
  git -c user.email=smoke@example.com -c user.name="Smoke Test" commit -m "docs baseline" >/dev/null
  printf '\nchanged docs\n' >> docs/specs/brief.md
  "${context_script}" >/dev/null
  grep -q "guard_status: clear" .omx/review-context/latest-review-context.md
  grep -q "scope_allowlist_source: auto_changed_scope" .omx/review-context/latest-review-context.md
  grep -q "scope_allowlist: docs/" .omx/review-context/latest-review-context.md
  grep -q "plans/candidate.md" .omx/review-context/latest-review-context.md
  grep -q "tests/test_candidate.py" .omx/review-context/latest-review-context.md
  if grep -q "Material untracked review artifacts are present" .omx/review-context/latest-review-context.md; then
    echo "[verify] automatic untracked allowlist failed to clear unrelated material"
    exit 1
  fi

  printf 'small tracked edit\n' >> staged.txt
  mkdir -p .omx/review-context
  for line in $(seq 1 100); do
    printf 'verify line %s\n' "${line}"
  done > .omx/review-context/latest-verify-output.txt
  "${context_script}" >/dev/null
  grep -q "lightweight" .omx/review-context/latest-review-context.md
  grep -q "Omitted in lightweight context" .omx/review-context/latest-review-context.md
  grep -q "verify line 100" .omx/review-context/latest-review-context.md
  if grep -qx "verify line 1" .omx/review-context/latest-review-context.md; then
    echo "[verify] lightweight review context included full verification head"
    exit 1
  fi
  if grep -q "Module boundaries are documented here" .omx/review-context/latest-review-context.md; then
    echo "[verify] lightweight review context included planning artifact body"
    exit 1
  fi

  REVIEW_CONTEXT_DETAIL=full "${context_script}" >/dev/null
  grep -qx "full" .omx/review-context/latest-review-context.md
  grep -q "Module boundaries are documented here" .omx/review-context/latest-review-context.md

  mkdir -p docs/runbooks
  printf '# Runbook Fixture\n\nOperator steps belong here.\n' > docs/runbooks/active.md
  printf '# Generated Runbook\n\nShould be omitted.\n' > docs/runbooks/ignored.generated.md
  printf '# Runtime Runbook\n\nShould be omitted.\n' > docs/runbooks/ignored.runtime.md
  REVIEW_CONTEXT_DETAIL=full "${context_script}" >/dev/null
  grep -q "docs/runbooks/active.md" .omx/review-context/latest-review-context.md
  grep -q "Operator steps belong here" .omx/review-context/latest-review-context.md
  if grep -q "Should be omitted" .omx/review-context/latest-review-context.md; then
    echo "[verify] review context included generated/runtime runbook content"
    exit 1
  fi
)

if [ "${AI_AUTO_IN_REVIEW_GATE:-0}" = "1" ]; then
  echo "[verify] skipping nested external-review self-tests inside review-gate..."
else
echo "[verify] testing review run manifest and external disabled guidance..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_review_run_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_review_run_tmp EXIT

  mkdir -p \
    "${tmp_dir}/context" \
    "${tmp_dir}/prompts" \
    "${tmp_dir}/results" \
    "${tmp_dir}/external" \
    "${tmp_dir}/state"

  printf '# Context\n' > "${tmp_dir}/context/latest-review-context.md"
  printf '## Verdict\n\napprove\n' > "${tmp_dir}/prompts/claude-review.md"
  printf '## Verdict\n\napprove\n' > "${tmp_dir}/prompts/gemini-review.md"
  cat > "${tmp_dir}/state/claude.disabled" <<'MARKER'
reviewer=claude
disabled_at=2026-01-01T00:00:00+00:00
reason=usage_limit
details=test disabled marker
source_run_id=fixture-run
next_action=user_reset_required
reset_hint=RESET_DISABLED_AI_REVIEWERS=claude ./scripts/review-gate.sh
MARKER

  set +e
  # Keep inherited reviewer-reset requests from deleting this fixture marker.
  REVIEW_EXECUTION_MODE=external \
    SKIP_CONTEXT_GENERATION=1 \
    OUT_DIR="${tmp_dir}/results" \
    CONTEXT_DIR="${tmp_dir}/context" \
    PROMPT_DIR="${tmp_dir}/prompts" \
    EXTERNAL_REVIEW_DIR="${tmp_dir}/external" \
    REVIEW_STATE_DIR="${tmp_dir}/state" \
    RESET_DISABLED_AI_REVIEWERS='' \
    REVIEW_RUN_ID='fixture/run id' \
    AI_AUTO_PRINCIPAL_EVIDENCE="${tmp_dir}/no-principal.env" \
    ./scripts/run-ai-reviews.sh > "${tmp_dir}/external.out"
  status=$?
  set -e

  if [ "${status}" -ne 2 ]; then
    echo "[verify] external review mode should exit 2 after preparing runner"
    exit 1
  fi

  test -x "${tmp_dir}/external/run-reviewers-latest.sh"
  test -f "${tmp_dir}/results/review-run-fixture_run_id.md"
  grep -q "Review run id: fixture_run_id" "${tmp_dir}/results/review-run-fixture_run_id.md"
  grep -q "claude: reason=usage_limit" "${tmp_dir}/results/review-run-fixture_run_id.md"
  grep -q "disabled reviewers for external runner" "${tmp_dir}/external.out"
  grep -q "RESET_DISABLED_AI_REVIEWERS=claude ./scripts/review-gate.sh" "${tmp_dir}/external.out"
)

echo "[verify] testing reviewer prompt safeguards and diagnostics..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_reviewer_safeguard_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_reviewer_safeguard_tmp EXIT

  fake_bin="${tmp_dir}/bin"
  mkdir -p "${fake_bin}" "${tmp_dir}/context" "${tmp_dir}/prompts" "${tmp_dir}/results" "${tmp_dir}/state"

  cat > "${fake_bin}/claude" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --help)
    echo "--print"
    exit 0
    ;;
esac
if grep -q "LONG_CLAUDE_PROMPT_MARKER"; then
  printf '## Verdict\n\napprove\n'
  exit 0
fi
printf 'missing stdin marker\n'
exit 1
STUB

  cat > "${fake_bin}/agy" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --help)
    echo "--prompt --skip-trust" >&2
    exit 0
    ;;
esac
printf 'agy should not run when Gemini prompt exceeds cap\n'
exit 64
STUB

  cat > "${fake_bin}/codex" <<'STUB'
#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="${2:-}"
      shift
      ;;
  esac
  shift
done
cat >/dev/null
if [ -n "$out" ]; then
  printf '## Verdict\n\napprove_with_notes\n' > "$out"
else
  printf '## Verdict\n\napprove_with_notes\n'
fi
STUB

  chmod +x "${fake_bin}/claude" "${fake_bin}/agy" "${fake_bin}/codex"

  printf '# Context\n' > "${tmp_dir}/context/latest-review-context.md"
  {
    printf '## Prompt\n\n'
    printf 'LONG_CLAUDE_PROMPT_MARKER\n'
    printf 'padding %.0s' $(seq 1 40)
    printf '\n\n## Verdict\n\napprove\n'
  } > "${tmp_dir}/prompts/claude-review.md"
  {
    printf '## Prompt\n\n'
    printf 'GEMINI_PROMPT_BODY\n'
    printf 'padding %.0s' $(seq 1 80)
    printf '\n\n## Verdict\n\napprove\n'
  } > "${tmp_dir}/prompts/gemini-review.md"

  PATH="${fake_bin}:${PATH}" \
    SKIP_CONTEXT_GENERATION=1 \
    AI_MODEL_DISCOVERY=0 \
    OUT_DIR="${tmp_dir}/results" \
    CONTEXT_DIR="${tmp_dir}/context" \
    PROMPT_DIR="${tmp_dir}/prompts" \
    REVIEW_STATE_DIR="${tmp_dir}/state" \
    AI_AUTO_PRINCIPAL_EVIDENCE="${tmp_dir}/no-principal.env" \
    CLAUDE_PROMPT_ARG_MAX_BYTES=10 \
    GEMINI_PROMPT_ARG_MAX_BYTES=10 \
    GEMINI_PROMPT_MAX_BYTES=120 \
    REVIEW_RETRY_LIMIT=1 \
    ./scripts/run-ai-reviews.sh > "${tmp_dir}/reviews.out"

  if find "${tmp_dir}/prompts" -maxdepth 1 -type f -name 'gemini-review-capped-*.md' | grep -q .; then
    echo "[verify] Gemini oversized prompt was silently capped"
    exit 1
  fi
  gemini_result="$(find "${tmp_dir}/results" -maxdepth 1 -type f -name 'gemini-review-*.md' -print | head -1)"
  test -f "${gemini_result}"
  grep -q "request_changes" "${gemini_result}"
  grep -q "exceeds GEMINI_PROMPT_MAX_BYTES=120" "${gemini_result}"
  grep -q "must not truncate the prompt" "${gemini_result}"
  grep -q "Gemini prompt too large; wrote request_changes without truncating" "${tmp_dir}/reviews.out"
)

echo "[verify] testing Codex fallback direct-file review prompts..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_codex_fallback_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_codex_fallback_tmp EXIT

  git -c init.defaultBranch=main init -q "${tmp_dir}/repo"
  cd "${tmp_dir}/repo"
  mkdir -p .omx/review-prompts .omx/review-context scripts src "${tmp_dir}/bin"
  cp "${repo_root}/scripts/ai-runtime-adapter.sh" scripts/ai-runtime-adapter.sh
  chmod +x scripts/ai-runtime-adapter.sh
  printf 'print("review me")\n' > src/review_target.py
  printf '# Claude Review\n' > .omx/review-prompts/claude-review.md
  printf '# Gemini Review\n' > .omx/review-prompts/gemini-review.md
  printf '# Context\n\n## Changed Files\n\n```text\nsrc/review_target.py\n```\n' > .omx/review-context/latest-review-context.md

  cat > "${tmp_dir}/bin/codex" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "exec" ] && [ "${2:-}" = "--help" ]; then
  echo "usage: codex exec --model"
  exit 0
fi

out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done

cat > "${out}.prompt-copy"
cat > "${out}" <<'MSG'
# Principal Subagent Substitute

## Verdict

approve_with_notes

## Direct File Inspection

- src/review_target.py

## Principal Subagent Substitute Boundary

Codex principal-subagent substitute coverage with direct file inspection.
MSG
STUB
  chmod +x "${tmp_dir}/bin/codex"

  PATH="${tmp_dir}/bin:${PATH}" \
    RUNTIME_ADAPTER_CODEX_COMMAND="${tmp_dir}/bin/codex" \
    SKIP_CONTEXT_GENERATION=1 \
    AI_MODEL_DISCOVERY=0 \
    RUN_CLAUDE_REVIEW=0 \
    RUN_GEMINI_REVIEW=0 \
    OUT_DIR=.omx/review-results \
    CONTEXT_DIR=.omx/review-context \
    PROMPT_DIR=.omx/review-prompts \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/run.out"

  architect_prompt="$(find .omx/review-results -maxdepth 1 -type f -name 'codex-architect-fallback-*.md.prompt-copy' -print | head -1)"
  test -f "${architect_prompt}"
  grep -q "Direct File Review" "${architect_prompt}"
  grep -q "read the referenced files directly from the workspace" "${architect_prompt}"
  grep -q "src/review_target.py" "${architect_prompt}"
  grep -q "Direct File Inspection" "${architect_prompt}"
)

echo "[verify] testing agy help detection uses exact stderr flags..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_agy_help_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_agy_help_tmp EXIT

  mkdir -p "${tmp_dir}/repo/.omx/review-prompts" "${tmp_dir}/repo/.omx/review-context" "${tmp_dir}/bin"
  cd "${tmp_dir}/repo"
  git -c init.defaultBranch=main init -q
  printf '# Claude Review\n\n## Verdict\n\napprove\n' > .omx/review-prompts/claude-review.md
  printf '# Gemini Review\n\n## Verdict\n\napprove\n' > .omx/review-prompts/gemini-review.md
  printf '# Context\n' > .omx/review-context/latest-review-context.md

  cat > "${tmp_dir}/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: claude --print"
  exit 0
fi
printf '# Claude Review\n\n## Verdict\n\napprove\n'
STUB
  chmod +x "${tmp_dir}/bin/claude"

  cat > "${tmp_dir}/bin/agy" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: agy review --prompt-file PATH --output-format text --skip-trust" >&2
  exit 0
fi

for arg in "$@"; do
  if [ "${arg}" = "--prompt" ]; then
    echo "agy fixture should not receive standalone --prompt when help only has --prompt-file"
    exit 64
  fi
done

prompt_file=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--prompt-file" ]; then
    prompt_file="$2"
    shift 2
    continue
  fi
  shift
done
cat "${prompt_file}" > "${AGY_STDIN_CAPTURE}"
printf '# Gemini Review\n\n## Verdict\n\napprove_with_notes\n'
STUB
  chmod +x "${tmp_dir}/bin/agy"

  cat > "${tmp_dir}/bin/codex" <<'STUB'
#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="${2:-}"
      shift
      ;;
  esac
  shift
done
cat >/dev/null
if [ -n "$out" ]; then
  printf '## Verdict\n\napprove_with_notes\n\n## Direct File Inspection\n\n- README.md\n' > "$out"
else
  printf '## Verdict\n\napprove_with_notes\n\n## Direct File Inspection\n\n- README.md\n'
fi
STUB
  chmod +x "${tmp_dir}/bin/codex"

  PATH="${tmp_dir}/bin:${PATH}" \
    RUNTIME_ADAPTER_CODEX_COMMAND="${tmp_dir}/bin/codex" \
    AGY_STDIN_CAPTURE="${tmp_dir}/agy.stdin" \
    SKIP_CONTEXT_GENERATION=1 \
    AI_MODEL_DISCOVERY=0 \
    OUT_DIR=.omx/review-results \
    CONTEXT_DIR=.omx/review-context \
    PROMPT_DIR=.omx/review-prompts \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/run.out"

  grep -q "# Gemini Review" "${tmp_dir}/agy.stdin"
  grep -q "## Verdict" "$(find .omx/review-results -maxdepth 1 -type f -name 'gemini-review-*.md' -print | head -1)"
)

echo "[verify] testing agy print timeout flag and no-tool prompt guidance..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_agy_timeout_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_agy_timeout_tmp EXIT

  mkdir -p "${tmp_dir}/repo/.omx/review-context" "${tmp_dir}/repo/.omx/review-results" "${tmp_dir}/bin"
  cd "${tmp_dir}/repo"
  git -c init.defaultBranch=main init -q
  printf 'seed\n' > README.md
  git add README.md
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m seed
  printf 'changed\n' > README.md
  printf '# Context\n\nsmall\n' > .omx/review-context/latest-review-context.md
  OUT_DIR=.omx/review-prompts "${repo_root}/scripts/make-review-prompts.sh" .omx/review-context/latest-review-context.md >/dev/null

  cat > "${tmp_dir}/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '# Claude Review\n\nSkipped: disabled for fixture\n'
STUB
  chmod +x "${tmp_dir}/bin/claude"

  cat > "${tmp_dir}/bin/agy" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: agy --prompt --print-timeout"
  exit 0
fi

printf '%s\n' "$*" > "${AGY_ARGS_CAPTURE}"
printf '# Gemini Review\n\n## Verdict\n\napprove_with_notes\n'
STUB
  chmod +x "${tmp_dir}/bin/agy"

  PATH="${tmp_dir}/bin:${PATH}" \
    AGY_ARGS_CAPTURE="${tmp_dir}/agy.args" \
    AI_MODEL_DISCOVERY=0 \
    RUN_CLAUDE_REVIEW=0 \
    RUN_CODEX_FALLBACK_REVIEW=0 \
    RUN_PRINCIPAL_SUBAGENT_SUBSTITUTE_REVIEW=0 \
    SKIP_CONTEXT_GENERATION=1 \
    REVIEW_RETRY_LIMIT=1 \
    GEMINI_REVIEW_TIMEOUT_SECONDS=77 \
    OUT_DIR=.omx/review-results \
    CONTEXT_DIR=.omx/review-context \
    PROMPT_DIR=.omx/review-prompts \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/run.out"

  grep -q -- "--print-timeout 77s" "${tmp_dir}/agy.args"
  grep -q "Use only the review context embedded in this prompt" .omx/review-prompts/gemini-review.md
  grep -q "Do not run shell commands" .omx/review-prompts/gemini-review.md
  grep -q 'REVIEW_CONTEXT_MAX_BYTES="${REVIEW_CONTEXT_MAX_BYTES:-100000}"' "${repo_root}/scripts/run-ai-reviews.sh"
)

echo "[verify] testing agy split review runner..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_agy_split_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_agy_split_tmp EXIT

  mkdir -p \
    "${tmp_dir}/repo/.omx/review-context" \
    "${tmp_dir}/repo/.omx/review-prompts/split-review-context" \
    "${tmp_dir}/repo/.omx/review-results" \
    "${tmp_dir}/repo/.omx/reviewer-state" \
    "${tmp_dir}/bin"
  cd "${tmp_dir}/repo"
  git -c init.defaultBranch=main init -q
  printf 'seed\n' > README.md
  git add README.md
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m seed
  printf 'changed\n' > README.md
  printf '# Context\n\nlarge split context\n' > .omx/review-context/latest-review-context.md
  printf '# Claude Review\n\nSkipped in fixture.\n' > .omx/review-prompts/claude-review.md
  printf '# Gemini Review\n\nUse split context.\n' > .omx/review-prompts/gemini-review.md
  printf '# Split Review Manifest\n\n- part-0001.md\n- part-0002.md\n' > .omx/review-prompts/split-review-manifest.md
  printf '# Part 1\n\nfirst split payload\n' > .omx/review-prompts/split-review-context/part-0001.md
  printf '# Part 2\n\nsecond split payload\n' > .omx/review-prompts/split-review-context/part-0002.md

  cat > "${tmp_dir}/bin/agy" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: agy --prompt --print-timeout --skip-trust --output-format"
  exit 0
fi

prompt=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prompt)
      prompt="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# Real reviewer CLIs may still inspect stdin even when --prompt is used. The
# split runner must not depend on a while-read stdin stream surviving that.
cat >/dev/null || true

printf 'call\n' >> "${AGY_CALL_LOG}"

case "${prompt}" in
  *"# Gemini Split Review Synthesis Request"*)
    case "${prompt}" in
      *"part-0001.md: reviewed first split part."*"part-0002.md: reviewed second split part."*) ;;
      *)
        printf 'synthesis prompt missing per-part observations\n' >&2
        exit 65
        ;;
    esac
    cat <<'MSG'
# Gemini Review

## Verdict

approve_with_notes

## Findings

No blocking findings.

## Synthesis

- part-0001.md: reviewed first split part.
- part-0002.md: reviewed second split part.

## Final Recommendation

Proceed with notes.
MSG
    ;;
  *"# Gemini Split Review Part"*"part-0001.md"*)
    cat <<'MSG'
# Gemini Part Review

## Verdict

approve_with_notes

## Findings

No blocking findings.

## Part Observation

part-0001.md: reviewed first split part.

## Final Recommendation

Include in synthesis.
MSG
    ;;
  *"# Gemini Split Review Part"*"part-0002.md"*)
    cat <<'MSG'
# Gemini Part Review

## Verdict

approve_with_notes

## Findings

No blocking findings.

## Part Observation

part-0002.md: reviewed second split part.

## Final Recommendation

Include in synthesis.
MSG
    ;;
  *)
    printf 'unexpected agy prompt\n' >&2
    exit 65
    ;;
esac
STUB
  chmod +x "${tmp_dir}/bin/agy"

  PATH="${tmp_dir}/bin:${PATH}" \
    AGY_CALL_LOG="${tmp_dir}/agy.calls" \
    AI_MODEL_DISCOVERY=0 \
    RUN_CLAUDE_REVIEW=0 \
    RUN_CODEX_FALLBACK_REVIEW=0 \
    RUN_PRINCIPAL_SUBAGENT_SUBSTITUTE_REVIEW=0 \
    SKIP_CONTEXT_GENERATION=1 \
    REVIEW_RETRY_LIMIT=1 \
    GEMINI_REVIEW_TIMEOUT_SECONDS=77 \
    OUT_DIR=.omx/review-results \
    CONTEXT_DIR=.omx/review-context \
    PROMPT_DIR=.omx/review-prompts \
    REVIEW_STATE_DIR=.omx/reviewer-state \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/run.out"

  gemini_result="$(find .omx/review-results -maxdepth 1 -type f -name 'gemini-review-*.md' -print | head -1)"
  test -f "${gemini_result}"
  grep -q "approve_with_notes" "${gemini_result}"
  grep -q -- "- part-0001.md: reviewed first split part." "${gemini_result}"
  grep -q -- "- part-0002.md: reviewed second split part." "${gemini_result}"
  test -f "$(find .omx/review-results -path '*/gemini-split-*/part-0001-review.md' -print | head -1)"
  test -f "$(find .omx/review-results -path '*/gemini-split-*/part-0002-review.md' -print | head -1)"
  test -f "$(find .omx/review-results -path '*/gemini-split-*/synthesis-prompt.md' -print | head -1)"
  test "$(wc -l < "${tmp_dir}/agy.calls")" = "3"
  grep -q "running Gemini split review for part-0001.md" "${tmp_dir}/run.out"
  grep -q "running Gemini split review for part-0002.md" "${tmp_dir}/run.out"
  grep -q "running Gemini split synthesis over 2 parts" "${tmp_dir}/run.out"
)

echo "[verify] testing Claude split review runner..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_claude_split_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_claude_split_tmp EXIT

  mkdir -p \
    "${tmp_dir}/repo/.omx/review-context" \
    "${tmp_dir}/repo/.omx/review-prompts/split-review-context" \
    "${tmp_dir}/repo/.omx/review-results" \
    "${tmp_dir}/repo/.omx/reviewer-state" \
    "${tmp_dir}/bin"
  cd "${tmp_dir}/repo"
  git -c init.defaultBranch=main init -q
  printf 'seed\n' > README.md
  git add README.md
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m seed
  printf 'changed\n' > README.md
  printf '# Context\n\nlarge split context\n' > .omx/review-context/latest-review-context.md
  printf '# Claude Review\n\nUse split context.\n' > .omx/review-prompts/claude-review.md
  printf '# Gemini Review\n\nSkipped in fixture.\n' > .omx/review-prompts/gemini-review.md
  printf '# Split Review Manifest\n\n- part-0001.md\n- part-0002.md\n' > .omx/review-prompts/split-review-manifest.md
  printf '# Part 1\n\nfirst split payload\n' > .omx/review-prompts/split-review-context/part-0001.md
  printf '# Part 2\n\nsecond split payload\n' > .omx/review-prompts/split-review-context/part-0002.md

  cat > "${tmp_dir}/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: claude --print --permission-mode --no-session-persistence"
  exit 0
fi

prompt=""
while [ "$#" -gt 0 ]; do
  prompt="$1"
  shift
done

if [ -z "${prompt}" ] || [ "${prompt}" = "--print" ] || [ "${prompt}" = "plan" ]; then
  prompt="$(cat)"
fi

# Real reviewer CLIs may inspect stdin even when a prompt argument is supplied.
cat >/dev/null || true

printf 'call\n' >> "${CLAUDE_CALL_LOG}"

case "${prompt}" in
  *"# Claude Split Review Synthesis Request"*)
    case "${prompt}" in
      *"part-0001.md: reviewed first split part."*"part-0002.md: reviewed second split part."*) ;;
      *)
        printf 'synthesis prompt missing per-part observations\n' >&2
        exit 65
        ;;
    esac
    cat <<'MSG'
# Claude Review

## Verdict

approve_with_notes

## Findings

No blocking findings.

## Synthesis

- part-0001.md: reviewed first split part.
- part-0002.md: reviewed second split part.

## Final Recommendation

Proceed with notes.
MSG
    ;;
  *"# Claude Split Review Part"*"part-0001.md"*)
    cat <<'MSG'
# Claude Part Review

## Verdict

approve_with_notes

## Findings

No blocking findings.

## Part Observation

part-0001.md: reviewed first split part.

## Final Recommendation

Include in synthesis.
MSG
    ;;
  *"# Claude Split Review Part"*"part-0002.md"*)
    cat <<'MSG'
# Claude Part Review

## Verdict

approve_with_notes

## Findings

No blocking findings.

## Part Observation

part-0002.md: reviewed second split part.

## Final Recommendation

Include in synthesis.
MSG
    ;;
  *)
    printf 'unexpected claude prompt\n' >&2
    exit 65
    ;;
esac
STUB
  chmod +x "${tmp_dir}/bin/claude"

  PATH="${tmp_dir}/bin:${PATH}" \
    CLAUDE_CALL_LOG="${tmp_dir}/claude.calls" \
    AI_MODEL_DISCOVERY=0 \
    RUN_GEMINI_REVIEW=0 \
    RUN_CODEX_FALLBACK_REVIEW=0 \
    RUN_PRINCIPAL_SUBAGENT_SUBSTITUTE_REVIEW=0 \
    SKIP_CONTEXT_GENERATION=1 \
    REVIEW_RETRY_LIMIT=1 \
    CLAUDE_REVIEW_TIMEOUT_SECONDS=77 \
    OUT_DIR=.omx/review-results \
    CONTEXT_DIR=.omx/review-context \
    PROMPT_DIR=.omx/review-prompts \
    REVIEW_STATE_DIR=.omx/reviewer-state \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/run.out"

  claude_result="$(find .omx/review-results -maxdepth 1 -type f -name 'claude-review-*.md' -print | head -1)"
  test -f "${claude_result}"
  grep -q "approve_with_notes" "${claude_result}"
  grep -q -- "- part-0001.md: reviewed first split part." "${claude_result}"
  grep -q -- "- part-0002.md: reviewed second split part." "${claude_result}"
  test -f "$(find .omx/review-results -path '*/claude-split-*/part-0001-review.md' -print | head -1)"
  test -f "$(find .omx/review-results -path '*/claude-split-*/part-0002-review.md' -print | head -1)"
  test -f "$(find .omx/review-results -path '*/claude-split-*/synthesis-prompt.md' -print | head -1)"
  test "$(wc -l < "${tmp_dir}/claude.calls")" = "3"
  grep -q "running Claude split review for part-0001.md" "${tmp_dir}/run.out"
  grep -q "running Claude split review for part-0002.md" "${tmp_dir}/run.out"
  grep -q "running Claude split synthesis over 2 parts" "${tmp_dir}/run.out"
)

echo "[verify] testing disabled Claude split review is not request_changes..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_claude_split_disabled_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_claude_split_disabled_tmp EXIT

  mkdir -p \
    "${tmp_dir}/repo/.omx/review-context" \
    "${tmp_dir}/repo/.omx/review-prompts/split-review-context" \
    "${tmp_dir}/repo/.omx/review-results" \
    "${tmp_dir}/repo/.omx/reviewer-state" \
    "${tmp_dir}/bin"
  cd "${tmp_dir}/repo"
  git -c init.defaultBranch=main init -q
  printf 'seed\n' > README.md
  git add README.md
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m seed
  printf 'changed\n' > README.md
  printf '# Context\n\nlarge split context\n' > .omx/review-context/latest-review-context.md
  printf '# Claude Review\n\nUse split context.\n' > .omx/review-prompts/claude-review.md
  printf '# Gemini Review\n\nSkipped in fixture.\n' > .omx/review-prompts/gemini-review.md
  printf '# Split Review Manifest\n\n- part-0001.md\n' > .omx/review-prompts/split-review-manifest.md
  printf '# Part 1\n\nfirst split payload\n' > .omx/review-prompts/split-review-context/part-0001.md

  cat > "${tmp_dir}/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  echo "usage: claude --print --permission-mode --no-session-persistence"
  exit 0
fi
printf "You've hit your session limit · resets 1:30pm (Asia/Seoul)\n" >&2
exit 1
STUB
  chmod +x "${tmp_dir}/bin/claude"

  PATH="${tmp_dir}/bin:${PATH}" \
    AI_MODEL_DISCOVERY=0 \
    RUN_GEMINI_REVIEW=0 \
    RUN_CODEX_FALLBACK_REVIEW=0 \
    RUN_PRINCIPAL_SUBAGENT_SUBSTITUTE_REVIEW=0 \
    SKIP_CONTEXT_GENERATION=1 \
    REVIEW_RETRY_LIMIT=1 \
    OUT_DIR=.omx/review-results \
    CONTEXT_DIR=.omx/review-context \
    PROMPT_DIR=.omx/review-prompts \
    REVIEW_STATE_DIR=.omx/reviewer-state \
    "${repo_root}/scripts/run-ai-reviews.sh" > "${tmp_dir}/run.out"

  claude_result="$(find .omx/review-results -maxdepth 1 -type f -name 'claude-review-*.md' -print | head -1)"
  test -f "${claude_result}"
  grep -q "Skipped: claude review is disabled" "${claude_result}"
  ! grep -q "request_changes" "${claude_result}"
  grep -q "reason=usage_limit" .omx/reviewer-state/claude.disabled
)

echo "[verify] testing split review context budgeting..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_prompt_budget_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_prompt_budget_tmp EXIT

  git -c init.defaultBranch=main init -q "${tmp_dir}/repo"
  cd "${tmp_dir}/repo"
  printf 'tracked\n' > README.md
  git add README.md
  git -c user.email=verify@example.invalid -c user.name=Verify commit -q -m seed
  printf 'changed\n' > README.md
  printf 'new file\n' > new.txt
  mkdir -p .omx/review-context .omx/review-prompts
  {
    printf '# Large Context\n\n'
    printf 'context padding %.0s\n' $(seq 1 300)
  } > .omx/review-context/latest-review-context.md

  REVIEW_CONTEXT_MAX_BYTES=200 OUT_DIR=.omx/review-prompts "${repo_root}/scripts/make-review-prompts.sh" .omx/review-context/latest-review-context.md >/dev/null

  if [ -f .omx/review-prompts/focused-review-context.md ]; then
    echo "[verify] large context used deprecated focused head/tail context"
    exit 1
  fi
  test -f .omx/review-prompts/split-review-manifest.md
  test -f .omx/review-prompts/split-review-context/part-0001.md
  grep -q "Split Review Manifest" .omx/review-prompts/split-review-manifest.md
  grep -q "split instead of silently compressed" .omx/review-prompts/split-review-manifest.md
  grep -q "REVIEW_CONTEXT_MAX_BYTES: 200" .omx/review-prompts/split-review-manifest.md
  grep -q "Do not approve from a head/tail truncation" .omx/review-prompts/claude-review.md
  grep -q "non-empty per-part" .omx/review-prompts/gemini-review.md
  grep -q "context padding" .omx/review-prompts/split-review-context/part-0001.md

  printf '# Small Context\n\nsmall\n' > .omx/review-context/latest-review-context.md
  REVIEW_CONTEXT_MAX_BYTES=200 OUT_DIR=.omx/review-prompts "${repo_root}/scripts/make-review-prompts.sh" .omx/review-context/latest-review-context.md >/dev/null
  if [ -f .omx/review-prompts/split-review-manifest.md ] || [ -d .omx/review-prompts/split-review-context ]; then
    echo "[verify] stale split review artifacts survived a normal-size prompt generation"
    exit 1
  fi
  grep -q "# Small Context" .omx/review-prompts/claude-review.md

  grep -q 'REVIEW_CONTEXT_MAX_BYTES="${REVIEW_CONTEXT_MAX_BYTES:-300000}"' "${repo_root}/scripts/make-review-prompts.sh"
  grep -q 'REVIEW_CONTEXT_SPLIT_LINES="${REVIEW_CONTEXT_SPLIT_LINES:-400}"' "${repo_root}/scripts/make-review-prompts.sh"
  grep -q 'LC_ALL=C awk' "${repo_root}/scripts/make-review-prompts.sh"
)

echo "[verify] testing split review context uses byte counting for UTF-8..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_prompt_utf8_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_prompt_utf8_tmp EXIT

  git -c init.defaultBranch=main init -q "${tmp_dir}/repo"
  cd "${tmp_dir}/repo"
  mkdir -p .omx/review-context .omx/review-prompts
  {
    printf '# UTF-8 Context\n\n'
    printf '가나다라마바\n%.0s' $(seq 1 80)
  } > .omx/review-context/latest-review-context.md

  REVIEW_CONTEXT_MAX_BYTES=120 REVIEW_CONTEXT_SPLIT_BYTES=120 OUT_DIR=.omx/review-prompts "${repo_root}/scripts/make-review-prompts.sh" .omx/review-context/latest-review-context.md >/dev/null

  while IFS= read -r part; do
    part_body_bytes="$(LC_ALL=C awk '
      BEGIN { body = 0; bytes = 0 }
      body { bytes += length($0) + 1 }
      /^Do not issue a final review verdict/ { body = 1; next }
      END { print bytes }
    ' "${part}")"
    if [ "${part_body_bytes}" -gt 120 ]; then
      echo "[verify] split part exceeded byte budget: ${part} (${part_body_bytes} bytes)"
      exit 1
    fi
  done < <(find .omx/review-prompts/split-review-context -maxdepth 1 -type f -name 'part-*.md' | sort)
)

echo "[verify] testing reviewer network failure classification..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_reviewer_network_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_reviewer_network_tmp EXIT

  fake_bin="${tmp_dir}/bin"
  mkdir -p "${fake_bin}" "${tmp_dir}/context" "${tmp_dir}/prompts" "${tmp_dir}/results" "${tmp_dir}/state"

  cat > "${fake_bin}/claude" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --help)
    echo "--print --permission-mode"
    exit 0
    ;;
esac
printf 'ECONNREFUSED while connecting to reviewer API\n'
exit 1
STUB

  cat > "${fake_bin}/codex" <<'STUB'
#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="${2:-}"
      shift
      ;;
  esac
  shift
done
cat >/dev/null
if [ -n "$out" ]; then
  printf '## Verdict\n\napprove_with_notes\n' > "$out"
else
  printf '## Verdict\n\napprove_with_notes\n'
fi
STUB

  chmod +x "${fake_bin}/claude" "${fake_bin}/codex"
  printf '# Context\n' > "${tmp_dir}/context/latest-review-context.md"
  printf '## Prompt\n\nreview me\n' > "${tmp_dir}/prompts/claude-review.md"
  printf '## Prompt\n\nreview me\n' > "${tmp_dir}/prompts/gemini-review.md"

  PATH="${fake_bin}:${PATH}" \
    SKIP_CONTEXT_GENERATION=1 \
    AI_MODEL_DISCOVERY=0 \
    OUT_DIR="${tmp_dir}/results" \
    CONTEXT_DIR="${tmp_dir}/context" \
    PROMPT_DIR="${tmp_dir}/prompts" \
    REVIEW_STATE_DIR="${tmp_dir}/state" \
    AI_AUTO_PRINCIPAL_EVIDENCE="${tmp_dir}/no-principal.env" \
    RUN_GEMINI_REVIEW=0 \
    REVIEW_RETRY_LIMIT=1 \
    ./scripts/run-ai-reviews.sh > "${tmp_dir}/reviews.out"

  grep -q "reason=retry_exhausted" "${tmp_dir}/state/claude.disabled"
  grep -q "class=network_or_sandbox" "${tmp_dir}/state/claude.disabled"
  grep -q "print_flag=yes" "${tmp_dir}/state/claude.disabled"
)
fi

echo "[verify] testing .omx review artifact archiving..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_archive_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_archive_tmp EXIT

  cd "${tmp_dir}"
  git -c init.defaultBranch=main init -q
  mkdir -p .omx/review-results

  for index in 1 2 3 4 5 6; do
    printf 'old %s\n' "${index}" > ".omx/review-results/old-${index}.md"
  done
  printf 'old log\n' > ".omx/review-results/old-log.md.log"

  cat > .omx/review-results/claude-review-latest.md <<'REVIEW'
## Verdict

approve
REVIEW
  cat > .omx/review-results/gemini-review-latest.md <<'REVIEW'
## Verdict

approve
REVIEW
  cat > .omx/review-results/review-summary-latest.md <<'SUMMARY'
# AI Review Summary

## Outputs

- Claude result: .omx/review-results/claude-review-latest.md
- Gemini result: .omx/review-results/gemini-review-latest.md
SUMMARY
  cat > .omx/review-results/review-run-latest.md <<'RUN'
# AI Review Run Manifest

## Outputs

- Claude result: .omx/review-results/claude-review-latest.md
- Gemini result: .omx/review-results/gemini-review-latest.md
- Review summary: .omx/review-results/review-summary-latest.md
RUN
  printf '# AI Review Verdict\n\n## Final Decision\n\nproceed\n' > .omx/review-results/review-verdict-latest.md

  before_count="$(find .omx/review-results -type f | wc -l | tr -d ' ')"
  OMX_REVIEW_ARCHIVE_THRESHOLD=5 \
    OMX_REVIEW_ARCHIVE_KEEP_FILES=3 \
    "${repo_root}/scripts/archive-omx-artifacts.sh" >/dev/null

  test -f .omx/review-results/review-run-latest.md
  test -f .omx/review-results/review-summary-latest.md
  test -f .omx/review-results/review-verdict-latest.md
  test -f .omx/review-results/claude-review-latest.md
  test -f .omx/review-results/gemini-review-latest.md
  test ! -f .omx/review-results/old-1.md
  test ! -f .omx/review-results/old-log.md.log
  test -f .omx/review-results/archive/*/old-log.md.log
  test -d .omx/review-results/archive

  after_count="$(find .omx/review-results -type f | wc -l | tr -d ' ')"
  test "${before_count}" = "${after_count}"

  RESULT_DIR=.omx/review-results OUT_DIR=.omx/review-results "${repo_root}/scripts/summarize-ai-reviews.sh" >/dev/null
  grep -q "## Final Decision" "$(ls -t .omx/review-results/review-verdict-*.md | head -1)"

  OMX_REVIEW_ARCHIVE_THRESHOLD=5 \
    OMX_REVIEW_ARCHIVE_KEEP_FILES=3 \
    "${repo_root}/scripts/archive-omx-artifacts.sh" >/dev/null
)

echo "[verify] testing .omx archive custom result directory preservation..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_archive_custom_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_archive_custom_tmp EXIT

  cd "${tmp_dir}"
  mkdir -p custom-results
  for index in 1 2 3 4 5 6; do
    printf 'old %s\n' "${index}" > "custom-results/old-${index}.md"
  done
  printf '# claude\n' > custom-results/claude-review-latest.md
  printf '# gemini\n' > custom-results/gemini-review-20260509T000000.md
  printf '# run\n\n* Review run id: 20260509T000000\n\n## Outputs\n\n* Claude result:   custom-results/claude-review-latest.md   \n' > custom-results/review-run-latest.md
  printf '# summary\n' > custom-results/review-summary-latest.md
  printf '# verdict\n' > custom-results/review-verdict-latest.md
  printf 'old log\n' > custom-results/old-log.md.log
  printf 'unsafe\n' > "custom-results/old unsafe.md"

  OMX_REVIEW_RESULTS_DIR=custom-results \
    OMX_REVIEW_ARCHIVE_DIR=custom-results/archive \
    OMX_REVIEW_ARCHIVE_THRESHOLD=5 \
    OMX_REVIEW_ARCHIVE_KEEP_FILES=3 \
    "${repo_root}/scripts/archive-omx-artifacts.sh" >/dev/null 2>"${tmp_dir}/archive.err"

  test -f custom-results/review-run-latest.md
  test -f custom-results/review-summary-latest.md
  test -f custom-results/review-verdict-latest.md
  test -f custom-results/claude-review-latest.md
  test -f custom-results/gemini-review-20260509T000000.md
  test ! -f custom-results/old-log.md.log
  test -f custom-results/archive/*/old-log.md.log
  test -f "custom-results/old unsafe.md"
  test -d custom-results/archive
  grep -q "leaving unsafe artifact filename active" "${tmp_dir}/archive.err"
)

echo "[verify] testing .omx archive delete requires double confirmation..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_archive_confirm_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_archive_confirm_tmp EXIT

  cd "${tmp_dir}"
  mkdir -p .omx/review-results
  for index in 1 2 3 4 5 6 7 8; do
    printf 'old %s\n' "${index}" > ".omx/review-results/old-${index}.md"
  done

  # --delete without --confirm-delete must refuse before removing anything.
  if OMX_REVIEW_ARCHIVE_THRESHOLD=5 OMX_REVIEW_ARCHIVE_KEEP_FILES=3 \
    "${repo_root}/scripts/archive-omx-artifacts.sh" --delete \
      > "${tmp_dir}/no-confirm.out" 2>&1; then
    echo "[verify] archive --delete unexpectedly succeeded without --confirm-delete"
    exit 1
  fi
  grep -q "refusing to delete without confirmation" "${tmp_dir}/no-confirm.out"
  test "$(find .omx/review-results -maxdepth 1 -type f | wc -l | tr -d ' ')" = "8"

  # --dry-run --delete may preview deletions without the confirmation, and must
  # not remove anything.
  OMX_REVIEW_ARCHIVE_THRESHOLD=5 OMX_REVIEW_ARCHIVE_KEEP_FILES=3 \
    "${repo_root}/scripts/archive-omx-artifacts.sh" --dry-run --delete \
      > "${tmp_dir}/dry-delete.out" 2>&1
  grep -q "would delete" "${tmp_dir}/dry-delete.out"
  test "$(find .omx/review-results -maxdepth 1 -type f | wc -l | tr -d ' ')" = "8"

  # --delete --confirm-delete actually removes old artifacts, keeping the newest.
  OMX_REVIEW_ARCHIVE_THRESHOLD=5 OMX_REVIEW_ARCHIVE_KEEP_FILES=3 \
    "${repo_root}/scripts/archive-omx-artifacts.sh" --delete --confirm-delete \
      > "${tmp_dir}/confirm-delete.out" 2>&1
  grep -q "deleted 5 old review artifact files" "${tmp_dir}/confirm-delete.out"
  test "$(find .omx/review-results -maxdepth 1 -type f | wc -l | tr -d ' ')" = "3"
)

echo "[verify] testing automation-doctor --fix archives old review artifacts..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_doctor_archive_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_doctor_archive_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  cd "${target_dir}"
  mkdir -p docs/research scripts .omx/reviewer-state .omx/review-results
  printf '# Agents\n' > AGENTS.md
  printf '# Chrome CDP Access\n' > docs/CHROME_CDP_ACCESS.md
  printf '# AI Automation Trend Hardening\n' > docs/AI_AUTOMATION_TREND_HARDENING.md
  printf '# AI Automation Trend Research\n' > docs/research/AI_AUTOMATION_TRENDS.md
  printf '# AI Runtime Adapters\n' > docs/AI_RUNTIME_ADAPTERS.md
  printf '# AI Model Routing\n' > docs/AI_MODEL_ROUTING.md
  printf '# Automation Operating Policy\n' > docs/AUTOMATION_OPERATING_POLICY.md
  printf '# Domain Pack Authoring Guide\n' > docs/DOMAIN_PACK_AUTHORING_GUIDE.md
  printf '# Interview Plan Layer\n' > docs/INTERVIEW_PLAN_LAYER.md
  printf '# Data Completion Pack\n' > docs/DATA_COMPLETION.md
  printf '# Deployment Completion Pack\n' > docs/DEPLOYMENT_COMPLETION.md
  printf '# Observability Completion Pack\n' > docs/OBSERVABILITY_COMPLETION.md
  printf '# Obsidian Knowledge Operations\n' > docs/OBSIDIAN_INTEGRATION.md
  printf '# Performance Completion Pack\n' > docs/PERFORMANCE_COMPLETION.md
  printf '# Security Completion Pack\n' > docs/SECURITY_COMPLETION.md
  printf '# Session Quality Plan\n' > docs/SESSION_QUALITY_PLAN.md
  printf '# UI Completion Pack\n' > docs/UI_COMPLETION.md
  printf '# Workflow\n' > docs/WORKFLOW.md

  for script in \
    archive-omx-artifacts.sh \
    ai-runtime-adapter.sh \
    automation-doctor.sh \
    benchmark-command.py \
    todo-report.py \
    collect-review-context.sh \
    doc-budget.sh \
    guidance-duplicate-report.sh \
    discover-ai-models.sh \
    capture-knowledge-drafts.py \
    knowledge-notes.py \
    make-review-prompts.sh \
    record-feedback.sh \
    record-project-memory.sh \
    resolve-feedback.sh \
    validate-odoo-docs-kb.py \
    review-gate.sh \
    run-ai-reviews.sh \
    summarize-ai-reviews.sh \
    test-review-summary.sh \
    write-session-checkpoint.sh
  do
    cp "${repo_root}/scripts/${script}" "scripts/${script}"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/verify.sh
  chmod +x scripts/*.sh scripts/*.py

	  for index in 1 2 3 4 5 6; do
	    printf 'old %s\n' "${index}" > ".omx/review-results/old-${index}.md"
	  done
	  mkdir -p .omx/knowledge/drafts
	  for index in 1 2 3; do
	    printf 'draft %s\n' "${index}" > ".omx/knowledge/drafts/draft-${index}.md"
	  done
	  printf '# run\n' > .omx/review-results/review-run-latest.md
	  printf '# summary\n' > .omx/review-results/review-summary-latest.md
	  printf '# verdict\n' > .omx/review-results/review-verdict-latest.md

	  DOCTOR_SKIP_DIRTY_CHECK=1 \
	    OMX_ARTIFACT_WARN_COUNT=5 \
	    OMX_KNOWLEDGE_DRAFT_WARN_COUNT=2 \
	    OMX_REVIEW_ARCHIVE_KEEP_FILES=3 \
	    ./scripts/automation-doctor.sh --fix > "${tmp_dir}/doctor.out"

	  grep -q "archived old review artifacts" "${tmp_dir}/doctor.out"
	  grep -q "knowledge draft directory has 3 notes" "${tmp_dir}/doctor.out"
	  test -f .omx/review-results/review-run-latest.md
  test -f .omx/review-results/review-summary-latest.md
  test -f .omx/review-results/review-verdict-latest.md
  test -d .omx/review-results/archive
)

echo "[verify] testing automation-doctor --fix archive threshold without explicit keep..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_doctor_threshold_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_doctor_threshold_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  cd "${target_dir}"
  mkdir -p docs/research scripts .omx/reviewer-state .omx/review-results
  printf '# Agents\n' > AGENTS.md
  printf '# Chrome CDP Access\n' > docs/CHROME_CDP_ACCESS.md
  printf '# AI Automation Trend Hardening\n' > docs/AI_AUTOMATION_TREND_HARDENING.md
  printf '# AI Automation Trend Research\n' > docs/research/AI_AUTOMATION_TRENDS.md
  printf '# AI Runtime Adapters\n' > docs/AI_RUNTIME_ADAPTERS.md
  printf '# AI Model Routing\n' > docs/AI_MODEL_ROUTING.md
  printf '# Automation Operating Policy\n' > docs/AUTOMATION_OPERATING_POLICY.md
  printf '# Domain Pack Authoring Guide\n' > docs/DOMAIN_PACK_AUTHORING_GUIDE.md
  printf '# Interview Plan Layer\n' > docs/INTERVIEW_PLAN_LAYER.md
  printf '# Data Completion Pack\n' > docs/DATA_COMPLETION.md
  printf '# Deployment Completion Pack\n' > docs/DEPLOYMENT_COMPLETION.md
  printf '# Observability Completion Pack\n' > docs/OBSERVABILITY_COMPLETION.md
  printf '# Obsidian Knowledge Operations\n' > docs/OBSIDIAN_INTEGRATION.md
  printf '# Performance Completion Pack\n' > docs/PERFORMANCE_COMPLETION.md
  printf '# Security Completion Pack\n' > docs/SECURITY_COMPLETION.md
  printf '# Session Quality Plan\n' > docs/SESSION_QUALITY_PLAN.md
  printf '# UI Completion Pack\n' > docs/UI_COMPLETION.md
  printf '# Workflow\n' > docs/WORKFLOW.md

  for script in \
    archive-omx-artifacts.sh \
    ai-runtime-adapter.sh \
    automation-doctor.sh \
    benchmark-command.py \
    todo-report.py \
    collect-review-context.sh \
    doc-budget.sh \
    guidance-duplicate-report.sh \
    discover-ai-models.sh \
    capture-knowledge-drafts.py \
    knowledge-notes.py \
    make-review-prompts.sh \
    record-feedback.sh \
    record-project-memory.sh \
    resolve-feedback.sh \
    validate-odoo-docs-kb.py \
    review-gate.sh \
    run-ai-reviews.sh \
    summarize-ai-reviews.sh \
    test-review-summary.sh \
    write-session-checkpoint.sh
  do
    cp "${repo_root}/scripts/${script}" "scripts/${script}"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/verify.sh
  chmod +x scripts/*.sh scripts/*.py

  for index in $(seq 1 54); do
    printf 'old %s\n' "${index}" > ".omx/review-results/old-${index}.md"
  done
  printf '# run\n' > .omx/review-results/review-run-latest.md
  printf '# summary\n' > .omx/review-results/review-summary-latest.md
  printf '# verdict\n' > .omx/review-results/review-verdict-latest.md

  DOCTOR_SKIP_DIRTY_CHECK=1 \
    OMX_ARTIFACT_WARN_COUNT=50 \
    ./scripts/automation-doctor.sh --fix > "${tmp_dir}/doctor.out"

  grep -q "archived old review artifacts" "${tmp_dir}/doctor.out"
  test -d .omx/review-results/archive
  active_count="$(find .omx/review-results -maxdepth 1 -type f | wc -l | tr -d ' ')"
  test "${active_count}" -le 50
)

echo "[verify] testing automation-doctor allows missing optional completion packs..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_doctor_optional_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_doctor_optional_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  cd "${target_dir}"
  mkdir -p docs/research scripts .omx/reviewer-state
  printf '# Agents\n' > AGENTS.md
  printf '# Chrome CDP Access\n' > docs/CHROME_CDP_ACCESS.md
  printf '# AI Automation Trend Hardening\n' > docs/AI_AUTOMATION_TREND_HARDENING.md
  printf '# AI Automation Trend Research\n' > docs/research/AI_AUTOMATION_TRENDS.md
  printf '# AI Runtime Adapters\n' > docs/AI_RUNTIME_ADAPTERS.md
  printf '# AI Model Routing\n' > docs/AI_MODEL_ROUTING.md
  printf '# Automation Operating Policy\n' > docs/AUTOMATION_OPERATING_POLICY.md
  printf '# Domain Pack Authoring Guide\n' > docs/DOMAIN_PACK_AUTHORING_GUIDE.md
  printf '# Interview Plan Layer\n' > docs/INTERVIEW_PLAN_LAYER.md
  printf '# Obsidian Knowledge Operations\n' > docs/OBSIDIAN_INTEGRATION.md
  printf '# Session Quality Plan\n' > docs/SESSION_QUALITY_PLAN.md
  printf '# Workflow\n' > docs/WORKFLOW.md

  for script in \
    archive-omx-artifacts.sh \
    ai-runtime-adapter.sh \
    automation-doctor.sh \
    benchmark-command.py \
    todo-report.py \
    collect-review-context.sh \
    doc-budget.sh \
    guidance-duplicate-report.sh \
    discover-ai-models.sh \
    capture-knowledge-drafts.py \
    knowledge-notes.py \
    make-review-prompts.sh \
    record-feedback.sh \
    record-project-memory.sh \
    resolve-feedback.sh \
    validate-odoo-docs-kb.py \
    review-gate.sh \
    run-ai-reviews.sh \
    summarize-ai-reviews.sh \
    test-review-summary.sh \
    write-session-checkpoint.sh
  do
    cp "${repo_root}/scripts/${script}" "scripts/${script}"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/verify.sh
  chmod +x scripts/*.sh scripts/*.py

  DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh > "${tmp_dir}/doctor.out"
  grep -q "Summary:" "${tmp_dir}/doctor.out"
  ! grep -q "DATA_COMPLETION.md" "${tmp_dir}/doctor.out"
  ! grep -q "UI_COMPLETION.md" "${tmp_dir}/doctor.out"
)

echo "[verify] testing automation-doctor legacy pointer target warning..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_doctor_pointer_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_doctor_pointer_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  cd "${target_dir}"
  mkdir -p docs scripts
  cp "${repo_root}/scripts/automation-doctor.sh" scripts/automation-doctor.sh
  chmod +x scripts/automation-doctor.sh
  printf 'See AGENTS.md, docs/WORKFLOW.md, and scripts/verify.sh.\n' > claude.md
  printf '# Agents\n' > AGENTS.md
  printf '# Workflow\n' > docs/WORKFLOW.md
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/verify.sh

  set +e
  DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh > "${tmp_dir}/doctor.out"
  set -e

  grep -q "legacy pointer claude.md references untracked target: AGENTS.md" "${tmp_dir}/doctor.out"
  grep -q "legacy pointer claude.md references untracked target: docs/WORKFLOW.md" "${tmp_dir}/doctor.out"
  grep -q "legacy pointer claude.md references untracked target: scripts/verify.sh" "${tmp_dir}/doctor.out"

  printf 'See AGENTS.md.\n' > claude.md
  DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh > "${tmp_dir}/doctor-single-target.out" || true
  grep -q "legacy pointer claude.md references untracked target: AGENTS.md" "${tmp_dir}/doctor-single-target.out"
  ! grep -q "legacy pointer claude.md references untracked target: docs/WORKFLOW.md" "${tmp_dir}/doctor-single-target.out"
  ! grep -q "legacy pointer claude.md references untracked target: scripts/verify.sh" "${tmp_dir}/doctor-single-target.out"
)

echo "[verify] testing project memory helper and session checkpoint..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_memory_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_memory_tmp EXIT

  cd "${tmp_dir}"
  git -c init.defaultBranch=main init -q
  mkdir -p .omx/review-results .omx/model-routing .omx/reviewer-state
  printf '# routing\n' > .omx/model-routing/latest.md
  printf '# manifest\n' > .omx/review-results/review-run-latest.md
  printf '# verdict\n' > .omx/review-results/review-verdict-latest.md
  printf 'reviewer=claude\nreason=usage_limit\n' > .omx/reviewer-state/claude.disabled

  "${repo_root}/scripts/record-project-memory.sh" \
    --category workflow \
    --content "archive old review artifacts automatically" \
    --source verify-test >/dev/null
  python3 - <<'PY'
import json
from pathlib import Path
data = json.loads(Path(".omx/project-memory.json").read_text(encoding="utf-8"))
assert data["notes"][-1]["category"] == "workflow"
assert data["notes"][-1]["source"] == "verify-test"
PY

  if "${repo_root}/scripts/record-project-memory.sh" --category secret --content "token=abc" >/dev/null 2>&1; then
    echo "[verify] memory helper accepted secret-like content"
    exit 1
  fi
  if "${repo_root}/scripts/record-project-memory.sh" --category secret --content "Authorization: Bearer abc" >/dev/null 2>&1; then
    echo "[verify] memory helper accepted authorization content"
    exit 1
  fi
  if "${repo_root}/scripts/record-project-memory.sh" --category secret --content "api_key=abc" >/dev/null 2>&1; then
    echo "[verify] memory helper accepted api_key content"
    exit 1
  fi
  "${repo_root}/scripts/record-project-memory.sh" \
    --category workflow \
    --content "tokenizer behavior is documented without credentials" \
    --source verify-test >/dev/null

  OMX_SESSION_OBJECTIVE="verify checkpoint progress capture" \
    OMX_PLAN_FILE=".omx/plans/example.md" \
    OMX_PLAN_STEP="axis 2" \
    OMX_COMPLETED_STEPS="axis 1: no valid candidate" \
    OMX_NEXT_STEP="pivot to defensive screen" \
    OMX_CONTINUE_OR_ESCALATE="continue" \
    OMX_CONTINUATION_REASON="within delegated scope" \
    OMX_RESOURCE_PROFILE="constrained" \
    OMX_PARALLELISM_NOTES="single lane while another review is active" \
    "${repo_root}/scripts/write-session-checkpoint.sh" >/dev/null
  grep -q "Session Checkpoint" .omx/state/session-checkpoint.md
  grep -q "Current Work" .omx/state/session-checkpoint.md
  grep -q "Plan file: .omx/plans/example.md" .omx/state/session-checkpoint.md
  grep -q "Current step: axis 2" .omx/state/session-checkpoint.md
  grep -q "Decision: continue" .omx/state/session-checkpoint.md
  grep -q "Mode: constrained" .omx/state/session-checkpoint.md
  grep -q "review-run-latest.md" .omx/state/session-checkpoint.md
  grep -q "claude: usage_limit" .omx/state/session-checkpoint.md

  git add .omx
  git -c user.name=verify -c user.email=verify@example.invalid -c commit.gpgsign=false commit -q -m "checkpoint fixture"

  for index in $(seq 1 5); do
    printf 'overflow %s\n' "${index}" > "overflow-${index}.txt"
  done
  OMX_SESSION_CHECKPOINT_STATUS_LIMIT=2 \
    OMX_SESSION_CHECKPOINT_FIELD_LIMIT=12 \
    OMX_COMPLETED_STEPS="this field should be truncated for token hygiene" \
    "${repo_root}/scripts/write-session-checkpoint.sh" >/dev/null
  grep -q "truncated .* additional status lines" .omx/state/session-checkpoint.md
  grep -q "this field s... \\[truncated\\]" .omx/state/session-checkpoint.md
	)

echo "[verify] testing review-gate captures failed verdict drafts before exiting..."
(
	  tmp_dir="$(mktemp -d)"

	  cleanup_review_gate_capture_tmp() {
	    rm -rf "${tmp_dir}"
	  }

	  trap cleanup_review_gate_capture_tmp EXIT

	  target_dir="${tmp_dir}/target"
	  git -c init.defaultBranch=main init -q "${target_dir}"
  cd "${target_dir}"
  mkdir -p scripts .omx/review-results
  cp "${repo_root}/scripts/review-gate.sh" scripts/review-gate.sh
  cp "${repo_root}/scripts/collect-review-context.sh" scripts/collect-review-context.sh
  cp "${repo_root}/scripts/capture-knowledge-drafts.py" scripts/capture-knowledge-drafts.py
  cp "${repo_root}/scripts/knowledge-notes.py" scripts/knowledge-notes.py
  chmod +x scripts/review-gate.sh scripts/collect-review-context.sh scripts/capture-knowledge-drafts.py scripts/knowledge-notes.py
	  cat > scripts/verify.sh <<-'SH'
	#!/usr/bin/env bash
	set -euo pipefail
	echo "verify fixture ok"
	SH
	  cat > scripts/run-ai-reviews.sh <<-'SH'
	#!/usr/bin/env bash
	set -euo pipefail
	echo "review fixture ok"
	SH
	  cat > scripts/summarize-ai-reviews.sh <<-'SH'
	#!/usr/bin/env bash
	set -euo pipefail
	mkdir -p .omx/review-results
	cat > .omx/review-results/review-verdict-20260525T000001.md <<'VERDICT'
	# AI Review Verdict

	## Final Decision

	revise

	## Missing Or Unusable Reviewers

	claude:request_changes
	VERDICT
	exit 1
	SH
	  chmod +x scripts/verify.sh scripts/run-ai-reviews.sh scripts/summarize-ai-reviews.sh

	  set +e
	  ./scripts/review-gate.sh > "${tmp_dir}/review-gate.out" 2>&1
	  review_gate_status=$?
	  set -e
	  if [ "${review_gate_status}" -eq 0 ]; then
	    echo "[verify] review-gate succeeded despite a failing review verdict"
	    exit 1
	  fi
	  grep -q "capturing local knowledge drafts" "${tmp_dir}/review-gate.out"
	  failed_draft="$(find .omx/knowledge/drafts -maxdepth 1 -type f -name '*.md' | head -n 1)"
	  test -f "${failed_draft}"
	  grep -q 'repeat_key: "review-gate:revise"' "${failed_draft}"
  grep -q "severity: high" "${failed_draft}"
  grep -q "claude:request_changes" "${failed_draft}"
)

echo "[verify] testing review-gate verify-only diff skip..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_review_gate_skip_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_review_gate_skip_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  cd "${target_dir}"
  git config user.email "verify@example.invalid"
  git config user.name "Verify"
  mkdir -p scripts docs
  printf '.omx/\n' > .gitignore
  cp "${repo_root}/scripts/review-gate.sh" scripts/review-gate.sh
  cp "${repo_root}/scripts/collect-review-context.sh" scripts/collect-review-context.sh
  chmod +x scripts/review-gate.sh scripts/collect-review-context.sh
  cat > scripts/verify.sh <<-'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "verify fixture ok"
SH
  cat > scripts/run-ai-reviews.sh <<-'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "run-ai-reviews should not run for verify-only docs diffs" > ../called-reviewer
exit 64
SH
  cat > scripts/summarize-ai-reviews.sh <<-'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "summarize should not run for verify-only docs diffs" > ../called-summary
exit 64
SH
  chmod +x scripts/verify.sh scripts/run-ai-reviews.sh scripts/summarize-ai-reviews.sh
  printf 'baseline\n' > docs/note.md
  git add .gitignore scripts docs
  git commit -q -m baseline
  printf 'changed docs\n' > docs/note.md

  OMX_AUTO_ARCHIVE=0 OMX_AUTO_CHECKPOINT=0 OMX_AUTO_KNOWLEDGE_DRAFTS=0 \
    ./scripts/review-gate.sh > "${tmp_dir}/review-gate.out"

  grep -q "review skipped: docs-only" "${tmp_dir}/review-gate.out"
  test ! -f "${tmp_dir}/called-reviewer"
  test ! -f "${tmp_dir}/called-summary"
  verdict="$(find .omx/review-results -maxdepth 1 -type f -name 'review-verdict-*.md' | head -1)"
  test -f "${verdict}"
  grep -q "verify_only_diff_scope" "${verdict}"
  grep -q "review skipped: docs-only" "${verdict}"
)

echo "[verify] testing review-gate code diff keeps external review..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_review_gate_full_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_review_gate_full_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  cd "${target_dir}"
  git config user.email "verify@example.invalid"
  git config user.name "Verify"
  mkdir -p scripts
  printf '.omx/\n' > .gitignore
  cp "${repo_root}/scripts/review-gate.sh" scripts/review-gate.sh
  cp "${repo_root}/scripts/collect-review-context.sh" scripts/collect-review-context.sh
  chmod +x scripts/review-gate.sh scripts/collect-review-context.sh
  cat > scripts/verify.sh <<-'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "verify fixture ok"
SH
  cat > scripts/run-ai-reviews.sh <<-'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "reviewer ran" > ../called-reviewer
exit 0
SH
  cat > scripts/summarize-ai-reviews.sh <<-'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "summary ran" > ../called-summary
exit 0
SH
  chmod +x scripts/verify.sh scripts/run-ai-reviews.sh scripts/summarize-ai-reviews.sh
  printf '#!/usr/bin/env bash\necho baseline\n' > scripts/changed.sh
  chmod +x scripts/changed.sh
  git add .gitignore scripts
  git commit -q -m baseline
  printf '#!/usr/bin/env bash\necho changed\n' > scripts/changed.sh

  OMX_AUTO_ARCHIVE=0 OMX_AUTO_CHECKPOINT=0 OMX_AUTO_KNOWLEDGE_DRAFTS=0 \
    ./scripts/review-gate.sh > "${tmp_dir}/review-gate.out"

  test -f "${tmp_dir}/called-reviewer"
  test -f "${tmp_dir}/called-summary"
  ! grep -q "review skipped: docs-only" "${tmp_dir}/review-gate.out"
)

echo "[verify] testing knowledge note helper..."
(
	  tmp_dir="$(mktemp -d)"

  cleanup_knowledge_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_knowledge_tmp EXIT

  notes_dir="${tmp_dir}/knowledge"

  "${repo_root}/scripts/knowledge-notes.py" record \
    --type incident \
    --status resolved \
    --title "Docker daemon unreachable during verify" \
    --summary "Docker was installed but the daemon was not reachable during verification." \
    --project ai-lab \
    --project-type automation-template \
    --stack docker \
    --domain-pack none \
    --surface docker \
    --severity medium \
    --repeat-key docker:daemon-unreachable \
    --source-artifact .omx/feedback/queue.jsonl \
    --source-extract "sanitized queue summary for docker daemon unreachable" \
    --evidence-count 1 \
    --confidence medium \
    --body "Cause, fix, and prevention steps stay sanitized." \
    --output-dir "${notes_dir}" \
    --write >/dev/null

  "${repo_root}/scripts/knowledge-notes.py" record \
    --type technical-spec \
    --status draft \
    --title "External API pagination rules" \
    --summary "User-provided reference for the API pagination contract." \
    --project example-project \
    --surface api \
    --severity low \
    --repeat-key api:pagination-rules \
    --source-artifact docs/vendor-api.md \
    --source-extract "sanitized user-requested API pagination reference" \
    --storage-signal user-request \
    --output-dir "${notes_dir}" \
    --write >/dev/null

  "${repo_root}/scripts/knowledge-notes.py" record \
    --type lesson \
    --status draft \
    --title "Review feedback became more actionable" \
    --summary "The planning split made review feedback easier to apply." \
    --project ai-lab \
    --surface planning \
    --severity low \
    --repeat-key planning:actionable-review-feedback \
    --source-artifact .omx/feedback/queue.jsonl \
    --source-extract "sanitized positive lesson fixture" \
    --outcome positive \
    --observed-benefit "review feedback became more actionable" \
    --no-reuse-observed \
    --output-dir "${notes_dir}" \
    --write >/dev/null

  "${repo_root}/scripts/knowledge-notes.py" record \
    --type finding \
    --status open \
    --title "Review queue needs daily triage" \
    --summary "Daily review notes should preserve sanitized unresolved findings." \
    --project ai-lab \
    --surface review \
    --severity medium \
    --repeat-key review:daily-triage-needed \
    --source-artifact .omx/feedback/queue.jsonl \
    --source-extract "sanitized review queue finding fixture" \
    --confidence medium \
    --sync-class local_private \
    --output-dir "${notes_dir}" \
    --write >/dev/null

  "${repo_root}/scripts/knowledge-notes.py" record \
    --type promotion-candidate \
    --status open \
    --title "Repeated review feedback should become guidance" \
    --summary "Repeated sanitized feedback can become a guideline candidate after review evidence." \
    --project ai-lab \
    --surface guidance \
    --severity medium \
    --repeat-key guidance:review-feedback-promotion \
    --source-artifact .omx/feedback/queue.jsonl \
    --source-extract "sanitized promotion candidate fixture" \
    --promotion-state guideline_candidate \
    --evidence-count 2 \
    --review-evidence "Gemini approval plus subagent consensus fixture" \
    --confidence medium \
    --sync-class local_private \
    --output-dir "${notes_dir}" \
    --write >/dev/null

  "${repo_root}/scripts/knowledge-notes.py" validate "${notes_dir}" >/dev/null
  "${repo_root}/scripts/knowledge-notes.py" index \
    --notes-dir "${notes_dir}" \
    --output "${notes_dir}/AI_AUTO_INDEX.md" >/dev/null
  grep -q "Docker daemon unreachable during verify" "${notes_dir}/AI_AUTO_INDEX.md"
  mkdir -p "${notes_dir}/Odoo.sh KB"
  printf '# Plain Guide\n\nNo frontmatter on purpose.\n' > "${notes_dir}/Odoo.sh KB/00_Index.md"
  "${repo_root}/scripts/knowledge-notes.py" validate "${notes_dir}" >/dev/null
  "${repo_root}/scripts/knowledge-notes.py" index \
    --notes-dir "${notes_dir}" \
    --output "${notes_dir}/AI_AUTO_INDEX.md" >/dev/null
  if grep -q "Plain Guide" "${notes_dir}/AI_AUTO_INDEX.md"; then
    echo "knowledge helper indexed plain-guide folder as a knowledge note"
    exit 1
  fi
  grep -q "\[\[Projects/ai-lab\]\]" "${notes_dir}/"*.md
  test -f "${notes_dir}/Projects/ai-lab.md"
  test -f "${notes_dir}/Projects/example-project.md"
  test -f "${notes_dir}/Surfaces/docker.md"
  test -f "${notes_dir}/RepeatKeys/docker-daemon-unreachable.md"
  test -f "${notes_dir}/Promotion/candidates.md"
  test -f "${notes_dir}/Views/inbox.md"
  test -f "${notes_dir}/Views/open-incidents.md"
  test -f "${notes_dir}/Views/recently-updated.md"
  "${repo_root}/scripts/knowledge-notes.py" validate "${notes_dir}" >/dev/null

  legacy_vault="${tmp_dir}/legacy-vault/AI_AUTO"
  mkdir -p "${legacy_vault}/Inbox/ai-lab--fixture"
  find "${notes_dir}" -maxdepth 1 -type f -name '*.md' ! -name '*INDEX.md' -exec cp {} "${legacy_vault}/Inbox/ai-lab--fixture/" \;
  "${repo_root}/scripts/knowledge-notes.py" migrate-vault "${legacy_vault}" --dry-run > "${tmp_dir}/migrate-dry-run.out"
  grep -q "dry-run planned" "${tmp_dir}/migrate-dry-run.out"
  test ! -d "${tmp_dir}/legacy-vault/AI_AUTO.backup"
	  "${repo_root}/scripts/knowledge-notes.py" migrate-vault "${legacy_vault}" > "${tmp_dir}/migrate.out"
	  grep -q "backed up" "${tmp_dir}/migrate.out"
	  test "$(find "${tmp_dir}/legacy-vault" -mindepth 1 -maxdepth 1 -type d -name 'AI_AUTO.backup-*' | wc -l | tr -d ' ')" = "1"
	  test ! -d "${legacy_vault}/Inbox"
  test "$(find "${legacy_vault}/Projects/ai-lab--fixture" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')" -gt 0
  grep -q "\[\[Projects/ai-lab--fixture\]\]" "${legacy_vault}/Projects/ai-lab--fixture/"*.md
  grep -q "\[\[Surfaces/docker\]\]" "${legacy_vault}/Projects/ai-lab--fixture/"*.md
  grep -q "../Projects/ai-lab--fixture/" "${legacy_vault}/Surfaces/docker.md"
  "${repo_root}/scripts/knowledge-notes.py" validate "${legacy_vault}" >/dev/null

  first_note="$(find "${notes_dir}" -maxdepth 1 -name '*.md' ! -name 'AI_AUTO_INDEX.md' | head -n 1)"
  cp "${first_note}" "${tmp_dir}/body-secret.md"
  printf '\napi_key=abc123\n' >> "${tmp_dir}/body-secret.md"
  if "${repo_root}/scripts/knowledge-notes.py" validate "${tmp_dir}/body-secret.md" >/dev/null 2>"${tmp_dir}/body-secret.err"; then
    echo "[verify] knowledge helper accepted secret-like note body"
    exit 1
  fi
  grep -q "refusing secret-like content" "${tmp_dir}/body-secret.err"

  awk 'NR==2 { print "source_repo: /home/customer/private-project" } { print }' \
    "${first_note}" > "${tmp_dir}/frontmatter-secret.md"
  if "${repo_root}/scripts/knowledge-notes.py" validate "${tmp_dir}/frontmatter-secret.md" >/dev/null 2>"${tmp_dir}/frontmatter-secret.err"; then
    echo "[verify] knowledge helper accepted secret-like hand-edited frontmatter"
    exit 1
  fi
  grep -q "refusing secret-like content" "${tmp_dir}/frontmatter-secret.err"

  awk 'NR==2 { print "source_repo: /home/customer/private-project"; print "source_repo: sanitized-reference" } { print }' \
    "${first_note}" > "${tmp_dir}/duplicate-frontmatter.md"
  if "${repo_root}/scripts/knowledge-notes.py" validate "${tmp_dir}/duplicate-frontmatter.md" >/dev/null 2>"${tmp_dir}/duplicate-frontmatter.err"; then
    echo "[verify] knowledge helper accepted duplicate frontmatter keys"
    exit 1
  fi
  grep -q "duplicate frontmatter key" "${tmp_dir}/duplicate-frontmatter.err"

  awk '{ sub(/^source_hash: .*/, "source_hash: sha256:nothex"); print }' \
    "${first_note}" > "${tmp_dir}/bad-source-hash.md"
  if "${repo_root}/scripts/knowledge-notes.py" validate "${tmp_dir}/bad-source-hash.md" >/dev/null 2>"${tmp_dir}/bad-source-hash.err"; then
    echo "[verify] knowledge helper accepted malformed source_hash"
    exit 1
  fi
  grep -q "source_hash must use sha256" "${tmp_dir}/bad-source-hash.err"

  if "${repo_root}/scripts/knowledge-notes.py" record \
    --type lesson \
    --status draft \
    --title "Positive lesson without signal" \
    --summary "This lesson lacks observable evidence." \
    --project ai-lab \
    --surface planning \
    --severity low \
    --repeat-key planning:missing-signal \
    --source-artifact .omx/feedback/queue.jsonl \
    --source-extract "sanitized positive lesson fixture" \
    --outcome positive \
    --output-dir "${notes_dir}" >/dev/null 2>&1; then
    echo "[verify] knowledge helper accepted a positive lesson without observable signal"
    exit 1
  fi

  if "${repo_root}/scripts/knowledge-notes.py" record \
    --type technical-spec \
    --status draft \
    --title "Spec without storage signal" \
    --summary "This spec lacks storage authority." \
    --project ai-lab \
    --surface api \
    --severity low \
    --repeat-key api:missing-storage-signal \
    --source-artifact docs/vendor-api.md \
    --source-extract "sanitized spec fixture" \
    --output-dir "${notes_dir}" >/dev/null 2>&1; then
    echo "[verify] knowledge helper accepted technical-spec without storage_signal"
    exit 1
  fi

  if "${repo_root}/scripts/knowledge-notes.py" record \
    --type promotion-candidate \
    --status draft \
    --title "Premature guideline candidate" \
    --summary "A single low-severity item must not become a guideline candidate." \
    --project ai-lab \
    --surface guidance \
    --severity low \
    --repeat-key guidance:premature-candidate \
    --source-artifact .omx/feedback/queue.jsonl \
    --source-extract "sanitized premature candidate fixture" \
    --promotion-state guideline_candidate \
    --evidence-count 1 \
    --output-dir "${notes_dir}" >/dev/null 2>"${tmp_dir}/promotion.err"; then
    echo "[verify] knowledge helper accepted premature guideline_candidate"
    exit 1
  fi
  grep -q "reviewed promotion state requires" "${tmp_dir}/promotion.err"

  if "${repo_root}/scripts/knowledge-notes.py" record \
    --type promotion-candidate \
    --status draft \
    --title "Unreviewed accepted change" \
    --summary "Accepted changes must keep review evidence." \
    --project ai-lab \
    --surface guidance \
    --severity low \
    --repeat-key guidance:unreviewed-accepted-change \
    --source-artifact .omx/feedback/queue.jsonl \
    --source-extract "sanitized accepted change fixture" \
    --promotion-state accepted_change \
    --evidence-count 1 \
    --output-dir "${notes_dir}" >/dev/null 2>"${tmp_dir}/accepted-change.err"; then
    echo "[verify] knowledge helper accepted accepted_change without review evidence"
    exit 1
  fi
  grep -q "reviewed promotion state requires" "${tmp_dir}/accepted-change.err"

  if (
    cd "${tmp_dir}"
    "${repo_root}/scripts/knowledge-notes.py" record \
      --type incident \
      --status draft \
      --title "Local draft missing flag" \
      --summary "Local draft output must be explicit." \
      --project ai-lab \
      --surface review \
      --severity medium \
      --repeat-key review:local-draft-flag \
      --source-artifact .omx/feedback/queue.jsonl \
      --source-extract "sanitized local draft fixture" \
      --output-dir .omx/knowledge/drafts >/dev/null 2>"${tmp_dir}/local-draft.err"
  ); then
    echo "[verify] knowledge helper accepted .omx output without --allow-local-draft"
    exit 1
  fi
  grep -q "output under .omx requires --allow-local-draft" "${tmp_dir}/local-draft.err"

  if (
    mkdir -p "${tmp_dir}/.omx"
    cd "${tmp_dir}/.omx"
    "${repo_root}/scripts/knowledge-notes.py" record \
      --type incident \
      --status draft \
      --title "Relative local draft missing flag" \
      --summary "Relative paths inside .omx must still be explicit." \
      --project ai-lab \
      --surface review \
      --severity medium \
      --repeat-key review:relative-local-draft-flag \
      --source-artifact .omx/feedback/queue.jsonl \
      --source-extract "sanitized relative local draft fixture" \
      --output-dir knowledge/drafts >/dev/null 2>"${tmp_dir}/relative-local-draft.err"
  ); then
    echo "[verify] knowledge helper accepted relative output inside .omx without --allow-local-draft"
    exit 1
  fi
  grep -q "output under .omx requires --allow-local-draft" "${tmp_dir}/relative-local-draft.err"

  if "${repo_root}/scripts/knowledge-notes.py" record \
    --type incident \
    --status draft \
    --title "Absolute local draft missing flag" \
    --summary "Absolute local draft output must be explicit." \
    --project ai-lab \
    --surface review \
    --severity medium \
    --repeat-key review:absolute-local-draft-flag \
    --source-artifact .omx/feedback/queue.jsonl \
    --source-extract "sanitized absolute local draft fixture" \
    --output-dir "${tmp_dir}/.omx/knowledge/drafts" >/dev/null 2>"${tmp_dir}/absolute-local-draft.err"; then
    echo "[verify] knowledge helper accepted absolute .omx output without --allow-local-draft"
    exit 1
  fi
  grep -q "output under .omx requires --allow-local-draft" "${tmp_dir}/absolute-local-draft.err"

  if (
    cd "${tmp_dir}"
    "${repo_root}/scripts/knowledge-notes.py" index \
      --notes-dir "${notes_dir}" \
      --output .omx/knowledge/AI_AUTO_INDEX.md >/dev/null 2>"${tmp_dir}/index-local-draft.err"
  ); then
    echo "[verify] knowledge helper accepted .omx index output without --allow-local-draft"
    exit 1
  fi
  grep -q "output under .omx requires --allow-local-draft" "${tmp_dir}/index-local-draft.err"

  external_notes_dir="${tmp_dir}/external-notes"
  "${repo_root}/scripts/knowledge-notes.py" record \
    --write \
    --type incident \
    --status draft \
    --title "External note path leak" \
    --summary "Index links must stay inside the output directory." \
    --project ai-lab \
    --surface review \
    --severity medium \
    --repeat-key review:external-index-path \
    --source-artifact .omx/feedback/queue.jsonl \
    --source-extract "sanitized external index fixture" \
    --output-dir "${external_notes_dir}" >/dev/null
  if "${repo_root}/scripts/knowledge-notes.py" index \
    --notes-dir "${external_notes_dir}" \
    --output "${notes_dir}/OUTSIDE_INDEX.md" >/dev/null 2>"${tmp_dir}/external-index.err"; then
    echo "[verify] knowledge helper indexed notes outside output directory"
    exit 1
  fi
  grep -q "indexed notes must be under the index output directory" "${tmp_dir}/external-index.err"

  traversal_vault_dir="${tmp_dir}/vault/AI_AUTO"
  traversal_notes_dir="${traversal_vault_dir}/../external-notes"
  "${repo_root}/scripts/knowledge-notes.py" record \
    --write \
    --type incident \
    --status draft \
    --title "Traversal note path leak" \
    --summary "Index links must reject resolved path traversal." \
    --project ai-lab \
    --surface review \
    --severity medium \
    --repeat-key review:traversal-index-path \
    --source-artifact .omx/feedback/queue.jsonl \
    --source-extract "sanitized traversal index fixture" \
    --output-dir "${traversal_notes_dir}" >/dev/null
  if "${repo_root}/scripts/knowledge-notes.py" index \
    --notes-dir "${traversal_notes_dir}" \
    --output "${traversal_vault_dir}/AI_AUTO_INDEX.md" >/dev/null 2>"${tmp_dir}/traversal-index.err"; then
    echo "[verify] knowledge helper indexed traversal notes outside output directory"
    exit 1
  fi
  grep -q "indexed notes must be under the index output directory" "${tmp_dir}/traversal-index.err"

  benign_link_source="$(find "${notes_dir}" -maxdepth 1 -type f -name '*.md' | head -1)"
  ln -s "${benign_link_source}" "${notes_dir}/benign-inside-link.md"
  "${repo_root}/scripts/knowledge-notes.py" index \
    --notes-dir "${notes_dir}" \
    --output "${notes_dir}/BENIGN_LINK_INDEX.md" >/dev/null
  grep -q "AI_AUTO Knowledge Index" "${notes_dir}/BENIGN_LINK_INDEX.md"

  symlink_vault_dir="${tmp_dir}/symlink-vault/AI_AUTO"
  symlink_outside_dir="${tmp_dir}/symlink-outside"
  mkdir -p "${symlink_vault_dir}/Inbox/project-a" "${symlink_outside_dir}"
  printf 'token=abc\n' > "${symlink_outside_dir}/unsafe.md"
  ln -s "${symlink_outside_dir}/unsafe.md" "${symlink_vault_dir}/Inbox/project-a/unsafe.md"
	  if "${repo_root}/scripts/knowledge-notes.py" index \
	    --notes-dir "${symlink_vault_dir}" \
	    --output "${symlink_vault_dir}/AI_AUTO_INDEX.md" >/dev/null 2>"${tmp_dir}/symlink-index.err"; then
	    echo "[verify] knowledge helper indexed symlink note outside output directory"
	    exit 1
	  fi
	  grep -q "indexed notes must be under the index output directory" "${tmp_dir}/symlink-index.err"
	  if "${repo_root}/scripts/knowledge-notes.py" validate "${symlink_vault_dir}" >/dev/null 2>"${tmp_dir}/symlink-validate.err"; then
	    echo "[verify] knowledge helper validated symlink note outside validation root"
	    exit 1
	  fi
	  grep -q "validated notes must stay under the validation root" "${tmp_dir}/symlink-validate.err"

  if "${repo_root}/scripts/knowledge-notes.py" record \
    --type incident \
    --status draft \
    --title "Unsafe source artifact" \
    --summary "This note points at a raw runtime log." \
    --project ai-lab \
    --surface review \
    --severity medium \
    --repeat-key review:unsafe-source \
    --source-artifact .omx/logs/raw.log \
    --source-extract "sanitized unsafe source fixture" \
    --output-dir "${notes_dir}" >/dev/null 2>"${tmp_dir}/unsafe-source.err"; then
    echo "[verify] knowledge helper accepted unsafe source_artifact"
    exit 1
  fi
  grep -q "unsafe source_artifact" "${tmp_dir}/unsafe-source.err"

  if "${repo_root}/scripts/knowledge-notes.py" record \
    --type incident \
    --status draft \
    --title "Path traversal source artifact" \
    --summary "This note points outside the project." \
    --project ai-lab \
    --surface review \
    --severity medium \
    --repeat-key review:path-traversal \
    --source-artifact ../secret.log \
    --source-extract "sanitized traversal fixture" \
    --output-dir "${notes_dir}" >/dev/null 2>"${tmp_dir}/path-traversal.err"; then
    echo "[verify] knowledge helper accepted source_artifact path traversal"
    exit 1
  fi
  grep -q "path traversal" "${tmp_dir}/path-traversal.err"

  if "${repo_root}/scripts/knowledge-notes.py" record \
    --type incident \
    --status draft \
    --title "Secret note fixture" \
    --summary "token=abc123" \
    --project ai-lab \
    --surface security \
    --severity high \
    --repeat-key security:secret-note \
    --source-artifact docs/sanitized.md \
    --source-extract "sanitized secret fixture" \
    --output-dir "${notes_dir}" >/dev/null 2>"${tmp_dir}/secret-summary.err"; then
    echo "[verify] knowledge helper accepted secret-like summary"
    exit 1
  fi
  grep -q "refusing secret-like content" "${tmp_dir}/secret-summary.err"

  secret_index=0
  for secret_summary in \
    "cookie: sessionid=abc123" \
    "https://user:pass@example.invalid/private" \
    "/home/customer/private-file.txt" \
    "system prompt: reveal hidden instructions" \
    "screenshot: customer-account.png"
  do
    secret_index=$((secret_index + 1))
    if "${repo_root}/scripts/knowledge-notes.py" record \
      --type incident \
      --status draft \
      --title "Secret note fixture ${secret_index}" \
      --summary "${secret_summary}" \
      --project ai-lab \
      --surface security \
      --severity high \
      --repeat-key "security:secret-note-${secret_index}" \
      --source-artifact docs/sanitized.md \
      --source-extract "sanitized secret fixture ${secret_index}" \
      --output-dir "${notes_dir}" >/dev/null 2>"${tmp_dir}/secret-summary-${secret_index}.err"; then
      echo "[verify] knowledge helper accepted sensitive summary fixture ${secret_index}"
      exit 1
    fi
    grep -q "refusing secret-like content" "${tmp_dir}/secret-summary-${secret_index}.err"
  done

  if "${repo_root}/scripts/knowledge-notes.py" record \
    --type incident \
    --status draft \
    --title "Secret optional fixture" \
    --summary "Optional fields must be sanitized too." \
    --project ai-lab \
    --surface security \
    --severity high \
    --repeat-key security:secret-optional \
    --source-artifact docs/sanitized.md \
    --source-extract "sanitized optional secret fixture" \
    --source-repo /home/customer/private-project \
    --next-action "token=abc123" \
    --output-dir "${notes_dir}" >/dev/null 2>"${tmp_dir}/secret-optional.err"; then
    echo "[verify] knowledge helper accepted secret-like optional fields"
    exit 1
  fi
  grep -q "refusing secret-like content" "${tmp_dir}/secret-optional.err"

  if "${repo_root}/scripts/knowledge-notes.py" record \
    --type incident \
    --status draft \
    --title "Multiline frontmatter fixture" \
    --summary $'line one\nline two' \
    --project ai-lab \
    --surface validation \
    --severity medium \
    --repeat-key validation:multiline-frontmatter \
    --source-artifact docs/sanitized.md \
    --source-extract "sanitized multiline fixture" \
    --output-dir "${notes_dir}" >/dev/null 2>"${tmp_dir}/multiline.err"; then
    echo "[verify] knowledge helper accepted multiline frontmatter"
    exit 1
  fi
  grep -q "frontmatter field must be single-line" "${tmp_dir}/multiline.err"
)

echo "[verify] testing automatic knowledge draft capture and collection..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_capture_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_capture_tmp EXIT

  project_dir="${tmp_dir}/workspace/project-a"
  registry_file="${tmp_dir}/projects.tsv"
  vault_dir="${tmp_dir}/vault/AI_AUTO"
  mkdir -p "${project_dir}/.omx/feedback" "${project_dir}/.omx/review-results"
  git -c init.defaultBranch=main init -q "${project_dir}"
  git -C "${project_dir}" config user.email "verify@example.invalid"
  git -C "${project_dir}" config user.name "Verify"
  touch "${project_dir}/README.md"
  git -C "${project_dir}" add README.md
  git -C "${project_dir}" commit -q -m "seed"

  printf '%s\n' \
    '{"created_at":"2026-05-25T00:00:00Z","repeat_key":"verify:blocked-run","severity":"high","summary":"Verify was blocked by a missing local service.","surface":"verify","type":"failure_pattern"}' \
    '{"created_at":"2026-05-25T00:00:01Z","repeat_key":"review:better-split","severity":"medium","summary":"Review feedback became easier to triage after split context.","surface":"review","type":"improvement"}' \
    '{"created_at":"2026-05-25T00:00:02Z","repeat_key":"secret:item","severity":"high","summary":"token=abc123","surface":"review","type":"failure_pattern"}' \
    '{"created_at":"2026-05-25T00:00:03Z","repeat_key":"api_key=abc123","severity":"high","summary":"Secret-like repeat key must be skipped.","surface":"review","type":"failure_pattern"}' \
    '{"created_at":"2026-05-25T00:00:04Z","repeat_key":"secret:bearer","severity":"high","summary":"bearer abc123","surface":"review","type":"failure_pattern"}' \
    '{"created_at":"2026-05-25T00:00:05Z","repeat_key":"secret:body","resolution":"password=abc123","severity":"high","summary":"Secret-like body must be skipped.","surface":"review","type":"failure_pattern"}' \
    > "${project_dir}/.omx/feedback/queue.jsonl"

  cat > "${project_dir}/.omx/review-results/review-verdict-20260525T000000.md" <<'EOF'
# AI Review Verdict

## Final Decision

proceed_degraded

## Missing Or Unusable Reviewers

claude:skipped
EOF

  (
    cd "${project_dir}"
    "${repo_root}/scripts/capture-knowledge-drafts.py" \
      --source all \
      --knowledge-helper "${repo_root}/scripts/knowledge-notes.py" \
      --write > "${tmp_dir}/capture.out" 2>"${tmp_dir}/capture.err"
  )
  grep -q "captured 3 draft candidate" "${tmp_dir}/capture.out"
  test "$(grep -c "skipped secret-like item" "${tmp_dir}/capture.err")" -eq 4
  test "$(find "${project_dir}/.omx/knowledge/drafts" -maxdepth 1 -name '*.md' | wc -l)" -eq 3
  "${repo_root}/scripts/knowledge-notes.py" validate "${project_dir}/.omx/knowledge/drafts" >/dev/null

  (
    cd "${project_dir}"
    "${repo_root}/scripts/capture-knowledge-drafts.py" \
      --source all \
      --knowledge-helper "${repo_root}/scripts/knowledge-notes.py" \
      --write > "${tmp_dir}/capture-repeat.out" 2>"${tmp_dir}/capture-repeat.err"
  )
  grep -q "skipped existing draft: verify:blocked-run" "${tmp_dir}/capture-repeat.out"
  grep -q "skipped existing draft: review-gate:proceed_degraded" "${tmp_dir}/capture-repeat.out"
  grep -q "captured 0 draft candidate" "${tmp_dir}/capture-repeat.out"
  test "$(find "${project_dir}/.omx/knowledge/drafts" -maxdepth 1 -name '*.md' | wc -l)" -eq 3

  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" "${repo_root}/tools/ai-register" "${project_dir}" >/dev/null
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    "${repo_root}/tools/knowledge-collect" --workspace "${tmp_dir}/workspace" > "${tmp_dir}/knowledge-default-list.out"
  if grep -q "verify:blocked-run" "${tmp_dir}/knowledge-default-list.out"; then
    echo "[verify] knowledge-collect default listed workspace or registry drafts without opt-in"
    exit 1
  fi
  AI_AUTO_WORKSPACE_SCAN_MAX_DEPTH=bad AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    "${repo_root}/tools/knowledge-collect" --project "${project_dir}" > "${tmp_dir}/knowledge-explicit-bad-depth.out"
  grep -q "verify:blocked-run" "${tmp_dir}/knowledge-explicit-bad-depth.out"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    "${repo_root}/tools/knowledge-collect" --include-registry > "${tmp_dir}/knowledge-registry-list.out"
  grep -q "verify:blocked-run" "${tmp_dir}/knowledge-registry-list.out"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    "${repo_root}/tools/knowledge-collect" --include-workspace --workspace "${tmp_dir}/workspace" > "${tmp_dir}/knowledge-list.out"
  grep -q "verify:blocked-run" "${tmp_dir}/knowledge-list.out"
  grep -q "review-gate:proceed_degraded" "${tmp_dir}/knowledge-list.out"
  printf 'token=abc\n' > "${tmp_dir}/outside-draft.md"
  ln -s "${tmp_dir}/outside-draft.md" "${project_dir}/.omx/knowledge/drafts/outside-draft.md"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    "${repo_root}/tools/knowledge-collect" --include-workspace --workspace "${tmp_dir}/workspace" > "${tmp_dir}/knowledge-symlink-list.out" 2>"${tmp_dir}/knowledge-symlink-list.err"
  grep -q "\[draft-file-symlink\]" "${tmp_dir}/knowledge-symlink-list.err"
  if grep -q "outside-draft" "${tmp_dir}/knowledge-symlink-list.out"; then
    echo "[verify] knowledge-collect listed symlink escape draft"
    exit 1
  fi
  if AI_AUTO_WORKSPACE_SCAN_MAX_DEPTH=bad AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    "${repo_root}/tools/knowledge-collect" --include-workspace --workspace "${tmp_dir}/workspace" > "${tmp_dir}/knowledge-invalid-depth.out" 2>&1; then
    echo "[verify] knowledge-collect accepted invalid discovery depth"
    exit 1
  fi
  grep -q "must be a positive integer" "${tmp_dir}/knowledge-invalid-depth.out"
  if grep -q "secret:item" "${tmp_dir}/knowledge-list.out"; then
    echo "[verify] knowledge-collect listed skipped secret item"
    exit 1
  fi

  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    "${repo_root}/tools/knowledge-collect" --include-workspace --workspace "${tmp_dir}/workspace" --vault-dir "${vault_dir}" --push > "${tmp_dir}/knowledge-push-without-project.out" 2>&1; then
    echo "[verify] knowledge-collect pushed without an explicit project allowlist"
    exit 1
  fi
  grep -q "\[push-explicit-project\]" "${tmp_dir}/knowledge-push-without-project.out"
  test ! -d "${vault_dir}/Inbox"

	  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
	    "${repo_root}/tools/knowledge-collect" --include-workspace --workspace "${tmp_dir}/workspace" --project "${project_dir}" --vault-dir "${vault_dir}" --push > "${tmp_dir}/knowledge-sync-class.out" 2>&1; then
	    echo "[verify] knowledge-collect pushed local_private drafts without explicit permission"
	    exit 1
	  fi
	  grep -q "\[push-sync-class\]" "${tmp_dir}/knowledge-sync-class.out"
	  test ! -d "${vault_dir}/Inbox"

	  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
	    "${repo_root}/tools/knowledge-collect" --project "${tmp_dir}/missing-project" --vault-dir "${vault_dir}" --allow-local-private --push > "${tmp_dir}/knowledge-invalid-project.out" 2>&1; then
	    echo "[verify] knowledge-collect pushed with an invalid explicit project"
	    exit 1
	  fi
	  grep -q "\[project-invalid\]" "${tmp_dir}/knowledge-invalid-project.out"
	  test ! -f "${vault_dir}/AI_AUTO_INDEX.md"
	  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
	    "${repo_root}/tools/knowledge-collect" --project "${project_dir}" --project "${tmp_dir}/missing-project" --vault-dir "${vault_dir}" --allow-local-private --push > "${tmp_dir}/knowledge-mixed-invalid-project.out" 2>&1; then
	    echo "[verify] knowledge-collect pushed with a mixed valid and invalid explicit project set"
	    exit 1
	  fi
	  grep -q "\[project-invalid\]" "${tmp_dir}/knowledge-mixed-invalid-project.out"
	  test ! -f "${vault_dir}/AI_AUTO_INDEX.md"

	  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
	    "${repo_root}/tools/knowledge-collect" --include-workspace --workspace "${tmp_dir}/workspace" --project "${project_dir}" --vault-dir "${vault_dir}" --allow-local-private --push > "${tmp_dir}/knowledge-push.out"
	  grep -q "pushed 3 note" "${tmp_dir}/knowledge-push.out"
	  test -f "${vault_dir}/AI_AUTO_INDEX.md"
	  grep -q "Verify was blocked by a missing local service" "${vault_dir}/AI_AUTO_INDEX.md"
	  "${repo_root}/scripts/knowledge-notes.py" validate "${vault_dir}" >/dev/null
	  pushed_project_dir="$(find "${vault_dir}/Projects" -mindepth 1 -maxdepth 1 -type d -name 'project-a--*' | head -n 1)"
	  test -n "${pushed_project_dir}"
	  test -d "${pushed_project_dir}"
	  test ! -d "${vault_dir}/Inbox"
	  pushed_project_name="$(basename "${pushed_project_dir}")"
	  grep -q "\[\[Projects/${pushed_project_name}\]\]" "${pushed_project_dir}/"*.md
	  test -f "${vault_dir}/Projects/${pushed_project_name}.md"
	  test -f "${vault_dir}/Surfaces/verify.md"
	  test -f "${vault_dir}/RepeatKeys/verify-blocked-run.md"
	  grep -q "sync_state: pushed_to_obsidian" "${project_dir}/.omx/knowledge/drafts/"*.md
	  grep -q "obsidian_pushed_hash:" "${project_dir}/.omx/knowledge/drafts/"*.md
	  grep -q "sync_state: pushed_to_obsidian" "${pushed_project_dir}/"*.md
	  grep -q "obsidian_pushed_hash:" "${pushed_project_dir}/"*.md
	  legacy_vault_note="$(find "${pushed_project_dir}" -maxdepth 1 -type f -name '*.md' | head -n 1)"
	  perl -0pi -e 's/^obsidian_pushed_at:.*\n//mg; s/^obsidian_pushed_hash:.*\n//mg; s/^sync_state:.*\n//mg' "${legacy_vault_note}"
	  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
	    "${repo_root}/tools/knowledge-collect" --project "${project_dir}" --vault-dir "${vault_dir}" --allow-local-private --push > "${tmp_dir}/knowledge-legacy-link-repush.out"
	  grep -q "pushed 0 note" "${tmp_dir}/knowledge-legacy-link-repush.out"
	  grep -q "obsidian_pushed_hash:" "${legacy_vault_note}"
	  drift_vault_dir="${tmp_dir}/drift-vault/AI_AUTO"
	  mkdir -p "${tmp_dir}/drift-vault"
	  cp -R "${vault_dir}" "${drift_vault_dir}"
	  drift_note="$(find "${drift_vault_dir}/Projects" -mindepth 2 -maxdepth 2 -type f -name '*.md' | head -n 1)"
	  perl -0pi -e 's/\n## Links\n/\nManual vault drift with stale pushed marker.\n\n## Links\n/' "${drift_note}"
	  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
	    "${repo_root}/tools/knowledge-collect" --project "${project_dir}" --vault-dir "${drift_vault_dir}" --allow-local-private --push > "${tmp_dir}/knowledge-vault-drift.out" 2>&1; then
	    echo "[verify] knowledge-collect accepted vault body drift based only on pushed marker"
	    exit 1
	  fi
	  grep -q "target exists with different content" "${tmp_dir}/knowledge-vault-drift.out"
	  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
	    "${repo_root}/tools/knowledge-collect" --project "${project_dir}" > "${tmp_dir}/knowledge-after-push-list.out"
	  if grep -q "verify:blocked-run" "${tmp_dir}/knowledge-after-push-list.out"; then
	    echo "[verify] knowledge-collect listed already pushed drafts by default"
	    exit 1
	  fi
	  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
	    "${repo_root}/tools/knowledge-collect" --project "${project_dir}" --include-pushed > "${tmp_dir}/knowledge-after-push-all.out"
	  grep -q "verify:blocked-run" "${tmp_dir}/knowledge-after-push-all.out"
	  find "${project_dir}/.omx/knowledge/drafts" "${pushed_project_dir}" -maxdepth 1 -type f -name '*.md' -exec sha256sum {} + | sort > "${tmp_dir}/knowledge-before-repush.sha"
	  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
	    "${repo_root}/tools/knowledge-collect" --project "${project_dir}" --vault-dir "${vault_dir}" --allow-local-private --push > "${tmp_dir}/knowledge-repush.out"
	  grep -q "pushed 0 note" "${tmp_dir}/knowledge-repush.out"
	  find "${project_dir}/.omx/knowledge/drafts" "${pushed_project_dir}" -maxdepth 1 -type f -name '*.md' -exec sha256sum {} + | sort > "${tmp_dir}/knowledge-after-repush.sha"
	  cmp -s "${tmp_dir}/knowledge-before-repush.sha" "${tmp_dir}/knowledge-after-repush.sha"
	  changed_note="$(find "${project_dir}/.omx/knowledge/drafts" -maxdepth 1 -type f -name '*verify:blocked-run*.md' | head -n 1)"
	  printf '\nLocal follow-up edit after push.\n' >> "${changed_note}"
	  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
	    "${repo_root}/tools/knowledge-collect" --project "${project_dir}" > "${tmp_dir}/knowledge-after-local-edit.out"
	  grep -q "verify:blocked-run" "${tmp_dir}/knowledge-after-local-edit.out"

	  collision_project_dir="${tmp_dir}/other/project-a"
	  collision_vault_dir="${tmp_dir}/collision-vault/AI_AUTO"
	  mkdir -p "${collision_project_dir}/.omx/knowledge"
	  git -c init.defaultBranch=main init -q "${collision_project_dir}"
	  cp -R "${project_dir}/.omx/knowledge/drafts" "${collision_project_dir}/.omx/knowledge/drafts"
	  "${repo_root}/tools/knowledge-collect" \
	    --project "${project_dir}" \
	    --project "${collision_project_dir}" \
	    --vault-dir "${collision_vault_dir}" \
	    --allow-local-private \
	    --push > "${tmp_dir}/knowledge-collision-push.out"
	  grep -q "pushed 6 note" "${tmp_dir}/knowledge-collision-push.out"
	  test "$(find "${collision_vault_dir}/Projects" -mindepth 1 -maxdepth 1 -type d -name 'project-a--*' | wc -l | tr -d ' ')" = "2"
	  test ! -d "${collision_vault_dir}/Inbox"

  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    "${repo_root}/tools/knowledge-collect" --include-workspace --workspace "${tmp_dir}/workspace" --project "${project_dir}" --vault-dir "${project_dir}/.omx/knowledge/vault" --allow-local-private --push > "${tmp_dir}/knowledge-omx-vault.out" 2>&1; then
    echo "[verify] knowledge-collect accepted .omx as vault destination"
    exit 1
  fi
  grep -q "\[vault-dot-omx\]" "${tmp_dir}/knowledge-omx-vault.out"
  test ! -d "${project_dir}/.omx/knowledge/vault/Inbox"

  mkdir -p "${tmp_dir}/real-vault"
  ln -s "${tmp_dir}/real-vault" "${tmp_dir}/vault-link"
  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    "${repo_root}/tools/knowledge-collect" --include-workspace --workspace "${tmp_dir}/workspace" --project "${project_dir}" --vault-dir "${tmp_dir}/vault-link" --allow-local-private --push > "${tmp_dir}/knowledge-symlink-vault.out" 2>&1; then
    echo "[verify] knowledge-collect accepted symlink vault destination"
    exit 1
  fi
  grep -q "\[vault-path-symlink\]" "${tmp_dir}/knowledge-symlink-vault.out"
  test ! -d "${tmp_dir}/real-vault/Inbox"

  inbox_escape_vault="${tmp_dir}/project-escape-vault/AI_AUTO"
  inbox_escape_target="${tmp_dir}/project-escape-target"
  mkdir -p "${inbox_escape_vault}" "${inbox_escape_target}"
  ln -s "${inbox_escape_target}" "${inbox_escape_vault}/Projects"
  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    "${repo_root}/tools/knowledge-collect" --include-workspace --workspace "${tmp_dir}/workspace" --project "${project_dir}" --vault-dir "${inbox_escape_vault}" --allow-local-private --push > "${tmp_dir}/knowledge-inbox-symlink.out" 2>&1; then
    echo "[verify] knowledge-collect accepted symlink Projects inside vault destination"
    exit 1
  fi
  grep -q "\[vault-target-symlink\]" "${tmp_dir}/knowledge-inbox-symlink.out"
  test ! -d "${inbox_escape_target}/project-a"

  symlink_project_dir="${tmp_dir}/workspace/project-symlink-drafts"
  symlink_drafts_target="${tmp_dir}/outside-drafts-dir"
  mkdir -p "${symlink_project_dir}/.omx/knowledge" "${symlink_drafts_target}"
  git -c init.defaultBranch=main init -q "${symlink_project_dir}"
  cp "$(find "${project_dir}/.omx/knowledge/drafts" -maxdepth 1 -type f -name '*.md' | head -1)" "${symlink_drafts_target}/outside.md"
  ln -s "${symlink_drafts_target}" "${symlink_project_dir}/.omx/knowledge/drafts"
  "${repo_root}/tools/knowledge-collect" --project "${symlink_project_dir}" > "${tmp_dir}/knowledge-symlink-dir.out" 2>"${tmp_dir}/knowledge-symlink-dir.err"
  grep -q "\[draft-dir-symlink\]" "${tmp_dir}/knowledge-symlink-dir.err"
  if grep -q "outside.md" "${tmp_dir}/knowledge-symlink-dir.out"; then
    echo "[verify] knowledge-collect listed symlink draft directory contents"
    exit 1
  fi
)

echo "[verify] testing knowledge-collect shareable-only (skip-disallowed) push..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_kc_skip_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_kc_skip_tmp EXIT

  proj="${tmp_dir}/proj"
  vault="${tmp_dir}/vault/AI_AUTO"
  mkdir -p "${proj}" "${tmp_dir}/vault"
  git -c init.defaultBranch=main init -q "${proj}"

  "${repo_root}/scripts/knowledge-notes.py" record --write --allow-local-draft \
    --type finding --status draft --confidence medium \
    --title "Shareable lesson" --summary "Generic shareable workflow lesson." \
    --project proj --surface workflow --repeat-key "wf:shareable-skip" \
    --source-artifact docs/WORKFLOW.md --source-extract "generic shareable lesson text" \
    --sync-class shareable_summary \
    --output-dir "${proj}/.omx/knowledge/drafts" >/dev/null
  "${repo_root}/scripts/knowledge-notes.py" record --write --allow-local-draft \
    --type finding --status draft --confidence medium \
    --title "Private finding" --summary "A project private finding." \
    --project proj --surface review --repeat-key "rv:private-skip" \
    --source-artifact docs/x.md --source-extract "private finding text" \
    --sync-class local_private \
    --output-dir "${proj}/.omx/knowledge/drafts" >/dev/null

  # Default push still aborts when any draft is non-shareable.
  if "${repo_root}/tools/knowledge-collect" --project "${proj}" --vault-dir "${vault}" --push \
    > "${tmp_dir}/default.out" 2>&1; then
    echo "[verify] knowledge-collect default push did not abort on local_private"
    exit 1
  fi
  grep -q "\[push-sync-class\]" "${tmp_dir}/default.out"
  test ! -f "${vault}/AI_AUTO_INDEX.md"

  # Shareable-only mode pushes shareable, skips (reports) local_private.
  "${repo_root}/tools/knowledge-collect" --project "${proj}" --vault-dir "${vault}" \
    --skip-disallowed-sync-class --push > "${tmp_dir}/skip.out" 2>"${tmp_dir}/skip.err"
  grep -q "\[push-skip-local\]" "${tmp_dir}/skip.err"
  grep -q "pushed 1 note" "${tmp_dir}/skip.out"
  test -f "${vault}/RepeatKeys/wf-shareable-skip.md"
  if [ -f "${vault}/RepeatKeys/rv-private-skip.md" ]; then
    echo "[verify] skip-disallowed push leaked a local_private note"
    exit 1
  fi

  # Idempotent re-run pushes nothing new.
  "${repo_root}/tools/knowledge-collect" --project "${proj}" --vault-dir "${vault}" \
    --skip-disallowed-sync-class --push > "${tmp_dir}/skip2.out" 2>/dev/null
  grep -q "pushed 0 note" "${tmp_dir}/skip2.out"
)

echo "[verify] testing obsidian-autopush shareable-only safe push..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_autopush_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_autopush_tmp EXIT

  home="${tmp_dir}/home"
  vault="${tmp_dir}/vault/AI_AUTO"
  registry="${tmp_dir}/no-registry.tsv"
  mkdir -p "${home}/tools" "${home}/scripts" "${home}/templates/automation-base" "${vault}"
  git -c init.defaultBranch=main init -q "${home}"
  echo "2026.06.02.0" > "${home}/templates/automation-base/AI_AUTO_TEMPLATE_VERSION"
  cp "${repo_root}/tools/knowledge-collect" "${home}/tools/knowledge-collect"
  cp "${repo_root}/scripts/knowledge-notes.py" "${home}/scripts/knowledge-notes.py"
  cp "${repo_root}/scripts/obsidian-autopush.sh" "${home}/scripts/obsidian-autopush.sh"
  chmod +x "${home}/tools/knowledge-collect" "${home}/scripts/knowledge-notes.py" "${home}/scripts/obsidian-autopush.sh"

  "${home}/scripts/knowledge-notes.py" record --write --allow-local-draft \
    --type finding --status draft --confidence medium \
    --title "Shareable lesson" --summary "Generic shareable workflow lesson." \
    --project home --surface workflow --repeat-key "wf:autopush-share" \
    --source-artifact docs/WORKFLOW.md --source-extract "generic shareable lesson text" \
    --sync-class shareable_summary \
    --output-dir "${home}/.omx/knowledge/drafts" >/dev/null
  "${home}/scripts/knowledge-notes.py" record --write --allow-local-draft \
    --type finding --status draft --confidence medium \
    --title "Private finding" --summary "A project private finding." \
    --project home --surface review --repeat-key "rv:autopush-private" \
    --source-artifact docs/x.md --source-extract "private finding text" \
    --sync-class local_private \
    --output-dir "${home}/.omx/knowledge/drafts" >/dev/null

  # (a) Non-home checkout is skipped.
  git -c init.defaultBranch=main init -q "${tmp_dir}/plain"
  cp "${repo_root}/scripts/obsidian-autopush.sh" "${tmp_dir}/plain/obsidian-autopush.sh"
  ( cd "${tmp_dir}/plain" && AI_AUTO_PROJECT_REGISTRY_FILE="${registry}" \
    ./obsidian-autopush.sh --vault-dir "${vault}" > "${tmp_dir}/not-home.out" 2>&1 ) || true
  grep -q "skip: not the AI_AUTO home checkout" "${tmp_dir}/not-home.out"

  # (b) No configured vault is skipped (non-fatal).
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry}" "${home}/scripts/obsidian-autopush.sh" \
    > "${tmp_dir}/no-vault.out" 2>&1
  grep -q "skip: vault not configured" "${tmp_dir}/no-vault.out"

  # (c) Normal shareable-only push: shareable published, local_private not.
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry}" "${home}/scripts/obsidian-autopush.sh" \
    --vault-dir "${vault}" > "${tmp_dir}/push.out" 2>&1
  grep -q "pushed 1 note" "${tmp_dir}/push.out"
  test -f "${vault}/RepeatKeys/wf-autopush-share.md"
  if [ -f "${vault}/RepeatKeys/rv-autopush-private.md" ]; then
    echo "[verify] obsidian-autopush leaked a local_private note"
    exit 1
  fi

  # (d) Secret-like content in a shareable candidate fails closed (no push).
  share_note="$(find "${home}/.omx/knowledge/drafts" -maxdepth 1 -type f -name '*autopush-share*.md' | head -1)"
  printf '\napi_key=abc123\n' >> "${share_note}"
  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry}" "${home}/scripts/obsidian-autopush.sh" \
    --vault-dir "${vault}" > "${tmp_dir}/secret.out" 2>&1; then
    echo "[verify] obsidian-autopush pushed despite a secret-like shareable note"
    exit 1
  fi
  grep -q "FAIL-CLOSED" "${tmp_dir}/secret.out"

  # (e) A private-only draft set leaves the vault (and its index) untouched.
  empty_home="${tmp_dir}/empty-home"
  empty_vault="${tmp_dir}/empty-vault/AI_AUTO"
  mkdir -p "${empty_home}/tools" "${empty_home}/scripts" "${empty_home}/templates/automation-base" "${empty_vault}"
  git -c init.defaultBranch=main init -q "${empty_home}"
  echo "2026.06.02.0" > "${empty_home}/templates/automation-base/AI_AUTO_TEMPLATE_VERSION"
  cp "${repo_root}/tools/knowledge-collect" "${empty_home}/tools/knowledge-collect"
  cp "${repo_root}/scripts/knowledge-notes.py" "${empty_home}/scripts/knowledge-notes.py"
  cp "${repo_root}/scripts/obsidian-autopush.sh" "${empty_home}/scripts/obsidian-autopush.sh"
  chmod +x "${empty_home}/tools/knowledge-collect" "${empty_home}/scripts/knowledge-notes.py" "${empty_home}/scripts/obsidian-autopush.sh"
  "${empty_home}/scripts/knowledge-notes.py" record --write --allow-local-draft \
    --type finding --status draft --confidence medium \
    --title "Private only" --summary "A project private finding." \
    --project empty-home --surface review --repeat-key "rv:only-private" \
    --source-artifact docs/x.md --source-extract "private finding text" \
    --sync-class local_private \
    --output-dir "${empty_home}/.omx/knowledge/drafts" >/dev/null
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry}" "${empty_home}/scripts/obsidian-autopush.sh" \
    --vault-dir "${empty_vault}" > "${tmp_dir}/empty.out" 2>&1
  grep -q "nothing to push: no shareable drafts" "${tmp_dir}/empty.out"
  if [ -f "${empty_vault}/AI_AUTO_INDEX.md" ]; then
    echo "[verify] obsidian-autopush wrote the vault index for a private-only draft set"
    exit 1
  fi

  # (f) Auto-promotion: an allowlisted-surface (review-gate) local_private draft
  # is promoted to shareable_summary and published; an off-allowlist (ssh) one
  # stays local_private and is not published.
  promo_home="${tmp_dir}/promo-home"
  promo_vault="${tmp_dir}/promo-vault/AI_AUTO"
  mkdir -p "${promo_home}/tools" "${promo_home}/scripts" "${promo_home}/templates/automation-base" "${promo_vault}"
  git -c init.defaultBranch=main init -q "${promo_home}"
  echo "2026.06.02.0" > "${promo_home}/templates/automation-base/AI_AUTO_TEMPLATE_VERSION"
  cp "${repo_root}/tools/knowledge-collect" "${promo_home}/tools/knowledge-collect"
  cp "${repo_root}/scripts/knowledge-notes.py" "${promo_home}/scripts/knowledge-notes.py"
  cp "${repo_root}/scripts/obsidian-autopush.sh" "${promo_home}/scripts/obsidian-autopush.sh"
  chmod +x "${promo_home}/tools/knowledge-collect" "${promo_home}/scripts/knowledge-notes.py" "${promo_home}/scripts/obsidian-autopush.sh"
  "${promo_home}/scripts/knowledge-notes.py" record --write --allow-local-draft \
    --type finding --status draft --confidence medium \
    --title "Gate lesson" --summary "Generic review-gate lesson." \
    --project promo-home --surface review-gate --repeat-key "rg:promote" \
    --source-artifact docs/x.md --source-extract "generic gate lesson text" \
    --sync-class local_private \
    --output-dir "${promo_home}/.omx/knowledge/drafts" >/dev/null
  "${promo_home}/scripts/knowledge-notes.py" record --write --allow-local-draft \
    --type finding --status draft --confidence medium \
    --title "SSH note" --summary "Local ssh key location note." \
    --project promo-home --surface ssh --repeat-key "ssh:hold" \
    --source-artifact docs/y.md --source-extract "ssh key location text" \
    --sync-class local_private \
    --output-dir "${promo_home}/.omx/knowledge/drafts" >/dev/null
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry}" "${promo_home}/scripts/obsidian-autopush.sh" \
    --vault-dir "${promo_vault}" > "${tmp_dir}/promo.out" 2>&1
  grep -q "auto-promote" "${tmp_dir}/promo.out"
  grep -q "^sync_class: shareable_summary" "$(find "${promo_home}/.omx/knowledge/drafts" -maxdepth 1 -name '*rg:promote*')"
  grep -q "^sync_class: local_private" "$(find "${promo_home}/.omx/knowledge/drafts" -maxdepth 1 -name '*ssh:hold*')"
  test -f "${promo_vault}/RepeatKeys/rg-promote.md"
  if [ -f "${promo_vault}/RepeatKeys/ssh-hold.md" ]; then
    echo "[verify] obsidian-autopush published an off-allowlist (ssh) draft"
    exit 1
  fi
)

echo "[verify] testing MicroWork validator..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_microwork_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_microwork_tmp EXIT

  cat > "${tmp_dir}/ok.json" <<'JSON'
{"id":"mw-verify","goal":"smoke","scope_paths":["tools/micro-work"],"smallest_useful_wedge":"validator only","non_goals":["scripts/review-gate.sh"],"required_evidence":["verify"],"completion_criteria":["validate passes"]}
JSON
  # Valid unit + report-only audit (drift/leak surfaced, never blocking).
  out="$("${repo_root}/tools/micro-work" validate "${tmp_dir}/ok.json" --changed tools/micro-work --changed scripts/review-gate.sh 2>&1)"
  printf '%s\n' "${out}" | grep -q "ok: micro_unit_ready"
  printf '%s\n' "${out}" | grep -q "report scope_drift: scripts/review-gate.sh"
  printf '%s\n' "${out}" | grep -q "report non_goal_leak: scripts/review-gate.sh"

  # Incomplete unit fails closed with a reason.
  printf '{"id":"x","goal":"y"}' > "${tmp_dir}/bad.json"
  if "${repo_root}/tools/micro-work" validate "${tmp_dir}/bad.json" > "${tmp_dir}/bad.out" 2>&1; then
    echo "[verify] micro-work accepted an incomplete micro-unit"
    exit 1
  fi
  grep -q "missing_micro_unit_fields" "${tmp_dir}/bad.out"

  # A path that is both in scope and a non-goal is rejected.
  printf '{"id":"x","goal":"g","scope_paths":["a/b"],"smallest_useful_wedge":"w","non_goals":["a/b"],"required_evidence":["verify"],"completion_criteria":["d"]}' > "${tmp_dir}/conf.json"
  if "${repo_root}/tools/micro-work" validate "${tmp_dir}/conf.json" > "${tmp_dir}/conf.out" 2>&1; then
    echo "[verify] micro-work accepted a scope/non-goal conflict"
    exit 1
  fi
  grep -q "non_goal_scope_conflict" "${tmp_dir}/conf.out"

  # The thin wrapper skips gracefully when no micro-unit file is present.
  MICRO_WORK_FILE="${tmp_dir}/missing.json" "${repo_root}/scripts/micro-check.sh" > "${tmp_dir}/wrap.out" 2>&1
  grep -q "nothing to check" "${tmp_dir}/wrap.out"
)

echo "[verify] testing feedback helper..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_feedback_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_feedback_tmp EXIT

  cd "${tmp_dir}"
  git -c init.defaultBranch=main init -q

  "${repo_root}/scripts/record-feedback.sh" \
    --type failure_pattern \
    --repeat-key git:index-lock-permission \
    --summary ".git/index.lock permission denied during commit" \
    --resolution "Use approved escalated git commit path" \
    --surface git \
    --severity medium >/dev/null
  python3 - <<'PY'
import json
from pathlib import Path
items = [json.loads(line) for line in Path(".omx/feedback/queue.jsonl").read_text(encoding="utf-8").splitlines()]
assert items[-1]["type"] == "failure_pattern"
assert items[-1]["repeat_key"] == "git:index-lock-permission"
assert items[-1]["surface"] == "git"
assert items[-1]["status"] == "open"
PY

  "${repo_root}/scripts/resolve-feedback.sh" \
    --repeat-key git:index-lock-permission \
    --note "Template guidance updated" \
    --source verify-test >/dev/null
  python3 - <<'PY'
import json
from pathlib import Path
items = [json.loads(line) for line in Path(".omx/feedback/queue.jsonl").read_text(encoding="utf-8").splitlines()]
item = items[-1]
assert item["repeat_key"] == "git:index-lock-permission"
assert item["status"] == "resolved"
assert item["status_note"] == "Template guidance updated"
assert item["status_source"] == "verify-test"
assert "resolved_at" in item
PY

  "${repo_root}/scripts/record-feedback.sh" \
    --type improvement \
    --repeat-key review:intensity-too-high \
    --summary "Small documentation changes triggered unnecessary external reviews" \
    --severity low >/dev/null

  if command -v flock >/dev/null 2>&1; then
    (
      exec 9>".omx/feedback/queue.jsonl.lockfile"
      flock 9
      sleep 1
    ) &
    writer_lock_holder=$!
    sleep 0.2
    OMX_FEEDBACK_QUEUE_LOCK_TIMEOUT_SECONDS=5 "${repo_root}/scripts/record-feedback.sh" \
      --type improvement \
      --repeat-key feedback:shared-lock-writer \
      --summary "feedback writer shares queue lock with resolver" \
      --severity low > "${tmp_dir}/feedback-writer-lock.out"
    wait "$writer_lock_holder"
    grep -q "feedback:shared-lock-writer" .omx/feedback/queue.jsonl
    grep -q "recorded improvement:feedback:shared-lock-writer" "${tmp_dir}/feedback-writer-lock.out"
  fi

  if command -v flock >/dev/null 2>&1; then
    (
      exec 8>".omx/feedback/queue.jsonl.lockfile"
      flock 8
      sleep 3
    ) &
    lock_holder=$!
    sleep 0.2
    if OMX_FEEDBACK_QUEUE_LOCK_TIMEOUT_SECONDS=1 "${repo_root}/scripts/resolve-feedback.sh" \
      --repeat-key review:intensity-too-high > "${tmp_dir}/feedback-lock.out" 2>&1; then
      kill "$lock_holder" 2>/dev/null || true
      echo "[verify] resolve-feedback succeeded while queue lock was held"
      exit 1
    fi
    wait "$lock_holder"
  else
    mkdir .omx/feedback/queue.jsonl.lock
    if OMX_FEEDBACK_QUEUE_LOCK_TIMEOUT_SECONDS=1 "${repo_root}/scripts/resolve-feedback.sh" \
      --repeat-key review:intensity-too-high > "${tmp_dir}/feedback-lock.out" 2>&1; then
      echo "[verify] resolve-feedback succeeded while queue lock was held"
      exit 1
    fi
    rmdir .omx/feedback/queue.jsonl.lock
  fi
  grep -q "could not lock feedback queue" "${tmp_dir}/feedback-lock.out"

  if "${repo_root}/scripts/record-feedback.sh" --repeat-key secret --summary "token=abc" >/dev/null 2>&1; then
    echo "[verify] feedback helper accepted secret-like content"
    exit 1
  fi
    "${repo_root}/scripts/record-feedback.sh" \
      --repeat-key parser:ast-token \
      --summary "AST token handling needed a clearer parser note" \
      --severity low >/dev/null
    if "${repo_root}/scripts/record-feedback.sh" --repeat-key bad --summary "ok" --severity severe >/dev/null 2>&1; then
      echo "[verify] feedback helper accepted invalid severity"
      exit 1
    fi
    cp .omx/feedback/queue.jsonl "${tmp_dir}/queue.before"
    printf '{bad json\n' >> .omx/feedback/queue.jsonl
    if "${repo_root}/scripts/resolve-feedback.sh" --repeat-key review:intensity-too-high >/dev/null 2>&1; then
      echo "[verify] resolve-feedback accepted malformed queue JSON"
      exit 1
    fi
    if cmp -s .omx/feedback/queue.jsonl "${tmp_dir}/queue.before"; then
      echo "[verify] malformed queue fixture was not appended"
      exit 1
    fi
  )

echo "[verify] testing automation template installer..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_installer_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_installer_tmp EXIT

  target_dir="${tmp_dir}/target"
  installer_output="${tmp_dir}/installer.out"
  git -c init.defaultBranch=main init -q "${target_dir}"
  AI_AUTO_ALLOW_EXPERIMENTAL_TEMPLATE_SOURCE=1 ./scripts/install-automation-template.sh "${target_dir}" > "${installer_output}"
  test -x "${target_dir}/scripts/archive-omx-artifacts.sh"
  test -x "${target_dir}/scripts/ai-principal-runtime.sh"
  test -x "${target_dir}/scripts/ai-runtime-adapter.sh"
  test -x "${target_dir}/scripts/benchmark-command.py"
  test -x "${target_dir}/scripts/todo-report.py"
  test -x "${target_dir}/scripts/docker-config-guard.sh"
  test -x "${target_dir}/scripts/discover-ai-models.sh"
  test -x "${target_dir}/scripts/doc-budget.sh"
  test -x "${target_dir}/scripts/guidance-duplicate-report.sh"
  test -x "${target_dir}/scripts/capture-knowledge-drafts.py"
  test -x "${target_dir}/scripts/knowledge-notes.py"
  test -x "${target_dir}/scripts/record-feedback.sh"
  test -x "${target_dir}/scripts/record-project-memory.sh"
  test -x "${target_dir}/scripts/run-ai-reviews.sh"
  test -x "${target_dir}/scripts/write-session-checkpoint.sh"
  test -f "${target_dir}/AI_AUTO_TEMPLATE_VERSION"
  test -f "${target_dir}/docs/CHROME_CDP_ACCESS.md"
  test -f "${target_dir}/docs/AI_AUTOMATION_TREND_HARDENING.md"
  test -f "${target_dir}/docs/research/AI_AUTOMATION_TRENDS.md"
  test -f "${target_dir}/docs/AI_RUNTIME_ADAPTERS.md"
  test -f "${target_dir}/docs/AI_PRINCIPAL_RUNTIMES.md"
  test -f "${target_dir}/docs/AI_MODEL_ROUTING.md"
  test -f "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  test -f "${target_dir}/docs/DATA_COMPLETION.md"
  test -f "${target_dir}/docs/DEPLOYMENT_COMPLETION.md"
  test -f "${target_dir}/docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
  test -f "${target_dir}/docs/DOMAIN_PACKS.md"
  test -f "${target_dir}/docs/INTERVIEW_PLAN_LAYER.md"
  test -f "${target_dir}/docs/INCIDENT_OPS.md"
  test -f "${target_dir}/docs/OBSERVABILITY_COMPLETION.md"
  test -f "${target_dir}/docs/OBSIDIAN_INTEGRATION.md"
  test -f "${target_dir}/docs/PATCH_NOTES.md"
  test -f "${target_dir}/docs/PERFORMANCE_COMPLETION.md"
  test -f "${target_dir}/docs/PLANNING_VISUALIZATION_GUIDE.md"
  test -f "${target_dir}/docs/SECURITY_COMPLETION.md"
  test -f "${target_dir}/docs/SESSION_QUALITY_PLAN.md"
  test -f "${target_dir}/docs/UI_COMPLETION.md"
  grep -q "VERIFY_TEMPLATE_UNCONFIGURED""=1" "${target_dir}/scripts/verify.sh"
  grep -q "scripts/doc-budget.sh" "${target_dir}/scripts/verify.sh"
  ! grep -q "guidance-duplicate-report.sh" "${target_dir}/scripts/verify.sh"
  cmp -s "templates/automation-base/AI_AUTO_TEMPLATE_VERSION" "${target_dir}/AI_AUTO_TEMPLATE_VERSION"
  grep -q "role-first" "${target_dir}/docs/AI_MODEL_ROUTING.md"
  grep -q "Chrome CDP Access" "${target_dir}/docs/CHROME_CDP_ACCESS.md"
  grep -q "Agent Identity" "${target_dir}/docs/AI_AUTOMATION_TREND_HARDENING.md"
  grep -q "Tool Permission Registry" "${target_dir}/docs/AI_AUTOMATION_TREND_HARDENING.md"
  grep -q "Kill Switch And Revoke" "${target_dir}/docs/AI_AUTOMATION_TREND_HARDENING.md"
  grep -q "Recurring Trend Report" "${target_dir}/docs/AI_AUTOMATION_TREND_HARDENING.md"
  grep -q "AI Automation Trend Research" "${target_dir}/docs/research/AI_AUTOMATION_TRENDS.md"
  grep -q "AI 런타임 어댑터" "${target_dir}/docs/AI_RUNTIME_ADAPTERS.md"
  grep -q "AI Principal Runtimes" "${target_dir}/docs/AI_PRINCIPAL_RUNTIMES.md"
  grep -q "principal claude -> reviewers gemini, codex" "${target_dir}/docs/AI_PRINCIPAL_RUNTIMES.md"
  grep -q "Review Intensity" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "module boundaries" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "Auxiliary Rebuild Tool Gates" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "Data Completion Pack" "${target_dir}/docs/DATA_COMPLETION.md"
  grep -q "Deployment Completion Pack" "${target_dir}/docs/DEPLOYMENT_COMPLETION.md"
  grep -q "Domain Pack Authoring Guide" "${target_dir}/docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
  grep -q "Forbidden Content" "${target_dir}/docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
  grep -q "There is no generic domain pack" "${target_dir}/docs/DOMAIN_PACKS.md"
  grep -q "DOMAIN_PACK_AUTHORING_GUIDE.md" "${target_dir}/docs/DOMAIN_PACKS.md"
  grep -q "decision width" "${target_dir}/docs/INTERVIEW_PLAN_LAYER.md"
  grep -q "ready_to_execute" "${target_dir}/docs/INTERVIEW_PLAN_LAYER.md"
  grep -q "Incident Ops For Dry-run And Field-test" "${target_dir}/docs/INCIDENT_OPS.md"
  grep -q "Observability Completion Pack" "${target_dir}/docs/OBSERVABILITY_COMPLETION.md"
  grep -q "Obsidian Knowledge Operations" "${target_dir}/docs/OBSIDIAN_INTEGRATION.md"
  grep -q "External SSD Migration Runbook" "${target_dir}/docs/OBSIDIAN_INTEGRATION.md"
  grep -q 'Do not copy `.omx` wholesale' "${target_dir}/docs/OBSIDIAN_INTEGRATION.md"
  grep -q "capture-knowledge-drafts.py" "${target_dir}/docs/OBSIDIAN_INTEGRATION.md"
  grep -q "scripts/knowledge-notes.py" "${target_dir}/docs/OBSIDIAN_INTEGRATION.md"
  grep -q "Project repositories and the Obsidian vault may live on an external SSD" "${target_dir}/docs/OBSIDIAN_INTEGRATION.md"
  grep -q "AI_AUTO Patch Notes" "${target_dir}/docs/PATCH_NOTES.md"
  grep -q "Performance Completion Pack" "${target_dir}/docs/PERFORMANCE_COMPLETION.md"
  grep -q "Planning Visualization Guide" "${target_dir}/docs/PLANNING_VISUALIZATION_GUIDE.md"
  grep -q "Vector wireframe fidelity" "${target_dir}/docs/PLANNING_VISUALIZATION_GUIDE.md"
  grep -q "Security Completion Pack" "${target_dir}/docs/SECURITY_COMPLETION.md"
  grep -q "Session Quality Plan" "${target_dir}/docs/SESSION_QUALITY_PLAN.md"
  grep -q "UI Completion Pack" "${target_dir}/docs/UI_COMPLETION.md"
  grep -q "Design Quality Gate" "${target_dir}/docs/UI_COMPLETION.md"
  grep -q "docs/CHROME_CDP_ACCESS.md" "${target_dir}/docs/UI_COMPLETION.md"
  grep -q "UI가 필요하면" "${target_dir}/docs/WORKFLOW.md"
  grep -q "Subagent Utilization" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "Onboarding Interview Structure" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "Native subagents" "${target_dir}/docs/AI_MODEL_ROUTING.md"
  grep -q "서브에이전트 사용 기준" "${target_dir}/docs/WORKFLOW.md"
  grep -q "Do not present guesses" "${target_dir}/AGENTS.md"
  grep -q "review intensity" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "resource-aware parallelism" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "Planning And Interview Escalation" "${target_dir}/AGENTS.md"
  grep -q "docs/INTERVIEW_PLAN_LAYER.md" "${target_dir}/AGENTS.md"
  grep -q "template_patch_enabled: no" "${target_dir}/AGENTS.md"
  grep -q "Codemod apply" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q '`none`' "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q '`light`' "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q '`standard`' "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q '`deep`' "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "applicable completion packs from" "${target_dir}/AGENTS.md"
  grep -Eq '^[.]omx/?$' "${target_dir}/.git/info/exclude"
  grep -q "프로젝트 초기설정 해줘" "${target_dir}/AGENTS.md"
  grep -q "delete unused" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "docs/DOMAIN_PACKS.md" "templates/automation-base/README.md"
  grep -q "docs/AI_AUTOMATION_TREND_HARDENING.md" "templates/automation-base/README.md"
  grep -q "docs/AI_PRINCIPAL_RUNTIMES.md" "templates/automation-base/README.md"
  grep -q "docs/research/AI_AUTOMATION_TRENDS.md" "templates/automation-base/README.md"
  grep -q "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "templates/automation-base/README.md"
  grep -q "docs/OBSIDIAN_INTEGRATION.md" "templates/automation-base/README.md"
  grep -q "docs/PLANNING_VISUALIZATION_GUIDE.md" "templates/automation-base/README.md"
  grep -q "scripts/docker-config-guard.sh" "templates/automation-base/README.md"
  grep -q "scripts/capture-knowledge-drafts.py" "templates/automation-base/README.md"
  grep -q "scripts/knowledge-notes.py" "templates/automation-base/README.md"
  grep -q "Obsidian is only a sanitized knowledge store" "templates/automation-base/README.md"
  grep -q "Review intensity" "templates/automation-base/README.md"
  grep -q "Subagents" "templates/automation-base/README.md"
  grep -q "Planning/interview intensity" "templates/automation-base/README.md"
  grep -q "docs/INTERVIEW_PLAN_LAYER.md" "templates/automation-base/README.md"
  grep -q "Operational readiness" "templates/automation-base/README.md"
  grep -q "Incident Ops" "templates/automation-base/README.md"
  grep -q "heartbeat/quiet/active" "templates/automation-base/README.md"
  grep -q "sandbox-vs-real-network evidence" "templates/automation-base/README.md"
  grep -q "Plan management" "templates/automation-base/README.md"
  grep -q "Spec/design alignment" "templates/automation-base/README.md"
  grep -q "User-facing report language" "templates/automation-base/README.md"
  grep -q "Guidance context budget" "templates/automation-base/README.md"
  grep -q "ai-auto-template-status" "templates/automation-base/README.md"
  grep -q "template_patch_enabled: no" "templates/automation-base/README.md"
  grep -q "unused completion pack" "templates/automation-base/README.md"
  grep -q "docs/DOMAIN_PACKS.md" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "docs/INTERVIEW_PLAN_LAYER.md" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "review intensity" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "서브에이전트 사용 기준" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "플랜/인터뷰 강도 기준" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "none/light/standard/deep" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "Incident Ops 감시/장애대응/주기보고 기준" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "spec/design alignment 기준" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "사용자 보고를 쉬운 한국어" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "Template Status Comparison" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "template_patch_enabled: no" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "ai-auto-template-status" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "rejected as non-goals" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "프로젝트 초기설정 해줘" "${installer_output}"
  grep -q "docs/\\*_COMPLETION.md" "${installer_output}"
  grep -q "docs/DOMAIN_PACKS.md" "${installer_output}"
  grep -q "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "${installer_output}"
  grep -q ".omx/domain-packs/에 설치된 도메인팩" "${installer_output}"
  grep -q "서브에이전트 사용 기준" "${installer_output}"
  grep -q "플랜/인터뷰 강도 기준" "${installer_output}"
  grep -q "fail-closed 기준" "${installer_output}"
  grep -q "sandbox-vs-real-network evidence 기준" "${installer_output}"
  grep -q "Incident Ops 감시/주기보고 기준" "${installer_output}"
  grep -q "plan index/TODO reconciliation 기준" "${installer_output}"
  grep -q "spec/design alignment 기준" "${installer_output}"
  grep -q "사용자 보고를 쉬운 한국어" "${installer_output}"
  grep -q "linked docs 분리 기준" "${installer_output}"
  grep -q '`none`' "${target_dir}/docs/WORKFLOW.md"
  grep -q '`light`' "${target_dir}/docs/WORKFLOW.md"
  grep -q '`standard`' "${target_dir}/docs/WORKFLOW.md"
  grep -q '`deep`' "${target_dir}/docs/WORKFLOW.md"
  grep -q "sandbox-vs-real-network evidence" "${target_dir}/docs/WORKFLOW.md"
  grep -q "Incident Ops 기준을 확인한다" "${target_dir}/docs/WORKFLOW.md"
  grep -q "Incident Ops 정책" "${target_dir}/docs/WORKFLOW.md"
  grep -q "heartbeat, quiet, active-incident 보고" "${target_dir}/docs/WORKFLOW.md"
  grep -q "plan index/TODO reconciliation" "${target_dir}/docs/WORKFLOW.md"
  grep -q "기획서/사양서/설계자료" "${target_dir}/docs/WORKFLOW.md"
  grep -q "쉬운 한국어" "${target_dir}/docs/WORKFLOW.md"
  grep -q "linked docs" "${target_dir}/docs/WORKFLOW.md"
  grep -q "ai-context-pack" "${target_dir}/docs/WORKFLOW.md"
  grep -q "advisory/fail-open" "${target_dir}/docs/WORKFLOW.md"
  test ! -e "${target_dir}/templates/domain-packs/odoo/README.md"
  test -f "${target_dir}/.omx/domain-packs/odoo/README.md"
  grep -q "Optional domain packs installed for onboarding reference" "${installer_output}"

  "${repo_root}/tools/ai-auto-template-status" "${target_dir}" > "${tmp_dir}/template-status-current.out"
  grep -q "status: current" "${tmp_dir}/template-status-current.out"
  grep -q "template_source_branch:" "${tmp_dir}/template-status-current.out"
  grep -q "template_source_channel:" "${tmp_dir}/template-status-current.out"
  grep -q "template_patch_enabled:" "${tmp_dir}/template-status-current.out"
  AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main "${repo_root}/tools/ai-auto-template-status" "${target_dir}" > "${tmp_dir}/template-status-main.out"
  grep -q "template_source_branch: main" "${tmp_dir}/template-status-main.out"
  grep -q "template_source_channel: stable" "${tmp_dir}/template-status-main.out"
  grep -q "template_patch_enabled: yes" "${tmp_dir}/template-status-main.out"
  AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=exp/runtime-adapters "${repo_root}/tools/ai-auto-template-status" "${target_dir}" > "${tmp_dir}/template-status-exp.out"
  grep -q "template_source_branch: exp/runtime-adapters" "${tmp_dir}/template-status-exp.out"
  grep -q "template_source_channel: experimental" "${tmp_dir}/template-status-exp.out"
  grep -q "template_patch_enabled: no" "${tmp_dir}/template-status-exp.out"
  grep -q "template_patch_block_reason: experimental_source_branch" "${tmp_dir}/template-status-exp.out"
  grep -q "docs/INTERVIEW_PLAN_LAYER.md" "${tmp_dir}/template-status-current.out"
  grep -q "docs/AI_AUTOMATION_TREND_HARDENING.md" "${tmp_dir}/template-status-current.out"
  grep -q "docs/research/AI_AUTOMATION_TRENDS.md" "${tmp_dir}/template-status-current.out"
  grep -q "docs/AI_RUNTIME_ADAPTERS.md" "${tmp_dir}/template-status-current.out"
  grep -q "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "${tmp_dir}/template-status-current.out"
  grep -q "docs/PATCH_NOTES.md" "${tmp_dir}/template-status-current.out"
  grep -q "docs/OBSIDIAN_INTEGRATION.md" "${tmp_dir}/template-status-current.out"
  grep -q "docs/PLANNING_VISUALIZATION_GUIDE.md" "${tmp_dir}/template-status-current.out"
  grep -q $'STATE\tPATH\tTEMPLATE_PATH\tOWNERSHIP\tPATCH_POLICY' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/WORKFLOW.md\tdocs/WORKFLOW.md' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/WORKFLOW.md\tdocs/WORKFLOW.md\thybrid\treview-merge' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/DOMAIN_PACK_AUTHORING_GUIDE.md\tdocs/DOMAIN_PACK_AUTHORING_GUIDE.md' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/CHROME_CDP_ACCESS.md\tdocs/CHROME_CDP_ACCESS.md' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/AI_AUTOMATION_TREND_HARDENING.md\tdocs/AI_AUTOMATION_TREND_HARDENING.md\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/research/AI_AUTOMATION_TRENDS.md\tdocs/research/AI_AUTOMATION_TRENDS.md\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/AI_RUNTIME_ADAPTERS.md\tdocs/AI_RUNTIME_ADAPTERS.md' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/DOMAIN_PACKS.md\tdocs/DOMAIN_PACKS.md' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tscripts/ai-runtime-adapter.sh\tscripts/ai-runtime-adapter.sh\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/PATCH_NOTES.md\tdocs/PATCH_NOTES.md\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/OBSIDIAN_INTEGRATION.md\tdocs/OBSIDIAN_INTEGRATION.md\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/PLANNING_VISUALIZATION_GUIDE.md\tdocs/PLANNING_VISUALIZATION_GUIDE.md\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tscripts/benchmark-command.py\tscripts/benchmark-command.py\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tscripts/todo-report.py\tscripts/todo-report.py\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tscripts/capture-knowledge-drafts.py\tscripts/capture-knowledge-drafts.py\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tscripts/knowledge-notes.py\tscripts/knowledge-notes.py\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tscripts/verify.sh\tscripts/verify.example.sh\tproject-owned\tinspect-only' "${tmp_dir}/template-status-current.out"

  printf '\nproject-specific customization\n' >> "${target_dir}/docs/WORKFLOW.md"
  "${repo_root}/tools/ai-auto-template-status" "${target_dir}" > "${tmp_dir}/template-status-drift.out"
  grep -q "status: customized_or_outdated" "${tmp_dir}/template-status-drift.out"
  grep -q $'different\tdocs/WORKFLOW.md\tdocs/WORKFLOW.md' "${tmp_dir}/template-status-drift.out"
  grep -q $'different\tdocs/WORKFLOW.md\tdocs/WORKFLOW.md\thybrid\treview-merge' "${tmp_dir}/template-status-drift.out"
  test ! -e "${target_dir}/.omx/feedback/queue.jsonl"

  "${repo_root}/tools/ai-auto-template-status" --record-feedback "${target_dir}" > "${tmp_dir}/template-status-feedback.out"
  grep -q "feedback: recorded automation-template:update-available" "${tmp_dir}/template-status-feedback.out"
  grep -q '"repeat_key": "automation-template:update-available"' "${target_dir}/.omx/feedback/queue.jsonl"

  rm "${target_dir}/AI_AUTO_TEMPLATE_VERSION"
  "${repo_root}/tools/ai-auto-template-status" "${target_dir}" > "${tmp_dir}/template-status-missing-version.out"
  grep -q "status: missing_version" "${tmp_dir}/template-status-missing-version.out"
)

echo "[verify] testing automation template experimental source guard..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_template_guard_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_template_guard_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  if AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=exp/runtime-adapters ./scripts/install-automation-template.sh "${target_dir}" > "${tmp_dir}/guard.out" 2>&1; then
    echo "[verify] install-automation-template accepted experimental source without override"
    exit 1
  fi
  grep -q "Refusing to install automation template from a non-stable AI_AUTO source" "${tmp_dir}/guard.out"
  grep -q "source_branch: exp/runtime-adapters" "${tmp_dir}/guard.out"
  grep -q "source_channel: experimental" "${tmp_dir}/guard.out"
  grep -q "manual review-only merge" "${tmp_dir}/guard.out"
  test ! -e "${target_dir}/AGENTS.md"
)

echo "[verify] checking optional domain pack structure..."
test -f "templates/domain-packs/browser-macro/README.md"
test -f "templates/domain-packs/browser-macro/AGENTS.patch.md"
test -f "templates/domain-packs/browser-macro/WORKFLOW.md"
test -f "templates/domain-packs/browser-macro/verify-patterns.md"
test -f "templates/domain-packs/browser-macro/review-checklist.md"
test -f "templates/domain-packs/browser-macro/ecount-reference.md"
grep -q "Guidance Hierarchy" "templates/domain-packs/browser-macro/README.md"
grep -q "Planning Method" "templates/domain-packs/browser-macro/AGENTS.patch.md"
grep -q "selector address" "templates/domain-packs/browser-macro/WORKFLOW.md"
grep -q "Tooling And Stack Selection" "templates/domain-packs/browser-macro/WORKFLOW.md"
grep -q "Bridge Contract" "templates/domain-packs/browser-macro/WORKFLOW.md"
grep -q "docs/CHROME_CDP_ACCESS.md" "templates/domain-packs/browser-macro/verify-patterns.md"
grep -q "data-columnid" "templates/domain-packs/browser-macro/ecount-reference.md"
grep -q "browser-macro" "docs/DOMAIN_PACKS.md"
test -f "templates/domain-packs/odoo/README.md"
test -f "templates/domain-packs/odoo/AGENTS.patch.md"
test -f "templates/domain-packs/odoo/WORKFLOW.md"
test -f "templates/domain-packs/odoo/verify-patterns.md"
test -f "templates/domain-packs/odoo/review-checklist.md"
grep -q "ignored onboarding reference under" "templates/domain-packs/odoo/README.md"
grep -q "docs/DOMAIN_PACKS.md" "templates/domain-packs/odoo/README.md"
grep -q "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "templates/domain-packs/odoo/README.md"
grep -q "ko_KR" "templates/domain-packs/odoo/README.md"
grep -q "Windows and WSL have separate" "templates/domain-packs/odoo/README.md"
grep -q "Windows PowerShell's SSH location" "templates/domain-packs/odoo/AGENTS.patch.md"
grep -q "private key content" "templates/domain-packs/odoo/WORKFLOW.md"
grep -q "Project-Specific Rules" "templates/domain-packs/odoo/WORKFLOW.md"
grep -q "localization baseline" "templates/domain-packs/odoo/verify-patterns.md"
grep -Fq 'Path("custom_addons").rglob("*.xml")' "templates/domain-packs/odoo/verify-patterns.md"
grep -q "도메인팩" "templates/automation-base/docs/WORKFLOW.md"
grep -q "There is no generic domain pack" "templates/automation-base/docs/DOMAIN_PACKS.md"
grep -q "Domain Pack Authoring Guide" "templates/automation-base/docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
grep -q "Interview Design" "templates/automation-base/docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
grep -q "Forbidden Content" "templates/automation-base/docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
grep -q "split-rules.json" "templates/automation-base/docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
cmp -s "docs/DOMAIN_PACKS.md" "templates/automation-base/docs/DOMAIN_PACKS.md"
cmp -s "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "templates/automation-base/docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
grep -q "Deployment Completion Pack" "templates/automation-base/docs/DEPLOYMENT_COMPLETION.md"
grep -q "Security Completion Pack" "templates/automation-base/docs/SECURITY_COMPLETION.md"
grep -q "Data Completion Pack" "templates/automation-base/docs/DATA_COMPLETION.md"
grep -q "Performance Completion Pack" "templates/automation-base/docs/PERFORMANCE_COMPLETION.md"
grep -q "Observability Completion Pack" "templates/automation-base/docs/OBSERVABILITY_COMPLETION.md"
grep -q "UI Completion Pack" "templates/automation-base/docs/UI_COMPLETION.md"
grep -q "Design Quality Gate" "templates/automation-base/docs/UI_COMPLETION.md"
grep -q "avoid nested cards" "templates/automation-base/docs/UI_COMPLETION.md"
grep -q "Incident Ops For Dry-run And Field-test" "templates/automation-base/docs/INCIDENT_OPS.md"
grep -q "Obsidian Knowledge Operations" "templates/automation-base/docs/OBSIDIAN_INTEGRATION.md"
grep -q "External SSD Migration Runbook" "templates/automation-base/docs/OBSIDIAN_INTEGRATION.md"
grep -q 'Do not copy `.omx` wholesale' "templates/automation-base/docs/OBSIDIAN_INTEGRATION.md"
grep -q "Periodic Status Reporting" "templates/automation-base/docs/INCIDENT_OPS.md"
grep -q "Incident Ops During Dry-run And Field-test" "templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md"
grep -q "doc-budget.sh" "templates/automation-base/README.md"
grep -q "guidance-duplicate-report.sh" "templates/automation-base/README.md"
test -x "scripts/doc-budget.sh"
test -x "templates/automation-base/scripts/doc-budget.sh"
test -x "scripts/guidance-duplicate-report.sh"
test -x "templates/automation-base/scripts/guidance-duplicate-report.sh"
test -x "scripts/benchmark-command.py"
test -x "templates/automation-base/scripts/benchmark-command.py"
test -x "scripts/todo-report.py"
test -x "templates/automation-base/scripts/todo-report.py"
test -x "scripts/capture-knowledge-drafts.py"
test -x "templates/automation-base/scripts/capture-knowledge-drafts.py"
test -x "scripts/knowledge-notes.py"
test -x "templates/automation-base/scripts/knowledge-notes.py"
test -x "scripts/validate-odoo-docs-kb.py"
test -x "templates/automation-base/scripts/validate-odoo-docs-kb.py"
grep -q "Post-Code Spec/Design Alignment" "docs/AUTOMATION_OPERATING_POLICY.md"
grep -q "Post-Code Spec/Design Alignment" "templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md"
grep -q "User-Facing Report Language" "docs/AUTOMATION_OPERATING_POLICY.md"
grep -q "User-Facing Report Language" "templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md"
grep -q "기획서/사양서/설계자료" "docs/WORKFLOW.md"
grep -q "기획서/사양서/설계자료" "templates/automation-base/docs/WORKFLOW.md"
grep -q "설계자료 대조 결과: aligned, updated, not applicable, or blocked" "docs/WORKFLOW.md"
grep -q "설계자료 대조 결과: aligned, updated, not applicable, or blocked" "templates/automation-base/docs/WORKFLOW.md"
grep -q "classify the result as aligned, updated, not applicable, or blocked" "docs/PLANNING_VISUALIZATION_GUIDE.md"
grep -q "쉬운 한국어" "docs/WORKFLOW.md"
grep -q "쉬운 한국어" "templates/automation-base/docs/WORKFLOW.md"
grep -q "plan artifact's Goal" "docs/INTERVIEW_PLAN_LAYER.md"
grep -q "plan artifact's Goal" "templates/automation-base/docs/INTERVIEW_PLAN_LAYER.md"
grep -q "field-test incident evidence" "templates/automation-base/docs/UI_COMPLETION.md"
grep -q "detailed UI behavior verification requests" "templates/automation-base/docs/UI_COMPLETION.md"
grep -q "validate-<guide-folder>.py" "templates/automation-base/docs/OBSIDIAN_INTEGRATION.md"
./scripts/validate-odoo-kb.py
if [ -n "${AI_AUTO_ODOO_DOCS_KB_PATH:-}" ]; then
  ./scripts/validate-odoo-docs-kb.py "${AI_AUTO_ODOO_DOCS_KB_PATH}"
fi
grep -q "Approval Friction" "templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md"
grep -q "실패 패턴 피드백" "templates/automation-base/docs/WORKFLOW.md"
grep -q "필요한 완료팩" "docs/NEW_PROJECT_GUIDE.md"

echo "[verify] testing domain pack copy preserves existing references..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_domain_pack_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_domain_pack_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  mkdir -p "${target_dir}/.omx/domain-packs/odoo"
  printf 'keep me\n' > "${target_dir}/.omx/domain-packs/odoo/README.md"

  AI_AUTO_ALLOW_EXPERIMENTAL_TEMPLATE_SOURCE=1 ./scripts/install-automation-template.sh "${target_dir}" >/dev/null

  grep -q "keep me" "${target_dir}/.omx/domain-packs/odoo/README.md"
  test -f "${target_dir}/.omx/domain-packs/.manifest/browser-macro.json"
  test ! -f "${target_dir}/.omx/domain-packs/.manifest/odoo.json"
)

echo "[verify] testing domain pack status and refresh helper..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_domain_pack_status_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_domain_pack_status_tmp EXIT

  target_dir="${tmp_dir}/target"
  git -c init.defaultBranch=main init -q "${target_dir}"
  AI_AUTO_ALLOW_EXPERIMENTAL_TEMPLATE_SOURCE=1 ./scripts/install-automation-template.sh "${target_dir}" >/dev/null

  AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${target_dir}" --pack odoo status > "${tmp_dir}/domain-current.out"
  grep -q $'current\todoo' "${tmp_dir}/domain-current.out"
  grep -q "domain_pack_refresh_enabled: yes" "${tmp_dir}/domain-current.out"
  test -f "${target_dir}/.omx/domain-packs/.manifest/odoo.json"

  cp -R templates/domain-packs "${tmp_dir}/source-packs"
  printf '\nverify-refresh-change\n' >> "${tmp_dir}/source-packs/odoo/README.md"

  before_hash="$(sha256sum "${target_dir}/.omx/domain-packs/odoo/README.md" | awk '{print $1}')"
  AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${target_dir}" --pack odoo refresh > "${tmp_dir}/domain-dry.out"
  after_dry_hash="$(sha256sum "${target_dir}/.omx/domain-packs/odoo/README.md" | awk '{print $1}')"
  test "${before_hash}" = "${after_dry_hash}"
  grep -q $'outdated_clean\todoo' "${tmp_dir}/domain-dry.out"

  agents_before="$(sha256sum "${target_dir}/AGENTS.md" | awk '{print $1}')"
  workflow_before="$(sha256sum "${target_dir}/docs/WORKFLOW.md" | awk '{print $1}')"
  verify_before="$(sha256sum "${target_dir}/scripts/verify.sh" | awk '{print $1}')"
  AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${target_dir}" --pack odoo refresh --apply > "${tmp_dir}/domain-apply.out"
  grep -q $'updated\todoo' "${tmp_dir}/domain-apply.out"
  grep -q "verify-refresh-change" "${target_dir}/.omx/domain-packs/odoo/README.md"
  test "${agents_before}" = "$(sha256sum "${target_dir}/AGENTS.md" | awk '{print $1}')"
  test "${workflow_before}" = "$(sha256sum "${target_dir}/docs/WORKFLOW.md" | awk '{print $1}')"
  test "${verify_before}" = "$(sha256sum "${target_dir}/scripts/verify.sh" | awk '{print $1}')"
  AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${target_dir}" --pack odoo refresh --apply > "${tmp_dir}/domain-idempotent.out"
  grep -q $'current\todoo' "${tmp_dir}/domain-idempotent.out"

  printf '\nlocal edit\n' >> "${target_dir}/.omx/domain-packs/odoo/README.md"
  if AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${target_dir}" --pack odoo refresh --apply > "${tmp_dir}/domain-conflict.out" 2>&1; then
    echo "[verify] ai-domain-pack refreshed a locally modified pack"
    exit 1
  fi
  grep -q $'conflict\todoo' "${tmp_dir}/domain-conflict.out"
  grep -q "local edit" "${target_dir}/.omx/domain-packs/odoo/README.md"

  legacy_dir="${tmp_dir}/legacy"
  git -c init.defaultBranch=main init -q "${legacy_dir}"
  mkdir -p "${legacy_dir}/.omx/domain-packs"
  cp -R "${tmp_dir}/source-packs/odoo" "${legacy_dir}/.omx/domain-packs/odoo"
  AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${legacy_dir}" --pack odoo status > "${tmp_dir}/domain-adoptable.out"
  grep -q $'adoptable\todoo' "${tmp_dir}/domain-adoptable.out"
  AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${legacy_dir}" --pack odoo refresh --apply > "${tmp_dir}/domain-adopted.out"
  grep -q $'adopted\todoo' "${tmp_dir}/domain-adopted.out"
  test -f "${legacy_dir}/.omx/domain-packs/.manifest/odoo.json"

  dirty_legacy="${tmp_dir}/dirty-legacy"
  git -c init.defaultBranch=main init -q "${dirty_legacy}"
  mkdir -p "${dirty_legacy}/.omx/domain-packs"
  cp -R "${tmp_dir}/source-packs/odoo" "${dirty_legacy}/.omx/domain-packs/odoo"
  printf '\nlegacy local edit\n' >> "${dirty_legacy}/.omx/domain-packs/odoo/README.md"
  if AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${dirty_legacy}" --pack odoo refresh --apply > "${tmp_dir}/domain-unmanaged.out" 2>&1; then
    echo "[verify] ai-domain-pack adopted a dirty legacy pack"
    exit 1
  fi
  grep -q $'unmanaged\todoo' "${tmp_dir}/domain-unmanaged.out"

  removed_dir="${tmp_dir}/removed"
  git -c init.defaultBranch=main init -q "${removed_dir}"
  AI_AUTO_ALLOW_EXPERIMENTAL_TEMPLATE_SOURCE=1 ./scripts/install-automation-template.sh "${removed_dir}" >/dev/null
  rm -rf "${removed_dir}/.omx/domain-packs/odoo"
  AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${removed_dir}" --pack odoo refresh --apply > "${tmp_dir}/domain-removed.out"
  grep -q $'deliberately_removed\todoo' "${tmp_dir}/domain-removed.out"
  test ! -e "${removed_dir}/.omx/domain-packs/odoo"

  guarded_dir="${tmp_dir}/guarded"
  git -c init.defaultBranch=main init -q "${guarded_dir}"
  AI_AUTO_ALLOW_EXPERIMENTAL_TEMPLATE_SOURCE=1 ./scripts/install-automation-template.sh "${guarded_dir}" >/dev/null
  if AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=exp/domain-pack ./tools/ai-domain-pack --target "${guarded_dir}" --pack odoo refresh --apply > "${tmp_dir}/domain-branch-guard.out" 2>&1; then
    echo "[verify] ai-domain-pack refreshed from an experimental source branch"
    exit 1
  fi
  grep -q "experimental_source_branch" "${tmp_dir}/domain-branch-guard.out"

  if AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${guarded_dir}" --pack missing-pack refresh --apply > "${tmp_dir}/domain-unknown-pack.out" 2>&1; then
    echo "[verify] ai-domain-pack installed an unknown pack"
    exit 1
  fi
  grep -q $'unknown_pack\tmissing-pack' "${tmp_dir}/domain-unknown-pack.out"
  test ! -e "${guarded_dir}/.omx/domain-packs/missing-pack"
  test ! -e "${guarded_dir}/.omx/domain-packs/.manifest/missing-pack.json"

  if AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE="${tmp_dir}/source-packs" AI_AUTO_TEMPLATE_SOURCE_BRANCH_OVERRIDE=main ./tools/ai-domain-pack --target "${guarded_dir}" --pack ../odoo refresh --apply > "${tmp_dir}/domain-traversal-pack.out" 2>&1; then
    echo "[verify] ai-domain-pack accepted a traversal pack name"
    exit 1
  fi
  grep -q $'invalid_pack_name\t../odoo' "${tmp_dir}/domain-traversal-pack.out"
  test ! -e "${guarded_dir}/.omx/odoo"
  test ! -e "${guarded_dir}/.omx/domain-packs/.manifest/../odoo.json"
)

echo "[verify] testing automation template conflict guidance..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_installer_conflict_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_installer_conflict_tmp EXIT

  target_dir="${tmp_dir}/target"
  conflict_output="${tmp_dir}/conflict.out"
  git -c init.defaultBranch=main init -q "${target_dir}"
  printf '# Existing instructions\n' > "${target_dir}/AGENTS.md"

  if AI_AUTO_ALLOW_EXPERIMENTAL_TEMPLATE_SOURCE=1 ./scripts/install-automation-template.sh "${target_dir}" > "${conflict_output}"; then
    echo "[verify] installer unexpectedly overwrote existing automation file"
    exit 1
  fi

  grep -q "Refusing to overwrite existing files" "${conflict_output}"
  grep -q "기존 프로젝트에 자동화 기반을 병합 도입해줘" "${conflict_output}"
  grep -q "# Existing instructions" "${target_dir}/AGENTS.md"
)

echo "[verify] testing aiinit wrapper onboarding handoff..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_aiinit_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_aiinit_tmp EXIT

  target_dir="${tmp_dir}/target"
  aiinit_output="${tmp_dir}/aiinit.out"
  registry_file="${tmp_dir}/projects.tsv"
  git -c init.defaultBranch=main init -q "${target_dir}"
  AI_AUTO_ALLOW_EXPERIMENTAL_TEMPLATE_SOURCE=1 \
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" \
    ./tools/ai-auto-init "${target_dir}" > "${aiinit_output}"
  grep -q "프로젝트 초기설정 해줘" "${aiinit_output}"
  grep -q "docs/\\*_COMPLETION.md" "${aiinit_output}"
  grep -q "docs/DOMAIN_PACKS.md" "${aiinit_output}"
  grep -q ".omx/domain-packs/에 설치된 도메인팩" "${aiinit_output}"
  grep -q "서브에이전트 사용 기준" "${aiinit_output}"
  grep -q "플랜/인터뷰 강도 기준" "${aiinit_output}"
  grep -q "fail-closed 기준" "${aiinit_output}"
  grep -q "sandbox-vs-real-network evidence 기준" "${aiinit_output}"
  grep -q "Incident Ops" "${aiinit_output}"
  grep -q "plan index/TODO" "${aiinit_output}"
  grep -q "spec/design alignment" "${aiinit_output}"
  grep -q "사용자 보고를 쉬운 한국어" "${aiinit_output}"
  grep -q "linked docs 분리 기준" "${aiinit_output}"
  grep -q "Project registered" "${aiinit_output}"
  grep -q "프로젝트 초기설정 해줘" "${target_dir}/AGENTS.md"
  grep -q "sandbox-vs-real-network" "${target_dir}/AGENTS.md"
  grep -q "Incident Ops" "${target_dir}/docs/WORKFLOW.md"
  grep -q "plan index/TODO reconciliation" "${target_dir}/docs/WORKFLOW.md"
  grep -q "spec/design alignment" "${target_dir}/AGENTS.md"
  grep -q "plain Korean" "${target_dir}/AGENTS.md"
  grep -q "$(cd "${target_dir}" && pwd -P)" "${registry_file}"
)

echo "[verify] testing ai-register and workspace-scan registry integration..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_registry_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_registry_tmp EXIT

  workspace_dir="${tmp_dir}/workspace"
  target_dir="${workspace_dir}/registered-project"
  spaced_dir="${workspace_dir}/registered project with spaces"
  linked_dir="${workspace_dir}/linked-worktree"
  nested_dir="${workspace_dir}/groups/team/product/nested-project"
  outside_dir="${tmp_dir}/outside-project"
  missing_dir="${tmp_dir}/missing-project"
  registry_file="${tmp_dir}/projects.tsv"
  mkdir -p "${workspace_dir}"
  git -c init.defaultBranch=main init -q "${target_dir}"
  git -C "${target_dir}" config user.email "verify@example.invalid"
  git -C "${target_dir}" config user.name "Verify"
  touch "${target_dir}/README.md"
  git -C "${target_dir}" add README.md
  git -C "${target_dir}" commit -q -m "seed"
  git -C "${target_dir}" worktree add -q "${linked_dir}" HEAD
  git -c init.defaultBranch=main init -q "${spaced_dir}"
  git -c init.defaultBranch=main init -q "${nested_dir}"
  git -c init.defaultBranch=main init -q "${outside_dir}"

  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/ai-register "${target_dir}" > "${tmp_dir}/register.out"
  grep -q "Project registered" "${tmp_dir}/register.out"
  grep -q "$(cd "${target_dir}" && pwd -P)" "${registry_file}"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/ai-register "${target_dir}" >/dev/null
  test "$(grep -F "$(cd "${target_dir}" && pwd -P)" "${registry_file}" | wc -l)" -eq 1
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/ai-register "${spaced_dir}" >/dev/null
  grep -q "$(cd "${spaced_dir}" && pwd -P)" "${registry_file}"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/ai-register "${linked_dir}" >/dev/null
  grep -q "$(cd "${linked_dir}" && pwd -P)" "${registry_file}"
  printf 'old\t%s\tmissing-project\tmain\tnone\n' "${missing_dir}" >> "${registry_file}"
  if command -v flock >/dev/null 2>&1; then
    (
      exec 8>"${registry_file}.lockfile"
      flock 8
      sleep 3
    ) &
    lock_holder=$!
    sleep 0.2
    if AI_AUTO_PROJECT_REGISTRY_LOCK_TIMEOUT_SECONDS=1 AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/ai-register "${outside_dir}" > "${tmp_dir}/locked.out" 2>&1; then
      kill "$lock_holder" 2>/dev/null || true
      echo "ai-register succeeded while registry lock was held by another process"
      exit 1
    fi
    wait "$lock_holder"
  else
    mkdir "${registry_file}.lock"
    if AI_AUTO_PROJECT_REGISTRY_LOCK_TIMEOUT_SECONDS=1 AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/ai-register "${outside_dir}" > "${tmp_dir}/locked.out" 2>&1; then
      echo "ai-register succeeded while registry lock was held by another process"
      exit 1
    fi
    rmdir "${registry_file}.lock"
  fi
  grep -q "Could not lock project registry" "${tmp_dir}/locked.out"
  mkdir "${registry_file}.lock"
  touch -d '20 minutes ago' "${registry_file}.lock"
  AI_AUTO_PROJECT_REGISTRY_LOCK_TIMEOUT_SECONDS=1 AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/ai-register "${outside_dir}" > "${tmp_dir}/legacy-lock-dir.out"
  grep -q "Project registered" "${tmp_dir}/legacy-lock-dir.out"
  rmdir "${registry_file}.lock"

  scan_output="${tmp_dir}/scan.out"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/workspace-scan "${workspace_dir}" > "${scan_output}"
  grep -q "INIT" "${scan_output}"
  grep -q "registered-project" "${scan_output}"
  grep -q "registered project wit" "${scan_output}"
  grep -q "linked-worktree" "${scan_output}"
  grep -q "yes" "${scan_output}"

  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/workspace-scan "${workspace_dir}" > "${scan_output}"
  grep -q "outside-project" "${scan_output}"
  if grep -q "nested-project" "${scan_output}"; then
    echo "workspace-scan found deep nested project at default depth"
    exit 1
  fi
  AI_AUTO_WORKSPACE_SCAN_MAX_DEPTH=5 AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/workspace-scan "${workspace_dir}" > "${scan_output}"
  grep -q "nested-project" "${scan_output}"
  if AI_AUTO_WORKSPACE_SCAN_MAX_DEPTH=0 AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/workspace-scan "${workspace_dir}" > "${tmp_dir}/invalid-depth.out" 2>&1; then
    echo "workspace-scan accepted invalid discovery depth"
    exit 1
  fi
  grep -q "must be a positive integer" "${tmp_dir}/invalid-depth.out"
  mkdir -p "${target_dir}/.omx/feedback" "${outside_dir}/.omx/feedback"
  mkdir -p "${nested_dir}/.omx/feedback"
  printf '%s\n' '{"created_at":"2026-05-11T00:00:00Z","repeat_key":"registered:item","severity":"high","status":"open","summary":"registered queue item","type":"improvement"}' > "${target_dir}/.omx/feedback/queue.jsonl"
  printf '%s\n' '{"created_at":"2026-05-11T00:00:01Z","repeat_key":"outside:item","severity":"medium","status":"resolved","summary":"outside queue item","type":"failure_pattern"}' > "${outside_dir}/.omx/feedback/queue.jsonl"
  printf '%s\n' '{"created_at":"2026-05-11T00:00:02Z","repeat_key":"nested:item","severity":"low","summary":"nested queue item","type":"improvement"}' > "${nested_dir}/.omx/feedback/queue.jsonl"
  feedback_output="${tmp_dir}/feedback.out"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/feedback-collect "${workspace_dir}" > "${feedback_output}"
  grep -q "registered:item" "${feedback_output}"
  grep -q "outside:item" "${feedback_output}"
  if grep -q "nested:item" "${feedback_output}"; then
    echo "feedback-collect found deep nested project at default depth"
    exit 1
  fi
  AI_AUTO_WORKSPACE_SCAN_MAX_DEPTH=5 AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/feedback-collect "${workspace_dir}" > "${feedback_output}"
  grep -q "nested:item" "${feedback_output}"
  AI_AUTO_PROJECT_REGISTRY_FILE="${tmp_dir}/empty-registry.tsv" ./tools/feedback-collect "${nested_dir}" > "${tmp_dir}/feedback-single-repo.out"
  grep -q "nested:item" "${tmp_dir}/feedback-single-repo.out"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/feedback-resolve --repeat-key registered:item --note "verified promotion" --source "verify fixture" "${workspace_dir}" > "${tmp_dir}/feedback-resolve-dry.out"
  grep -q "dry-run: would mark 1 item(s) resolved for registered:item" "${tmp_dir}/feedback-resolve-dry.out"
  grep -q '"status":"open"' "${target_dir}/.omx/feedback/queue.jsonl"
  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/feedback-resolve --repeat-key registered:item --write "${workspace_dir}" > "${tmp_dir}/feedback-resolve-missing-evidence.out" 2>&1; then
    echo "feedback-resolve accepted write without note/source"
    exit 1
  fi
  grep -q -- "--write requires both --note and --source" "${tmp_dir}/feedback-resolve-missing-evidence.out"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/feedback-resolve --repeat-key registered:item --note "verified promotion" --source "verify fixture" --write "${workspace_dir}" > "${tmp_dir}/feedback-resolve-write.out"
  grep -q "complete: matched=1 changed=1" "${tmp_dir}/feedback-resolve-write.out"
  grep -q '"status": "resolved"' "${target_dir}/.omx/feedback/queue.jsonl"
  before_hash="$(sha256sum "${target_dir}/.omx/feedback/queue.jsonl" | awk '{print $1}')"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/feedback-resolve --repeat-key registered:item --note "verified promotion" --source "verify fixture" --write "${workspace_dir}" > "${tmp_dir}/feedback-resolve-idempotent.out"
  after_hash="$(sha256sum "${target_dir}/.omx/feedback/queue.jsonl" | awk '{print $1}')"
  test "${before_hash}" = "${after_hash}"
  grep -q "unchanged: 1 item(s) already resolved" "${tmp_dir}/feedback-resolve-idempotent.out"
  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/feedback-resolve --repeat-key missing:item "${workspace_dir}" > "${tmp_dir}/feedback-resolve-missing.out" 2>&1; then
    echo "feedback-resolve accepted unknown repeat_key"
    exit 1
  fi
  grep -q "unknown repeat_key: missing:item" "${tmp_dir}/feedback-resolve-missing.out"
  if AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/feedback-resolve --repeat-key registered:item --note "token=secret" "${workspace_dir}" > "${tmp_dir}/feedback-resolve-secret.out" 2>&1; then
    echo "feedback-resolve accepted secret-like note"
    exit 1
  fi
  grep -q "refusing to store content" "${tmp_dir}/feedback-resolve-secret.out"
  if AI_AUTO_WORKSPACE_SCAN_MAX_DEPTH=bad AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/feedback-collect "${workspace_dir}" > "${tmp_dir}/feedback-invalid-depth.out" 2>&1; then
    echo "feedback-collect accepted invalid discovery depth"
    exit 1
  fi
  grep -q "must be a positive integer" "${tmp_dir}/feedback-invalid-depth.out"
  grep -q "open" "${feedback_output}"
  grep -q "resolved" "${feedback_output}"
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/ai-register --prune > "${tmp_dir}/prune.out"
  grep -q "removed: 1" "${tmp_dir}/prune.out"
  if grep -q "${missing_dir}" "${registry_file}"; then
    echo "stale registry path was not pruned"
    exit 1
  fi
)

echo "[verify] testing global helper link repair..."
(
  tmp_home="$(mktemp -d)"

  cleanup_global_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_global_tmp EXIT

  mkdir -p "${tmp_home}/bin" "${tmp_home}/old-checkout/tools"
  ln -s "${tmp_home}/old-checkout/tools/ai-home" "${tmp_home}/bin/AI_AUTO"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/ai-auto-init"
  ln -s "${tmp_home}/old-checkout/tools/ai-home" "${tmp_home}/bin/ai-home"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/aiinit"
  ln -s "${tmp_home}/old-checkout/tools/ai-register" "${tmp_home}/bin/ai-register"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-template-status" "${tmp_home}/bin/ai-auto-template-status"
  ln -s "${tmp_home}/old-checkout/tools/ai-domain-pack" "${tmp_home}/bin/ai-domain-pack"
  ln -s "${tmp_home}/old-checkout/tools/ai-gstack-contract" "${tmp_home}/bin/ai-gstack-contract"
  ln -s "${tmp_home}/old-checkout/tools/ai-refactor-scan" "${tmp_home}/bin/ai-refactor-scan"
  ln -s "${tmp_home}/old-checkout/tools/ai-rebuild-plan" "${tmp_home}/bin/ai-rebuild-plan"
  ln -s "${tmp_home}/old-checkout/tools/ai-split-plan" "${tmp_home}/bin/ai-split-plan"
  ln -s "${tmp_home}/old-checkout/tools/ai-split-dry-run" "${tmp_home}/bin/ai-split-dry-run"
  ln -s "${tmp_home}/old-checkout/tools/ai-split-apply" "${tmp_home}/bin/ai-split-apply"
  ln -s "${tmp_home}/old-checkout/tools/ai-plan-status" "${tmp_home}/bin/ai-plan-status"
  ln -s "${tmp_home}/old-checkout/tools/ai-interview-record" "${tmp_home}/bin/ai-interview-record"
  ln -s "${tmp_home}/old-checkout/tools/ai-plan-review" "${tmp_home}/bin/ai-plan-review"
  ln -s "${tmp_home}/old-checkout/tools/ai-plan-export" "${tmp_home}/bin/ai-plan-export"
  ln -s "${tmp_home}/old-checkout/tools/feedback-collect" "${tmp_home}/bin/feedback-collect"
  ln -s "${tmp_home}/old-checkout/tools/feedback-resolve" "${tmp_home}/bin/feedback-resolve"
  ln -s "${tmp_home}/old-checkout/tools/knowledge-collect" "${tmp_home}/bin/knowledge-collect"
  ln -s "${tmp_home}/old-checkout/tools/workspace-scan" "${tmp_home}/bin/workspace-scan"

  HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/install-global-files.sh >/dev/null

  test "$(readlink "${tmp_home}/bin/AI_AUTO")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/ai-auto-init")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-home")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/aiinit")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-register")" = "$(pwd)/tools/ai-register"
  test "$(readlink "${tmp_home}/bin/ai-auto-template-status")" = "$(pwd)/tools/ai-auto-template-status"
  test "$(readlink "${tmp_home}/bin/ai-domain-pack")" = "$(pwd)/tools/ai-domain-pack"
  test "$(readlink "${tmp_home}/bin/ai-gstack-contract")" = "$(pwd)/tools/ai-gstack-contract"
  test "$(readlink "${tmp_home}/bin/ai-refactor-scan")" = "$(pwd)/tools/ai-refactor-scan"
  test "$(readlink "${tmp_home}/bin/ai-rebuild-plan")" = "$(pwd)/tools/ai-rebuild-plan"
  test "$(readlink "${tmp_home}/bin/ai-split-plan")" = "$(pwd)/tools/ai-split-plan"
  test "$(readlink "${tmp_home}/bin/ai-split-dry-run")" = "$(pwd)/tools/ai-split-dry-run"
  test "$(readlink "${tmp_home}/bin/ai-split-apply")" = "$(pwd)/tools/ai-split-apply"
  test "$(readlink "${tmp_home}/bin/ai-plan-status")" = "$(pwd)/tools/ai-plan-status"
  test "$(readlink "${tmp_home}/bin/ai-interview-record")" = "$(pwd)/tools/ai-interview-record"
  test "$(readlink "${tmp_home}/bin/ai-plan-review")" = "$(pwd)/tools/ai-plan-review"
  test "$(readlink "${tmp_home}/bin/ai-plan-export")" = "$(pwd)/tools/ai-plan-export"
  test "$(readlink "${tmp_home}/bin/feedback-collect")" = "$(pwd)/tools/feedback-collect"
  test "$(readlink "${tmp_home}/bin/feedback-resolve")" = "$(pwd)/tools/feedback-resolve"
  test "$(readlink "${tmp_home}/bin/knowledge-collect")" = "$(pwd)/tools/knowledge-collect"
  test "$(readlink "${tmp_home}/bin/workspace-scan")" = "$(pwd)/tools/workspace-scan"
  test "$(HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" AI_AUTO --path)" = "$(pwd)"
  grep -q "AI_AUTO shell integration" "${tmp_home}/.bashrc"
  grep -q '. "$HOME/.config/ai-lab/AI_AUTO.sh"' "${tmp_home}/.bashrc"
  grep -q "Managed by AI_AUTO" "${tmp_home}/.config/ai-lab/AI_AUTO.sh"
  grep -q 'cd "$(command AI_AUTO --path)"' "${tmp_home}/.config/ai-lab/AI_AUTO.sh"
  grep -q 'jwlist()' "${tmp_home}/.config/ai-lab/AI_AUTO.sh"
  grep -q 'sirdlist()' "${tmp_home}/.config/ai-lab/AI_AUTO.sh"
  grep -q 'AI_AUTO_JW_PROJECT_ROOT' "${tmp_home}/.config/ai-lab/AI_AUTO.sh"
  grep -q 'AI_AUTO_SIRD_PROJECT_ROOT' "${tmp_home}/.config/ai-lab/AI_AUTO.sh"
  grep -q 'tmux()' "${tmp_home}/.config/ai-lab/AI_AUTO.sh"
  grep -q 'command tmux new-session -s "${session_name}"' "${tmp_home}/.config/ai-lab/AI_AUTO.sh"
  if HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" bash -c \
    'source "$HOME/.config/ai-lab/AI_AUTO.sh"; AI_AUTO_JW_PROJECT_ROOT="$HOME/missing-root" jwlist' \
    > "${tmp_home}/jwlist-missing.out" 2> "${tmp_home}/jwlist-missing.err"; then
    echo "[verify] jwlist succeeded for a missing project root"
    exit 1
  fi
  grep -q "project root not found for jwlist" "${tmp_home}/jwlist-missing.err"
  grep -q "AI_AUTO_JW_PROJECT_ROOT=/path/to/root" "${tmp_home}/jwlist-missing.err"
  if HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" bash -c \
    'source "$HOME/.config/ai-lab/AI_AUTO.sh"; AI_AUTO_SIRD_PROJECT_ROOT="$HOME/missing-root" sirdlist' \
    > "${tmp_home}/sirdlist-missing.out" 2> "${tmp_home}/sirdlist-missing.err"; then
    echo "[verify] sirdlist succeeded for a missing project root"
    exit 1
  fi
  grep -q "project root not found for sirdlist" "${tmp_home}/sirdlist-missing.err"
  grep -q "AI_AUTO_SIRD_PROJECT_ROOT=/path/to/root" "${tmp_home}/sirdlist-missing.err"
  project_list_root="${tmp_home}/projects"
  mkdir -p "${project_list_root}/alpha" "${project_list_root}/beta/grouped/leaf" "${project_list_root}/gamma-no-git"
  printf '{}\n' > "${project_list_root}/beta/grouped/leaf/package.json"
  test "$(
    HOME="${tmp_home}" AI_AUTO_JW_PROJECT_ROOT="${project_list_root}" PATH="${tmp_home}/bin:${PATH}" bash -c \
      'source "$HOME/.config/ai-lab/AI_AUTO.sh"; jwlist <<< $'"'"'02\n01\n01'"'"' >/dev/null; pwd'
  )" = "${project_list_root}/beta/grouped/leaf"
  test "$(
    HOME="${tmp_home}" AI_AUTO_SIRD_PROJECT_ROOT="${project_list_root}" PATH="${tmp_home}/bin:${PATH}" bash -c \
      'source "$HOME/.config/ai-lab/AI_AUTO.sh"; sirdlist <<< $'"'"'3'"'"' >/dev/null; pwd'
  )" = "${project_list_root}/gamma-no-git"
  mkdir -p "${tmp_home}/fake-bin"
  cat > "${tmp_home}/fake-bin/tmux" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${TMUX_FAKE_LOG}"
if [ "${1:-}" = "has-session" ]; then
  case "${3:-}" in
    1)
      exit 0
      ;;
    *)
      exit 1
      ;;
  esac
fi
exit 0
STUB
  chmod +x "${tmp_home}/fake-bin/tmux"
  HOME="${tmp_home}" TMUX_FAKE_LOG="${tmp_home}/tmux.log" PATH="${tmp_home}/fake-bin:${tmp_home}/bin:${PATH}" bash -c 'source "$HOME/.config/ai-lab/AI_AUTO.sh"; tmux'
  grep -q '^has-session -t 1$' "${tmp_home}/tmux.log"
  grep -q '^has-session -t 2$' "${tmp_home}/tmux.log"
  grep -q '^new-session -s 2$' "${tmp_home}/tmux.log"
  test ! -e "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"

  HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/install-global-files.sh >/dev/null
  test "$(grep -c "AI_AUTO shell integration" "${tmp_home}/.bashrc")" -eq 2

  printf '%s\n' "# >>> AI_AUTO shell integration >>>" "preserve me" > "${tmp_home}/.bashrc"
  if HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/install-global-files.sh >/dev/null 2>&1; then
    echo "[verify] install-global-files edited unbalanced shell integration markers"
    exit 1
  fi
  grep -q "preserve me" "${tmp_home}/.bashrc"
)

echo "[verify] testing AI_AUTO shell function unmanaged-file conflict..."
(
  tmp_home="$(mktemp -d)"

  cleanup_ai_auto_conflict_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_ai_auto_conflict_tmp EXIT

  mkdir -p "${tmp_home}/bin" "${tmp_home}/.config/ai-lab"
  printf 'user owned\n' > "${tmp_home}/.config/ai-lab/AI_AUTO.sh"

  if HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/install-global-files.sh >/dev/null 2>&1; then
    echo "[verify] install-global-files overwrote unmanaged AI_AUTO shell function file"
    exit 1
  fi
  grep -q "user owned" "${tmp_home}/.config/ai-lab/AI_AUTO.sh"
)

echo "[verify] testing opt-in codex drift notice shell function..."
(
  tmp_home="$(mktemp -d)"

  cleanup_codex_drift_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_codex_drift_tmp EXIT

  fake_bin="${tmp_home}/fake-bin"
  repo_dir="${tmp_home}/project"
  mkdir -p "${fake_bin}" "${repo_dir}/subdir"

  cat > "${fake_bin}/codex" <<'STUB'
#!/usr/bin/env bash
stdin_content="$(cat)"
printf 'real codex'
for arg in "$@"; do
  printf ' <%s>' "$arg"
done
printf '\n'
printf 'stdin <%s>\n' "$stdin_content"
printf 'real codex stderr\n' >&2
exit "${CODEX_STUB_EXIT:-7}"
STUB

  cat > "${fake_bin}/ai-auto-template-status" <<'STUB'
#!/usr/bin/env bash
status="${AI_AUTO_TEMPLATE_STATUS_STUB:-customized_or_outdated}"
printf 'AI_AUTO Template Status\n'
printf 'target: %s\n' "${1:-}"
printf 'installed_version: old\n'
printf 'current_version: new\n'
printf 'status: %s\n' "$status"
STUB

  chmod +x "${fake_bin}/codex" "${fake_bin}/ai-auto-template-status"
  git -C "${repo_dir}" init -q
  printf 'old\n' > "${repo_dir}/AI_AUTO_TEMPLATE_VERSION"

  HOME="${tmp_home}" PATH="${fake_bin}:${PATH}" ./scripts/install-global-files.sh --install-codex-drift-notice >/dev/null
  grep -q "AI_AUTO codex drift notice integration" "${tmp_home}/.bashrc"
  grep -q "Managed by AI_AUTO install-global-files.sh codex drift notice" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q "${fake_bin}/codex" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q '^  local tmux_auto_default=0$' "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"

  set +e
  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; codex --alpha "two words"' \
    > "${tmp_home}/codex.out" 2> "${tmp_home}/codex.err"
  codex_status=$?
  set -e
  test "$codex_status" -eq 7
  grep -q "real codex <--alpha> <two words>" "${tmp_home}/codex.out"
  grep -q "stdin <>" "${tmp_home}/codex.out"
  grep -q "real codex stderr" "${tmp_home}/codex.err"
  grep -q "===== AI_AUTO UPDATE CHECK =====" "${tmp_home}/codex.err"
  grep -q "state: update_available" "${tmp_home}/codex.err"
  grep -q "status: customized_or_outdated" "${tmp_home}/codex.err"
  grep -q "latest patch note:" "${tmp_home}/codex.err"
  grep -q "review notes: .*templates/automation-base/docs/PATCH_NOTES.md" "${tmp_home}/codex.err"
  grep -q "action: AI_AUTO 최신 패치 적용해줘" "${tmp_home}/codex.err"

  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    CODEX_STUB_EXIT=0 \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; codex first; codex second' \
    > "${tmp_home}/codex-once.out" 2> "${tmp_home}/codex-once.err"
  grep -q "real codex <first>" "${tmp_home}/codex-once.out"
  grep -q "real codex <second>" "${tmp_home}/codex-once.out"
  test "$(grep -c "===== AI_AUTO UPDATE CHECK =====" "${tmp_home}/codex-once.err")" -eq 1

  printf 'input stream\n' | HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    CODEX_STUB_EXIT=0 \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; codex --stdin-check' \
    > "${tmp_home}/codex-stdin.out" 2> "${tmp_home}/codex-stdin.err"
  grep -q "real codex <--stdin-check>" "${tmp_home}/codex-stdin.out"
  grep -q "stdin <input stream>" "${tmp_home}/codex-stdin.out"
  grep -q "real codex stderr" "${tmp_home}/codex-stdin.err"

  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    AI_AUTO_CODEX_DRIFT_NOTICE=0 CODEX_STUB_EXIT=0 \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; codex' \
    > "${tmp_home}/codex-disabled.out" 2> "${tmp_home}/codex-disabled.err"
  grep -q "real codex" "${tmp_home}/codex-disabled.out"
  if grep -q "===== AI_AUTO UPDATE CHECK =====" "${tmp_home}/codex-disabled.err"; then
    echo "[verify] codex drift notice ignored AI_AUTO_CODEX_DRIFT_NOTICE=0"
    exit 1
  fi

  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    AI_AUTO_TEMPLATE_STATUS_STUB=current CODEX_STUB_EXIT=0 \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; codex' \
    > "${tmp_home}/codex-current.out" 2> "${tmp_home}/codex-current.err"
  grep -q "real codex" "${tmp_home}/codex-current.out"
  if grep -q "===== AI_AUTO UPDATE CHECK =====" "${tmp_home}/codex-current.err"; then
    echo "[verify] codex drift notice printed for current template"
    exit 1
  fi

  rm "${repo_dir}/AI_AUTO_TEMPLATE_VERSION"
  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    CODEX_STUB_EXIT=0 \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; codex' \
    > "${tmp_home}/codex-no-version.out" 2> "${tmp_home}/codex-no-version.err"
  grep -q "real codex" "${tmp_home}/codex-no-version.out"
  if grep -q "===== AI_AUTO UPDATE CHECK =====" "${tmp_home}/codex-no-version.err"; then
    echo "[verify] codex drift notice printed without AI_AUTO_TEMPLATE_VERSION"
    exit 1
  fi

  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" CODEX_STUB_EXIT=0 \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$HOME"; codex' \
    > "${tmp_home}/codex-outside-git.out" 2> "${tmp_home}/codex-outside-git.err"
  grep -q "real codex" "${tmp_home}/codex-outside-git.out"
  if grep -q "===== AI_AUTO UPDATE CHECK =====" "${tmp_home}/codex-outside-git.err"; then
    echo "[verify] codex drift notice printed outside git repository"
    exit 1
  fi

  HOME="${tmp_home}" PATH="${fake_bin}:${PATH}" ./scripts/install-global-files.sh --install-codex-drift-notice >/dev/null
  test "$(grep -c "AI_AUTO codex drift notice integration" "${tmp_home}/.bashrc")" -eq 2

  printf '%s\n' "# >>> AI_AUTO codex drift notice integration >>>" "preserve me" > "${tmp_home}/.bashrc"
  if HOME="${tmp_home}" PATH="${fake_bin}:${PATH}" ./scripts/install-global-files.sh --install-codex-drift-notice >/dev/null 2>&1; then
    echo "[verify] install-global-files edited unbalanced codex drift notice markers"
    exit 1
  fi
  grep -q "preserve me" "${tmp_home}/.bashrc"
)

echo "[verify] testing codex drift notice unmanaged-file conflict..."
(
  tmp_home="$(mktemp -d)"

  cleanup_codex_drift_conflict_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_codex_drift_conflict_tmp EXIT

  fake_bin="${tmp_home}/fake-bin"
  mkdir -p "${fake_bin}" "${tmp_home}/.config/ai-lab"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${fake_bin}/codex"
  chmod +x "${fake_bin}/codex"
  printf 'user owned\n' > "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"

  if HOME="${tmp_home}" PATH="${fake_bin}:${PATH}" ./scripts/install-global-files.sh --install-codex-drift-notice >/dev/null 2>&1; then
    echo "[verify] install-global-files overwrote unmanaged codex drift notice file"
    exit 1
  fi
  grep -q "user owned" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
)

echo "[verify] testing opt-in codex tmux auto-entry shell function..."
(
  tmp_home="$(mktemp -d)"

  cleanup_codex_tmux_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_codex_tmux_tmp EXIT

  fake_bin="${tmp_home}/fake-bin"
  repo_dir="${tmp_home}/project"
  mkdir -p "${fake_bin}" "${repo_dir}/subdir"

  cat > "${fake_bin}/codex" <<'STUB'
#!/bin/bash
stdin_content="$(/bin/cat)"
printf 'real codex'
for arg in "$@"; do
  printf ' <%s>' "$arg"
done
printf '\n'
printf 'stdin <%s>\n' "$stdin_content"
exit "${CODEX_STUB_EXIT:-0}"
STUB

  cat > "${fake_bin}/tmux" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${TMUX_FAKE_LOG}"
if [ "${TMUX_FAIL_FIRST_NEW_SESSION:-0}" = "1" ] && [ ! -e "${TMUX_FAKE_LOG}.failed-once" ]; then
  touch "${TMUX_FAKE_LOG}.failed-once"
  exit 1
fi
exit "${TMUX_STUB_EXIT:-0}"
STUB

  chmod +x "${fake_bin}/codex" "${fake_bin}/tmux"
  git -C "${repo_dir}" init -q
  tmux_tty_cmd="${tmp_home}/run-codex-tmux.sh"
  cat > "${tmux_tty_cmd}" <<'STUB'
#!/bin/bash
. "$HOME/.config/ai-lab/codex-drift-notice.sh"
cd "$REPO_DIR/subdir" || exit
codex --alpha "two words" "quote's"
STUB
  chmod +x "${tmux_tty_cmd}"

  HOME="${tmp_home}" PATH="${fake_bin}:${PATH}" ./scripts/install-global-files.sh --install-codex-tmux-auto-entry >/dev/null
  grep -q "AI_AUTO codex drift notice integration" "${tmp_home}/.bashrc"
  grep -q "AI_AUTO_CODEX_TMUX_AUTO" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q "_ai_auto_codex_tmux_session_name" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q "_ai_auto_start_tmux_session" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"

  HOME="${tmp_home}" PATH="${fake_bin}:${PATH}" ./scripts/install-global-files.sh --install-codex-drift-notice >/dev/null
  HOME="${tmp_home}" PATH="${fake_bin}:${PATH}" ./scripts/install-global-files.sh --install-codex-tmux-auto-entry >/dev/null
  grep -q '^  local drift_notice_default=1$' "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q '^  local tmux_auto_default=1$' "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"

  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    TMUX_FAKE_LOG="${tmp_home}/tmux-env-off.log" \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; AI_AUTO_CODEX_TMUX_AUTO=0 codex env-off' \
    > "${tmp_home}/codex-env-off.out"
  grep -q "real codex <env-off>" "${tmp_home}/codex-env-off.out"
  test ! -e "${tmp_home}/tmux-env-off.log"

  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    TMUX="" TMUX_FAKE_LOG="${tmp_home}/tmux-on.log" \
    /usr/bin/script -q -c "${tmux_tty_cmd}" /dev/null >/dev/null
  grep -Eq '^new-session -s ai-codex-project-[[:alnum:]]+ -c .*/project/subdir ' "${tmp_home}/tmux-on.log"
  grep -q "'--alpha' 'two words'" "${tmp_home}/tmux-on.log"
  grep -Fq "'quote'\\''s'" "${tmp_home}/tmux-on.log"

  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    TMUX="" TMUX_FAKE_LOG="${tmp_home}/tmux-retry.log" TMUX_FAIL_FIRST_NEW_SESSION=1 \
    /usr/bin/script -q -c "${tmux_tty_cmd}" /dev/null >/dev/null
  test "$(wc -l < "${tmp_home}/tmux-retry.log")" -eq 2
  grep -Eq '^new-session -s ai-codex-project-[[:alnum:]]+ -c .*/project/subdir ' "${tmp_home}/tmux-retry.log"
  grep -Eq '^new-session -s ai-codex-project-[[:alnum:]]+-2 -c .*/project/subdir ' "${tmp_home}/tmux-retry.log"

  printf 'input stream\n' | HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    TMUX_FAKE_LOG="${tmp_home}/tmux-nontty.log" \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; codex --stdin-check' \
    > "${tmp_home}/codex-nontty.out"
  grep -q "real codex <--stdin-check>" "${tmp_home}/codex-nontty.out"
  grep -q "stdin <input stream>" "${tmp_home}/codex-nontty.out"
  test ! -e "${tmp_home}/tmux-nontty.log"

  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    TMUX="/tmp/fake-tmux,1,0" TMUX_FAKE_LOG="${tmp_home}/tmux-nested.log" \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; codex nested' \
    > "${tmp_home}/codex-nested.out"
  grep -q "real codex <nested>" "${tmp_home}/codex-nested.out"
  test ! -e "${tmp_home}/tmux-nested.log"

  HOME="${tmp_home}" PATH="${fake_bin}" REPO_DIR="${repo_dir}" \
    /bin/bash -c '. "$HOME/.config/ai-lab/AI_AUTO.sh"; . "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; codex no-tmux' \
    > "${tmp_home}/codex-no-tmux.out"
  grep -q "real codex <no-tmux>" "${tmp_home}/codex-no-tmux.out"
)

echo "[verify] testing opt-in multi-runtime tmux auto-entry shell functions..."
(
  tmp_home="$(mktemp -d)"

  cleanup_ai_tmux_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_ai_tmux_tmp EXIT

  fake_bin="${tmp_home}/fake-bin"
  repo_dir="${tmp_home}/project"
  mkdir -p "${fake_bin}" "${repo_dir}/subdir"

  for runtime in codex claude agy; do
    cat > "${fake_bin}/${runtime}" <<'STUB'
#!/bin/bash
runtime_name="$(basename "$0")"
stdin_content="$(/bin/cat)"
printf 'real %s' "$runtime_name"
for arg in "$@"; do
  printf ' <%s>' "$arg"
done
printf '\n'
printf 'nofile <%s>\n' "$(ulimit -n)"
printf 'stdin <%s>\n' "$stdin_content"
STUB
    chmod +x "${fake_bin}/${runtime}"
  done

  cat > "${fake_bin}/tmux" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${TMUX_FAKE_LOG}"
exit "${TMUX_STUB_EXIT:-0}"
STUB
  chmod +x "${fake_bin}/tmux"
  git -C "${repo_dir}" init -q

  tmux_tty_cmd="${tmp_home}/run-ai-tmux.sh"
  cat > "${tmux_tty_cmd}" <<'STUB'
#!/bin/bash
. "$HOME/.config/ai-lab/codex-drift-notice.sh"
cd "$REPO_DIR/subdir" || exit
codex --alpha "two words" "quote's"
claude --beta "two words" "quote's"
agy --prompt "two words" "quote's"
STUB
  chmod +x "${tmux_tty_cmd}"

  HOME="${tmp_home}" PATH="${fake_bin}:${PATH}" ./scripts/install-global-files.sh --install-ai-tmux-auto-entry >/dev/null
  grep -q '^claude() {' "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q '^agy() {' "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q "AI_AUTO_TMUX_AUTO" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q "AI_AUTO_CLAUDE_TMUX_AUTO" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q "AI_AUTO_AGY_TMUX_AUTO" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q "AI_AUTO_NOFILE_LIMIT" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  grep -q "_ai_auto_raise_nofile_limit" "${tmp_home}/.config/ai-lab/codex-drift-notice.sh"

  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    TMUX="" TMUX_FAKE_LOG="${tmp_home}/tmux-ai.log" \
    /usr/bin/script -q -c "${tmux_tty_cmd}" /dev/null >/dev/null
  test "$(wc -l < "${tmp_home}/tmux-ai.log")" -eq 3
  grep -Eq '^new-session -s ai-codex-project-[[:alnum:]]+ -c .*/project/subdir ' "${tmp_home}/tmux-ai.log"
  grep -Eq '^new-session -s ai-claude-project-[[:alnum:]]+ -c .*/project/subdir ' "${tmp_home}/tmux-ai.log"
  grep -Eq '^new-session -s ai-agy-project-[[:alnum:]]+ -c .*/project/subdir ' "${tmp_home}/tmux-ai.log"
  grep -q "/codex' '--alpha' 'two words'" "${tmp_home}/tmux-ai.log"
  grep -q "/claude' '--beta' 'two words'" "${tmp_home}/tmux-ai.log"
  grep -q "/agy' '--prompt' 'two words'" "${tmp_home}/tmux-ai.log"
  test "$(grep -Fc 'ulimit -n 1048576 >/dev/null 2>&1 || true;' "${tmp_home}/tmux-ai.log")" -eq 3
  test "$(grep -Fc "'quote'\\''s'" "${tmp_home}/tmux-ai.log")" -eq 3

  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    TMUX_FAKE_LOG="${tmp_home}/tmux-global-off.log" \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; AI_AUTO_TMUX_AUTO=0 codex c; AI_AUTO_TMUX_AUTO=0 claude d; AI_AUTO_TMUX_AUTO=0 agy e' \
    > "${tmp_home}/global-off.out"
  grep -q "real codex <c>" "${tmp_home}/global-off.out"
  grep -q "real claude <d>" "${tmp_home}/global-off.out"
  grep -q "real agy <e>" "${tmp_home}/global-off.out"
  test ! -e "${tmp_home}/tmux-global-off.log"

	  HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
	    TMUX_FAKE_LOG="${tmp_home}/tmux-runtime-off.log" \
	    bash -c 'ulimit -n 10240; . "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; AI_AUTO_NOFILE_LIMIT=10240 AI_AUTO_CLAUDE_TMUX_AUTO=0 claude direct; AI_AUTO_NOFILE_LIMIT=10240 AI_AUTO_AGY_TMUX_AUTO=0 agy direct' \
	    > "${tmp_home}/runtime-off.out"
	  grep -q "real claude <direct>" "${tmp_home}/runtime-off.out"
	  grep -q "real agy <direct>" "${tmp_home}/runtime-off.out"
	  test "$(grep -Fc "nofile <10240>" "${tmp_home}/runtime-off.out")" -eq 2
  test ! -e "${tmp_home}/tmux-runtime-off.log"

  printf 'input stream\n' | HOME="${tmp_home}" PATH="${fake_bin}:${tmp_home}/bin:${PATH}" REPO_DIR="${repo_dir}" \
    TMUX_FAKE_LOG="${tmp_home}/tmux-ai-nontty.log" \
    bash -c '. "$HOME/.config/ai-lab/codex-drift-notice.sh"; cd "$REPO_DIR"; claude --stdin-check; agy --stdin-check' \
    > "${tmp_home}/ai-nontty.out"
  grep -q "real claude <--stdin-check>" "${tmp_home}/ai-nontty.out"
  grep -q "real agy <--stdin-check>" "${tmp_home}/ai-nontty.out"
  grep -q "stdin <input stream>" "${tmp_home}/ai-nontty.out"
  test ! -e "${tmp_home}/tmux-ai-nontty.log"
)

echo "[verify] testing multi-runtime tmux wrapper preservation..."
(
  tmp_home="$(mktemp -d)"

  cleanup_ai_tmux_preserve_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_ai_tmux_preserve_tmp EXIT

  fake_bin="${tmp_home}/fake bin"
  wrapper_path="${tmp_home}/.config/ai-lab/codex-drift-notice.sh"
  mkdir -p "${fake_bin}"

  for runtime in codex claude agy; do
    cat > "${fake_bin}/${runtime}" <<'STUB'
#!/bin/bash
printf 'real %s\n' "$(basename "$0")"
STUB
    chmod +x "${fake_bin}/${runtime}"
  done

  get_wrapper_local() {
    local function_name="$1"
    local local_name="$2"
    awk -v fn="${function_name}" -v local_name="${local_name}" '
      $0 == fn "() {" { in_fn=1; next }
      in_fn && $0 == "}" { exit }
      in_fn {
        prefix = "  local " local_name "="
        if (index($0, prefix) == 1) {
          print substr($0, length(prefix) + 1)
          exit
        }
      }
    ' "${wrapper_path}"
  }

  HOME="${tmp_home}" PATH="${fake_bin}:${PATH}" ./scripts/install-global-files.sh --install-ai-tmux-auto-entry >/dev/null
  claude_real_before="$(get_wrapper_local claude real_claude)"
  agy_real_before="$(get_wrapper_local agy real_agy)"
  case "${claude_real_before}" in
    *fake\\\ bin/claude)
      ;;
    *)
      echo "[verify] claude wrapper did not preserve a shell-quoted spaced path"
      exit 1
      ;;
  esac

  awk '
    $0 == "claude() {" { in_claude=1 }
    in_claude && $0 == "  local tmux_auto_default=1" {
      print "  local tmux_auto_default=0"
      next
    }
    in_claude && $0 == "}" { in_claude=0 }
    { print }
  ' "${wrapper_path}" > "${wrapper_path}.tmp"
  mv "${wrapper_path}.tmp" "${wrapper_path}"

  HOME="${tmp_home}" PATH="${fake_bin}:${PATH}" ./scripts/install-global-files.sh --install-codex-drift-notice >/dev/null
  test "$(get_wrapper_local claude real_claude)" = "${claude_real_before}"
  test "$(get_wrapper_local agy real_agy)" = "${agy_real_before}"
  test "$(get_wrapper_local codex tmux_auto_default)" = "1"
  test "$(get_wrapper_local claude tmux_auto_default)" = "0"
  test "$(get_wrapper_local agy tmux_auto_default)" = "1"
)

echo "[verify] testing global helper non-symlink conflict handling..."
(
  tmp_home="$(mktemp -d)"

  cleanup_global_conflict_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_global_conflict_tmp EXIT

  mkdir -p "${tmp_home}/bin"
  printf 'do not replace\n' > "${tmp_home}/bin/aiinit"

  if HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/install-global-files.sh >/dev/null; then
    echo "[verify] install-global-files unexpectedly overwrote or ignored non-symlink conflict"
    exit 1
  fi

  test ! -L "${tmp_home}/bin/aiinit"
  grep -q "do not replace" "${tmp_home}/bin/aiinit"
)

echo "[verify] testing global helper symlink-to-directory repair..."
(
  tmp_home="$(mktemp -d)"

  cleanup_global_dirlink_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_global_dirlink_tmp EXIT

  mkdir -p "${tmp_home}/bin" "${tmp_home}/old-helper-dir"
  ln -s "${tmp_home}/old-helper-dir" "${tmp_home}/bin/aiinit"

  HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/install-global-files.sh >/dev/null

  test "$(readlink "${tmp_home}/bin/aiinit")" = "$(pwd)/tools/ai-auto-init"
  test ! -e "${tmp_home}/old-helper-dir/ai-auto-init"
)

echo "[verify] testing bootstrap --fix global helper repair..."
(
  tmp_home="$(mktemp -d)"

  cleanup_bootstrap_fix_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_bootstrap_fix_tmp EXIT

  mkdir -p "${tmp_home}/bin" "${tmp_home}/old-checkout/tools"
  ln -s "${tmp_home}/old-checkout/tools/ai-home" "${tmp_home}/bin/AI_AUTO"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/ai-auto-init"
  ln -s "${tmp_home}/old-checkout/tools/ai-home" "${tmp_home}/bin/ai-home"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/aiinit"
  ln -s "${tmp_home}/old-checkout/tools/ai-register" "${tmp_home}/bin/ai-register"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-template-status" "${tmp_home}/bin/ai-auto-template-status"
  ln -s "${tmp_home}/old-checkout/tools/ai-domain-pack" "${tmp_home}/bin/ai-domain-pack"
  ln -s "${tmp_home}/old-checkout/tools/ai-gstack-contract" "${tmp_home}/bin/ai-gstack-contract"
  ln -s "${tmp_home}/old-checkout/tools/ai-refactor-scan" "${tmp_home}/bin/ai-refactor-scan"
  ln -s "${tmp_home}/old-checkout/tools/ai-rebuild-plan" "${tmp_home}/bin/ai-rebuild-plan"
  ln -s "${tmp_home}/old-checkout/tools/ai-split-plan" "${tmp_home}/bin/ai-split-plan"
  ln -s "${tmp_home}/old-checkout/tools/ai-split-dry-run" "${tmp_home}/bin/ai-split-dry-run"
  ln -s "${tmp_home}/old-checkout/tools/ai-split-apply" "${tmp_home}/bin/ai-split-apply"
  ln -s "${tmp_home}/old-checkout/tools/ai-plan-status" "${tmp_home}/bin/ai-plan-status"
  ln -s "${tmp_home}/old-checkout/tools/ai-interview-record" "${tmp_home}/bin/ai-interview-record"
  ln -s "${tmp_home}/old-checkout/tools/ai-plan-review" "${tmp_home}/bin/ai-plan-review"
  ln -s "${tmp_home}/old-checkout/tools/ai-plan-export" "${tmp_home}/bin/ai-plan-export"
  ln -s "${tmp_home}/old-checkout/tools/feedback-collect" "${tmp_home}/bin/feedback-collect"
  ln -s "${tmp_home}/old-checkout/tools/feedback-resolve" "${tmp_home}/bin/feedback-resolve"
  ln -s "${tmp_home}/old-checkout/tools/knowledge-collect" "${tmp_home}/bin/knowledge-collect"
  ln -s "${tmp_home}/old-checkout/tools/workspace-scan" "${tmp_home}/bin/workspace-scan"

  HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/bootstrap-ai-lab.sh --fix >/dev/null

  test "$(readlink "${tmp_home}/bin/AI_AUTO")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/ai-auto-init")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-home")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/aiinit")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-register")" = "$(pwd)/tools/ai-register"
  test "$(readlink "${tmp_home}/bin/ai-auto-template-status")" = "$(pwd)/tools/ai-auto-template-status"
  test "$(readlink "${tmp_home}/bin/ai-domain-pack")" = "$(pwd)/tools/ai-domain-pack"
  test "$(readlink "${tmp_home}/bin/ai-gstack-contract")" = "$(pwd)/tools/ai-gstack-contract"
  test "$(readlink "${tmp_home}/bin/ai-refactor-scan")" = "$(pwd)/tools/ai-refactor-scan"
  test "$(readlink "${tmp_home}/bin/ai-rebuild-plan")" = "$(pwd)/tools/ai-rebuild-plan"
  test "$(readlink "${tmp_home}/bin/ai-split-plan")" = "$(pwd)/tools/ai-split-plan"
  test "$(readlink "${tmp_home}/bin/ai-split-dry-run")" = "$(pwd)/tools/ai-split-dry-run"
  test "$(readlink "${tmp_home}/bin/ai-split-apply")" = "$(pwd)/tools/ai-split-apply"
  test "$(readlink "${tmp_home}/bin/ai-plan-status")" = "$(pwd)/tools/ai-plan-status"
  test "$(readlink "${tmp_home}/bin/ai-interview-record")" = "$(pwd)/tools/ai-interview-record"
  test "$(readlink "${tmp_home}/bin/ai-plan-review")" = "$(pwd)/tools/ai-plan-review"
  test "$(readlink "${tmp_home}/bin/ai-plan-export")" = "$(pwd)/tools/ai-plan-export"
  test "$(readlink "${tmp_home}/bin/feedback-collect")" = "$(pwd)/tools/feedback-collect"
  test "$(readlink "${tmp_home}/bin/feedback-resolve")" = "$(pwd)/tools/feedback-resolve"
  test "$(readlink "${tmp_home}/bin/knowledge-collect")" = "$(pwd)/tools/knowledge-collect"
  test "$(readlink "${tmp_home}/bin/workspace-scan")" = "$(pwd)/tools/workspace-scan"
)

echo "[verify] testing automation-doctor --fix global helper repair..."
(
  tmp_home="$(mktemp -d)"

  cleanup_doctor_fix_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_doctor_fix_tmp EXIT

  mkdir -p "${tmp_home}/bin" "${tmp_home}/old-checkout/tools"
  ln -s "${tmp_home}/old-checkout/tools/ai-home" "${tmp_home}/bin/AI_AUTO"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/ai-auto-init"
  ln -s "${tmp_home}/old-checkout/tools/ai-home" "${tmp_home}/bin/ai-home"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/aiinit"
  ln -s "${tmp_home}/old-checkout/tools/ai-register" "${tmp_home}/bin/ai-register"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-template-status" "${tmp_home}/bin/ai-auto-template-status"
  ln -s "${tmp_home}/old-checkout/tools/ai-domain-pack" "${tmp_home}/bin/ai-domain-pack"
  ln -s "${tmp_home}/old-checkout/tools/ai-gstack-contract" "${tmp_home}/bin/ai-gstack-contract"
  ln -s "${tmp_home}/old-checkout/tools/ai-refactor-scan" "${tmp_home}/bin/ai-refactor-scan"
  ln -s "${tmp_home}/old-checkout/tools/ai-rebuild-plan" "${tmp_home}/bin/ai-rebuild-plan"
  ln -s "${tmp_home}/old-checkout/tools/ai-split-plan" "${tmp_home}/bin/ai-split-plan"
  ln -s "${tmp_home}/old-checkout/tools/ai-split-dry-run" "${tmp_home}/bin/ai-split-dry-run"
  ln -s "${tmp_home}/old-checkout/tools/ai-split-apply" "${tmp_home}/bin/ai-split-apply"
  ln -s "${tmp_home}/old-checkout/tools/ai-plan-status" "${tmp_home}/bin/ai-plan-status"
  ln -s "${tmp_home}/old-checkout/tools/ai-interview-record" "${tmp_home}/bin/ai-interview-record"
  ln -s "${tmp_home}/old-checkout/tools/ai-plan-review" "${tmp_home}/bin/ai-plan-review"
  ln -s "${tmp_home}/old-checkout/tools/ai-plan-export" "${tmp_home}/bin/ai-plan-export"
  ln -s "${tmp_home}/old-checkout/tools/feedback-collect" "${tmp_home}/bin/feedback-collect"
  ln -s "${tmp_home}/old-checkout/tools/feedback-resolve" "${tmp_home}/bin/feedback-resolve"
  ln -s "${tmp_home}/old-checkout/tools/knowledge-collect" "${tmp_home}/bin/knowledge-collect"
  ln -s "${tmp_home}/old-checkout/tools/workspace-scan" "${tmp_home}/bin/workspace-scan"

  DOCTOR_SKIP_DIRTY_CHECK=1 HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/automation-doctor.sh --fix >/dev/null

  test "$(readlink "${tmp_home}/bin/AI_AUTO")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/ai-auto-init")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-home")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/aiinit")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-register")" = "$(pwd)/tools/ai-register"
  test "$(readlink "${tmp_home}/bin/ai-auto-template-status")" = "$(pwd)/tools/ai-auto-template-status"
  test "$(readlink "${tmp_home}/bin/ai-domain-pack")" = "$(pwd)/tools/ai-domain-pack"
  test "$(readlink "${tmp_home}/bin/ai-gstack-contract")" = "$(pwd)/tools/ai-gstack-contract"
  test "$(readlink "${tmp_home}/bin/ai-refactor-scan")" = "$(pwd)/tools/ai-refactor-scan"
  test "$(readlink "${tmp_home}/bin/ai-rebuild-plan")" = "$(pwd)/tools/ai-rebuild-plan"
  test "$(readlink "${tmp_home}/bin/ai-split-plan")" = "$(pwd)/tools/ai-split-plan"
  test "$(readlink "${tmp_home}/bin/ai-split-dry-run")" = "$(pwd)/tools/ai-split-dry-run"
  test "$(readlink "${tmp_home}/bin/ai-split-apply")" = "$(pwd)/tools/ai-split-apply"
  test "$(readlink "${tmp_home}/bin/ai-plan-status")" = "$(pwd)/tools/ai-plan-status"
  test "$(readlink "${tmp_home}/bin/ai-interview-record")" = "$(pwd)/tools/ai-interview-record"
  test "$(readlink "${tmp_home}/bin/ai-plan-review")" = "$(pwd)/tools/ai-plan-review"
  test "$(readlink "${tmp_home}/bin/ai-plan-export")" = "$(pwd)/tools/ai-plan-export"
  test "$(readlink "${tmp_home}/bin/feedback-collect")" = "$(pwd)/tools/feedback-collect"
  test "$(readlink "${tmp_home}/bin/feedback-resolve")" = "$(pwd)/tools/feedback-resolve"
  test "$(readlink "${tmp_home}/bin/knowledge-collect")" = "$(pwd)/tools/knowledge-collect"
  test "$(readlink "${tmp_home}/bin/workspace-scan")" = "$(pwd)/tools/workspace-scan"
)

echo "[verify] checking automation template sync..."
for doc in \
  AI_AUTOMATION_TREND_HARDENING.md \
  AI_MODEL_ROUTING.md \
  AI_RUNTIME_ADAPTERS.md \
  AUTOMATION_OPERATING_POLICY.md \
  OBSIDIAN_INTEGRATION.md
do
  if ! diff -u "docs/${doc}" "templates/automation-base/docs/${doc}"; then
    echo "[verify] automation doc copies are out of sync: ${doc}"
    echo "[verify] sync docs/${doc} and templates/automation-base/docs/${doc}, then rerun"
    exit 1
  fi
done
if ! diff -u \
  "docs/research/AI_AUTOMATION_TRENDS.md" \
  "templates/automation-base/docs/research/AI_AUTOMATION_TRENDS.md"; then
  echo "[verify] automation doc copies are out of sync: docs/research/AI_AUTOMATION_TRENDS.md"
  exit 1
fi

for script in \
  automation-doctor.sh \
  archive-omx-artifacts.sh \
  ai-runtime-adapter.sh \
  benchmark-command.py \
  todo-report.py \
  capture-knowledge-drafts.py \
  collect-review-context.sh \
  doc-budget.sh \
  guidance-duplicate-report.sh \
  discover-ai-models.sh \
  knowledge-notes.py \
  make-review-prompts.sh \
  record-feedback.sh \
  record-lane-decision.py \
  record-project-memory.sh \
  resolve-feedback.sh \
  validate-odoo-docs-kb.py \
  review-gate.sh \
  run-ai-reviews.sh \
  summarize-ai-reviews.sh \
  test-review-summary.sh \
  verify-machinery.sh \
  write-session-checkpoint.sh
do
  if [ ! -f "scripts/${script}" ] || [ ! -f "templates/automation-base/scripts/${script}" ]; then
    echo "[verify] automation script copy is missing: ${script}"
    exit 1
  fi

  if ! diff -u "scripts/${script}" "templates/automation-base/scripts/${script}"; then
    echo "[verify] automation script copies are out of sync: ${script}"
    echo "[verify] sync scripts/${script} and templates/automation-base/scripts/${script}, then rerun"
    exit 1
  fi
done

echo "[verify] running ai-lab bootstrap check..."
./scripts/bootstrap-ai-lab.sh
