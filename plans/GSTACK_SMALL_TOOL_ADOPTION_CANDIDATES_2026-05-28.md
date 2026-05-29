# GStack Small-Tool Adoption Candidates - 2026-05-28

## Scope

이 문서는 GStack을 AI_AUTO에 바로 설치하기 위한 계획이 아니다. 임시 클론을
읽기 전용으로 분석해, AI_AUTO에 흡수할 만한 작은 도구/절차 후보를 점수화한
채택 후보표다.

- 분석 원본: `/tmp/gstack-analysis-20260528`
- 원본 커밋: `19770ea` (`v1.51.0.0 feat: $B memory diagnostic + 4 CDP-resource leak fixes (#1751)`)
- 수행한 작업: 얕은 클론, `README.md`, `ARCHITECTURE.md`, `package.json`, 주요 `SKILL.md`, `review/` 체크리스트, `bin/` 목록 분석
- 하지 않은 작업: `./setup`, Codex 호스트 설치, 브라우저 데몬 실행, 쿠키 연결, GBrain 연결, ngrok 터널, PR/배포 자동화

## Package Decision

GStack 분석과 소도구 채택후보 스코어링은 같은 패키지로 진행한다. 후보 발굴과
점수화를 분리하면 같은 스킬/런타임을 반복 분석하게 되고, 설치형 기능과
문서/체크리스트로 흡수 가능한 기능이 섞인다.

이번 패키지의 산출물은 다음으로 제한한다.

1. GStack 기능을 마이크로 단위로 분해한다.
2. AI_AUTO에 흡수할 수 있는 후보를 점수화한다.
3. 설치 없이 문서/체크리스트/검증 계약으로 먼저 채택할 후보를 고른다.
4. 런타임 설치, 브라우저 권한, 쿠키, 터널, 외부 메모리는 별도 승인 항목으로 남긴다.

## Scoring Rubric

각 항목은 0-5점이다. 총점은 35점 만점이다.

| 항목 | 의미 |
| --- | --- |
| Fit | AI_AUTO의 현재 구조, Ralph, review-gate, 구조감사 흐름과 맞는 정도 |
| Utility | 즉시 얻는 품질/속도/검증 이득 |
| Smallness | 마이크로 단위로 흡수 가능한 정도 |
| Verification | 테스트나 문서 검증으로 효과를 확인하기 쉬운 정도 |
| Low authority risk | 기존 AGENTS/OMX 권한 모델과 충돌이 적은 정도 |
| Low state risk | 쿠키, 토큰, 외부 메모리, 터널 등 상태 리스크가 낮은 정도 |
| Low runtime burden | 새 의존성/데몬/설치 부담이 낮은 정도 |

Decision 기준:

- `adopt_contract`: 설치 없이 AI_AUTO 문서/체크리스트/리뷰 계약으로 채택
- `prototype`: 작은 로컬 도구나 검증 스크립트로 별도 실험
- `reference_only`: 현재 TODO가 아니며 특정 구조 변화가 있을 때만 재검토
- `reject_default`: 기본 채택 금지, 명시 승인 없이는 실행하지 않음

## Candidate Matrix

