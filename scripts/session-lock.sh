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

# A process-unique id for THIS logical session, shared with child processes
# (review-gate -> the verify.sh it spawns) via the exported AI_AUTO_SESSION_ID,
# so nesting is re-entrant and never self-blocks, while a genuinely separate
# concurrent run gets a different id.
_session_lock_compute_id() {
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

# Backward-clock-step tolerance (seconds). A LIVE holder's acquired_at is wall-clock, so an
# NTP/WSL/VM backstep makes its age NEGATIVE — indistinguishable, by sign alone, from a forged
# future lock. Treat a small negative age (-GRACE <= age < 0) as a plausible skew of a FRESH
# lock (respect it); only age < -GRACE is implausibly-future (forged/planted) -> stale.
_session_lock_skew_grace() {
  local g="${AI_AUTO_CLOCK_SKEW_GRACE_SECONDS:-300}"
  case "$g" in ''|*[!0-9]*) g=300 ;; esac
  printf '%s' "$g"
}

# Expired iff acquired_at is present AND (its age exceeds the TTL, OR its age is implausible:
# past -GRACE into the future, OR present-but-unparseable) — all with TTL>0. A future acquired_at
# yields a NEGATIVE age that can never exceed the TTL, so without a clamp a future-dated
# always-alive holder_pid (e.g. planted holder_pid=1) would wedge the tree FOREVER, defeating the
# TTL. BUT a bare `age<0 -> STALE` clamp is TOO strong: a LIVE holder's wall-clock acquired_at
# goes negative under a real backward clock step (NTP/WSL/VM), and reclaiming it STEALS a live
# lock (fail-open concurrency). So only age < -GRACE (implausibly future = forged/planted) is
# STALE; a small backstep (-GRACE <= age < 0) is treated as a FRESH live lock and respected. A
# MISSING/empty acquired_at is still NOT expired (falls back to PID-liveness), so pre-TTL locks and
# a genuine fresh legit lock (whose acquired_at ≈ now, age ≈ 0) are never reclaimed instantly.
_session_lock_expired() {
  local at="$1" ttl="$2" ts now age
  [ "$ttl" -gt 0 ] 2>/dev/null || return 1
  [ -n "$at" ] || return 1
  ts="$(date -d "$at" +%s 2>/dev/null)" || return 0   # present but unparseable -> STALE
  [ -n "$ts" ] || return 0                             # ditto
  now="$(date +%s)"
  age=$((now - ts))
  if [ "$age" -lt 0 ]; then
    local grace; grace="$(_session_lock_skew_grace)"
    [ "$age" -lt $(( -grace )) ] && return 0           # implausibly future (forged/planted) -> STALE
    return 1                                            # within skew grace (backward step) -> FRESH, respect a live holder
  fi
  [ "$age" -gt "$ttl" ]
}

# Emit a fully-formed lock body on stdout (redirected by the caller into the exclusive fd or,
# in the flock fallback, a plain create the flock already serializes).
_session_lock_meta() {
  printf 'holder_pid=%s\nholder_session=%s\nholder_op=%s\nacquired_at=%s\n' \
    "$$" "$2" "$1" "$(date -Iseconds)"
}

# Exclusive create-or-fail primitive: `set -C` (noclobber) opens the `>` redirect with
# O_CREAT|O_EXCL, so a create onto an EXISTING path fails. The SINGLE exclusivity seam — used by
# BOTH the O_EXCL probe and the fast publish path — so a fixture can shadow this one function to
# simulate a filesystem that silently ignores O_EXCL and exercise the flock fallback end-to-end.
_session_lock_excl_create() { ( set -C; : > "$1" ) 2>/dev/null; }

# One-time (per-process) probe of whether O_EXCL is genuinely honored on the FS hosting the lock
# dir. `set -C` gives O_CREAT|O_EXCL, which is atomic WHERE the server enforces it — but some 9p /
# Windows Z: mounts silently ignore it, so exactly-one-winner would degrade. Probe: create a temp
# in the SAME dir, then a SECOND exclusive create onto that now-existing path — under real O_EXCL
# the second MUST fail; if it "succeeds", O_EXCL is not exclusive here. Result cached in
# _SESSION_LOCK_OEXCL (1=fast O_EXCL path, 0=flock fallback). AI_AUTO_SESSION_LOCK_OEXCL forces it.
_SESSION_LOCK_OEXCL=""
_session_lock_oexcl_ok() {
  case "${AI_AUTO_SESSION_LOCK_OEXCL:-}" in 0) _SESSION_LOCK_OEXCL=0 ;; 1) _SESSION_LOCK_OEXCL=1 ;; esac
  if [ -z "$_SESSION_LOCK_OEXCL" ]; then
    local probe; probe="$(dirname "$SESSION_LOCK_FILE")/.session.lock.oexcl.$$"
    rm -f "$probe"
    if _session_lock_excl_create "$probe" && ! _session_lock_excl_create "$probe"; then
      _SESSION_LOCK_OEXCL=1                    # 2nd exclusive create refused -> O_EXCL honored
    else
      _SESSION_LOCK_OEXCL=0                    # 2nd "won" (or 1st failed) -> not exclusive -> flock
    fi
    rm -f "$probe"
  fi
  [ "$_SESSION_LOCK_OEXCL" = 1 ]
}

