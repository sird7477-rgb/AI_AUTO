# PRD: AI_AUTO Native Workbench

## 목적

AI_AUTO Native Workbench는 VS Code 확장이나 기성 IDE 플러그인이 아니라,
AI_AUTO 사용 방식에 맞춘 전용 운영형 IDE / 워크벤치다.

목표는 코드를 편집하는 IDE를 새로 만드는 것이 아니라, 다중 터미널,
AI 세션, 검증, review-gate, QC, Reflection, Obsidian 지식화, UI reference
작업을 한눈에 통제할 수 있는 작업판을 제공하는 것이다.

## 핵심 정의

```text
터미널 = 실제 작업대
AI_AUTO Native Workbench = 작업 현황판 + 체크리스트 + 승인대기함 + 지식화 콘솔
```

v1에서는 터미널을 그대로 내장하지 않는다. 터미널, tmux, Codex, Claude,
검증 스크립트, 로그의 상태를 읽고 요약하며, 필요한 액션을 제안하거나
승인 대기 상태로 보여준다.

## 선행 프로토타입과 역할 분리

`<local-private-path>/IPAD_mornitor`에 세션 모니터링 중심의 선행 프로토타입이
있다.

따라서 Native Workbench를 단순 세션 모니터로 다시 만들지 않는다. 기존
프로토타입은 "현재 무엇이 보이는가"를 확인하는 모니터 성격으로 보고,
Native Workbench는 "무엇을 검토, 승인, 보류, 검증, 기록, 승격할 것인가"를
결정하는 운영 콘솔로 정의한다.

```text
IPAD_mornitor
→ 세션/화면/상태를 보는 모니터

AI_AUTO Native Workbench
→ QC, review-gate, Reflection, Obsidian, promotion, field validation을 다루는 운영 콘솔
```

Session Monitor는 Native Workbench의 핵심 정체성이 아니라 보조 패널로
낮춘다.

## 비전

```text
흩어진 프로젝트와 AI 작업 세션을 한눈에 파악한다.
완료 상태를 코드 완료, 커밋 완료, 현장 확인, 최종 완료로 분리한다.
review-gate와 QC 결과를 사용자가 빠르게 판단할 수 있게 만든다.
작업 중 얻은 lesson, incident, finding, promotion-candidate를 지식화한다.
UI reference, Excalidraw, screenshot, ui-spec을 한 흐름으로 묶는다.
```

## 핵심 화면

### Project Board

전체 프로젝트 상태를 보여준다.

```text
프로젝트명
최근 작업
현재 상태
backfill 수집 여부
QC 상태
Obsidian sync 상태
field validation 필요 여부
```

### Session Monitor

진행 중인 AI 작업과 터미널 세션의 상태를 요약한다.

```text
Codex / Claude / Ralph 상태
현재 작업 목표
최근 command 또는 trigger
실패/대기/완료 상태
어느 터미널 또는 로그를 봐야 하는지
```

터미널 화면 자체를 복제하지 않고, 상태와 요약을 보여준다.

### QC / Review Gate Console

검증과 리뷰 상태를 보여준다.

```text
verify 결과
review-gate 결과
QC routing 결과
Domain QC 필요 여부
Field QC 대기 여부
UX/UI QC 필요 여부
Regression QC 필요 여부
```

목표는 사용자가 긴 로그를 모두 읽지 않아도 `차단`, `주의`, `통과`,
`사용자 확인 필요`를 빠르게 구분하게 하는 것이다.

### Reflection Inbox

작업 중 생성된 지식화 후보를 모은다.

```text
incident
lesson
finding
promotion-candidate
backfill-report
reflection-report
```

이 화면은 자동 반영 화면이 아니라 검토함이다. Obsidian push 또는 지침 승격
전에 privacy gate와 promotion reviewer를 거친다.

### Obsidian Sync / Promotion Review

Obsidian에 보낼 note와 AI_AUTO 지침 승격 후보를 분리해서 검토한다.

```text
Obsidian draft
privacy warning
redaction 필요 여부
push 대기
promotion candidate
승격 승인 / 보류 / 폐기
```

