# AI Model Routing

AI model routing is role-first and runtime-surface-first.

Do not route work by a dated hardcoded model name. Route work by the role and
capability needed, then resolve that role onto the models or aliases actually
available in the current CLI/runtime/account.

## Precedence

1. Explicit project/run override environment variables.
2. Current local CLI capability and advertised aliases.
3. Current OMX/Codex model contract from the active runtime.
4. Provider default with no explicit model flag.

Provider documentation is reference material only. It is not proof that a local
CLI, login session, account, or Codex runtime can use a specific model.
Recurring trend reports may recommend routing changes, but they must remain
dated, sourced proposals until local runtime evidence confirms availability and
the normal verification/review gates accept the change.

## Principal vs Delegated Routing

The active principal runtime is selected by the runtime or user and may be
Codex, Claude, or Gemini. Treat the active principal as the single owner of the
repo-local workflow for that run: it may read files, edit files, run local
verification, and write the normal `.omx/*` artifacts under the same project
rules as the default Codex principal.

Do not claim that a runtime changed its own model or principal mid-session
unless the runtime provides explicit evidence of a supported change path.
Principal selection changes the owner of the lane, not the workflow contract or
artifact layout. Use `docs/AI_PRINCIPAL_RUNTIMES.md` for the principal runtime
contract.

Cost and latency optimization should happen through bounded delegated lanes:
route lookup, scanning, lightweight synthesis, and narrow implementation slices
to role-appropriate child agents such as `explore`/fast-scan lanes or the
current low-cost Codex coding lane. Keep planning, architecture,
security-sensitive decisions, integration, final verification, review-gate
interpretation, and user-facing completion claims on the leader or stronger
reviewer roles.

Default child-agent routing should inherit the current runtime contract. Use an
explicit model override only when a lane has a concrete reason and current
runtime evidence supports that model. Prefer role and `reasoning_effort`
selection over hardcoded model names. When the current runtime exposes an
available low-cost Codex coding lane, prefer that lane for bounded
implementation work that passes the delegation guardrails in
`docs/AUTOMATION_OPERATING_POLICY.md`.

## Token-Efficient Implementation Delegation

Delegate implementation to a low-cost coding lane only when the guardrails in
`docs/AUTOMATION_OPERATING_POLICY.md` pass. That policy is the authoritative
source for allowed task shapes, security and contract carve-outs, escalation
rules, leader review duties, and rewrite-rate stop rules.

Availability must be supported by auditable runtime evidence: the active
model-routing report, an explicit session configuration value, or another
runtime capability signal. Prefer role selection and reasoning effort over
hardcoded model overrides, and inherit the current runtime model unless a
concrete, current runtime-supported reason exists to override it.

For detailed subagent delegation boundaries, use
`docs/AUTOMATION_OPERATING_POLICY.md` as the source of truth. Native subagents
are throughput and focus lanes, not independent external reviewer coverage.

## Role Profiles

| Role | Target Capability | Default Runtime Mapping |
|---|---|---|
| `architect_review` | deep reasoning, long-context risk review, maintainability judgment | Claude provider default with suggested alias recorded; principal-subagent architect substitute when needed |
| `alternative_review` | independent second opinion, missed cases, simpler alternatives | Gemini provider default unless explicitly configured; principal-subagent test substitute when needed |
| `implementation` | bounded repo-local code edits and test fixes | Current low-cost Codex coding lane when guardrails pass; otherwise Codex executor/current runtime default |
| `debug` | logs, reproduction, root cause, regression isolation | Codex debugger/current runtime default |
| `test_review` | verification shape, missing tests, failure modes | Codex test-engineer plus Gemini when available |
| `fast_scan` | file/symbol lookup and lightweight synthesis | Codex explore/spark lane |
| `docs` | documentation and handoff clarity | Codex writer or provider default |

## Model-Class Lanes

Delegated work routes through four provider-neutral lanes that resolve onto the
active principal's model class (`fast` / `standard` / `frontier`) via the
precedence above. The lane is the contract; the model name is resolved, never
hardcoded.

