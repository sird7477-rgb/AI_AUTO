# GStack Benchmark Ralph Deep Dive

Date: 2026-05-28

Context snapshot:

- `.omx/context/gstack-benchmark-ralph-20260528T001954Z.md`

Primary benchmark artifact:

- `plans/GSTACK_BENCHMARK.md`

## Scope Lock

This Ralph run applies the deep analysis to the benchmark and planning
artifacts. It does not approve immediate runtime adoption of GStack, a new
persona roster, a second memory layer, autonomous release commands, persistent
browser state, or parallel sprint execution.

Execution in this run means:

- analyze AI_AUTO and GStack at micro level
- map useful GStack concepts to AI_AUTO surfaces
- harden the benchmark plan
- define review hierarchy and adoption sequencing
- record blockers and deferrals

Runtime/code adoption requires a later approved phase with its own scope,
evidence, and verification.

## Source Evidence

Local sources:

- `AGENTS.md`
- `docs/AI_ROLES.md`
- `docs/AI_MODEL_ROUTING.md`
- `docs/MULTI_AI_COLLABORATION.md`
- `docs/OBSIDIAN_INTEGRATION.md`
- `docs/AUTOMATION_OPERATING_POLICY.md`
- `scripts/review-gate.sh`
- `scripts/run-ai-reviews.sh`
- `scripts/verify.sh`
- `scripts/reflection_contracts.py`
- `tests/test_reflection_contracts.py`
- `plans/GSTACK_BENCHMARK.md`
- `plans/AI_AUTO_REFLECTION_LOOP_V1.md`
- `plans/AI_AUTO_REFLECTION_LOOP_V1_PHASE0.md`
- `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`

External sources checked:

- `https://github.com/garrytan/gstack`
- `https://raw.githubusercontent.com/garrytan/gstack/main/README.md`
- `https://raw.githubusercontent.com/garrytan/gstack/main/docs/skills.md`
- `https://raw.githubusercontent.com/garrytan/gstack/main/ARCHITECTURE.md`
- `https://raw.githubusercontent.com/garrytan/gstack/main/CLAUDE.md`
- `https://gstacks.org/`
- `https://gstack.lol/`
- `https://deepwiki.com/garrytan/gstack`

Source caveat:

- GStack public sources describe different counts across time and surfaces:
  nine skills, 18 specialists, 23 tools, 31+ skills, or 20+ agents depending on
  source and date. Treat the exact count as unstable. The benchmark should use
  stable workflow concepts and persona lenses, not rely on a fixed role count.

## AI_AUTO Micro Analysis

### Strengths

1. Clear authority chain
   - AGENTS.md and linked docs define repository behavior.
   - `verify.sh` is the mechanical verifier.
   - `review-gate.sh` is the final review gate.
   - Human approval remains final for commit/push.

2. Existing multi-review foundation
   - Claude and Gemini reviews are integrated through `run-ai-reviews.sh`.
   - Codex/GPT fallback is separately reported as degraded/informational.
   - Review manifests and disabled reviewer state are persisted.

3. Verification breadth
   - Tests, shell syntax, doc budget checks, template sync, bootstrap/doctor,
     and Docker smoke checks are already part of verification.

4. Knowledge loop foundation
   - Obsidian integration, local knowledge drafts, feedback collection,
     Reflection Loop plans, and promotion boundaries exist.

5. Safety posture
   - Sandbox boundaries, privacy blocking, review-gate discipline, template
     patch rules, and no-commit/no-push rules are documented.

6. Portable role model
   - AI_AUTO already uses AGENTS.md, skills, helper scripts, and role-routing
     docs instead of a provider-specific authority file.

### Weaknesses / Gaps

1. Artifact sync is still process-based
   - The GStack benchmark already documented a missed late finding.
   - Reflection Loop has not yet fully absorbed artifact sync as a gate.

2. Multi-session/worktree execution is not governed
   - Current parallelism covers native subagents and OMX lanes better than
     independent worktree sprint ownership.

3. Review hierarchy is not formalized
   - Micro, small-group, mid-group, and overall review layers were user-defined
     for this Ralph run but did not previously exist as an artifact.

4. Guidance volume pressure exists
   - Existing doc-budget warning shows the guidance surface is already large.

5. UI source-of-truth hierarchy is incomplete
   - UI reference flow exists, but user-provided design templates need explicit
     priority over generic external references.

6. Self-demo validation is not yet a first-class gate
   - Feature upgrades can be verified mechanically, but user-facing workflow
     demos are not yet consistently required for module/guidance upgrades.

## GStack Micro Analysis

### Stable Useful Concepts

1. Think before build
   - `/office-hours` and CEO review challenge whether the requested solution is
     the right problem and what the smallest useful wedge is.

