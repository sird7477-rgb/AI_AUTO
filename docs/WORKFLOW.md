# AI 개발 워크플로우

이 저장소는 Codex/OMX 기반 CLI 개발 루프를 검증하기 위한 테스트베드다.

현재 단계는 Codex가 구현하고, 고정 검증과 Claude/Gemini 리뷰 게이트를 통과한 뒤에만 커밋 후보를 만드는 범용 자동화 루프다.

## 현재 루프

1. 요청 내용을 정리한다.
2. 플랜/인터뷰 강도를 판단한다.
3. 작은 작업은 바로 실행하고, 방향이 갈리는 작업은 짧은 질문을 먼저 한다.
4. 새 코드를 추가하기 전에 문제 제거, 기존 동작 재사용, 설정 변경, 문서화,
   삭제, 단순화로 해결할 수 있는지 먼저 확인한다. 코드가 필요하면 검증
   가능한 최소 변경만 수행한다.
5. 장기 정책, 표준, 아키텍처, 검증 체계, 배포/보안/데이터 작업은
   plan-first interview 후 진행하며, 인터뷰/플랜 산출물은
   `docs/PLANNING_VISUALIZATION_GUIDE.md`의 Markdown +
   Mermaid/Structurizr + Excalidraw 운영 기준을 따른다. 새 기획, 계획,
   전략, 아키텍처, 운영 판단 문서는 한국어를 기본으로 작성하되 명령어,
   파일 경로, 상태값, schema field, 코드 식별자는 영어를 유지한다. 기존
   영문 문서는 사용자 요청이나 해당 문서 정비 범위가 없으면 그대로 둔다.
6. 요청/입력/승인 경계가 애매하고 잘못 추측하면 결과가 달라지는 경우 먼저
   확인한다.
7. 운영 준비, dry-run, 배포, promotion, field evidence 작업은 필수 입력이
   missing/stale/incomplete/degraded이면 fail-closed로 멈춘다.
8. 작업 범위를 작게 고정한다.
9. 최소 변경만 수행한다.
10. 완료를 주장하기 전에 diff와 plan/TODO index 상태를 확인한다.
11. 코드 수정 후 관련 기획서/사양서/설계자료가 있으면 최종 diff를
    승인된 scope, non-goal, success criteria, execution boundary,
    verification plan과 대조한다. 관련 artifact가 없으면 그 이유를 기록한다.
12. `./scripts/verify.sh`를 실행한다.
13. 실패하면 수정 후 다시 검증한다.
14. 커밋 후보를 만들기 전에는 `./scripts/review-gate.sh`를 실행한다.
    - 리뷰에서 finding이 나오면 전체 게이트를 새로 돌리지 말고, 승인된
      finding scope에 한정한 targeted revision task로만 수정한다
      (`REVIEW_TARGETED_RECHECK` 기본 1). 변경 파일이 그 scope를 벗어나면
      (`REVIEW_TARGETED_RECHECK_SCOPE_OK=0`) 전체 게이트 또는 수동 검토로
      fail-closed한다.
    - 이미 개별 승인된 task diff를 2개 이상 합쳐 한 커밋으로 올릴 때는
      `REVIEW_INTEGRATION_ONLY=1`로 게이트를 돌린다. cross-task 상호작용만
      보는 light 패스이며(리뷰어 패널·trust 로직은 불변), provenance
      exact-match skip이 억제되어 통합 리뷰가 항상 실행된다.
    - 반복 루프 리뷰는 `REVIEW_CONTEXT_DETAIL=light`로 가볍게 돌리되, PR/병합
      직전의 결정 게이트에서는 `REVIEW_DECISION_GATE=1`로 돌려 전체 만장일치
      패널을 강제한다(provenance skip·targeted recheck·integration-only가 모두
      꺼지고 context=full). 결정 지점에서는 어떤 축소도 적용하지 않는다.