| Lane | Work shape | Class |
|---|---|---|
| `fast_scan` | lookup, lightweight synthesis, triage | fast |
| `low_cost_impl` | tightly bounded, reversible single-concern edits (guardrails in `docs/AUTOMATION_OPERATING_POLICY.md`) | fast/low |
| `standard_impl` | normal implementation, refactors | standard |
| `frontier_review` | architecture/security risk, long-context review | frontier |

Per-principal class surface (verified locally, observe-only):

- Codex: `explore` (`gpt-5.3-codex-spark`) / `executor` (`gpt-5.5`) / `gpt-5.5`
  high reasoning — full variable operation.
- Claude: `haiku` / `sonnet` / `opus` via `--model` — variable when the CLI
  supports `--model`.
- Gemini: invoked **only via `agy`** (the sole path to gemini 3.5); `gemini -m`
  is forbidden. `agy` has no model selector, so a Gemini principal is
  class-fixed and reports `class_unavailable` for variable operation.

`scripts/discover-ai-models.sh` records this as an observe-only
"Principal Class Lanes" block, and `scripts/collect-review-context.sh` emits a
report-only "Model Routing Lane Audit" (active principal, recommended lane,
missed fast-lane opportunity). Both are evidence only: no lane is auto-rerouted
and routing records carry no completion authority.

### `low_cost_impl` lane contract

