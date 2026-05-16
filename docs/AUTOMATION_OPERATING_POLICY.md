# Automation Operating Policy

This document defines the reusable default policy for AI review intensity and
failure-pattern feedback. Project onboarding should copy the defaults, then tune
them to the target project's risk level.

## Review Intensity

Default mode: `standard`.

Use one of these project policies during onboarding:

| Mode | Use When | Required Gate |
| --- | --- | --- |
| `lightweight` | Documentation-only, local-only, or very small reversible changes | `./scripts/verify.sh`; run `review-gate` only for risky or shared automation changes |
| `standard` | Normal application or automation work | `./scripts/verify.sh`; run `review-gate` before commit candidates when behavior, workflow, data, deployment, security, or shared scripts change |
| `strict` | Finance, production deployment, auth/security, destructive data, regulated workflow, or high-blast-radius automation | `./scripts/verify.sh` and `./scripts/review-gate.sh` before every commit candidate |

Escalate one level when:

- the change touches shared automation, review routing, model routing, or
  verification scripts
- the change affects data persistence, migrations, deployment, credentials,
  security boundaries, or user-visible workflows
- prior verification or review failed on the same task
- the agent is making assumptions that materially affect behavior

De-escalate one level only when all are true:

- the change is documentation-only or a small local maintenance edit
- `./scripts/verify.sh` proves the relevant behavior
- no external reviewer or domain-specific judgment is needed
- the completion report explicitly states that `review-gate` was intentionally
  skipped under the project's review-intensity policy

## Advisory Reviewer Sessions

External reviewers may be kept open during local development only as an
advisory optimization. This is useful for repeated small iterations where a
human or agent wants fast feedback before the final gate.

Rules:

- Treat warm reviewer sessions as advisory only, not as commit-candidate
  approval.
- Clear the reviewer context before each advisory request when the CLI supports
  it, for example with `/clear`.
- Send a compact prompt or changed-file summary rather than the full review
  context whenever possible.
- Save any useful advisory finding in the work notes, diff, or feedback queue;
  do not rely on hidden reviewer session memory as evidence.
- Run the normal stateless `./scripts/review-gate.sh` for final commit-candidate
  judgment whenever the project's review-intensity policy requires it.

The final gate remains stateless because `review-gate` writes review context,
prompts, manifests, outputs, disabled reviewer state, and summaries as
reproducible artifacts. A warm session with `/clear` can reduce iteration cost,
but it does not replace those artifacts.

## Failure-Pattern Feedback

Record a feedback item when it has reuse value, not for every transient mistake.

Record when any of these are true:

- the same repeat key appears 2 or more times
- a failure blocks verify, review, commit, push, deploy, or onboarding
- manual user intervention was required
- an AI made a wrong assumption that caused rework
- a project-local fix should become an AI_AUTO template improvement

Do not record:

- secrets, credentials, tokens, customer data, private logs, or copied stack
  traces that contain sensitive context
- one-off typos with no reuse value
- speculative ideas that were not accepted as future guidance
- raw generated output when a short symptom/cause/resolution summary is enough

Use:

```bash
./scripts/record-feedback.sh \
  --type failure_pattern \
  --repeat-key git:index-lock-permission \
  --summary ".git/index.lock permission denied during commit" \
  --resolution "Use the approved escalated git commit path in this environment" \
  --severity medium
```

Feedback is written to `.omx/feedback/queue.jsonl`. `.omx/` is ignored by git,
so raw project feedback stays local by default.

When a feedback item has been handled, mark it instead of deleting it:

```bash
./scripts/resolve-feedback.sh \
  --repeat-key git:index-lock-permission \
  --note "Template guidance updated"
```

Use `status=resolved` for accepted and completed work, `ignored` for items that
were reviewed and intentionally rejected, and `deferred` when the item remains
valid but is not in the current implementation scope. Missing status on older
queue entries is treated as `open`.

## Subagent Utilization

The leader owns scope, integration, final verification, and user-facing claims.
Use subagents only when a bounded lane can improve speed, quality, or risk
coverage without blocking the immediate next step.

Good subagent lanes:

- repo lookup and symbol mapping
- focused implementation slices with disjoint write ownership
- test strategy or verification review
- UX/design review for UI work
- dependency or official-doc research
- independent critique of a plan or risky diff

Do not delegate:

- destructive actions, credentialed operations, production deploys, or commits
  and pushes
