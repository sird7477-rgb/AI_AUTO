# AI Lab

Lightweight testbed for validating a CLI-based AI development workflow with Codex and OmX.

The Flask todo API in this repository is a stable sample target. It exists so an AI coding agent can exercise and verify the loop around a real but small backend stack:

1. plan the change
2. implement the change
3. run tests
4. review the diff
5. debug failures
6. commit with evidence

This is not an end-user app, a deployment template, or a framework showcase.

## Stack

- Flask API in `app.py`
- Todo persistence in `repository.py`
- pytest coverage in `tests/`
- Docker image in `Dockerfile`
- API + Postgres runtime in `docker-compose.yml`
- OmX workflow artifacts under `.omx/`

## Verified Commands

Before marking any work complete, run the repository verification script:

```bash
./scripts/verify.sh
```

Check first-time ai-lab checkout setup:

```bash
./scripts/bootstrap-ai-lab.sh
```

Run the local test suite with the repository virtual environment:

```bash
.venv/bin/python -m pytest
```

Start the API and Postgres stack:

```bash
API_PORT=5001 docker compose up --build -d
```

Check container readiness:

```bash
docker compose ps
```

Smoke check the running API:

```bash
curl http://localhost:5001/
curl http://localhost:5001/todos
```

Stop the Docker stack:

```bash
docker compose down
```

## Workflow Target

Use this repo to test whether an AI CLI development environment can move through a full change loop without expanding scope:

- capture requirements in a spec or plan
- make a small, reviewable change
- keep the Flask sample working
- verify with pytest, Docker Compose, and smoke checks
- review the final diff and evidence
- commit only after the validation trail is clear

## Scope Guardrails

Allowed cleanup:

- rewrite README and workflow docs
- remove stale notes that do not support the testbed
- fix broken setup or documented commands
- make narrow reliability fixes that keep the sample target stable

Out of scope:

- new todo app features
- UI, auth, background jobs, or endpoint expansion
- large architecture rewrites
- repository abstraction layers or migration frameworks
- release deployment hardening
- new automation wrappers unless an already documented command is broken

## Documentation Map

- `docs/AI_ROLES.md` describes the AI roles used when exercising the workflow.
- `docs/WORKFLOW.md` describes the required Codex/OMX single-agent verification loop.
- `.omx/plans/ralplan-ai-dev-testbed-cleanup.md` contains the approved cleanup plan for this pass.
