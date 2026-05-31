#!/usr/bin/env bash

ai_auto_docker_config_needs_guard() {
  local config_file="${HOME:-}/.docker/config.json"

  [ -z "${DOCKER_CONFIG:-}" ] || return 1
  [ -f "${config_file}" ] || return 1
  grep -Eq '"credsStore"[[:space:]]*:[[:space:]]*"desktop\.exe"' "${config_file}"
}

ai_auto_configure_docker_config() {
  local guard_dir

  if ! ai_auto_docker_config_needs_guard; then
    return 0
  fi

  guard_dir="${AI_AUTO_DOCKER_CONFIG_DIR:-/tmp/ai-lab-docker-config}"
  mkdir -p "${guard_dir}"
  export DOCKER_CONFIG="${guard_dir}"
  echo "[docker] using temporary DOCKER_CONFIG=${DOCKER_CONFIG} to avoid WSL Docker Desktop credential helper failures"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  ai_auto_configure_docker_config
  if [ -n "${DOCKER_CONFIG:-}" ]; then
    printf 'DOCKER_CONFIG=%s\n' "${DOCKER_CONFIG}"
  fi
fi
