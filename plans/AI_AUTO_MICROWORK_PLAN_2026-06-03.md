# AI_AUTO MicroWork 구현 계획 (2026-06-03)

ST-P1-21 활성화(사용자 승인 2026-06-03). later_gated → active. "정규화까지 포함하는
Ralph"로, 프로토타입이 아니라 **정규 표면(verify + review-context)에 배선된** 부작용
없는 MicroWork 계약·검증 도구를 구현한다. AI 리뷰(Gemini + Codex, principal=claude)로
계획 검증 후 구현한다.

## 1. 목적
대형/전략 작업을 산문 규칙이 아니라 **검증 가능한 "마이크로 단위" 계약**으로 형식화한다.
마이크로 단위 = 스코프·최소유효쐐기·비목표·필요증거·완료조건을 명시한 JSON. 이미 쓰는
"마이크로 단위 + 스코프 규율 + 완료조건 드리프트 방지(ST-P1-28)"를 도구로 고정한다.

## 2. 마이크로 단위 스키마 (JSON)
필수 필드: `id`, `goal`, `scope_paths`(비어있지 않음), `smallest_useful_wedge`,
`non_goals`(비어있지 않음), `required_evidence`(비어있지 않음), `completion_criteria`(비어있지 않음).

## 3. 구현 범위

### 3-1. 순수 계약 — `scripts/micro_work_contracts.py` (홈 전용)
- `validate_micro_unit(record) -> ContractResult`: 필수 필드 비어있지 않음 검사;
  `scope_paths`와 `non_goals` 경로 충돌 시 `non_goal_scope_conflict`; 통과 시 ready.
- `micro_work_scope_audit(record, changed_paths) -> dict`: **리포트 전용** —
  scope 밖 변경(scope_drift), 비목표 영역 변경(non_goal_leak), 필요증거 표기 유무,
  최소유효쐐기 유무를 계산해 반환(차단하지 않음). 부작용 없음.
- `tests/test_micro_work_contracts.py`: 각 게이트 + 정상 + 감사 분기.

### 3-2. CLI — `tools/micro-work` (전역 헬퍼)
- `micro-work validate <file.json>`: 계약으로 검증, 결과/사유 출력, exit code. **읽기 전용**.
- `--json`으로 기계 판독 출력. 런타임/큐/스케줄러/자동실행/완료권한 **신설 금지**.
- 전역 헬퍼 정규화: `install-global-files.sh` 심링크 집합 + `docs/GLOBAL_TOOLS.md` +
  헬퍼-링크 패리티 테스트(`test_global_helper_link_surfaces_stay_in_sync`)에 등록.

### 3-3. 얇은 래퍼 — `scripts/micro-check.sh` (홈 전용)
- 기본 경로(`.omx/micro/current.json` 또는 `--file`)를 `tools/micro-work validate`로 넘기는
  얇은 래퍼. 부작용 없음.

### 3-4. 리뷰 표면 배선(정규화) — `scripts/collect-review-context.sh` (템플릿 소유)
- 마이크로 단위 파일이 있을 때(`MICRO_WORK_FILE` 또는 `.omx/micro/current.json`)
  **"MicroWork Audit" 리포트 전용 섹션** 출력: scope_drift / non_goal_leak / 증거 적정성 /
  최소유효쐐기. 기존 report-only 감사들과 동일 패턴, **차단하지 않음**.
- 템플릿 소유 → 루트/템플릿 byte-identical 동기 + `AI_AUTO_TEMPLATE_VERSION` 범프 +
  `PATCH_NOTES.md` 항목. `tests/test_micro_work_context.py`로 잠금.

### 3-5. verify 스모크 — `scripts/verify.sh`
- 유효 마이크로 단위 → micro-work validate 통과, 무효(필드 누락/충돌) → 실패+사유,
  scope_drift/non_goal_leak 감사 분기, micro-check.sh 래퍼 동작.

## 4. 비목표(Non-Goals)
- 런타임·큐·스케줄러·UI·자동실행·완료권한 신설 금지. MicroWork는 **검증/리포트 전용**이며
  `verify.sh`/`review-gate.sh` 위의 권한을 갖지 않는다.
- 감사 섹션은 **리포트 전용**(리뷰 게이트를 차단하지 않음).
- 마이크로 단위 파일 작성을 강제하지 않는다(있을 때만 감사). 기존 워크플로 불변.

## 5. 정규화/소유 정리
- 홈 전용: `scripts/micro_work_contracts.py`, `scripts/micro-check.sh`,
  `tests/test_micro_work_contracts.py`. (install-automation-template 복사 목록 미등록)
- 전역 헬퍼: `tools/micro-work` (+ install-global-files/GLOBAL_TOOLS/패리티 테스트).
- 템플릿 소유: `collect-review-context.sh` 감사 추가(+미러 동기, 버전범프, 패치노트,
  `test_micro_work_context.py`).

## 6. 검증(엔드투엔드)
1. `verify.sh` 그린 — 신규 micro-work 스모크 + 컨텍스트 감사 + 헬퍼 패리티 + 템플릿 동기/버전.
2. `pytest` — 계약/컨텍스트 테스트.
3. `AI_AUTO_PRINCIPAL=claude ./scripts/review-gate.sh` 만장일치.
4. 백로그 `ST-P1-21` → complete_contract. 커밋 후보 제시, 커밋·푸시는 승인 후.

## 7. 단계(마이크로) 실행
- 단계 A: 계약 + CLI + 래퍼 + 테스트 + verify 스모크(홈/전역, 템플릿 무변경) → verify·review·커밋.
- 단계 B: collect-review-context 감사 배선(템플릿 소유, 버전범프) + 컨텍스트 테스트 →
  verify·review·커밋.
- 각 단계 독립 커밋(마이크로 단위), 각자 만장일치.
