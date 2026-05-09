# Agent Instructions

This repository is a Codex/OMX single-agent workflow testbed.

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
- `docs/AI_MODEL_ROUTING.md`
- `docs/SESSION_QUALITY_PLAN.md`
- `scripts/verify.sh`
- `scripts/review-gate.sh`

## Evidence And Uncertainty

- Do not present guesses, inferred model availability, undocumented behavior, or unverified project assumptions as facts.
- If something is unclear, say what is known, what is inferred, and what evidence would confirm it.
- Prefer local runtime evidence for CLI/model availability; provider documentation is reference material unless the current task explicitly asks for external research.
- When forced to proceed with an assumption, label it as an assumption and keep the change reversible.

## Command Keywords

When the user asks `전역파일 설치해줘`, `전역 파일 설치`, or `global files install`,
run `./scripts/install-global-files.sh` from the repository root.

This command installs or repairs only the repo-owned global helper symlinks under
`~/bin`. It does not install external programs, edit shell profiles, configure
credentials, run `automation-doctor --fix`, or overwrite non-symlink files.

## Completion Report Format

When reporting completion, include:

- changed files
- diff summary
- verification command
- verification result
- known warnings or limitations
