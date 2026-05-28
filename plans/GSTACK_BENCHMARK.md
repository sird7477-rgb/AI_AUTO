# GStack Benchmark For AI_AUTO/OMX

Date: 2026-05-28

## Summary

GStack is a useful benchmark, but it should not be installed as a second
operating layer over AI_AUTO/OMX. The practical path is selective absorption:
borrow the product challenge, design review, browser QA, release discipline, and
retro patterns while keeping AGENTS.md, OMX skills, review-gate, and Reflection
Loop as the authority surfaces.

Decision: do not adopt GStack wholesale for now.

Recommended adoption style:

1. Add GStack-style product challenge as a pre-plan/read-only gate.
2. Strengthen UI/design review with anti-slop and reference-extraction checks.
3. Convert browser QA ideas into AI_AUTO Playwright/CDP verification patterns.
4. Feed retro patterns into Reflection Loop and Obsidian drafts.
5. Keep security review as an explicit optional lane for security-sensitive work.
6. Record GStack parallel sprints as an operating-model observation only; do not
   treat them as an approved AI_AUTO implementation track.
7. Compare GStack operating guidance and agent personas against AI_AUTO's
   current roles, gates, and escalation rules. Absorb useful review lenses, not
   a permanently expanded 20+ persona roster.

Deep Ralph analysis:

- `plans/GSTACK_BENCHMARK_RALPH_DEEP_DIVE.md`

Current execution boundary:

- This benchmark may harden plans and comparison artifacts.
- It does not approve GStack runtime installation, a second authority layer,
  permanent 20+ persona operation, autonomous release/deploy commands, GBrain
  memory adoption, or parallel sprint execution.
- Runtime adoption requires a later approved phase with explicit scope,
  evidence, and review gates.

## Source Snapshot

Public GStack materials describe it as an open-source workflow/skill pack that
turns Claude Code, Codex, and compatible coding agents into a structured virtual
software team. The most relevant claimed workflow is:

- Think: `/office-hours`
- Plan: `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`
- Build: implementation against a brief
- Review: `/review`
- Test: `/qa`
- Ship: `/ship`
- Reflect: `/retro`

The public site also states that GStack can install for Codex with
`./setup --host codex`, and positions itself as a workflow for Claude Code,
Codex, and compatible agents.

Primary sources:

- https://github.com/garrytan/gstack
- https://gstacks.org/
- https://gstack.lol/

Notes on source collection:

- The local deep clone attempt for `garrytan/gstack` was approved and started,
  but it stalled during transfer and was stopped. This benchmark therefore uses
  public web/source references plus independent AI review artifacts rather than
  a local full-repo checkout.
- Public GStack sources differ by date and surface on exact counts such as nine
  skills, 18 specialists, 23 tools, 31+ skills, or 20+ agents. Treat exact
  persona count as unstable. Benchmark stable workflow concepts and persona
  lenses instead of count-level claims.

## Fit With Current AI_AUTO/OMX

AI_AUTO/OMX already has the core primitives GStack tries to provide:

- Role/workflow routing: AGENTS.md, OMX skills, native subagents, `$team`,
  `$ralph`, `$ralplan`
- Review discipline: `./scripts/review-gate.sh`, Claude/Gemini review,
  Codex fallback rules
- Verification discipline: `./scripts/verify.sh`, docker smoke checks,
  targeted tests
- Knowledge loop: Obsidian integration, knowledge drafts, Reflection Loop,
  promotion rules
- Browser/UI surface: Playwright/CDP guidance, visual-ralph, UI reference rules
- Safety: sandbox boundary rules, privacy blocking, approval gates

Therefore, GStack is more valuable as a benchmark than as a dependency.

## Candidate Imports

### 1. Product Challenge Gate

GStack's strongest gap-fill is `/office-hours` and CEO-style challenge before
implementation. AI_AUTO has planning, but it can still benefit from a sharper
read-only step that asks:

- Is this the right problem?
- Is the requested solution too literal or too broad?
- What is the smallest useful wedge?
- What should explicitly not be built?
- What evidence would change the plan?

Implementation shape:

- Add a small `$product-challenge` or `ai-product-challenge` planning surface.
- Keep it read-only.
- Output: problem reframing, non-goals, smallest wedge, risks, acceptance checks.
- Do not trigger it for small maintenance tasks.

Priority: P0.

### 2. Design Slop Review

