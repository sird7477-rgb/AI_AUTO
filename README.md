# AI_AUTO

AI_AUTO is a Codex/OMX automation testbed for reusable AI development
workflows. It keeps a small Flask todo API as the stable sample target, but the
repository's main purpose is to build and verify the operating system around AI
coding work:

1. plan the change
2. implement the change
3. run tests
4. review the diff
5. debug failures
6. collect reusable feedback or knowledge when appropriate
7. commit with evidence

This is not an end-user app, a deployment template, or a framework showcase.

## Stack

- Flask sample API in `app.py`
- Todo persistence in `repository.py`
- pytest coverage in `tests/`
- Docker image in `Dockerfile`
- API + Postgres runtime in `docker-compose.yml`
- Optional domain packs under `templates/domain-packs/`
- Global helper source commands under `tools/`
- Codex/OMX workflow artifacts under `.omx/`

## What This Repository Maintains

- `ai-auto setup` for adopting the global AI_AUTO workflow on another
  git repository (no framework files are vendored into the project; it installs
  hook shims, ignores `.omx/`, and removes leftover vendored copies).
- `./scripts/verify.sh` and `./scripts/review-gate.sh` for the local
  verify-review completion loop, reachable in a project via `ai-auto verify` /
  `ai-auto gate`.
- Active principal runtime contracts so `codex`, `claude`, or `gemini` can be
  recorded as the current AI_AUTO/OMX principal while preserving the same
  workflow, permissions, and `.omx/*` artifact paths.
- Domain-pack authoring and application rules for optional project-specific
  guidance.
- Feedback and knowledge collection helpers for promoting useful project
  lessons back into the source workflow.
- Read-only rebuild, split-planning, and plan-quality helper commands for
  larger maintenance work.
- A side-effect-free MicroWork validator (`micro-work` / `scripts/micro-check.sh`)
  that checks a "micro unit" definition (goal, scope, smallest-useful-wedge,
  non-goals, required evidence, completion criteria) and reports scope drift
  against the current changes; review context surfaces it as a report-only audit.

## Verified Commands

Before marking any work complete, run the repository verification script:

```bash
./scripts/verify.sh
```

In WSL/Docker Desktop environments, `verify.sh` automatically uses a temporary
Docker config when `~/.docker/config.json` points at `credsStore: desktop.exe`.

`verify.sh` now includes:

- pytest
- shell syntax checks
- ShellCheck at warning severity for repo/template shell scripts
- automation contract tests
- Docker Compose API/Postgres smoke checks

By default, `./scripts/verify.sh` runs the full machinery suite and product
smoke. Use `AI_AUTO_VERIFY_SCOPE=product ./scripts/verify.sh` only for
review-gate-style product smoke, or `AI_AUTO_VERIFY_SCOPE=machinery
./scripts/verify.sh` for the self-test/tooling suite without Docker smoke.

ShellCheck info/style findings are not part of the required gate yet. Treat them
as cleanup candidates unless a later plan promotes a narrower rule set.

Before a commit candidate, run the review gate after verification:

```bash
./scripts/review-gate.sh
```

Codex is the default principal. Claude/Gemini principal runs require a
launcher-owned evidence marker, then `AI_AUTO_PRINCIPAL` rotates the remaining
runtimes into review coverage:

```bash
AI_AUTO_PRINCIPAL=claude ./scripts/review-gate.sh
AI_AUTO_PRINCIPAL=gemini ./scripts/review-gate.sh
```

Manual marker creation is not sufficient proof. Without launcher-owned evidence,
review-gate fails closed with `principal_unavailable`.

When a candidate includes untracked text artifacts that should be reviewed, run
the gate with untracked content included after confirming generated output and
secrets are ignored:

```bash
REVIEW_INCLUDE_UNTRACKED_CONTENT=1 REVIEW_UNTRACKED_MANUAL_REVIEWED=1 ./scripts/review-gate.sh
```

For targeted diffs, review context derives the untracked allowlist from tracked
changed paths. Set `REVIEW_UNTRACKED_ALLOWLIST` only when you need to override
that scope; unrelated untracked files are reported but do not block the gate.

Check first-time ai-lab checkout setup:

```bash
./scripts/bootstrap-ai-lab.sh
```

Install Ubuntu prerequisites for a fresh checkout:

```bash
./scripts/install-ubuntu-prereqs.sh
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

Use this repo to test whether an AI CLI development environment can move
through a full change loop without expanding scope:

- capture requirements in a spec or plan
- make a small, reviewable change
- keep the Flask sample working
- verify with pytest, Docker Compose, and smoke checks
- review the final diff and evidence
- preserve project-specific rules while updating shared automation guidance
- record reusable feedback or knowledge without leaking private project details
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
- `docs/GLOBAL_TOOLS.md` describes `ai-auto`, `workspace-scan`, and bootstrap helper setup.
- `docs/OBSIDIAN_INTEGRATION.md` describes curated Obsidian note publishing and scoped plain-guide folder pushes.
- `docs/NEW_PROJECT_GUIDE.md` explains how to set up the AI_AUTO workflow on another repository.
- `docs/DOMAIN_PACKS.md` explains reusable domain packs and their application lifecycle.
- `docs/DOMAIN_PACK_AUTHORING_GUIDE.md` defines quality rules for creating or changing domain packs.
- `docs/MULTI_AI_COLLABORATION.md` documents principal-runtime review rotation, substitute reviewer coverage, degraded-review behavior, and command keywords.
- `docs/AI_PRINCIPAL_RUNTIMES.md` documents active principal selection, permission parity, reviewer rotation, and shared artifact paths.
- `knowledge/Odoo.sh KB/` contains the promoted Odoo 19.0 / Odoo.sh working KB prepared for Obsidian.
- `Odoo19_Docs_KB` in the configured Obsidian vault is the Odoo 19 official-docs baseline (`odoo-19-docs-2026-06`): for Odoo work, use the project guide first, then the matching developer or user-manual `slim` page for navigation only, then one matching `raw` page, then the pinned source URL.
- `plans/AI_AUTO_FEEDBACK_QUEUE_REGULAR_PROMOTION_PLAN_2026-06-04.md` tracks the seven-item regular-promotion execution plan.
- `plans/ODOO_SH_KB_DRAFT_PLAN_2026-06-04.md` tracks the Odoo.sh KB promotion and Obsidian publish plan.
- `plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md` tracks structural workflow improvements that should stay outside immediate patch churn.
- `.omx/plans/ralplan-ai-dev-testbed-cleanup.md` contains the approved cleanup plan for this pass.

## 클론 후 전역파일 설치 방법

Git clone으로 내려받는 것은 이 저장소에 커밋된 파일뿐입니다. `~/.codex`,
`~/bin`, Claude/Gemini 로그인, SSH key, Docker image, `.venv`, `.omx` 런타임
결과물 같은 로컬/전역 상태는 같이 내려받아지지 않습니다.

## 새 Ubuntu PC 초기 설치

Ubuntu만 설치된 새 PC에서는 먼저 OS 패키지, Python 가상환경, Docker, Node/npm,
레포 전역 helper를 준비해야 합니다. 이 저장소에는 해당 작업을 한 번에 실행하는
스크립트가 있습니다.

```bash
git clone git@github.com:sird7477-rgb/AI_AUTO.git
cd AI_AUTO
./scripts/install-ubuntu-prereqs.sh
```

HTTPS로 클론하려면 아래처럼 바꿔서 실행합니다.

```bash
git clone https://github.com/sird7477-rgb/AI_AUTO.git
cd AI_AUTO
./scripts/install-ubuntu-prereqs.sh
```

이 스크립트가 설치하거나 준비하는 항목은 다음과 같습니다.

- `git`, `curl`, `ca-certificates`, `bash`
- `python3`, `python3-venv`, `python3-pip`
- `nodejs`, `npm`
- `docker.io`와 사용 가능한 Docker Compose v2 plugin 패키지
- `shellcheck`
- `hyperfine`
- `.venv` 가상환경과 `requirements.txt` Python 패키지
- `./scripts/install-global-files.sh`를 통한 `~/bin` helper symlink

Docker 권한을 위해 현재 사용자를 `docker` 그룹에 추가할 수 있습니다. 이 경우
권한은 보통 로그아웃 후 다시 로그인해야 적용됩니다.

```bash
exit
```

다시 로그인한 뒤 저장소에서 확인합니다.

```bash
cd /path/to/AI_AUTO
./scripts/bootstrap-ai-lab.sh
./scripts/automation-doctor.sh
./scripts/verify.sh
```

AI 호출용 CLI까지 npm으로 설치하려면 아래 옵션을 사용합니다.

```bash
./scripts/install-ubuntu-prereqs.sh --install-ai-cli
```

이 옵션은 다음 npm 패키지 설치를 시도합니다.

```bash
sudo npm install -g \
  @openai/codex \
  @anthropic-ai/claude-code
```

AI CLI 설치에는 Node.js 18 이상이 필요합니다. Ubuntu 기본 패키지의 Node.js가
너무 낮으면 최신 Node.js LTS를 먼저 설치한 뒤 다시 실행합니다.

Gemini 리뷰 lane의 기본 실행 명령은 Antigravity CLI `agy`입니다. `agy`는
위 npm 설치 목록에 포함되지 않으므로 Antigravity가 제공하는 설치/업데이트
경로로 별도 설치한 뒤 `agy --version`으로 확인합니다.

```bash
node --version
./scripts/install-ubuntu-prereqs.sh --skip-system --install-ai-cli
```

Node.js가 낮아서 실패하면 NodeSource 같은 신뢰하는 배포 경로로 Node.js 20 LTS
이상을 설치한 뒤 다시 시도합니다. 예시는 다음과 같습니다.

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version
./scripts/install-ubuntu-prereqs.sh --skip-system --install-ai-cli
```

사용자가 직접 해야 하는 작업은 자동화하지 않습니다.

