#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/ai-runtime-adapter.sh capability <runtime> <capability>
  ./scripts/ai-runtime-adapter.sh run-readonly --runtime <runtime> --capability <capability> --prompt-file <path> --output <path> [--timeout <seconds>] [--kill-after <seconds>] [--cd <path>] [--model <model>]

Provide a narrow AI runtime compatibility surface for AI_AUTO automation.

Runtimes:
  codex, claude, agy, gemini

Capabilities:
  review, analyze, plan, edit_files, commit

Only read-only-intent capabilities are executable through this adapter. Codex
uses a read-only sandbox. Claude and agy/Gemini use provider no-edit flags when
available, but those CLIs are not treated as a filesystem sandbox boundary.
Write-capable automation remains intentionally outside this script until a
separate execution contract and review gate are approved.
USAGE
}

runtime_command() {
  case "$1" in
    codex)
      printf '%s\n' "${RUNTIME_ADAPTER_CODEX_COMMAND:-codex}"
      ;;
    claude)
      printf '%s\n' "${RUNTIME_ADAPTER_CLAUDE_COMMAND:-claude}"
      ;;
    agy|gemini)
      printf '%s\n' "${RUNTIME_ADAPTER_AGY_COMMAND:-agy}"
      ;;
    *)
      return 1
      ;;
  esac
}

runtime_adapter() {
  case "$1" in
    codex|claude|agy|gemini)
      printf '%s\n' "$1"
      ;;
    *)
      return 1
      ;;
  esac
}

capability_mode() {
  local runtime="$1"
  local capability="$2"

  case "${capability}" in
    review|analyze|plan)
      case "${runtime}" in
    codex|claude|agy|gemini)
      case "${runtime}" in
        codex)
          printf 'readonly_sandbox\n'
          ;;
        *)
          printf 'logical_readonly\n'
          ;;
      esac
      return 0
      ;;
      esac
      ;;
    edit_files)
      case "${runtime}" in
        codex)
          return 1
          ;;
      esac
      ;;
    commit)
      case "${runtime}" in
        codex)
          return 1
          ;;
      esac
      ;;
  esac

  return 1
}

command_help_text() {
  local command_name="$1"

  run_with_timeout "${RUNTIME_ADAPTER_HELP_TIMEOUT_SECONDS:-10}" "${RUNTIME_ADAPTER_HELP_KILL_AFTER_SECONDS:-2}" "${command_name}" --help 2>&1 || true
}

codex_exec_help_text() {
  local command_name="$1"

  run_with_timeout "${RUNTIME_ADAPTER_HELP_TIMEOUT_SECONDS:-10}" "${RUNTIME_ADAPTER_HELP_KILL_AFTER_SECONDS:-2}" "${command_name}" exec --help 2>&1 || true
}

help_supports_flag() {
  local help_text="$1"
  local flag="$2"

  printf '%s\n' "${help_text}" | grep -Eq "(^|[^[:alnum:]_-])${flag}($|[^[:alnum:]_-])"
}

print_capability() {
  local runtime="$1"
  local capability="$2"
  local adapter mode command_name

  if ! adapter="$(runtime_adapter "${runtime}")"; then
    echo "runtime: ${runtime}"
    echo "capability: ${capability}"
    echo "supported: no"
    echo "reason: unknown_runtime"
    return 1
  fi

  command_name="$(runtime_command "${runtime}")"
  echo "runtime: ${runtime}"
  echo "adapter: ${adapter}"
  echo "command: ${command_name}"
  echo "capability: ${capability}"

  if mode="$(capability_mode "${runtime}" "${capability}")"; then
    echo "supported: yes"
    echo "execution_mode: ${mode}"
    return 0
  fi

  echo "supported: no"
  echo "reason: unsupported_capability"
  return 1
}

require_file() {
  local path="$1"

  if [ ! -f "${path}" ]; then
    echo "missing file: ${path}"
    exit 2
  fi
}

absolute_file_path() {
  local path="$1"
  local dir base

  dir="$(dirname "${path}")"
  base="$(basename "${path}")"
  printf '%s/%s\n' "$(cd "${dir}" && pwd -P)" "${base}"
}

absolute_dir_path() {
  local path="$1"

  cd "${path}" && pwd -P
}

require_parent_dir() {
  local path="$1"
  local dir

  dir="$(dirname "${path}")"
  if [ ! -d "${dir}" ]; then
    mkdir -p "${dir}"
  fi
}