GStack explicitly separates design review from code review. AI_AUTO already has
visual-ralph and frontend guidance, but a compact anti-slop checklist would make
review results more consistent.

Implementation shape:

- Add a reusable checklist for UI work:
  - reference principles extracted
  - copied visual elements rejected
  - screenshots captured
  - console checked
  - mobile/desktop overflow checked
  - taste pass separated from functional pass
- Reuse the existing `validate_ui_reference` and `visual_qc_result` contract
  direction from Reflection Loop Phase 3.

Priority: P1.

### 3. Browser QA Pattern

GStack emphasizes real-browser QA. AI_AUTO already has Playwright/CDP guidance,
but browser QA can be made more operationally explicit.

Implementation shape:

- Standardize browser QA evidence:
  - target URL
  - viewport matrix
  - screenshot artifacts
  - console/network errors
  - user-path steps
  - regression test created or deferred reason
- Keep persistent browser/session mechanics optional because they expand the
  security and state surface.

Priority: P1.

### 4. Retro To Reflection Loop

GStack's `/retro` maps well to AI_AUTO's Reflection Loop. The useful part is not
another memory store, but a stable retrospective template.

Implementation shape:

- Add a local draft type for sprint/session retro:
  - what failed repeatedly
  - which gate caught it
  - which gate missed it
  - what should become a test
  - what should become a guidance proposal
- Keep promotion into AGENTS/docs/scripts behind review-gate.
- Avoid automatic Obsidian push during review-gate.

Priority: P1/P2.

### 5. Security Review Lane

GStack's CSO-style lane is useful as a named trigger for auth, secrets, data,
deployment, browser cookies, and production-adjacent work.

Implementation shape:

- Add a security-review checklist or skill only for security-shaped work.
- Require threat model, secret scan, auth boundary, data retention, and rollback
  checks when triggered.
- Do not run it on every small change.

Priority: P2.

### 6. Parallel Sprints Observation

GStack also presents a high-throughput operating model around parallel sprints.
This was missing from the first draft of this benchmark and was caught only in
follow-up discussion. It is recorded here as an observation, not as an approved
AI_AUTO roadmap item.

The important distinction is that GStack-style parallel sprinting is not MCP
parallelism and not simply "more subagent slots" inside one session. It implies
multiple independent agent sessions over isolated workspaces, with a conductor
or leader integrating results.

No implementation should be inferred from this benchmark alone. Any future
multi-worktree or tmux-based sprint model requires a separate plan, approval,
dry-run, and final-gate design.

Priority: research note only.

### 7. Operating Guidance And Persona Benchmark

GStack's many agent personas are useful as a design reference, but not as a
direct roster to import. AI_AUTO already has role routing through AGENTS.md,
OMX skills, native subagents, review-gate, and Reflection Loop. Adding many
always-on personas would increase authority conflict, prompt budget, reviewer
fatigue, and process duplication.

Benchmark goal:

- Compare GStack operating instructions, role boundaries, escalation rules, and
  persona prompts against AI_AUTO's current guidance.
- Identify review lenses that AI_AUTO does not currently express well.
- Decide whether each useful lens should become:
  - an existing role enhancement
  - an optional review checklist
  - a conditional workflow gate
  - a later-phase research note
  - rejected because it duplicates existing authority

Persona lenses worth comparing:

- product / CEO challenge
- engineering plan review
- design review
- browser QA
- security / privacy review
- release / ship review
- retro / reflection review
- conductor / integration owner for parallel work

Adoption rule:

- Do not adopt a 20+ standing persona roster.
- Do not create a second authority layer beside AGENTS.md and repo scripts.
- Prefer conditional persona lenses that activate only when the task shape
  needs them.
- Map every adopted lens to one authoritative AI_AUTO surface: AGENTS.md,
  workflow skill, review-gate checklist, Reflection Loop contract, or Workbench
  view.

Priority: P0 analysis input, P1/P2 adoption depending on overlap and risk.

## Do Not Import

- Do not install GStack team mode into this repository as a default.
- Do not add `.claude/` or `CLAUDE.md` as a second authority surface unless a
  separate migration plan is approved.
- Do not duplicate `review-gate.sh` with another mandatory review gate.
- Do not add persistent browser cookies or shared browser state without a
  security preflight.
- Do not let GStack/GBrain memory bypass Obsidian Reflection Loop and promotion
  rules.
- Do not copy slash command names directly if they collide with OMX skills.

