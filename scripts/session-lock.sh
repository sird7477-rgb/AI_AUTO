#!/usr/bin/env bash
# Per-working-tree session guard. SOURCED by review-gate.sh / verify.sh (not executed
# directly). The lock lives at .omx/state/session.lock — gitignored and per-working-tree,
# so two SEPARATE git worktrees never collide (each has its own .omx), but two terminals
# sharing ONE working tree are warned and soft-blocked instead of silently racing the
# review/validation state. Prefer one worktree per terminal:  aiwt <name>.
#
# Provides: session_lock_acquire <op>  (0 = proceed; 75 = a different LIVE session holds
#             this tree — EX_TEMPFAIL/retryable contention, NOT a verification failure)
#           session_lock_release
# Override: AI_AUTO_ALLOW_SHARED_TREE=1 proceeds on a shared tree (state races possible).
# 75 is emitted ONLY from the live-foreign-holder branch below; stale-reclaim and our own
# re-entrant session both return 0, so callers can treat 75 as "deferred, re-run / use
# aiwt" without ever masking a real failure (which never produces 75 here).

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

# TTL ceiling (seconds): a lock older than this is STALE regardless of PID liveness, so a
# recycled/forged holder_pid (e.g. PID reuse, or holder_pid=1 which is always alive) can no
# longer wedge the tree forever. 0 disables expiry. Default 4h >> any real gate run.
_session_lock_ttl() {
  local t="${AI_AUTO_SESSION_LOCK_TTL_SECONDS:-14400}"
  case "$t" in ''|*[!0-9]*) t=14400 ;; esac
  printf '%s' "$t"
}

# Expired iff acquired_at is present AND (its age exceeds the TTL, OR its age is implausible:
# NEGATIVE / future-dated, OR present-but-unparseable) — all with TTL>0. A future acquired_at
# (clock roll-back, or a forged/planted lock) yields a NEGATIVE age that can never exceed the
# TTL, so without this clamp a future-dated always-alive holder_pid (e.g. planted holder_pid=1)
# would wedge the tree FOREVER, defeating the very TTL added to close that wedge. Clamping an
# implausible age to STALE routes it through the race-safe reclaim instead. A MISSING/empty
# acquired_at is still NOT expired (falls back to PID-liveness), so pre-TTL locks and a genuine
# fresh legit lock (whose acquired_at ≈ now, age ≈ 0) are never reclaimed instantly.
_session_lock_expired() {
  local at="$1" ttl="$2" ts now age
  [ "$ttl" -gt 0 ] 2>/dev/null || return 1
  [ -n "$at" ] || return 1
  ts="$(date -d "$at" +%s 2>/dev/null)" || return 0   # present but unparseable -> STALE
  [ -n "$ts" ] || return 0                             # ditto
  now="$(date +%s)"
  age=$((now - ts))
  [ "$age" -lt 0 ] && return 0                         # future-dated (clock skew/forged) -> STALE
  [ "$age" -gt "$ttl" ]
}

# LOW: sweep obviously-orphaned reclaim temps left by a SIGKILL between mktemp and ln. Only
# removes .session.lock.XXXXXX temps older than 60min (never the live lock itself).
_session_lock_sweep_orphans() {
  local dir; dir="$(dirname "$SESSION_LOCK_FILE")"
  find "$dir" -maxdepth 1 -type f -name '.session.lock.??????' -mmin +60 -delete 2>/dev/null || true
}

# Build a fully-formed lock temp and atomically install it via `ln` (O_EXCL create-or-fail).
# Sets SESSION_LOCK_HELD=1 and returns 0 on win. Returns 1 if we LOST the create race (the
# lock now exists, published by someone else) so the caller loops to inspect it. Returns 2 on
# mktemp failure (caller fails open). Every path removes its own temp; a temp orphaned by a
# SIGKILL between mktemp and ln (uncatchable, so no trap can help) is reaped by the orphan
# sweep on a later acquire.
_session_lock_publish() {
  local op="$1" self="$2" dir tmp
  dir="$(dirname "$SESSION_LOCK_FILE")"
  tmp="$(mktemp "$dir/.session.lock.XXXXXX")" || return 2
  {
    printf 'holder_pid=%s\n' "$$"
    printf 'holder_session=%s\n' "$self"
    printf 'holder_op=%s\n' "$op"
    printf 'acquired_at=%s\n' "$(date -Iseconds)"
  } > "$tmp"
  if ln "$tmp" "$SESSION_LOCK_FILE" 2>/dev/null; then
    rm -f "$tmp"; SESSION_LOCK_HELD=1; return 0
  fi
  if [ ! -e "$SESSION_LOCK_FILE" ]; then       # hardlinks unsupported -> non-atomic fallback
    mv -f "$tmp" "$SESSION_LOCK_FILE"; SESSION_LOCK_HELD=1; return 0
  fi
  rm -f "$tmp"; return 1                        # lost the race -> caller loops to inspect
}

