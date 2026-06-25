# AI_AUTO U2 정리 플랜 — 이중구현 붕괴 vs pytest 병목 (2026-06-26)

전략 서술은 한국어, 식별자/경로/상태값은 영어(감사 corpus 규약).

## Context

감사 `plans/AI_AUTO_OVERENGINEERING_AUDIT_2026-06-05.md` U2: "모든 정책이 두 번 구현되고
드리프트한다" — 각 정책이 (a) `scripts/self_demo_contracts.py`의 Python 계약 + (b)
`scripts/collect-review-context.sh`의 Bash 감사로 각각 존재, 손수 동기, 테스트도 양쪽.

U1 세션에서 사용자가 **속도(pytest 병목 축소)** 목표로 B(U2)를 선택. 그러나 착수 전 실측 결과
**속도와 이중구현 제거는 별개 문제**임이 드러남:

| 범위 | 시간 | 비고 |
|---|---|---|
| 전체 suite (`test_app.py` 제외, flask 미설치) | **31.0s** | 229 tests |
| `tests/test_*_context.py` 11파일 | **10.5s** | 29 tests, ~42 subprocess spawn |
| `tests/test_self_demo_contracts.py` (Python 계약) | **0.12s** | 53 tests |
| odoo_docs_kb + model_routing 단일 테스트 2개 | **~9s** | **U2 밖** |

병목 근본원인 = **테스트 구조**: 각 `*_context.py` 테스트가 `collect-review-context.sh`를 매번
재spawn하고, 그 스크립트는 단일 `{ … } > OUT_FILE`로 **16개 섹션 전부 + git init**을 생성
(`collect-review-context.sh:1448`). 한 섹션 단언하려고 전체 리포트를 매번 재생성. → **이중구현
'존재'가 아니라 per-test subprocess가 비용.** 따라서 두 목표를 분리한다.

## 핵심 사실 (검증됨)
- Bash 감사 = 유일한 런타임 소비자: 출력이 `.omx/review-context/latest-review-context.md`로 들어가
  리뷰어가 읽음. 전부 `audit_status: report_only`(차단 안 함). **삭제하면 리뷰어 리포트 상실.**
- Python 계약(페어 8~9개) = test-only 미러, 런타임 호출자 없음(U1에서 `review_gate_short_summary`
  1개만 배선됨). `test_self_demo_contracts.py`가 단언할 뿐.
- 양측은 진짜 로직 중복(렌더링 vs shape 아님): 예) spec_code_alignment — Python `:1128` triggered/
  invalid_row 규칙 ≡ Bash `:942-1006` 동일 case 분기. product_challenge required_shape 집합도 양쪽 복제.
- 페어 정책(둘 다 존재): spec_code_alignment, standard_flow_preservation, product_challenge,
  browser_qa_evidence, visual_artifact, planning_visual_gate, completion_pack_routing,
  persona_lens, phase_scope_guard. (delegation_recording은 fold.) **tree_churn / micro_work /
  model_routing = Bash-only(Python 없음) → 이중구현 아님, de-dup 대상 밖.**

## Phase 1 — 속도 (저위험, 먼저): `*_context.py` subprocess 배칭
"B 선택"이 원한 속도는 이중구현 제거가 아니라 이걸로 얻는다.
- **메커니즘:** 각 `tests/test_*_context.py`의 `_run_context(...)`를 per-test 호출에서
  **module(또는 session)-scoped fixture**로 전환 — `collect-review-context.sh`를 필요한 env
  superset로 **1회** 실행, `latest-review-context.md` 캐시, 각 테스트는 자기 `## … Audit` 섹션을
  캐시 텍스트에서 슬라이스해 단언.
- **착수 전 파일별 점검:** 한 파일 내 테스트들이 동일 env 설정을 공유하는지 vs 변형이 필요한지.
  변형 필요 시 parametrized fixture 소수로(여전히 spawn 1~2회), 진짜 다르면 해당 테스트만 per-test 유지.
  최대 수혜: spec_code_alignment·browser_qa·standard_flow·planning_visual_gate·micro_work(각 3~4 spawn).
- **대상 파일:** `tests/test_*_context.py` 11개. **scripts/·템플릿 미러·버전범프 불필요**(테스트만 수정).
- **기대:** context 블록 10.5s → ~3s, suite에서 **~6~8s 절감**. 커버리지·런타임 동작 **무손실**.
- **검증:** `python3 -m pytest -q tests/test_*_context.py` 전/후(테스트 수 불변, 시간↓);
  전체 suite 시간 ~6~8s↓. 런타임 스크립트 미변경이므로 게이트 동작 회귀 없음.
- **위험:** 낮음(순수 테스트 리팩터). fixture 스코프 누수(테스트 간 OUT_FILE 오염) 주의 — 캐시는 읽기전용 슬라이스.

## Phase 2 — 진짜 U2 de-dup (선택·고위험·별개): 단일 진실원
U2 '문언' 그대로 = 두 번째 구현 제거. 속도와 무관, **드리프트 방지(유지보수)** 목적일 때만.
- **2a (추진 시 권장): Bash 감사를 Python 계약에서 생성.** 각 `write_*_audit` 본문을
  `python3 self_demo_contracts.py <name> --report`(신규 report 모드, 리포트 라인 방출) 호출로 교체.
  로직 1벌(Python). 배칭된 통합테스트 1개 + 빠른 Python 테스트로 커버.
  - 비용/위험: `collect-review-context.sh` ~10섹션 emitter 재작성 + **템플릿 미러(parity+범프)**.
    리뷰어/테스트가 의존하는 **정확한 출력 문자열** 보존 필수. 게이트-임계 스크립트, 블라스트 큼.
- **2b (기각): Bash측 삭제** — 리뷰어 리포트(유일 소비자) 상실.
- **drop-Python (감사 option a): Python측+테스트 삭제** — 0.12s만 줄고 계약 커버리지 손실. 정리 목적이면 가능하나 속도 무익.
- **대상:** 위 페어 9개. bash-only 3종 제외.

## 비목표
- odoo_docs_kb(4.8s) / model_routing(4.1s) 느린 단일테스트 — **U2 밖**, 별도 티켓(실제 suite 시간 목표면 추적).
- 리뷰어용 review-context 리포트 삭제.

## 권장 시퀀스
1. **Phase 1 즉시** — 싸고 안전, B가 원한 속도 확보(~6~8s).
2. 재측정. suite 시간 수용 가능하면 정지.
3. **Phase 2는 드리프트 방지가 독립 목표일 때만** — 미러/범프 세금 지는 별도 리뷰 변경으로.

## 추적
- U1 진행분(이미 머지 전 작업트리): self_demo_contracts CLI + `review_gate_short_summary` fail-closed
  배선 + 계약↔셸 normal-trust 드리프트 1건 정합화. PATCH_NOTES `2026.06.25.1`. 커밋 대기.
