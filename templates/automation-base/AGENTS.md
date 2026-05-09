# Agent Instructions

This repository uses the Codex/OMX automation baseline.

Project-specific purpose, scope, and verification rules must be defined during
onboarding before feature work begins.

## Operating Rule

Before claiming a task is complete, the agent must:

1. keep the change small and within scope
2. inspect the diff
3. run `./scripts/verify.sh` for basic verification
4. run `./scripts/review-gate.sh` before presenting a commit candidate
5. report the verification and review results
6. mention any remaining warnings or limitations

If `./scripts/verify.sh` fails, the task is not complete.
If `./scripts/review-gate.sh` fails or returns a decision other than `proceed` or `proceed_degraded`, do not present the change as ready to commit. A `proceed_degraded` result may continue only when its degraded trust level and missing reviewer state are reported clearly.

## Scope

Allowed:

- documentation cleanup
- workflow clarification
- narrow reliability fixes
- verification script improvements
- small changes within the project scope defined during onboarding

Not allowed without a new explicit plan:

- project-specific feature work before onboarding defines the scope
- authentication, authorization, or security-sensitive changes
- data model, migration, or destructive storage changes
- new dependencies or external services
- large architecture rewrites
- deployment hardening

## Onboarding Rule

After `aiinit`, interview the project owner before the first real task and
record the project-specific operating rules.

Clarify at minimum:

- project purpose and non-goals
- which installed domain packs under `.omx/domain-packs/` apply or do not apply
- stack and runtime commands
- allowed and forbidden change types
- required verification commands
- smoke checks that prove the final result works
- project-specific documentation or domain constraints

Optional domain packs may be available under `.omx/domain-packs/` after
`aiinit`. They are onboarding references only and are ignored by git by default.

Then update:

- `AGENTS.md`
- `docs/WORKFLOW.md`
- `scripts/verify.sh`

Run `./scripts/automation-doctor.sh`, `./scripts/verify.sh`, and
`./scripts/review-gate.sh` before treating the automation baseline as ready.

## Command Keywords

When the user asks `프로젝트 초기설정 해줘`, or asks to interview project
requirements and configure `AGENTS.md`, `docs/WORKFLOW.md`, and
`scripts/verify.sh`, run the onboarding workflow.

Onboarding workflow:

1. Confirm the current path and git status.
2. Inspect existing project materials as references, including folders such as
   `(old)/`, `docs/`, `README.md`, or domain notes when present.
3. Interview the project owner for purpose, stack, completion criteria, forbidden
   changes, sensitive-data boundaries, and required verification.
4. Inspect `.omx/domain-packs/` and explicitly confirm which installed packs
   apply and which do not. If a pack applies, use it as reference material and
   merge only the applicable rules. Do not apply domain packs to unrelated
   projects.
5. Update `AGENTS.md` with project-specific agent rules.
6. Update `docs/WORKFLOW.md` with project-specific workflow and verification
   expectations.
7. Customize `scripts/verify.sh` with real project checks while preserving useful template safeguards.
8. Run `./scripts/automation-doctor.sh`.
9. Run `./scripts/verify.sh`.
10. Run `./scripts/review-gate.sh` when `./scripts/verify.sh` passes.
11. Do not commit unless the user explicitly asks for a commit.

## Required References

Use these files as the workflow baseline:

- `docs/WORKFLOW.md`
- `docs/AI_MODEL_ROUTING.md`
- `docs/SESSION_QUALITY_PLAN.md`
- `scripts/verify.sh`
- `scripts/review-gate.sh`

## Evidence And Uncertainty

- Do not present guesses, inferred model availability, undocumented behavior, or unverified project assumptions as facts.
- If something is unclear, say what is known, what is inferred, and what evidence would confirm it.
- Prefer local runtime evidence for CLI/model availability; provider documentation is reference material unless the current task explicitly asks for external research.
- When forced to proceed with an assumption, label it as an assumption and keep the change reversible.

## Completion Report Format

When reporting completion, include:

- changed files
- diff summary
- verification command
- verification result
- known warnings or limitations
