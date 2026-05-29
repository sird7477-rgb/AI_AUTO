# AI_AUTO Small-Tool Adoption Review - 2026-05-28

## Scope

이 문서는 GStack 외의 소도구 채택 후보를 문제영역별로 검토한 1차 분석이다.
목표는 새 패키지를 많이 설치하는 것이 아니라, AI_AUTO가 이미 가진 도구를 먼저
재사용하고 꼭 필요한 빈칸만 작은 단위로 메우는 것이다.

- 분석 대상: `scripts/`, `tools/`, `docs/`, `plans/`, `tests/`
- 현재 상태: `requirements.txt`는 Flask, psycopg, pytest만 사용
- 설치 확인: 원 분석 시점에는 `jq`와 `rg`만 사용 가능했다. 이후 사용자
  승인으로 `hyperfine 1.18.0`과 `shellcheck 0.9.0`을 설치했다. `shfmt`,
  `cloc`, `tokei`, `ruff`, `markdownlint`, `semgrep`, `actionlint`, `fd`,
  `yq`는 현재 PATH에서 미설치
- 하지 않은 작업: runtime hook 추가

## Decision Rule

채택 순서는 다음이 맞다.

1. 이미 있는 내부 도구를 그대로 사용한다.
2. 내부 도구 결과를 묶는 얇은 wrapper를 만든다.
3. 표준 도구가 이미 설치되어 있으면 optional path로만 쓴다.
4. 외부 패키지 설치는 마지막에 둔다.
5. 설치형 도구는 설치 전 공식 문서, 라이선스, 실행 권한, rollback 경로를 다시 확인한다.

## Scoring Rubric

각 항목은 0-5점이다. 총점은 35점 만점이다.

| 항목 | 의미 |
| --- | --- |
| Fit | AI_AUTO의 현재 구조와 맞는 정도 |
| Utility | TODO 누락, 검증, 리뷰, 벤치마크에 주는 즉시 이득 |
| Smallness | 마이크로 단위로 붙일 수 있는 정도 |
| Verification | 테스트/문서/fixture로 검증하기 쉬운 정도 |
| Low dependency | 새 패키지 설치가 적거나 없는 정도 |
| Low authority risk | commit, push, 배포, credential 권한과 충돌하지 않는 정도 |
| Maintenance | 장기 유지보수 부담이 낮은 정도 |

Decision:

- `adopt_existing`: 이미 있는 내부 도구를 표준 경로로 사용
- `adopt_contract`: 코드 없이 문서/검증 계약으로 채택
- `prototype_internal`: 내부 wrapper나 작은 테스트로 실험
- `optional_external`: 설치되어 있으면 사용하되 필수로 만들지 않음
- `reference_only`: 현재 TODO가 아니며, 특정 구조 변화가 생길 때만 재검토
- `reject_default`: 기본 채택 금지

## Existing Internal Tools

| Tool | Current role | Adoption note |
| --- | --- | --- |
| `./scripts/verify.sh` | 전체 deterministic 검증 | 이미 최상위 gate. 다만 장시간 review 테스트가 중첩 프로세스를 만들 수 있어 guard 후보가 있다. |
| `./scripts/review-gate.sh` | verify + AI review + verdict | 최종 gate. Claude/Gemini/Codex fallback 상태가 복잡해져 요약 helper 후보가 있다. |
| `./scripts/collect-review-context.sh` | 리뷰 context 생성 | untracked 문서가 기본 context에서 빠질 수 있다. untracked 후보 문서 검토 모드가 필요하다. |
| `./scripts/summarize-ai-reviews.sh` | reviewer verdict 요약 | 이미 핵심 판단 로직 보유. 사람이 보기 쉬운 short summary wrapper가 유용하다. |
| `./scripts/doc-budget.sh` | 지침 문서 예산 | 이미 경고/실패 분리. stage-2 duplicate report 연결은 optional이다. |
| `./scripts/guidance-duplicate-report.sh` | 지침 중복 분석 | `jscpd` 있으면 사용, 없으면 fallback. 현재 방식은 좋은 optional-external 패턴이다. |
| `tools/ai-auto-template-status` | 템플릿 drift read-only 검사 | 이미 안정적. patch workflow와 연결되어 있음. |
| `tools/ai-refactor-scan` | read-only refactor 후보 탐색 | 구조 분석 소도구로 이미 채택됨. |
| `tools/ai-rebuild-plan` | read-only rebuild preflight | 실행 승인과 분리된 좋은 패턴. |
| `tools/ai-split-*` | Python split plan/dry-run/apply | apply에 명시 승인 gate가 있어 안전한 구조. |
| `tools/ai-plan-*` | 계획 상태/리뷰/export | deep interview와 실행 승인 분리용으로 이미 유효. |
| `feedback-collect`, `knowledge-collect` | local queue/draft 수집 | 권한이 opt-in이라 유지. |

