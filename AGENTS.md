# Agent Instructions

This repository is a Codex/OMX single-agent workflow testbed.

## Operating Rule

Before claiming a task is complete, the agent must:

1. keep the change small and within scope
2. inspect the diff
3. run `./scripts/verify.sh`
4. report the verification result
5. mention any remaining warnings or limitations

If `./scripts/verify.sh` fails, the task is not complete.

## Scope

Allowed:

- documentation cleanup
- workflow clarification
- narrow reliability fixes
- verification script improvements
- small testbed maintenance

Not allowed without a new explicit plan:

- new todo app features
- UI work
- authentication
- background jobs
- large architecture rewrites
- deployment hardening

## Required References

Use these files as the workflow baseline:

- `docs/WORKFLOW.md`
- `docs/AI_ROLES.md`
- `scripts/verify.sh`

## Completion Report Format

When reporting completion, include:

- changed files
- diff summary
- verification command
- verification result
- known warnings or limitations
