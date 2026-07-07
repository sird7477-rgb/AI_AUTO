# 적대적 리뷰 — SPEC v1 (2026-07-07)

리뷰어: Sonnet red-team 서브에이전트(실제 스크립트 대조) + Codex cross-family(방향 1패스).
결과: v1 **블루팀 인계 부적격**. → `2026-07-07-spec-v2.md`로 교정.

## Codex cross-family (방향)
- 우선순위 A2 > A1+A5 > A3. "seam"이 아니라 "verification contract"(정확한 커밋에 fresh proof 바인딩).
- 최대 사각지대 = proof 위조/stale proof 재사용. 청킹은 synthesis 패스 + 메타 필수.
- 게임 최고가치 공격각 = promotion-bypass + oracle-omission.

## Sonnet red-team (SPEC 결함, 심각도순)
- **D1 [CRIT] unimplementable/missing-vector**: 모든 집행이 client-side git 훅 → 훅은 clone/worktree-add로
  전파 안 됨(A1의 뿌리). doctor-in-pre-push는 순환. server-side 백스톱 없음. → out-of-band auditor 필요.
- **D2 [CRIT] false-closed**: HMAC 위협모델=untrusted project지 operating shell 아님. same-UID가 harness
  미실행 상태로 유효 proof 주조 가능. 5개 R-test 중 이걸 잡는 게 없음. → 테스트 추가 + 주장 하향.
- **D3 [HIGH] priority**: 헤드라인은 게이트 없는 워크트리서 push됨 = A1/IP-2 실패이기도. IP-1 단독으론 못 잡음
  → IP-1+IP-2 동시 필요.
- **D4 [HIGH] priority**: Lore-hook FP가 plumbing 우회의 실증 트리거인데 IP-4 dry-only에 방치. IP-2가
  게이트 강화하면 우회압력↑ → IP-2와 동반 수정.
- **D5 [HIGH] gameable**: "bound"의 강도가 곧 게이트 강도. plumbed 커밋도 (약한)게이트 재실행하면 bound.
  현재 게이트=codex 자기리뷰 → IP-2 hard-block이 "codex 자기승인"으로 축소. → IP-3 non-codex 리뷰어 선행.
- **D6 [MED-HI] gameable/regression**: size-fail을 transient로 → disabled_at 매번 리셋 → 21일 stale경보가
  영원히 안 뜸. → chronic-redisable 카운터.
- **D7 [MED] false-closed/모순**: docker-down hard-stop이 기존 ack-bypass(`AI_AUTO_PRINCIPAL_LAUNCHER=1`
  env, 셸 자가export)와 충돌. → TTY 등 자가생산불가 신호로 상향 or override 명시.
- **D8 [MED] missing-vector**: IP-1이 `mods` 비면(custom-addons 밖) skip → hard-stop 도달 전 종료. → 임의
  diff엔 harness, mods는 `-u` 범위만.
- **D9 [MED] unimplementable-as-specified**: doctor `--project`는 warn-only 설계. `--bootstrap` required 목록
  미명시. → 열거 + `--project` 불변 테스트.
- **D10 [LOW-MED] mislabeled**: AC1-4는 AC1-1에 포섭. 진짜 A4 동시성(TOCTOU: proof생성~push 사이 트리변이)
  미테스트. → session-lock 토큰 바인딩 + TOCTOU 테스트.
- **D11 [LOW] gameable**: chunked synthesis 테스트가 presence만 검사. → 청크경계 걸친 이슈 포착 테스트.
- **D12 [LOW] gameable**: "shell-only" 미정의. → pytest-collected 경로 무접촉으로 정의.

## Verdict
Not ready as-is. 반드시: (1) same-UID 위조갭 닫기 or 주장 하향(D2), (2) IP-1+IP-2 동시(D1/D3), (3) Lore-hook
FP를 IP-2와 함께(D4). → v2에 전부 반영 완료.