The `low_cost_impl` lane is a **separate** bounded fast-class lane, not a
downgrade of the standard implementation lane. This doc is its source of truth;
the runtime applies it as a per-principal agent (for Codex,
`~/.codex/agents/executor-low.toml`, which is global oh-my-codex config outside
this repo's review-gate). A unit may use `low_cost_impl` only when all hold:

- tightly bounded, reversible, single-concern edit aligned to existing patterns;
- the delegation guardrails in `docs/AUTOMATION_OPERATING_POLICY.md` (§ Low-Cost
  Coding Lane) pass — escalation, security/contract carve-outs, rewrite-rate
  stop rule;
- the leader reviews the diff; ambiguity, scope growth, or repeated failure
  escalates to the standard lane.

It never plans, decides architecture/security, owns verification, or carries
completion authority. Gemini has no `low_cost_impl` (class-fixed via `agy`).
Every delegation onto a class lane is recorded via the Delegation Recording
Protocol (see `AGENTS.md`) into `.omx/model-routing/lane-decisions.tsv`.

### Evidence-driven tuning

A lane's default model-class selector is changed only after repeated
`lane-decisions.tsv` evidence across several local runs shows a class is
consistently better for that lane. Never change a default from a single
provider announcement or a one-off failure, and never globally downgrade the
standard implementation, planner, verifier, or reviewer lanes. Per-unit
delegations are recorded as a normalized step (the Delegation Recording Protocol
in `AGENTS.md`), so evidence accrues in `lane-decisions.tsv`; until enough
accumulates to show a class is consistently better for a lane,
no default change is warranted and the lanes stay at their current classes.

## Current Review Lanes

`scripts/discover-ai-models.sh` writes `.omx/model-routing/latest.env` and
`.omx/model-routing/latest.md` before review execution. The discovery result is
cached for a session-scale TTL so repeated review runs do not churn model
selection without an explicit reason.

The default Codex-principal review lanes are:

- Claude: `architect_review`
- Gemini: `alternative_review`
- principal-subagent architect substitute: `architect_fallback`
- principal-subagent test/alternative substitute: `test_alternative`

When the active principal is Claude, Claude self-review is skipped and the
expected reviewers are Gemini plus Codex. When the active principal is Gemini,
Gemini self-review is skipped and the expected reviewers are Claude plus Codex.
Those Codex reviews are principal-rotation coverage, not degraded fallback.

When an expected reviewer is unavailable, the active principal's subagent is the
regular substitute reviewer for that lane. The substitute is accepted as normal
coverage only with a usable verdict and direct file inspection evidence. Missing
or unusable substitute output remains degraded or blocked coverage.

Claude stays on provider default by default. Discovery records the suggested
alias for the role when the installed CLI advertises one, but it does not pass a
Claude `--model` flag unless `CLAUDE_REVIEW_MODEL` is set explicitly or
`CLAUDE_REVIEW_MODEL_AUTO=1` is used for that run. This avoids turning a
session-local alias guess into a default that can amplify timeout or quota
issues.

Gemini stays on provider default unless a project/run override supplies a model,
because the local CLI may not expose a reliable model inventory through help
text.

Principal-subagent substitute reviews prefer the active principal runtime
contract or explicit override variables instead of public API model names.

## Overrides

Use these only when the current project has a concrete reason to force routing:

- `CLAUDE_REVIEW_ROLE`
- `GEMINI_REVIEW_ROLE`
- `CODEX_ARCHITECT_REVIEW_ROLE`
- `CODEX_TEST_REVIEW_ROLE`
- `CLAUDE_REVIEW_MODEL`
- `CLAUDE_REVIEW_MODEL_AUTO=1`
- `GEMINI_REVIEW_MODEL`
- `CODEX_ARCHITECT_REVIEW_MODEL`
- `CODEX_TEST_REVIEW_MODEL`
- `CODEX_FALLBACK_MODEL`
- `OMX_DEFAULT_FRONTIER_MODEL`
- `AI_AUTO_PRINCIPAL=codex|claude|gemini`

`GEMINI_REVIEW_MODEL` is honored only when the configured Gemini command exposes
`--model`. Under the mandated `agy` command (the sole path to gemini 3.5, with no
model selector) discovery records the Gemini model source as `unsupported` and
clears the override, so it is inert and Gemini stays class-fixed. This matches
the observe-only `class_unavailable` reporting in the Model-Class Lanes section;
making the override actually variable is Phase 1 parity work, not Phase 0.

Set `AI_MODEL_DISCOVERY=0` to skip model discovery and use provider defaults.

Discovery also writes output-only variables such as
`CLAUDE_REVIEW_SUGGESTED_MODEL` and `AI_MODEL_ROUTING_OBSERVATIONS_STATUS`.
Do not set those as overrides; treat them as evidence for reports and tuning.

## Cache And Refresh

Default behavior:

- reuse `.omx/model-routing/latest.env` and `.omx/model-routing/latest.md` when
  they exist and are within `AI_MODEL_ROUTING_TTL_SECONDS`
- default TTL: `43200` seconds, 12 hours
- refresh immediately with `AI_MODEL_DISCOVERY_REFRESH=1`
- reuse cache only when the role/model override fingerprint matches
- bypass cache automatically when a role/model override changes
- bypass cache automatically when Claude, Gemini, or Codex CLI version/help
  output changes

Examples:

```bash
./scripts/review-gate.sh
AI_MODEL_DISCOVERY_REFRESH=1 ./scripts/review-gate.sh
AI_MODEL_ROUTING_TTL_SECONDS=86400 ./scripts/review-gate.sh
AI_MODEL_DISCOVERY=0 ./scripts/review-gate.sh
```

The routing report records cache status, discovery epoch, TTL, selected roles,
selected models, suggested Claude model, observation-log status, and source
labels.

The routing script also appends refreshed selections to
`.omx/model-routing/observations.tsv`. Treat this as operational evidence for
future tuning: adjust role selectors only after repeated local runs show that a
provider alias or default is consistently better for that lane. Do not change
defaults from a single provider announcement or one-off failure. The TSV is
capped to its header plus the latest 1000 rows.

## Uncertainty Rule

If a model choice is inferred from CLI help, local config, aliases, or current
runtime metadata, report it as suggested or inferred. Do not present it as a
verified provider fact.

If model availability is unclear, say so directly and fall back to provider
default or an explicit user override. Do not invent a model name and do not
claim that a model is available unless the current runtime or the user provided
evidence.
