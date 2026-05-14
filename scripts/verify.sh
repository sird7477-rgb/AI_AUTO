#!/usr/bin/env bash
set -euo pipefail

API_PORT="${API_PORT:-5001}"
BASE_URL="http://localhost:${API_PORT}"
repo_root="$(pwd)"

cleanup() {
  docker compose down >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "[verify] running pytest..."
.venv/bin/python -m pytest -q

echo "[verify] checking shell script syntax..."
for script in \
  scripts/bootstrap-ai-lab.sh \
  scripts/archive-omx-artifacts.sh \
  scripts/automation-doctor.sh \
  scripts/collect-review-context.sh \
  scripts/discover-ai-models.sh \
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
  scripts/write-session-checkpoint.sh \
  templates/automation-base/scripts/archive-omx-artifacts.sh \
  templates/automation-base/scripts/automation-doctor.sh \
  templates/automation-base/scripts/collect-review-context.sh \
  templates/automation-base/scripts/discover-ai-models.sh \
  templates/automation-base/scripts/make-review-prompts.sh \
  templates/automation-base/scripts/record-feedback.sh \
  templates/automation-base/scripts/record-project-memory.sh \
  templates/automation-base/scripts/resolve-feedback.sh \
  templates/automation-base/scripts/review-gate.sh \
  templates/automation-base/scripts/run-ai-reviews.sh \
  templates/automation-base/scripts/summarize-ai-reviews.sh \
  templates/automation-base/scripts/test-review-summary.sh \
  templates/automation-base/scripts/write-session-checkpoint.sh \
  templates/automation-base/scripts/verify.example.sh
do
  bash -n "${script}"
done
bash -n tools/ai-auto-init
bash -n tools/ai-home
bash -n tools/ai-register
bash -n tools/ai-auto-template-status
bash -n tools/ai-refactor-scan
bash -n tools/ai-rebuild-plan
bash -n tools/ai-split-plan
bash -n tools/ai-split-dry-run
bash -n tools/ai-split-apply
bash -n tools/ai-plan-status
bash -n tools/ai-interview-record
bash -n tools/ai-plan-review
bash -n tools/ai-plan-export
bash -n tools/feedback-collect
bash -n tools/workspace-scan
python3 -m py_compile tools/ai-python-split
python3 -m py_compile tools/ai-plan-workflow

echo "[verify] testing review summary decisions..."
./scripts/test-review-summary.sh

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

  cat > "${fake_bin}/gemini" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    echo "gemini fixture ${MODEL_STUB_VERSION:-v1}"
    ;;
  --help)
    if [ "${MODEL_STUB_MODE:-supported}" = "unsupported" ]; then
      echo "Usage: gemini [--model-context <tokens>]"
    else
      echo "Usage: gemini [-m, --model <model>]"
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

  chmod +x "${fake_bin}/claude" "${fake_bin}/gemini" "${fake_bin}/codex"

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
  grep -q "| Codex architect fallback | debug |" "${provider_role_dir}/latest.md"
  grep -q "| Codex test fallback | test_review |" "${provider_role_dir}/latest.md"

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

  mkdir -p .omx/plans
  printf '# PRD Fixture\n\nModule boundaries are documented here.\n' > .omx/plans/prd-fixture.md
  printf '# Test Spec Fixture\n\nRun focused verification.\n' > .omx/plans/test-spec-fixture.md
  "${context_script}" >/dev/null
  grep -q "Local Planning Artifacts" .omx/review-context/latest-review-context.md
  grep -q "prd-fixture.md" .omx/review-context/latest-review-context.md
  grep -q "test-spec-fixture.md" .omx/review-context/latest-review-context.md

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
)

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
    RESET_DISABLED_AI_REVIEWERS= \
    REVIEW_RUN_ID='fixture/run id' \
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

  cat > "${fake_bin}/gemini" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --help)
    echo "--prompt"
    exit 0
    ;;
esac
if grep -q "Truncation Notice"; then
  printf 'FATAL ERROR: Reached heap limit Allocation failed - JavaScript heap out of memory\n'
  exit 1