15. 리뷰어가 사용 불가하면 상태와 보강 경로를 기록한다.
16. 검증과 review gate 증거가 있을 때만 커밋 후보를 만든다.

## Writer 격리

한 working tree에는 한 writer만 둔다. 병렬 에이전트가 필요하면 에이전트별
git worktree를 쓰거나 다운스트림 세션을 자기 프로젝트 트리로 제한한다.
다른 에이전트가 만든 무관 파일은 stage하지 않는다.

## 플랜/인터뷰 강도

기본은 속도를 위해 즉시 실행이다. 단, 아래 기준으로 AI가 자체 판단해
인터뷰를 요청할 수 있다.

인터뷰와 플랜은 `docs/INTERVIEW_PLAN_LAYER.md`를 따른다. 목표는 질문 수
최소화가 아니라 질문 범위 최소화다. AI는 로컬 증거를 먼저 읽고, 한
질문에 하나의 결정만 담으며, 답변을 플랜 필드와 검증/정지 게이트에
연결한다.

- `none`: 명확하고 작고 되돌리기 쉬운 작업. 바로 실행한다.
- `light`: 결과를 바꾸는 결정이 하나 있다. 질문 하나로 확인하고 진행한다.
- `standard`: 여러 선택지가 결과를 바꾼다. 로컬 증거를 먼저 읽고 2-4개
  질문으로 확정한 뒤 짧은 플랜을 만든다.
- `deep`: 장기 정책, 표준, 아키텍처, 보안, 배포, 데이터, 검증 체계처럼
  실패 비용이 크다. 단계별 인터뷰, 플랜, 필요 시 리뷰어/서브에이전트
  검토를 거친다.

사용자가 "바로 진행"이라고 해도 destructive, credential, production,
scope 변경 작업의 승인 게이트는 유지한다.

프로젝트 초기 환경 구축에서는 템플릿 설치가 필요할 때만 `aiinit`을
실행한다. 이미 초기화된 프로젝트나 레지스트리 등록만 필요한 프로젝트는
재설치하지 않고 README/docs/scripts/package 파일을 먼저 확인한다. 이후
목적, 사용자, 산출물, non-goal, 스택, 검증, 리뷰 강도, 완료팩, 도메인팩,
운영 준비, plan/TODO ownership을 좁은 질문으로 확정한다. 이 단계의
플랜이 완료되어도 커밋/푸시/운영/파괴적 작업 승인은 별도로 받아야 한다.

## 필수 검증

작업 완료 전 반드시 실행한다.

```bash
./scripts/verify.sh
```

이 명령은 다음을 확인한다.

pytest 테스트
Docker Compose 실행
/ smoke check
/todos smoke check
Docker Compose 정리
automation-doctor 기본 진단
ai-lab bootstrap 진단

이 명령이 실패하면 작업은 완료된 것이 아니다.

`./scripts/verify.sh`는 `./scripts/bootstrap-ai-lab.sh`를 실행하고, bootstrap은 작업 중인 변경사항 자체를 경고로 만들지 않도록 `DOCTOR_SKIP_DIRTY_CHECK=1`로 automation-doctor를 실행한다. 단독으로 `./scripts/automation-doctor.sh`를 실행하면 dirty working tree는 계속 경고로 보고된다.

WSL/Docker Desktop 환경에서 `~/.docker/config.json`의 `credsStore:
desktop.exe`가 public image pull 중 credential 오류를 만들 수 있다.
`./scripts/verify.sh`는 `DOCKER_CONFIG`가 명시되지 않았고 이 패턴이 감지되면
전역 Docker 설정을 수정하지 않고 `/tmp/ai-lab-docker-config`를 임시
Docker config로 사용한다.

## 리뷰 게이트

커밋 후보 전 반드시 실행한다.

```bash
./scripts/review-gate.sh
```

이 ai-lab 본진은 공유 자동화와 검증/리뷰 스크립트를 직접 관리하므로
기본 리뷰 강도는 `strict`에 가깝게 운영한다. 단순 커밋/푸시처럼 이미
검증이 끝난 절차만 재실행하는 경우에는 사용자가 명시한 범위 안에서 추가
리뷰어 호출을 생략할 수 있다.

