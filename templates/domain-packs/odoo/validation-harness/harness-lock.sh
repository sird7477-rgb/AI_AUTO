#!/usr/bin/env bash
# Reader/writer lock for the SHARED warm base (the harness is a single postgres volume +
# base/base_demo, shared by every run — git worktrees do NOT isolate it). prepare-base-db.sh
# takes a WRITE lock (it drops + rebuilds the base); validate-*.sh take a READ lock (they
# only clone the base), so concurrent validations coexist but never clone a base that is
# mid-rebuild, and two rebuilds never overlap. flock holds fd 9 for the rest of the script
# (released on exit). Degrades to no-lock if flock is unavailable (do not block work).
# Sourced by the harness scripts; the lock file lives in the harness dir (outside the
# project's git repo, so it is never committed).
# Per-project lock file (keyed by HARNESS_SLUG, set by harness-slug.sh) so project A's
# base rebuild never blocks project B.
HARNESS_LOCK_FILE="${HARNESS_LOCK_FILE:-${HARNESS_DIR:-.}/.harness-base.${HARNESS_SLUG:-default}.lock}"

harness_lock() {  # $1 = read | write
  # RED3-3: no fallback mechanism exists once flock is missing (unlike session-lock.sh's
  # O_EXCL probe), so a bare `return 0` here was a fully silent no-op -- a concurrent
  # write (prepare-base-db.sh dropping/rebuilding the base) and read (validate-*.sh
  # cloning it) could then race with zero diagnostic trail. Degrading is still correct
  # (do not block work over a missing binary) but it must be LOUD, not silent.
  if ! command -v flock >/dev/null 2>&1; then
    echo "[lock] WARNING: flock not found — base rebuild/validation running WITHOUT concurrency protection (a concurrent rebuild + validate-* read can race/corrupt the shared warm base)" >&2
    return 0
  fi
  exec 9>"$HARNESS_LOCK_FILE" || return 0
  if [ "${1:-read}" = "write" ]; then
    echo "[lock] acquiring base WRITE lock (blocks concurrent rebuilds/validations)..." >&2
    flock -x 9
  else
    flock -s 9   # shared: many validations run together; waits only during a rebuild
  fi
}

# Release our lock (close fd 9). Used before a script spawns a child that needs the WRITE
# lock (e.g. validate-full's demo rebuild calls prepare-base-db) to avoid a read->write
# self-deadlock on the same per-project lock file.
harness_unlock() {
  command -v flock >/dev/null 2>&1 || return 0
  exec 9>&- 2>/dev/null || true
}
