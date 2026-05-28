# 기획안 v1: AI_AUTO Reflection Loop

## 목적

AI_AUTO에 Claude Managed Agents의 `Dreaming`과 유사한 운영 구조를
AI_AUTO 방식으로 적용한다.

목표는 모델 자체를 학습시키는 것이 아니라, 작업 중 발생한 실패, 성공,
판단 근거, 반복 패턴을 로컬 지식으로 정리하고, 검증된 항목만 AI_AUTO
지침, 스크립트, 템플릿으로 승격하는 것이다.

## 핵심 방향

```text
작업 수행
→ 실패/성공/판단 근거 기록
→ 반복 패턴 추출
→ Obsidian에 정제된 지식으로 저장
→ AI_AUTO 개선 후보로 승격
→ 검증/리뷰 통과 후 실제 지침·스크립트·템플릿에 반영
```

이 구조는 자동 학습이라기보다 `AI_AUTO Reflection Loop` 또는
`Dreaming-like Knowledge Loop`에 가깝다.

계획과 실행은 분리한다. 이 문서는 v1의 지식화/검토 계획을 고도화하는
기준이며, 실제 rebuild 실행 승인이 아니다. 실행 단계는 승인된 plan,
behavior-locking test 또는 smoke evidence, module boundary, `verify.sh`,
`review-gate.sh`를 별도로 요구한다.

## 구성 요소

### Memory

`.omx/project-memory.json`

사용자 선호, 프로젝트별 규칙, 장기적으로 기억해야 할 결정사항을 저장한다.
모든 중간 대화나 로그를 저장하지 않고, 다음 세션에서도 의미가 있는
정제된 결정만 남긴다.

### Feedback Queue

`.omx/feedback/queue.jsonl`

반복 문제, 개선 요청, 자동화 고도화 후보를 쌓는 큐다. 프로젝트별로 흩어진
개선 아이디어를 AI_AUTO 본진으로 되돌리는 통로로 사용한다.

### Knowledge / Obsidian

`Obsidian AI_AUTO_Vault`

사람이 읽고 검색할 수 있는 정제된 지식 저장소다. 주요 note type은 다음과
같다.

- `incident`: 실패, 권한 문제, 검증 실패, 반복 디버깅
- `lesson`: 재사용 가능한 해결책이나 운영상 배운 점
- `finding`: 기술 판단 근거와 조사 결과
- `promotion-candidate`: AI_AUTO 지침 또는 템플릿 승격 후보

Obsidian은 지식 창고, 검색, 회고, 후보 관리 역할만 한다.

### Outcome / Verification

`./scripts/verify.sh`, `./scripts/review-gate.sh`

실제 반영 여부를 판단하는 검증 루프다. Obsidian에 기록된 내용은 참고
자료일 뿐이며, AI_AUTO 본진에서 검증과 리뷰를 통과해야 지침, 스크립트,
템플릿으로 반영된다.

## 권한 매트릭스

```text
Reflection Loop
→ observe / sanitize / draft / classify / recommend

Native Workbench
→ display / triage / approve-or-defer action requests

Obsidian
→ durable curated knowledge store

review-gate-core
→ verification + reviewer verdict authority

review-gate-sidecar
→ local draft/report generation only

Field validation
→ real-environment evidence contract

Execution
→ Codex/Ralph/scripts/user-approved commands
```

Reflection Loop는 명령 실행, field evidence 확정, Obsidian push, guidance
promotion을 자체 수행하지 않는다. 작업 상태를 관찰하거나 증거로 미러링할
수는 있지만, 실행 상태 전이의 소유자는 아니다.

## Obsidian과 AI_AUTO의 권한 경계

```text
Obsidian = 지식 창고 / 검색 / 회고 / 후보 관리
AI_AUTO = 실행 / 승인 / 검증 / 리뷰 / 실제 반영
```

Obsidian이 AI_AUTO를 조종하지 않는다. AI_AUTO가 작업 중 얻은 지식을
정제해서 Obsidian에 보관하고, 이후 유사 작업에서 참고하거나 개선 후보로
끌어오는 구조다.

## 기대 효과

- 같은 실수를 반복할 가능성을 줄인다.
- 프로젝트별 권한 문제, 검증 실패, 도구 한계, 운영 패턴을 누적한다.
- AI_AUTO 템플릿에 반영해야 할 후보를 체계적으로 모은다.
- 새 프로젝트 시작 시 과거 유사 사례를 참고할 수 있다.
- 장기적으로 AI_AUTO가 사용자의 작업 방식에 더 잘 맞게 고도화된다.

## 안전선

- 모델이 몰래 학습하는 구조가 아니다.
- raw 로그, raw 프롬프트, 토큰, 민감 경로, 스크린샷을 그대로 Obsidian에
  저장하지 않는다.
- Obsidian 기록은 참고 자료이며 승인, 검증, 커밋의 기준이 아니다.
- 실제 지침 변경은 반드시 AI_AUTO 본진에서 `verify.sh`와
  `review-gate.sh`를 거쳐야 한다.
- `.omx/` 전체를 vault나 git에 그대로 복사하지 않는다.

## v1 범위

v1은 자동 수정이 아니라 자동 정리와 후보 생성에 집중한다.