| Candidate | GStack source | Fit | Utility | Smallness | Verification | Low authority risk | Low state risk | Low runtime burden | Total | Decision | Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 계획 비판 렌즈 | `plan-ceo-review`, `office-hours` | 5 | 5 | 4 | 4 | 5 | 5 | 5 | 33 | adopt_contract | "전제 도전, 대안 비교, 범위 확장/축소, completeness 점수"만 흡수한다. GBrain/telemetry/AskUserQuestion 런타임은 제외한다. |
| 구조감사 렌즈 | `plan-eng-review` | 5 | 5 | 4 | 5 | 5 | 5 | 5 | 34 | adopt_contract | 시스템 경계, 에러 경로, 테스트 다이어그램, 실패 모드 확인을 기존 구조감사설계에 접목한다. |
| 리뷰 specialist taxonomy | `review/checklist.md`, `review/specialists/*.md` | 5 | 5 | 4 | 5 | 4 | 5 | 5 | 33 | adopt_contract | testing, maintainability, security, performance, data-migration, api-contract, red-team 분류를 review-gate의 범위 감지 기준으로 흡수한다. |
| 리뷰 quality score | `review/SKILL.md` | 4 | 4 | 5 | 5 | 5 | 5 | 5 | 33 | adopt_contract | `10 - critical*2 - informational*0.5`는 단순하고 검증 가능하다. 단, 통과/실패 판단을 대체하지 않고 보조 지표로만 둔다. |
| QA report-only schema | `qa-only`, `qa` | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 28 | adopt_contract | health score, screenshot evidence, repro steps 형식만 차용한다. GStack browse 실행은 제외한다. |
| 벤치마크 evidence schema | `benchmark`, `bin/gstack-model-benchmark` | 4 | 4 | 3 | 5 | 5 | 5 | 4 | 30 | adopt_contract | 이미 생긴 AI_AUTO 벤치마크 문서와 연결한다. 임의 기준 대신 반복 가능 측정, 환경, 원자료 링크를 요구한다. |
| TODO 정규화 포맷 | `review/TODOS-format.md` | 4 | 3 | 5 | 5 | 5 | 5 | 5 | 32 | adopt_contract | 남은 일/완료/우선순위/검증근거를 구조화하는 규칙만 흡수한다. |
| diff scope detector | `bin/gstack-diff-scope` | 4 | 4 | 3 | 4 | 4 | 5 | 4 | 28 | prototype | 프론트엔드/백엔드/마이그레이션/API 변경 감지에 유용하다. 먼저 shell 없이 현재 `review-gate.sh`의 범위 판정 계약으로 재현한다. |
| review history suppression | `bin/gstack-review-read`, `bin/gstack-review-log` | 3 | 4 | 3 | 4 | 3 | 3 | 4 | 24 | prototype | 이전에 사용자가 skip한 리뷰 항목을 중복 제기하지 않는 아이디어는 좋다. 다만 로컬 상태 파일 권위가 생기므로 별도 로그 계약 필요. |
| learnings/retro loop | `learn`, `retro`, `gstack-learnings-*` | 4 | 4 | 3 | 3 | 3 | 2 | 3 | 22 | reference_only | AI_AUTO Reflection Loop와 겹친다. 외부 메모리 도입 없이 현재 reflection 문서의 참고 렌즈로만 둔다. |
| GBrain semantic memory | `setup-gbrain`, `sync-gbrain`, `bin/gstack-gbrain-*` | 3 | 4 | 1 | 2 | 2 | 1 | 1 | 14 | reject_default | 외부 메모리/인덱스/동기화 권한이 커서 현재 AI_AUTO TODO에서 제외한다. |
| browser daemon | `browse`, `open-gstack-browser`, `chrome-cdp` | 3 | 5 | 2 | 3 | 2 | 1 | 1 | 17 | reject_default | 지속 Chromium, 로컬 HTTP, 쿠키/세션 상태가 핵심이므로 현재 AI_AUTO TODO에서 제외한다. |
| browser cookie setup | `setup-browser-cookies` | 2 | 4 | 2 | 2 | 1 | 0 | 1 | 12 | reject_default | 인증 쿠키/세션을 다루므로 기본 채택 금지. 명시 승인과 격리 브라우저 프로파일이 필요하다. |
| pair-agent tunnel | `pair-agent`, ngrok path | 2 | 4 | 1 | 2 | 1 | 0 | 1 | 11 | reject_default | 원격 에이전트에 브라우저 접근을 주는 기능이다. 토큰, 터널, 쿠키 접근 리스크 때문에 기본 채택하지 않는다. |
| ship/deploy automation | `ship`, `land-and-deploy`, `canary` | 2 | 4 | 1 | 3 | 1 | 3 | 2 | 16 | reject_default | 커밋 정리, PR 생성, 배포, canary까지 포함한다. AI_AUTO의 명시 commit/push 승인 규칙과 충돌한다. |
| autoplan full pipeline | `autoplan`, `spec` | 3 | 4 | 2 | 3 | 3 | 4 | 3 | 22 | reject_default | AI_AUTO의 ralplan/Ralph/구조감사와 중복이 커서 현재 AI_AUTO TODO에서 제외한다. |

