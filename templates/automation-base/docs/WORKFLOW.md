# AI 개발 워크플로우

이 저장소는 Codex/OMX 기반 범용 자동화 기준을 사용한다.

`aiinit` 직후의 기본 파일은 완성된 프로젝트 설정이 아니다. 첫 작업 전에
프로젝트 인터뷰를 통해 목적, 범위, 검증 기준, 금지 범위를 채운 뒤에
개발 루프를 시작한다.

## 초기 온보딩

초기 온보딩의 상세 체크리스트는 `docs/AUTOMATION_OPERATING_POLICY.md`가
권위 문서다. 질문 방식, 답변 매핑, ambiguity, plan/run boundary는
`docs/INTERVIEW_PLAN_LAYER.md`를 따른다.

요약 절차:

1. 템플릿 설치가 필요한 새 프로젝트에서는 `aiinit`을 실행한다. 이미
   초기화된 프로젝트나 레지스트리 등록만 필요한 프로젝트는 재설치하지 않는다.
2. 기존 README, docs, package/script 파일, 과거 메모를 먼저 읽고 로컬 증거로
   알 수 없는 항목만 좁은 질문으로 인터뷰한다.
3. `docs/AUTOMATION_OPERATING_POLICY.md`의 온보딩 체크리스트에 따라
   프로젝트 운영 규칙, 완료팩, 도메인팩, 검증 기준을 확정한다.
   UI가 필요하면 `docs/UI_COMPLETION.md`를 기준으로 UI 완료/검증 조건을
   정한다.
   Incident Ops 기준을 확인한다. dry-run/field-test 감시, 자동 조치 class,
   incident log 필드, UI field-test evidence, heartbeat/quiet/active-incident
   보고 기준을 정한다.
   sandbox-vs-real-network evidence 기준과 plan index/TODO reconciliation
   ownership도 함께 확정한다.
4. `AGENTS.md`, `docs/WORKFLOW.md`, `scripts/verify.sh`를 프로젝트에 맞게
   반영한다.
5. `./scripts/automation-doctor.sh`, `./scripts/verify.sh`, 필요한
   `./scripts/review-gate.sh`를 실행한다.
6. 커밋/푸시는 별도 사용자 승인이 있을 때만 진행한다.

## 도메인팩

도메인팩 선택, 거절, 적용 기준은 `docs/DOMAIN_PACKS.md`를 따른다.
`automation-base`는 범용 기준이며 별도 generic domain pack은 없다. 일치하는
도메인팩이 없으면 설치된 팩을 non-goal로 기록하고 범용 baseline과 필요한
완료팩만 사용한다.

## 현재 루프

1. 요청 내용을 정리한다.
2. 플랜/인터뷰 강도를 판단한다.
3. 작은 작업은 바로 실행하고, 방향이 갈리는 작업은 짧은 질문을 먼저 한다.
4. 장기 정책, 표준, 아키텍처, 검증 체계, 배포/보안/데이터 작업은
   plan-first interview 후 진행한다.
5. 요청/입력/승인 경계가 애매하고 잘못 추측하면 결과가 달라지는 경우 먼저
   확인한다.
6. 운영 준비, dry-run, 배포, promotion, field evidence 작업은 필수 입력이
   missing/stale/incomplete/degraded이면 fail-closed로 멈춘다.
7. 작업 범위를 작게 고정한다.
8. 최소 변경만 수행한다.
9. 완료를 주장하기 전에 diff와 plan/TODO index 상태를 확인한다.
10. `./scripts/verify.sh`를 실행한다.
11. 실패하면 수정 후 다시 검증한다.
12. 커밋 후보를 만들기 전에는 `./scripts/review-gate.sh`를 실행한다.
13. 리뷰어가 사용 불가하면 상태와 보강 경로를 기록한다.
14. 검증과 review gate 증거가 있을 때만 커밋 후보를 만든다.

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

## 리뷰 강도

기본값은 `standard`다. 프로젝트 온보딩에서 아래 중 하나를 선택하고
`AGENTS.md`와 이 문서에 기록한다.

- `lightweight`: 문서, 로컬 설정, 작고 되돌리기 쉬운 변경은
  `./scripts/verify.sh`만 기본으로 한다. 공유 자동화, 동작 변경, 배포,
  보안, 데이터, UI workflow 변경에는 review-gate를 실행한다.
