#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${AI_MODEL_DISCOVERY_DIR:-.omx/model-routing}"
ENV_OUT="${AI_MODEL_ROUTING_ENV:-${OUT_DIR}/latest.env}"
REPORT_OUT="${AI_MODEL_ROUTING_REPORT:-${OUT_DIR}/latest.md}"
AI_MODEL_ROUTING_TTL_SECONDS="${AI_MODEL_ROUTING_TTL_SECONDS:-43200}"
AI_MODEL_DISCOVERY_REFRESH="${AI_MODEL_DISCOVERY_REFRESH:-0}"

mkdir -p "${OUT_DIR}" "$(dirname "${ENV_OUT}")" "$(dirname "${REPORT_OUT}")"

shell_quote() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

write_env() {
  local key="$1"
  local value="$2"

  printf "%s='%s'\n" "${key}" "$(shell_quote "${value}")" >> "${ENV_OUT}"
}

command_version() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "missing"
    return 0
  fi

  "${command_name}" --version 2>/dev/null | head -1 || echo "available"
}

command_help() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    return 0
  fi

  "${command_name}" --help 2>/dev/null || true
}

codex_exec_help_text() {
  if ! command -v codex >/dev/null 2>&1; then
    return 0
  fi

  codex exec --help 2>/dev/null || true
}

override_fingerprint() {
  # Keep this list in sync with all routing-affecting env vars and cheap
  # runtime facts. Any new selector must be added here to avoid stale cache.
  printf 'CLAUDE_REVIEW_ROLE=%s|GEMINI_REVIEW_ROLE=%s|CODEX_ARCHITECT_REVIEW_ROLE=%s|CODEX_TEST_REVIEW_ROLE=%s|CLAUDE_REVIEW_MODEL=%s|GEMINI_REVIEW_MODEL=%s|CODEX_ARCHITECT_REVIEW_MODEL=%s|CODEX_TEST_REVIEW_MODEL=%s|CODEX_FALLBACK_MODEL=%s|OMX_DEFAULT_FRONTIER_MODEL=%s|CLAUDE_CLI_VERSION=%s|GEMINI_CLI_VERSION=%s|CODEX_CLI_VERSION=%s|CLAUDE_HELP=%s|GEMINI_HELP=%s|CODEX_EXEC_HELP=%s' \
    "${CLAUDE_REVIEW_ROLE:-}" \
    "${GEMINI_REVIEW_ROLE:-}" \
    "${CODEX_ARCHITECT_REVIEW_ROLE:-}" \
    "${CODEX_TEST_REVIEW_ROLE:-}" \
    "${CLAUDE_REVIEW_MODEL:-}" \
    "${GEMINI_REVIEW_MODEL:-}" \
    "${CODEX_ARCHITECT_REVIEW_MODEL:-}" \
    "${CODEX_TEST_REVIEW_MODEL:-}" \
    "${CODEX_FALLBACK_MODEL:-}" \
    "${OMX_DEFAULT_FRONTIER_MODEL:-}" \
    "$(command_version claude)" \
    "$(command_version gemini)" \
    "$(command_version codex)" \
    "$(command_help claude)" \
    "$(command_help gemini)" \
    "$(codex_exec_help_text)"
}

override_fingerprint_digest() {
  if [ -x /usr/bin/cksum ]; then
    set -- $(override_fingerprint | /usr/bin/cksum)
    printf "%s-%s" "$1" "$2"
  elif command -v cksum >/dev/null 2>&1; then
    set -- $(override_fingerprint | cksum)
    printf "%s-%s" "$1" "$2"
  else
    override_fingerprint
  fi
}

update_cached_report_status() {
  local cache_age="$1"

  if [ ! -f "${REPORT_OUT}" ]; then
    return 0
  fi

  tmp_report="${REPORT_OUT}.tmp.$$"
  sed \
    -e "s/^- Cache status: .*/- Cache status: reused/" \
    -e "s/^- Cache age seconds: .*/- Cache age seconds: ${cache_age}/" \
    -e "s/^- TTL seconds: .*/- TTL seconds: ${AI_MODEL_ROUTING_TTL_SECONDS}/" \
    "${REPORT_OUT}" > "${tmp_report}"
  mv "${tmp_report}" "${REPORT_OUT}"
}

case "${AI_MODEL_ROUTING_TTL_SECONDS}" in
  ''|*[!0-9]*)
    AI_MODEL_ROUTING_TTL_SECONDS=43200
    ;;