- auth, authorization, validation, crypto, credential handling, PII, external
  data boundaries, schema/API contracts, migrations, or serialization behavior
- ambiguous scope decisions that require user judgment
- the final integration decision or completion claim
- work that would duplicate the leader's immediate critical path

### Low-Cost Coding Lane

For token efficiency, the leader may delegate bounded implementation work to
the current low-cost Codex coding lane when runtime evidence shows that lane is
available.
Acceptable runtime evidence includes the active model-routing report, an
explicit session configuration value, or another auditable runtime capability
signal.

Use this lane for:

- exact-file implementation slices with clear acceptance criteria
- local test fixes or test additions
- mechanical cleanup and narrow refactors
- repo-local code edits that do not alter contracts or security boundaries

Do not use this lane for:

- planning, architecture, or requirements interpretation
- security-sensitive implementation or review
- cross-module integration decisions
- review-gate verdict interpretation
- final user-facing completion claims

The leader must package enough context for the delegated task to be completed
without guessing, require the child agent to escalate ambiguity or scope
expansion, inspect the resulting diff rather than only test output, and run the
project verification gates before accepting the work.

Track delegation quality informally during a session. If the leader rewrites a
significant fraction of low-cost-lane output for correctness or fit (rough
guide: about 20%, not a precise metric), suspend that lane for the task and
finish the work locally or with a stronger role.
When a low-cost lane was used, include the estimated rewrite fraction in the
completion report.
When guardrails do not pass, fall back to the standard implementation lane.

External reviewers such as Claude and Gemini do not directly control Codex
native subagents. They may recommend subagent follow-ups, but the leader decides
whether to spawn them, assigns a narrow task, and reports the result. When an
external reviewer is disabled, Codex fallback review lanes may cover the missing
perspective, but this remains degraded informational coverage and must be
reported as such.

Prefer role selection and reasoning effort over hardcoded model overrides.
Inherit the current runtime model unless a concrete, current runtime-supported
reason exists to override it.

### Resource-Aware Parallelism

Parallelism is adaptive, not a fixed target. Use fewer or no subagents when the
host is resource constrained, another session is running heavy review or
backtest work, or the environment has shown instability such as forced
Ubuntu/WSL shutdowns.

At onboarding time, inspect local resource evidence before asking the user:
CPU count, memory, disk space, load average, and whether obvious heavy
processes are already running. Then ask only for constraints the agent cannot
reliably infer, such as prior Ubuntu/WSL forced shutdowns, thermal limits,
concurrent long-running sessions, and the user's preferred maximum parallelism.

Default to one lane for small edits and documentation updates. Increase
parallelism only when the work is independent, bounded, and worth the extra CPU,
memory, and I/O load. Record the chosen resource profile in
`.omx/state/session-checkpoint.md` when a long-running workflow continues after
a checkpoint.

## Planning And Interview Escalation

Default posture: act directly when the request is clear, narrow, and reversible.
Do not interview for routine edits, small fixes, local documentation updates,
or commands the user already requested.

Use `docs/INTERVIEW_PLAN_LAYER.md` as the contract for interview and planning
work. Its core rule is decision-width minimization: do not minimize user
questions by increasing hidden AI assumptions.

Autonomy applies only after the user has clearly requested execution. Do not
treat feasibility questions, advice requests, recommendations, brainstorming,
or "could we/should we/how would we" prompts as permission to edit files, run
verification, install helpers, or start long-running commands. For those
prompts, answer with the likely approach, expected scope, verification plan, and
the explicit command or instruction that would start execution.

Before implementation, inspect the expected command, module, and domain shape.
If the work is likely to span multiple command groups, business domains, or
long-lived maintenance areas, document the module boundaries in the plan before
writing code. A single entrypoint is acceptable for small surfaces, but do not
grow a monolithic command file when complexity is already visible during
planning.

Escalate to a short interview when one decision would materially change the
result. Ask one concise question, then proceed from the answer.

Fail closed on material ambiguity:

- If the user request, operating input, target project, or approval boundary is
  ambiguous and a wrong assumption would change behavior, risk, cost, or
  persistence, ask before acting.
- Do not hide an assumption inside best-effort execution when the missing answer
  determines whether work should proceed, stop, or be analysis-only.
- Proceed from a labeled assumption only for safe, reversible work where the
  assumption does not change the user's intended outcome.

Escalate to a plan-first interview when the task involves any of these:

- broad words such as foundation, standard, strategy, architecture, workflow,
  policy, automation, onboarding, or hardening