- 세션 종료 또는 리뷰 종료 시 지식 초안 후보를 만든다.
- 실패, 반복, 사용자 지적, 검증 실패, 성공 패턴을 분류한다.
- 민감 정보가 포함될 가능성이 있으면 저장하지 않는다.
- Obsidian vault에는 정제된 Markdown note만 저장한다.
- 승격 후보는 feedback queue 또는 promotion-candidate note로 남긴다.
- v1 최소 deliverable은 local sanitized draft capture와 명시적 collection이다.
  UI alignment, historical backfill, resource scheduling, promotion automation은
  v1 본체가 아니라 별도 gate를 통과한 확장 단계로 둔다.

## 가동 트리거

Reflection Loop는 하나의 완료 이벤트에 의존하지 않는다. 커밋은 변경
스냅샷일 뿐이며, 특히 Odoo 같은 환경에서는 커밋 후 실제 동작 확인이
남을 수 있으므로 완료 확정 트리거로 쓰지 않는다.

트리거는 다음 분류를 먼저 가진다.

```text
read_only_observation
→ review-gate 결과, session end, periodic reflection

write_capable_local
→ local sanitized draft/report 생성

promotion_request
→ repo edit proposal 생성까지만 허용, 실제 반영은 별도 검증 필요

field_confirmation
→ 사용자가 제공한 실제 환경 증거를 수집/표시, 단독 완료 판정 금지
```

각 트리거는 source event, required evidence artifact, allowed output,
blocking condition, retry/idempotency key, must-not-write case를 가져야 한다.

### Review Gate

기본 자동 트리거다.

`review-gate` 결과를 보고 실패, degraded 상태, 리뷰어 부재, 검증 이슈를
지식 draft로 남긴다. 이 시점의 note는 해결 완료가 아니라 관찰 기록이다.

```text
status: draft
outcome: pending
evidence: review-gate result
```

`review-gate-core` verdict가 authoritative하다. Reflection capture는
sidecar-only이며, draft capture 누락이나 실패는 warning/trace로 남기고 gate
결과를 바꾸지 않는다.

### Ralph Complete

AI 작업 단위 완료 트리거다.

Ralph 완료는 AI가 계획된 작업을 수행하고, 검증과 리뷰 증거를 모으고,
known blocker를 정리했다는 의미다. 단, 외부 시스템이나 실제 Odoo UI 확인이
필요한 작업에서는 최종 완료가 아니라 field validation 대기 상태로 남긴다.

```text
ralph complete
→ AI 작업 완료 요약
→ verify/review evidence 정리
→ field validation 필요 여부 판단
```

단순 코드나 문서 작업은 `review-gate` 통과와 `ralph_completed`만으로
`resolved` 처리할 수 있다. Odoo, 브라우저, 운영성 작업은
`pending_field_validation`을 거쳐야 한다.

### Commit

완료 트리거가 아니라 변경 스냅샷 트리거다.

커밋 시점에는 어떤 문제를 해결하려 했는지, 어떤 영역이 바뀌었는지, 어떤
검증까지 통과했는지, 남은 확인이 무엇인지 기록한다.

```text
status: committed
outcome: awaiting_field_validation
```

### User Field Confirmation

완료 확정 절차의 시작 트리거다.

사용자가 "field 완료 처리해줘", "운영 확인 완료", "Odoo 동작확인 끝났어",
"이 작업 완료 확정" 같은 명령을 주면 AI_AUTO는 바로 `resolved`로 바꾸지
않고 완료 확정 절차를 실행한다.

```text
1. 대상 작업, commit, draft 식별
2. 필요한 post-check 목록 확인
3. 사용자가 말한 확인 내용 기록
4. 가능한 자동 검증 재실행
5. 부족한 증거가 있으면 pending_field_validation 유지
6. 충분하면 field_verified 또는 resolved 처리
```

### Post-check / Field-test

실제 완료 확정 트리거다.

Odoo 같은 프로젝트에서는 로컬 검증과 커밋 이후에도 Odoo 모듈 업데이트,
브라우저 메뉴 진입, 주요 버튼 클릭, 서버 로그 에러 여부, 사용자 플로우
확인 등이 필요할 수 있다. 이 증거가 충분할 때만 최종 `resolved`로
처리한다.

### Session End

회고 트리거다.

모든 세션 종료마다 note를 만들지는 않는다. 아래 조건 중 하나가 있을 때만
draft를 만든다.

- 검증 실패 후 재시도 발생
- review-gate degraded 발생
- 사용자가 운영 실수를 지적함
- 권한, 경로, 환경 문제로 작업이 막힘
- 동일 `repeat_key`가 반복됨

### Periodic Reflection

반복 패턴 정리 트리거다.

누적된 draft, feedback queue, Obsidian note를 검토해 `promotion-candidate`
후보를 정리한다. 이 단계도 자동 반영이 아니라 후보 생성이다.

## 상태 모델

Reflection Loop는 완료 상태를 한 단계로 보지 않으며, 작업 상태와 지식
상태를 분리한다.

Work item state:

```text
editing
→ code_ready
→ review_ready
→ committed
→ pending_field_validation
→ field_verified
→ done
```

Knowledge item state:

```text
draft
→ sanitized
→ triaged
→ local_private
→ pushed_to_obsidian
→ promotion_candidate
→ accepted_change | rejected | deferred
```

단순 작업의 축약 경로:

```text
review-gate 통과 + ralph_completed
→ resolved 가능
```

Odoo, 브라우저, 운영성 작업의 경로:

```text
review-gate 통과 + ralph_completed
→ pending_field_validation
→ 사용자 동작확인 또는 post-check
→ field_verified
→ resolved
```

Reflection은 work state를 증거로 기록하거나 미러링할 수 있지만 work state
transition을 소유하지 않는다.

## 완료 기준 분리

완료 기준은 프로젝트 성격에 따라 분리한다.

```text
code_ready: verify + review-gate 통과
commit_ready: 커밋 가능 또는 커밋 완료
field_ready: 실제 환경에서 동작 확인
done: field_ready까지 통과
```

Odoo 같은 프로젝트에서는 `code_ready`나 `commit_ready`를 `done`으로
취급하지 않는다.

## Field Validation Boundary

Field validation은 Obsidian note도 아니고 Reflection 판단도 아니다.

```text
필수 입력:
→ project-specific checklist evidence
→ 필요한 경우 사용자/operator confirmation
→ 허용된 post-check 결과

증거가 missing, stale, degraded이면:
→ pending_field_validation 유지
```

Workbench는 확인 증거를 수집하고 표시할 수 있다. 실행/Ralph/scripts는
허용된 check를 수행한다. 최종 전이는 AI_AUTO 정책과 프로젝트별 완료 기준이
결정한다.

## Historical Backfill

Reflection Loop 적용 전에 진행된 프로젝트도 과거 작업 이력을 일부
역추출할 수 있다. 단, 이 기능은 초기에는 experimental로 둔다.

Backfill은 v1 본체가 아니라 explicit project list가 있을 때만 실행하는
실험 단계다. 기본은 dry-run이며, unsafe `.omx` artifact는 원문 복사가
아니라 reference-only 요약으로 다룬다. privacy scan은 vault push 직전뿐
아니라 durable local draft/report/index 생성 전에도 통과해야 한다.

### aiinit 적용 프로젝트

`aiinit` 또는 AI_AUTO 템플릿이 적용된 프로젝트는 다음 흔적을 사용할 수
있다.

```text
.omx/feedback/queue.jsonl
.omx/project-memory.json
.omx/review-results/*
.omx/context/*
.omx/plans/*
scripts/verify.sh
scripts/review-gate.sh
AGENTS.md
```

이 경우 구조화된 feedback, review, memory, plan 정보가 남아 있으므로
상대적으로 신뢰도가 높다. 그래도 backfill 결과는 기본적으로 draft에서
시작하고, 완료 확정은 별도 검증이나 사용자 확인을 거친다.

### aiinit 미적용 프로젝트

`aiinit` 없이 진행된 프로젝트도 수집은 가능하다. 다만 AI_AUTO 전용 흔적이
없으므로 git과 문서 기반의 후보 발굴로 제한한다.

```text
git log
commit message
branch name
README/docs
TODO/FIXME 주석
테스트 파일 변화
패키지/설정 변경 이력
Obsidian에 직접 적은 메모
```

이 경우 추출 결과의 기본 신뢰도는 낮게 둔다.

```text
source_quality: low | medium
status: draft
confidence: low | medium
outcome: inferred
promotion_state: not_candidate
```

사용 가능한 note 성격도 확정 지식이 아니라 후보로 제한한다.

```text
historical-finding
historical-incident-candidate
historical-lesson-candidate
pending-user-review
```

### Backfill 운영 원칙

Backfill은 완전한 과거 복원이 아니라 신호 대비 노이즈를 평가하기 위한
저비용 수집으로 시작한다.

```text
대표 프로젝트 1~2개 선택
→ git/docs/.omx 흔적 스캔
→ low-confidence 후보만 추출
→ Obsidian push 없이 요약 리포트 또는 local draft 생성
→ 사람이 쓸만함 / 노이즈 많음 판단
→ 가치가 있으면 정식 도구화
```

Backfill 결과는 바로 vault나 AI_AUTO 지침으로 승격하지 않는다. 특히 Odoo,
브라우저, 운영성 작업은 과거 git 기록만으로 field validation 여부를 알 수
없으므로 `resolved`가 아니라 `pending-user-review` 또는
`pending_field_validation`으로 남긴다.

### Backfill 수집 플래그

Backfill에는 수집 완료 플래그가 필요하다. 플래그는 "지식 확정"이나
"작업 완료"가 아니라, 특정 시점까지 read-only 수집을 마쳤다는 기록이다.

프로젝트별 플래그:

```text
.omx/knowledge/backfill-status.json
```

예시:

```json
{
  "schema_version": 1,
  "status": "collected",
  "collected_at": "2026-05-27T00:00:00Z",
  "collector": "AI_AUTO Reflection Backfill",
  "source_quality": "medium",
  "project_path": "...",
  "git_head": "...",
  "sources_scanned": [
    "git_log",
    "docs",
    "feedback_queue",
    "review_results"
  ],
  "outputs": {
    "report": ".omx/knowledge/backfill-report.md",
    "draft_count": 0,
    "obsidian_pushed": false
  },
  "privacy": {
    "raw_logs_copied": false,
    "secret_like_items_skipped": 3,
    "absolute_paths_redacted": true
  },
  "next_action": "user_review"
}
```

