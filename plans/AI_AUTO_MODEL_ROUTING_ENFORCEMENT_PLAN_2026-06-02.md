# AI_AUTO Cross-Runtime Model-Routing Enforcement and Observability Plan (2026-06-02)

Backlog item: `ST-P1-22` (`plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md`).
Status going in: `later_gated` design candidate. This plan is the scoped design;
implementation still requires explicit approval and full verify/review coverage.

## 1. Why This Plan Changed Shape

The original `ST-P1-22` was written narrowly as "GPT-5.5 to GPT-5.3" routing,
because the visible symptom is Codex-only:

- `/root/.codex/agents/executor.toml` hardcodes `model = "gpt-5.5"`.
- `/root/.codex/agents/explore.toml` hardcodes `model = "gpt-5.3-codex-spark"`.
- Sessions repeatedly run bounded, lookup-shaped work on the standard `gpt-5.5`
  executor instead of the fast `gpt-5.3-codex-spark` lane.

But the repo's routing contract in `docs/AI_MODEL_ROUTING.md` is already
**role-first and runtime-surface-first**, and the active principal can be
`codex`, `claude`, or `gemini` (`docs/AI_PRINCIPAL_RUNTIMES.md`). A
GPT-only fix would re-hardcode a single provider's model names into the
workflow — exactly what the precedence rules in that doc forbid.

So the plan is generalized: define a **provider-neutral model-class ladder and
lane set**, resolve it onto whichever principal is active, and make the
selection observable. "GPT-5.5 to GPT-5.3" becomes one concrete mapping of a
general rule, not the rule itself.

## 2. Goal and Non-Goals

### Goal
Give every principal runtime (Codex, Claude, Gemini) the same routing contract:

1. A small, named set of **lanes** (work shapes) that map to **model classes**
   (`fast`, `standard`, `frontier`), not to dated model names.
2. **Observability**: each delegated unit records role, resolved model, model
   class, reason, fallback, confidence, and the active principal.
3. A **report-only audit** of missed low-cost-lane opportunities (the Codex
   instance of this is missed `omx explore` lookups).
4. A **separate bounded low-cost implementation lane** (`*-low`) added per
   provider, only after guardrails pass.

### Non-Goals (hard boundaries, all providers)
- Do **not** globally downgrade `executor`, planner, verifier, or reviewer
  roles to a fast/low class.
- Do **not** treat the fast class (`gpt-5.3-codex-spark`, `haiku`, Gemini flash)
  as an automatic principal/main-session downgrade.
- Do **not** hardcode dated provider model names as broad workflow defaults;
  resolve classes through the existing precedence chain.
- Routing logs and audits get **no completion authority**; they are evidence,
  not gates that can pass work.
- No new always-on runtime, scheduler, queue, or UI.

## 3. Provider-Neutral Model-Class Ladder

| Lane (role) | Work shape | Model class | Completion authority |
|---|---|---|---|
| `fast_scan` | file/symbol lookup, lightweight synthesis, routing triage | `fast` | none |
| `low_cost_impl` | tightly bounded, reversible, single-concern edits that pass delegation guardrails | `fast`/`low` | none (leader reviews diff) |
| `standard_impl` | normal implementation, multi-file changes, refactors | `standard` | none (verify/review gates own completion) |
| `frontier_review` | architecture risk, security-sensitive judgment, long-context review | `frontier` | reviewer verdict only, never self-completion |

These lane names already appear in the backlog scope wording and partly in
`docs/AI_MODEL_ROUTING.md` role profiles (`fast_scan`, `implementation`). This
plan formalizes the four-lane set and the `*_impl` split.

## 4. Per-Provider Class Resolution

The class ladder resolves onto each principal using the existing precedence in
`docs/AI_MODEL_ROUTING.md` (env override → local CLI capability/aliases →
OMX/Codex contract → provider default). Concrete current mappings:

Verified directly on 2026-06-02 (not inferred from docs):