- long-lived guidance files such as `AGENTS.md`, `docs/WORKFLOW.md`,
  `scripts/verify.sh`, templates, completion packs, or domain packs
- multiple valid approaches with different cost, safety, or maintenance impact
- data loss, security, credentials, deployment, production, billing, or
  irreversible behavior
- unclear success criteria, unknown users, or final deliverables that cannot be
  inferred from local evidence
- a user explicitly asks for interview, planning, or "don't assume"

Recommendation, review, discussion, and brainstorming requests are answer-only
by default. Escalate them to interview/planning only when a user decision is
required to change outcome, risk, cost, durability, approval boundary, or
execution scope.

Use this intensity scale:

| Intensity | Use When | Expected Behavior |
| --- | --- | --- |
| `none` | Small, clear, reversible task | Execute, verify, report |
| `light` | One material branch or missing fact | Ask one question, then execute |
| `standard` | Several choices shape the outcome | Inspect evidence, ask 2-4 focused questions, write a short plan, then execute |
| `deep` | High-risk, long-lived, or strategic work | Run a staged interview, produce a plan/test shape, optionally request reviewer/subagent critique, then execute only the approved/safe slice |

When interviewing, first inspect local files and ask only for facts that cannot
be inferred safely. Prefer many narrow, concrete questions over a few broad
questions. Map answers into concrete plan fields, track ambiguity with the
`docs/INTERVIEW_PLAN_LAYER.md` ambiguity rules, and apply its
`ready_to_execute` gate only for full-schema lanes such as initial onboarding,
`deep` interviews, rebuild planning, migration, production, credentialed, data,
or materially scope-changing work. Label assumptions explicitly. If the user
says "바로 진행", skip interview only for safe and reversible work; keep
approval gates for destructive, credentialed, production, or materially
scope-changing actions.

## Auxiliary Rebuild Tool Gates

Auxiliary rebuild tools are optional support gates, not default execution
requirements. Do not install external tools or make normal verification depend
on them unless the user explicitly asks or a project-local policy promotes a
specific gate to required.

Read-only diagnostic gates include:

- context pack: create a local AI-readable repository snapshot for planning
- codemod scan: structurally search for migration or refactor candidates
- boundary check: scan for forbidden imports, old APIs, or domain-boundary leaks
- Python split plan: use domain-pack `split-rules.json` to propose top-level
  function/class moves without editing files

These read-only gates may be suggested or run when available only when local
evidence shows one of these triggers:

- explicit user command for context packing, codemod scan, boundary check, or
  rebuild support
- material large-scope or boundary-changing work, such as module moves, public
  API/signature changes, import-path rewrites, schema/config changes, or shared
  module extraction
- `ai-refactor-scan` or equivalent local evidence identifies a material
  refactor smell above the project threshold
- a domain-critical boundary is touched, such as credentials, production/real
  data, order/execution loops, risk controls, payment, deployment, or security
- required evidence is stale, including context packs, domain-pack assumptions,
  plan artifacts, generated scans, or behavior-locking tests
- repeated verification failure has a structural cause rather than a local typo
- a reviewer finding specifically requests rebuild, refactor, migration, or
  boundary planning

These gates are advisory and fail-open by default. Missing optional tools must
not fail `./scripts/verify.sh`, block normal commit readiness, or interrupt
small safe reversible work. They fail-closed only for rebuild-run, migration,
domain-critical, production/real-data, destructive paths, or when a
project-local policy explicitly makes the gate required.

Write gates are separate. Codemod apply, autofix, or any tool that edits files
must not be triggered automatically by the diagnostic criteria above. It
requires an explicit execution command, an approved scoped plan artifact, exact
target scope, reviewed dry-run diff or summary, rollback path, and post-apply
verification.

For Python rebuilds, `ai-split-plan` may consume
`.omx/domain-packs/<name>/split-rules.json` and write a proposed plan. This is
still advisory. `ai-split-dry-run` must be reviewed before `ai-split-apply`,
and apply requires `--execute-approved-plan` plus completed approval-gate fields.
The splitter is a mechanical top-level symbol mover; it does not rewrite imports
or call sites, so behavior-locking tests remain mandatory for any rebuild run.

## Autonomous Checkpoint Continuation

Long-running autonomous workflows, including Ralph-style execution loops, should
distinguish a useful checkpoint from a stop condition.