## Risk Register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Authority conflict | AGENTS.md, OMX, and GStack commands disagree | Keep AGENTS.md and repo scripts authoritative |
| Review duplication | Plan/review gates slow execution without new signal | Import challenge checklists, not mandatory second gates |
| Context bloat | More roles increase prompt size and budget pressure | Keep surfaces small and link to docs/research |
| Browser state risk | Persistent sessions/cookies leak state or credentials | Make persistent browser optional and security-gated |
| Memory drift | GStack/GBrain-style memory conflicts with Obsidian | Use Reflection Loop as the only promotion path |
| Namespace collision | Slash commands overlap with OMX skills | Use AI_AUTO-specific names and aliases only after review |
| Parallel sprint confusion | MCP/subagent slots are mistaken for external multi-session capacity | Treat parallel sprinting as a research note until a separate operating plan exists |
| Persona sprawl | Too many standing roles create authority conflicts and slow routine work | Import review lenses conditionally instead of adopting a 20+ persona roster |

## Multi-AI Review

### Claude Review

Claude recommended selective absorption and advised against wholesale install.
Key points:

- GStack overlaps with OMX on virtual team, plan review, browser QA, retro, and
  security review.
- Main gaps are office-hours/product challenge and Codex host workflow polish.
- Highest ROI is product challenge plus Codex host workflow refinement.
- Main risks are slash namespace collision, duplicate review gates, split retro
  memory, doc budget, and upstream dependency drift.

Artifact:
`.omx/artifacts/claude-ai-auto-omx-gstack-gstack-agents-md-omx-skills-team-ralph-re-2026-05-27T22-24-00-255Z.md`

### Gemini Review

Gemini also recommended selective absorption. Key points:

- Full install risks logic conflicts with `review-gate.sh` and AGENTS.md.
- Candidate imports are slash-command UX, product challenge, browser QA,
  retro-to-Obsidian, and Codex host support.
- Main risks are process duplication, context overhead, and dependency complexity.
- Suggested priorities were security/plan review checklist, browser QA
  automation, then retro automation.

Artifact:
`.omx/artifacts/gemini-ai-auto-omx-gstack-gstack-agents-md-omx-skills-team-ralph-re-2026-05-27T22-23-49-570Z.md`

### Codex Synthesis

Consensus: GStack should be treated as a reference architecture, not a runtime
dependency. The immediate implementation should be one small planning surface
for product challenge, followed by UI/browser QA and retro refinements after the
Reflection Loop contracts settle.

### Artifact Sync Failure Review

The first version of this benchmark missed the parallel sprint observation even
though the follow-up conversation identified it as relevant. The failure was not
that AI_AUTO lacked a parallel sprint policy. The failure was artifact sync:

- A benchmark artifact was created.
- A new material finding appeared after the first write.
- The answer discussed the new finding, but the artifact was not updated.
- The document stopped being the source of truth for the active benchmark.

This requires a research-artifact discipline improvement. When an active
benchmark, plan, or research document exists, later material findings must be
reflected in that artifact before completion, or explicitly recorded as deferred
with a reason.

Proposed recurrence-prevention rule:

1. New finding sync: if a material fact, risk, counterargument, or adoption
   candidate appears after a benchmark/plan artifact is written, update the
   artifact before final reporting.
2. Delta check before answer: before replying, ask whether anything important
   was learned after the last artifact write.
3. Artifact as source of truth: final answers summarize the artifact; they
   should not contain material conclusions absent from the artifact.
4. Late discovery handling: if a later user question exposes a missing axis,
   say it is missing, then patch the artifact or record a deferred update.
5. Search check: verify major user-named axes are present with a narrow `rg`
   check before claiming the artifact is complete.

Recommended follow-up: propose a small guidance update for research/benchmark
workflows after this benchmark is stable. Do not add broad AGENTS.md rules from
this incident alone.

## Proposed Roadmap

Roadmap scope:

- Phase A through Phase F are adoption planning phases.
- The execution Ralph implements Phase A through Phase F as AI_AUTO-native
  checklists and side-effect-free pure contracts only.
- Product/runtime adoption begins only after the current Reflection Loop work is
  committed or otherwise stabilized and a phase-specific execution plan is
  approved.

Execution artifacts:

- `docs/GSTACK_ADOPTION_CHECKLISTS.md`
- `scripts/gstack_benchmark_contracts.py`
- `tests/test_gstack_benchmark_contracts.py`

