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
5. mention any remaining warnings or limitations

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
- stack and runtime commands
- allowed and forbidden change types
- required verification commands
- smoke checks that prove the final result works
- project-specific documentation or domain constraints

Then update:

- `AGENTS.md`
- `docs/WORKFLOW.md`
- `scripts/verify.sh`

Run `./scripts/automation-doctor.sh`, `./scripts/verify.sh`, and
`./scripts/review-gate.sh` before treating the automation baseline as ready.

## Required References

Use these files as the workflow baseline:

- `docs/WORKFLOW.md`
- `scripts/verify.sh`
- `scripts/review-gate.sh`

## Completion Report Format

When reporting completion, include:

- changed files
- diff summary
- verification command
- verification result
- known warnings or limitations
