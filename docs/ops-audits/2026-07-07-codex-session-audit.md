# AI_AUTO 운영 감사 — 2026-07-07 jw_dev 코덱스 세션 (적대검증본)

범위: 2026-07-07 하루의 jw_dev 코덱스 세션 13개(worktree w0/w1/w2/w3/w4, ~14MB).
방법: 6개 서브에이전트(Sonnet)가 세션 다이제스트를 분담 정독 → 오케스트레이터(Opus)가
증거를 다이제스트/원본 jsonl/파일시스템으로 **적대적 교차검증** 후 종합.
대상은 **AI_AUTO 파이프라인 운영문제**이며 jw_dev 제품(Odoo) 로직 버그는 제외.

계열다양성: Gemini(agy) = `api_env=missing`로 사용 불가(프로덕션 게이트 로그가 확증, 아래 P2).
따라서 cross-family 협의는 Codex로 대체(single-family+codex).

---

## 헤드라인 (검증 완료)

**정적 로컬 게이트가 무한재귀 결함 커밋을 통과시켜 origin에 푸시했고, odoo.sh 빌드가 KILLED됐다.
이 클래스를 잡는 유일 수단은 docker harness(`validate-full.sh`) — 사용자가 오늘 처음 제기한
"로컬 테스트 DB 검증 안 됨"과 정확히 같은 도구다.** 정적검증의 green은 설치가능성을 보장하지 않는데,
파이프라인은 정적 green을 push 조건으로 취급하고 있었다.

- 커밋 `5e7da49`(jw_calendar work_type_calendar_sync): `partner_ids` 자동보정이 `write()`를
  재진입 → `_jw_ensure_default_attendees()` 무한재귀 → `RecursionError: maximum recursion depth exceeded`.
- `./scripts/verify-project.sh` = PASS(정적: XML well-formed + py_compile). → **origin/NEW_JS_dev 푸시**.
- odoo.sh: `Module jw_calendar: 0 failures, 2 errors of 2 tests` → 빌드 KILLED.
- `validate-full.sh`(docker/postgres harness)가 사후 재현. 후속 커밋에서 수정.
- 원본 jsonl 확인: `KILLED`×45, `RecursionError`×12, `1 failed`×7. (환각 아님.)

---

## P0/P1 확정 소견 (다세션 독립 확인)

### A1 [CRITICAL] 워크트리 간 게이트 배포 불일치
- `review-gate.sh`·`verify.sh`·`session-lock.sh`·`automation-doctor.sh`·`verify-machinery.sh`·
  `ai-principal-runtime.sh`가 **일부 워크트리엔 존재·실행**(w1/w2에서 `./scripts/review-gate.sh` 실 호출
  99+회, `[gate]` 출력 존재)되지만 **main jw_dev(NEW_JS_dev)·일부엔 on-disk 부재**(파일시스템 직접 확인).
- 부재 워크트리의 커밋은 `[post-commit] WARNING: no review-gate proceed verdict found ... may have
  bypassed review-gate`만 남기고 통과 — 경고는 정의상 차단 못 함(커밋은 이미 발생).
- 5개 세션(12-03-24/13-03-44/12-38-06/10-49-20/16-25-23)이 독립 확인. AGENTS.md·docs/WORKFLOW.md는
  이 스크립트들을 **필수**로 명시.
- **적대검증 정정**: 최초 "게이트 전무" 주장은 과잉 — 실제론 "있는 워크트리도 있으나 없는 데선 무방비"인
  **배포 일관성 결함**이 정확. (헤드라인 5e7da49는 게이트 없는 NEW_JS_dev에서 푸시됨.)

### A2 [HIGH] 검증공백: verify-project.sh는 정적 전용, 런타임 오라클 없음
- `verify-project.sh`는 스스로 `local Odoo runtime is not configured` 선언 + Playwright 기본 skip.
  참조하는 harness/lock/principal 스크립트가 없으면 `[ -x ]` 가드로 **전부 silent-skip** → 실효 검증 =
  XML lint + py_compile + 몇몇 grep-check뿐.
- 이번에 통과된 미검증 변경: 무한재귀(A1 헤드라인), `project.project`에 `jw_client_id` 강제
  `ValidationError`(기존 레코드 write 파괴 가능), `purchase.order.unlink()` 상태전이-후-삭제, OWL 대시보드
  위젯 로직, view XML — 전부 실 Odoo 설치/렌더 없이 커밋.
- harness(docker Lane 2)가 유일한 실오라클인데 `verify-project.sh`에 미배선. **docker가 죽으면 실검증 0**.

### A3 [HIGH] 외부 독립리뷰가 21일째 죽어 codex 자기리뷰로 상시 degrade
- 게이트 로그: `[gate] EXTERNAL REVIEW PERSISTENTLY DEGRADED: reviewer 'claude' disabled 21d ago (>7d)`
  및 'gemini' 동일.
- Gemini: `runtime_unavailable: runtime=agy reason=large_prompt_requires_prompt_file
  prompt_bytes=102029 prompt_arg_max_bytes=100000`, `api_env=missing`, `next_action=user_reset_required`,
  `reset_hint=RESET_DISABLED_AI_REVIEWERS=gemini`. **~100KB 하드실링 + 청킹 폴백 없음**(Claude는 같은 런에서
  6분할 자동) → 정상 크기 diff마다 영구 트립. 3주째 독립리뷰 부재를 상시-degraded 신뢰로 용인.