run_with_timeout() {
  local timeout_seconds="$1"
  local kill_after_seconds="$2"
  shift 2

  if ! command -v timeout >/dev/null 2>&1; then
    echo "runtime_unavailable: timeout command not found"
    return 127
  fi

  timeout -k "${kill_after_seconds}" "${timeout_seconds}" "$@"
}

run_readonly_codex() {
  local command_name="$1"
  local prompt_file="$2"
  local output_file="$3"
  local timeout_seconds="$4"
  local kill_after_seconds="$5"
  local work_dir="$6"
  local model="$7"
  local help_text
  local codex_args=(exec)

  if [ -n "${model}" ]; then
    help_text="$(codex_exec_help_text "${command_name}")"
    if help_supports_flag "${help_text}" "--model"; then
      codex_args+=(--model "${model}")
    else
      echo "adapter_note: codex model ignored because codex exec does not advertise --model"
    fi
  fi

  codex_args+=(--cd "${work_dir}" --sandbox read-only --ephemeral -o "${output_file}" -)
  run_with_timeout "${timeout_seconds}" "${kill_after_seconds}" "${command_name}" "${codex_args[@]}" < "${prompt_file}"
}

run_readonly_claude() {
  local command_name="$1"
  local prompt_file="$2"
  local output_file="$3"
  local timeout_seconds="$4"
  local kill_after_seconds="$5"
  local model="$6"
  local help_text
  local claude_args=()

  help_text="$(command_help_text "${command_name}")"
  if ! help_supports_flag "${help_text}" "--print"; then
    echo "runtime_unavailable: runtime=claude reason=missing_noninteractive_prompt_mode"
    return 4
  fi

  claude_args=(--print)
  if help_supports_flag "${help_text}" "--no-session-persistence"; then
    claude_args+=(--no-session-persistence)
  fi
  if help_supports_flag "${help_text}" "--permission-mode"; then
    claude_args+=(--permission-mode plan)
  fi
  if [ -n "${model}" ] && help_supports_flag "${help_text}" "--model"; then
    claude_args+=(--model "${model}")
  fi
  run_with_timeout "${timeout_seconds}" "${kill_after_seconds}" "${command_name}" "${claude_args[@]}" < "${prompt_file}" > "${output_file}"
}

run_readonly_agy() {
  local command_name="$1"
  local prompt_file="$2"
  local output_file="$3"
  local timeout_seconds="$4"
  local kill_after_seconds="$5"
  local model="$6"
  local help_text prompt_text prompt_bytes
  local prompt_arg_max_bytes="${RUNTIME_ADAPTER_PROMPT_ARG_MAX_BYTES:-100000}"

  help_text="$(command_help_text "${command_name}")"
  prompt_bytes="$(wc -c < "${prompt_file}")"
  if help_supports_flag "${help_text}" "--prompt-file"; then
    local agy_args=(--prompt-file "${prompt_file}")
    if help_supports_flag "${help_text}" "--sandbox"; then
      agy_args+=(--sandbox)
    fi
    if help_supports_flag "${help_text}" "--approval-mode"; then
      agy_args+=(--approval-mode plan)
    fi
    if help_supports_flag "${help_text}" "--skip-trust"; then
      agy_args+=(--skip-trust)
    fi
    if help_supports_flag "${help_text}" "--output-format"; then
      agy_args+=(--output-format text)
    fi
    if help_supports_flag "${help_text}" "--print-timeout"; then
      agy_args+=(--print-timeout "${timeout_seconds}s")
    fi
    if [ -n "${model}" ] && help_supports_flag "${help_text}" "--model"; then
      agy_args+=(--model "${model}")
    fi
    run_with_timeout "${timeout_seconds}" "${kill_after_seconds}" "${command_name}" "${agy_args[@]}" > "${output_file}"
  elif help_supports_flag "${help_text}" "--prompt"; then
    if [ "${prompt_bytes}" -gt "${prompt_arg_max_bytes}" ]; then
      prompt_text="Review the Markdown prompt provided on stdin."
    else
      prompt_text="$(sed -n '1,$p' "${prompt_file}")"
    fi
    local agy_args=(--prompt "${prompt_text}")
    if help_supports_flag "${help_text}" "--sandbox"; then
      agy_args+=(--sandbox)
    fi
    if help_supports_flag "${help_text}" "--approval-mode"; then
      agy_args+=(--approval-mode plan)
    fi
    if help_supports_flag "${help_text}" "--skip-trust"; then
      agy_args+=(--skip-trust)
    fi
    if help_supports_flag "${help_text}" "--output-format"; then
      agy_args+=(--output-format text)
    fi
    if help_supports_flag "${help_text}" "--print-timeout"; then
      agy_args+=(--print-timeout "${timeout_seconds}s")
    fi
    if [ -n "${model}" ] && help_supports_flag "${help_text}" "--model"; then
      agy_args+=(--model "${model}")
    fi
    if [ "${prompt_bytes}" -gt "${prompt_arg_max_bytes}" ]; then
      run_with_timeout "${timeout_seconds}" "${kill_after_seconds}" "${command_name}" "${agy_args[@]}" < "${prompt_file}" > "${output_file}"
    else
      run_with_timeout "${timeout_seconds}" "${kill_after_seconds}" "${command_name}" "${agy_args[@]}" > "${output_file}"
    fi
  else
    echo "runtime_unavailable: runtime=${command_name} reason=missing_noninteractive_prompt_mode"
    return 4
  fi
}

