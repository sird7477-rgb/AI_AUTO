# AI_AUTO Persona Lens And Review Gate Enforcement Plan - 2026-05-29

## Purpose

AI_AUTO should support situation-specific persona lenses without creating a
standing persona roster or a second authority layer. This plan defines a scoped
path to connect conditional lenses, integrator arbitration, and review-gate
activation into one enforceable classifier.

This plan was the implementation planning source. As of the non-active
promotion Ralph pass on 2026-05-29, `ST-P1-07` is promoted to
`complete_contract` through `persona_lens_policy` in
`scripts/self_demo_contracts.py` and matching tests in
`tests/test_self_demo_contracts.py`. Runtime review-gate wiring remains subject
to the safety boundaries in this plan.

## Current Evidence

- `docs/AUTOMATION_OPERATING_POLICY.md` already defines lightweight, standard,
  and strict review intensity.
- `scripts/collect-review-context.sh` already classifies changed paths into
  review scopes and emits a review intensity hint.
- `scripts/review-gate.sh` already runs `verify.sh`, AI reviews, summary,
  checkpoint, archive, and knowledge-draft capture.
- `docs/GSTACK_ADOPTION_CHECKLISTS.md` already states that GStack personas
  become conditional lenses, not a standing AI team.
- `scripts/gstack_benchmark_contracts.py` already rejects standing persona
  rosters, missing task-shape triggers, and persona lanes on routine small
  tasks.

## Design Principle

Use one classifier result to drive three outputs:

1. active persona lenses
2. whether an integrator is required
3. the minimum review-gate policy

The classifier must remain subordinate to user instructions, `AGENTS.md`,
project policy docs, `verify.sh`, and `review-gate.sh`.

## Gate Policy Levels

| Policy | Meaning | Minimum action |
| --- | --- | --- |
| `skip` | Safe to skip review-gate under project policy | Report why review-gate was skipped |
| `verify_only` | Basic verification required | Run `./scripts/verify.sh` |
| `review_gate` | Final review gate required before commit candidate | Run `./scripts/review-gate.sh` |
| `strict_gate` | High-risk gate required before any commit candidate and after material changes | Run `./scripts/verify.sh` and `./scripts/review-gate.sh`; report degraded reviewer state |

In the AI_AUTO home repository, `skip` should be rare. It is mainly for
downstream template projects with lightweight local changes.

## Lens Registry V1

Existing allowed lenses:

- `product`
- `design`
- `browser_qa`
- `security`
- `release`
- `retro`

Candidate V1 additions:

- `data_migration`
- `review_taxonomy`
- `guidance_bloat`
- `performance_budget`
- `policy_compliance`
- `test_strategy`
- `docs_dx`

Deferred or absorbed:

- `a11y`: keep under `design` until UI work volume proves separation is useful.
- `i18n`: keep under `design` or `docs_dx` until repeated misses appear.
- `ops_incident`: defer until incident/on-call workflows become more than a
  testbed concern.
- `conductor`: defer until a separate parallel worktree or multi-session
  execution plan exists.

Rejected by default:

- standing 20+ persona roster
- GStack runtime installation
- persistent browser daemon
- cookie/session transfer
- pair-agent tunnel
- GBrain memory authority
- autonomous ship/deploy/canary behavior
- persona markdown files that claim authority over `AGENTS.md`,
  `verify.sh`, or `review-gate.sh`

## Activation Rules

### Hard Triggers

These always activate a lens and raise the minimum policy:

| Signal | Lens | Minimum policy |
| --- | --- | --- |
| `AGENTS.md`, `docs/WORKFLOW.md`, `docs/AUTOMATION_OPERATING_POLICY.md` | `policy_compliance`, `guidance_bloat` | `strict_gate` |
| `scripts/verify.sh`, `scripts/review-gate.sh`, `scripts/run-ai-reviews.sh`, `scripts/collect-review-context.sh`, `scripts/summarize-ai-reviews.sh` | `policy_compliance`, `test_strategy`, `review_taxonomy` | `strict_gate` |
| `templates/automation-base/*` | `policy_compliance`, `guidance_bloat`, `review_taxonomy` | `strict_gate` |
| auth, token, cookie, secret, PII, credential, browser state | `security` | `strict_gate` |
| schema, migration, serialization, API contract, backfill, import/export | `data_migration` | `strict_gate` |
| deploy, release, rollback, monitoring, production-adjacent | `release` | `strict_gate` |