이 명령은 다음을 실행한다.

./scripts/verify.sh
활성 주관자를 제외한 reviewer rotation
필요 시 principal-subagent substitute 또는 Codex principal-rotation 리뷰
리뷰 verdict 요약

Gemini 리뷰 lane은 reviewer 이름과 산출물 호환성은 유지하지만, 기본 실행
명령은 Antigravity CLI `agy`다. 필요하면 `GEMINI_REVIEW_COMMAND`로 실행
명령만 덮어쓴다.

Codex 데스크탑앱처럼 Claude 리뷰어를 쓸 수 없는 외부 런타임에서는
`RUN_CLAUDE_REVIEW=0`으로 Claude 리뷰를 건너뛰고 나머지 리뷰어(Gemini +
Codex)로 gate를 운영할 수 있다. 함께 `REVIEW_EXECUTION_MODE=external`을 쓰면
제한 없는 대화형 터미널용 러너(`.omx/external-review/run-reviewers-latest.sh`)를
준비해서 리뷰어를 실행하고 verdict를 요약한다.

`GEMINI_REVIEW_COMMAND`를 raw `gemini`로 덮어쓰는 것은 `agy`가 없는 환경의
degraded 최후수단이다. raw `gemini`는 `agy`와 달리 모델이 class-fixed로
고정되지 않으므로(`docs/AI_MODEL_ROUTING.md`) 기본·권장 실행 명령은 `agy`를
유지한다. 또한 raw `gemini --sandbox`는 Docker/podman 컨테이너 런타임(또는
macOS Seatbelt)을 요구해서, WSL이나 Docker가 없는 데스크탑 런타임에서는
샌드박스 이미지 pull/기동 실패로 리뷰 자체가 중단된다. 이 경우 어댑터는
사용 가능한 컨테이너 런타임(데몬 응답 포함)을 찾지 못하면 자동으로 `--sandbox`를
생략하며(리뷰는 프롬프트만 읽는 read-only 경로라 안전), `GEMINI_SANDBOX=0`으로 명시적으로 끄거나
`GEMINI_SANDBOX=1`로(또는 Docker가 있으면 자동 감지로) 샌드박스를 유지할 수
있다.

기본 활성 주관자는 Codex다. `AI_AUTO_PRINCIPAL=claude|gemini`로 실행하면
해당 런타임은 self-review에서 제외되고, 나머지 런타임이 리뷰어로 회전한다.
이때 Codex 리뷰는 degraded fallback이 아니라 정상 principal-rotation
coverage로 기록된다. 세부 계약은 `docs/AI_PRINCIPAL_RUNTIMES.md`를 따른다.
단, Claude/Gemini 주관자는 launcher-owned principal marker가 있어야 하며,
수동 marker나 불일치 marker는 `principal_unavailable`로 중단한다.

Claude 또는 Gemini가 세션 제한, 주간 제한, quota/rate limit 등으로 응답할 수 없으면 해당 리뷰어는 `.omx/reviewer-state/`에 disabled 상태로 기록된다. disabled 리뷰어는 사용자가 `RESET_DISABLED_AI_REVIEWERS=claude|gemini|all`로 복구하기 전까지 스킵된다.

리뷰 컨텍스트가 제한을 넘으면 head/tail 압축본으로 정상 승인을 요청하지 않는다. 컨텍스트는 manifest가 있는 ordered split part로 나누고, 모든 part를 처리한 synthesis가 명시된 경우에만 최종 verdict를 신뢰한다. principal-subagent substitute와 Codex principal-rotation 리뷰는 축약 프롬프트만 보지 말고 관련 파일을 workspace에서 직접 읽고, 직접 확인한 파일과 확인하지 못한 관련 파일을 결과에 적는다.