AI_AUTO 본진 전체 인덱스:

```text
.omx/knowledge/backfill-index.jsonl
```

예시:

```json
{"project":"Project_zurini","status":"collected","source_quality":"high","git_head":"abc123","draft_count":4,"next_action":"user_review"}
```

상태값:

```text
not_started
scanned
collected
drafted
user_review_required
pushed_to_obsidian
skipped_sensitive
needs_rescan
```

재수집 판단은 `git_head`, 수집 시각, 스캔한 source 목록, draft/report 출력
상태를 기준으로 한다.

## QC Routing Layer

AI_AUTO의 QC는 모든 작업에 6단계를 고정 실행하는 파이프라인이 아니다.
작업 유형과 위험도에 따라 필요한 QC만 켜는 조건부 라우팅 시스템이어야
한다.

### QC 레이어

```text
1. Minimal QC
   수정 중 빠르게 반복하는 최소 검증

2. Code QC
   테스트, lint, typecheck, build, smoke 등 개발자 검증

3. Review QC
   AI review, diff review, regression risk 검토

4. Domain QC
   Odoo, Ecount, 데이터 처리, 브라우저 자동화 등 업무 시나리오 검증

5. Field QC
   실제 환경 동작 확인, 사용자 확인, 로그/화면 증거

6. UX/UI QC
   화면 상태, 사용성, 반응형, 오류/빈상태, 디자인 일관성

7. Regression QC
   과거 이슈나 중요 기능의 재발 방지 검증
```

6레이어라고 부를 때도 `Regression QC`는 별도 조건부 보강 레이어로 둔다.
모든 작업이 전체 레이어를 통과하지 않는다.

### 트리거 매트릭스

```text
수정 중
→ Minimal QC

작업 단위 완료
→ Code QC

커밋 후보
→ Code QC + Review QC

업무 규칙/도메인 로직 변경
→ Domain QC

실제 Odoo/브라우저/운영 확인 필요
→ Field QC

UI 변경
→ UX/UI QC

버그 수정/반복 이슈/중요 기능
→ Regression QC
```

### 경로 예시

문서 수정:

```text
editing
→ minimal_checked
→ code_ready
→ done
```

Odoo 코드 변경:

```text
editing
→ minimal_checked
→ code_ready
→ review_ready
→ domain_checked
→ pending_field_validation
→ field_verified
→ done
```

UI 변경:

```text
editing
→ minimal_checked
→ code_ready
→ review_ready
→ ux_checked
→ done
```

Odoo UI 또는 업무 플로우 변경:

```text
editing
→ minimal_checked
→ code_ready
→ review_ready
→ domain_checked
→ ux_checked
→ pending_field_validation
→ field_verified
→ regression_checked
→ done
```

### 라우팅 원칙

- 매 수정마다 전체 QC를 실행하지 않는다.
- 작업 중에는 변경 파일 중심의 빠른 검증을 우선한다.
- 커밋 후보에는 프로젝트 review intensity 정책에 따른 `review-gate`를
  적용한다.
- 업무 규칙, 데이터, 자동화 플로우를 건드린 경우에만 Domain QC를 켠다.
- 실제 환경 확인이 필요한 프로젝트는 `pending_field_validation`으로
  남기고, 사용자 field confirmation이나 post-check 후 완료 확정한다.
- UI 변경이 없으면 UX/UI QC를 실행하지 않는다.
- 새 화면, 대규모 UI 변경, user-facing UI, 반복 사용 업무 UI는 Reference
  Intake Gate와 Visual QC Gate를 UX/UI QC의 하위 gate로 실행한다.
- Reference Intake Gate는 reference source, 추출 원리, 제외할 요소,
  민감정보 redaction 상태가 없으면 통과하지 않는다.
- Visual QC Gate는 구현 screenshot이 ui-spec과 reference principle을 추적
  가능하게 충족하는지 확인한다.
- 버그 수정, 반복 이슈, 중요 기능, reviewer가 지적한 회귀 위험이 있을 때만
  Regression QC를 추가한다.
- QC 결과는 Reflection Loop의 draft, report, promotion candidate 생성
  근거가 될 수 있다.

## UI Visual Alignment Layer

UI 작업은 말로 된 요구사항만으로는 사용자 의도와 AI 해석 사이의 갭이
생기기 쉽다. UI가 새 화면, 복잡한 흐름, 업무용 화면, 반복 사용 화면,
운영자 화면, 고객-facing 화면을 포함하면 Excalidraw 기반의 시각 보정
흐름을 사용한다.

### 기본 흐름

```text
UI reference intake
→ reference source, 사용 맥락, 금지할 복제 범위 기록
→ reference에서 적용할 원리 추출
→ AI_AUTO가 reference-brief.md 또는 ui-spec.md 초안 생성
→ 사용자가 reference 해석과 spec을 검토하고 의도 차이를 수정/승인
→ AI가 승인된 spec 기준으로 구현
→ Playwright/screenshot으로 실제 화면 캡처
→ reference principle / ui-spec / screenshot 비교
→ 불일치 시 UI 수정, spec 수정, 또는 reference 해석 수정
→ 승인된 spec, screenshot, reference principle을 기준점으로 저장
```

