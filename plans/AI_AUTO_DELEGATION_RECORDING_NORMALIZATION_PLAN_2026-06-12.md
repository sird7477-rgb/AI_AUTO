# AI_AUTO Delegation Recording Protocol Normalization Plan - 2026-06-12

## Goal

Normalize per-unit model-class lane delegation recording from an ad-hoc,
caller-less step (`scripts/record-lane-decision.py` had no production caller, so
`.omx/model-routing/lane-decisions.tsv` stayed empty and the evidence-driven
tuning loop in `docs/AI_MODEL_ROUTING.md` was permanently dormant) into a
standing, contract-tested rule. After this change, whenever the leader/principal
delegates a unit of code work onto a model-class lane, recording the decision is
a required, locked part of the workflow.

## Consensus Inputs

- User request (2026-06-12): drive the code-delegation loop to normalization, with
  thorough post-normalization execution verification.
- Live PoC executed and verified the same day: Opus principal delegated a bounded
  test-addition to a `haiku` (fast-class) native subagent, guardrails passed,
  leader diff-inspected, suite green (0% rewrite), and the first-ever
  `lane-decisions.tsv` row was written. This plan promotes that one-time step.
- Architectural constraint (`docs/AUTOMATION_OPERATING_POLICY.md` § Subagent
  Utilization, "the leader decides whether to spawn them"): code-work delegation
  is the principal's own native subagent at a lower class, spawned by leader
  judgment — NOT a scripted auto-router and NOT the external one-shot review CLI.
  So normalization codifies a *recording obligation*, not an automatic dispatcher.
- Reference: ST-P1-22 (`plans/AI_AUTO_MODEL_ROUTING_ENFORCEMENT_PLAN_2026-06-02.md`,
  `docs/AI_MODEL_ROUTING.md`); idiom mirror: ST-P1-28 Ralph Completion Discipline
  (AGENTS.md rule + `scripts/self_demo_contracts.py` contract + test + verify).

## Scope / Non-Goals

- IN: a standing AGENTS.md rule; a pure contract validating a delegation-episode
  record; tests; doc update removing the "no caller / dormant" framing; parity
  locks; template sync.
- OUT: an automatic lane dispatcher; changing any lane's default model class
  (still evidence-driven, no accumulated evidence yet); routing actual review
  CLI invocation; any global downgrade of standard/planner/verifier/reviewer
  lanes. Leader-judgment spawn and all existing guardrails are preserved.

## Implementation Contract

1. AGENTS.md: add `## Delegation Recording Protocol` after `## Ralph Completion
   Discipline`, naming `delegation_recording_policy` and the
   observability-only / no-completion-authority invariant. Mirror in
   `templates/automation-base/AGENTS.md`.
2. `scripts/self_demo_contracts.py` (machinery-only, not templated): add pure
   `delegation_recording_policy(record)` returning `ContractResult`; update the
   module-docstring inventory to list it.
3. `tests/test_self_demo_contracts.py`: import it; add pass/fail test functions
   covering not-applicable, invalid-lane, not-recorded, observability-only, and
   all four valid class lanes.
4. `docs/AI_MODEL_ROUTING.md`: update § Evidence-driven tuning and the
   `low_cost_impl` lane contract so recording is described as a normalized
   required step (still evidence-only; tuning still gated on accumulated
   evidence). Keep `templates/automation-base/docs/AI_MODEL_ROUTING.md` identical.
5. `scripts/verify-machinery.sh`: lock the rule — `grep -q` the new AGENTS.md
   marker in main and template, and `cmp -s` main vs template AI_MODEL_ROUTING.md.
6. `templates/automation-base/AI_AUTO_TEMPLATE_VERSION` bump + a
   `templates/automation-base/docs/PATCH_NOTES.md` top entry.
7. `plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md` ST-P1-22: append a normalization
   note.

## Micro Work Units

- U1: AGENTS.md rule + template mirror.
- U2: contract function + docstring inventory.
- U3: tests.
- U4: AI_MODEL_ROUTING.md (main + template) doc update.
- U5: verify-machinery parity locks.
- U6: template version bump + patch notes.
- U7: backlog note.

## Completion Evidence

Required before claiming completion:
- `AGENTS.md` and template both contain the marker; `grep -q` parity passes.
- `delegation_recording_policy` importable; `python3 -m py_compile` clean.
- `tests/test_self_demo_contracts.py` delegation tests pass under `pytest -q`.
- `docs/AI_MODEL_ROUTING.md` == template (`cmp -s`).
- `./scripts/verify.sh` (machinery scope) green.
- `./scripts/review-gate.sh`: unanimous accept (Gemini + Codex, principal=claude).
- Post-normalization execution verification: the contract actually REJECTS an
  unrecorded delegation episode and ACCEPTS a recorded one (live), and a fresh
  delegation round writes a real second `lane-decisions.tsv` row through the
  normalized path.

## Status

Complete — 2026-06-12. Implemented all 7 units. Verified: `pytest` 65 passed
(incl. new `delegation_recording_policy` tests + recorder cap test); doc-budget
failures=0; parity locks green; contract teeth live-verified (rejects unrecorded
delegation and authority-claim, accepts recorded). The lone verify-machinery
failure (`bootstrap --fix` sandbox installer test) reproduces on a clean baseline
→ pre-existing/environmental, not this change. review-gate (principal=claude):
decision `proceed`, trust `normal`, reason `principal_rotation_approval`,
missing_or_unusable_reviewers `none` — Gemini approve, Codex architect
approve_with_notes (no blocking findings). Not committed (awaiting user).
