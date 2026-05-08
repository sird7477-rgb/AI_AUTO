# AI 개발 워크플로우

이 저장소는 Codex/OMX 기반 CLI 개발 루프를 검증하기 위한 테스트베드다.

현재 단계는 Codex가 구현하고, 고정 검증과 Claude/Gemini 리뷰 게이트를 통과한 뒤에만 커밋 후보를 만드는 범용 자동화 루프다.

## 현재 루프

1. 요청 내용을 정리한다.
2. 작업 범위를 작게 고정한다.
3. 최소 변경만 수행한다.
4. 완료를 주장하기 전에 diff를 확인한다.
5. `./scripts/verify.sh`를 실행한다.
6. 실패하면 수정 후 다시 검증한다.
7. 커밋 후보를 만들기 전에는 `./scripts/review-gate.sh`를 실행한다.
8. 리뷰어가 사용 불가하면 상태와 보강 경로를 기록한다.
9. 검증과 review gate 증거가 있을 때만 커밋 후보를 만든다.

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

이 명령이 실패하면 작업은 완료된 것이 아니다.

`./scripts/verify.sh`는 작업 중인 변경사항 자체를 경고로 만들지 않도록 `DOCTOR_SKIP_DIRTY_CHECK=1`로 automation-doctor를 실행한다. 단독으로 `./scripts/automation-doctor.sh`를 실행하면 dirty working tree는 계속 경고로 보고된다.

## 리뷰 게이트

커밋 후보 전 반드시 실행한다.

```bash
./scripts/review-gate.sh
```

이 명령은 다음을 실행한다.

./scripts/verify.sh
Claude 리뷰
Gemini 리뷰
필요 시 Codex fallback 리뷰
리뷰 verdict 요약

Claude 또는 Gemini가 세션 제한, 주간 제한, quota/rate limit 등으로 응답할 수 없으면 해당 리뷰어는 `.omx/reviewer-state/`에 disabled 상태로 기록된다. disabled 리뷰어는 사용자가 `RESET_DISABLED_AI_REVIEWERS=claude|gemini|all`로 복구하기 전까지 스킵된다.

한 리뷰어가 disabled 상태이면 남은 외부 리뷰어 프롬프트는 그대로 유지하고, disabled 역할은 별도 Codex/GPT fallback 리뷰가 담당한다. 두 외부 리뷰어가 모두 disabled 상태이면 `codex-architect-review`와 `codex-test-alternative-review` fallback 리뷰가 모두 필요하다. 이 결과는 `proceed_degraded`, `single_external_plus_codex_fallback`, 또는 `codex_only_degraded`로 표시되며 독립 Claude/Gemini 승인으로 세지 않는다. `proceed_degraded`는 진행 가능한 gate 결과지만 완료 보고에 degraded trust level과 누락 리뷰어 상태를 반드시 포함한다.

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

새 프로젝트 초기화:

```bash
aiinit
```

Odoo 등 특정 프레임워크 검증 패턴은 별도 계획에서 다룬다.
