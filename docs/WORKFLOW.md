# AI 개발 워크플로우

이 저장소는 Codex/OMX 기반 CLI 개발 루프를 검증하기 위한 테스트베드다.

현재 단계는 Codex가 구현하고, 고정 검증과 Claude/Gemini 리뷰 게이트를 통과한 뒤에만 커밋 후보를 만드는 범용 자동화 루프다.

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

- `none`: 명확하고 작고 되돌리기 쉬운 작업. 바로 실행한다.
- `light`: 결과를 바꾸는 결정이 하나 있다. 질문 하나로 확인하고 진행한다.
- `standard`: 여러 선택지가 결과를 바꾼다. 로컬 증거를 먼저 읽고 2-4개
  질문으로 확정한 뒤 짧은 플랜을 만든다.
- `deep`: 장기 정책, 표준, 아키텍처, 보안, 배포, 데이터, 검증 체계처럼
  실패 비용이 크다. 단계별 인터뷰, 플랜, 필요 시 리뷰어/서브에이전트
  검토를 거친다.

사용자가 "바로 진행"이라고 해도 destructive, credential, production,
scope 변경 작업의 승인 게이트는 유지한다.

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
Claude 리뷰
Gemini 리뷰
필요 시 Codex fallback 리뷰
리뷰 verdict 요약

Claude 또는 Gemini가 세션 제한, 주간 제한, quota/rate limit 등으로 응답할 수 없으면 해당 리뷰어는 `.omx/reviewer-state/`에 disabled 상태로 기록된다. disabled 리뷰어는 사용자가 `RESET_DISABLED_AI_REVIEWERS=claude|gemini|all`로 복구하기 전까지 스킵된다.

한 리뷰어가 disabled 상태이면 남은 외부 리뷰어 프롬프트는 그대로 유지하고, disabled 역할은 별도 Codex/GPT fallback 리뷰가 담당한다. 두 외부 리뷰어가 모두 disabled 상태이면 `codex-architect-review`와 `codex-test-alternative-review` fallback 리뷰가 모두 필요하다. 이 결과는 `proceed_degraded`, `single_external_plus_codex_fallback`, 또는 `codex_only_degraded`로 표시되며 독립 Claude/Gemini 승인으로 세지 않는다. `proceed_degraded`는 진행 가능한 gate 결과지만 완료 보고에 degraded trust level과 누락 리뷰어 상태를 반드시 포함한다.

루프 내 역할 경계:

- Codex/GPT 리더는 구현, 조율, 검증, 완료 보고를 책임진다.
- 리더가 작업 중 스스로 모델을 바꿨다고 표현하지 않는다.
- 비용/속도 최적화가 필요하면 탐색, 파일 매핑, 가벼운 합성처럼 범위가
  좁은 작업만 역할별 서브에이전트나 OMX lane에 위임한다.
- 세부 위임 기준은 `docs/AUTOMATION_OPERATING_POLICY.md`의
  `Subagent Utilization`을 따른다.
- Claude/Gemini는 독립 외부 리뷰어다.
- Codex/GPT fallback 리뷰는 연속성을 위한 degraded 보강이며 독립
  Claude/Gemini 승인으로 세지 않는다.

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
- 긴 runbook/checklist/detail은 `AGENTS.md`에 계속 붙이지 말고 linked docs로
  분리한다.

완료 보고에 포함할 것
변경 파일
diff 요약
실행한 검증 명령
검증 결과
남은 warning 또는 제한사항
허용 범위

허용:

문서 정리
워크플로우 명확화
좁은 범위의 안정성 수정
검증 스크립트 개선
테스트베드 유지보수

새 계획 없이 금지:

todo 앱 신규 기능
UI 작업
인증
백그라운드 작업
대규모 구조 변경
배포용 하드닝
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

범용 템플릿은 UI, 배포, 보안, 데이터, 성능, 관측성 완료 기준이 필요한
프로젝트를 위해 `docs/*_COMPLETION.md` 완료팩을 함께 설치한다. 단, 이
ai-lab 저장소 자체는 CLI/API 자동화 테스트베드이므로 새 계획 없이 UI,
배포, 보안, 데이터, 성능, 관측성 기능 작업을 하지 않는다.