### Artifact 역할

```text
Excalidraw
→ 의도, 레이아웃, 정보 우선순위, 사용자 감각을 전달하는 그림

ui-spec.md
→ AI가 구현할 수 있는 명확한 계약

screenshot / browser test
→ 실제 구현이 계약과 맞는지 보여주는 증거

Obsidian
→ 결정된 UI 원칙, 좋은 예시, 반복 실수, 재사용 가능한 패턴 저장

reference-brief.md
→ 어떤 화면/제품을 참고했는지, 그대로 복제하지 않을 범위, 추출한 UI 원리,
  적용 대상 화면, QC 기준을 기록하는 reference 해석 문서

reference screenshot / existing screen
→ 시각 취향, 정보 밀도, 레이아웃 리듬, interaction pattern을 읽기 위한 입력.
  민감정보가 있으면 원본 저장 금지, redacted export 또는 설명 note만 허용

traceability matrix
→ reference principle이 docs/UI_PROFILE.md, ui-spec.md, 구현 screenshot,
  UX/UI QC 항목 중 어디에 반영됐는지 추적하는 표
```

Excalidraw만으로 구현에 들어가지 않는다. Excalidraw는 해석 여지가 크기
때문에 반드시 `ui-spec.md` 같은 구현용 spec으로 변환하고, 사람이 검토한
뒤 실행 계약으로 사용한다.

### UI Spec 필수 항목

```text
화면 목적
주 사용자
주요 동선
정보 우선순위
레이아웃 영역
컴포넌트 목록
상태: loading / empty / error / success / disabled
반응형 규칙
금지할 UI 패턴
reference source
reference에서 추출한 원리
복제하지 않을 요소
UI_PROFILE 반영 여부
reference principle → 화면 요소 trace
visual QC gate
완료 기준
스크린샷 검증 기준
Open Questions
```

그림이 애매하면 AI_AUTO는 behavior를 발명하지 않고 `Open Questions`에
남긴다.

### Practical Reference Workflow

reference 기반 UI 작업은 screenshot을 보고 바로 구현하지 않는다. 모든
reference는 다음 단계를 거쳐 실행 가능한 UI 계약으로 변환한다.

```text
1. Reference intake
   기존 제품, 기존 프로젝트 화면, 사용자가 제공한 screenshot, 또는
   domain UI 사례를 수집한다.

2. Principle extraction
   색상, 카드, 레이아웃을 그대로 베끼지 않고 정보 밀도, 조작 흐름,
   우선순위, 상태 표현, 반복 작업 피로도 같은 원리로 번역한다.

3. Project mapping
   추출한 원리를 docs/UI_PROFILE.md와 ui-spec.md에 매핑한다.
   프로젝트 목적과 맞지 않는 reference 요소는 명시적으로 제외한다.

4. Implementation trace
   구현 후 screenshot이 reference 원리와 ui-spec 항목을 어떻게 충족하는지
   traceability matrix에 기록한다.

5. Visual QC
   screenshot, console status, responsive viewport, overflow, 상태 화면,
   Anti-AI UI Checklist를 함께 검토한다.
```

reference가 부족한 비단순 UI 작업은 바로 구현하지 않고 `Open Questions`에
남긴다. 단, 기존 프로젝트 화면이 충분한 source of truth이면 외부 reference
없이 기존 화면 기반으로 진행할 수 있다.

### 적용 기준

작은 UI 수정:

```text
기존 UI 규칙 + screenshot QC만으로 진행 가능
```

새 화면 또는 복잡한 업무 흐름:

```text
Excalidraw sketch
→ ui-spec.md
→ 사용자 승인
→ 구현
→ screenshot QC
```

이미 디자인 시스템이나 기존 화면 패턴이 강한 프로젝트:

```text
기존 화면 screenshot / component pattern
→ ui-spec.md
→ 구현
→ screenshot QC
```

### 완료 기준

UI 변경은 다음 증거 없이 완료로 보지 않는다.

- 승인된 `ui-spec.md` 또는 기존 UI 규칙
- 주요 viewport screenshot 또는 browser smoke evidence
- console error 확인 결과
- loading, empty, error, success 등 필요한 상태 확인
- 텍스트 overflow와 버튼/폼 상태 확인
- spec과 실제 screenshot의 차이 판단

UI Visual Alignment 결과는 UX/UI QC의 입력이 되고, 반복되는 좋은 패턴이나
실수는 Reflection Loop를 통해 Obsidian note 또는 promotion-candidate로
남길 수 있다.

### Anti-AI UI Taste Layer

AI_AUTO는 UI를 만들 때 "AI가 생성한 듯한" 기본 패턴을 경계한다. 사용자가
매번 UI 취향을 티칭하지 않아도 되도록 프로젝트별 UI 취향, 금지 패턴,
reference screenshot, visual review를 구조화한다.

대표적인 AI스러운 UI 패턴:

```text
과한 그라데이션
둥근 카드 남발
불필요한 hero section
비슷한 보라/파랑 팔레트
큰 제목 + 의미 없는 설명문
실제 업무 밀도보다 마케팅 페이지 느낌
아이콘/버튼/상태가 기능보다 장식 위주
모든 앱이 SaaS 랜딩페이지처럼 보이는 현상
```

프로젝트별 UI 취향 파일:

```text
docs/UI_PROFILE.md
```

예시 필드:

```text
UI 성격: 내부 운영툴 / 고객-facing / 관리자 / 대시보드 / prototype
톤: 조용함 / 밀도 있음 / 빠른 스캔 / 반복 사용 / 설명 중심
금지: hero / marketing copy / gradient orb / 과한 카드 레이아웃
선호: 테이블 / 필터 / 상태 배지 / 명확한 액션 / 좁은 여백
색상: 중립 기반 + 상태색 제한 사용
기준 화면: reference screenshot 또는 기존 화면 경로
```

Anti-AI UI Checklist:

```text
이 화면이 실제 업무를 바로 시작하게 하는가?
불필요한 소개 문구가 있는가?
카드가 중첩되어 있는가?
그라데이션/장식이 기능을 방해하는가?
텍스트가 너무 크거나 마케팅 톤인가?
반복 작업자가 빠르게 스캔할 수 있는가?
기존 프로젝트 화면과 톤이 일관적인가?
```

Reference-based taste check:

```text
reference가 실제 사용 맥락과 같은가?
reference에서 추출한 원리가 UI_PROFILE에 반영됐는가?
구현 화면이 reference의 겉모습만 흉내 내고 있지 않은가?
업무형 화면인데 마케팅/랜딩페이지 문법이 섞이지 않았는가?
정보 밀도, action 위치, 상태 표시가 reference 원리와 일치하는가?
```

Visual Review는 기능 리뷰와 분리한다. 기능이 맞아도 화면이 업무 맥락,
정보 밀도, 일관성, 사용 피로도 기준을 통과하지 못하면 UX/UI QC에서
수정 대상으로 남긴다.

Visual Review는 `functional pass`와 `taste pass`를 분리한다. 기능이 맞아도
reference principle, UI_PROFILE, Anti-AI UI Checklist 중 하나라도 명확히
어긋나면 UX/UI QC는 `needs_visual_revision`으로 남긴다.

Reference screenshot은 Obsidian에 정제된 note로 저장할 수 있다. 단,
민감정보가 있는 screenshot 원본은 저장하지 않고, 필요하면 redacted export
또는 설명 note만 남긴다.

### Universal UI Guideline Reference Layer

UI reference는 특정 앱을 그대로 복제하기 위한 기준이 아니다. 여러 앱에서
잘 작동하는 원리를 추출해 범용 UI 가이드라인으로 승격하기 위한 원천으로
사용한다.

기초 reference의 역할:

```text
CapCut
→ 조작감, 빠른 작업 진입, 도구 배치, 생성/편집 워크플로우

monday.com
→ 업무형 정보 구조, 상태 표시, 보드/목록/대시보드, 협업 흐름

Notion
→ 문서/지식/블록 기반 편집, 낮은 마찰의 정보 정리

Todoist
→ 태스크 입력, 우선순위, 필터, 반복 작업

Linear 계열
→ 이슈, 버그, QC, 릴리즈 흐름

Slack / Discord 계열
→ 알림, 메시지, 피드백, 협업 인터랙션
```

범용 UI 가이드라인의 핵심 축:

```text
작업형 UI
→ 설명보다 현재 상태와 다음 행동을 우선한다.

정보형 UI
→ 목록, 상태, 필터, 정렬, 검색, 상세 진입을 기본 구조로 본다.

도구형 UI
→ 자주 쓰는 액션을 가까이에 두고, 설명보다 조작 가능한 컨트롤을 우선한다.

검토형 UI
→ 승인, 보류, 차단, 실패, 완료 같은 상태와 근거를 추적 가능하게 한다.

지식형 UI
→ 문서, 노트, reference, 결정 기록을 쉽게 남기고 다시 찾게 한다.

비-AI스러운 UI
→ 큰 hero 문구, 과한 그라데이션, 의미 없는 카드 묶음, 추상 아이콘 남발을 피한다.
```

reference를 적용할 때는 "이 앱처럼 만든다"가 아니라 "이 앱에서 어떤 원리가
잘 작동하는지 추출한다"로 기록한다. 좋은 reference screenshot도 곧바로
구현 기준이 되지 않고, `docs/UI_PROFILE.md`, `ui-spec.md`, UX/UI QC 기준으로
정리된 뒤 적용한다.

Reference 적용 결과는 다음 형식으로 남긴다.

```text
reference:
  source: 제품명, 기존 화면 경로, 또는 redacted screenshot note
  context: 왜 이 reference가 해당 작업에 적합한지
  extracted_principles:
    - 적용할 원리
  rejected_elements:
    - 복제하지 않을 요소와 이유
  mapped_artifacts:
    - docs/UI_PROFILE.md
    - ui-spec.md
    - screenshot evidence
  qc_result:
    - passed / needs_revision / blocked
```

이 기록은 UI 구현의 보조 증거이며, 저작권/민감정보/브랜드 복제 위험이
있는 원본 asset을 저장하거나 그대로 재현하는 근거가 아니다.

