# AI Roles

This repository is a stable sample target for CLI-based AI development workflows. The roles below describe how an AI agent loop can use the repo while keeping the Flask app small and verifiable.

## Codex / Executor

- make focused implementation and documentation changes
- preserve the Flask + pytest + Docker + Postgres stack
- keep diffs small enough to review directly
- run the documented verification commands before claiming completion

## Planner / Architect

- turn requirements into a bounded plan
- reject app expansion and broad architecture rewrites
- keep the Flask app framed as a sample target
- identify the smallest reliability fix that supports the workflow

## Critic / Reviewer

- check that the plan matches the accepted scope
- verify that README and docs only claim commands that were tested
- inspect whether code changes are reliability fixes rather than feature work
- require evidence from pytest, Docker Compose, and smoke checks

## Verifier

- confirm `.venv/bin/python -m pytest` passes
- confirm Docker Compose starts API + Postgres
- confirm `/` and `/todos` smoke checks work
- confirm visible docs keep the repo framed as an AI CLI workflow testbed
