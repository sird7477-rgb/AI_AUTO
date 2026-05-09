# AI 개발 워크플로우

이 저장소는 Codex/OMX 기반 범용 자동화 기준을 사용한다.

`aiinit` 직후의 기본 파일은 완성된 프로젝트 설정이 아니다. 첫 작업 전에
프로젝트 인터뷰를 통해 목적, 범위, 검증 기준, 금지 범위를 채운 뒤에
개발 루프를 시작한다.

## 초기 온보딩

1. `aiinit`으로 자동화 템플릿을 설치한다.
2. 프로젝트 목적, 스택, 완료 기준, 금지 범위를 인터뷰한다.
3. 최종 산출물에 적용할 완료팩을 확인한다. 적용하지 않는 항목은
   non-goal로 기록하고, 프로젝트 문서에 불필요하면 해당
   `docs/*_COMPLETION.md` 파일은 삭제해도 된다.
4. UI가 필요하면 `docs/UI_COMPLETION.md`를 기준으로 UI 완료/검증 조건을
   정한다.
5. 배포/운영이 필요하면 `docs/DEPLOYMENT_COMPLETION.md`를 기준으로
   release artifact, smoke check, rollback 조건을 정한다.
6. 보안/인증/secret/개인정보가 범위에 있으면
   `docs/SECURITY_COMPLETION.md`를 기준으로 trust boundary와 검증 조건을
   정한다.
7. 영속 데이터, 마이그레이션, seed/import/export가 범위에 있으면
   `docs/DATA_COMPLETION.md`를 기준으로 데이터 완료/검증 조건을 정한다.
8. 성능 목표가 있으면 `docs/PERFORMANCE_COMPLETION.md`를 기준으로 baseline,
   target, 측정 명령을 정한다.
9. 운영 진단, 로그, health check, metrics, traces, audit가 범위에 있으면
   `docs/OBSERVABILITY_COMPLETION.md`를 기준으로 관측성 완료/검증 조건을
   정한다.
10. `.omx/domain-packs/`에 설치된 선택 적용 도메인팩을 확인한다.
11. 인터뷰로 적용할 표준팩과 제외할 표준팩을 확정한다.
12. 적용 대상 도메인팩이 있으면 필요한 항목만 프로젝트 지침에 병합한다.
13. `AGENTS.md`에 프로젝트별 에이전트 활동 지침을 반영한다.
14. `docs/WORKFLOW.md`에 실제 개발 루프와 검증 기준을 반영한다.
15. `scripts/verify.sh`를 프로젝트별 검증 명령으로 교체한다.
16. `./scripts/automation-doctor.sh`를 실행해 자동화 파일 상태를 확인한다.
17. `./scripts/verify.sh`를 실행해 프로젝트 검증이 통과하는지 확인한다.
18. `./scripts/review-gate.sh`를 실행해 검증과 AI 리뷰 게이트를 통과시킨다.
19. 필요하면 사용자 승인 후 baseline 커밋을 만든다.

## 도메인팩

`aiinit`은 범용 자동화 기반만 프로젝트 파일로 설치한다. Odoo 같은 특정
프레임워크 또는 도메인 기준은 프로젝트 지침에 자동 병합하지 않고,
`.omx/domain-packs/` 아래의 ignored 참고자료로만 둔다. 온보딩 인터뷰에서
프로젝트 성격을 확인한 뒤 필요한 항목만 선택 적용한다.

도메인팩 적용 원칙:

- 프로젝트가 해당 도메인인지 먼저 확인한다.
- 대상 repo 안의 `.omx/domain-packs/`에서 실제로 읽을 수 있는 표준팩만 사용한다.
- 표준팩은 참고자료로 사용하고 최종 파일은 프로젝트 상황에 맞게 작성한다.
- 사용하지 않는 규칙, 명령, 체크리스트는 붙여넣지 않는다.
- 도메인팩 적용 후에도 `scripts/verify.sh`는 실제 실행 가능한 명령이어야 한다.

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