- GitHub에 SSH로 접근하려면 SSH key 생성과 GitHub 등록이 필요합니다.
- private repository를 클론하려면 GitHub 인증이 필요합니다.
- Codex, Claude, Antigravity(`agy`)는 각 CLI 설치 후 로그인해야 합니다.
- API key를 쓰는 방식이라면 각 서비스의 key를 직접 발급하고 shell profile에
  등록해야 합니다.

복붙용 SSH key 생성 예시는 다음과 같습니다.

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
cat ~/.ssh/id_ed25519.pub
```

출력된 공개키를 GitHub의 SSH keys에 등록한 뒤 확인합니다.

```bash
ssh -T git@github.com
```

복붙용 AI CLI 로그인 예시는 다음과 같습니다.

```bash
codex login
claude login
agy
```

API key 환경변수를 직접 쓰는 경우에는 사용하는 서비스에 맞게 `~/.bashrc`에
추가합니다. 실제 key 값은 본인 계정에서 발급한 값으로 바꿉니다.

```bash
cat >> ~/.bashrc <<'EOF'
export OPENAI_API_KEY="replace-with-your-openai-key"
export ANTHROPIC_API_KEY="replace-with-your-anthropic-key"
export GEMINI_API_KEY="replace-with-your-gemini-key"
EOF
source ~/.bashrc
```

주의할 점:

- 이 저장소의 스크립트는 API key를 만들거나 저장해주지 않습니다.
- 이 저장소의 스크립트는 Claude/Gemini/Codex 로그인을 대신하지 않습니다.
- `--install-ai-cli`는 CLI 패키지만 설치하고 인증은 사용자가 직접 해야 합니다.
- npm 전역 설치 패키지는 `scripts/install-ubuntu-prereqs.sh`에 명시된 이름을
  설치합니다. 패키지명을 바꾸려면 각 서비스의 공식 설치 문서를 먼저 확인합니다.

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
~/bin/ai-auto -> <현재 클론 경로>/tools/ai-auto
~/bin/aiinit  -> <현재 클론 경로>/tools/ai-auto
~/bin/workspace-scan -> <현재 클론 경로>/tools/workspace-scan
```

이후 새 프로젝트에서는 어디서든 다음 명령으로 전역 AI_AUTO 모드를 도입할 수 있습니다(프레임워크 파일을 복사하지 않고 훅 심만 설치).

```bash
ai-auto setup
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

만약 `ai-auto` 또는 `workspace-scan` 명령이 실행되지 않으면 `~/bin`이 PATH에 없을
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

## Installed Local Tools

AI_AUTO currently expects these local tools for the full source-checkout
workflow:

- `shellcheck`: required by `./scripts/verify.sh` at warning severity.
- `hyperfine`: used by `scripts/benchmark-command.py` for optional benchmark
  evidence capture.
- `scripts/todo-report.py`: reads the canonical backlog and fails with
  `--fail-on-active` if active TODO or policy-attention items remain.
- `docker`: required for the final API/Postgres smoke check in `verify.sh`.
- `claude` and `agy`: used by `review-gate`; if a reviewer is unavailable, the
  active principal's subagent substitute covers that lane as degraded coverage
  (`proceed_degraded` / degraded trust), not independent external review.

Benchmark evidence is observational. It does not replace `verify.sh` or
`review-gate`.

Optional Codex startup notices can be installed with:

```bash
./scripts/install-global-files.sh --install-codex-drift-notice
```

In the AI_AUTO home checkout, this startup hook prints an `OBSIDIAN OUTPUT CHECK`
block when validated knowledge drafts are waiting across AI_AUTO and registered
projects. That notice is read-only. To publish, run `scripts/obsidian-autopush.sh`
from the home checkout (or say `옵시디언 푸시해줘`). By rule it auto-promotes
`local_private` drafts to `shareable_summary` when the draft's `surface` is on
the allowlist (AI_AUTO tooling surfaces: review-gate, workflow, ai-review,
model-routing, ai-auto-template, domain-pack, obsidian, shell-integration,
verification, browser-verification) and the note is sanitized and passes a
secret/redaction preflight, then publishes the shareable set to the vault at
`obsidian.ai_auto_vault_dir` in `.omx/local-config.json`. Off-allowlist surfaces
(e.g. `ssh`, project-specific surfaces), unsanitized, or secret-like drafts stay
`local_private` and are never published (default-deny, fail-closed). Override the
allowlist with `AI_AUTO_AUTOPROMOTE_SURFACES`, disable promotion with
`--no-auto-promote`, or preview with `--dry-run`. Auto-push on startup is
intentionally not wired in — publishing only happens when you run the command.

정리하면, 클론 직후의 권장 흐름은 다음과 같습니다.

```bash
git clone git@github.com:sird7477-rgb/AI_AUTO.git
cd AI_AUTO
./scripts/install-ubuntu-prereqs.sh
./scripts/automation-doctor.sh
./scripts/verify.sh
```

AI에게 맡기는 경우에는 저장소를 연 뒤 이렇게 요청하면 됩니다.

```text
전역파일 설치해줘
```
