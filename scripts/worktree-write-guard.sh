#!/usr/bin/env bash
# Refuse write operations when another live AI_AUTO session owns this working tree.
set -uo pipefail

worktree_write_guard_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd -P
}

worktree_write_guard_session_id() {
  if [ -n "${AI_AUTO_SESSION_ID:-}" ]; then
    printf '%s\n' "${AI_AUTO_SESSION_ID}"
    return
  fi
  if [ -f .omx/state/session.json ]; then
    local sid
    sid="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .omx/state/session.json | head -1)"
    if [ -n "${sid}" ]; then printf '%s\n' "${sid}"; return; fi
  fi
  printf '%s@%s\n' "$$" "$(hostname 2>/dev/null || echo host)"
}

worktree_write_guard_field() {
  local file="$1" key="$2"
  sed -n "s/^${key}=//p" "${file}" 2>/dev/null | head -1
}

worktree_write_guard_pid_alive() {
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

worktree_write_guard_ttl() {
  local t="${AI_AUTO_SESSION_LOCK_TTL_SECONDS:-14400}"
  case "${t}" in ''|*[!0-9]*) t=14400 ;; esac
  printf '%s\n' "${t}"
}

worktree_write_guard_skew_grace() {
  local g="${AI_AUTO_CLOCK_SKEW_GRACE_SECONDS:-300}"
  case "${g}" in ''|*[!0-9]*) g=300 ;; esac
  printf '%s\n' "${g}"
}

worktree_write_guard_expired() {
  local at="$1" ttl="$2" ts now age grace
  [ "${ttl}" -gt 0 ] 2>/dev/null || return 1
  [ -n "${at}" ] || return 1
  ts="$(date -d "${at}" +%s 2>/dev/null)" || return 0
  [ -n "${ts}" ] || return 0
  now="$(date +%s)"
  age=$((now - ts))
  if [ "${age}" -lt 0 ]; then
    grace="$(worktree_write_guard_skew_grace)"
    [ "${age}" -lt $(( -grace )) ] && return 0
    return 1
  fi
  [ "${age}" -gt "${ttl}" ]
}

worktree_write_guard_check() {
  local op="${1:-write}" repo lock self holder_session holder_pid holder_op holder_at ttl
  repo="$(worktree_write_guard_repo_root)" || return 0
  lock="${SESSION_LOCK_FILE:-${repo}/.omx/state/session.lock}"
  [ -f "${lock}" ] || return 0
  self="$(worktree_write_guard_session_id)"
  holder_session="$(worktree_write_guard_field "${lock}" holder_session)"
  holder_pid="$(worktree_write_guard_field "${lock}" holder_pid)"
  holder_op="$(worktree_write_guard_field "${lock}" holder_op)"
  holder_at="$(worktree_write_guard_field "${lock}" acquired_at)"
  [ -n "${holder_session}" ] || return 0
  [ "${holder_session}" != "${self}" ] || return 0
  ttl="$(worktree_write_guard_ttl)"
  if worktree_write_guard_pid_alive "${holder_pid}" && ! worktree_write_guard_expired "${holder_at}" "${ttl}"; then
    printf '[write-guard] refusing %s: working tree is owned by live session %s (pid=%s op=%s). Use that session or a separate worktree.\n' \
      "${op}" "${holder_session}" "${holder_pid:-unknown}" "${holder_op:-unknown}" >&2
    return 75
  fi
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-check}" in
    check) shift || true; worktree_write_guard_check "${1:-write}" ;;
    *) echo "usage: worktree-write-guard.sh check [op]" >&2; exit 2 ;;
  esac
fi