한 리뷰어가 disabled 상태이면 남은 리뷰어 프롬프트는 그대로 유지하고,
disabled 역할은 활성 주관자의 subagent substitute가 담당한다. 이 대체
리뷰는 정규 외부 리뷰가 아니라 항상 degraded coverage다. usable verdict와
`Direct File Inspection` 증거가 있어도 `proceed_degraded`(degraded trust)로
보고하고, 그것조차 없으면 blocked로 남긴다. `proceed_degraded`인 경우
완료 보고에 degraded trust level과 누락 리뷰어 상태를 반드시 포함한다.

루프 내 역할 경계:

- Codex/GPT 리더는 구현, 조율, 검증, 완료 보고를 책임진다.
- 리더가 작업 중 스스로 모델을 바꿨다고 표현하지 않는다.
- 비용/속도 최적화가 필요하면 탐색, 파일 매핑, 가벼운 합성처럼 범위가
  좁은 작업만 역할별 서브에이전트나 OMX lane에 위임한다.
- 세부 위임 기준은 `docs/AUTOMATION_OPERATING_POLICY.md`의
  `Subagent Utilization`을 따른다.
- Claude/Gemini는 기본 Codex 주관자 모드에서 독립 외부 리뷰어다.
- Claude/Gemini가 활성 주관자이면 해당 런타임은 self-review하지 않고,
  나머지 외부 런타임과 Codex가 같은 산출물 경로에서 reviewer rotation을
  구성한다.
- principal-subagent substitute 리뷰는 expected reviewer가 빠졌을 때 활성
  주관자의 subagent가 맡는 대체 lane이며, 정규 외부 리뷰가 아니라 항상
  degraded coverage다(usable verdict·직접 파일 확인이 있어도 `proceed_degraded`,
  없으면 blocked).

Ralph/완료 루프는 요청 범위 안에서 발견한 미승격 규칙, 문서/도구 괴리,
누락 도구, 계획만 있고 정규화되지 않은 항목을 가능한 한 같은 루프에서
정규 산출물로 승격한다. 외부 한도나 권한처럼 즉시 해결할 수 없는 하드
블로커만 증거와 함께 보고한다.

## 실패 패턴과 승인 마찰

반복 가능한 실패나 공통 개선 아이디어는 raw log 대신 sanitized feedback으로
남긴다.

```bash
./scripts/record-feedback.sh \
  --type failure_pattern \
  --repeat-key git:index-lock-permission \
  --summary ".git/index.lock permission denied during commit" \
  --resolution "Use approved escalated git commit path" \
  --surface git \
  --severity medium
```

기록 기준은 `docs/AUTOMATION_OPERATING_POLICY.md`를 따른다. `.omx/feedback/`
아래 queue는 로컬 런타임 데이터이며 원격 커밋 대상이 아니다.

권한 승인은 우회하지 않는다. 반복되는 비파괴 명령은 approved prefix나
repo helper로 마찰을 줄이고, destructive/credential/production 작업은 계속
명시 승인 대상으로 둔다.

운영 산출물 규칙:

- operational readiness, dry-run validity, promotion readiness, field-start
  evidence를 주장하는 작업은 필수 입력이 degraded이면 분석 전용으로만
  계속할 수 있다.
- partial/degraded run은 진단 리포트는 남길 수 있지만 accepted operating
  artifact나 downstream input으로 저장하지 않는다.
- operational dry-run/deployment 전에는 read-only/auth/network 권한, DB,
  token, cooldown, output path, API budget, side-effect boundary를 preflight로
  확인한다.
- sandboxed external API probe 실패는 provider/user network 실패로 단정하지
  않고, 승인된 real-network path로 1회 재시도한 증거를 함께 남긴다.
- dry-run/field-test 중 이상 로그가 발견되면 `docs/INCIDENT_OPS.md`의
  Incident Ops 정책에 따라 observe/diagnose/safe_recover는 선조치하고,
  guarded_recover는 정책상 1회만 허용하며, ask_required/blocked 조치는
  증거를 남긴 뒤 사용자 승인 경계에서 멈춘다.