2. Plan review by lens
   - Product, engineering, design, DX, and security each look for different
     failure modes.

3. Artifact chaining
   - Design docs, plan reviews, test plans, QA evidence, release reports, and
     retrospectives feed the next stage.

4. Real-browser QA
   - Browser interaction, screenshots, console/network evidence, and regression
     capture are treated as first-class evidence.

5. Report-only QA option
   - `/qa-only` is a useful model for safe analysis before allowing fix loops.

6. Release discipline
   - `/ship`, `/land-and-deploy`, `/canary`, and `/benchmark` encode release,
     production verification, post-deploy monitoring, and performance checks.

7. Retro discipline
   - `/retro` turns delivery outcomes and repeated failures into learning.

8. Safety and scope tools
   - `/careful`, `/freeze`, and `/guard` show a useful pattern for bounded edit
     scopes and destructive-action caution.

9. Persona lenses
   - CEO, Eng Manager, Designer, QA, CSO, Release Engineer, Technical Writer,
     DX Reviewer, SRE, Performance Engineer, Debugger, and Memory represent
     reusable review perspectives.

### Risks / Weaknesses

1. Authority duplication
   - Installing GStack wholesale would introduce `.claude/`, `CLAUDE.md`,
     slash-command namespace, and GStack state beside AI_AUTO's AGENTS/scripts.

2. Persona sprawl
   - A large standing roster increases context cost, review fatigue, and
     ambiguity over who owns final authority.

3. Browser/session risk
   - Persistent browser state, cookie import, remote/tunnel pairing, and sidebar
     agents expand credential and prompt-injection risk.

4. Autonomous release risk
   - `/ship`, `/land-and-deploy`, and production canary flows imply git,
     deploy, and production side effects that require explicit human approval in
     AI_AUTO.

5. Memory drift
   - GBrain or `/learn` can become a second memory authority unless forced
     through Reflection/Obsidian promotion.

6. Source/version drift
   - Public GStack materials differ on exact skill/persona counts. Adoption
     should use concept-level matching, not count-level matching.

7. Overfit to web/frontend
   - Browser QA is strong, but backend/headless workflows need separate
     evidence profiles.

## Micro Matching Matrix

| GStack unit | AI_AUTO equivalent | Gap | Disposition | Target surface |
| --- | --- | --- | --- | --- |
| `/office-hours` | Interview/planning policy, no-code-first rule | sharper pre-build challenge | adopt | new product challenge planning surface |
| `/plan-ceo-review` | planner/architect | product reframing lens | modify | product challenge checklist |
| `/plan-eng-review` | architect review / ralplan | compact architecture/test-shape checklist | modify | `ralplan` / planning docs |
| `/plan-design-review` | UI Visual Alignment | user template SoT priority | adopt/modify | Reflection Loop UI layer |
| `/design-review` | visual-ralph / UI completion | live visual evidence discipline | modify | UI completion + visual workflow |
| `/plan-devex-review` | docs/workflow checks | TTHW/dev onboarding lens | defer/optional | docs/devex checklist |
| `/review` | `review-gate.sh` | no core gap | reject duplicate | keep review-gate authoritative |
| `/codex` | Codex fallback | trust-boundary handling | keep existing | review-gate summaries |
| `/cso` | security completion pack | named security trigger | modify | optional security-review lane |
| `/browse` | Playwright/CDP guidance | evidence schema | adopt schema only | UI/browser QA docs |
| `/qa` | tests + smoke + visual checks | real-browser QA loop | modify | report-only first, fix later |
| `/qa-only` | read-only QA review | safe audit pattern | adopt | browser QA checklist |
| `/ship` | completion/report/review-gate | release checklist | defer | deployment completion pack |
| `/land-and-deploy` | deployment completion | production execution | reject until explicit deploy plan | deployment gate only |
| `/canary` | incident/observability docs | post-deploy monitoring | defer | ops plan |
| `/benchmark` | performance completion | perf evidence pattern | optional | performance completion pack |
| `/document-release` | docs alignment rules | stale docs after feature | modify | self-demo/docs update checklist |
| `/document-generate` | docs authoring guides | Diataxis coverage lens | optional | docs completion work |
| `/retro` | Reflection Loop | stable retro draft schema | adopt | Reflection/Obsidian draft |
| `/learn` / GBrain | Obsidian/Reflection/project memory | no need for second memory | reject bypass | Reflection promotion path |
| `/careful` | approval/destructive command rules | destructive command warning UX | mine language only | safety docs |
| `/freeze` | phase/scope lock plans | edit-boundary enforcement idea | defer as small tool | phase guard later |
| `/guard` | safety + scope lock | bundled caution mode | defer | later small-tool audit |
| parallel sprints | subagents/team mode | worktree/conductor model missing | research note | separate parallel sprint plan |
| pair-agent | native subagents / tmux | cross-agent browser coordination | reject for now | security-gated future only |
| design-shotgun/html | UI reference/design workflow | visual option generation | defer | UI design system phase |