# Race-safe reclaim of a STALE (dead-PID or TTL-expired) lock. The critical section is
# serialized by an flock on a stable sidecar, so N racers that all saw the SAME stale lock
# can never all `rm`+`ln` into each other's gap (the old bug: 100+/250 double-wins). Under the
# flock we RE-VERIFY the lock is still the stale one before dropping it: if a live session
# already reclaimed it we back off (return 1) instead of stealing a now-LIVE lock.
# Returns 0 if WE now hold it (SESSION_LOCK_HELD set by publish, or 0 if it became ours),
# 1 if someone else won (caller loops to inspect and resolve to 75), 2 on infra failure.
_session_lock_reclaim() {
  local op="$1" self="$2" ttl="$3" dir sidecar rc fd
  dir="$(dirname "$SESSION_LOCK_FILE")"
  sidecar="$dir/.session.lock.reclaim"
  exec {fd}>>"$sidecar" 2>/dev/null || return 2
  if ! flock -w 10 "$fd"; then exec {fd}>&-; return 2; fi
  if [ -f "$SESSION_LOCK_FILE" ]; then
    local nsess npid nat
    nsess="$(_session_lock_field holder_session)"
    npid="$(_session_lock_field holder_pid)"
    nat="$(_session_lock_field acquired_at)"
    if [ "$nsess" = "$self" ]; then SESSION_LOCK_HELD=0; flock -u "$fd"; exec {fd}>&-; return 0; fi
    if _session_lock_pid_alive "$npid" && ! _session_lock_expired "$nat" "$ttl"; then
      flock -u "$fd"; exec {fd}>&-; return 1   # a live session reclaimed first; not ours to steal
    fi
    rm -f "$SESSION_LOCK_FILE"                  # confirmed still stale -> drop and republish
  fi
  _session_lock_publish "$op" "$self"; rc=$?
  flock -u "$fd"; exec {fd}>&-
  return "$rc"
}

session_lock_acquire() {
  local op="${1:-session}" self held_pid held_sess held_op held_at ttl tries=0 prc
  : "${AI_AUTO_SESSION_ID:=$(_session_lock_compute_id)}"
  export AI_AUTO_SESSION_ID
  self="$AI_AUTO_SESSION_ID"
  mkdir -p "$(dirname "$SESSION_LOCK_FILE")"
  ttl="$(_session_lock_ttl)"
  _session_lock_sweep_orphans

  # Acquire is atomic on the FRESH path: `_session_lock_publish` installs a fully-formed lock
  # with `ln` (O_EXCL create-or-fail), so exactly one simultaneous racer wins and the loser's
  # `ln` fails -> loops -> inspects (own / live-foreign->75 / stale). A STALE lock (dead PID or
  # TTL-expired) is reclaimed through the flock-serialized `_session_lock_reclaim`, so N racers
  # reclaiming the SAME stale lock can never all `rm`+`ln` into each other's gap (the old blind
  # rm+ln double-win). Bounded loop: each iteration returns or resolves to a live holder; the
  # counter is a deadlock backstop.
  while : ; do
    tries=$((tries + 1))
    if [ -f "$SESSION_LOCK_FILE" ]; then
      held_sess="$(_session_lock_field holder_session)"
      held_pid="$(_session_lock_field holder_pid)"
      held_op="$(_session_lock_field holder_op)"
      held_at="$(_session_lock_field acquired_at)"
      if [ "$held_sess" = "$self" ]; then
        SESSION_LOCK_HELD=0          # our own session (e.g. review-gate -> nested verify.sh)
        return 0
      fi
      if [ -z "$held_pid" ] && [ "$tries" -lt 50 ]; then
        continue                     # lock present but holder_pid unreadable: retry, do not steal
      fi
      # LIVE foreign holder still WITHIN its TTL -> retryable contention (75). A live-but-EXPIRED
      # holder (recycled/forged PID that outlived the TTL) is treated as stale and reclaimed below,
      # so it can never wedge the tree forever.
      if _session_lock_pid_alive "$held_pid" && ! _session_lock_expired "$held_at" "$ttl"; then
        printf '%s\n' "[lock] WARNING: this working tree is already in use by a live session (pid=${held_pid} op=${held_op})." >&2
        printf '%s\n' "[lock]   Prefer a separate worktree per terminal:  aiwt <name>" >&2
        if [ "${AI_AUTO_ALLOW_SHARED_TREE:-0}" != "1" ]; then
          printf '%s\n' "[lock]   Deferred (retryable): re-run after that session finishes, or use a separate worktree (aiwt). Set AI_AUTO_ALLOW_SHARED_TREE=1 to share anyway (state races possible)." >&2
          return 75   # EX_TEMPFAIL: live-foreign-holder contention, NOT a failure
        fi
        printf '%s\n' "[lock]   AI_AUTO_ALLOW_SHARED_TREE=1: proceeding on a SHARED tree." >&2
        SESSION_LOCK_HELD=0          # do not disturb the live holder's lock
        return 0
      fi
      # Stale holder (dead PID or TTL-expired) -> race-safe reclaim under an flock.
      printf '%s\n' "[lock] reclaiming stale lock (holder pid=${held_pid}, dead or past TTL)" >&2
      _session_lock_reclaim "$op" "$self" "$ttl"; prc=$?
      [ "$prc" -eq 0 ] && return 0    # we now hold it (or it became ours)
      [ "$prc" -eq 2 ] && return 0    # infra failure (no flock) -> fail open, proceed
      continue                        # someone live won it -> loop to inspect (resolves to 75)
    fi

    # Fresh path: no lock present -> atomic publish.
    _session_lock_publish "$op" "$self"; prc=$?
    [ "$prc" -eq 0 ] && return 0      # we won
    [ "$prc" -eq 2 ] && return 0      # mktemp failure -> fail open, proceed
    # prc=1: lost the create race, a racer just published -> loop to inspect it.
  done
}

# Release only a lock WE created and still hold (never delete a live holder's lock).
session_lock_release() {
  [ "${SESSION_LOCK_HELD:-0}" = "1" ] || return 0
  if [ "$(_session_lock_field holder_session)" = "${AI_AUTO_SESSION_ID:-}" ]; then
    rm -f "$SESSION_LOCK_FILE"
  fi
  SESSION_LOCK_HELD=0
}