## Recommended Adoption Package

### Phase 1: Contract-only adoption

설치 없이 문서/체크리스트로 흡수한다.

- 계획 비판 렌즈: 전제 도전, 대안 비교, completeness 점수, 범위 확장/축소 명시
- 구조감사 렌즈: 데이터 흐름, 실패 모드, 에러 명명, 테스트 다이어그램, 관측성 확인
- 리뷰 taxonomy: 변경 범위별 specialist dispatch 기준
- QA report-only schema: health score, screenshot/evidence, repro steps
- 벤치마크 evidence schema: 환경, 반복 횟수, 원자료, 비교 기준, 해석 한계
- TODO 정규화: open/contract_started/deferred/blocked/completed 상태와 검증 근거 연결

### Phase 2: Micro prototypes

문서 계약이 안정된 뒤, repo-local 스크립트나 review-gate 보조 로직으로만 실험한다.

- diff scope detector: 변경 파일 기반 specialist 후보 추천
- review history suppression: 같은 fingerprint를 반복 제기하지 않도록 하는 감사 가능한 로컬 로그
- benchmark runner wrapper: 기존 `plans/AI_AUTO_BENCHMARK_BASELINE_2026-05-28.md`와 결과 파일을 일관되게 묶는 wrapper

### Phase 3: Excluded/reference-only by default

다음은 이번 패키지와 현재 active/later-gated TODO에서 제외한다. 새 런타임 채택
계획이 별도로 승인되기 전까지 참고 기록으로만 남긴다.

- GStack `./setup --host codex`
- 지속 브라우저 데몬
- 쿠키/세션 이관
- ngrok 또는 원격 agent pair
- GBrain 설치/동기화
- ship/deploy/canary 자동화
- commit/push/PR 생성 자동화

## Immediate Backlog Entries

| Item | Type | Acceptance evidence |
| --- | --- | --- |
| GStack scoring matrix를 구조감사 backlog에 연결 | docs | backlog가 이 문서를 참조하고 제외/참고 후보가 중복 없이 정리됨 |
| review-gate specialist taxonomy 초안 | docs/test contract | 변경 범위별 reviewer dispatch 표가 있고 기존 review-gate와 충돌하지 않음 |
| benchmark evidence schema 정식화 | docs | 기준, 원자료, 반복성, 환경, 해석 한계가 문서 템플릿에 들어감 |
| QA report-only schema 초안 | docs | 버그 리포트가 health score, evidence, repro steps를 갖춤 |
| diff scope prototype 설계 | plan | 구현 전 입력/출력/오탐 처리/검증 샘플이 정의됨 |

## Current Recommendation

채택 우선순위는 다음 순서가 맞다.

1. `adopt_contract`: 계획 비판 렌즈, 구조감사 렌즈, 리뷰 taxonomy, quality score, QA report-only schema, 벤치마크 evidence schema, TODO 정규화
2. `prototype`: diff scope detector, review history suppression, benchmark wrapper
3. `reference_only`: learnings/retro ideas as design input only
4. `reject_default`: GBrain, browser daemon, cookie setup, pair-agent tunnel,
   ship/deploy/canary 자동화, autoplan full pipeline

이렇게 하면 GStack의 좋은 판단 구조는 바로 흡수하면서도, 권한이 큰 런타임은
AI_AUTO의 명시 승인/검증 규칙 밖으로 새지 않는다.