| Provider | `--model` support | fast | standard | frontier | Notes |
|---|---|---|---|---|---|
| Codex | yes (`codex exec --model`; `gpt-5.5`) | `gpt-5.3-codex-spark` (explore lane) | `gpt-5.5` (executor) | `gpt-5.5` high reasoning | Models from OMX/Codex contract, not hardcoded in workflow scripts; agent TOMLs already carry `model_class: fast/standard` metadata |
| Claude | yes (`--model <sonnet\|opus\|claude-opus-4-8…>`) | `haiku` (full name) | `sonnet` | `opus` | Stays on provider default unless `CLAUDE_*_MODEL`/`_AUTO=1` set, per existing rule |
| Gemini | **no, in practice** — must use `agy`, which has no `--model` | fixed (`agy` → gemini 3.5) | fixed (`agy` → gemini 3.5) | fixed (`agy` → gemini 3.5) | `/usr/bin/gemini -m` exists but is **not an allowed path**: gemini 3.5 is only reachable through `agy`. So Gemini is class-fixed |

**Hard constraint (user, 2026-06-02):** Gemini must be invoked **only via
`agy`**. The standalone `/usr/bin/gemini -m` binary technically accepts a model
flag, but it cannot reach gemini 3.5 — only `agy` can — so routing Gemini
through `gemini -m` is forbidden. Net effect: `agy` exposes no model selector,
so a Gemini **principal is pinned to a single class** (gemini 3.5) and cannot
operate models variably. This is a real, documented limitation, not a bug to
work around. `GEMINI_REVIEW_COMMAND` stays `agy`.

**Honesty rule (scoped):** when a *specific runtime surface* cannot honor a
requested class, the router must record `model_class_applied: false` with reason
`class_unavailable` for that surface, use its default, and never log a class it
did not actually apply or claim a model is available without runtime evidence
(`docs/AI_MODEL_ROUTING.md` uncertainty rule). It must distinguish
"this provider cannot" from "this one wrapper command cannot."

## 5. Observability Schema

Observability lands in two stages so the evidence surface tracks what actually
exists at each phase. Both extend the existing routing evidence surface
(`.omx/model-routing/observations.tsv` and `latest.md`, written by
`discover-ai-models.sh`) rather than inventing a new store.

**Phase 0 (observe-only, no per-unit routing yet):** the routing report
(`.omx/model-routing/latest.md`) gains an observe-only **"Principal Class
Lanes"** block recording the per-principal lane-to-class contract and each
principal's variable-operation availability. There is nothing per-unit to log
yet, so the existing reviewer-lane TSV stays unchanged.

**Phase 1 (real routing decisions exist):** once lanes actually route work,
each delegated/routed unit appends one record to a **dedicated**
`.omx/model-routing/lane-decisions.tsv` (kept separate from the 6-column
reviewer-lane `observations.tsv` to avoid a schema collision), via the
validated `scripts/record-lane-decision.py` helper:

```
timestamp  principal  lane  role  requested_class  resolved_model  model_source  model_class_applied  reason  fallback  confidence
```

- `principal`: active runtime (`codex`/`claude`/`gemini`).
- `requested_class`: `fast`/`standard`/`frontier`.
- `model_source`: reuse existing source labels (`provider-default`,
  `env:*`, `unsupported`, OMX contract, inferred).
- `model_class_applied`: `true`/`false` (false ⇒ `reason` explains, e.g.
  `class_unavailable`, `override`, `escalated`).
- `confidence`: `high`/`medium`/`low` for the routing decision (inferred from
  help/config = at most `medium`, never presented as verified provider fact).

The TSV stays capped to header + latest 1000 rows (existing behavior).

## 6. Missed-Opportunity Audit (Report-Only)

Generalize the "missed `omx explore`" idea to a per-principal **fast-lane
opportunity audit** emitted in review context, report-only:

- Codex: bounded read-only lookups that ran on `executor`/`gpt-5.5` instead of
  the `explore`/spark lane (the original symptom).
- Claude / Gemini: lookup-shaped delegated work that ran on standard/frontier
  class when the fast class was eligible and available.

Output is advisory hints in `collect-review-context.sh`
(matching the report-only pattern of `ST-P1-15`/`ST-P1-19`), with an explicit
`runtime_lane_added: false` marker. It never blocks, never auto-reroutes, and
never carries completion authority. Where the fast class is unavailable
(Gemini today), the audit reports `fast_lane_unavailable` instead of flagging a
missed opportunity.

## 7. Phased Implementation

### Phase 0 — Observe only (no behavior change)
- Add the observe-only per-principal "Principal Class Lanes" report block to
  `discover-ai-models.sh` (the §5 Phase 0 stage). The per-unit `observations.tsv`
  schema is **not** part of Phase 0 — it lands in Phase 1 when real routing
  decisions exist to log.
- Add the report-only fast-lane opportunity audit ("Model Routing Lane Audit")
  to review context.
- No agent TOML changes, no new lanes, no rerouting, no TSV schema change.
- Exit criteria: the observe-only report block + review-context audit are
  visible for all three principals (Gemini honestly `class_unavailable`),
  `verify.sh` and `review-gate.sh` green, targeted tests lock the report/audit
  shape.

### Phase 1 — Variable model operation for every principal (Codex, Claude, Gemini)
**Scope decision (user, 2026-06-02):** Phase 1 is *not* Codex-only. When Claude
or Gemini holds the **principal/orchestrator position**, it must be able to
operate model classes variably for its own delegated work, exactly like the
Codex principal does today with the `explore` (spark) and `executor` (gpt-5.5)
lanes. The lane→class contract is principal-symmetric.

Concretely, each principal exposes its own class lanes for delegated work:

| Principal | fast lane | standard lane | frontier lane | Mechanism |
|---|---|---|---|---|
| Codex | `explore` (`gpt-5.3-codex-spark`) + new `executor-low` | `executor` (`gpt-5.5`) | `gpt-5.5` high reasoning | agent TOMLs + `codex exec --model` |
| Claude | `haiku` subagent lane | `sonnet` subagent lane | `opus` subagent lane | `--model` on delegated child agents |
| Gemini | — (class-fixed) | `agy` → gemini 3.5 | — (class-fixed) | `agy` only; no model selector → single class, `class_unavailable` for variable operation |

So Phase 1 delivers variable model operation for **Codex and Claude**
principals. The **Gemini** principal is included in the contract but honestly
reports a single fixed class, because the mandated `agy` invocation (the only
path to gemini 3.5) exposes no model selector. Variable Gemini routing is
revisited only if `agy` later gains a class/model surface.

- Introduce `low_cost_impl` as a **separate** lane, e.g. Codex `executor-low`
  (a new `/root/.codex/agents/executor-low.toml`, not a mutation of
  `executor.toml`); the Claude/Gemini equivalents are delegated child-agent
  profiles, not principal downgrades. The principal itself stays stable; it
  *dispatches* lanes at different classes rather than self-mutating mid-turn
  (`docs/AI_MODEL_ROUTING.md` principal-vs-delegated rule).
- Gate every route into `low_cost_impl` on the delegation guardrails in
  `docs/AUTOMATION_OPERATING_POLICY.md` (§ Low-Cost Coding Lane, escalation
  rules, rewrite-rate stop rule). The principal reviews the diff; ambiguity
  escalates. This applies identically whichever principal is active.
- Each principal records its lane→class selections through the same
  observability schema (§5), tagged with the active principal.
- Exit criteria: every available principal has opt-in, guardrail-checked,
  observable, cleanly-reverting class lanes; the rewrite-rate stop rule is
  enforced; review-gate covers it; any surface that genuinely lacks a model
  selector (e.g. the `agy` review lane) reports `class_unavailable` honestly.

