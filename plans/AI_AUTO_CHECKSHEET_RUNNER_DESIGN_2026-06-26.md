# 체크시트 러너 설계 — ponytail agentic-bench 5패턴 이식 (2026-06-26)

전략 서술 한국어, 식별자/경로 영어.

## Context
검증 자동화 최우선 화두(메모리 `feature-verification-automation-direction`)의 확정 골격
(`verification-checksheet-pipeline-design`)을 코드로 내리기 위한 설계. 외부 레퍼런스로
DietrichGebert/ponytail의 `benchmarks/agentic/`(정직한 결정론 오라클 하니스)를 채택해 5패턴 이식.

**리포 실측(조사됨):** 체크시트 러너는 **플랜-only**. 오라클-인접 코드 = Odoo 도메인팩 하니스뿐
(`templates/domain-packs/odoo/validation-harness/`)와 `scripts/verify.sh`. 제네릭 결정론 오라클·
`--selftest`·머신리더블 수용기준은 **전무**. 이 설계는 그 공백을 채운다.

## 빌드 토대 (기존 CODE 위에)
- **Odoo 2단 패턴 = prior art:** 싼 static screen(`check-action-shape.py`/`check-manifest-files.py`,
  결정론 AST) → runtime oracle(`popup-smoke.mjs`, 실제 실행 후 console-error-0 판정).
  `verify-patterns.md:40-65`. "screen은 판사 아님, 과대근사 후 런타임이 결정"의 3단 발상.
- **pure-core + thin-wrapper 패턴:** `self_demo_contracts.py`(+U1에서 추가한 CLI: name+stdin JSON→
  exit0/1/2). 러너 호출규약을 이 exit-code 컨벤션에 맞춤.
- **공백:** 제네릭 오라클 없음, `--selftest` 선례 없음, 머신리더블 수용기준 없음 → 전부 net-new.

## ponytail 5패턴 → 러너 스펙
1. **결정론 오라클 = 적대입력 실제 실행.** 체크시트 항목 1개 = oracle: 산출물을 고정 입력으로
   *실행*해 accepted/rejected를 **결정론적으로**(LLM 없이) 반환. 모델: ponytail `tasks.py`
   `score_safe_path`(`fn(base,"../../etc/passwd")` 실행 후 `os.path.commonpath`로 탈출 판정),
   `score_sql_user`(`' OR '1'='1` 주입), HMAC 변조, CSV malformed, rate-limit DoS — 전부 stdlib.
   Odoo "screen→execute" 2단을 제네릭화.
2. **요구사항 IMPLICIT → 누락 강제 검출.** 항목에 `implicit: true` 플래그 — 변경 스펙에 명시 안 된
   안전축(검증/보안)을 러너가 무조건 단언 → 까먹은 산출물을 잡음. ponytail "safety implicit, an arm
   that forgets gets caught"의 핵심. = 메모리의 "누락강제" 레인.
3. **측정기 오염 통제 / arm 격리.** 산출물-under-test를 러너 자신 환경에서 격리(fresh tmp + env 스크럽)
   해 러너가 자신을 통과시키지 않게. ponytail의 `--setting-sources project,local`+arm당 `--plugin-dir`
   오염버그 교훈 + 리포의 `env -u` 스크럽·[[verify-machinery-result-via-vmexit-value]](누출 마스킹) 동형.
4. **산출물 상태 측정 + 러너 `--selftest`(★net-new 핵심).**
   (a) 판정은 *서술*이 아니라 산출물/출력 *상태*에서. (메모리 DB델타/구조술어 레인과 동결.)
   (b) **`--selftest`:** 각 oracle은 known-good(통과해야)·known-bad(잡혀야) 레퍼런스를 동봉.
   실제 입력 신뢰 전, 러너가 oracle이 자기 bad 레퍼런스를 *잡는지* 먼저 증명 — 못 잡으면 abort
   (그 oracle 불신). ponytail `run.py --selftest`("good passes/bad caught before any API spend").
   → `echo $?` 마스킹 false-pass([[verify-machinery-result-via-vmexit-value]])에 대한 구조적 답.
5. **LLM은 결정론 불가 축에만, 감사가능하게.** 결정론 축(path/SQLi/HMAC/schema/DB-delta)=코드 oracle,
   LLM 결과산출 제외. 결정론 불가 축(예: 과설계 여부, UI 적정성)=옵션 LLM judge — 공개 루브릭+모델고정+
   temp0+구조물 지목 강제+judge selftest(bad>good 못 매기면 불신). ponytail `judge.py` 그대로.

## 구체 형태 (최소·접지)
- `scripts/checksheet-run.py`(pure-Python core) + thin `scripts/checksheet-run.sh`(self_demo 패턴).
  Odoo-특화로 커지면 도메인팩으로 분리. 제네릭/크로스도메인 수용오라클이 이 러너의 자리.
- **체크시트 포맷(머신리더블):** 항목 리스트 `{id, oracle, input, expect, implicit?}`(YAML/JSON).
- **oracle 라이브러리:** 결정론 체크 소수 레지스트리 — `safe_path`, `sql_param`, `hmac_verify`,
  `schema`/`db_delta`, `file_exists`(`check-manifest-files.py` 발상 재사용). 각 oracle은 good/bad 레퍼 동봉.
- **`--selftest`:** 실행 전 전 oracle 자기검증. 통과 못하면 비-zero abort.
- **판정/exit:** 항목별 accepted/rejected+reason, 하나라도 reject면 nonzero(fail-closed, self_demo CLI 규약 재사용).

## PoC 계획 (step 2, 다음)
ponytail oracle 1~2개(safe-path traversal, SQLi-param)를 oracle lib + 2항목 체크시트 + `--selftest`로
이식, "실제 산출물 실행 전 good 통과/bad 검출" 증명. stdlib-only, 의존성 0(ponytail 규율).

## 비목표 / 오픈
- DB-delta·Excalidraw 구조술어 레인(외부 메모리 설계) — 미래 레인으로 명명만, 지금 미구축.
- role/company matrix, Tours 통합 — Odoo 도메인, 별개.
- Odoo 하니스 재발명 금지 — 제네릭 러너는 비-Odoo/크로스도메인 수용오라클용.

## 추적
다음 단계는 위 PoC. 관련: `notes/ponytail-review-and-checksheet-todo.md`(Task #1 원천),
prior art `templates/domain-packs/odoo/validation-harness/`, `verify-patterns.md:40-65`.