- 게임의 "single-family / AA-4 미실행" 취약섹션이 **프로덕션서 라이브**. (내 agy 호출 실패도 동일 원인.)

### A4 [HIGH] 동시성: session-lock 부재 → 공유 워크트리 오염
- 13-03-44: 공유 `NEW_JS_dev`의 HEAD가 이 세션이 안 만든 커밋으로 조용히 전진 + 무관 파일 유입,
  사용자가 두 번 물어서야 자기 diff와 외부 diff 분리. `verify-project.sh`의 동시성 가드는
  `session-lock.sh` 존재 조건부인데 그게 없어 무방비.

### A5 [HIGH] gate-bypass가 상시 관행화
- 12-34-59: `git push --no-verify`를 게이트 부재 시 표준 우회로 3회+ 사용. Lore-format pre-commit 훅이
  이미 규정준수 메시지를 8회 연속 거부 → `git write-tree`+`commit-tree`+`update-ref` 원시 플러밍으로
  훅 우회. (훅 false-positive가 우회를 유발.)

---

## P2 확정 소견 (중간 심각도)

- **B1 [MED] 게이트 diff-scope가 무관 untracked 파일 흡입**: 워크트리에 상주한 `requirements.txt`가
  gate scope에 섞여 무관 `request_changes` 유발, 매 게이트/커밋마다 수동 제외. `git stash pop` EXIT=1로
  수동복구까지. (16-25-23, 12-34-59.)
- **B2 [MED] 커밋시점 manifest version 무단 범프**: test-fixture 한 줄만 건드린 3개 addon 포함 4개 매니페스트
  version이 out-of-band로 변경 → 사후감사로만 발견. (12-38-06.)
- **B3 [MED] git status --short가 dirty 워크트리서 빈 출력**: exec-session stale/9p 슬로우 의심,
  다음 `git diff`가 즉시 반증. gate-scope 오산정 위험. (16-25-23.)
- **B4 [MED] 워크트리 state 오염**: 자기 tmux 세션의 워크트리 자가삭제(10-19-00);
  `git apply` 실패 → 통짜 `cp` 폴백으로 무관 내용 유입 후 수동 제거(13-03-44).
- **B5 [MED] 재발견 flail**: "게이트 스크립트 부재"라는 정착된 사실을 세션당 10회+ 재확인(캐시 안 함).

## P3 확정 소견 (저·잡음)

- **C1 [LOW] perf-waste**: 9p 마운트서 find/rg 30–90s 스톨로 수동 인터럽트 4회+; clean-worktree-per-push
  패턴이 ~10분 docker base 재빌드 반복 유발.
- **C2 [LOW] 검증도구 가용성 갭**: `agent-browser` PATH 부재, repo Playwright node_modules 미설치 →
  글로벌 CLI를 시행착오로 발견(자가복구).
- **C3 [LOW] direct `docker compose ps`가 harness env 부재로 실패**(자가복구) — **본 세션 #1 프리플라이트가
  이 클래스를 명확한 메시지로 전환**.

## 오케스트레이터 직접 발견 (본 세션)

- **D1 [MED] 배포 harness가 정본 대비 stale**: `00. DATA/harness/`의 배포본이 ai-lab 템플릿 대비
  attr-source git-exec RCE 하드닝·warm-PASS 캐시·orphan-container cleanup trap을 결여. (템플릿 refresh
  미적용.)
- **D2 [LOW] 신선 워크트리 venv 갭**: `.venv` 없는 fresh 워크트리에서 pre-commit pytest가 `flask` 수집불가로
  fail → shell 전용 변경조차 `--no-verify` 유도(하드닝된 훅의 의도를 무력화).

---

## WHAT WORKED (회귀 방지용 기록)

- pre-push 바인딩 게이트는 **있는 워크트리에선** verdict 없이 push를 통과시킨 적 없음 — 모든 우회는 명시적
  `--no-verify`로 로깅됨.
- `validate-full.sh`(docker harness)는 호출되기만 하면 정적이 놓친 실회귀(무한재귀)를 정확히 포착.
- `proceed_degraded`는 "커밋 승인 아님" 정직 고지를 일관 유지, clean pass로 위장 안 함.
- 커밋 메시지의 `Not-tested:` 필드가 게이트 부재를 매번 자기고지 — 은폐 없음.

---

## 취약섹션 매핑 (→ #4 블루/레드 게임 입력)

| 감사 소견 | 지난 게임서 미커버/약했던 섹션 |
|---|---|
| A2 검증공백·오라클부재, 헤드라인 | verification-gap / oracle-omission (게임 후반 얕게) |
| A3 외부리뷰 21일 죽음, Gemini 100KB실링 | single-family / AA-4 LLM-judge 실저항 (미실행, "최고가치") |
| A1 게이트 배포 불일치 | template-distribution / connectivity (비보안, 후발) |
| A4 동시성 락 부재 | concurrency (bounded만 테스트) |
| B1/B3 gate-scope 오산정 | quality-uniformity / correctness (후발) |
| C1 9p·재빌드 비용 | operational-cost/perf (후발) |