run_readonly() {
  local runtime=""
  local capability=""
  local prompt_file=""
  local output_file=""
  local timeout_seconds="${RUNTIME_ADAPTER_TIMEOUT_SECONDS:-180}"
  local kill_after_seconds="${RUNTIME_ADAPTER_TIMEOUT_KILL_AFTER_SECONDS:-${REVIEW_TIMEOUT_KILL_AFTER_SECONDS:-5}}"
  local work_dir="$(pwd)"
  local model=""
  local mode command_name

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --runtime)
        runtime="${2:-}"
        shift 2
        ;;
      --capability)
        capability="${2:-}"
        shift 2
        ;;
      --prompt-file)
        prompt_file="${2:-}"
        shift 2
        ;;
      --output)
        output_file="${2:-}"
        shift 2
        ;;
      --timeout)
        timeout_seconds="${2:-}"
        shift 2
        ;;
      --kill-after)
        kill_after_seconds="${2:-}"
        shift 2
        ;;
      --cd)
        work_dir="${2:-}"
        shift 2
        ;;
      --model)
        model="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1"
        exit 2
        ;;
    esac
  done

  if [ -z "${runtime}" ] || [ -z "${capability}" ] || [ -z "${prompt_file}" ] || [ -z "${output_file}" ]; then
    usage
    exit 2
  fi

  if ! mode="$(capability_mode "${runtime}" "${capability}")"; then
    echo "capability_refused: runtime=${runtime} capability=${capability} reason=unsupported_capability"
    exit 3
  fi

  case "${mode}" in
    readonly_sandbox|logical_readonly)
      ;;
    *)
    echo "capability_refused: runtime=${runtime} capability=${capability} reason=not_readonly mode=${mode}"
    exit 3
      ;;
  esac

  require_file "${prompt_file}"
  prompt_file="$(absolute_file_path "${prompt_file}")"
  require_parent_dir "${output_file}"
  output_file="$(absolute_file_path "${output_file}")"
  if [ ! -d "${work_dir}" ]; then
    echo "runtime_unavailable: runtime=${runtime} reason=missing_work_dir work_dir=${work_dir}"
    exit 4
  fi
  work_dir="$(absolute_dir_path "${work_dir}")"
  command_name="$(runtime_command "${runtime}")"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "runtime_unavailable: runtime=${runtime} command=${command_name}"
    exit 4
  fi

  case "${runtime}" in
    codex)
      run_readonly_codex "${command_name}" "${prompt_file}" "${output_file}" "${timeout_seconds}" "${kill_after_seconds}" "${work_dir}" "${model}"
      ;;
    claude)
      (cd "${work_dir}" && run_readonly_claude "${command_name}" "${prompt_file}" "${output_file}" "${timeout_seconds}" "${kill_after_seconds}" "${model}")
      ;;
    agy|gemini)
      (cd "${work_dir}" && run_readonly_agy "${command_name}" "${prompt_file}" "${output_file}" "${timeout_seconds}" "${kill_after_seconds}" "${model}")
      ;;
    *)
      echo "runtime_unavailable: runtime=${runtime}"
      exit 4
      ;;
  esac

  echo "adapter_status: ok"
  echo "artifact_path: ${output_file}"
  echo "execution_mode: ${mode}"
}

main() {
  local command="${1:-}"
  shift || true

  case "${command}" in
    capability)
      if [ "$#" -ne 2 ]; then
        usage
        exit 2
      fi
      print_capability "$1" "$2"
      ;;
    run-readonly)
      run_readonly "$@"
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      echo "Unknown command: ${command}"
      usage
      exit 2
      ;;
  esac
}

main "$@"
