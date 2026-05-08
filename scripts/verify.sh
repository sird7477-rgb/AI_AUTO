#!/usr/bin/env bash
set -euo pipefail

API_PORT="${API_PORT:-5001}"
BASE_URL="http://localhost:${API_PORT}"

cleanup() {
  docker compose down >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "[verify] running pytest..."
.venv/bin/python -m pytest -q

echo "[verify] checking shell script syntax..."
for script in \
  scripts/bootstrap-ai-lab.sh \
  scripts/automation-doctor.sh \
  scripts/collect-review-context.sh \
  scripts/discover-ai-models.sh \
  scripts/install-global-files.sh \
  scripts/install-automation-template.sh \
  scripts/make-review-prompts.sh \
  scripts/review-gate.sh \
  scripts/run-ai-reviews.sh \
  scripts/summarize-ai-reviews.sh \
  scripts/test-review-summary.sh \
  templates/automation-base/scripts/automation-doctor.sh \
  templates/automation-base/scripts/collect-review-context.sh \
  templates/automation-base/scripts/discover-ai-models.sh \
  templates/automation-base/scripts/make-review-prompts.sh \
  templates/automation-base/scripts/review-gate.sh \
  templates/automation-base/scripts/run-ai-reviews.sh \
  templates/automation-base/scripts/summarize-ai-reviews.sh \
  templates/automation-base/scripts/test-review-summary.sh \
  templates/automation-base/scripts/verify.example.sh
do
  bash -n "${script}"
done

echo "[verify] testing review summary decisions..."
./scripts/test-review-summary.sh

echo "[verify] testing AI model discovery..."
(
  tmp_dir="$(mktemp -d)"

  cleanup_model_tmp() {
    rm -rf "${tmp_dir}"
  }

  trap cleanup_model_tmp EXIT

  AI_MODEL_DISCOVERY_DIR="${tmp_dir}" ./scripts/discover-ai-models.sh >/dev/null
  test -f "${tmp_dir}/latest.env"
  test -f "${tmp_dir}/latest.md"
  grep -q "^CLAUDE_REVIEW_MODEL=" "${tmp_dir}/latest.env"
  grep -q "^GEMINI_REVIEW_MODEL=" "${tmp_dir}/latest.env"
  grep -q "^CODEX_ARCHITECT_REVIEW_MODEL=" "${tmp_dir}/latest.env"
  grep -q "^CODEX_TEST_REVIEW_MODEL=" "${tmp_dir}/latest.env"
  grep -q "AI Model Routing Inventory" "${tmp_dir}/latest.md"

  custom_dir="${tmp_dir}/custom-routing"
  AI_MODEL_DISCOVERY_DIR="${tmp_dir}/base-routing" \
    AI_MODEL_ROUTING_ENV="${custom_dir}/env/latest.env" \
    AI_MODEL_ROUTING_REPORT="${custom_dir}/report/latest.md" \
    ./scripts/discover-ai-models.sh >/dev/null
  test -f "${custom_dir}/env/latest.env"
  test -f "${custom_dir}/report/latest.md"

  fake_bin="${tmp_dir}/fake-bin"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/claude" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    echo "claude fixture"
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
    echo "gemini fixture"
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
  echo "codex fixture"
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

  core_bin="${tmp_dir}/core-bin"
  mkdir -p "${core_bin}"
  for tool in bash cat date dirname grep head mkdir sed; do
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
  grep -q "No staged or unstaged tracked diff detected" .omx/review-context/latest-review-context.md
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
  test -x "${target_dir}/scripts/discover-ai-models.sh"
  test -x "${target_dir}/scripts/run-ai-reviews.sh"
  grep -q "VERIFY_TEMPLATE_UNCONFIGURED""=1" "${target_dir}/scripts/verify.sh"
  grep -Eq '^[.]omx/?$' "${target_dir}/.git/info/exclude"
  grep -q "프로젝트 초기설정 해줘" "${target_dir}/AGENTS.md"
  grep -q "프로젝트 요구사항 인터뷰하고 AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 프로젝트에 맞게 설정해줘" "templates/automation-base/README.md"
  grep -q "프로젝트 요구사항 인터뷰하고 AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 프로젝트에 맞게 설정해줘" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "프로젝트 초기설정 해줘" "${installer_output}"
  grep -q "프로젝트 요구사항 인터뷰하고 AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 프로젝트에 맞게 설정해줘" "${installer_output}"
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
  git -c init.defaultBranch=main init -q "${target_dir}"
  ./tools/ai-auto-init "${target_dir}" > "${aiinit_output}"
  grep -q "프로젝트 초기설정 해줘" "${aiinit_output}"
  grep -q "프로젝트 요구사항 인터뷰하고 AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 프로젝트에 맞게 설정해줘" "${aiinit_output}"
  grep -q "프로젝트 초기설정 해줘" "${target_dir}/AGENTS.md"
)

echo "[verify] testing global helper link repair..."
(
  tmp_home="$(mktemp -d)"

  cleanup_global_tmp() {
    rm -rf "${tmp_home}"
  }

  trap cleanup_global_tmp EXIT

  mkdir -p "${tmp_home}/bin" "${tmp_home}/old-checkout/tools"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/ai-auto-init"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/aiinit"
  ln -s "${tmp_home}/old-checkout/tools/workspace-scan" "${tmp_home}/bin/workspace-scan"

  HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/install-global-files.sh >/dev/null

  test "$(readlink "${tmp_home}/bin/ai-auto-init")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/aiinit")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/workspace-scan")" = "$(pwd)/tools/workspace-scan"
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
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/ai-auto-init"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/aiinit"
  ln -s "${tmp_home}/old-checkout/tools/workspace-scan" "${tmp_home}/bin/workspace-scan"

  HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/bootstrap-ai-lab.sh --fix >/dev/null

  test "$(readlink "${tmp_home}/bin/ai-auto-init")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/aiinit")" = "$(pwd)/tools/ai-auto-init"
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
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/ai-auto-init"
  ln -s "${tmp_home}/old-checkout/tools/ai-auto-init" "${tmp_home}/bin/aiinit"
  ln -s "${tmp_home}/old-checkout/tools/workspace-scan" "${tmp_home}/bin/workspace-scan"

  DOCTOR_SKIP_DIRTY_CHECK=1 HOME="${tmp_home}" PATH="${tmp_home}/bin:${PATH}" ./scripts/automation-doctor.sh --fix >/dev/null

  test "$(readlink "${tmp_home}/bin/ai-auto-init")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/aiinit")" = "$(pwd)/tools/ai-auto-init"
  test "$(readlink "${tmp_home}/bin/workspace-scan")" = "$(pwd)/tools/workspace-scan"
)

echo "[verify] checking automation template sync..."
for script in \
  automation-doctor.sh \
  collect-review-context.sh \
  discover-ai-models.sh \
  make-review-prompts.sh \
  review-gate.sh \
  run-ai-reviews.sh \
  summarize-ai-reviews.sh \
  test-review-summary.sh
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