fi
printf 'expected capped prompt on stdin\n'
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

  chmod +x "${fake_bin}/claude" "${fake_bin}/gemini" "${fake_bin}/codex"

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
    CLAUDE_PROMPT_ARG_MAX_BYTES=10 \
    GEMINI_PROMPT_ARG_MAX_BYTES=10 \
    GEMINI_PROMPT_MAX_BYTES=120 \
    REVIEW_RETRY_LIMIT=1 \
    ./scripts/run-ai-reviews.sh > "${tmp_dir}/reviews.out"

  test -f "${tmp_dir}/prompts/gemini-review-capped-"*.md
  grep -q "reason=retry_exhausted" "${tmp_dir}/state/gemini.disabled"
  grep -q "class=oom" "${tmp_dir}/state/gemini.disabled"
  grep -q "exit_status=1" "${tmp_dir}/state/gemini.disabled"
  grep -q "preflight=prompt_bytes=" "${tmp_dir}/state/gemini.disabled"
  grep -q "prompt_flag=yes" "${tmp_dir}/state/gemini.disabled"
  grep -q "api_env=missing" "${tmp_dir}/state/gemini.disabled"
)

echo "[verify] testing focused review context budgeting..."
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

  test -f .omx/review-prompts/focused-review-context.md
  grep -q "Focused Review Context" .omx/review-prompts/focused-review-context.md
  grep -q "new.txt" .omx/review-prompts/focused-review-context.md
  grep -q "exceeded REVIEW_CONTEXT_MAX_BYTES=200" .omx/review-prompts/focused-review-context.md
  grep -q "Bounded Actual Diff" .omx/review-prompts/focused-review-context.md
  grep -q "diff --git a/README.md b/README.md" .omx/review-prompts/focused-review-context.md
  grep -q "+changed" .omx/review-prompts/focused-review-context.md
  grep -q "+new file" .omx/review-prompts/focused-review-context.md
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
    RUN_GEMINI_REVIEW=0 \
    REVIEW_RETRY_LIMIT=1 \
    ./scripts/run-ai-reviews.sh > "${tmp_dir}/reviews.out"

  grep -q "reason=retry_exhausted" "${tmp_dir}/state/claude.disabled"
  grep -q "class=network_or_sandbox" "${tmp_dir}/state/claude.disabled"
  grep -q "print_flag=yes" "${tmp_dir}/state/claude.disabled"
)

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
  mkdir -p docs scripts .omx/reviewer-state .omx/review-results
  printf '# Agents\n' > AGENTS.md
  printf '# AI Model Routing\n' > docs/AI_MODEL_ROUTING.md
  printf '# Automation Operating Policy\n' > docs/AUTOMATION_OPERATING_POLICY.md
  printf '# Domain Pack Authoring Guide\n' > docs/DOMAIN_PACK_AUTHORING_GUIDE.md
  printf '# Interview Plan Layer\n' > docs/INTERVIEW_PLAN_LAYER.md
  printf '# Data Completion Pack\n' > docs/DATA_COMPLETION.md
  printf '# Deployment Completion Pack\n' > docs/DEPLOYMENT_COMPLETION.md
  printf '# Observability Completion Pack\n' > docs/OBSERVABILITY_COMPLETION.md
  printf '# Performance Completion Pack\n' > docs/PERFORMANCE_COMPLETION.md
  printf '# Security Completion Pack\n' > docs/SECURITY_COMPLETION.md
  printf '# Session Quality Plan\n' > docs/SESSION_QUALITY_PLAN.md
  printf '# UI Completion Pack\n' > docs/UI_COMPLETION.md
  printf '# Workflow\n' > docs/WORKFLOW.md

  for script in \
    archive-omx-artifacts.sh \
    automation-doctor.sh \
    collect-review-context.sh \
    discover-ai-models.sh \
      make-review-prompts.sh \
      record-feedback.sh \
      record-project-memory.sh \
      resolve-feedback.sh \
      review-gate.sh \
    run-ai-reviews.sh \
    summarize-ai-reviews.sh \
    test-review-summary.sh \
    write-session-checkpoint.sh
  do
    cp "${repo_root}/scripts/${script}" "scripts/${script}"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/verify.sh
  chmod +x scripts/*.sh

  for index in 1 2 3 4 5 6; do
    printf 'old %s\n' "${index}" > ".omx/review-results/old-${index}.md"
  done
  printf '# run\n' > .omx/review-results/review-run-latest.md
  printf '# summary\n' > .omx/review-results/review-summary-latest.md
  printf '# verdict\n' > .omx/review-results/review-verdict-latest.md

  DOCTOR_SKIP_DIRTY_CHECK=1 \
    OMX_ARTIFACT_WARN_COUNT=5 \
    OMX_REVIEW_ARCHIVE_KEEP_FILES=3 \
    ./scripts/automation-doctor.sh --fix > "${tmp_dir}/doctor.out"

  grep -q "archived old review artifacts" "${tmp_dir}/doctor.out"
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
  mkdir -p docs scripts .omx/reviewer-state .omx/review-results
  printf '# Agents\n' > AGENTS.md
  printf '# AI Model Routing\n' > docs/AI_MODEL_ROUTING.md
  printf '# Automation Operating Policy\n' > docs/AUTOMATION_OPERATING_POLICY.md
  printf '# Domain Pack Authoring Guide\n' > docs/DOMAIN_PACK_AUTHORING_GUIDE.md
  printf '# Interview Plan Layer\n' > docs/INTERVIEW_PLAN_LAYER.md
  printf '# Data Completion Pack\n' > docs/DATA_COMPLETION.md
  printf '# Deployment Completion Pack\n' > docs/DEPLOYMENT_COMPLETION.md
  printf '# Observability Completion Pack\n' > docs/OBSERVABILITY_COMPLETION.md
  printf '# Performance Completion Pack\n' > docs/PERFORMANCE_COMPLETION.md
  printf '# Security Completion Pack\n' > docs/SECURITY_COMPLETION.md
  printf '# Session Quality Plan\n' > docs/SESSION_QUALITY_PLAN.md
  printf '# UI Completion Pack\n' > docs/UI_COMPLETION.md
  printf '# Workflow\n' > docs/WORKFLOW.md

  for script in \
    archive-omx-artifacts.sh \
    automation-doctor.sh \
    collect-review-context.sh \
    discover-ai-models.sh \
      make-review-prompts.sh \
      record-feedback.sh \
      record-project-memory.sh \
      resolve-feedback.sh \
      review-gate.sh \
    run-ai-reviews.sh \
    summarize-ai-reviews.sh \
    test-review-summary.sh \
    write-session-checkpoint.sh
  do
    cp "${repo_root}/scripts/${script}" "scripts/${script}"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/verify.sh
  chmod +x scripts/*.sh

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
  mkdir -p docs scripts .omx/reviewer-state
  printf '# Agents\n' > AGENTS.md
  printf '# AI Model Routing\n' > docs/AI_MODEL_ROUTING.md
  printf '# Automation Operating Policy\n' > docs/AUTOMATION_OPERATING_POLICY.md
  printf '# Domain Pack Authoring Guide\n' > docs/DOMAIN_PACK_AUTHORING_GUIDE.md
  printf '# Interview Plan Layer\n' > docs/INTERVIEW_PLAN_LAYER.md
  printf '# Session Quality Plan\n' > docs/SESSION_QUALITY_PLAN.md
  printf '# Workflow\n' > docs/WORKFLOW.md

  for script in \
    archive-omx-artifacts.sh \
    automation-doctor.sh \
    collect-review-context.sh \
    discover-ai-models.sh \
      make-review-prompts.sh \
      record-feedback.sh \
      record-project-memory.sh \
      resolve-feedback.sh \
      review-gate.sh \
    run-ai-reviews.sh \
    summarize-ai-reviews.sh \
    test-review-summary.sh \
    write-session-checkpoint.sh
  do
    cp "${repo_root}/scripts/${script}" "scripts/${script}"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/verify.sh
  chmod +x scripts/*.sh

  DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh > "${tmp_dir}/doctor.out"
  grep -q "Summary:" "${tmp_dir}/doctor.out"
  ! grep -q "DATA_COMPLETION.md" "${tmp_dir}/doctor.out"
  ! grep -q "UI_COMPLETION.md" "${tmp_dir}/doctor.out"
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
  ./scripts/install-automation-template.sh "${target_dir}" > "${installer_output}"
  test -x "${target_dir}/scripts/archive-omx-artifacts.sh"
  test -x "${target_dir}/scripts/discover-ai-models.sh"
  test -x "${target_dir}/scripts/record-feedback.sh"
  test -x "${target_dir}/scripts/record-project-memory.sh"
  test -x "${target_dir}/scripts/run-ai-reviews.sh"
  test -x "${target_dir}/scripts/write-session-checkpoint.sh"
  test -f "${target_dir}/AI_AUTO_TEMPLATE_VERSION"
  test -f "${target_dir}/docs/AI_MODEL_ROUTING.md"
  test -f "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  test -f "${target_dir}/docs/DATA_COMPLETION.md"
  test -f "${target_dir}/docs/DEPLOYMENT_COMPLETION.md"
  test -f "${target_dir}/docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
  test -f "${target_dir}/docs/DOMAIN_PACKS.md"
  test -f "${target_dir}/docs/INTERVIEW_PLAN_LAYER.md"
  test -f "${target_dir}/docs/INCIDENT_OPS.md"
  test -f "${target_dir}/docs/OBSERVABILITY_COMPLETION.md"
  test -f "${target_dir}/docs/PATCH_NOTES.md"
  test -f "${target_dir}/docs/PERFORMANCE_COMPLETION.md"
  test -f "${target_dir}/docs/SECURITY_COMPLETION.md"
  test -f "${target_dir}/docs/SESSION_QUALITY_PLAN.md"
  test -f "${target_dir}/docs/UI_COMPLETION.md"
  grep -q "VERIFY_TEMPLATE_UNCONFIGURED""=1" "${target_dir}/scripts/verify.sh"
  cmp -s "templates/automation-base/AI_AUTO_TEMPLATE_VERSION" "${target_dir}/AI_AUTO_TEMPLATE_VERSION"
  grep -q "role-first" "${target_dir}/docs/AI_MODEL_ROUTING.md"
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
  grep -q "AI_AUTO Patch Notes" "${target_dir}/docs/PATCH_NOTES.md"
  grep -q "Performance Completion Pack" "${target_dir}/docs/PERFORMANCE_COMPLETION.md"
  grep -q "Security Completion Pack" "${target_dir}/docs/SECURITY_COMPLETION.md"
  grep -q "Session Quality Plan" "${target_dir}/docs/SESSION_QUALITY_PLAN.md"
  grep -q "UI Completion Pack" "${target_dir}/docs/UI_COMPLETION.md"
  grep -q "UI가 필요하면" "${target_dir}/docs/WORKFLOW.md"
  grep -q "Subagent Utilization" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "Onboarding Interview Structure" "${target_dir}/docs/AUTOMATION_OPERATING_POLICY.md"
  grep -q "Native subagents" "${target_dir}/docs/AI_MODEL_ROUTING.md"
  grep -q "서브에이전트 사용 기준" "${target_dir}/docs/WORKFLOW.md"
  grep -q "Do not present guesses" "${target_dir}/AGENTS.md"
  grep -q "review intensity policy" "${target_dir}/AGENTS.md"
  grep -q "resource-aware parallelism" "${target_dir}/AGENTS.md"
  grep -q "Planning And Interview Escalation" "${target_dir}/AGENTS.md"
  grep -q "docs/INTERVIEW_PLAN_LAYER.md" "${target_dir}/AGENTS.md"
  grep -q "codemod apply" "${target_dir}/AGENTS.md"
  grep -q '`none`' "${target_dir}/AGENTS.md"
  grep -q '`light`' "${target_dir}/AGENTS.md"
  grep -q '`standard`' "${target_dir}/AGENTS.md"
  grep -q '`deep`' "${target_dir}/AGENTS.md"
  grep -q "applicable completion packs from" "${target_dir}/AGENTS.md"
  grep -Eq '^[.]omx/?$' "${target_dir}/.git/info/exclude"
  grep -q "프로젝트 초기설정 해줘" "${target_dir}/AGENTS.md"
  grep -q "Delete unused" "${target_dir}/AGENTS.md"
  grep -q "docs/DOMAIN_PACKS.md" "templates/automation-base/README.md"
  grep -q "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "templates/automation-base/README.md"
  grep -q "Review intensity" "templates/automation-base/README.md"
  grep -q "Subagents" "templates/automation-base/README.md"
  grep -q "Planning/interview intensity" "templates/automation-base/README.md"
  grep -q "docs/INTERVIEW_PLAN_LAYER.md" "templates/automation-base/README.md"
  grep -q "Operational readiness" "templates/automation-base/README.md"
  grep -q "Incident Ops" "templates/automation-base/README.md"
  grep -q "heartbeat/quiet/active" "templates/automation-base/README.md"
  grep -q "sandbox-vs-real-network evidence" "templates/automation-base/README.md"
  grep -q "Plan management" "templates/automation-base/README.md"
  grep -q "Guidance context budget" "templates/automation-base/README.md"
  grep -q "ai-auto-template-status" "templates/automation-base/README.md"
  grep -q "unused completion pack" "templates/automation-base/README.md"
  grep -q "docs/DOMAIN_PACKS.md" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "docs/INTERVIEW_PLAN_LAYER.md" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "review intensity" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "서브에이전트 사용 기준" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "플랜/인터뷰 강도 기준" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "none/light/standard/deep" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "Incident Ops 감시/장애대응/주기보고 기준" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "Template Status Comparison" "docs/NEW_PROJECT_GUIDE.md"
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
  grep -q "linked docs" "${target_dir}/docs/WORKFLOW.md"
  grep -q "ai-context-pack" "${target_dir}/docs/WORKFLOW.md"
  grep -q "advisory/fail-open" "${target_dir}/docs/WORKFLOW.md"
  test ! -e "${target_dir}/templates/domain-packs/odoo/README.md"
  test -f "${target_dir}/.omx/domain-packs/odoo/README.md"
  grep -q "Optional domain packs installed for onboarding reference" "${installer_output}"

  "${repo_root}/tools/ai-auto-template-status" "${target_dir}" > "${tmp_dir}/template-status-current.out"
  grep -q "status: current" "${tmp_dir}/template-status-current.out"
  grep -q "docs/INTERVIEW_PLAN_LAYER.md" "${tmp_dir}/template-status-current.out"
  grep -q "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "${tmp_dir}/template-status-current.out"
  grep -q "docs/PATCH_NOTES.md" "${tmp_dir}/template-status-current.out"
  grep -q $'STATE\tPATH\tTEMPLATE_PATH\tOWNERSHIP\tPATCH_POLICY' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/WORKFLOW.md\tdocs/WORKFLOW.md' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/WORKFLOW.md\tdocs/WORKFLOW.md\thybrid\treview-merge' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/DOMAIN_PACK_AUTHORING_GUIDE.md\tdocs/DOMAIN_PACK_AUTHORING_GUIDE.md' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/DOMAIN_PACKS.md\tdocs/DOMAIN_PACKS.md' "${tmp_dir}/template-status-current.out"
  grep -q $'same\tdocs/PATCH_NOTES.md\tdocs/PATCH_NOTES.md\ttemplate-owned\tupdate' "${tmp_dir}/template-status-current.out"
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

echo "[verify] checking optional domain pack structure..."
test -f "templates/domain-packs/odoo/README.md"
test -f "templates/domain-packs/odoo/AGENTS.patch.md"
test -f "templates/domain-packs/odoo/WORKFLOW.md"
test -f "templates/domain-packs/odoo/verify-patterns.md"
test -f "templates/domain-packs/odoo/review-checklist.md"
grep -q "ignored onboarding reference under" "templates/domain-packs/odoo/README.md"
grep -q "docs/DOMAIN_PACKS.md" "templates/domain-packs/odoo/README.md"
grep -q "docs/DOMAIN_PACK_AUTHORING_GUIDE.md" "templates/domain-packs/odoo/README.md"
grep -q "ko_KR" "templates/domain-packs/odoo/README.md"
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
grep -q "Incident Ops For Dry-run And Field-test" "templates/automation-base/docs/INCIDENT_OPS.md"
grep -q "Periodic Status Reporting" "templates/automation-base/docs/INCIDENT_OPS.md"
grep -q "Incident Ops During Dry-run And Field-test" "templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md"
grep -q "field-test incident evidence" "templates/automation-base/docs/UI_COMPLETION.md"
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

  ./scripts/install-automation-template.sh "${target_dir}" >/dev/null

  grep -q "keep me" "${target_dir}/.omx/domain-packs/odoo/README.md"
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

  if ./scripts/install-automation-template.sh "${target_dir}" > "${conflict_output}"; then
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
  AI_AUTO_PROJECT_REGISTRY_FILE="${registry_file}" ./tools/ai-auto-init "${target_dir}" > "${aiinit_output}"
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
  grep -q "linked docs 분리 기준" "${aiinit_output}"
  grep -q "Project registered" "${aiinit_output}"
  grep -q "프로젝트 초기설정 해줘" "${target_dir}/AGENTS.md"
  grep -q "sandbox-vs-real-network" "${target_dir}/AGENTS.md"
  grep -q "Incident Ops rules" "${target_dir}/AGENTS.md"
  grep -q "plan index/TODO reconciliation" "${target_dir}/AGENTS.md"
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
  printf '%s\n' '{"created_at":"2026-05-11T00:00:00Z","repeat_key":"registered:item","severity":"high","summary":"registered queue item","type":"improvement"}' > "${target_dir}/.omx/feedback/queue.jsonl"
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
  ln -s "${tmp_home}/old-checkout/tools/workspace-scan" "${tmp_home}/bin/workspace-scan"

  HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/install-global-files.sh >/dev/null

  test "$(readlink "${tmp_home}/bin/AI_AUTO")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/ai-auto-init")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-home")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/aiinit")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-register")" = "$(pwd)/tools/ai-register"
  test "$(readlink "${tmp_home}/bin/ai-auto-template-status")" = "$(pwd)/tools/ai-auto-template-status"
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
  test "$(readlink "${tmp_home}/bin/workspace-scan")" = "$(pwd)/tools/workspace-scan"
  test "$(HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" AI_AUTO --path)" = "$(pwd)"
  grep -q "AI_AUTO shell integration" "${tmp_home}/.bashrc"
  grep -q '. "$HOME/.config/ai-lab/AI_AUTO.sh"' "${tmp_home}/.bashrc"
  grep -q "Managed by AI_AUTO" "${tmp_home}/.config/ai-lab/AI_AUTO.sh"
  grep -q 'cd "$(command AI_AUTO --path)"' "${tmp_home}/.config/ai-lab/AI_AUTO.sh"

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
  ln -s "${tmp_home}/old-checkout/tools/workspace-scan" "${tmp_home}/bin/workspace-scan"

  HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/bootstrap-ai-lab.sh --fix >/dev/null

  test "$(readlink "${tmp_home}/bin/AI_AUTO")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/ai-auto-init")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-home")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/aiinit")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-register")" = "$(pwd)/tools/ai-register"
  test "$(readlink "${tmp_home}/bin/ai-auto-template-status")" = "$(pwd)/tools/ai-auto-template-status"
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
  ln -s "${tmp_home}/old-checkout/tools/workspace-scan" "${tmp_home}/bin/workspace-scan"

  DOCTOR_SKIP_DIRTY_CHECK=1 HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/automation-doctor.sh --fix >/dev/null

  test "$(readlink "${tmp_home}/bin/AI_AUTO")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/ai-auto-init")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-home")" = "$(pwd)/tools/ai-home"
  test "$(readlink "${tmp_home}/bin/aiinit")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/ai-register")" = "$(pwd)/tools/ai-register"
  test "$(readlink "${tmp_home}/bin/ai-auto-template-status")" = "$(pwd)/tools/ai-auto-template-status"
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
  test "$(readlink "${tmp_home}/bin/workspace-scan")" = "$(pwd)/tools/workspace-scan"
)

echo "[verify] checking automation template sync..."
for script in \
  automation-doctor.sh \
  archive-omx-artifacts.sh \
  collect-review-context.sh \
  discover-ai-models.sh \
  make-review-prompts.sh \
  record-feedback.sh \
  record-project-memory.sh \
  resolve-feedback.sh \
  review-gate.sh \
  run-ai-reviews.sh \
  summarize-ai-reviews.sh \
  test-review-summary.sh \
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

echo "[verify] starting docker compose on API_PORT=${API_PORT}..."
API_PORT="${API_PORT}" docker compose up --build -d

echo "[verify] waiting for API..."
for i in {1..30}; do
  if curl -fsS "${BASE_URL}/" >/dev/null; then
    break
  fi

  if [ "$i" -eq 30 ]; then
    echo "[verify] API did not become ready"
    docker compose ps
    docker compose logs api --tail=80
    exit 1
  fi

  sleep 1
done

echo "[verify] checking / ..."
curl -fsS "${BASE_URL}/"
echo

echo "[verify] checking /todos ..."
curl -fsS "${BASE_URL}/todos"
echo

echo "[verify] docker compose status..."
docker compose ps

echo "[verify] success"