# Fast path: the O_EXCL create decides the winner (exactly one racer's `_session_lock_excl_create`
# succeeds); only that sole winner then writes the metadata, so a loser never overwrites it. A
# loser inspecting the brief empty-body window reads no holder_pid and retries (the empty-pid
# branch in acquire). Returns 0/1/2 (see _session_lock_publish).
_session_lock_excl_publish() {
  local op="$1" self="$2"
  if _session_lock_excl_create "$SESSION_LOCK_FILE"; then
    _session_lock_meta "$op" "$self" > "$SESSION_LOCK_FILE"
    SESSION_LOCK_HELD=1; return 0
  fi
  [ -e "$SESSION_LOCK_FILE" ] && return 1
  return 2
}

# Fallback for a FS that does not honor O_EXCL on create (probe said so): serialize the
# check-then-create under an flock on the same stable sidecar the reclaim uses, so exactly one
# racer wins even though the create itself is not atomic. Same 0/1/2 contract.
_session_lock_flock_publish() {
  local op="$1" self="$2" dir sidecar fd rc
  dir="$(dirname "$SESSION_LOCK_FILE")"
  sidecar="$dir/.session.lock.reclaim"
  exec {fd}>>"$sidecar" 2>/dev/null || return 2
  if ! flock -w 10 "$fd"; then exec {fd}>&-; return 2; fi
  if [ -e "$SESSION_LOCK_FILE" ]; then flock -u "$fd"; exec {fd}>&-; return 1; fi
  _session_lock_meta "$op" "$self" > "$SESSION_LOCK_FILE" 2>/dev/null; rc=$?
  flock -u "$fd"; exec {fd}>&-
  if [ "$rc" -eq 0 ]; then SESSION_LOCK_HELD=1; return 0; fi
  [ -e "$SESSION_LOCK_FILE" ] && return 1
  return 2
}

# Atomically install a fully-formed lock. On a FS that honors O_EXCL (the common case, confirmed
# by the one-time probe) this is a genuinely atomic create-or-fail — including hardlink-less 9p /
# Z: where the old `ln` silently failed and dropped to a fail-OPEN `mv -f` (N sessions ALL won).
# Where the probe finds O_EXCL is NOT enforced, publish falls back to an flock-serialized create so
# exactly-one-winner still holds. Sets SESSION_LOCK_HELD=1 and returns 0 on win; 1 if we LOST the
# race (lock now exists) so the caller loops to inspect it; 2 only if the create failed for a
# NON-contention reason (no lock file materialised) -> caller fails open.
_session_lock_publish() {
  if _session_lock_oexcl_ok; then _session_lock_excl_publish "$1" "$2"
  else _session_lock_flock_publish "$1" "$2"; fi
}

# Race-safe reclaim of a STALE (dead-PID or TTL-expired) lock. The critical section is
# serialized by an flock on a stable sidecar, so N racers that all saw the SAME stale lock
# can never all `rm`+publish into each other's gap (the old bug: 100+/250 double-wins). Under the
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
  if _session_lock_oexcl_ok; then
    _session_lock_excl_publish "$op" "$self"; rc=$?   # O_EXCL create-or-fail guards the fresh-publisher gap
  else
    # Non-exclusive FS: we already hold this sidecar flock and every fresh publisher blocks on
    # the SAME flock, so no racer can sneak into the post-rm gap -> a plain write is race-free
    # (and re-calling _session_lock_publish here would re-flock this fd -> self-deadlock).
    if _session_lock_meta "$op" "$self" > "$SESSION_LOCK_FILE" 2>/dev/null; then
      SESSION_LOCK_HELD=1; rc=0; else rc=2; fi
  fi
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

  # F4: a lock path that exists but is NOT a regular file (e.g. a pre-planted DIRECTORY) is
  # anomalous — `[ -f ]` is false so the loop would take the fresh-create path forever (the
  # O_EXCL create fails "Is a directory" -> publish returns 1 -> spin). Fail deterministically
  # (2, propagated as a hard error by callers, distinct from 75 contention) instead of hanging.
  if [ -e "$SESSION_LOCK_FILE" ] && [ ! -f "$SESSION_LOCK_FILE" ]; then
    printf '%s\n' "[lock] ERROR: lock path exists but is not a regular file (anomalous, e.g. a directory): $SESSION_LOCK_FILE" >&2
    return 2
  fi

  # Acquire is atomic on the FRESH path: `_session_lock_publish` installs a fully-formed lock
  # with an O_EXCL create (`set -C` noclobber redirect), so exactly one simultaneous racer wins
  # and the loser's create fails -> loops -> inspects (own / live-foreign->75 / stale). This is
  # atomic on any FS that honors O_EXCL (confirmed once by `_session_lock_oexcl_ok`); on a FS that
  # silently ignores it (some 9p / Z: mounts) publish transparently falls back to an flock-
  # serialized create so exactly-one-winner still holds — unlike the old `ln` that failed on
  # hardlink-less FS and dropped to a fail-OPEN `mv`. A STALE lock (dead PID or TTL-expired) is reclaimed
  # through the flock-serialized `_session_lock_reclaim`, so N racers reclaiming the SAME stale
  # lock can never all publish into each other's gap. Bounded loop: each iteration returns or
  # resolves to a live holder; the counter is a deadlock backstop.
  while : ; do
    tries=$((tries + 1))
    # F4: global deadlock backstop for the whole loop (mirrors the empty-pid branch's bound) so
    # NO unforeseen state can spin forever; real contention resolves in a handful of iterations.
    [ "$tries" -gt 10000 ] && { printf '%s\n' "[lock] ERROR: acquire loop exceeded bound without resolving; giving up" >&2; return 2; }
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
    [ "$prc" -eq 2 ] && return 0      # create infra failure -> fail open, proceed
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