esac

now_epoch="$(date +%s)"
current_override_fingerprint="$(override_fingerprint_digest)"

if [ "${AI_MODEL_DISCOVERY_REFRESH}" != "1" ] && [ -f "${ENV_OUT}" ] && [ -f "${REPORT_OUT}" ]; then
  cached_epoch="$(sed -n "s/^AI_MODEL_ROUTING_DISCOVERED_EPOCH='\\([0-9][0-9]*\\)'$/\\1/p" "${ENV_OUT}" | head -1)"
  cached_epoch="${cached_epoch:-0}"
  cached_override_fingerprint="$(sed -n "s/^AI_MODEL_ROUTING_OVERRIDE_FINGERPRINT='\\(.*\\)'$/\\1/p" "${ENV_OUT}" | head -1)"
  case "${cached_epoch}" in
    ''|*[!0-9]*)
      cached_epoch=0
      ;;
  esac

  cache_age=$((now_epoch - cached_epoch))
  if [ "${cached_override_fingerprint}" = "${current_override_fingerprint}" ] && [ "${cache_age}" -ge 0 ] && [ "${cache_age}" -le "${AI_MODEL_ROUTING_TTL_SECONDS}" ]; then
    tmp_env="${ENV_OUT}.tmp.$$"
    grep -v -E "^(AI_MODEL_ROUTING_CACHE_STATUS|AI_MODEL_ROUTING_CACHE_AGE_SECONDS|AI_MODEL_ROUTING_CACHE_TTL_SECONDS)=" "${ENV_OUT}" > "${tmp_env}" || true
    mv "${tmp_env}" "${ENV_OUT}"
    write_env "AI_MODEL_ROUTING_CACHE_TTL_SECONDS" "${AI_MODEL_ROUTING_TTL_SECONDS}"
    write_env "AI_MODEL_ROUTING_CACHE_STATUS" "reused"
    write_env "AI_MODEL_ROUTING_CACHE_AGE_SECONDS" "${cache_age}"
    update_cached_report_status "${cache_age}"
    echo "${ENV_OUT}"
    exit 0
  fi
fi

supports_flag() {
  local help_text="$1"
  local flag="$2"

  printf '%s\n' "${help_text}" | grep -Eq "(^|[^[:alnum:]_-])${flag}($|[^[:alnum:]_-])"
}

contains_word() {
  local text="$1"
  local word="$2"

  printf '%s\n' "${text}" | grep -qiE "(^|[^[:alnum:]_-])${word}([^[:alnum:]_-]|$)"
}

first_nonempty() {
  local value

  for value in "$@"; do
    if [ -n "${value}" ]; then
      echo "${value}"
      return 0
    fi
  done

  return 0
}

select_claude_alias_for_role() {
  local role="$1"

  case "${role}" in
    architect_review|architecture_review|risk_review|plan_review)
      if contains_word "${claude_help}" "opus"; then
        echo "opus"
      elif contains_word "${claude_help}" "sonnet"; then
        echo "sonnet"
      fi
      ;;
    code_review|implementation_review|debug_review|test_review|docs_review|alternative_review)
      if contains_word "${claude_help}" "sonnet"; then
        echo "sonnet"
      elif contains_word "${claude_help}" "opus"; then
        echo "opus"
      fi
      ;;
    *)
      if contains_word "${claude_help}" "opus"; then
        echo "opus"
      elif contains_word "${claude_help}" "sonnet"; then
        echo "sonnet"
      fi
      ;;
  esac
}

claude_help="$(command_help claude)"
gemini_help="$(command_help gemini)"
codex_exec_help=""
if command -v codex >/dev/null 2>&1; then
  codex_exec_help="$(codex_exec_help_text)"
fi

claude_supports_model=0
gemini_supports_model=0
codex_supports_model=0

if supports_flag "${claude_help}" "--model"; then
  claude_supports_model=1
fi

if supports_flag "${gemini_help}" "--model"; then
  gemini_supports_model=1
fi

if supports_flag "${codex_exec_help}" "--model"; then
  codex_supports_model=1
fi

claude_aliases=()
if contains_word "${claude_help}" "opus"; then
  claude_aliases+=("opus")
fi
if contains_word "${claude_help}" "sonnet"; then
  claude_aliases+=("sonnet")
fi