### Size And Scope Triggers

| Signal | Lens/integrator effect | Minimum policy |
| --- | --- | --- |
| 4 or more changed files | `integrator` required | `review_gate` |
| 150 or more tracked diff lines | `integrator` required | `review_gate` |
| 8 or more changed files | `integrator`, `architect`, `test_strategy` | `review_gate` |
| 400 or more tracked diff lines | `integrator`, `architect`, `test_strategy` | `review_gate` |
| 2 or more active lenses | `integrator` required | `review_gate` |

### Scope Triggers

| Scope | Lens | Minimum policy |
| --- | --- | --- |
| `scripts`, `tools` | `test_strategy`, `review_taxonomy` | `review_gate` |
| `tests` | `test_strategy` | `review_gate` |
| `docs`, `plans` only | `docs_dx` | `verify_only` unless policy/guidance/template triggers apply |
| `app` | `test_strategy` | `review_gate` |
| `docker`, `.github/workflows` | `release`, `policy_compliance` | `strict_gate` |
| UI/browser-facing files | `design`, `browser_qa` | `review_gate` |

### Routine Small Task Suppression

Suppress optional lenses only when all are true:

- one changed file
- small tracked diff
- documentation-only or typo/local maintenance
- no hard trigger
- no security, data, release, template, review-routing, or verification scope
- user did not request detailed review, AI consultation, or broad comparison

Suppression must not apply to hard triggers.

## Integrator Role

The integrator is not a new authority. V1 should be implemented as a small,
testable logical helper, preferably a standalone script such as
`scripts/review-policy-classifier.py` or a similarly narrow module consumed by
`scripts/collect-review-context.sh` and `scripts/review-gate.sh`. Keeping it out
of a large shell block makes the synthesis rules unit-testable and reduces
coupling to review execution.

It combines active lens reports into one decision shape:

- `proceed`
- `proceed_with_notes`
- `narrow_scope`
- `request_user_decision`
- `block`

Integrator priority order:

1. user instruction and safety constraints
2. `AGENTS.md` and project policy docs
3. security, data loss, irreversible operation, credential, and deploy blockers
4. failing verification or missing required evidence
5. scope creep, maintainability, docs, DX, style, and preference notes

Integrator duties:

- merge duplicate findings
- keep optional lens advice non-blocking unless the policy says otherwise
- explain conflicts between lenses
- classify findings as blocker, risk, suggestion, or deferred
- avoid inventing requirements outside the active scope

Degraded reviewer state:

- if a required reviewer or required lens lane is skipped, timed out, disabled,
  or produces malformed output, the integrator must not report normal
  `proceed`
- if the classifier helper itself crashes, exits non-zero, times out, or cannot
  be executed, `review-gate.sh` must fail closed to `strict_gate` and report the
  classifier failure as the reason
- degraded coverage can be reported as `proceed_degraded` only when project
  policy allows it and the missing reviewer/lens state is explicit
- hard-trigger lenses such as `security`, `policy_compliance`, `data_migration`,
  and `release` fail closed to `strict_gate` if classifier data is missing or
  malformed
- Codex fallback review may support diagnosis, but does not replace an available
  independent reviewer when the policy requires one

Diff metric stability:

- tracked diff size must use one documented metric consistently
- V1 should use `git diff --numstat` over the same tracked change set consumed by
  `collect-review-context.sh`; binary files count as one changed file and zero
  line delta for size-trigger purposes unless a hard path trigger applies
- standard lockfiles, generated files, vendor directories, and large static
  assets should not by themselves escalate to `strict_gate`; they may still
  contribute to an integrator note or become strict when another hard trigger
  applies
- untracked material artifacts must either be included through the existing
  untracked-content guard or reported as manual-review-required

## Surrounding Module Relationships

