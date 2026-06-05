# AI_AUTO 경량화 실행계획 (2026-06-05)

근거 감사: `plans/AI_AUTO_OVERENGINEERING_AUDIT_2026-06-05.md` (Gemini approve,
Codex 사실교정 반영). 본 문서는 그 권고를 마이크로 유닛 실행계획으로 분해한다.

## 랄프 완료 조건 (사용자 지정)
**전체 계획(Phase 1~4)을 클리어해 control plane 경량화를 달성**하면 완료.
각 유닛: 구현 → `./scripts/verify.sh` 그린 → review-gate 만장일치(외부 리뷰어
2인 proceed) → 커밋 → 백로그 갱신. 큐/도구 중복 주의(아래 함정 참고).

## 핵심 재정의
죽은 무게는 **Python 계약 38개**(런타임 caller 0, 테스트 전용). Bash audit 9개는
리뷰 컨텍스트에 *방출은 됨*. 역설: 외부 LLM 리뷰 파이프라인은 실효 있음(감사
문서 오류를 실제로 잡음). 따라서 "전부 제거"가 아니라 **강제/자문/제거 분류 후
정직화 + 무게의 diff-비례화**가 목표.

## Phase 1 — 계약 레이어 정체성
- **U1.1 (읽기전용)** 38계약을 enforce/advisory/dead 분류표 작성. 기준: 위반이
  실재·탐지가능·고비용 + 자연스러운 런타임 훅이면 enforce(≤3 권장:
  `review_gate_short_summary`, `template_parity_boundary`,
  `completion_acceptance_scope` 후보). 리뷰컨텍스트에 방출되면 advisory, 아니면
  dead. 코드변경 0.
- **U1.2** 백로그 상태값 `advisory_contract` 신설. 범위: 백로그 "Status values"
  범례 + `scripts/todo-report.py` 상태집합 + `tests/test_todo_report.py`. 경계:
  `--fail-on-active` 여전히 통과(비활성 취급).
- **U1.3** advisory 분류 계약들의 백로그 행 `complete_contract→advisory_contract`
  재라벨 + `scripts/self_demo_contracts.py` 모듈 docstring에 enforced/advisory
  그룹 명시. 행동변화 0. (U6 상태 인플레이션 해소)
- **U1.4 (고리스크·결정)** enforce 후보를 하나씩 게이트에 fail-closed 배선(각
  1유닛). 부트스트랩 검증(변경 후 게이트 재실행) 필수. 실효 없으면 생략 가능.
- **U1.5 (선택)** dead 계약+테스트 삭제 또는 저가치 audit 섹션 제거(템플릿 동기화
  동반).

### U1.1 분류표

기준:

- `enforce_candidate`: 위반 비용이 높고 기존 gate/verify/review 경로에 자연스럽게
  연결할 수 있다. 아직 강제 배선 전이면 후보로만 둔다.
- `advisory_contract`: 리뷰 컨텍스트 또는 별도 CLI/리포트 표면으로 방출되어
  운영자가 볼 수 있지만, 현재 fail-closed gate는 아니다.
- `dead_contract`: 테스트 외 런타임 caller가 없고 리뷰 컨텍스트에도 방출되지 않는다.
  당장 삭제하지 않고 U1.5 후보로 보류한다.