### UI Reference & Spec Studio

범용 UI 가이드라인과 화면별 UI spec을 다룬다.

```text
reference screenshot
.excalidraw import/export
ui-spec.md 생성
구현 screenshot 비교
UX/UI QC 결과
Anti-AI UI checklist
```

CapCut, monday.com, Notion, Todoist, Linear, Slack/Discord 같은 reference는
그대로 복제하지 않고, 조작감, 정보 구조, 상태 관리, 태스크 흐름, 협업
인터랙션 같은 원리만 추출한다.

### File Drop Command Bar

텍스트 입력과 파일 드래그앤드랍을 함께 지원하는 명령 수집창이다.

```text
파일 드롭
→ 경로와 파일 타입 인식
→ 프로젝트 내부/외부 여부 확인
→ 민감정보 가능성 검사
→ context card 생성
→ 가능한 액션 제안
→ 사용자 명령 또는 승인 후 실행
```

지원 후보:

```text
source file
folder
screenshot
.excalidraw
log
CSV / XLSX / PDF
git diff / patch
Odoo error log
```

입력칸은 실행창이 아니라 요청 수집창이다. 파일을 드롭했다고 즉시 수정,
실행, Obsidian push를 하지 않는다.

## v1 범위

v1은 읽기 중심 관제와 승인 중심 워크플로우에 집중한다.

포함:

```text
Project Board
QC / Review Gate Console
Reflection Inbox
Obsidian Sync 상태 표시
Promotion Review 초안
File Drop Command Bar
UI Reference & Spec Studio의 import/spec draft 중심 기능
Session Monitor 보조 패널
```

제외:

```text
완전한 코드 편집기
터미널 전체 내장
무제한 명령 실행
자동 Obsidian push
자동 지침 승격
기성 IDE 플러그인 종속
```

## 단계별 확장

### v0: Product-grade Design Checkpoint

구현 전에 "제대로 만들 가치가 있는가"를 검증한다. 큰 IDE를 바로 만들지
않고, 제품급 정보 구조와 상태 모델을 먼저 확정한다.

```text
Workbench의 핵심 문제 정의
기존 IPAD_mornitor와의 중복 제거
첫 화면 정보 구조
상태 소스 목록
읽기 전용 데이터 모델
privacy boundary
실행 버튼 제외 기준
```

### v1: Read-first Workbench

```text
상태 읽기
로그 요약
검증 결과 표시
파일 드롭 context 생성
reflection draft 검토
UI reference/spec draft 생성
```

v1 실행 전에는 privacy blocking contract가 먼저 고정돼야 한다. Workbench는
file drop, log summary, screenshot reference, draft/context card, local
persistence, Obsidian/promotion flow에서 다음 기준을 통과하지 못한 입력을
저장하거나 외부 동기화하지 않는다.

```text
allowed output
→ redacted summary
→ count + reason
→ path category, not raw private path
→ reference principle, not raw sensitive screenshot

redaction required
→ raw logs
→ absolute/private paths
→ credentials, tokens, keys, session values
→ customer/user/company private data
→ screenshots with sensitive visible content
→ raw prompts or raw .omx transcript-like dumps

must-not-store
→ unredacted screenshot originals
→ credential-like strings
→ raw prompt/log dumps
→ private absolute paths when a path category is enough
→ external-production evidence without explicit approval
```

Minimal privacy verification gate:

```text
negative checks:
→ raw log rejected or summarized
→ absolute/private path redacted
→ credential/token-like value rejected
→ sensitive screenshot requires redacted note only
→ degraded reviewer label preserved and not shown as consensus
```

이 gate가 없으면 Workbench v1은 read-only display 수준을 넘지 않는다.

### v2: Action Queue Workbench

```text
검증 실행 버튼
review-gate 실행 버튼
Obsidian push 승인
promotion candidate 승인/보류
field confirmation 처리
```

Action class:

```text
read_only_local
safe_local_command
repo_write_proposal
obsidian_push
field_confirmation
external_or_production_action
```

