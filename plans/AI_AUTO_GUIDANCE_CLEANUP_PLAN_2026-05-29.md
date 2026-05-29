# AI_AUTO Guidance Cleanup Plan - 2026-05-29

## Scope

This plan starts the guidance cleanup lane after the structural backlog reopened
guidance-budget cleanup. It does not edit `AGENTS.md`, template guidance, or
policy documents yet.

## Evidence

- `./scripts/doc-budget.sh` passed with warnings, not failures.
- `AGENTS.md` is 155 lines; the warning budget is 150.
- Initial total guidance markdown was 9525 lines under the former aggregate
  9000-line warning budget. Follow-up audit replaced that single aggregate
  threshold with separate primary/template budgets because template mirrors are
  intentional distribution copies.
- Current guidance diff adds 0 lines, so the warning is accumulated volume, not
  this branch's current edits.
- Stage-2 duplicate report was generated at
  `.omx/doc-duplicate-report/guidance-duplicate-report-20260529T000943+0900.md`.

## Diagnosis

The current problem is guidance volume and duplication pressure, not a broken
gate. The root `AGENTS.md` barely exceeds its warning threshold, while total
guidance volume exceeds the aggregate threshold by 525 lines.

The duplicate report shows two kinds of repetition:

- Expected root/template mirror duplication. Examples include
  `docs/AUTOMATION_OPERATING_POLICY.md` and
  `templates/automation-base/docs/AUTOMATION_OPERATING_POLICY.md`. This should
  not be removed casually because the template copy is a distributable baseline.
- Candidate consolidation pressure in completion packs and policy guidance.
  Repeated section shapes such as `Onboarding Questions`, `Workflow Additions`,
  `Verification Patterns`, `Completion Criteria`, and `Non-Goals` appear across
  completion packs. These are structurally intentional, but they may be
  shortened by extracting a shared completion-pack skeleton.

## Two-Stage Cleanup

### Stage 1: Root Guidance Trim

Goal: bring root `AGENTS.md` below the 150-line warning budget without changing
operating behavior.

Allowed edits:

- replace repeated rule lists in `AGENTS.md` with references to existing policy
  docs when the same rule already exists there
- keep command keywords and completion report requirements intact
- preserve all Korean trigger phrases and explicit safety gates

Stop condition:

- `AGENTS.md` is at or below 150 lines
- `./scripts/doc-budget.sh` still passes
- `./scripts/verify.sh` still finds required root guidance strings

### Stage 2: Completion-Pack Skeleton Review

Goal: reduce real duplicated guidance volume without weakening domain
completion contracts.

Allowed edits:

- create or identify one shared completion-pack skeleton
- shorten repeated completion-pack sections only when the domain-specific
  requirement remains explicit
- keep template copies synchronized when template-owned files are changed

Stop condition:

- primary and template guidance budgets pass, or a concrete rejected reason is
  recorded for any remaining budget pressure
- template version and patch notes are updated if template files change
- `./scripts/verify.sh` and `./scripts/review-gate.sh` are run before any
  commit candidate

## Non-Goals

- No deletion of safety, approval, verification, or destructive-action gates.
- No direct edit to `.omx/` reports.
- No broad rewrite of policy language.
- No guidance edit based only on a warning without matching verification.

## Recommendation

Proceed with Stage 1 first. It is narrow, reversible, and targets the current
root warning directly. Stage 2 should wait until Stage 1 is verified, because it
touches template-owned completion-pack surfaces and has a larger review burden.

## Stage 1 Execution Note

Stage 1 may trim root `AGENTS.md` only by compressing duplicated wording without
removing safety or verification requirements. The first safe target is the
project-specific "not allowed" list: it can be expressed as one wrapped bullet
without changing the forbidden scope.

Executed result: root `AGENTS.md` is now 150 lines, which clears its warning
budget.

## Stage 2 Micro Assessment

Stage 2 was assessed during the TODO Ralph micro pass. It should not be folded
into the same micro implementation slice.

Reason:

- The remaining excess is aggregate volume, not a failing root guidance gate.
- The largest safe targets are template-mirrored completion packs and shared
  policy/workflow documents. Reducing more than 500 lines would require a
  shared completion-pack skeleton or template-owned rewrite, not a local trim.
- Template-owned changes require versioning, patch notes, sync checks, and
  review-gate coverage. Combining that with review-gate/untracked-artifact
  contract work would mix two separate risk surfaces.

Decision update: the single aggregate 9000-line warning budget was not suitable
for the current structure because it counted live project guidance together with
intentionally mirrored template guidance. `scripts/doc-budget.sh` now budgets
primary guidance and template guidance separately and reports the combined total
as informational. Stage 2 remains available only for real duplication pressure,
not for this former aggregate warning alone.
