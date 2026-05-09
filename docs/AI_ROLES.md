# AI Roles

This repository is a stable sample target for CLI-based AI development workflows. The roles below describe how an AI agent loop can use the repo while keeping the Flask app small and verifiable.

## Codex / Executor

- make focused implementation and documentation changes
- preserve the Flask + pytest + Docker + Postgres stack
- keep diffs small enough to review directly
- run the documented verification commands before claiming completion
- use the current Codex/OMX runtime contract for repo-local implementation and debugging work instead of public API model names
- do not claim to switch the active leader model mid-session; delegate bounded
  low-cost or fast-scan work to role-appropriate subagents when that improves
  throughput without weakening final responsibility

## Planner / Architect

- turn requirements into a bounded plan
- reject app expansion and broad architecture rewrites
- keep the Flask app framed as a sample target
- identify the smallest reliability fix that supports the workflow
- route high-risk plan/design review through the `architect_review` profile when external review is available

## Critic / Reviewer

- check that the plan matches the accepted scope
- verify that README and docs only claim commands that were tested
- inspect whether code changes are reliability fixes rather than feature work
- require evidence from pytest, Docker Compose, and smoke checks
- distinguish facts from assumptions; do not present inferred model availability or undocumented behavior as verified fact

## Verifier

- confirm `.venv/bin/python -m pytest` passes
- confirm Docker Compose starts API + Postgres
- confirm `/` and `/todos` smoke checks work
- confirm visible docs keep the repo framed as an AI CLI workflow testbed

## Model Routing Reference

Use `docs/AI_MODEL_ROUTING.md` for role-to-model routing policy. The default
principle is role-first and runtime-surface-first: decide the capability needed,
then resolve it against the current local CLI/account/runtime evidence.

The leader/subagent boundary is part of that policy: Codex remains responsible
for orchestration, integration, verification, and completion claims, while
delegated lanes can optimize cost or latency for bounded lookup, scanning, and
secondary review work.

## Session Quality Reference

Use `docs/SESSION_QUALITY_PLAN.md` for long-session operation, memory capture,
model-routing cache behavior, and token/context hygiene.