Workbench는 policy에 따라 action request를 enqueue하고 approve/defer할 수
있다. 실제 실행은 AI_AUTO runtime/scripts로 위임한다. destructive,
credentialed, production, materially scope-changing action은 명시 승인 없이는
차단한다.

### v3: Embedded Tooling

```text
tmux pane bridge
PTY session viewer
Excalidraw 편집 기능 일부 내장
Playwright screenshot 비교
project-local command palette
```

터미널 내장은 v3 이후 선택 기능으로 둔다. 보안, 권한, 세션 복구, 키 입력
전달, 로그 저장 정책이 정리되기 전에는 기본 기능으로 넣지 않는다.

## 설계 원칙

- 기성 IDE의 UX 철학에 종속되지 않는다.
- 사용자의 다중 터미널 작업 방식을 대체하지 않고 관제한다.
- 기존 `IPAD_mornitor`와 중복되는 단순 세션 모니터링을 핵심 가치로 삼지 않는다.
- 자동 실행보다 상태 가시화와 승인 흐름을 우선한다.
- 완료 상태를 `code_ready`, `commit_ready`, `field_ready`, `done`으로 분리한다.
- UI는 실제 업무, 실제 상태, 실제 액션을 중심으로 한다.
- AI스러운 hero, 과한 gradient, 의미 없는 card 묶음을 피한다.
- 파일 드롭은 즉시 실행이 아니라 context 생성과 액션 제안으로 처리한다.
- raw log, 민감 경로, credential, screenshot 원본은 privacy gate 전에는 외부 저장하지 않는다.

## Reflection Loop와의 관계

Native Workbench는 Reflection Loop를 대체하지 않는다. Reflection Loop가
생성한 draft, report, promotion candidate, privacy warning, backfill index를
사용자가 검토하고 통제할 수 있게 보여주는 UI 레이어다.

```text
Reflection Loop = 관찰, 정제, draft, 분류, 추천
Native Workbench = 상태 가시화, 검토, 승인, 보류, action request 표시
```

Workbench는 authoritative knowledge를 자체 생성하지 않는다. Reflection
artifact와 action request를 보여주고, 수락된 action은 AI_AUTO
scripts/hooks/runtime에 handoff한다.

## Obsidian과의 관계

Obsidian은 장기 지식 저장소다. Native Workbench는 Obsidian으로 가기 전의
검토함과 동기화 상태판 역할을 한다.

```text
Knowledge sync:
Workbench draft
→ privacy gate
→ user review
→ Obsidian note

Promotion:
local draft / feedback / reviewed note
→ promotion reviewer
→ repo edit proposal
→ verify.sh
→ review-gate.sh
→ accepted AI_AUTO guidance
```

## 결정 필요

- v1 구현 형태: 웹앱, 로컬 데스크톱 앱, Tauri/Electron, 또는 단순 로컬 서버
- 상태 수집 방식: 파일 기반 polling, event hook, MCP, 또는 혼합
- tmux/Codex/Claude 세션 식별 방식
- 파일 드롭 시 허용할 기본 파일 타입
- UI Reference & Spec Studio를 v1 핵심에 포함할지, v1.5로 분리할지
- 기존 `IPAD_mornitor`에서 재사용할 구조와 버릴 구조
- Session Monitor를 별도 제품으로 유지할지, Workbench 보조 패널로 흡수할지

## 현재 환경 메모

2026-05-28 기준, Windows PowerShell에서는
`<local-private-path>/IPAD_mornitor`가 정상 조회된다. 내부에는
`package.json`, `server.js`, `shortcuts.json`, `start.bat`, `tray.ps1`,
`public/`, `node_modules/`가 확인되었다.

다만 현재 WSL 세션에서는 `/mnt/d` 접근이 `Invalid argument`로 실패한다.
Windows D: 드라이브 자체는 `NTFS / Healthy / OK`로 확인되었으므로 파일
문제가 아니라 WSL의 D 드라이브 마운트 브리지 문제로 본다. 분석을 계속하려면
PowerShell 경유로 읽거나, WSL 재시작 후 `/mnt/d` 접근을 재확인한다.
