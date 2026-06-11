#!/usr/bin/env bash
# Per-working-tree session guard. SOURCED by review-gate.sh / verify.sh (not executed
# directly). The lock lives at .omx/state/session.lock — gitignored and per-working-tree,
# so two SEPARATE git worktrees never collide (each has its own .omx), but two terminals
# sharing ONE working tree are warned and soft-blocked instead of silently racing the
# review/validation state. Prefer one worktree per terminal:  aiwt <name>.
#
# Provides: session_lock_acquire <op>  (0 = proceed, 1 = blocked)
#           session_lock_release
# Override: AI_AUTO_ALLOW_SHARED_TREE=1 proceeds on a shared tree (state races possible).

SESSION_LOCK_FILE="${SESSION_LOCK_FILE:-.omx/state/session.lock}"
SESSION_LOCK_HELD=0

# A stable id for THIS logical session, shared with child processes (review-gate -> the
# verify.sh it spawns) via the exported AI_AUTO_SESSION_ID, so nesting is re-entrant and
# never self-blocks, while a genuinely separate concurrent run gets a different id.
_session_lock_compute_id() {
  if [ -f .omx/state/session.json ]; then
    local sid
    sid="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .omx/state/session.json | head -1)"
    if [ -n "$sid" ]; then printf '%s' "$sid"; return; fi
  fi
  printf '%s@%s' "$$" "$(hostname 2>/dev/null || echo host)"
}

_session_lock_field() { sed -n "s/^$1=//p" "$SESSION_LOCK_FILE" 2>/dev/null | head -1; }
_session_lock_pid_alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }

session_lock_acquire() {
  local op="${1:-session}" self tmp held_pid held_sess held_op
  : "${AI_AUTO_SESSION_ID:=$(_session_lock_compute_id)}"
  export AI_AUTO_SESSION_ID
  self="$AI_AUTO_SESSION_ID"
  mkdir -p "$(dirname "$SESSION_LOCK_FILE")"

  if [ -f "$SESSION_LOCK_FILE" ]; then
    held_sess="$(_session_lock_field holder_session)"
    held_pid="$(_session_lock_field holder_pid)"
    held_op="$(_session_lock_field holder_op)"
    if [ "$held_sess" = "$self" ]; then
      SESSION_LOCK_HELD=0          # our own session (e.g. review-gate -> nested verify.sh)
      return 0
    fi
    if _session_lock_pid_alive "$held_pid"; then
      printf '%s\n' "[lock] WARNING: this working tree is already in use by a live session (pid=${held_pid} op=${held_op})." >&2
      printf '%s\n' "[lock]   Prefer a separate worktree per terminal:  aiwt <name>" >&2
      if [ "${AI_AUTO_ALLOW_SHARED_TREE:-0}" != "1" ]; then
        printf '%s\n' "[lock]   Blocked. Set AI_AUTO_ALLOW_SHARED_TREE=1 to share this tree anyway (state races possible)." >&2
        return 1
      fi
      printf '%s\n' "[lock]   AI_AUTO_ALLOW_SHARED_TREE=1: proceeding on a SHARED tree." >&2
      SESSION_LOCK_HELD=0          # do not disturb the live holder's lock
      return 0
    fi
    printf '%s\n' "[lock] reclaiming stale lock (holder pid=${held_pid} no longer alive)" >&2
  fi

  tmp="$(mktemp "$(dirname "$SESSION_LOCK_FILE")/.session.lock.XXXXXX")" || return 0
  {
    printf 'holder_pid=%s\n' "$$"
    printf 'holder_session=%s\n' "$self"
    printf 'holder_op=%s\n' "$op"
    printf 'acquired_at=%s\n' "$(date -Iseconds)"
  } > "$tmp"
  mv -f "$tmp" "$SESSION_LOCK_FILE"
  SESSION_LOCK_HELD=1
  return 0
}

# Release only a lock WE created and still hold (never delete a live holder's lock).
session_lock_release() {
  [ "${SESSION_LOCK_HELD:-0}" = "1" ] || return 0
  if [ "$(_session_lock_field holder_session)" = "${AI_AUTO_SESSION_ID:-}" ]; then
    rm -f "$SESSION_LOCK_FILE"
  fi
  SESSION_LOCK_HELD=0
}
