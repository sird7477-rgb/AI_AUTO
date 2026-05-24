# AI Automation Trend Hardening

Compact control-plane contract for AI automation hardening. Use it for agents,
reviewers, runtime adapters, MCP/tool connectors, long-running automation, or
recurring automation research.

This guide does not create a scheduler, daemon, ACL/auth engine, tracing backend,
or write-capable adapter. Trend notes may propose a reviewed patch, but must not
directly mutate templates, model routing, permissions, or defaults.

## Agent Identity

Agent identity is evidence, not authority. It records actor, surface, and
boundary; missing identity evidence must be reported as missing, not inferred.
Record when available: run id, role/lane, invocation surface, runtime/CLI,
command/adapter path, model source evidence, execution/sandbox mode, cwd/target
repo, artifacts, disabled/degraded/fallback state, and timestamp.

## Tool Permission Registry

Start with a Markdown registry/table when explicit tool governance is needed.
Use `read_only`, `local_write`, `external_network`, `credentialed`,
`destructive`, `git_publish`, and `template_patch`. Each entry should name the
tool surface, roles, approval gate, evidence artifact, and revoke path.
Approved prefixes do not make credentialed, destructive, production, or publish
actions safe.

## Kill Switch And Revoke

A kill switch is a stop condition plus a recovery path. It is not permission to
silently replace one agent/tool with another and claim equivalent coverage.

Use revoke classes: temporary pause, user-reset-required disable, and permanent
policy block. Trigger revoke on capability refusal, permission denial, sandbox
escape risk, unexpected write attempt, reviewer usage/auth/trust/verdict/timeout
failure, prompt-injection suspicion, secret pressure, degraded required input,
or repeated tool failure. Record reason, class, timestamp, affected surface,
source run id, next action, reset hint, and degraded fallback state.

## Agent Observability

Keep observability local by default: Markdown, JSON, JSONL, manifests,
checkpoints, and review artifacts. Record capability decisions, boundaries,
reviewer state, lane ownership, retries/timeouts/failure class, doc-budget/drift
warnings, repeated failure patterns, and redaction status. External telemetry is
opt-in; never export secrets or unredacted private data. Use
`docs/OBSERVABILITY_COMPLETION.md` for broader operations.

## Recurring Trend Report

AI automation trends should be dated, sourced research artifacts; they must not
directly change runtime defaults. Use `docs/research/AI_AUTOMATION_TRENDS.md`
for structure and cadence. Provider docs are reference material; local runtime
evidence controls what AI_AUTO may claim or execute.

## Review Checklist

Before applying a hardening update, verify `AGENTS.md` stays light, root/template
docs stay in sync, template version and patch notes are updated, new runtime
capabilities have a separate plan, degraded reviewers stay reported, trend
research is dated/sourced, and verification plus review gate pass.