| Module | Relationship | Coupling Risk | Plan Boundary |
| --- | --- | --- | --- |
| `scripts/collect-review-context.sh` | Produces scope summary and is the first consumer of classifier output. | Shell parsing drift can make review-gate enforce stale fields. | Add machine-readable summary fields or a narrow helper output; keep human text derived from the same data. |
| `scripts/review-gate.sh` | Enforces minimum gate policy and reports degraded reviewer state. | Review execution and policy classification can become tangled. | Gate reads classifier result; classifier does not run reviews. |
| `scripts/run-ai-reviews.sh` | Runs external and fallback reviews. | Lens labels could be mistaken for mandatory reviewer processes. | V1 lenses are labels/policy hints, not new reviewer processes. |
| `scripts/summarize-ai-reviews.sh` | Synthesizes reviewer verdicts. | `proceed_degraded` language can hide missing lens/reviewer coverage. | Summary must keep missing reviewer/lens state explicit. |
| `scripts/todo-report.py` | Confirms promoted work is not active debt. | Plan work could accidentally create active TODO debt. | Keep `ST-P1-07` as `complete_contract` after contract promotion; runtime wiring still needs separate safety review. |
| `docs/AUTOMATION_OPERATING_POLICY.md` / `docs/WORKFLOW.md` | Policy source of truth. | Lens docs could become duplicate authority. | Only minimal policy references; no standalone persona authority. |
| `templates/automation-base/*` | Downstream propagation surface. | Template edits require version and patch notes. | Touch only if downstream inheritance is explicitly intended. |

## Micro Work Units

Each unit must be independently reviewable and reversible.

| Unit | Target | Change | Surrounding Checks | Tests | Rollback |
| --- | --- | --- | --- | --- | --- |
| 7.1 | classifier contract | Define JSON or key-value schema for `active_lenses`, `integrator_required`, `gate_policy`, and `reasons`. | Align with current `Diff Scope Summary` fields. | Schema fixture rejects missing/malformed policy. | Remove helper/schema and keep current review context. |
| 7.2 | diff metric | Standardize tracked file/line counts with one `git diff --numstat`-based function. | Must match untracked artifact guard semantics. | Fixtures for text, binary, deleted, and untracked files. | Restore previous scope summary. |
| 7.3 | generated/lockfile filter | Deprioritize lockfiles, generated files, vendor dirs, and large static assets for size escalation. | Must not hide hard triggers in template/policy/security paths. | 1000-line lockfile fixture does not force strict by itself. | Count all files normally again. |
| 7.4 | hard triggers | Encode path/content trigger table for policy, review, template, security, data, release. | Must not duplicate docs as runtime authority beyond trigger mapping. | Each hard trigger maps to `strict_gate`. | Disable hard-trigger helper and fall back to current intensity. |
| 7.5 | routine suppression | Encode small docs/local-maintenance suppression. | Must run after hard triggers, not before. | Hard trigger plus small diff still stays strict. | Remove suppression branch. |
| 7.6 | integrator requirement | Require integrator for 2+ lenses, 4+ files, 150+ lines, or explicit user broad-review request. | Keep integrator as synthesis label/helper, not a new agent. | Multi-lens fixture sets `integrator_required=true`. | Treat integrator field as advisory only. |
| 7.7 | degraded state | Map skipped/disabled/malformed required reviewer or lens output to non-normal proceed. | Reuse existing disabled reviewer reporting. | Fixture with missing security lens fails closed. | Return to current review summary semantics. |
| 7.8 | classifier execution failure | Treat helper crash, timeout, non-zero exit, or missing executable as `strict_gate`. | Must not silently fall back to lightweight policy. | Forced helper failure fixture blocks normal proceed. | Disable helper call and keep current gate behavior. |
| 7.9 | review-gate consumption | Print and enforce classifier result in `review-gate.sh`. | Must not bypass existing verify/review execution. | Gate fixture rejects malformed strict classifier. | Stop consuming classifier fields. |
| 7.10 | docs alignment | Update minimal workflow/policy docs after behavior exists. | Avoid broad guidance bloat. | Doc-budget and required-reference checks. | Revert doc additions only. |

### Ralph Work Groups And Review Loop

Ralph execution for `ST-P1-07` must work in micro units, but review cadence is
based on grouped risk:

| Group | Units | Review Requirement |
| --- | --- | --- |
| Small | 7.1, 7.2, 7.3, 7.4, 7.5 | Targeted fixture or static check after each unit. Claude reviewer participates when available; if Claude is disabled due quota/usage limit, a GPT architect reviewer may be counted as Claude-equivalent only with degraded trust explicitly reported. |
| Medium | 7.6, 7.7, 7.8, 7.9 | Verify after each unit and run review-gate after each coherent pair or sooner if a hard-trigger path is touched. Claude-or-GPT-equivalent review is required. |
| Large | 7.10 plus any template propagation or policy-doc rewrite | Full `./scripts/verify.sh` and `./scripts/review-gate.sh`; no completion claim without review consensus or an explicitly reported degraded substitute. |

Loop rule:

1. implement exactly one micro unit or one coherent small pair
2. inspect diff and classify alignment with this plan
3. run the unit's targeted test
4. run `python3 scripts/todo-report.py --fail-on-active`
5. run `./scripts/verify.sh` for medium/large groups or before any user-facing
   completion claim
6. run review-gate for medium/large groups and for any commit-candidate report
7. accept reviewer notes only when they preserve authority boundaries; revise
   and repeat until every available reviewer approves or an approved GPT
   substitute covers a Claude usage-limit gap

## AI Meeting Refinements

Gemini advisor artifact:
`.omx/artifacts/gemini-review-the-ai-auto-later-gated-planning-artifacts-for-st-p1--2026-05-29T10-40-50-229Z.md`.

Accepted refinements:

- define the integrator as a narrow testable helper or logical module rather than
  an opaque shell block
- formalize degraded reviewer/lens state and prevent normal `proceed` when
  required coverage is missing
- fail closed to `strict_gate` when the classifier helper itself crashes,
  times out, exits non-zero, or cannot execute
- document the tracked diff metric used by size triggers
- avoid lockfile/generated/vendor/static asset churn inflating routine updates
  into strict gates without another hard trigger

Claude advisor was attempted in this Ralph branch but did not return before
manual termination. The current unanimity claim therefore cannot rely on Claude
participation; it must rely on Gemini plus review-gate evidence unless Claude is
later re-enabled.

Updated user rule on 2026-05-29: for Ralph execution of the three non-active
TODOs, Claude should participate for Small group and larger work when available.
If Claude is disabled due quota/usage limit, GPT architect review is accepted as
a same-tier substitute only when the report labels the trust as degraded and
records the disabled Claude state.

## Implementation Plan

### Step 1: Report Classifier Fields

Extend `scripts/collect-review-context.sh` to emit these fields under
`Diff Scope Summary`:

- `active lenses`
- `integrator required`
- `review gate policy`
- `review gate reasons`

This step must include regression tests for representative path sets and
small-task suppression.

### Step 2: Enforce In Review Gate

Extend `scripts/review-gate.sh` to read the latest context summary and enforce
minimum policy:

- if policy is `strict_gate`, refuse to summarize as complete unless
  verification and AI review summary are present for the same gate run
- if policy is `review_gate`, require normal review-gate execution before a
  commit-candidate report
- if policy is `verify_only`, allow review-gate to complete normally when run
  but do not require external reviewer escalation beyond the normal project
  policy

Because `review-gate.sh` already runs verification and AI review, initial
enforcement should focus on making the policy explicit, detecting malformed or
missing classifier data, and preserving fail-closed behavior for strict scopes.

### Step 3: Add Contract Tests

Add tests that prove:

- hard triggers map to `strict_gate`
- scripts/tools/tests map to at least `review_gate`
- docs-only small changes can map to `verify_only`
- routine small task suppression does not suppress hard triggers
- two active lenses require the integrator
- unknown classifier output fails closed
- template changes still require template version and patch notes through the
  existing verification path

### Step 4: Documentation Alignment

Update only the minimal policy docs needed:

- `docs/AUTOMATION_OPERATING_POLICY.md`
- `docs/WORKFLOW.md`
- template copies only if behavior is intended for downstream projects

If template files change, update `templates/automation-base/AI_AUTO_TEMPLATE_VERSION`
and `templates/automation-base/docs/PATCH_NOTES.md`.

### Step 5: Verification

Required before claiming implementation complete:

1. inspect diff
2. compare edits against this plan and classify alignment
3. run targeted tests for the classifier
4. run `./scripts/verify.sh`
5. run `./scripts/review-gate.sh`
6. report reviewer degradation, skipped checks, and remaining limitations

## Acceptance Criteria

- The review context shows active lenses, integrator requirement, gate policy,
  and reasons.
- High-risk scopes fail closed instead of silently becoming lightweight.
- Small routine changes remain lightweight when no hard trigger exists.
- No standing persona roster is introduced.
- No new external runtime, browser state, memory authority, deploy command, or
  GStack installation is introduced.
- The implementation remains shell/test driven and reviewable in small diffs.

## Open Decisions

- Whether persona lens definitions should live as standalone markdown files in
  a later phase, or remain pure classifier labels for V1.
- Whether downstream template projects should inherit `strict_gate` defaults or
  keep a lighter default with hard-trigger escalation.
- Whether review-gate should eventually block commit-candidate reporting when
  `review_gate` was intentionally skipped outside this script.
