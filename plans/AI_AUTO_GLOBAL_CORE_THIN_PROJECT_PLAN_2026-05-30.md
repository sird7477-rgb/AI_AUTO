# AI_AUTO 전역 코어와 얇은 프로젝트 구조 계획

## 상태

- State: planning-only
- Date: 2026-05-30
- Trigger: AI_AUTO 공통 업데이트 때마다 여러 프로젝트의 복사본을 패치해야 하는
  부담이 커지고 있다는 사용자 관찰.
- Execution approval: not granted

## 문제

현재 AI_AUTO는 각 프로젝트에 비교적 넓은 자동화 스냅샷을 설치한다.

- 공통 지침 문서
- 완료팩과 도메인팩 참고 문서
- review-gate 스크립트
- review-context와 review-summary 스크립트
- feedback, knowledge, model-discovery, doctor helper
- template status marker와 패치 비교 표면

이 구조는 클론된 프로젝트가 독립적으로 동작한다는 장점이 있다. 하지만 AI_AUTO
공통 개선이 생길 때마다 프로젝트별 복사본을 다시 패치해야 하므로, 프로젝트가
늘어날수록 실제 전용 규칙보다 공통 코어 복사본 관리가 더 큰 부담이 된다.

## 확인된 경계

프로젝트 전용 규칙 자체는 패치 문제의 핵심이 아니다. 아래 항목은 계속
프로젝트가 소유해야 한다.

- 프로젝트 목적과 non-goal
- 금지 파일, 모듈, 리팩터링 경계
- 실제 검증 명령
- 배포, 운영, credential, 승인 경계
- 고객, 환경, 도메인 인스턴스별 규칙
- 프로젝트별 완료 기준
- 선택하거나 제외한 완료팩과 도메인팩

패치 부담은 공통 AI_AUTO 코어 파일이 각 프로젝트에 복사되는 데서 발생한다.

## 목표 구조

장기적으로는 아래 하이브리드 구조를 지향한다.

```text
AI_AUTO global core
  canonical common guidance
  completion/domain pack source references
  review-gate engine
  review context and summary engine
  feedback/knowledge helpers
  template/status/update tooling

project repository
  project-specific AGENTS.md or PROJECT_RULES.md
  project-specific docs/WORKFLOW.md
  project-specific scripts/verify.sh
  thin shims or profile for AI_AUTO core integration
  bundled fallback snapshot sufficient for standalone clone
```

목표는 AI_AUTO가 없으면 깨지는 완전 thin project가 아니다. 목표는 다음 동작이다.

```text
global core available:
  use the latest compatible read-only AI_AUTO core

global core unavailable:
  use the bundled project snapshot with an explicit fallback notice
```

## 기대 효과

- AI_AUTO 공통 코어 업데이트는 대체로 AI_AUTO 본진 checkout만 갱신하면 된다.
- 개별 프로젝트 패치는 프로젝트 전용 규칙, verify 명령, shim, profile schema 변경,
  일회성 migration으로 제한된다.
- 독립 클론도 bundled fallback snapshot을 통해 자동화 기준을 실행하거나 최소한
  설명할 수 있다.

## Non-Goals

- 프로젝트 전용 `scripts/verify.sh`를 제거하지 않는다.
- 로컬 AI_AUTO checkout이 없다고 프로젝트가 쓸 수 없게 만들지 않는다.
- 전역 AI_AUTO 업데이트가 version/profile evidence 없이 프로젝트의 commit/readiness
  policy를 조용히 바꾸게 하지 않는다.
- 전역 guidance를 프로젝트 전용 규칙에 자동 병합하지 않는다.
- `.omx/` runtime state를 커밋된 프로젝트 의존성으로 만들지 않는다.

## 리스크와 완화

| Risk | Failure Mode | Required Mitigation |
| --- | --- | --- |
| 독립 클론 깨짐 | 클론된 프로젝트가 없는 전역 파일만 참조한다. | bundled fallback snapshot 또는 명확한 bootstrap path를 유지한다. |
| 조용한 policy drift | AI_AUTO 업데이트가 프로젝트 review behavior를 예기치 않게 바꾼다. | core version/profile reporting과 compatibility gate를 추가한다. |
| 디버깅 모호성 | global core와 bundled fallback 중 무엇이 실행됐는지 알 수 없다. | doctor/review-gate/status 출력에 execution source를 표시한다. |
| migration churn | 기존 프로젝트에 큰 일회성 수정이 필요하다. | opt-in migration으로 시작하고, current aiinit default는 당분간 유지한다. |
| verify authority 혼동 | 전역 review tooling을 프로젝트 correctness check로 착각한다. | 프로젝트 전용 `scripts/verify.sh`를 correctness source로 유지한다. |
| fallback snapshot drift | 전역 core와 bundled fallback snapshot의 동작이 달라진다. | fallback snapshot version, refresh command, drift warning을 template status에 포함한다. |
| profile/core version mismatch | project profile이 요구하는 core와 설치된 global core가 맞지 않는다. | 호환 범위를 명시하고 mismatch 시 fail-closed 또는 명시적 fallback으로 전환한다. |