claude_review_role="${CLAUDE_REVIEW_ROLE:-architect_review}"
gemini_review_role="${GEMINI_REVIEW_ROLE:-alternative_review}"
codex_architect_role="${CODEX_ARCHITECT_REVIEW_ROLE:-architect_fallback}"
codex_test_role="${CODEX_TEST_REVIEW_ROLE:-test_alternative}"

claude_review_model="${CLAUDE_REVIEW_MODEL:-}"
claude_review_model_source="env:CLAUDE_REVIEW_MODEL"
if [ -z "${claude_review_model}" ] && [ "${claude_supports_model}" -eq 1 ]; then
  claude_role_alias="$(select_claude_alias_for_role "${claude_review_role}")"
  if [ -n "${claude_role_alias}" ]; then
    claude_review_model="${claude_role_alias}"
    claude_review_model_source="inferred:claude-cli-alias:${claude_role_alias};role:${claude_review_role}"
  else
    claude_review_model_source="default"
  fi
fi

gemini_review_model="${GEMINI_REVIEW_MODEL:-}"
gemini_review_model_source="env:GEMINI_REVIEW_MODEL"
if [ -z "${gemini_review_model}" ]; then
  gemini_review_model_source="default"
fi

codex_architect_model="$(first_nonempty \
  "${CODEX_ARCHITECT_REVIEW_MODEL:-}" \
  "${CODEX_FALLBACK_MODEL:-}" \
  "${OMX_DEFAULT_FRONTIER_MODEL:-}")"
codex_architect_model_source="default"
if [ -n "${CODEX_ARCHITECT_REVIEW_MODEL:-}" ]; then
  codex_architect_model_source="env:CODEX_ARCHITECT_REVIEW_MODEL"
elif [ -n "${CODEX_FALLBACK_MODEL:-}" ]; then
  codex_architect_model_source="env:CODEX_FALLBACK_MODEL"
elif [ -n "${OMX_DEFAULT_FRONTIER_MODEL:-}" ]; then
  codex_architect_model_source="env:OMX_DEFAULT_FRONTIER_MODEL"
fi

codex_test_model="$(first_nonempty \
  "${CODEX_TEST_REVIEW_MODEL:-}" \
  "${CODEX_FALLBACK_MODEL:-}" \
  "${OMX_DEFAULT_FRONTIER_MODEL:-}")"
codex_test_model_source="default"
if [ -n "${CODEX_TEST_REVIEW_MODEL:-}" ]; then
  codex_test_model_source="env:CODEX_TEST_REVIEW_MODEL"
elif [ -n "${CODEX_FALLBACK_MODEL:-}" ]; then
  codex_test_model_source="env:CODEX_FALLBACK_MODEL"
elif [ -n "${OMX_DEFAULT_FRONTIER_MODEL:-}" ]; then
  codex_test_model_source="env:OMX_DEFAULT_FRONTIER_MODEL"
fi

if [ "${claude_supports_model}" -ne 1 ]; then
  claude_review_model=""
  claude_review_model_source="unsupported"
fi

if [ "${gemini_supports_model}" -ne 1 ]; then
  gemini_review_model=""
  gemini_review_model_source="unsupported"
fi

if [ "${codex_supports_model}" -ne 1 ]; then
  codex_architect_model=""
  codex_architect_model_source="unsupported"
  codex_test_model=""
  codex_test_model_source="unsupported"
fi

: > "${ENV_OUT}"
discovered_at="$(date -Iseconds)"
write_env "AI_MODEL_ROUTING_DISCOVERED_AT" "${discovered_at}"
write_env "AI_MODEL_ROUTING_DISCOVERED_EPOCH" "${now_epoch}"
write_env "AI_MODEL_ROUTING_REPORT" "${REPORT_OUT}"
write_env "AI_MODEL_ROUTING_POLICY" "role-capability-runtime-surface-v1"
write_env "AI_MODEL_ROUTING_CACHE_TTL_SECONDS" "${AI_MODEL_ROUTING_TTL_SECONDS}"
write_env "AI_MODEL_ROUTING_CACHE_STATUS" "refreshed"
write_env "AI_MODEL_ROUTING_CACHE_AGE_SECONDS" "0"
write_env "AI_MODEL_ROUTING_OVERRIDE_FINGERPRINT" "${current_override_fingerprint}"
write_env "CLAUDE_REVIEW_ROLE" "${claude_review_role}"
write_env "CLAUDE_REVIEW_MODEL" "${claude_review_model}"
write_env "CLAUDE_REVIEW_MODEL_SOURCE" "${claude_review_model_source}"
write_env "GEMINI_REVIEW_ROLE" "${gemini_review_role}"
write_env "GEMINI_REVIEW_MODEL" "${gemini_review_model}"
write_env "GEMINI_REVIEW_MODEL_SOURCE" "${gemini_review_model_source}"
write_env "CODEX_ARCHITECT_REVIEW_ROLE" "${codex_architect_role}"
write_env "CODEX_ARCHITECT_REVIEW_MODEL" "${codex_architect_model}"
write_env "CODEX_ARCHITECT_REVIEW_MODEL_SOURCE" "${codex_architect_model_source}"
write_env "CODEX_TEST_REVIEW_ROLE" "${codex_test_role}"
write_env "CODEX_TEST_REVIEW_MODEL" "${codex_test_model}"
write_env "CODEX_TEST_REVIEW_MODEL_SOURCE" "${codex_test_model_source}"