## Review Hierarchy For This Benchmark

### Micro Unit Review

Unit:

- one GStack concept, one AI_AUTO surface, or one benchmark section

Allowed reviewers:

- Codex/GPT lead review
- native subagent review
- Gemini for important uncertain units

Claude use:

- not required by default

Pass condition:

- no unresolved blocker for that micro unit
- disposition is one of `adopt`, `modify`, `defer`, or `reject`
- target authority surface is named when disposition is `adopt` or `modify`

### Small-Group Review

Unit:

- related micro units grouped by theme:
  - AI_AUTO state
  - GStack state
  - persona/guidance
  - browser/UI/QA
  - security/release/memory
  - parallel/conductor

Allowed reviewers:

- Gemini and/or GPT substitute
- Claude only when the group is high-risk or materially changes authority

Pass condition:

- no contradiction between included micro units
- persona sprawl and authority conflicts are explicitly assessed
- routine small tasks are not burdened with mandatory new lanes

### Mid-Group Review

Unit:

- the synthesized benchmark upgrade before final plan adoption

Required reviewers:

- Claude when available
- Gemini when available
- GPT substitute accepted as formal-equivalent only when a reviewer limit,
  quota, or session failure occurs in this Ralph run

Pass condition:

- all available reviewers approve or approve with non-blocking notes
- any degraded/fallback reviewer is labeled
- no reviewer requests revision
- `consensus` or `unanimous` language at this layer also requires recorded
  reviewer eligibility, independence, context completeness, and zero blocking
  findings.

### Overall Review

Unit:

- repository state after benchmark artifact updates

Required checks:

- `git diff --check`
- `./scripts/verify.sh`
- `./scripts/review-gate.sh`

Pass condition:

- `review-gate.sh` returns `proceed`, or the user-approved GPT substitute rule
  is invoked due to reviewer session limit and recorded as degraded for this
  Ralph run only.

## Adoption Plan

Implementation surface for this Ralph execution:

- `docs/GSTACK_ADOPTION_CHECKLISTS.md`
- `scripts/gstack_benchmark_contracts.py`
- `tests/test_gstack_benchmark_contracts.py`

This implements Phase A-F as side-effect-free checklists and pure contracts.
It does not install GStack, add standing personas, start browser automation,
push to Obsidian, merge, deploy, or start parallel worktrees.

### Phase A. Product Challenge

Goal:

- Add a read-only product challenge surface before broad or strategic plans.

Micro units:

1. Define trigger rules:
   - use for broad, high-cost, ambiguous, strategic, or product-shaping work
   - skip for small maintenance, typo fixes, and already-scoped patches
2. Define output fields:
   - problem restatement
   - smallest useful wedge
   - non-goals
   - risks
   - acceptance evidence
   - decision: proceed / narrow / ask / reject
3. Map to authority:
   - planning skill or `docs/AUTOMATION_OPERATING_POLICY.md`
   - no new runtime authority
4. Self-demo:
   - run against one existing rebuild plan and one small maintenance task
   - prove it triggers only for the former

Status:

- implemented as `product_challenge_contract()` and checklist guidance.
- Micro pass requires broad/strategic triggers, explicit output fields, and
  skip behavior for small maintenance.

### Phase B. UI / Browser QA Evidence

Goal:

- Import GStack's browser QA discipline without importing persistent browser
  state or cookie workflows.

Micro units:

1. Standard evidence fields:
   - URL or route
   - viewport matrix
   - screenshot artifacts
   - console/network status
   - user path
   - regression test or deferred reason
2. Separate modes:
   - report-only QA first
   - fix loop only after explicit execution scope
3. UI source-of-truth:
   - user design template > existing project screen > external reference
4. Security boundary:
   - browser state remains credential-equivalent
   - authenticated persistent browser workflows require separate approval

Status:

- implemented as `browser_qa_contract()` and checklist guidance.
- Micro pass requires evidence metadata and explicit approval for persistent
  authenticated browser state.

### Phase C. Retro / Reflection Draft

Goal:

- Convert repeated failures and delivery outcomes into sanitized local drafts.

Micro units:

1. Define draft fields:
   - repeated failure
   - gate that caught it
   - gate that missed it
   - evidence
   - proposed test/guidance/doc update
   - privacy scan summary
2. Keep Obsidian non-authoritative:
   - no automatic runtime behavior from notes
   - promotion requires review-gate