## 단계별 계획

### Phase 0: 설계만 진행

구현 전에 PRD와 test spec을 만든다. 이 문서는 아래를 정의해야 한다.

- global core command surface
- project profile schema
- bundled fallback shape와 갱신 방식
- compatibility/version rules
- standalone clone behavior
- 현재 full-copy 프로젝트에서의 migration path
- verification and review evidence

### Phase 1: 현재 프로젝트 구조를 바꾸지 않는 전역 wrapper

기존 복사형 프로젝트 스크립트는 그대로 두고 read-only/global entry point를 추가한다.

```bash
ai-auto doctor /path/to/project
ai-auto review-gate /path/to/project
ai-auto collect-review-context /path/to/project
ai-auto template-status /path/to/project
```

성공 기준:

- 현재 `aiinit` 동작은 바뀌지 않는다.
- global wrapper가 project path를 대상으로 실행된다.
- wrapper 출력에 AI_AUTO source path와 version이 표시된다.
- 기존 `./scripts/verify.sh`가 계속 통과한다.
- full-copy 프로젝트의 `./scripts/review-gate.sh`가 계속 동작한다.

### Phase 2: Thin shim prototype

새 test project에만 opt-in 설치 모드를 추가한다.

```bash
aiinit --thin /path/to/project
```

prototype project files:

- project-owned `AGENTS.md`
- project-owned `docs/WORKFLOW.md`
- project-owned `scripts/verify.sh`
- `AI_AUTO_PROJECT_PROFILE` 또는 동등한 profile file
- 공통 AI_AUTO 명령용 thin shim
- bundled fallback snapshot 또는 bootstrap notice

성공 기준:

- global AI_AUTO가 있으면 thin project가 정상 동작한다.
- global AI_AUTO가 없을 때도 같은 프로젝트가 명확한 fallback behavior를 보인다.
- template status가 `global-core`, `bundled-snapshot`, `project-owned`, `shim`
  surface를 구분한다.
- fallback snapshot이 global core와 얼마나 다른지 version/drift로 확인된다.

### Phase 3: Doctor와 template status 통합

진단 도구가 두 모델을 모두 이해하게 한다.

- full-copy project
- global core를 쓰는 thin project
- bundled fallback을 쓰는 thin project
- stale 또는 incompatible profile
- missing global core

성공 기준:

- doctor가 active execution source를 보고한다.
- template status가 의도적인 thin surface를 missing으로 오판하지 않는다.
- review-gate degraded/compatibility state가 계속 명시적으로 드러난다.

### Phase 4: Migration planning

prototype 검증 이후에만 기존 프로젝트 migration plan을 만든다.

Migration은 선택형이고 프로젝트별로 진행한다.

- project-specific customization을 먼저 검사한다.
- `AGENTS.md`, `docs/WORKFLOW.md`, `scripts/verify.sh`를 보존한다.
- fallback behavior가 검증된 경우에만 공통 복사 파일을 shim으로 바꾼다.
- rollback instructions를 기록한다.

## 구현 시 건드릴 가능성이 있는 파일

- `tools/ai-auto-init`
- `tools/ai-auto-template-status`
- 가능한 신규 `tools/ai-auto`
- `scripts/install-automation-template.sh`
- `scripts/automation-doctor.sh`
- `scripts/install-global-files.sh`
- `docs/NEW_PROJECT_GUIDE.md`
- `docs/GLOBAL_TOOLS.md`
- `docs/WORKFLOW.md`
- `templates/automation-base/README.md`
- `templates/automation-base/docs/PATCH_NOTES.md`
- `templates/automation-base/AGENTS.md`
- `templates/automation-base/docs/WORKFLOW.md`
- `templates/automation-base/scripts/*` shim 또는 fallback script
- `tests/test_template_global_contracts.py`
- `scripts/verify.sh`

## 열린 질문

- thin mode는 새 `aiinit --thin` 옵션으로 둘지, 별도 helper로 둘지?
- project profile은 어떤 파일이 소유해야 하는지?
- profile version은 정확한 AI_AUTO template version, minimum version, compatibility
  range 중 무엇을 pin해야 하는지?
- standalone clone을 유용하게 유지하는 최소 bundled fallback snapshot은 어디까지인지?
- review-gate는 profile이 명시적으로 opt-in한 경우에만 global core를 기본값으로
  써야 하는지?
- CI 환경은 AI_AUTO global core를 어떻게 설치하거나 찾아야 하는지?
- fallback snapshot refresh는 `aiinit`, `template-status`, 별도 명령 중 어디가
  책임져야 하는지?

## Stop Condition

scoped PRD와 test spec이 생기기 전에는 구현하지 않는다. 첫 실행 단계는 기존
프로젝트 migration이 아니라 Phase 1 global wrapper여야 한다.