If the user has already supplied the objective, boundaries, and decision
principles, a failed search axis or empty candidate set is normally a pivot
point. Record the result, choose the next reasonable axis, and continue within
the delegated scope.

Escalate to the user only when:

- the next axis requires a new business or product decision
- the next action exceeds the delegated scope or accepted principles
- the action is destructive, credentialed, production-facing, or materially
  riskier than the approved lane
- configured time, cost, or resource limits are reached
- the reasonable search space is exhausted and no useful fallback remains

For strategy or research tasks, "no valid candidate found" means "change the
search axis" unless one of the escalation conditions above is true.

## Operational Readiness Fail-Closed

Operational workflows must distinguish analysis from accepted operating output.
Once a workflow claims dry-run validity, promotion readiness, field-start
evidence, or production/operations readiness, required inputs are fail-closed.

Stop the operational path when required inputs are missing, stale, incomplete,
contract-invalid, permission-blocked, or produced by a degraded run. The command
should return a non-ready/non-zero status when practical and persist
machine-readable blocker flags or status artifacts.

Do not silently continue through:

- stale cache reuse
- narrowed scope
- reduced cadence
- placeholder/default values
- restricted or best-effort mode
- partial success from a larger required input set

These fallbacks may be used only when explicitly labeled analysis-only or
diagnostic. Diagnostic reports may be written for partial or degraded runs, but
accepted operating artifacts such as CSV inputs, universe files, promotion
evidence, readiness outputs, or downstream execution inputs must not be written
unless the full required input contract passes.

## Plan Index And TODO Reconciliation

Multi-document plans must designate one current index document as the first
navigation surface. The index should hold active status, immediate next actions,
future work queues, promotion/fallback gates, and links to detailed contracts,
runbooks, matrices, or evidence documents.

When agents split or extend a plan, they should update the index instead of
duplicating full criteria across documents. Answer plan-location questions from
the index first.

Before final reporting from Ralph/team/review-gate/checkpoint workflows, inspect
the current plan index or TODO source of truth. Update changed TODO/status/evidence
or explicitly record that the index is unchanged and why. Do not let a checkpoint
claim completion while the plan index still advertises stale next actions.

## Operational Deployment Preflight

Production, field dry-run, or operational deployment workflows must use
preconfigured read-only network/auth permissions where possible instead of
depending on interactive ad hoc approval mid-run.

Before the operational path begins, preflight the side-effect boundary and the
minimum required inputs, including the relevant database, token/auth state,
cooldowns, output paths, API budget, and read/write permissions. Permission or
preflight failure should fail closed with status artifacts rather than continuing
as if the run were operationally valid.

For external API checks, classify sandbox/network restrictions separately from
provider or user-network failures. If a sandboxed probe reports connection
refusal, timeout, or auth transport noise, retry once through the preconfigured
approved real-network path before blaming the provider, credentials, or local
network. Preserve both sandbox and real-network evidence in status artifacts.

## Incident Ops During Dry-run And Field-test

Use `docs/INCIDENT_OPS.md` when Ralph, team, QA, or a direct agent monitors a
dry-run, field-test, or operational rehearsal. Treat it as a policy layer for
anomaly response, not as permission to mutate external state.

Allowed automatic work is limited to observe, diagnose, safe reversible recovery,
and configured one-shot guarded recovery. Credential changes, production writes,
deployments, repeated external calls, orders, cancellations, position changes,
payments, deletion, or unknown side-effectful actions require approval or are
blocked by policy.

Every incident response must write an incident log with the trigger, phase,
severity, action class, decision, exact automatic action, pre/post evidence,
sandbox and approved real-network evidence when relevant, UI evidence when UI is
in scope, next approval boundary, and remaining risk.

Long-running monitoring must report status on a project-specific cadence instead
of staying silent until completion. Define heartbeat, quiet, and active-incident
reporting intervals during onboarding or before the run starts.

## Failure-Mode Inventory Before Expansion

Before broadening operational dry-run, deployment, collector, or scheduler
behavior, list plausible failure modes and map current defenses, blocker flags,
runbook coverage, and targeted-test needs. Defer live or chaos-style tests until
affected modules are split enough to observe safely, existing defenses are
verified, and the test scope is explicit.

## Guidance And Context Budget

Keep durable operating principles in `AGENTS.md`, but move detailed procedures,
examples, long checklists, volatile runbooks, and domain-specific matrices into
linked docs. When users repeatedly ask to add project instructions, check whether
the guidance belongs in a split document before appending to `AGENTS.md`.