3. Add self-demo:
   - simulate one review-gate failure and ensure only sanitized draft data is
     proposed

Status:

- implemented as `retro_draft_contract()` and checklist guidance.
- Micro pass requires privacy blocking and no Obsidian runtime authority.

### Phase D. Persona / Operating Guidance Comparison

Goal:

- Use GStack personas as review lenses, not as a standing team roster.

Micro units:

1. Build a comparison matrix:
   - persona
   - AI_AUTO equivalent
   - missing lens
   - duplication risk
   - disposition
   - authority surface
2. Require task-shape triggers:
   - product challenge for broad product work
   - design lens for UI work
   - browser QA for browser-facing work
   - security lens for auth/secrets/data/deploy
   - release lens for deployment/ship candidates
   - retro lens for repeated failure or end-of-phase reflection
3. Reject standing roster:
   - no 20+ always-on personas
   - no new default mandatory review lanes for routine work

Status:

- implemented as `persona_lens_contract()` and checklist guidance.
- Micro pass requires task-shape triggers and rejects standing persona rosters.

### Phase E. Security / Release / Ops Lenses

Goal:

- Borrow GStack's CSO/release/SRE thinking without importing autonomous
  production side effects.

Micro units:

1. Security trigger:
   - auth, secrets, tokens, cookies, browser state, PII, data retention,
     production-adjacent workflows
2. Release checklist:
   - tests
   - docs
   - rollback
   - monitoring
   - user-facing summary
3. Explicit non-goals:
   - no auto merge
   - no auto deploy
   - no production canary without approval

Status:

- implemented as `security_release_ops_contract()` and checklist guidance.
- Micro pass requires conditional triggers and rejects autonomous merge, deploy,
  or canary behavior.

### Phase F. Parallel Sprint / Conductor Research

Goal:

- Preserve the observation that GStack's parallel sprinting is a separate
  operating model from subagent parallelism.

Micro units:

1. Define required contract before adoption:
   - worktree ownership
   - branch owner
   - conductor
   - integration gate
   - lock strategy
   - duplicate draft strategy
   - reviewer coverage
2. Keep it out of current V1 runtime:
   - no automatic multi-worktree sprint until separate plan and dry-run exist

Status:

- implemented as `parallel_conductor_contract()` and checklist guidance.
- Micro pass requires research-only behavior unless a separate parallel
  execution plan is approved.

## Execution Review Ledger

Micro implementation:

- Phase A Product Challenge: implemented as pure contract and test.
- Phase B UI / Browser QA Evidence: implemented as pure contract and test.
- Phase C Retro / Reflection Draft: implemented as pure contract and test.
- Phase D Persona / Operating Guidance Comparison: implemented as pure contract
  and test.
- Phase E Security / Release / Ops Lenses: implemented as pure contract and
  test.
- Phase F Parallel Sprint / Conductor Research: implemented as pure contract and
  test.

Small-group review:

- Product Challenge, UI/Browser QA, Retro/Reflection, Persona/Guidance,
  Security/Release/Ops, and Parallel/Conductor groups are represented in
  `docs/GSTACK_ADOPTION_CHECKLISTS.md`.
- Routine small tasks remain exempt from new mandatory lanes.
- All adopted lenses map to existing AI_AUTO authority surfaces or pure
  side-effect-free contracts.

Mid-group review:

- Native planner and test-engineer subagents approved the docs + pure-contract
  implementation shape.
- Critic review remains required before final overall review.
- Claude/Gemini reviewer status is recorded through mid/overall review
  commands. If Claude is unavailable due to session limit, GPT substitute review
  is accepted for this Ralph run only and labeled degraded.

Overall review:

- Required after all edits: targeted tests, `git diff --check`,
  `./scripts/verify.sh`, and `./scripts/review-gate.sh`.

## Current Ralph Review Ledger

Micro analysis:

- AI_AUTO current-state subagent: passed with gaps noted.
- GStack research subagent: passed with selective-absorption conclusion.
- Mapping architect subagent: passed with adoption matrix.
- Critic subagent: rejected broad execution until scope lock, review hierarchy,
  and phase/status source of truth are explicit.

Resolution:

- This document adds the missing scope lock and review hierarchy.
- Broad runtime adoption remains deferred.
- The current execution is limited to benchmark-plan hardening.

## Completion Criteria For This Ralph Run

- `plans/GSTACK_BENCHMARK.md` links to this deep dive and reflects the revised
  review hierarchy and adoption boundaries.
- Mid-group AI review is run against the updated benchmark plan.
- Overall repository verification passes.
- Review language distinguishes approval, degraded substitute review, and
  unavailable reviewers.
- Phase A-F execution is represented by side-effect-free contracts and tests,
  not by runtime GStack adoption.