- `standard`: 일반 기본값. 작업 중에는 `./scripts/verify.sh`를 우선하고,
  커밋 후보 또는 위험도 있는 변경에는 review-gate를 실행한다.
- `strict`: 금융, 보안, 배포, 데이터 손실, 규제, 고위험 자동화는 커밋
  후보마다 `./scripts/verify.sh`와 `./scripts/review-gate.sh`를 실행한다.

공유 자동화, 검증/리뷰 스크립트, 모델 라우팅, 데이터, 배포, 보안, 사용자
가시 workflow를 건드리면 한 단계 더 강하게 운영한다. 리뷰를 생략한 경우
완료 보고에 선택한 리뷰 강도와 생략 이유를 명시한다.

## 실패 패턴 피드백

반복 가능한 실패나 공통 개선 아이디어는 raw log 대신 짧은 요약으로만
기록한다.

```bash
./scripts/record-feedback.sh \
  --type failure_pattern \
  --repeat-key verify:docker-socket-permission \
  --summary "Docker socket permission blocked verify" \
  --resolution "Retry approved external execution when Docker access is required" \
  --surface verify \
  --severity medium
```

기록 기준:

- 같은 repeat key가 2회 이상 반복된다.
- verify, review, commit, push, deploy, onboarding을 막았다.
- 사용자 수동 개입이 필요했다.
- AI의 잘못된 추측으로 재작업이 발생했다.
- 프로젝트 local fix를 AI_AUTO 템플릿 개선 후보로 올릴 가치가 있다.

금지:

- token, secret, credential, 고객정보, private log, raw stack trace 전문
- 단순 오타나 일회성 에러
- 사용자가 채택하지 않은 추측성 아이디어

`.omx/feedback/queue.jsonl`은 git에 올리지 않는 로컬 queue다. AI_AUTO가
나중에 여러 프로젝트의 queue를 취합하더라도, 원본 로그가 아니라 정제된
패턴만 공통 지침 후보로 승격한다.

## 권한 승인 마찰 관리

승인 자체를 우회하지 않는다. 대신 안전한 반복 작업은 프로젝트 지침에 명확히
기록해 같은 승인을 반복하지 않도록 한다.

- 검증, 리뷰 게이트, helper 설치, 커밋, 푸시처럼 반복되는 비파괴 명령은
  좁은 approved prefix 또는 repo helper를 사용한다.
- Docker socket, git index lock, reviewer CLI write/network 제한처럼 반복되는
  권한 문제는 `automation-doctor` 또는 feedback queue에 기록한다.
- agent runtime에서 reviewer CLI가 막히고 사용자 터미널에서는 동작하면
  `REVIEW_EXECUTION_MODE=external ./scripts/review-gate.sh`를 사용한다.
- destructive 명령, dependency 설치, credential/SSH/production/deploy 작업,
  프로젝트 지침 덮어쓰기는 계속 명시 승인 대상이다.

## 운영 산출물 규칙

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
- 긴 runbook/checklist/detail은 `AGENTS.md`에 계속 붙이지 말고 linked docs로
  분리한다.

## 서브에이전트 사용 기준

서브에이전트는 leader의 판단을 대체하지 않는다. 병렬로 좁고 독립적인 일을
맡길 때만 사용한다.

- 사용 가능: repo 탐색, 파일/심볼 매핑, 분리 가능한 구현 slice, 테스트 전략,
  UX/UI 검토, 의존성/공식문서 조사, 위험한 diff에 대한 독립 critique
- 사용 금지: destructive 작업, credential/production 작업, commit/push,
  사용자 판단이 필요한 범위 결정, 최종 통합 판단, 완료 주장
- Claude/Gemini가 비활성화되어 Codex fallback 리뷰를 쓰는 경우, 이는
  외부 리뷰어를 대체한 독립 승인으로 보지 않고 degraded/informational
  coverage로 보고한다.

## 필수 검증

작업 완료 전 반드시 실행한다.

```bash
./scripts/verify.sh
```

이 명령은 프로젝트별로 정의해야 한다. 가능한 검증 항목은 다음과 같다.

