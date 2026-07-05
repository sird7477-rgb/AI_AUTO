# AI_AUTO AA-2 Verify Diff-Scope Plan

## Packet Contract

- Item: AA-2, verify diff-scope enforcement.
- Tier: plan-first.
- Scope: `scripts/verify.sh`, `scripts/review-gate.sh`, `scripts/collect-review-context.sh`, `scripts/verify-machinery.sh`, and verify-project contract docs or reference implementation.
- Boundaries: do not touch host/git-config/9p settings; do not weaken the fail-closed `scripts/verify-project.sh` seam; do not rewrite gate structure; do not reinvent machinery memoization; do not silently skip verification.

## Design

Extend the existing Diff Scope Summary from review-only input into verify input.
`collect-review-context.sh` already classifies changed files and `review-gate.sh` already consumes that summary. Add a machine-readable changed-paths field, then have `review-gate.sh` pass scoped verify metadata to `verify.sh`/`scripts/verify-project.sh` through env:

- `AI_AUTO_VERIFY_DIFF_SCOPE=1`
- `AI_AUTO_VERIFY_SCOPES=<comma scopes>`
- `AI_AUTO_VERIFY_CHANGED_PATHS=<newline paths>`
- `AI_AUTO_VERIFY_SCOPE_POLICY=<policy>`

`verify.sh` remains the fail-closed dispatcher. It reports whether scoped metadata is present and forwards the env unchanged to the project verifier. The project-owned verifier decides whether narrowing is safe.

For this repo's reference `scripts/verify-project.sh`, narrow only when independence is obvious:

- docs/plans-only changes skip product pytest and Docker smoke with explicit output.
- known sample app paths run the existing product pytest and Docker smoke.
- unknown mappings fall back to the full product verifier with an explicit reason.
- an opt-in fixture env can inject scoped failure to prove fail-closed behavior.

Review verdicts record the verify scope metadata for audit, including verify-only skip verdicts and normal run manifests.

## Acceptance Mapping

1. docs/plans-only diff: verify prints that product pytest/smoke are skipped because scoped metadata proves docs/plans-only.
2. code diff with known mapping: only the mapped product checks run, and output names the changed paths.
3. unknown mapping: verifier prints fallback reason and runs the full product checks.
4. scoped failure injection: nonzero exit blocks the gate.
5. `scripts/verify-machinery.sh` fixtures cover all four cases and existing verify-only diff behavior remains intact.
