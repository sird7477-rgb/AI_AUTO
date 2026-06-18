# Fix P2 — worktree-safe pre-commit hook + post-commit gate-bypass guard (2026-06-18)

Source: `.aiauto-audit/SYNTHESIS.md` #2 (`--no-verify` habit / commit suite never gated).

## Root cause
The live pre-commit hook (`.git/hooks/pre-commit`, shared across all linked
worktrees via the common git dir) runs `pytest` without clearing the GIT_*
environment git exports into hooks (`GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE`,
`GIT_PREFIX`, `GIT_COMMON_DIR`, `GIT_NAMESPACE`). Test subprocesses that spawn
git inherit those and operate on the shared common git dir/index instead of their
own temp repos, corrupting git state across worktrees. That corruption is why
sessions fell back to `git commit --no-verify`, leaving the full suite ungated.
The live hook is also untracked, so no fix propagates fleet-wide.

## Fix (user: "둘 다")
A. **Worktree-safe hook, tracked + installed**
   - New tracked `templates/automation-base/hooks/pre-commit`: `unset` the GIT_*
     vars, then run the suite worktree-safely. Tests get a clean git environment,
     so the suite can gate at commit without corrupting linked worktrees.
     Behavior is a hybrid: fail-closed when a pytest runner is present and tests
     fail; warn + defer (exit 0) only when no runner exists at all (absence is a
     positive discovery, never inferred from a nonzero exit). review-gate.sh
     remains the authoritative gate; the post-commit hook is the backstop.
   - `install-automation-template.sh` installs `hooks/pre-commit` + `post-commit`
     into the target's real hooks dir (`git -C TARGET rev-parse --git-path hooks`,
     worktree-aware).
   - Fix the live `/root/workspace/ai-lab/.git/hooks/pre-commit` in place.
B. **post-commit gate-bypass guard (advisory)**
   - `--no-verify` skips pre-commit/commit-msg but NOT post-commit. New tracked
     `templates/automation-base/hooks/post-commit` warns loudly when no
     review-gate `proceed`/`proceed_degraded` verdict exists in the last 30 min,
     making gate-bypassing commits non-silent. Cannot block (commit already made)
     — git-design limit; visibility is the goal.

## Version / docs
`AI_AUTO_TEMPLATE_VERSION` 2026.06.18.1 -> 2026.06.18.2; PATCH_NOTES entry;
verify-machinery test asserting the installed pre-commit unsets GIT_*.

## Verify
`verify-machinery.sh` (installer test + parity + shellcheck) -> `review-gate.sh`
to unanimous.