### Phase A: Product Challenge

Goal: add a read-only product challenge workflow before broad plans.

Deliverable:

- A concise skill or helper that outputs problem reframing, smallest wedge,
  non-goals, risks, and acceptance checks.
- Implemented as `product_challenge_contract()`.

Validation:

- Test on one existing rebuild plan.
- Confirm it does not trigger for small maintenance tasks.

### Phase B: UI/Browser QA Checklist

Goal: turn GStack's browser QA discipline into AI_AUTO evidence requirements.

Deliverable:

- A browser QA evidence checklist and optional helper.
- Integration with visual-ralph/frontend completion criteria.
- Implemented as `browser_qa_contract()`.

Validation:

- One UI smoke scenario with screenshot, console check, and regression decision.

### Phase C: Retro Draft Template

Goal: deepen Reflection Loop without adding a second memory authority.

Deliverable:

- Retro draft schema for `.omx/knowledge/drafts`.
- Promotion candidate rules for tests/guidance/docs.
- Implemented as `retro_draft_contract()`.

Validation:

- Ensure raw transcript, prompt, token, private path, and screenshot content are
  blocked.

### Phase D: Persona And Operating Guidance Comparison

Goal: use GStack's operating guidance and agent personas as a benchmark against
AI_AUTO's current role system without importing a second authority layer.

Deliverable:

- A comparison matrix:
  - GStack persona or instruction
  - closest AI_AUTO role/gate/document
  - useful missing lens
  - duplication risk
  - recommended disposition
- Implemented as `persona_lens_contract()`.

Validation:

- Confirm no new standing persona is added without a task-shape trigger.
- Confirm adopted lenses map to one authoritative AI_AUTO surface.
- Confirm routine small tasks do not gain extra mandatory review lanes.

### Phase E: Security / Release / Ops Lens

Goal: borrow CSO, release, canary, and performance thinking without importing
autonomous production side effects.

Deliverable:

- A conditional checklist for security-shaped, release-shaped, deployment, or
  observability work.
- Clear non-goals: no auto merge, no auto deploy, no production canary, no
  credentialed browser state without explicit approval.
- Implemented as `security_release_ops_contract()`.

Validation:

- Confirm routine documentation and local maintenance tasks do not trigger the
  lane.
- Confirm security/privacy triggers are explicit and evidence-based.

### Phase F: Parallel Sprint / Conductor Research

Goal: keep GStack-style parallel sprints separate from ordinary subagent
parallelism until a safe operating model exists.

Deliverable:

- A future operating-plan outline for worktree ownership, branch owner,
  conductor role, integration gate, lock strategy, duplicate draft strategy, and
  reviewer coverage.
- Implemented as `parallel_conductor_contract()` with research-only enforcement.

Validation:

- Confirm no current V1 runtime behavior starts multi-worktree sprint execution.
- Confirm the benchmark treats this as research-only unless separately approved.

## Review Hierarchy For Benchmark Adoption

Micro review:

- One GStack concept or one AI_AUTO surface.
- Pass requires a clear disposition: `adopt`, `modify`, `defer`, or `reject`.
- Adopt/modify must name one authoritative AI_AUTO surface.

Small-group review:

- Related concepts grouped by AI_AUTO state, GStack state, persona/guidance,
  UI/browser/QA, security/release/memory, or parallel/conductor.
- Pass requires no unresolved contradiction and no unbounded persona sprawl.

Mid-group review:

- Synthesized benchmark upgrade.
- Claude participates here when available to conserve session quota.
- Gemini participates when available.
- If reviewer session limits occur, GPT substitute review is accepted for this
  Ralph run only and must be labeled as substitute/degraded.
- `consensus` or `unanimous` language at this layer requires reviewer
  eligibility, independence, context completeness, and zero blocking findings.

Overall review:

- Repository-level verification through `git diff --check`, `./scripts/verify.sh`,
  and `./scripts/review-gate.sh`.
- `consensus` or `unanimous` language requires recorded reviewer eligibility,
  independence, context completeness, and zero blocking findings.

## Recommendation

For this Ralph run, execute Phase A-F only as AI_AUTO-native documentation,
side-effect-free pure contracts, and regression tests. Keep runtime GStack
adoption, global persona/workflow expansion, persistent browser state, release
automation, and parallel sprint execution deferred until a separate
phase-specific plan is approved.