Track context budget qualitatively during long sessions. If the main instruction
surface is becoming hard to scan, add a cleanup TODO or linked guidance document
instead of continuing to append every operational lesson directly.

## Onboarding Interview Structure

For new template installation, run `aiinit` when requested, then use
`docs/INTERVIEW_PLAN_LAYER.md` before feature work. For existing initialized
projects or registry-only onboarding, start from local evidence and the
interview layer without reinstalling the template. Keep the interview narrow but
complete enough to replace the template placeholders with project-specific
rules. Inspect local evidence first, ask one decision at a time, map each answer
to the target project baseline, and stop at a plan/report boundary before
commits, pushes, destructive actions, credentials, production, or materially
scope-changing execution.

Use this order:

1. Existing evidence: read README, docs, package files, scripts, and old notes
   before asking.
2. Outcome: purpose, users, final deliverable, and non-goals.
3. Scope and safety: allowed changes, forbidden changes, data/secret/credential
   boundaries, and destructive-operation rules.
4. Stack and commands: runtime, setup, test, build, lint, smoke, and deploy
   commands.
5. Completion packs: select or reject UI, deployment, security, data,
   performance, and observability packs.
6. Domain packs: follow `docs/DOMAIN_PACKS.md` to select, reject, or defer
   installed `.omx/domain-packs/` references. Use
   `docs/DOMAIN_PACK_AUTHORING_GUIDE.md` only when creating or changing reusable
   source packs.
7. Operating policy: review intensity, feedback recording, approval-friction
   handling, subagent usage expectations, and resource-aware parallelism. Before
   asking, inspect local CPU, memory, disk, and load evidence; then ask about
   unknown hardware/runtime constraints such as WSL shutdown history or other
   active heavy sessions.
8. Operational readiness: required inputs, fail-closed blockers, accepted
   operating artifacts, read-only/auth/network preflight, and analysis-only
   fallback rules.
9. Incident Ops: dry-run/field-test monitoring policy, incident log contract,
   automatic action classes, UI field-test evidence, and periodic reporting
   cadence.
10. Plan management: current plan index, TODO reconciliation expectations, and
   where detailed runbooks/checklists live.
11. Verification contract: exact `scripts/verify.sh` checks and evidence needed
   before claiming completion.
12. Decision record: write confirmed rules into `AGENTS.md`, `docs/WORKFLOW.md`,
   and `scripts/verify.sh`; record rejected packs as non-goals.

Ask only for information that cannot be inferred safely from local evidence.
When proceeding from an assumption, label it as an assumption and keep the
change reversible.

## Promotion Policy

AI_AUTO may later collect project feedback queues and promote only sanitized,
generalizable patterns into versioned guidance.

Promotion targets:

- repeated environment failures -> `docs/WORKFLOW.md`, `AGENTS.md`, or doctor
  diagnostics
- repeated onboarding gaps -> template onboarding interview guidance
- repeated verification gaps -> template `scripts/verify.sh` or completion packs
- repeated review noise -> review-intensity policy adjustments

Do not promote raw project logs. Promote a short pattern with:

- repeat key
- symptom
- likely cause
- safe resolution
- affected surface
- confidence
- evidence count

SQLite or another database may be added later as a local search/index cache, but
the source of truth should remain reviewable text files (`jsonl` and markdown)
so changes can be diffed, reviewed, committed, and distributed through git.

## Approval Friction

Do not bypass safety approval for destructive, credentialed, external-production,
or materially scope-changing actions. Reduce approval friction by making common
safe paths explicit and repeatable.

Preferred order:

1. Use repo-owned helper scripts for safe repeated operations.
2. Use narrow approved command prefixes for non-destructive recurring commands
   such as verification, review gate, helper installation, commit, and push.
3. Use preflight checks (`automation-doctor`, `workspace-scan`, `git status`) to
   find permission or environment blockers before long work starts.
4. Use `REVIEW_EXECUTION_MODE=external` only when the agent runtime cannot access
   reviewer CLIs but the user's interactive terminal can.
5. Record repeated permission blockers as feedback patterns instead of silently
   retrying the same failing command.

Still require explicit approval for:

- deleting data, resetting git state, overwriting project instructions, or
  removing user files
- installing dependencies or external programs
- using credentials, production SSH, deployment targets, or paid external APIs
- changing permission boundaries rather than using an approved narrow command
  path
