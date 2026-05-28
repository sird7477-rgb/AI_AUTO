# GStack Benchmark Adoption Checklists

This document turns the GStack benchmark into AI_AUTO-native, conditional
checklists. It does not install GStack, add a second persona roster, create a
new memory authority, start browser daemons, run multi-worktree sprints, merge,
deploy, or push.

The executable contract surface is `scripts/gstack_benchmark_contracts.py`.

## Review Layers

- Micro: one checklist item or helper contract. Pass requires a disposition,
  target authority surface, and no blocker.
- Small group: one phase. Pass requires no contradiction inside the phase and no
  mandatory burden on routine small tasks.
- Mid group: cross-phase synthesis. Claude participates when available; Gemini
  participates when available; GPT substitute is acceptable for this Ralph run
  only when a reviewer is unavailable because of a session or quota limit.
- Overall: `git diff --check`, `./scripts/verify.sh`, and
  `./scripts/review-gate.sh`.

## Phase A: Product Challenge

Trigger only for broad, ambiguous, strategic, high-cost, product-shaping, or
rebuild-plan work.

Skip for typo fixes, small maintenance, already-scoped patches, and mechanical
patches.

Required output:

- problem restatement
- smallest useful wedge
- non-goals
- risks
- acceptance evidence
- decision: `proceed`, `narrow`, `ask`, or `reject`

Authority surface: planning policy and helper contract only. It does not block
ordinary maintenance work.

## Phase B: UI / Browser QA Evidence

Use for browser-facing or UI-facing work.

Required evidence:

- route or URL
- viewport matrix
- screenshot artifact references
- console status
- network status
- user path
- regression decision
- source of truth: `user_template`, `project_screen`, or `external_reference`

Modes:

- `report_only`: audit and evidence only
- `fix_loop`: requires explicit execution scope

Authenticated persistent browser state is credential-equivalent and requires
separate explicit approval.

## Phase C: Retro / Reflection Draft

Use for repeated failures, gate misses, or end-of-phase reflection.

Required draft fields:

- repeated failure
- gate that caught it
- gate that missed it
- evidence
- proposed test, guidance, or doc update

Privacy rules:

- no raw logs, raw prompts, tokens, private paths, credential-like strings, or
  sensitive screenshot contents
- Obsidian notes remain non-authoritative
- promotion to docs, scripts, templates, or guidance requires review-gate

## Phase D: Persona / Operating Guidance Comparison

GStack personas become conditional lenses, not a standing AI team.

Allowed lenses:

- product: broad product work
- design: UI work
- browser QA: browser-facing work
- security: auth, secrets, data, or deploy-shaped work
- release: deployment candidates
- retro: repeated failure or phase end

Forbidden:

- 20+ always-on personas
- new default review lanes for routine small tasks
- persona authority outside one named AI_AUTO surface

## Phase E: Security / Release / Ops Lenses

Security triggers:

- auth
- secrets, tokens, cookies
- persistent browser state
- PII
- data retention
- production-adjacent workflows

Release evidence:

- tests
- docs
- rollback
- monitoring
- user-facing summary

Non-goals:

- no auto merge
- no auto deploy
- no production canary without explicit approval

## Phase F: Parallel Sprint / Conductor Research

This is research-only unless a separate parallel execution plan is approved.

Required future contract:

- worktree owner
- branch owner
- conductor
- integration gate
- lock strategy
- duplicate draft strategy
- reviewer coverage

No current V1 behavior starts multi-worktree sprint execution.
