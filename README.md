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

Install or repair the global helper files for this checkout:

```bash
./scripts/install-global-files.sh
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
- `docs/WORKFLOW.md` describes the required Codex/OMX verification and review-gate loop.
- `docs/INTERVIEW_PLAN_LAYER.md` defines the reusable interview, plan, ambiguity, and execution-gate contract.
- `docs/CURRENT_STATE.md` is the current handoff document for completed automation capabilities, known limitations, and next-stage boundaries.
- `docs/GLOBAL_TOOLS.md` describes `aiinit`, `workspace-scan`, and bootstrap helper setup.
- `docs/NEW_PROJECT_GUIDE.md` explains how to apply the generic automation template to another repository.
- `docs/MULTI_AI_COLLABORATION.md` documents the Claude/Gemini review gate, degraded-review behavior, and command keywords.
- `.omx/plans/ralplan-ai-dev-testbed-cleanup.md` contains the approved cleanup plan for this pass.

## 클론 후 전역파일 설치 방법

Git clone으로 내려받는 것은 이 저장소에 커밋된 파일뿐입니다. `~/.codex`,
`~/bin`, Claude/Gemini 로그인, SSH key, Docker image, `.venv`, `.omx` 런타임
결과물 같은 로컬/전역 상태는 같이 내려받아지지 않습니다.

새 PC나 새 작업공간에서 이 저장소를 클론한 뒤 AI에게 아래처럼 말하면 됩니다.

```text
전역파일 설치해줘
```

이 저장소의 `AGENTS.md`에는 위 문장을 받았을 때 AI가 실행해야 할 명령이
등록되어 있습니다. AI는 저장소 루트에서 다음 명령을 실행해야 합니다.

```bash
./scripts/install-global-files.sh
```

이 명령은 `~/bin` 아래 전역 helper symlink만 생성하거나 복구합니다.

설치 또는 복구되는 전역 helper는 다음 symlink입니다.

```text
~/bin/ai-auto-init -> <현재 클론 경로>/tools/ai-auto-init
~/bin/aiinit       -> <현재 클론 경로>/tools/ai-auto-init
~/bin/workspace-scan -> <현재 클론 경로>/tools/workspace-scan
```

이후 새 프로젝트에서는 어디서든 다음 명령으로 자동화 템플릿을 설치할 수 있습니다.

```bash
aiinit
```

`workspace-scan`은 `~/workspace` 아래 git 저장소들의 자동화 준비 상태를 훑어보는
전역 helper입니다.

```bash
workspace-scan
```

주의할 점:

- 이 명령은 외부 프로그램을 설치하지 않습니다.
- 이 명령은 shell profile을 직접 수정하지 않습니다.
- 이 명령은 GitHub token, SSH key, Claude/Gemini 로그인 세션을 만들지 않습니다.
- 이 명령은 `automation-doctor --fix`를 실행하지 않습니다.
- 이미 존재하는 일반 파일을 덮어쓰지 않습니다.
- 안전한 symlink 생성/복구와 결과 요약만 수행합니다.

만약 `aiinit` 또는 `workspace-scan` 명령이 실행되지 않으면 `~/bin`이 PATH에 없을
가능성이 큽니다. 현재 터미널에서는 아래 명령으로 임시 적용할 수 있습니다.

```bash
export PATH="$HOME/bin:$PATH"
```

영구 적용은 선택사항입니다. 사용하는 shell 설정 파일을 먼저 열어서 내용을 확인한 뒤
같은 줄을 직접 추가합니다. Bash를 쓴다면 보통 `~/.bashrc`에 추가합니다.

```bash
export PATH="$HOME/bin:$PATH"
```

그 다음 새 터미널을 열거나 아래 명령을 실행합니다.

```bash
source ~/.bashrc
```

전역파일 설치 후 상태 확인은 아래 순서로 하면 됩니다.

```bash
./scripts/automation-doctor.sh
./scripts/verify.sh
```

정리하면, 클론 직후의 권장 흐름은 다음과 같습니다.

```bash
git clone git@github.com:sird7477-rgb/AI_AUTO.git
cd AI_AUTO
./scripts/install-global-files.sh
./scripts/automation-doctor.sh
./scripts/verify.sh
```

AI에게 맡기는 경우에는 저장소를 연 뒤 이렇게 요청하면 됩니다.

```text
전역파일 설치해줘
```
