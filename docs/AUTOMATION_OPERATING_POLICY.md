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

For token efficiency, the leader may delegate bounded implementation work to the
current low-cost Codex coding lane only when the routing evidence in
`docs/AI_MODEL_ROUTING.md` shows that lane is available.

Allowed shapes: exact-file implementation slices with clear acceptance
criteria, local test fixes or additions, mechanical cleanup, narrow refactors,
and repo-local code edits that do not alter contracts or security boundaries.
Forbidden shapes: planning, architecture, requirements interpretation,
security-sensitive work, cross-module integration decisions, review-gate verdict
interpretation, and final completion claims.

The leader must package enough context, require escalation for ambiguity or
scope expansion, inspect the resulting diff rather than only test output, and
run project verification gates before accepting the work. If the leader rewrites
a significant fraction of low-cost-lane output for correctness or fit (rough
guide: about 20%), suspend that lane for the task and finish locally or with a
stronger role. Report the estimated rewrite fraction when the lane was used.

External reviewers such as Claude and Gemini do not directly control Codex
native subagents. They may recommend subagent follow-ups, but the leader decides
whether to spawn them, assigns a narrow task, and reports the result. When an
expected reviewer is disabled, the active principal's subagent substitute may
cover that lane as degraded coverage, not independent external review. With a
usable verdict and direct file inspection evidence it is reported as
proceed_degraded with degraded trust; otherwise the gate reports blocked coverage.

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
mechanics. Keep decision-width minimization: do not reduce user questions by
increasing hidden AI assumptions.

Autonomy applies only after the user has clearly requested execution. Do not
treat feasibility questions, advice requests, recommendations, brainstorming,
or "could we/should we/how would we" prompts as permission to edit files, run
verification, install helpers, or start long-running commands. For those
prompts, answer with the likely approach, expected scope, verification plan, and
the explicit command or instruction that would start execution.

Before implementation, inspect the expected command, module, and domain shape.
If likely to span multiple command groups, business domains, or long-lived
maintenance areas, document module boundaries before writing code.

Escalate to a short interview when one decision would materially change the
result. Ask one concise question, then proceed from the answer.

Fail closed on material ambiguity:

- If the user request, operating input, target project, or approval boundary is
  ambiguous and a wrong assumption would change behavior, risk, cost, or
  persistence, ask before acting.
- Do not hide an assumption inside best-effort execution when the missing answer
  determines whether work should proceed, stop, or be analysis-only.
- For follow-up meta requests about root cause, guidance, or recurrence, anchor
  to the failure event the user identified. If the target may also mean an
  adjacent technical topic, ask before proposing or editing guidance.
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
be inferred safely. Map answers into concrete plan fields, use
`docs/INTERVIEW_PLAN_LAYER.md` for ambiguity and `ready_to_execute` gates, and
label assumptions explicitly. If the user says "바로 진행", skip interview only
for safe reversible work; keep approval gates for destructive, credentialed,
production, or materially scope-changing actions.

## Post-Code Spec/Design Alignment

After code edits and before final reporting, compare the final diff with the
applicable plan/spec/design artifact when one exists. Scope the comparison to
artifacts that are named by the user, linked from the current plan index, or
directly govern the touched behavior. Do not search every historical document
for small direct tasks.

First decide whether an applicable artifact exists. For `none`, `light`, or
`standard` work, report the alignment result as `not applicable` if no relevant
artifact exists. For `deep` or full-schema work, treat a missing governing
artifact as a planning gap instead.

Use the existing intensity model only to size the comparison:

- `none`: do not add an alignment search; compare only if the user or active
  task already named a governing artifact.
- `light`: compare only the named artifact or TODO/source-of-truth.
- `standard`: compare the diff against accepted scope, non-goals, success
  criteria, execution boundaries, and verification plan.
- `deep`: require an explicit artifact status: `aligned`, `updated`, or
  `blocked`. A deep/full-schema lane is expected to have a governing artifact;
  treat its absence as a planning gap, not `not applicable`.

When a mismatch exists, classify it before continuing:

- implementation drift: the code exceeds or contradicts a still-current
  artifact. Fix or revert the implementation, or split the extra work into a new
  plan/approval.
- outdated spec drift: the artifact is stale but the implementation remains
  inside the approved user intent and scope. Update the artifact when
  documentation edits are in scope; otherwise report the drift as a limitation.
- material scope change: updating the artifact would change goals, non-goals,
  risk, data, security, deployment, user-visible behavior, or approval
  boundaries. Stop implementation and return to planning/approval.
- partial implementation: the code implements an approved subset without
  contradicting the artifact. Report what is complete and what remains; continue
  only when the requested completion criteria still require it.

Do not update a plan/spec/design artifact merely to justify unauthorized code.
Completion reports should state the alignment result: `aligned`, `updated`,
`not applicable`, or `blocked`.