- 장시간 감시 작업은 프로젝트별 heartbeat, quiet, active-incident 보고
  주기를 정하고, 주기 보고에는 현재 phase, 마지막 정상 체크, 자동 조치,
  차단/승인 필요 조치, 다음 체크 시각을 포함한다.
- UI field-test에서는 route/viewport/screenshot, console error, network
  status, operator flow step, 다음 조작 가능 여부를 incident log에 남긴다.
- 작업 완료 전 plan index 또는 TODO source of truth를 갱신하거나 변경 없음
  이유를 기록한다.
- 코드 수정이 기획서/사양서/설계자료와 다르면 구현 drift, outdated spec
  drift, material scope change 중 하나로 분류한다. 구현 drift는 수정하거나
  되돌리고, outdated spec drift는 승인 범위가 변하지 않을 때만 artifact를
  갱신하며, scope change는 새 계획/승인 전까지 구현을 멈춘다.
- 코드가 승인된 범위 일부만 구현했고 자료와 충돌하지 않으면 완료된 부분과
  남은 부분을 보고한다. 요청한 완료 기준이 아직 남아 있으면 계속 진행한다.
- 긴 runbook/checklist/detail은 `AGENTS.md`에 계속 붙이지 말고 linked docs로
  분리한다.
- review artifact 정리는 보관(archive) 기본값을 유지하고, 삭제(delete)는
  명시 옵션으로만 실행한다.
- AI agent, 외부 reviewer, runtime adapter, MCP/tool connector, 장기 자동화,
  또는 트렌드 기반 자동화 개선을 다룰 때는
  `docs/AI_AUTOMATION_TREND_HARDENING.md`를 기준으로 agent identity,
  tool permission class, kill switch/revoke, local observability, recurring
  trend report 경계를 확인한다. 이 문서는 새 런타임 권한을 부여하지 않으며,
  write/credential/network/publish 권한 확대는 별도 계획과 리뷰 게이트가
  필요하다.

완료 보고에 포함할 것
변경 파일
diff 요약
실행한 검증 명령
검증 결과
설계자료 대조 결과: aligned, updated, not applicable, or blocked
남은 warning 또는 제한사항

사용자에게 보고할 때는 변수명, 내부 상수명, 환경변수명, raw identifier를
앞세우지 말고 쉬운 한국어로 결과를 먼저 설명한다. 재현이나 사용자 조치에
필요한 명령어, 파일 경로, 리뷰 verdict 같은 기술 식별자는 필요한 경우에만
덧붙인다.
허용 범위는 `AGENTS.md`를 따른다. 이 저장소에서는 문서/워크플로우 정리,
좁은 안정성 수정, 검증 스크립트 개선, 테스트베드 유지보수만 새 계획 없이
허용한다. todo 앱 기능, UI, 인증, 백그라운드 작업, 대규모 구조 변경,
배포용 하드닝은 새 계획 없이는 금지한다.
커밋 규칙

커밋은 아래 조건을 만족한 뒤에만 진행한다.

diff를 검토했다.
./scripts/verify.sh가 통과했다.
남은 warning을 기록했다.
커밋 메시지가 실제 변경 내용과 일치한다.
운영 명령

자동화 진단:

```bash
./scripts/automation-doctor.sh
```

ai-lab checkout 진단:

```bash
./scripts/bootstrap-ai-lab.sh
```

AI_AUTO 본진 위치 찾기:

```bash
AI_AUTO
AI_AUTO --status
```

새 프로젝트 초기화:

```bash
aiinit
```

기존 프로젝트 레지스트리 등록:

```bash
ai-register /path/to/existing-repo
ai-register --prune
```

리팩터링 후보 스캔:

```bash
ai-refactor-scan /path/to/project
```

