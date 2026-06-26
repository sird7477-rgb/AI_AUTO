# ponytail 검토 결론 + 체크시트 러너 후속 TODO

작성: 2026-06-25. 출처 레포: github.com/DietrichGebert/ponytail (v4.8.3, MIT).

## 1. 검토 결론 — AI_AUTO 게이트에 통합하지 말 것 (YAGNI)

ponytail = "게으른 시니어 개발자" 프롬프트 스킬. 핵심은 SessionStart/SubagentStart/
UserPromptSubmit 훅으로 7단 "사다리"(YAGNI→재사용→stdlib→네이티브→기설치의존성→한줄→최소구현)를
매 세션 강제 주입. 슬로건 "the best code is the code you never wrote."

**판정: 게이트 통합(리뷰 차원 추가/마커주석 하베스트) 전면 철회.** 근거:
- 철학이 이미 3중 인코딩 — `AGENTS.md:7`(Article 1.1 "the best code is code never written")
  + `scripts/make-review-prompts.sh:122-128`(maintainability/scope control) + `:195-202`(Gemini
  simpler alternatives). 네 번째 재진술은 준수율을 못 올림.
- 레포 자체 감사 `plans/AI_AUTO_OVERENGINEERING_AUDIT_2026-06-05.md`가 정반대 방향(빼기)을 권고.
  V1(리뷰 차원 추가)은 그 감사가 지목한 "advisory 층 2중 구현" 안티패턴을 그대로 추가함.
- 증거 전이 안 됨: 벤치는 Haiku·그린필드 FastAPI. 타깃은 브라운필드 bash(verify-machinery
  7,255줄)+Odoo. "코드 덜 쓰기" 레버는 기존 모놀리스 수술적 패치엔 거의 무효.
- 미러+버전범프+패치노트+parity 세금이 영구히 붙음(감사: "6 bumps/session").

**정정된 사실(초기 분석 오류):** scripts/ ↔ templates/automation-base/scripts/ 바이트동일을
*강제하는 게이트는 없음*(parity 테스트는 substring, 동일은 관행). 실제 강제는 버전범프뿐.
post-commit 하베스트는 commit trailer(`Finding:`)만 읽음 → `ponytail:` 소스주석 수확은 신규
코드패스 필요(기존 파이프 재사용 불가).

**남는 가치:** ponytail은 "참고(prior art)"로만. AGENTS.md 1.1 방향의 외부 독립 검증.
실익이 큰 건 아래 벤치 방법론.

## 2. TODO (a) — ponytail `benchmarks/agentic/` 패턴을 체크시트 러너로 이식

관련: verification-checksheet-pipeline-design, feature-verification-automation-direction.
ponytail의 `benchmarks/agentic/`(tasks.py 966줄, judge.py 185줄, run.py 449줄)은 당신
"오라클 문제" 설계의 작동하는 모범답안. 옮길 패턴 5가지:

1. **결정론 오라클 = 적대입력 실제 실행.** `tasks.py score_safe_path`는 LLM에 안 묻고
   `fn(base,"../../etc/passwd")` 실행 후 `os.path.commonpath`로 탈출 여부 기계 판정.
   → 체크시트 러너의 DB델타/구조술어 판정에 그대로. (SQLi `' OR '1'='1`, HMAC 변조,
   rate-limit DoS, CSV malformed, newline-injection 등 stdlib-only 결정론 체크.)
2. **요구사항 IMPLICIT → 누락 강제 검출.** 안전요건을 프롬프트에서 일부러 빼서, 까먹은
   에이전트를 잡음. → 누출결함/누락강제 레인에 채택.
3. **측정기 오염 통제.** SessionStart 훅이 baseline에도 켜져 대조군 오염 → 거짓 통과 직전.
   arm 격리(`--setting-sources project,local`, arm당 단일 `--plugin-dir`)로 수정.
   → verify-machinery-result-via-vmexit-value(echo $? 마스킹)와 동형. 러너 자기검증 필수.
4. **산출물 상태를 셈(서술 아님) + 러너 선(先)자기검증.** LOC=git diff 추가줄만, API 비용 전
   `--selftest`로 "good 통과/bad 검출" 증명. → 체크시트는 산출물 상태 측정 + 러너 selftest 게이트.
5. **LLM은 결정론 불가 축에만, 감사가능하게.** `judge.py`: over-engineering만 LLM 판정,
   공개 루브릭+temp0+모델고정+구조물 지목 강제+selftest로 "과설계>미니멀 못 매기면 불신".
   → LLM-judge 편향 검증 설계의 코드화 레퍼런스.

다음 단계: (1) ✅ 설계노트 완료 → `plans/AI_AUTO_CHECKSHEET_RUNNER_DESIGN_2026-06-26.md`
(5패턴→러너 스펙, Odoo 2단 하니스를 prior art로 접지). (2) safe-path/SQLi류 결정론 오라클 1~2개를
PoC로 러너에 이식해 `--selftest` 통과 확인 — 미착수.