## Resource-Aware Execution

Review gate, QC sidecar, Reflection, Obsidian, MCP, subagent가 동시에
몰리면 다른 AI 세션, Docker, Playwright, 외부 reviewer quota, git, vault
작업과 충돌할 수 있다. AI_AUTO는 항상 풀가동하지 않고 현재 리소스와
동시 세션 상태에 따라 실행 폭을 줄인다.

### Gate 분리

```text
review-gate-core
→ verify
→ required AI review
→ final verdict

review-gate-sidecar
→ QC routing report
→ reflection draft report
→ knowledge draft
→ promotion suggestions
→ observability trace

privacy-gate
→ durable local draft/report/index 생성 전과 Obsidian push 직전의 blocking
  privacy check
```

Core gate는 최종 판정에 집중한다. Sidecar는 보조 리포트와 draft 생성을
담당하며, 실패하더라도 기본적으로 gate 자체를 실패시키지 않는다.

### Blocking / Non-blocking 구분

Blocking:

```text
verify 실패
필수 review 실패
저장 또는 push 대상에 민감정보 위험이 있음
```

Non-blocking:

```text
knowledge draft 생성 실패
Obsidian index update 실패
reflection report 생성 실패
promotion 후보 분류 실패
sidecar trace 생성 실패
```

Non-blocking 실패는 warning과 trace로 남기고 core gate 결과를 덮어쓰지
않는다.

### Resource Profile

실행 전 현재 세션 수, heavy process, reviewer 상태, 브라우저/CDP 사용,
vault lock, git repo lock을 확인하고 실행 모드를 낮춘다.

```text
normal
→ verify + review + sidecar 일부 병렬 가능

busy
→ verify/review 우선, sidecar는 defer

constrained
→ verify 우선, review/sidecar 최소화 또는 수동 실행

exclusive-needed
→ Playwright/CDP, Obsidian push, field-test는 lock 확보 전 실행 금지
```

Subagent 기본값:

```text
기본: 0~1개
normal: 최대 2개
busy: 0개 또는 1개
constrained: 0개
```

실행 폭은 다음 ladder로 낮춘다.

```text
full
→ verify + review + sidecar + optional UI/browser evidence

standard
→ verify + review + essential sidecar

minimal
→ verify + required review only

manual-only
→ evidence collection only, write/push/action queue deferred
```

### 리소스별 정책

```text
read-only local file scan
→ 비교적 안전

Obsidian/vault write
→ lock 필요

browser/CDP
→ exclusive 필요

external AI reviewer
→ quota-aware

Docker/build/test
→ resource-heavy

same-repo git operation
→ concurrent write 금지
```

### Obsidian 운영 원칙

Review gate 중에는 Obsidian push를 하지 않는다.

```text
review-gate 중
→ local draft 생성까지만 수행
→ 실패해도 warning

주기적 AI_AUTO 본진 수집
→ knowledge-collect
→ privacy scan
→ Obsidian push
→ index update
```

이 원칙은 review-gate 병목을 줄이고, vault/index race를 방지한다.

## Plan Review Output Format

plan review나 AI 다자간 회의 결과는 다음 항목을 남긴다.

```text
reviewers:
  - identity
  - available / skipped / degraded / fallback
context:
  - inspected artifacts
  - known gaps
agreements:
  - accepted changes
disagreements:
  - unresolved objections
required_fixes:
  - blocker before execution
decision:
  - proceed / proceed_degraded / revise / reject
```

`unanimous`, `consensus`, `all AIs agreed` 같은 표현은 독립 reviewer coverage,
degraded/fallback 상태, 반대 의견, context completeness가 artifact에 증명될
때만 사용한다. Codex fallback이나 skipped reviewer는 독립 reviewer 승인으로
계산하지 않는다.

## 통합 구현 우선순위

현재 AI_AUTO에는 AGENTS/skills, memory, feedback queue, review-gate,
knowledge draft, Obsidian push, checkpoint, Ralph 기반 장시간 작업 루프가
이미 있다. 따라서 외부 memory DB나 대형 agent platform을 먼저 붙이지 않고,
기존 조각을 하나의 운영 루프로 정식화한다.

### Phase 0: v1 Boundary Lock

1. v1 범위와 non-goal 확정

   v1은 local sanitized draft capture와 명시적 collection에 집중한다.
   실행 자동화, 대규모 backfill, Obsidian push 자동화, promotion 자동화,
   Workbench 실행 UI는 별도 phase로 분리한다.

2. 권한 매트릭스와 상태 모델 정식화

   work item state와 knowledge item state를 분리하고, Reflection이 완료
   상태를 소유하지 않는다는 원칙을 고정한다.

### Phase 1: Trigger / Privacy / Report Contract

3. Hooks 체계 정식화

   `review-gate`, `Ralph complete`, `commit`, `field-confirm`, `session-end`,
   `periodic reflection`을 독립 트리거로 정의한다. 커밋은 완료가 아니라
   evidence 추가 트리거로만 취급한다. 각 hook은 event, evidence, allowed
   output, blocking condition, idempotency key를 가진다.