## Candidate Matrix

| Candidate | Type | Fit | Utility | Smallness | Verification | Low dependency | Low authority risk | Maintenance | Total | Decision | Rationale |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Review gate short summary | internal wrapper | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 35 | prototype_internal | `review_manually`, disabled reviewer, fallback failure를 한 줄 요약해 사용자가 바로 판단하게 한다. |
| Untracked artifact review mode | internal wrapper/contract | 5 | 5 | 4 | 5 | 5 | 5 | 4 | 33 | prototype_internal | 이번 Gemini 리뷰가 untracked 후보표를 못 본 문제가 있었다. 후보 문서 작성 직후 `REVIEW_INCLUDE_UNTRACKED_CONTENT=1` 또는 targeted file review 계약이 필요하다. |
| Diff scope classifier | internal wrapper | 5 | 5 | 4 | 5 | 5 | 5 | 4 | 33 | prototype_internal | 변경 파일을 docs/scripts/tests/templates/API 등으로 나눠 reviewer와 검증 강도를 추천한다. GStack `gstack-diff-scope` 아이디어와도 맞다. |
| Benchmark runner wrapper | internal wrapper | 5 | 4 | 4 | 5 | 5 | 5 | 4 | 32 | prototype_internal | `scripts.self_demo_contracts.benchmark_evidence`와 baseline 문서를 연결해 측정값, 샘플 수, 환경을 빠짐없이 남긴다. |
| TODO/report normalizer | contract + internal helper | 5 | 5 | 4 | 4 | 5 | 5 | 4 | 32 | prototype_internal | 사용자가 반복 지적한 TODO 누락 문제에 직접 대응한다. 남은 일, 보류, 승인 필요, 검증 필요를 분리한다. |
| Process leak guard for review tests | internal test guard | 4 | 5 | 3 | 4 | 5 | 5 | 3 | 29 | prototype_internal | `verify.sh` 안의 review runner 테스트가 실제 reviewer process처럼 보이는 중첩 실행을 남길 수 있다. timeout/cleanup fixture 보강 후보. |
| Tool availability doctor | internal wrapper | 4 | 4 | 5 | 5 | 5 | 5 | 5 | 33 | prototype_internal | optional tool의 설치 여부와 채택 상태를 한 번에 출력한다. 설치 자체는 하지 않는다. |
| Guidance duplicate deep scan | existing optional path | 4 | 3 | 4 | 5 | 4 | 5 | 4 | 29 | adopt_existing | 이미 `guidance-duplicate-report.sh`가 있고 `jscpd` optional fallback 구조가 좋다. |
| `jq` JSON validation path | installed standard tool | 4 | 4 | 5 | 5 | 5 | 5 | 5 | 33 | adopt_existing | 이미 설치되어 있다. JSONL/manifest 검사에 쓰기 좋지만 Python stdlib로 충분한 곳은 유지한다. |
| `shellcheck` | external lint | 4 | 4 | 4 | 5 | 2 | 5 | 4 | 28 | required_gate | 사용자 승인 후 설치했고 warning severity를 `verify.sh` 필수 게이트로 승격했다. |
| `shfmt` | external formatter | 3 | 3 | 4 | 5 | 2 | 5 | 4 | 26 | reject_default | 대량 formatting churn 위험이 ShellCheck warning gate 대비 크다. TODO에서 제외한다. |
| `hyperfine` | external benchmark | 4 | 4 | 4 | 4 | 2 | 5 | 4 | 27 | optional_external | 사용자 승인 후 설치했다. benchmark wrapper와 연결하되 필수 verify gate로 올리지는 않는다. |
| `tokei` or `cloc` | external size metrics | 3 | 3 | 4 | 4 | 2 | 5 | 4 | 25 | reject_default | LOC/언어 통계는 현재 `wc`, `find`, Python, `doc-budget.sh`로 충분하다. TODO에서 제외한다. |
| `ruff` | external Python lint | 3 | 4 | 3 | 5 | 2 | 5 | 4 | 26 | reference_only | Python 파일과 정책이 커질 때만 재검토한다. 현재 TODO에서 제외한다. |
| `markdownlint` | external doc lint | 3 | 3 | 3 | 4 | 2 | 5 | 3 | 23 | reject_default | 기존 장문 운영 문서와 충돌 가능성이 높고 예외 관리 부담이 크다. TODO에서 제외한다. |
| `actionlint` | external CI lint | 1 | 1 | 4 | 5 | 2 | 5 | 5 | 23 | reject_default | 현재 GitHub Actions surface가 없다. TODO에서 제외한다. |
| `semgrep` | external static analysis | 3 | 4 | 2 | 3 | 1 | 4 | 2 | 19 | reject_default | 규칙/오탐/성능 부담이 커서 이 로컬 testbed의 일반 TODO에서 제외한다. |
| `yq` | external YAML helper | 2 | 2 | 4 | 4 | 2 | 5 | 4 | 23 | reject_default | YAML surface가 작고 현재 shell/Python으로 충분하다. TODO에서 제외한다. |
| Browser QA automation package | external/runtime | 2 | 4 | 2 | 3 | 1 | 2 | 2 | 16 | reject_default | UI가 실제 요구될 때만 별도 승인. 브라우저 상태/쿠키/세션 권한 리스크가 크다. |