| Contract | Classification | Runtime evidence |
| --- | --- | --- |
| `review_gate_short_summary` | `enforce_candidate` | `summarize-ai-reviews.sh` already owns verdict summary semantics; Python contract is test-only. |
| `template_parity_boundary` | `enforce_candidate` | `verify.sh` and template parity checks already enforce parts of this boundary; Python contract is test-only. |
| `completion_acceptance_scope` | `enforce_candidate` | AGENTS/Ralph discipline carries the rule; no direct runtime caller yet. |
| `diff_scope_classification` | `enforce_candidate` | `collect-review-context.sh` and `review-gate.sh` already emit/consume diff scope; Python contract is test-only. |
| `completion_pack_routing_policy` | `advisory_contract` | `Completion Pack Routing Audit` is report-only in review context. |
| `product_challenge_policy` | `advisory_contract` | `Product Challenge Audit` is report-only in review context. |
| `visual_artifact_policy` | `advisory_contract` | `Visual Artifact Audit` is report-only in review context. |
| `planning_visual_gate_policy` | `advisory_contract` | `Planning Visual Gate Audit` is report-only in review context. |
| `spec_code_alignment_policy` | `advisory_contract` | `Spec Code Alignment Audit` is report-only in review context. |
| `standard_flow_preservation_policy` | `advisory_contract` | `Standard Flow Preservation Audit` is report-only in review context. |
| `browser_qa_evidence_policy` | `advisory_contract` | `Browser QA Evidence Audit` is report-only in review context. |
| `micro_work` contract surface | `advisory_contract` | `MicroWork Audit` is report-only; implementation lives in `scripts/micro_work_contracts.py`. |
| `self_demo_record` | `dead_contract` | Test-only schema; no runtime caller or review-context section. |
| `benchmark_evidence` | `dead_contract` | Test-only benchmark policy; no runtime caller. |
| `untracked_artifact_review_guard` | `dead_contract` | Shell review-context guard is real; Python mirror is test-only. |
| `todo_report_reconciliation` | `dead_contract` | `scripts/todo-report.py --fail-on-active` is real; Python mirror is test-only. |
| `benchmark_wrapper_plan` | `dead_contract` | Test-only planning shape. |
| `benchmark_capture_record` | `dead_contract` | `benchmark-command.py` has runtime behavior; Python mirror is test-only. |
| `process_cleanup_evidence` | `dead_contract` | Process cleanup fixture is test-only. |
| `reviewer_eligibility` | `dead_contract` | Review summary shell owns actual reviewer parsing; Python mirror is test-only. |
| `completion_authority` | `dead_contract` | Test-only completion authority shape. |
| `startup_preflight_boundary` | `dead_contract` | Test-only policy shape. |
| `vault_write_boundary` | `dead_contract` | Test-only policy shape. |
| `review_context_boundary` | `dead_contract` | Review context tooling has its own shell checks; Python mirror is test-only. |
| `registry_scan_boundary` | `dead_contract` | Test-only policy shape. |
| `status_notice_boundary` | `dead_contract` | Test-only display-only policy. |
| `guidance_minimality_boundary` | `dead_contract` | Test-only guidance policy. |
| `artifact_sync` | `dead_contract` | Test-only finding metadata shape. |
| `artifact_delta_check` | `dead_contract` | Test-only delta shape. |
| `persona_lens_policy` | `dead_contract` | Persona gate shell path is real; Python mirror is test-only. |
| `obsidian_autopush_policy` | `dead_contract` | Obsidian scripts have real behavior; Python mirror is test-only. |
| `shareable_autopromotion_policy` | `dead_contract` | Obsidian scripts have real behavior; Python mirror is test-only. |
| `update_visibility_policy` | `dead_contract` | Test-only display policy. |
| `phase_scope_guard_policy` | `dead_contract` | Phase scope shell guard is real; Python mirror is test-only. |
| `review_revision_loop_policy` | `dead_contract` | Review revision shell/test-summary path is real; Python mirror is test-only. |
| `tool_adoption_status_policy` | `dead_contract` | Test-only adoption status policy. |
| `reviewer_first_pass_permission_policy` | `dead_contract` | Runtime diagnostics are in review runner; Python mirror is test-only. |
| `guidance_stage2_consolidation_policy` | `dead_contract` | Test-only consolidation policy. |
| `domain_pack_retrospective_policy` | `dead_contract` | Test-only retrospective policy. |

## Phase 2 — verify 분리 (고리스크, self-modification)
- **U2.1 (읽기전용)** verify.sh 6057줄 섹션 매핑(제품검증 ~13줄 vs 자기검증
  60블록). 중첩 review-gate/run-ai-reviews를 띄우는 self-test 식별.
- **U2.2 (저위험, 먼저)** review-gate 내부 verify 재실행 시 중첩-리뷰 self-test만
  건너뛰는 env 가드(예: `OMX_IN_GATE=1`). 범위: review-gate.sh + verify.sh. 효과:
  이번에 3회 발생한 게이트 truncation 직접 해소. 마커 테스트
  (`test_verify_script_keeps_structural_audit_markers`) 유지.
- **U2.3 (고리스크)** 자기검증을 `scripts/verify-machinery.sh`로 추출, verify.sh가
  호출(출력 동등). 템플릿 동기화 + 마커 테스트 갱신 + 부트스트랩 검증.
