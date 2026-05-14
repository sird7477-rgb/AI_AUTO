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

## Planning And Interview Escalation

Use `docs/AUTOMATION_OPERATING_POLICY.md` for the full policy. In short:

- execute directly for clear, small, reversible work
- treat feasibility, advice, recommendation, and brainstorming questions as answer-only unless the user explicitly asks for execution
- ask one focused question when a single missing decision materially changes the result
- use a plan-first interview for broad, strategic, high-risk, or long-lived workflow changes
- inspect local evidence before asking, and label assumptions instead of presenting guesses as facts
- do not let "바로 진행" bypass destructive, credentialed, production, or materially scope-changing approval gates

## Onboarding Rule

After template installation or existing-project onboarding, interview the
project owner before the first real task and record project-specific operating
rules. The canonical onboarding checklist is in
`docs/AUTOMATION_OPERATING_POLICY.md`; question shape, answer mapping,
ambiguity, and plan/run boundaries are governed by
`docs/INTERVIEW_PLAN_LAYER.md`.

Optional domain packs may be available under `.omx/domain-packs/` after
`aiinit`. They are onboarding references only and are ignored by git by default.

Then update:

- `AGENTS.md`
- `docs/WORKFLOW.md`
- `scripts/verify.sh`

Record at minimum the review intensity policy, resource-aware parallelism
expectations, planning/interview intensity expectations (`none`, `light`,
`standard`, or `deep`), and any project-specific completion-pack decisions in
those files. Include sandbox-vs-real-network evidence, Incident Ops rules, and
plan index/TODO reconciliation boundaries when the project may run dry-run,
field-test, networked, or long-running work.

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
3. Run the canonical onboarding checklist from
   `docs/AUTOMATION_OPERATING_POLICY.md` using the interview mechanics in
   `docs/INTERVIEW_PLAN_LAYER.md`. Ask only for facts that cannot be inferred
   safely from local files or runtime evidence.
4. Confirm review intensity, feedback recording, approval-friction handling,
   subagent usage, resource-aware parallelism, operational readiness,
   Incident Ops, and plan/TODO reconciliation expectations from the linked docs.
5. Inspect `.omx/domain-packs/` and explicitly confirm which installed packs
   apply and which do not. If a pack applies, use it as reference material and
   merge only the applicable rules. Do not apply domain packs to unrelated
   projects.
6. Update `AGENTS.md` with project-specific agent rules.
7. Update `docs/WORKFLOW.md` with project-specific workflow and verification
   expectations.
8. Delete unused `docs/*_COMPLETION.md` files after recording them as non-goals
   if they would only clutter the target project.
9. Customize `scripts/verify.sh` with real project checks while preserving useful template safeguards.
10. Run `./scripts/automation-doctor.sh`.
11. Run `./scripts/verify.sh`.
12. Run `./scripts/review-gate.sh` when `./scripts/verify.sh` passes.
13. Do not commit unless the user explicitly asks for a commit.

When the user asks for `리빌드 플랜`, `리빌딩 플랜`, `rebuild plan`, or
`ai-rebuild-plan`, treat it as read-only planning. Inspect the repository,
template drift, domain-pack references, refactoring candidates, and behavior
locking gaps, then stop at a plan/report boundary. Do not modify files.

When the user asks for `리빌드 실행`, `리빌딩 실행`, or `rebuild run`, require
an approved rebuild plan, refreshed domain-pack assumptions, behavior-locking
tests or smoke checks, explicit module boundaries, and the normal verify/review
gates before execution.

Optional rebuild support gates are read-only by default. Context packing,
codemod scan, and boundary check may be suggested for explicit requests,
material boundary changes, stale required evidence, domain-critical work, or
structural verification/review failures. Missing optional tools must not block
small reversible work. `codemod apply`, autofix, or any write-capable tool
requires an explicit execution command tied to an approved scoped plan, reviewed
dry-run diff or summary, rollback path, and post-apply verification.

## Required References

Use these files as the workflow baseline:

- `docs/WORKFLOW.md`
- `docs/AI_MODEL_ROUTING.md`
- `docs/AUTOMATION_OPERATING_POLICY.md`
- `docs/DOMAIN_PACKS.md`
- `docs/DOMAIN_PACK_AUTHORING_GUIDE.md` when creating or changing reusable domain packs
- `docs/INTERVIEW_PLAN_LAYER.md`
- `docs/SESSION_QUALITY_PLAN.md`
- applicable completion packs from `docs/*_COMPLETION.md`
- `scripts/verify.sh`
- `scripts/review-gate.sh`

## Model And Delegation Boundary

Use `docs/AI_MODEL_ROUTING.md` as the source of truth for leader-vs-subagent
model routing. The active Codex/GPT leader is runtime-selected; optimize
cost/latency by delegating bounded work to role-appropriate child agents or OMX
lanes, not by claiming the leader changed models mid-session.

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
