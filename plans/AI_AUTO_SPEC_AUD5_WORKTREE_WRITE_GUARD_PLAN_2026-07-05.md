# SPEC-AUD-5 Plan: cross-worktree write guard

## Contract

SPEC-AUD-5 requires AI_AUTO write paths to refuse writes into a working tree
owned by another live session, while preserving legitimate self re-entry and
read-only cross-worktree inspection. The existing `scripts/session-lock.sh`
atomic locking primitive is already shipped and must not be reimplemented.

## Design Decisions

1. Reuse the existing `.omx/state/session.lock` metadata as the ownership
   source. A live lock with a different `holder_session` means another session
   owns the tree for writes. A self lock, missing lock, dead holder, or stale
   holder remains allowed.
2. Add a small executable/sourceable `scripts/worktree-write-guard.sh` with
   `worktree_write_guard_check <op>`. It reads lock metadata only; it does not
   acquire or release the session lock and does not alter `session-lock.sh`.
3. Wire the guard into the shipped write chokepoints:
   `scripts/guarded-git-commit.sh` for commits and `tools/ai-python-split apply`
   for the approved patch-apply path used by `ai-split-apply`.
4. Harden tmux dispatch booking in `tools/ai-tmux-worktree`: when a new tmux
   window starts inside an already tmux-managed worktree, allocate that window
   its own worktree instead of leaving two live windows in the same tree. Keep
   the existing `@ai_wt_done` idempotency for the respawned pane.
5. Do not block reads, status checks, review collection, or worktree lifecycle
   cleanup. The guard is write-only.

## Implementation Surface

- `scripts/worktree-write-guard.sh` (new)
- `scripts/guarded-git-commit.sh`
- `tools/ai-python-split`
- `tools/ai-tmux-worktree`
- `scripts/verify-machinery.sh`
- relevant docs if needed

`scripts/session-lock.sh` is not changed except for test consumption of its
existing metadata contract.

## Verification Plan

- Fixture: foreign live lock in `.omx/state/session.lock` + staged commit via
  guarded commit => non-zero with `write-guard` reason and no new HEAD.
- Fixture: self lock + staged commit via guarded commit => commit succeeds.
- Fixture: foreign live lock + `ai-split-apply` approved plan => refused before
  extracted files are written.
- Fixture: tmux worktree create from inside an already managed `*-tmux-wN`
  worktree calls `ai-worktree tmux-wM` for the new window instead of marking the
  same tree as done.
- Existing session-lock F3/F4 fixtures remain unchanged and continue to pass.
