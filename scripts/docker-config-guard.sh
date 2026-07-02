#!/usr/bin/env bash

ai_auto_docker_config_needs_guard() {
  local config_file="${HOME:-}/.docker/config.json"

  [ -z "${DOCKER_CONFIG:-}" ] || return 1
  [ -f "${config_file}" ] || return 1
  grep -Eq '"credsStore"[[:space:]]*:[[:space:]]*"desktop\.exe"' "${config_file}"
}

# R23: a guard dir must be a REAL directory (not a symlink), owned by us, and not group/world
# writable — otherwise a local co-tenant who pre-plants a symlink or a world-writable dir at a
# predictable path controls the DOCKER_CONFIG `docker compose` reads (credsStore/auths exec ->
# RCE in the built container). Refuse anything that fails these checks.
ai_auto_docker_config_dir_safe() {
  local d="$1" meta owner perms
  [ ! -L "${d}" ] || return 1          # symlink -> unsafe
  [ -d "${d}" ] || return 1            # must be a real directory
  meta="$(stat -c '%u %a' "${d}" 2>/dev/null)" || return 1
  owner="${meta%% *}"; perms="${meta##* }"
  [ "${owner}" = "$(id -u)" ] || return 1                     # owned by us
  case "${perms: -1}" in 2|3|6|7) return 1;; esac             # world-writable
  case "${perms: -2:1}" in 2|3|6|7) return 1;; esac           # group-writable
  return 0
}

ai_auto_configure_docker_config() {
  local guard_dir

  if ! ai_auto_docker_config_needs_guard; then
    return 0
  fi

  # R23: default to a per-uid UNPREDICTABLE location (never a fixed world-scope /tmp path).
  # Prefer $XDG_RUNTIME_DIR (already a per-uid 0700 dir a co-tenant cannot write into); else a
  # fresh mktemp -d. An explicit AI_AUTO_DOCKER_CONFIG_DIR override is honored but still validated.
  if [ -n "${AI_AUTO_DOCKER_CONFIG_DIR:-}" ]; then
    guard_dir="${AI_AUTO_DOCKER_CONFIG_DIR}"
  elif [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    guard_dir="${XDG_RUNTIME_DIR}/ai-lab-docker-config"
  else
    guard_dir="$(mktemp -d "${TMPDIR:-/tmp}/ai-lab-docker-config.$(id -u).XXXXXX" 2>/dev/null)" \
      || { echo "[docker] could not create a private DOCKER_CONFIG dir; leaving DOCKER_CONFIG unset" >&2; return 0; }
  fi

  if [ -L "${guard_dir}" ]; then
    echo "[docker] REFUSING DOCKER_CONFIG dir ${guard_dir}: it is a symlink — leaving DOCKER_CONFIG unset" >&2
    return 0
  fi
  [ -e "${guard_dir}" ] || (umask 077; mkdir -p "${guard_dir}") 2>/dev/null || true
  if ! ai_auto_docker_config_dir_safe "${guard_dir}"; then
    echo "[docker] REFUSING DOCKER_CONFIG dir ${guard_dir}: not a self-owned private directory — leaving DOCKER_CONFIG unset" >&2
    return 0
  fi
  chmod 0700 "${guard_dir}" 2>/dev/null || true
  export DOCKER_CONFIG="${guard_dir}"
  echo "[docker] using temporary DOCKER_CONFIG=${DOCKER_CONFIG} to avoid WSL Docker Desktop credential helper failures"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  ai_auto_configure_docker_config
  if [ -n "${DOCKER_CONFIG:-}" ]; then
    printf 'DOCKER_CONFIG=%s\n' "${DOCKER_CONFIG}"
  fi
fi