cat > "${REPORT_OUT}" <<REPORT
# AI Model Routing Inventory

Generated at: ${discovered_at}

## Cache Policy

- Cache status: refreshed
- Cache age seconds: 0
- Discovery epoch: ${now_epoch}
- TTL seconds: ${AI_MODEL_ROUTING_TTL_SECONDS}
- Refresh with: AI_MODEL_DISCOVERY_REFRESH=1 ./scripts/review-gate.sh
- Disable discovery with: AI_MODEL_DISCOVERY=0 ./scripts/review-gate.sh

## Discovery Policy

- Prefer explicit environment overrides.
- Route by role and required capability first; resolve that role onto the current runtime surface second.
- Prefer provider aliases that the installed CLI advertises, such as Claude's latest-model aliases.
- Do not hardcode dated provider model names in workflow scripts.
- Fall back to the provider CLI default when no safe model list or alias is available.
- Treat official provider docs as reference material, not proof that the local CLI/account can use a model.
- If a selection is inferred from help text or config, report it as inferred instead of presenting it as a verified provider fact.

## Runtime-Surface Precedence

1. Explicit environment override for this project/run.
2. Current local CLI/runtime capability and advertised aliases.
3. OMX/Codex model contract from the active session environment.
4. Provider default with no model flag.

## Role Profiles

| Role | Capability Target | Preferred Runtime Mapping |
|---|---|---|
| architect_review | deep reasoning, long-context risk review, maintainability judgment | Claude opus alias, then sonnet; Codex architect fallback |
| alternative_review | independent second opinion, missed cases, simpler alternatives | Gemini provider default/pro-class when explicitly configured; Codex test fallback |
| implementation | repo-local code edits and test fixes | Codex executor/current runtime default |
| debug | logs, reproduction, root cause, regression isolation | Codex debugger/current runtime default |
| fast_scan | file/symbol lookup and lightweight synthesis | Codex explore/spark lane |
| docs | documentation and handoff clarity | Codex writer or provider default |

## CLI Capabilities

| Provider | Version | Supports --model | Discovered aliases |
|---|---|---:|---|
| Claude | $(command_version claude) | ${claude_supports_model} | ${claude_aliases[*]:-none} |
| Gemini | $(command_version gemini) | ${gemini_supports_model} | none exposed by help |
| Codex exec | $(command_version codex) | ${codex_supports_model} | use env/OMX model contract |

## Selected Review Models

| Lane | Role | Model | Source |
|---|---|---|---|
| Claude review | ${claude_review_role} | ${claude_review_model:-provider-default} | ${claude_review_model_source} |
| Gemini review | ${gemini_review_role} | ${gemini_review_model:-provider-default} | ${gemini_review_model_source} |
| Codex architect fallback | ${codex_architect_role} | ${codex_architect_model:-provider-default} | ${codex_architect_model_source} |
| Codex test fallback | ${codex_test_role} | ${codex_test_model:-provider-default} | ${codex_test_model_source} |

## Override Variables

- CLAUDE_REVIEW_ROLE
- GEMINI_REVIEW_ROLE
- CODEX_ARCHITECT_REVIEW_ROLE
- CODEX_TEST_REVIEW_ROLE
- CLAUDE_REVIEW_MODEL
- GEMINI_REVIEW_MODEL
- CODEX_ARCHITECT_REVIEW_MODEL
- CODEX_TEST_REVIEW_MODEL
- CODEX_FALLBACK_MODEL
- OMX_DEFAULT_FRONTIER_MODEL
REPORT

echo "${ENV_OUT}"