## User-Facing Report Language

User-facing progress and completion reports should be written in clear Korean by
default. Avoid exposing internal variable names, constants, flags, or raw
implementation identifiers as the main explanation. Translate the result into
plain user terms first, then include commands, file paths, review verdicts, or
technical identifiers only when they are needed for reproduction, verification,
or user action.

Do not make users infer meaning from internal names. For example, say that the
design check was not applicable because no related planning artifact existed,
instead of only reporting an internal status value.

## Planning Artifact Language

New planning, strategy, architecture, and operations artifacts should be written
in Korean by default when they are meant for project-owner review or long-term
operation. Keep commands, file paths, verdicts, status values, schema fields,
code identifiers, and other machine-readable names in English.

Existing English documents should remain English unless the user explicitly
asks for translation or the document is already being revised for that purpose.
Prefer adding a concise Korean summary to rewriting a large existing document
when the goal is operational understanding rather than language cleanup.

## Review Context Integrity

Reviewer context limits must not be handled by silently compressing, head/tail
truncating, or summarizing away source material while still asking for a normal
approval. If a review context exceeds the configured reviewer budget, split it
into ordered parts with a manifest and require an explicit synthesis over every
part before accepting a final verdict.

Fallback Codex/GPT reviews should inspect relevant repository files directly
from the workspace instead of relying only on a shortened prompt. A fallback
verdict should list the files inspected and any relevant files that could not be
inspected.

## Guidance Budget Escalation

Treat guidance bloat control as a staged workflow.

Stage 1 is the normal guidance budget check. It may run during verification and
should report document-volume warnings to the user. A warning is evidence to
recommend the next review step, not approval to edit guidance.

When a long-lived branch already contains unrelated accumulated guidance bloat,
set `DOC_BUDGET_COMPLETION_BASE_REF` to the task or Ralph-run starting commit.
`scripts/doc-budget.sh` still reports the branch-cumulative diff against
`main`, but the hard failure applies to the completion-scoped diff from that
baseline. Report both numbers so implementation completion is not confused with
branch-integration guidance debt. The verify launcher auto-derives this baseline
from validated launcher evidence (`ai-principal-runtime.sh completion-base`, the
recorded launch-time HEAD that is still an ancestor of the current HEAD), so the
env var is only needed to override; with no or invalid evidence the measurement
safely falls back to branch-cumulative. A project that sets the baseline in its
OWN `scripts/verify.sh` must use the auto-deriving form, never a hardcoded commit
(a pinned anchor goes stale and then hard-fails unrelated work on a long-lived
branch): `DOC_BUDGET_COMPLETION_BASE_REF="${DOC_BUDGET_COMPLETION_BASE_REF:-$(./scripts/ai-principal-runtime.sh completion-base 2>/dev/null)}"`.

Stage 2 is a read-only duplicate or consolidation report, typically produced by
`scripts/guidance-duplicate-report.sh`. Run it only when the user asks for that
report after seeing the Stage 1 recommendation. The report should identify
likely repeated rules, candidate source-of-truth locations, and possible
deletions without changing files. Prefer existing duplicate-detection tools such
as `jscpd` when available; use the local fallback only when the distributed tool
is unavailable or inappropriate.

Guidance slimming or source-of-truth rewrites require a separate user decision
after the Stage 2 report, because they can change long-lived operating
contracts.

## No-Code Before New Code

The first implementation option is no new code. Before adding code, check
whether the request can be satisfied by removing the underlying problem, using
existing behavior, changing configuration, improving documentation, deleting
unneeded code, or simplifying the workflow.

If new code is still necessary, keep it to the smallest verifiable change and
then apply the tool-adoption rule below before building custom automation.

## Tool Adoption Before Custom Development

Before adding a new automation feature, first look for an existing maintained
tool, package, or CLI that already solves the core problem. Prefer wrapping or
configuring an available tool over building custom logic when the tool is
usable, reasonably maintained, compatible with the project's licensing and
runtime constraints, and can run in a read-only or reversible mode for the
needed workflow.

Build a custom tool only when available tools are unsuitable, unavailable in the
target environment, too risky for the approval boundary, or would add more
operational burden than the small project-local implementation.

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

1. Existing evidence: read README, docs, package files, scripts, old notes,
   `(old)/`, and domain notes before asking.
2. Outcome: purpose, users, final deliverable, and non-goals.
3. Scope and safety: allowed changes, forbidden changes, data/secret/credential
   boundaries, and destructive-operation rules.
4. Stack and commands: runtime, setup, test, build, lint, smoke, and deploy
   commands.
5. Completion packs: select or reject UI, deployment, security, data,
   performance, and observability packs; delete unused `docs/*_COMPLETION.md`
   files only after recording them as non-goals and only if they would clutter
   the target project.
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
