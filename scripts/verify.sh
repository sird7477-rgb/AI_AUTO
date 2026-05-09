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
  scripts/record-project-memory.sh \
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
  templates/automation-base/scripts/record-project-memory.sh \
  templates/automation-base/scripts/review-gate.sh \
  templates/automation-base/scripts/run-ai-reviews.sh \
  templates/automation-base/scripts/summarize-ai-reviews.sh \
  templates/automation-base/scripts/test-review-summary.sh \
  templates/automation-base/scripts/write-session-checkpoint.sh \
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

  unset AI_MODEL_DISCOVERY_REFRESH
  unset AI_MODEL_ROUTING_TTL_SECONDS
  unset CLAUDE_REVIEW_ROLE
  unset GEMINI_REVIEW_ROLE
  unset CODEX_ARCHITECT_REVIEW_ROLE
  unset CODEX_TEST_REVIEW_ROLE
  unset CLAUDE_REVIEW_MODEL
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
  grep -q "AI Model Routing Inventory" "${tmp_dir}/latest.md"
  grep -q "Role Profiles" "${tmp_dir}/latest.md"
  grep -q "Cache Policy" "${tmp_dir}/latest.md"

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
  grep -q "^CLAUDE_REVIEW_MODEL='opus'$" "${role_default_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='inferred:claude-cli-alias:opus;role:architect_review'$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='refreshed'$" "${role_default_dir}/latest.env"

  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    AI_MODEL_DISCOVERY_DIR="${role_default_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL='opus'$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_STATUS='reused'$" "${role_default_dir}/latest.env"
  grep -q "^AI_MODEL_ROUTING_CACHE_AGE_SECONDS=" "${role_default_dir}/latest.env"
  grep -q "^- Cache status: reused$" "${role_default_dir}/latest.md"
  grep -q "^- Cache age seconds: " "${role_default_dir}/latest.md"

  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
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
  grep -q "^CLAUDE_REVIEW_MODEL='sonnet'$" "${role_override_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL_SOURCE='inferred:claude-cli-alias:sonnet;role:code_review'$" "${role_override_dir}/latest.env"

  PATH="${fake_bin}:${PATH}" \
    MODEL_STUB_MODE=supported \
    AI_MODEL_DISCOVERY_DIR="${role_override_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_ROLE='architect_review'$" "${role_override_dir}/latest.env"
  grep -q "^CLAUDE_REVIEW_MODEL='opus'$" "${role_override_dir}/latest.env"

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
    AI_MODEL_DISCOVERY_DIR="${model_override_dir}" \
    ./scripts/discover-ai-models.sh >/dev/null
  grep -q "^CLAUDE_REVIEW_MODEL='opus'$" "${model_override_dir}/latest.env"
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
  printf '# run\n\n## Outputs\n\n- Claude result: custom-results/claude-review-latest.md\n' > custom-results/review-run-latest.md
  printf '# summary\n' > custom-results/review-summary-latest.md
  printf '# verdict\n' > custom-results/review-verdict-latest.md
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
  printf '# Workflow\n' > docs/WORKFLOW.md

  for script in \
    archive-omx-artifacts.sh \
    automation-doctor.sh \
    collect-review-context.sh \
    discover-ai-models.sh \
    make-review-prompts.sh \
    record-project-memory.sh \
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
  printf '# Workflow\n' > docs/WORKFLOW.md

  for script in \
    archive-omx-artifacts.sh \
    automation-doctor.sh \
    collect-review-context.sh \
    discover-ai-models.sh \
    make-review-prompts.sh \
    record-project-memory.sh \
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

  "${repo_root}/scripts/write-session-checkpoint.sh" >/dev/null
  grep -q "Session Checkpoint" .omx/state/session-checkpoint.md
  grep -q "review-run-latest.md" .omx/state/session-checkpoint.md
  grep -q "claude: usage_limit" .omx/state/session-checkpoint.md
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
  test -x "${target_dir}/scripts/record-project-memory.sh"
  test -x "${target_dir}/scripts/run-ai-reviews.sh"
  test -x "${target_dir}/scripts/write-session-checkpoint.sh"
  test -f "${target_dir}/docs/AI_MODEL_ROUTING.md"
  test -f "${target_dir}/docs/SESSION_QUALITY_PLAN.md"
  grep -q "VERIFY_TEMPLATE_UNCONFIGURED""=1" "${target_dir}/scripts/verify.sh"
  grep -q "role-first" "${target_dir}/docs/AI_MODEL_ROUTING.md"
  grep -q "Session Quality Plan" "${target_dir}/docs/SESSION_QUALITY_PLAN.md"
  grep -q "Do not present guesses" "${target_dir}/AGENTS.md"
  grep -Eq '^[.]omx/?$' "${target_dir}/.git/info/exclude"
  grep -q "프로젝트 초기설정 해줘" "${target_dir}/AGENTS.md"
  grep -q ".omx/domain-packs/에 설치된 선택 적용 표준팩" "templates/automation-base/README.md"
  grep -q ".omx/domain-packs/에 설치된 선택 적용 표준팩" "docs/NEW_PROJECT_GUIDE.md"
  grep -q "프로젝트 초기설정 해줘" "${installer_output}"
  grep -q ".omx/domain-packs/에 설치된 선택 적용 표준팩" "${installer_output}"
  test ! -e "${target_dir}/templates/domain-packs/odoo/README.md"
  test -f "${target_dir}/.omx/domain-packs/odoo/README.md"
  grep -q "Optional domain packs installed for onboarding reference" "${installer_output}"
)

echo "[verify] checking optional domain pack structure..."
test -f "templates/domain-packs/odoo/README.md"
test -f "templates/domain-packs/odoo/AGENTS.patch.md"
test -f "templates/domain-packs/odoo/WORKFLOW.md"
test -f "templates/domain-packs/odoo/verify-patterns.md"
test -f "templates/domain-packs/odoo/review-checklist.md"
grep -q "ignored onboarding reference under" "templates/domain-packs/odoo/README.md"
grep -q "ko_KR" "templates/domain-packs/odoo/README.md"
grep -q "Project-Specific Rules" "templates/domain-packs/odoo/WORKFLOW.md"
grep -q "localization baseline" "templates/domain-packs/odoo/verify-patterns.md"
grep -Fq 'Path("custom_addons").rglob("*.xml")' "templates/domain-packs/odoo/verify-patterns.md"
grep -q "도메인팩" "templates/automation-base/docs/WORKFLOW.md"

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
  git -c init.defaultBranch=main init -q "${target_dir}"
  ./tools/ai-auto-init "${target_dir}" > "${aiinit_output}"
  grep -q "프로젝트 초기설정 해줘" "${aiinit_output}"
  grep -q ".omx/domain-packs/에 설치된 선택 적용 표준팩" "${aiinit_output}"
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
  archive-omx-artifacts.sh \
  collect-review-context.sh \
  discover-ai-models.sh \
  make-review-prompts.sh \
  record-project-memory.sh \
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
