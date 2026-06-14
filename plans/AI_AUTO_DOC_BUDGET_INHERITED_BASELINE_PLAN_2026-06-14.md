# AI_AUTO 문서 비대화 예산 — 상속·미변경 베이스라인 제외 (2026-06-14)

## 문제

doc-budget의 **절대 크기 레인**(개별 파일 한계 + primary guidance total 6500/8000)이
파생 프로젝트에서 손도 안 댄 상속 문서를 매 verify마다 재검사한다. 본진(AI_AUTO)에서도
primary total 6,890줄 중 install이 복사하는 상속 docs가 3,889줄(56%). 실제 파생
프로젝트(두어 문서만 커스터마이징)면 상속·미변경 비중은 더 크다 → 예산의 절반 이상이
재검사 redundancy.

## 기각안: 합계 레인 fail→warn 강등(A)

- 에이전트 자동 루프는 warn에 안 멈춤 → 강등=사실상 삭제.
- 합계 레인은 다브랜치 누적 래칫의 유일한 절대 backstop(증분 레인은 main 머지 후 망각).
- 상시-warn은 guidance_bloat 신호 채널 오염.
- 본진/파생 분기 로직(env 플래그) 필요 → 설정 드리프트.
- redundancy는 B가 더 깔끔하게(자기판별, enforce 강도 유지) 제거하므로 A는 불필요.

## 채택안: 상속·미변경 절대예산 제외(B)

설치 시점 sha256 매니페스트를 baseline으로, 그와 바이트 동일한 primary guidance 파일을
절대예산에서 제외. 커스터마이징(해시 불일치)·자작(매니페스트에 없음) 문서만 예산.

### 자기판별 (env 플래그 없음)

- 파생 프로젝트: `.ai-auto/guidance-baseline.sha256` 존재 → 일치 파일 제외.
- 본진(AI_AUTO): 소스라 매니페스트 없음 → 항상 false → 전부 풀 enforce. 매니페스트
  유무로 동작이 자동 분기.

### baseline 형식/위치

- `sha256sum` 그대로의 텍스트(`.ai-auto/guidance-baseline.sha256`). JSON 아님 →
  doc-budget 순수 bash 유지.
- **tracked**(`.omx` 아님). 예산은 fail 게이트 → 신선 클론/CI 재현 필요.

### 증분 레인 불변

branch-cumulative diff 레인(경고 150/실패 300)은 손대지 않음. 상속 파일을 로컬 편집하면
해시 불일치 → 절대예산 재진입 + 증분 레인이 추가 줄을 계속 추적.

## 구현 (완료)

- `scripts/doc-budget.sh` (+ `templates/automation-base/scripts/doc-budget.sh` 바이트 동일):
  - `GUIDANCE_BASELINE` 변수(`DOC_BUDGET_BASELINE_FILE`로 오버라이드 가능).
  - `doc_budget_sha256`, `doc_budget_is_inherited_unchanged`, `budget_primary_file` 헬퍼.
  - 개별 파일 검사 3개를 `budget_primary_file`로 래핑(상속·미변경 시 skip 로그).
  - primary total 루프: 상속·미변경 제외 + `excluded N docs (M lines)` 가시화(침묵 삭제 금지).
- `scripts/install-automation-template.sh`: cp 블록 직후 설치 guidance 문서들의
  `sha256sum`을 `.ai-auto/guidance-baseline.sha256`에 기록(template_version 헤더 포함).
  `.ai-auto/`는 `.git/info/exclude`에 넣지 않음(추적 유지).
- `scripts/verify-machinery.sh`:
  - 신규 "inherited-unchanged baseline exclusion" 테스트(제외/편집후 재진입/매니페스트 부재 회귀가드).
  - installer 통합 테스트에 baseline 생성·추적·신규설치 primary total=0 검증 추가.

### 검증 결과

- 신규 설치 target: 23개 상속 문서(4,996줄) 전부 제외, primary total=0.
- 상속 문서 편집 시 즉시 예산 재진입. 매니페스트 부재 시 현행 동작(비파괴).
- guidance-budget 테스트 4블록 + installer 통합 테스트 exit 0.

## Phase 2 — 템플릿 패치 시 baseline 자동 갱신 (완료)

- `scripts/refresh-guidance-baseline.sh <target>` 신규: 템플릿에서 guidance 문서를
  자동 열거(AGENTS.md + docs/*.md, exempt 제외), 현재 템플릿과 바이트 동일한 문서만
  baseline에 기록. 커스터마이징·부재 문서는 제외 → 멱등.
- `install-automation-template.sh`는 인라인 해시 블록을 제거하고 이 스크립트를 호출(DRY).
- `ai-auto-template-status`의 update-available 피드백 resolution에 "패치 후
  `scripts/refresh-guidance-baseline.sh <target>` 실행" 단계 추가 → 기존 진행 프로젝트
  패치 플로우에서 자동 안내.
- backfill: 기존(베이스라인 이전) 설치 프로젝트도 같은 스크립트로 baseline 생성 가능.

## 문서화 (완료)

`docs/AUTOMATION_OPERATING_POLICY.md` Guidance Budget Escalation 절(+템플릿 사본)에
baseline 제외 메커니즘·refresh 사용법 명시.