- **U2.4** review-gate는 제품검증(경량)만, 머신러리는 pre-push/CI. 의존: U2.3.

## Phase 3 — 리뷰 무게 diff-비례화 (비용 최대 절감)
- **U3.1** 기존 `diff_scope_classification` 계약을 review-gate 실제 caller로 배선
  (U1 enforce 사례 1건 자연 확보).
- **U3.2** doc/backlog-only diff면 외부 LLM 리뷰 생략, verify는 유지, "review
  skipped: docs-only" 기록. 경계: 코드 섞이면 절대 생략(fail-safe=불확실시 전체).
  범위: review-gate.sh + run-ai-reviews 게이팅 + 테스트(doc-only→skip, code→full).
- **U3.3** `REVIEW_UNTRACKED_ALLOWLIST` 기본값을 변경 스코프에서 자동 도출(수동
  지정 마찰 제거). 무관 untracked는 여전히 보고.

## Phase 4 — 단일 writer / worktree 격리 (U5b churn 차단)
- **U4.1** 컨벤션 문서화(AGENTS.md/WORKFLOW): 한 트리=한 에이전트 또는 에이전트별
  git worktree, 다운스트림 세션은 자기 프로젝트에만 쓰기. 루트/템플릿 동기화.
- **U4.2 (저위험)** collect-review-context의 `REPO_STATUS_BEFORE_CONTEXT`로 리뷰 중
  트리 변동/신규 untracked 출현 감지→경고(report-only) + 테스트.
- **U4.3 (선택)** review-gate 시작 시 타 에이전트 활동 감지 경고.

## 권장 착수 순서
빠른 무위험 승리 먼저: U1.2+U1.3, U2.2, U3.1+U3.2, U4.1+U4.2.
결정/고리스크는 데이터와 함께: U1.1→U1.4, U2.3.
Phase 3를 먼저 하면 이후 유닛 게이트 비용이 줄어든다(고려).

## 실행 함정 (이전 세션에서 실측)
- **principal**: codex로 돌리면 active principal=codex, 리뷰어 회전=claude+gemini.
  claude 세션처럼 launcher-evidence 트릭 불필요. `AI_AUTO_PRINCIPAL` 명시 export는
  verify의 pytest로 누수되어 codex-default 테스트를 깨뜨릴 수 있으니 주의.
- **동시 에이전트 churn**: 다른 세션이 `plans/ODOO_SH_KB_*`, `knowledge/`를 이
  트리에 계속 생성. `git add -A` 금지(명시 staging), 리뷰는
  `REVIEW_UNTRACKED_ALLOWLIST="scripts/ templates/ tests/ docs/ plans/<해당파일>"`로
  스코프. 본인 신규 파일은 stage해서 컨텍스트에 포함.
- **게이트 truncation**: 동시 경합 시 verify-in-gate가 멈출 수 있음 → 분해
  (verify 단독 그린 + `run-ai-reviews.sh` + `summarize-ai-reviews.sh` 직접 실행).
- **템플릿 동기화**: `templates/automation-base/` 변경은 `AI_AUTO_TEMPLATE_VERSION`
  범프 + `PATCH_NOTES.md` 최상단 항목 + 루트↔템플릿 byte-identical 미러(verify가
  parity 강제). U1.2 템플릿 상태 동기화 후 현재 버전은 `2026.06.05.2`.
- **resolve 도구 이미 존재**: `scripts/resolve-feedback.sh` + `tools/feedback-resolve`
  (flock 동시성 안전). 큐 해소는 손편집 말고 이 도구 사용. ST-P1-43은 이미 완료됨
  (재제작 금지).
- **백로그 표 무결성**: 행 사이 빈 줄 금지(파서가 표를 분할함). `todo-report.py
  --fail-on-active`로 검증.

## 현재 상태 (U1.1~U1.3 진행 후)
- 감사 문서와 본 실행계획 문서는 같은 유닛 커밋 후보에 포함한다.
- U1.1 분류표 작성 완료.
- U1.2 `advisory_contract` 상태값 신설 완료(root/template `todo-report.py`,
  테스트, 템플릿 버전/패치노트 포함).
- U1.3 advisory 백로그 재라벨 및 `self_demo_contracts.py` 모듈 docstring
  정직화 완료.
- 다음 착수 후보: U2.2 또는 U3.1+U3.2.