## Recommended Micro Roadmap

### M1: Review visibility

목표: 사용자가 review-gate 상태를 캐묻지 않아도 즉시 이해하게 한다.

- `review-gate short summary` 설계
- 입력: 최신 `review-verdict-*.md`, `review-run-*.md`, reviewer files
- 출력: final decision, usable reviewers, missing reviewers, fallback 상태, next command
- 검증: fixture verdict 파일로 `proceed`, `proceed_degraded`, `review_manually`, `blocked` 각각 테스트

### M2: Artifact inclusion guard

목표: 새 후보표나 계획 문서가 untracked라서 리뷰에서 빠지는 일을 막는다.

- commit candidate 전 untracked `plans/*.md`, `docs/*.md`, `scripts/*`, `tools/*` 감지
- review context가 untracked content를 포함했는지 표시
- 포함하지 못하면 "manual review required"로 명시
- 검증: untracked plan fixture가 context에 포함/미포함되는 테스트

### M3: Diff scope classifier

목표: 변경 파일에 따라 검증/리뷰 강도를 자동 추천한다.

- docs-only, plans-only, scripts, tools, tests, template, app/API, docker, guidance로 분류
- 각 분류에 required checks를 매핑
- 검증: 파일 경로 fixture 기반 expected scope table

### M4: Benchmark wrapper - completed observe mode

목표: 성능평가가 임의 기준이 아니라 재현 가능한 evidence record가 되게 한다.

- Python stdlib timer 또는 shell `time`으로 시작
- 결과를 `benchmark_evidence` 계약에 맞게 JSON/Markdown으로 남김
- `hyperfine`은 설치됐지만 optional로만 설계
- 검증: temporary fixture, project baseline, failed benchmark 상태 테스트

### M5: TODO normalizer

목표: "남은 todo"가 실행 안 됨/미흡/승인 필요/완료를 빠뜨리지 않게 한다.

- 입력: backlog/plans/review artifacts
- 출력: open, contract_started, deferred, blocked, completed 섹션
- 검증: fixture 문서에서 누락 없이 분류되는지 테스트

## Current Recommendation

`shellcheck`와 `hyperfine`은 별도 사용자 승인 후 설치 완료했다. 지금 바로
추가 설치할 외부 패키지는 없다.

`shellcheck -S warning` 기준 경고는 마이크로 단위로 정리했고 `verify.sh`
필수 게이트로 승격했다. 전체 ShellCheck info/style 출력은 아직 필수 게이트가
아니며, 필요할 때 별도 cleanup TODO로 다룬다.

남은 내부 wrapper/계약 TODO는 없다. Benchmark wrapper는 observe mode까지
완료됐고, 장기 성능 기준은 later-gated 항목이다.

완료 처리 근거:

1. review-gate short summary: summary contract and fixture output exists.
2. untracked artifact review mode: context guard and verdict blocking exist.
3. diff scope classifier: context summary is consumed by `review-gate.sh`.
4. TODO/report normalizer: `scripts/todo-report.py --fail-on-active` is wired
   into verification.
5. process cleanup guard: deterministic timeout/reap fixture exists.

외부 도구 설치 TODO는 더 이상 남기지 않는다.

1. `shellcheck`: 설치 완료, warning-severity required gate로 승격
2. `hyperfine`: 설치 완료, optional benchmark capture 전용으로 유지
3. `ruff`: Python 코드와 정책이 커질 때만 reference-only로 재검토
4. `shfmt`, `markdownlint`, `semgrep`, `actionlint`, `yq`, `cloc/tokei`: 제외

## Stop Boundary

이 문서는 분석 산출물이다. reviewer 정책 변경, browser/runtime 도입, 추가
외부 패키지 설치는 별도 계획과 승인 없이 진행하지 않는다.
