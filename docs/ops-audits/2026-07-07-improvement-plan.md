# AI_AUTO 개선계획 — 2026-07-07 (감사 #2 → 개선 #3)

입력: `2026-07-07-codex-session-audit.md`. 결정협의: Claude(오케스트레이터) + Codex(cross-family,
`codex exec` 자문 로그 `scratchpad/codex_consult_out.txt`). Gemini는 `api_env=missing`로 협의 불참.

## 우선순위 (Codex 협의로 재조정)

내 최초 순위는 A3(Gemini 복원) 1순위였으나, Codex가 **A2(런타임 오라클 필수화)를 1순위**로 반론:
"헤드라인(무한재귀 커밋이 origin 도달 + odoo.sh KILLED)은 **실증된 프로덕션 피해**이고, 독립리뷰
복원은 중요하나 그 다음. 실오라클이 아예 없는 상태가 최우선." **채택.** 최종 순위:

1. **IP-1 [P0] Verification Contract** (A2 + 헤드라인) — 실런타임 오라클을 승격 필수조건으로.
2. **IP-2 [P1] Gate/harness presence fail-closed across worktrees** (A1 + A5) — 미배선·우회를 hard-stop으로.
3. **IP-3 [P1] 독립 cross-family 리뷰 복원** (A3) — agy 대용량 프롬프트 폴백 + disabled 자동재프로브.
4. **IP-4 [P2] 잔여 하드닝** (B1 gate-scope, D1 template staleness, D2 venv gap, A5 Lore-hook FP).

## Codex 협의 핵심 (스펙에 반영)

- "seam"이 아니라 **"verification contract"**: 승격은 **정확한 그 커밋에 바인딩된 fresh proof** 요구 —
  authoritative harness 통과 + Docker 실가용 + helper 존재 + harness 버전 기록. 미배선=hard stop, warning 아님.
- **최대 사각지대 = proof 위조 / stale proof 재사용**: harness가 한 번 통과 후 (a)다른 HEAD를 push,
  (b)옛 로그 재사용, (c)엉뚱한 워크트리서 실행, (d)Docker-down을 "일시 degraded"로 무시 — 이 4경로를 닫지
  않으면 IP-1은 **false-closed**(된 것처럼 보이나 안 됨).
- agy 청킹 리스크: 순진한 청킹은 전역 맥락 상실 → **청크 findings에 대한 최종 synthesis 패스 + "chunked/
  truncated" 메타데이터** 필수.
- #4 게임 최고가치 공격각: **promotion-bypass + oracle-omission**.

## 범위 경계 (tool-side only)

수정 대상 = ai-lab 프레임워크 파일(엔진 스크립트 + 템플릿). jw_dev 배포/자격증명(agy api key,
harness docker 상시기동)은 jw_dev측 운영이라 본 계획 밖 — 단, IP-2 bootstrap-detector가 "미배포"를
**소리나게** 만들어 jw_dev측 조치를 강제(silent 아님).

앵커 파일:
- IP-1: `scripts/verify.sh`, `scripts/verify-project.sh`, `scripts/verify-machinery.sh`,
  `templates/domain-packs/odoo/hooks/pre-push`, `templates/domain-packs/odoo/validation-harness/*`,
  `scripts/review-gate-binding.sh`(HMAC provenance 재사용).
- IP-2: `scripts/automation-doctor.sh`(bootstrap-detect 모드), `templates/domain-packs/odoo/hooks/pre-push`,
  `scripts/review-gate.sh`(post-commit warning → promotion 시 block).
- IP-3: `scripts/ai-runtime-adapter.sh`(:296 arg-max, :327 size분기, :288 run_readonly_agy),
  `scripts/run-ai-reviews.sh`, `scripts/review-gate.sh`(:641 disabled 분류/재프로브).

## 실행 방식

IP-1~IP-3의 구체 수용기준 = `2026-07-07-spec.md`. 구현·하드닝은 #4 블루/레드 게임에서 수행
(블루=구현[Sonnet], 레드=promotion-bypass/oracle-omission 공격). 본 계획·스펙은 게임 착수 전
**적대적 리뷰**(cross-family Codex 1패스 완료 + 서브에이전트 red 1패스)를 받는다.