- 테스트
- lint 또는 format check
- typecheck
- build
- CLI/API/UI smoke check
- UI가 범위에 있으면 build, browser smoke, screenshot 또는 viewport check
- 배포가 범위에 있으면 artifact build, config validation, post-deploy smoke 또는 rollback check
- 보안이 범위에 있으면 allowed/denied path, secret/log redaction, dependency audit check
- 데이터가 범위에 있으면 migration, seed, CRUD, import/export, backup/rollback check
- 성능이 범위에 있으면 baseline/target 측정과 correctness regression check
- 관측성이 범위에 있으면 health/readiness, log/error, metric/trace/audit smoke check
- Docker 또는 서비스 부팅 확인
- 프로젝트별 산출물 확인
- `DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh`

`./scripts/verify.sh`가 실패하면 작업은 완료된 것이 아니다.

`./scripts/verify.sh`는 작업 중인 변경사항 자체를 경고로 만들지 않도록
`DOCTOR_SKIP_DIRTY_CHECK=1`로 automation-doctor를 실행할 수 있다. 단독으로
`./scripts/automation-doctor.sh`를 실행하면 dirty working tree는 계속 경고로
보고된다.

## 리뷰 게이트

커밋 후보 전 반드시 실행한다.

```bash
./scripts/review-gate.sh
```

이 명령은 다음을 실행한다.

- `./scripts/verify.sh`
- Claude 리뷰
- Gemini 리뷰
- 필요 시 Codex fallback 리뷰
- 리뷰 verdict 요약

Claude 또는 Gemini가 세션 제한, 주간 제한, quota/rate limit 등으로 응답할 수
없으면 해당 리뷰어는 `.omx/reviewer-state/`에 disabled 상태로 기록된다.
disabled 리뷰어는 사용자가 `RESET_DISABLED_AI_REVIEWERS=claude|gemini|all`로
복구하기 전까지 스킵된다.

한 리뷰어가 disabled 상태이면 남은 외부 리뷰어 프롬프트는 그대로 유지하고,
disabled 역할은 별도 Codex/GPT fallback 리뷰가 담당한다. 두 외부 리뷰어가
모두 disabled 상태이면 `codex-architect-review`와
`codex-test-alternative-review` fallback 리뷰가 모두 필요하다. 이 결과는
`proceed_degraded`, `single_external_plus_codex_fallback`, 또는
`codex_only_degraded`로 표시되며 독립 Claude/Gemini 승인으로 세지 않는다.
`proceed_degraded`는 진행 가능한 gate 결과지만 완료 보고에 degraded trust
level과 누락 리뷰어 상태를 반드시 포함한다.

루프 내 역할 경계:

- Codex/GPT 리더는 구현, 조율, 검증, 완료 보고를 책임진다.
- 리더가 작업 중 스스로 모델을 바꿨다고 표현하지 않는다.
- 비용/속도 최적화가 필요하면 탐색, 파일 매핑, 가벼운 합성처럼 범위가
  좁은 작업만 역할별 서브에이전트나 OMX lane에 위임한다.
- Claude/Gemini는 독립 외부 리뷰어다.
- Codex/GPT fallback 리뷰는 연속성을 위한 degraded 보강이며 독립
  Claude/Gemini 승인으로 세지 않는다.

## 완료 보고

완료 보고에 포함할 것:

- 변경 파일
- diff 요약
- 실행한 검증 명령
- 검증 결과
- 남은 warning 또는 제한사항

## 허용 범위

허용:

- 프로젝트 온보딩 문서 정리
- 워크플로우 명확화
- 좁은 범위의 안정성 수정
- 검증 스크립트 개선
- 프로젝트 scope 안에서 승인된 작은 변경

새 계획 없이 금지:

- 온보딩 전 프로젝트 기능 구현
- 인증, 권한, 보안 민감 변경
- 데이터 모델, 마이그레이션, 파괴적 저장소 변경
- 신규 의존성 또는 외부 서비스 추가
- 대규모 구조 변경
- 배포용 하드닝

## 커밋 규칙

커밋은 아래 조건을 만족한 뒤에만 진행한다.

- diff를 검토했다.
- `./scripts/verify.sh`가 통과했다.
- `./scripts/review-gate.sh`가 통과했다.
- 남은 warning을 기록했다.
- 커밋 메시지가 실제 변경 내용과 일치한다.
- 사용자가 커밋을 명시적으로 요청했다.

## 운영 명령

자동화 진단:

```bash
./scripts/automation-doctor.sh
```

새 프로젝트 초기화:

```bash
aiinit
```

프레임워크별 세부 검증 패턴은 프로젝트 온보딩 단계에서 추가한다.