4. Report 표준화

   `backfill-report`, `reflection-report`, `promotion-candidate report`의
   최소 필드를 정의한다. 각 report는 source, confidence, redaction 상태,
   next action, field validation 필요 여부를 포함한다.

5. Privacy gate 정식화

   durable local draft/report/index 생성 전과 Obsidian push 전 모두에서
   민감정보, 절대경로, raw log, raw prompt, credential-like 문자열,
   민감 screenshot 원본을 차단한다. 차단 항목은 원문 없이 skip 사유와
   count만 남긴다.

### Phase 2: QC / Field Boundary

6. QC Routing Layer 정식화

   작업 유형과 위험도에 따라 Minimal, Code, Review, Domain, Field, UX/UI,
   Regression QC를 조건부로 실행하는 매트릭스를 정의한다.

7. Field Validation Boundary 정식화

   field checklist, 사용자/operator confirmation, allowed post-check 결과,
   stale/degraded 증거 처리 기준을 프로젝트 유형별로 분리한다.

### Phase 3: UI Reference / Visual QC

8. UI Visual Alignment Layer 정식화

   Excalidraw, reference intake, `reference-brief.md`, `ui-spec.md`,
   traceability matrix, screenshot QC를 묶어 사용자 시각 의도와 AI 구현
   사이의 갭을 줄인다.

9. Anti-AI UI Taste Layer 정식화

   `docs/UI_PROFILE.md`, reference principle extraction, Anti-AI UI
   Checklist, visual review를 통해 AI스러운 UI 기본값을 줄이고 프로젝트별
   UI 일관성을 유지한다.

### Phase 4: Resource / Review Integrity

10. Resource-Aware Execution 정식화

    review-gate core와 sidecar를 분리하고, 동시 세션/리소스 상태에 따라
    sidecar, subagent, MCP, Obsidian push를 defer하거나 축소한다.

11. Review integrity 정식화

    reviewer identity, skipped/degraded/fallback 상태, context completeness,
    disagreement, contradictory evidence를 report에 남긴다. degraded reviewer는
    독립 만장일치 근거로 쓰지 않는다.

### Phase 5: Experimental Backfill / Promotion

12. Historical Backfill과 전체 프로젝트 수집 인덱스

   전체 프로젝트를 read-only로 훑어 수집 상태, 신뢰도, 후보 수, skip 사유,
   재수집 필요 여부를 본진 인덱스에 남긴다. explicit project list와 dry-run을
   기본 gate로 둔다.

13. Promotion reviewer와 지침 승격 절차

   Obsidian note나 feedback item이 바로 AGENTS/docs/scripts로 승격되지
   않게 한다. `promotion-candidate`는 별도 검토, 근거 확인, verify,
   review-gate를 통과해야 실제 AI_AUTO 지침이나 템플릿에 반영된다.

### Phase 6: Observability / Portability

14. Agent observability 최소 도입

   어떤 trigger가 언제 실행됐고, 어떤 draft/report를 만들었고, 무엇을
   skip했으며, next action이 무엇인지 trace로 남긴다. 목적은 디버깅과
   재수집 판단이지, raw transcript 보존이 아니다.

15. Portable AGENTS.md / SKILL.md 구조 유지

   Claude, Codex, Gemini, Antigravity 계열 도구가 모두 읽을 수 있게
   AGENTS.md와 SKILL.md 중심의 portable instruction 구조를 유지한다.
   provider-specific 기능은 helper나 hook으로 격리한다.

## Explicit Non-Goals for v1 Review

- 승인 없는 rebuild 실행, 자동 코드 수정, 자동 commit/push
- Obsidian note나 feedback item을 runtime behavior로 직접 반영
- historical backfill을 default-on으로 전체 workspace에 적용
- UI reference screenshot을 그대로 복제하거나 민감 원본 asset으로 저장
- degraded/fallback reviewer를 독립 만장일치 근거로 표시
- field validation evidence 없이 실제 완료 상태로 전이

## 이후 결정할 사항

- `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`의 AI회의 고도화
  검토 항목 중 어떤 것을 V1 본문 계약으로 승격할 것인지
- low severity 항목을 어느 수준까지 무시할 것인지
- Obsidian note와 feedback queue의 중복을 어떻게 병합할 것인지
- `aiinit` 또는 planning 단계에서 과거 note를 몇 개까지 보여줄 것인지
- 자동 생성된 draft를 사용자가 언제 검토하고 vault로 push할 것인지
- field validation checklist를 프로젝트 유형별로 어디에 정의할 것인지
- Historical Backfill 샘플 대상 프로젝트를 무엇으로 할 것인지
- Backfill status/index 파일을 local-only `.omx` 상태로 둘지, 일부 요약만
  tracked report로 승격할지
- UI Visual Alignment를 어느 수준의 UI 변경부터 필수로 요구할 것인지
- reference-brief.md와 traceability matrix를 ui-spec.md 안에 둘지,
  별도 artifact로 둘지
- Resource profile 감지 기준과 lock 파일 위치를 어떻게 표준화할 것인지
- `docs/UI_PROFILE.md`를 프로젝트별 필수 문서로 둘지, UI 작업이 있는
  프로젝트에만 생성할지
- external reference screenshot의 redaction, 저장 금지, Obsidian note
  변환 기준을 어디까지 자동화할지
