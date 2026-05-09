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

## Role Profiles

| Role | Target Capability | Default Runtime Mapping |
|---|---|---|
| `architect_review` | deep reasoning, long-context risk review, maintainability judgment | Claude `opus` alias, then `sonnet`; Codex architect fallback |
| `alternative_review` | independent second opinion, missed cases, simpler alternatives | Gemini provider default unless explicitly configured; Codex test fallback |
| `implementation` | repo-local code edits and test fixes | Codex executor/current runtime default |
| `debug` | logs, reproduction, root cause, regression isolation | Codex debugger/current runtime default |
| `test_review` | verification shape, missing tests, failure modes | Codex test-engineer plus Gemini when available |
| `fast_scan` | file/symbol lookup and lightweight synthesis | Codex explore/spark lane |
| `docs` | documentation and handoff clarity | Codex writer or provider default |

## Current Review Lanes

`scripts/discover-ai-models.sh` writes `.omx/model-routing/latest.env` and
`.omx/model-routing/latest.md` before review execution. The discovery result is
cached for a session-scale TTL so repeated review runs do not churn model
selection without an explicit reason.

The current review lanes are:

- Claude: `architect_review`
- Gemini: `alternative_review`
- Codex architect fallback: `architect_fallback`
- Codex test fallback: `test_alternative`

Claude uses advertised aliases when possible. For `architect_review`, `opus` is
preferred when the installed CLI advertises it, then `sonnet`. For code-shaped
or test-shaped Claude roles, `sonnet` is preferred first.

Gemini stays on provider default unless a project/run override supplies a model,
because the local CLI may not expose a reliable model inventory through help
text.

Codex fallback prefers the current OMX/Codex runtime contract or explicit
override variables instead of public API model names.

## Overrides

Use these only when the current project has a concrete reason to force routing:

- `CLAUDE_REVIEW_ROLE`
- `GEMINI_REVIEW_ROLE`
- `CODEX_ARCHITECT_REVIEW_ROLE`
- `CODEX_TEST_REVIEW_ROLE`
- `CLAUDE_REVIEW_MODEL`
- `GEMINI_REVIEW_MODEL`
- `CODEX_ARCHITECT_REVIEW_MODEL`
- `CODEX_TEST_REVIEW_MODEL`
- `CODEX_FALLBACK_MODEL`
- `OMX_DEFAULT_FRONTIER_MODEL`

Set `AI_MODEL_DISCOVERY=0` to skip model discovery and use provider defaults.

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
selected models, and source labels.

## Uncertainty Rule

If a model choice is inferred from CLI help, local config, aliases, or current
runtime metadata, report it as inferred. Do not present it as a verified
provider fact.

If model availability is unclear, say so directly and fall back to provider
default or an explicit user override. Do not invent a model name and do not
claim that a model is available unless the current runtime or the user provided
evidence.