이 명령은 대상 저장소를 수정하지 않고 큰 파일, 긴 Python 함수/클래스,
import가 많은 파일을 출력한다. 주식자동매매처럼 코드가 한 파일에 뭉친
프로젝트에서는 이 결과를 기준으로 먼저 동작 고정 테스트를 만들고,
도메인/입출력/전략/어댑터 경계로 작은 모듈 분리를 계획한다.

Odoo 등 특정 프레임워크 검증 패턴은 `docs/DOMAIN_PACKS.md`와 설치된
`.omx/domain-packs/` 참고자료를 기준으로 적용 여부를 먼저 확정한 뒤 다룬다.
재사용 도메인팩을 새로 만들거나 수정할 때만
`docs/DOMAIN_PACK_AUTHORING_GUIDE.md`를 따른다.

리빌드 플랜:

```bash
ai-rebuild-plan /path/to/project
```

AI에게 `리빌드 플랜`, `리빌딩 플랜`, `rebuild plan`, `ai-rebuild-plan`을
요청하면 이 read-only 진단/계획 단계로만 들어간다. 이 단계는 대상 저장소,
git 상태, 자동화 템플릿 최신성, 도메인팩 원본/설치본 상태, 리팩터링 후보,
기존 동작 고정 테스트 필요성을 확인하고 계획을 만든다. 파일을 수정하지
않으며 리빌딩 실행을 시작하지 않는다.

`리빌드 실행`, `리빌딩 실행`, `rebuild run`은 별도 실행 요청이다. 승인된
계획 artifact, 최신 도메인팩 검증, 동작 고정 테스트 또는 smoke check,
모듈 경계와 non-goal이 없으면 실행하지 않는다. 도메인팩은 실행 허가증이
아니라 리빌딩 전 확인해야 하는 안전 계약이다.

### 리빌드 보조 게이트

외부 도구를 붙이더라도 기본 실행 엔진으로 쓰지 않는다. `ai-context-pack`
계열 컨텍스트 패킹, `ai-codemod-scan` 계열 구조 검색, `ai-boundary-check`
계열 경계 검사, `ai-split-plan` Python 분리 계획은 read-only 보조 게이트다.
명시 요청, 대형/경계 변경, `ai-refactor-scan`에서 확인된 material smell,
도메인-critical 변경, stale evidence, 구조적 검증 실패, 또는 리뷰어가
리빌드/리팩터/경계 검사를 요청한 경우에만 제안하거나 실행한다.

이 보조 게이트는 기본적으로 advisory/fail-open이다. 도구가 없다고 작은
되돌릴 수 있는 작업, 일반 verify, 커밋 준비를 막지 않는다. 단, 리빌드
실행, 마이그레이션, production/real-data, destructive, domain-critical
경로에서는 프로젝트 정책에 따라 fail-closed로 승격할 수 있다.

`ai-codemod-apply`, autofix처럼 파일을 수정하는 도구는 별도 실행 게이트다.
명시 실행 요청, 승인된 scoped plan artifact, exact target scope, 검토된
dry-run diff/summary, rollback path, post-apply verification이 없으면
실행하지 않는다.

Python 리빌드에서는 도메인팩의 `split-rules.json`이 심볼을 직접 명시하는
부담을 줄이는 자동 제안층이 될 수 있다. `ai-split-plan`은 top-level
function/class 이동 후보만 제안하고, `ai-split-dry-run` 검토와
`ai-split-apply --execute-approved-plan` 승인 게이트를 통과해야 파일을
수정한다. 이 도구는 import/call site를 자동 재작성하지 않으므로 리빌드
실행 전후 behavior-locking test가 필수다.

범용 템플릿은 UI, 배포, 보안, 데이터, 성능, 관측성 완료 기준이 필요한
프로젝트를 위해 `docs/*_COMPLETION.md` 완료팩을 함께 설치한다. 단, 이
ai-lab 저장소 자체는 CLI/API 자동화 테스트베드이므로 새 계획 없이 UI,
배포, 보안, 데이터, 성능, 관측성 기능 작업을 하지 않는다.
