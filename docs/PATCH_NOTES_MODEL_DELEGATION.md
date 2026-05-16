# Patch Notes: Token-Efficient Codex Delegation

Date: 2026-05-16

## Summary

Documented a guarded policy for using low-cost Codex coding lanes for bounded
implementation work while keeping architectural and completion authority on the
leader.

## Changed

- `docs/AI_MODEL_ROUTING.md`
  - Added token-efficient implementation delegation rules.
  - Updated the `implementation` role to prefer the current low-cost Codex
    coding lane only when guardrails pass.
  - Kept the detailed guardrail checklist delegated to
    `docs/AUTOMATION_OPERATING_POLICY.md` to avoid duplicated policy drift.
  - Clarified that planning, architecture, security-sensitive work,
    integration, review interpretation, and final claims stay with the leader.

- `docs/AUTOMATION_OPERATING_POLICY.md`
  - Added a `Low-Cost Coding Lane` subsection under `Subagent Utilization`.
  - Defined allowed and disallowed task shapes.
  - Added leader responsibilities for context packaging, ambiguity escalation,
    diff review, and verification.
  - Added a 20% rewrite-rate stop rule for low-cost lane output and a
    completion-report disclosure requirement when that lane is used.

## Direction Adopted

The leader adopted the direction with strict boundaries. This is a scoping
record, not a review-gate verdict. Low-cost coding lanes are useful for
exact-file implementation slices, local test fixes, mechanical cleanup, and
narrow refactors. They are not the authority for design, security, broad
integration, review-gate interpretation, or completion claims.

## Prior Advisor Input

These notes summarize the advisory discussion captured in session-local
artifacts before the policy edit, not a review-gate verdict:

- Claude advisor input recommended stronger guardrails around boundedness,
  security carve-outs, diff-level review, external-code exposure, and
  rewrite-rate measurement.
- Gemini advisor input emphasized leader-led re-validation, project gates, and
  reclaiming the task after repeated delegated failure.

## Operational Rule

Delegate bounded implementation only when files, scope, and acceptance criteria
are explicit and the task does not touch security, validation, serialization,
external data, PII, schema, or API contracts. The leader remains responsible for
planning, architecture, integration, verification interpretation, and final
completion.
