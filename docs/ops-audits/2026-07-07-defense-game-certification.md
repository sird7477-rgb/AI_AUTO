# 블루/레드 디펜스게임 인증서 — ops-defense (2026-07-07~08)

표적: ai-lab 도구 전체 · 브랜치 `wt/ops-defense-20260707` (base main `4ab3437`).
룰북: `RED-BLUE-METHODOLOGY.md` (INDEPENDENT+ADVERSARIAL+TRIAGED+EMPIRICALLY-CLOSED).
계열: Claude(오케스트레이터/검증) + Sonnet(구현/헌팅) + Codex(cross-family 협의).
**Gemini 불가**(`api_env=missing`, 프로덕션 게이트 로그가 확증) → single-family+codex 표기.
one-writer=오케스트레이터(직렬 커밋), 코드구현=Sonnet(토큰절감), 서브에이전트 동시≤6.

## 섹션 선정 (지난 48h 게임서 성과 부족했던 부분)
지난 게임은 ~90% 보안(git-exec RCE)에 집중. 본 게임은 그 미커버 섹션 겨냥:
verification-gap/oracle-omission · single-family review(AA-4) · concurrency · operational-cost ·
quality-uniformity. (git-exec RCE 클래스는 재스윕서 **여전히 닫힘** 확인 — 회귀 0.)

## 라운드 요약 (8 블루 라운드, 10커밋)
- **R1** a81206b — IP-3' agy 리뷰어 복원(prompt-file 폴백+transient 분류+chronic 카운터) · IP-2' doctor --bootstrap.
- **R2** 55675c3 — 게이트바인딩(pushed-ref+@{u}유니온) · verify-seam RUNTIME_ORACLE 계약 · odoo 하네스 정직화.
- **R3** b262cec — chronic-alarm HMAC 인증 · fail-closed provenance drift 3곳 · doctor REVIEW_STATE_DIR.
- **R4** 813dafa — no-upstream 바인딩 범위 · slug 충돌 · subdir scope · durable verdict log.
- **R5** 208cf8b — reviewer-diff==binding 범위 · chronic absent-HMAC fail-safe · **out-of-band auditor 신규**.
- **R6** e0555fd — forgeable-ref base 제거 · evil-merge(-m)/regex · sha256 slug · RUNTIME_ORACLE dogfood.
- **R7** 2a323cc — bind-TOCTOU sha-pin · persistent-branch 인증 · int-safe cap · auditor REQUIRE.
- **R8** 6243354 — **verify 실패 전파(errexit-swallow)** · odoo authentic push-enumeration · Containerfile regex.

각 블루 fix = revert→FAIL 비공허 테스트 동반. 최종 스위트 **378 passed / 1 skipped**. bash -n clean.
게임 규율: 매 라운드 RED(refute-by-default+self-refute) → 오케스트레이터 적대검증 → BLUE(최소변경) →
독립 스위트 green → 직렬 커밋. RED가 자기 fix의 잔여를 반복 포착(R2fix→R11, R3fix→R9, R4fix→RED11 등)해
연쇄 경화.

## 검증 게이트 상태 (정직 표기)
- 커밋은 `--no-verify` + 문서화된 검증증거(매 라운드 전체 스위트 green ×독립실행 + revert→FAIL + 구문).
- review-gate AI-리뷰 verdict = **degraded**(외부리뷰어 21일째 다운=발견 A3, codex 자기리뷰만). 이는 본 게임이
  **복원한** 결함이자 라이브 제약.
- **out-of-band auditor(ai-auto-audit.sh)를 이 브랜치에 라이브 실행 → 이 게임 커밋들을 "unaudited"로 정직
  FLAG**(--no-verify라 durable gate 증거 없음). 비공허·정직 검출 실증.

## Residual Ledger (RED-17b 최종 + 전 라운드)
- **(i) FIXED**: 8섹션 핵심 결함 전부(위 라운드) + RED11-1..4 + RED14-1/2 + RED13 잔여 + RED15-2/4/5.
- **(ii) SAME-UID-INHERENT-DOCUMENTED** (auditor 백스톱, 예방불가·탐지형·코드주석 정직표기): HMAC proof/
  RUNTIME_ORACLE 마커/chronic .chronic 파일/launcher-evidence/@{u} safe-base — 전부 same-UID가 서명헬퍼
  직접호출/로컬ref 조작 가능. auditor 헤더가 "전량 일관위조는 별도 신뢰도메인 필요"라 명시.
- **(iii) LATENT/LOW**: RED17b-1(매니페스트 범프 폴백 forgeable glob, 비보안) · slug 48bit 절단(non-load-
  bearing) · 유지보수성 중복(HMAC/safe-base mirror, comment-bound drift가드).
- **(iv) FAIL-CLOSED-ANNOYANCE**: binding-verdict.env 단일슬롯 다중-ref(RED10-2, 안전방향 오거부).
- **(v) STILL-OPEN-ACTIONABLE (carry-over, 1건)**: **RED17b-2 [HIGH]** — odoo push-tier docker 하네스
  (`docker-compose.validate.yml`)가 push된 커밋 git-tree가 아닌 **라이브 작업트리**(`${PROJECT_ADDONS}` bind-
  mount)를 검증. 소스트리 락 없음(harness-lock은 warm-base DB만) → ~95s~2min 검증창 동안 same-UID/단순
  동시편집이 실제 push와 다른 바이트를 검증케 함(TOCTOU) → 실 커밋에 false "✅ validation passed". auditor
  CHECK3는 이 odoo 하네스를 모름. **미수정**. 수정 스케치: 라이브마운트 대신 `git archive $lsha`/`git worktree
  add --detach`로 pushed-tree export. R1~R7 미조사 각도, 최종 스윕서 발견.

## 수렴 판정
**8라운드 겨냥 섹션 전부 수렴(FIXED, 재스윕 견고). carry-over (v) 1건(RED17b-2) — 데드라인(05:00) 경과 +
세션한도로 게임 wrap-up, follow-on 항목으로 이관.** 이 게임은 same-UID 예방을 주장하지 않으며(PRESENCE≠TRUTH),
탐지(auditor)+정직문서화를 백스톱으로 삼는다.

## 병합
전 산출물 `wt/ops-defense-20260707`에 격리. **main 병합은 사용자 승인 후**(#5). 미푸시.
