# AI_AUTO SPEC-AUD-1 Gate Verdict Binding Plan

Date: 2026-07-05
Tier: plan-first

## Goal

Make `review-gate` verdicts operationally binding for behavior-changing push paths.
A push must not proceed on a self-claim, a missing/hung gate, or a blocked verdict.
It needs a local, authenticated record that the current change was reviewed and
ended in `proceed` or `proceed_degraded`.

## Decisions

1. Use `pre-push` as the hard enforcement point.
   `post-commit` remains advisory because Git runs it after the commit already
   exists; it cannot reliably block the behavior commit. The pre-push hook is
   installed by `ai-auto setup` alongside the existing `pre-commit` and
   `post-commit` shims.

2. Add a small binding record separate from the existing provenance-skip record.
   The current `approved-provenance.env` intentionally records only normal-trust
   `proceed` and is optimized for review skip. SPEC-AUD-1 also needs
   `proceed_degraded` to be push-bindable, so `review-gate` will write a
   HMAC-authenticated `.omx/reviewer-state/binding-verdict.env` after any allowed
   verdict.

3. Bind to the reviewed change bytes, not to a mutable claim.
   The binding hash uses the current staged/unstaged/untracked change payload
   while dirty, and the latest commit diff when clean. This lets the normal
   flow `gate -> commit -> push` remain usable without accepting an unrelated
   later edit.

4. Treat negative or missing verdicts as fail-closed.
   A latest `blocked`, `revise`, or `review_manually` verdict blocks push. No
   verdict or a mismatching/forged binding blocks push with
   `no binding gate verdict for this change`.

5. Stop trusting `AI_AUTO_VERIFY_OVERRIDE_APPROVED_BY` as a bare env value.
   A verify-failure override is accepted only when the approver value matches a
   launcher-owned principal evidence record with a valid out-of-tree HMAC. A
   script-set env pair without launcher evidence remains blocked.

## Files

- `scripts/review-gate.sh`
- `scripts/review-gate-binding.sh` (new helper)
- `hooks/pre-push` (new global hook body)
- `hooks/post-commit`
- `tools/ai-auto`
- `scripts/automation-doctor.sh`
- `scripts/verify-machinery.sh`
- `docs/WORKFLOW.md`
- `AGENTS.md`

No `templates/automation-base` files are touched.

## Tests

Add non-vacuous machinery fixtures:

- behavior diff with no binding record: `pre-push` exits nonzero and prints
  `no binding gate verdict for this change`
- latest `blocked` verdict: `pre-push` exits nonzero
- env-only verify override: `review-gate` rejects the override and blocks
- launcher-evidence override: `review-gate` proceeds past verify failure and
  records override state
- docs/plans-only verify-skip verdict writes a binding record, preserving the
  AA-1 path
- `ai-auto setup` installs `pre-push` and doctor checks it

## Stop Condition

SPEC-AUD-1 is complete only after `./scripts/verify.sh` and
`./scripts/review-gate.sh` return an acceptable proceed decision, then the
change is committed through `scripts/guarded-git-commit.sh`.
