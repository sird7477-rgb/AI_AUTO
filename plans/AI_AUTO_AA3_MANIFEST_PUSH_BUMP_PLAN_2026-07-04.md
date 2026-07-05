# AA-3 Plan - Move Odoo manifest version bumps to push time

## Packet

AA-3: stop per-commit `__manifest__.py` auto-bumps and provide an advisory
domain-pack reference path for one bump at push/release time.

## Decision

Use the existing `safe-push.sh` shared-branch wrapper as the reference delivery
surface. Add an opt-in pre-push step there, not inside the raw `pre-push` hook:

- `safe-push.sh --bump-manifest-version [remote] [branch]`
- or `SAFE_PUSH_BUMP_MANIFEST=1 safe-push.sh [remote] [branch]`

The step runs before the first push attempt. It computes the unique changed Odoo
modules between `remote/branch` and `HEAD`, bumps each changed module manifest
once, and creates a single local commit. `safe-push.sh` then runs its normal
push/rebase/retry loop; the shipped version merge driver remains the transition
safety net for concurrent bumps and older per-commit hooks.

## Rejected Paths

- Raw `pre-push` hook creates a commit: rejected because Git already selected
  the pushed SHA before the hook runs.
- Release-only documentation: rejected for this slice because it does not provide
  a local reference tool or a non-vacuous fixture for the shared-branch workflow.
- Deterministic version formula from commit count: rejected for now because it
  changes downstream version semantics and still needs project-specific release
  policy.

## Scope

Touch only:

- `templates/domain-packs/odoo/git-tier/`
- `templates/domain-packs/odoo/verify-patterns.md`
- `scripts/verify-machinery.sh`
- this plan

Do not modify or regenerate `templates/automation-base`.

## Implementation Contract

- The bump script must be advisory and opt-in.
- It must refuse a dirty worktree before creating the bump commit, so unrelated
  user edits cannot be swept into the generated commit.
- It must bump a module at most once per invocation even if that module changed
  across many commits.
- It must fail closed on unparseable or missing version lines.
- It must use one generated commit for all bumped modules.
- Unknown/non-Odoo changes mean no bump, not failure.
- Rebase replay must not trigger extra bumps because the logic is not installed
  as a per-commit hook.

## Tests

Add `verify-machinery.sh` fixtures proving:

1. three commits touching one module produce one bump commit and one monotonic
   version increment;
2. rebase replay does not create an extra generated bump commit;
3. two sessions that both bump the same module converge through the shipped
   version merge driver during `safe-push.sh`;
4. dirty worktree and missing version-line cases fail before any commit is
   created.

Run `verify.sh` and `review-gate.sh` after implementation.