### Phase 2 — Enforcement tuning (evidence-driven only)
- Only after repeated local observation rows show a class is consistently
  better for a lane, adjust the **default class selector** for that lane.
- Never change a default from a single provider announcement or one-off
  failure (existing `observations.tsv` tuning rule).

## 8. Guardrails / Invariants (re-stated for enforcement)

1. Principal selection changes the lane owner, not the workflow contract or
   artifact layout (`docs/AI_PRINCIPAL_RUNTIMES.md` artifact invariance).
2. No fast/low class on planner, verifier, reviewer, or the principal itself.
3. No silent global `executor` downgrade; `low_cost_impl` is additive.
4. Honest unavailability: `class_unavailable` + provider default, never a
   fabricated model claim (Gemini is the live test of this rule).
5. Routing evidence ≠ completion authority.
6. Inferred selections reported as inferred, confidence ≤ medium.

## 9. Files In Scope

Workflow / docs (repo-owned, the durable contract):
- `docs/AI_MODEL_ROUTING.md` — formalize the 4-lane set + per-principal class
  resolution + observability schema.
- `docs/AUTOMATION_OPERATING_POLICY.md` — reference `low_cost_impl` guardrails
  (source of truth already exists; cross-link, do not duplicate).
- `scripts/discover-ai-models.sh` — Phase 0: observe-only per-principal lane
  report block. Phase 1: per-unit TSV fields. Keep provider-default-first
  behavior and the Gemini `unsupported`
  path.
- `scripts/collect-review-context.sh` — report-only fast-lane opportunity audit.
- `.omx/model-routing/latest.md` / `observations.tsv` — extended report blocks.

Runtime agent surfaces (provider-specific, additive only):
- `/root/.codex/agents/executor-low.toml` (new, Phase 1) — bounded low-cost lane.
- `/root/.codex/agents/explore.toml`, `executor.toml`, `/root/.codex/AGENTS.md`,
  `oh-my-codex/dist/team/model-contract.js` — referenced for current Codex
  mappings; not mutated to downgrade existing roles.

Tests:
- Targeted tests locking the observability schema, the report-only audit shape,
  the Gemini `class_unavailable` path, and the "no global executor downgrade"
  invariant (extend `scripts/self_demo_contracts.py` /
  `tests/test_self_demo_contracts.py` plus a routing-context test analogous to
  `tests/test_completion_pack_routing_context.py`).

## 10. Verification and Review Coverage

- `./scripts/verify.sh` green before any completion claim.
- `./scripts/review-gate.sh` green; because routing touches the review lane
  itself, run discovery refresh once (`AI_MODEL_DISCOVERY_REFRESH=1`) and
  confirm reviewers are not degraded.
- Self-demo contract covers: schema present for all three principals,
  report-only audit emitted, no completion authority, Gemini honesty path.

## 11. Decisions and Remaining Questions

Resolved 2026-06-02:

1. **Gemini invocation = `agy` only** (gemini 3.5 is reachable only through
   `agy`; `gemini -m` is forbidden). `agy` has no model selector, so the Gemini
   principal is class-fixed and reports `class_unavailable` for variable
   operation. Not worked around.
2. **Phase 1 covers all three principals**, not Codex-only (user decision):
   Codex and Claude get true variable model operation; Gemini is contractually
   included but honestly class-fixed until `agy` exposes a selector.

Remaining:

3. For Claude, keep provider-default-by-default (current rule) and enable class
   routing under `CLAUDE_*_MODEL_AUTO=1` / `CLAUDE_*_MODEL`, or add a dedicated
   `CLAUDE_LANE_*` knob? Recommendation: reuse existing variables, no new knob
   until evidence justifies it.
4. Should Phase 1 monitor whether `agy` later adds a model/class surface so the
   Gemini limitation can be lifted without a re-plan? Recommendation: yes, as a
   one-line capability check in `discover-ai-models.sh`, report-only.
