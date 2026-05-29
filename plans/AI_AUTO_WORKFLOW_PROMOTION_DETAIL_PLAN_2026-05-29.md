# AI_AUTO Workflow Promotion Detail Plan

## 목적

이 문서는 `ST-P1-13`부터 `ST-P1-19`까지의 workflow promotion TODO를
실행 가능한 상세 플랜으로 고도화한 기록이다. 2026-05-29 non-active
promotion Ralph pass에서 7개 항목은 `complete_contract`로 승격되었다.
승격 근거는 `scripts/self_demo_contracts.py`의 workflow policy contracts와
`tests/test_self_demo_contracts.py`의 대응 테스트다. Browser/CDP, push,
install, deployment, runtime lane 추가 같은 부작용 실행은 여전히 별도
사용자 승인과 이 문서의 권한 경계를 따른다.

## 공통 운영 원칙

1. 문서 소유권을 분리한다. Markdown plan은 workflow status, approval,
   gates, acceptance criteria, execution boundary를 소유한다. Mermaid는
   선언된 local diagram slice를 소유할 수 있고, Structurizr는 선언된
   long-lived architecture model slice를 소유할 수 있다. Excalidraw는
   explanatory artifact이며, human-reviewed paired `*-spec.md`로 승격된
   경우에만 implementation-facing input이 된다.
2. 새 gate는 기본 warning-first 또는 report-only로 시작한다. 반복 실패가
   확인되기 전에는 fail-closed로 승격하지 않는다.
3. credential, browser session, deployment, Obsidian push, package install은
   별도 승인 전까지 금지한다.
4. 각 micro unit은 작게 닫고, targeted check 후 다음 unit으로 넘어간다.
5. 소그룹 이상 작업은 AI council review를 통과해야 한다. Claude가 사용량
   한도로 비활성화되면 Gemini plus Codex/GPT fallback은
   `proceed_degraded` 근거로만 인정한다. 이 경우 `unanimous`라고 부르지
   않고, degraded trust와 missing reviewer를 보고한다.

## AI Council And Unanimity Rule

### Council Roles

| Role | Responsibility | Rejects When |
| --- | --- | --- |
| Planner | sequencing, dependency order, micro sizing | 작업 순서가 뒤집혔거나 active work를 숨김 |
| Architect | source-of-truth, authority boundaries, module relationships | 기존 authority를 우회하거나 주변 모듈 영향이 빠짐 |
| Critic | acceptance criteria, rollback, verification, ambiguity | 검증 불가하거나 rollback/stop condition이 없음 |

### Unanimity Definition

Pass requires all available reviewers to return one of:

- `approve`
- `approve_with_notes` where notes are applied or explicitly deferred

The plan is not unanimous if any reviewer returns:

- `request_changes`
- `blocked`
- unresolved `review_manually`

When Claude is unavailable due quota or usage limit, Gemini approval plus a
Codex/GPT architect or critic fallback may allow `proceed_degraded`, but it
must not be called unanimity. The final report must state `unanimous: false`,
the missing Claude reviewer, and the degraded trust level.

## Review Loop

1. Draft or revise one coherent group.
2. Run static checks:
   - `python3 scripts/todo-report.py --fail-on-active`
   - targeted `rg` checks for all seven IDs
3. Run planner/architect/critic review.
4. Apply accepted findings.
5. Repeat until every required reviewer returns `approve` or resolved/deferred
   `approve_with_notes`, with no `request_changes`, no `blocked`, and no
   unresolved `review_manually`; update the review ledger each iteration.
6. Run `./scripts/verify.sh`.
7. Run `./scripts/review-gate.sh` before any commit candidate.

## Size Groups

| Group | Items | Reason | Review Requirement |
| --- | --- | --- | --- |
| Small | `ST-P1-17`, `ST-P1-18` | mostly reporting and workflow state; low side-effect risk | targeted self-check plus AI council if grouped |
| Medium | `ST-P1-14`, `ST-P1-16`, `ST-P1-19` | touches planning policy or routing behavior | AI council required |
| Large | `ST-P1-13`, `ST-P1-15` | touches visual planning, UI/browser evidence, or credential-adjacent surfaces | AI council plus full verify/review-gate |

## ST-P1-13: Planning Visualization Workflow Promotion

### Goal

Turn the existing Mermaid, Structurizr, Excalidraw, exported diagram, and
paired `*-spec.md` guidance into a regular, testable planning workflow without
installing new diagram tooling first.

### Surrounding Modules And Tools

| Surface | Relationship | Risk |
| --- | --- | --- |
| `docs/PLANNING_VISUALIZATION_GUIDE.md` | current guidance source | may become stale if helper behavior diverges |
| `docs/plans/_templates/excalidraw-spec-template.md` | paired spec template | can be treated as implementation contract before human review |
| `docs/plans/_templates/high-risk-diagrams.md` | diagram starter | can duplicate Structurizr source of truth |
| `plans/AI_AUTO_NATIVE_WORKBENCH.md` | future UI surface | may imply a runtime app before Markdown workflow is proven |
| `scripts/collect-review-context.sh` | review context source | may need to include diagram/spec artifacts |

### Micro Units

| Unit | Size | Work | Touchpoints | Validation | Rollback |
| --- | --- | --- | --- | --- | --- |
| 13.1 | small | Define `visual_artifact_manifest` fields: plan, mermaid, structurizr, excalidraw, export, paired spec, owner, status. | docs plan only | schema example has every field | remove schema section |
| 13.2 | small | Define source-of-truth precedence and duplication rule. | planning guide, detail plan | Mermaid/Structurizr duplicate case has expected owner | revert text |
| 13.3 | small | Define stale detection rules for plan/spec/diagram mismatch. | planning guide | examples: stale spec, stale export, stale drawing | remove stale checks |
| 13.4 | medium | Plan a read-only checker that reports missing paired spec, unreviewed spec, stale export, ambiguous source. | future script contract | dry-run fixtures listed; no write behavior | keep manual checklist |
| 13.5a | small | Define manual/context rule for material visual artifacts. | detail plan, planning guide | untracked `.excalidraw` or spec requires included content or manual review record | defer to existing untracked artifact guard |
| 13.5b | medium | Plan later script integration for visual artifact context inclusion. | future collect-review-context/review-gate work | fixtures listed before script edits; no current script change | keep manual/context rule |
| 13.6 | medium | Add execution handoff rule: implementation cannot use Excalidraw-only requirements. | WORKFLOW/planning guide | plan has Markdown contract or blocked state | doc-only revert |
| 13.7 | large | Optional later implementation of `ai-plan-visual-check --summary-json`. | new helper, tests | fixtures pass, no external tool required | delete helper and keep docs |

### Acceptance Criteria

- Excalidraw is explanatory unless explicitly promoted through paired spec.
- Structurizr owns long-lived architecture only when the plan declares it.
- No source-of-truth is duplicated silently.
- Stale visual artifacts are reported, not silently rewritten.

### Representative Fixtures

| Fixture | Input Shape | Expected |
| --- | --- | --- |
| `visual_excalidraw_no_spec` | `.excalidraw` file referenced as requirement with no paired spec | `visual_warning:explanatory_only` |
| `visual_spec_unreviewed` | Excalidraw plus paired `*-spec.md` exists but is not human-reviewed/promoted | `visual_warning:unreviewed_spec` |
| `visual_spec_human_reviewed` | Excalidraw plus paired `*-spec.md` marked human-reviewed | `visual_ok:implementation_facing_spec` |
| `visual_stale_export` | source diagram newer than exported image | `visual_warning:stale_export` |
| `visual_mermaid_structurizr_overlap` | same architecture decision appears in Mermaid and Structurizr without declared owner | `visual_warning:ambiguous_source_of_truth` |

## ST-P1-14: Product Challenge Planning Gate

### Goal

Add a lightweight product challenge lens before broad or strategic plans, while
suppressing routine small tasks.

### Surrounding Modules And Tools

| Surface | Relationship | Risk |
| --- | --- | --- |
| `docs/AUTOMATION_OPERATING_POLICY.md` | no-code-first and interview policy | broad policy bloat |
| `docs/INTERVIEW_PLAN_LAYER.md` | interview intensity rules | duplicate questioning |
| `plans/GSTACK_BENCHMARK*.md` | source concept | importing GStack runtime or persona sprawl |

### Micro Units

| Unit | Size | Work | Touchpoints | Validation | Rollback |
| --- | --- | --- | --- | --- | --- |
| 14.1 | small | Define triggers: broad plan, product/strategy, unclear value, large UI/workflow. | plan docs | trigger examples classify correctly | remove trigger list |
| 14.2 | small | Define suppressions: typo, narrow bugfix, user already supplied approved plan. | plan docs | suppression examples classify correctly | remove suppressions |
| 14.3 | small | Define product challenge questions: user, job, non-goal, alternative, smallest useful outcome. | interview docs | max 3 questions per light path | revert checklist |
| 14.4 | medium | Plan classifier contract for challenge-required vs challenge-skipped. | future contract tests | fixtures for broad/narrow requests | keep manual rule |
| 14.5 | medium | Integrate with `ralplan`/plan docs without forcing every Ralph task through it. | AGENTS/WORKFLOW only if later approved | routine TODO clearance bypasses challenge | doc rollback |
| 14.6a | small | Define doc-level review criterion: plan must state why challenge was run or skipped. | detail plan only | fixture table below covers run/skipped/missing reason | remove criterion |
| 14.6b | medium | Later prompt/gate integration for the criterion. | future review-gate prompt work | separately approved fixture before prompt edit | keep doc-level criterion |

### Acceptance Criteria

- Broad plans get value/alternative pressure before execution.
- Small reversible work is not slowed.
- The lens never replaces user approval or normal verify/review gates.

### Representative Fixtures

| Fixture | Input Shape | Expected |
| --- | --- | --- |
| `product_broad_strategy` | "새 Workbench 전략을 세워줘"; touches UI/workflow/operations | `challenge_required` |
| `product_small_fix` | "오타 하나 고쳐"; single doc typo | `challenge_skipped:routine_small` |
| `product_existing_approved_plan` | approved PRD/test-spec path supplied | `challenge_skipped:approved_plan_exists` |
| `product_missing_reason` | broad plan with no run/skipped reason | `review_flag:missing_product_challenge_reason` |

## ST-P1-15: UI/Browser QA Evidence Workflow

### Goal

Create a report-only QA evidence workflow for UI/browser-adjacent work before
any fix-loop automation or credential-sensitive browser access is promoted.

### Surrounding Modules And Tools

| Surface | Relationship | Risk |
| --- | --- | --- |
| `docs/UI_COMPLETION.md` | UI completion pack | duplicate visual-ralph requirements |
| `docs/CHROME_CDP_ACCESS.md` | browser access safety | credential/session leakage |
| `plans/AI_AUTO_REFLECTION_LOOP_V1.md` | visual alignment layer | sidecar authority leakage |
| `scripts/review-gate.sh` | final review gate | QA report mistaken for approval |

### Micro Units

| Unit | Size | Work | Touchpoints | Validation | Rollback |
| --- | --- | --- | --- | --- | --- |
| 15.1 | small | Define QA report schema: target, environment, steps, screenshots, console/network notes, verdict. | docs plan | schema has no write/fix action | remove schema |
| 15.2 | small | Define read-only vs fix-loop boundary. | UI/CDP docs | report-only cannot apply patch | revert boundary |
| 15.3 | medium | Define CDP credential boundary and approval fields. | CHROME_CDP_ACCESS | loopback, user-launched, no cookies export | manual-only fallback |
| 15.4 | medium | Plan screenshot/evidence storage and redaction rules. | plans/artifacts, .omx | sensitive artifacts remain ignored or redacted | keep manual evidence |
| 15.5 | medium | Define visual review interaction with `visual-ralph`. | UI completion, visual workflow | visual verdict is evidence, not completion authority | doc rollback |
| 15.6 | large | Optional later report helper for browser QA without auto-fix. | future helper/tests | fixture report generation, no browser required | delete helper |
| 15.7 | large | Later fix-loop only after repeated report-only use proves low noise. | future plan | requires explicit user approval | do not implement |

### Acceptance Criteria

- Browser QA can produce useful evidence without taking action.
- Credential/session access is never implicit.
- QA report does not replace `verify.sh` or `review-gate.sh`.

### Representative Fixtures

| Fixture | Input Shape | Expected |
| --- | --- | --- |
| `qa_report_only` | QA evidence request with target, steps, screenshot note, no fix request | `qa_ok:report_only` |
| `qa_attempts_patch` | QA report includes proposed automatic patch or browser fix-loop action | `qa_block:auto_fix_not_allowed` |
| `qa_cdp_missing_approval` | browser/CDP access requested without loopback/user-launched/approval fields | `qa_block:credential_boundary` |
| `qa_cdp_safe_report` | loopback-bound approved CDP report, user-launched or isolated profile, no cookie/token export, no fix action | `qa_ok:cdp_report_only` |
| `qa_redaction_required` | screenshot or console evidence includes token, cookie, account, or private URL | `qa_warning:redaction_required` |
| `qa_visual_verdict_only` | visual verdict exists but verify/review-gate evidence is missing | `qa_warning:visual_not_completion_authority` |

## ST-P1-16: Phase/Scope Guard Workflow

### Goal

Detect phase leakage and missing deferral records in multi-phase plans without
blocking ordinary small edits.

### Surrounding Modules And Tools

| Surface | Relationship | Risk |
| --- | --- | --- |
| `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md` | phase-scope risk source | overfitting to one review |
| `docs/AUTOMATION_OPERATING_POLICY.md` | artifact sync and scope rules | policy duplication |
| `scripts/todo-report.py` | active/non-active separation | false active TODO creation |

### Micro Units

| Unit | Size | Work | Touchpoints | Validation | Rollback |
| --- | --- | --- | --- | --- | --- |
| 16.1 | small | Define plan fields: phase, allowed_files, deferred_files, blocked_files. | plan template | sample phase record parses conceptually | remove fields |
| 16.2 | small | Define leakage classes: out-of-phase edit, missing deferral, unowned artifact. | detail plan | examples classified | remove classes |
| 16.3 | medium | Plan read-only diff classifier against phase fields. | future contract | fixture diff with allowed/deferred files | manual review only |
| 16.4 | medium | Define false-positive escape: explicit `deferred_with_reason` or plan update. | policy/docs | escape requires reason | revert text |
| 16.5a | small | Link to artifact sync rule: final report must land material findings or defer. | detail plan and policy docs only | material finding has landed artifact or `deferred_with_reason` | no-op |
| 16.5b | medium | Later enforcement contract update, only if repeated leakage appears. | future self-demo contract work | separately approved test before contract edit | keep docs-only rule |
| 16.6 | medium | Later gate only for multi-phase high-risk plans. | review-gate later | small docs edit skipped | keep warning-only |

### Acceptance Criteria

- Guard is warning-first.
- Every out-of-phase artifact is either blocked, plan-updated, or deferred with
  reason.
- Routine small changes are not blocked.

### Representative Fixtures

| Fixture | Input Shape | Expected |
| --- | --- | --- |
| `phase_allowed_file` | current phase allows `docs/WORKFLOW.md`; diff touches only that file | `scope_ok` |
| `phase_out_of_phase_file` | phase allows docs; diff touches `scripts/review-gate.sh` without plan update | `scope_warning:out_of_phase_edit` |
| `phase_deferred_with_reason` | out-of-phase artifact has `deferred_with_reason` | `scope_ok:deferred` |
| `phase_missing_deferral` | material finding omitted from artifact and no deferral | `scope_warning:missing_deferral_record` |

## ST-P1-17: Review Finding Revision Loop

### Goal

Plan a bounded workflow that turns accepted reviewer findings into revision
tasks, reruns verification, and performs a second review pass when repeated
review-fix-review friction appears.

### Surrounding Modules And Tools

| Surface | Relationship | Risk |
| --- | --- | --- |
| `docs/MULTI_AI_COLLABORATION.md` | phase 3 deferred source | automatic patch authority |
| `scripts/summarize-ai-reviews.sh` | verdict source | parsing request_changes incorrectly |
| `scripts/review-gate.sh` | review execution | recursive review loops |

### Micro Units

| Unit | Size | Work | Touchpoints | Validation | Rollback |
| --- | --- | --- | --- | --- | --- |
| 17.1 | small | Define finding states: proposed, accepted, rejected, fixed, deferred. | docs plan | state transition table complete | remove table |
| 17.2 | small | Define accepted-finding task schema. | docs plan | schema has source reviewer and file refs | revert schema |
| 17.3 | medium | Plan parser boundary: only structured findings become draft tasks. | summarize docs/tests later | free text cannot auto-patch | manual acceptance |
| 17.4 | medium | Define cycle limit and stop condition: max 2 revision cycles, then stop for manual decision if verification repeatedly fails, reviewer findings contradict, or reviewer output is unclear. | review workflow docs | max cycles and stop reasons documented | remove automation |
| 17.5 | medium | Plan second-pass review trigger after fixes. | review-gate later | second pass requires changed diff | keep manual rerun |

### Acceptance Criteria

- Reviewer findings remain advisory until accepted.
- No finding directly applies code.
- Revision cycles are bounded to 2 automated revision cycles and always re-run
  verification.

### Representative Fixtures

| Fixture | Input Shape | Expected |
| --- | --- | --- |
| `finding_structured_accepted` | structured reviewer finding marked accepted with file reference | `revision_task_created` |
| `finding_rejected_or_free_text` | rejected finding or unstructured free text only | `revision_task_skipped` |
| `finding_reviewer_disagreement` | reviewers disagree on same required change | `revision_manual_review` |
| `finding_repeated_verify_failure` | accepted finding fix still fails verification after retry | `revision_stop:verification_failure` |
| `finding_unclear_reviewer_output` | reviewer output cannot be mapped to approve/request_changes/block/manual states | `revision_stop:unclear_review` |
| `finding_second_pass_no_diff` | second-pass review requested but no changed diff after fixes | `revision_block:no_changed_diff` |
| `finding_cycle_exhausted` | third automatic revision cycle would start after two prior cycles | `revision_stop:cycle_limit` |

## ST-P1-18: Tool Availability And Adoption Status Workflow

### Goal

Create a read-only status surface that distinguishes required, optional,
reference-only, rejected, missing, and installed tools without installing or
promoting anything.

### Surrounding Modules And Tools

| Surface | Relationship | Risk |
| --- | --- | --- |
| `scripts/automation-doctor.sh` | tool availability | status may imply installation approval |
| `scripts/bootstrap-ai-lab.sh` | setup check | duplicate reporting |
| `docs/GLOBAL_TOOLS.md` | user-facing helper docs | drift with actual helper list |
| tool review plans | adoption decisions | reference-only rediscovery |

### Micro Units

| Unit | Size | Work | Touchpoints | Validation | Rollback |
| --- | --- | --- | --- | --- | --- |
| 18.1 | small | Define adoption states and meanings. | detail plan | all existing decisions map to one state | remove table |
| 18.2 | small | Define read-only summary fields: tool, installed, adoption_state, source, next_gate. | docs plan | no install field | revert schema |
| 18.3 | medium | Plan source merger from doctor/bootstrap/docs/tool review. | future helper | duplicate tool resolves deterministically | keep manual docs |
| 18.4 | medium | Define drift warning when installed state conflicts with adoption state. | future tests | installed reference_only is warning, not failure | warning-only |
| 18.5 | medium | Add review rule: status report cannot upgrade gate. | review docs later | no silent required_gate | no-op |

### Acceptance Criteria

- Status surface is read-only.
- Missing optional tools do not fail.
- Required gate promotion needs a separate approved plan.

### Representative Fixtures

| Fixture | Input Shape | Expected |
| --- | --- | --- |
| `tool_required_installed` | `shellcheck` installed and `required_gate` | `status_ok` |
| `tool_optional_missing` | optional tool missing | `status_warning_only` |
| `tool_reference_installed` | `ruff` installed but `reference_only` | `status_info:not_required` |
| `tool_required_missing` | required gate missing | `status_attention:required_missing` |
| `tool_silent_promotion` | optional tool appears as required with no plan source | `status_block:silent_gate_promotion` |

## ST-P1-19: Completion-Pack Trigger And Lens Routing Audit

### Goal

Audit whether security, deployment, observability, performance, data, and UI
completion packs have clear triggers and review lenses before any new runtime
lane is added. Documentation-generation remains a GStack benchmark lens and is
tracked separately as reference input, not as a current `docs/*_COMPLETION.md`
pack.

### Surrounding Modules And Tools

| Surface | Relationship | Risk |
| --- | --- | --- |
| `docs/*_COMPLETION.md` | completion-pack guidance | uneven trigger behavior |
| `docs/WORKFLOW.md` | base workflow | guidance bloat |
| `plans/GSTACK_BENCHMARK_RALPH_DEEP_DIVE.md` | named GStack lenses | importing duplicate commands |
| `scripts/collect-review-context.sh` | context packing | wrong review intensity |

### Micro Units

| Unit | Size | Work | Touchpoints | Validation | Rollback |
| --- | --- | --- | --- | --- | --- |
| 19.1 | small | Inventory existing completion packs and current trigger wording. | docs only | table includes UI, performance, data, observability, deployment, security | remove inventory |
| 19.2 | small | Define trigger classes: explicit user request, file-scope trigger, risk trigger, never-auto. | detail plan | examples classify correctly | remove classes |
| 19.3 | medium | Map each pack to review lens and required evidence. | WORKFLOW/docs later | no missing pack | doc rollback |
| 19.4a | small | Define manual intensity alignment rules. | detail plan only | fixture table below covers security/deploy/data scopes | keep manual review |
| 19.4b | medium | Later script integration for collect-review-context intensity alignment. | future collect-review-context work | separately approved fixture before script edit | keep manual rule |
| 19.5 | medium | Define anti-bloat rule: no new runtime lane until repeated need. | policy docs | prevents duplicate GStack commands | remove rule |
| 19.6 | medium | Plan summary report for pack coverage gaps. | future helper optional | report-only output | delete helper |

### Acceptance Criteria

- Completion packs have clear trigger ownership.
- Review lens routing is auditable.
- No new runtime lane is added from the audit alone.

### Representative Fixtures

| Fixture | Input Shape | Expected |
| --- | --- | --- |
| `pack_security_explicit` | user asks for security review | `trigger:security_completion` |
| `pack_deploy_files` | diff touches deployment guide or deployment script | `trigger:deployment_completion` |
| `pack_data_risk` | task touches persisted data or migration | `trigger:data_completion` |
| `pack_ui_scope` | UI implementation or visual QA request | `trigger:ui_completion` |
| `pack_docs_generation_lens` | docs generation idea from GStack only | `reference_lens:not_completion_pack` |
| `pack_no_missing_current` | inventory over current repo docs | `packs_present:ui,performance,data,observability,deployment,security` |

## Cross-Item Dependency Order

1. `ST-P1-18` first: tool status vocabulary reduces later ambiguity.
2. `ST-P1-19` second: completion-pack routing informs UI/browser/security
   triggers.
3. `ST-P1-14` third: product challenge only after routing vocabulary is clear.
4. `ST-P1-16` fourth: phase guard uses plan fields from earlier planning rules.
5. `ST-P1-13` fifth: visualization workflow depends on plan/source-of-truth
   conventions.
6. `ST-P1-15` sixth: UI/browser QA depends on visual and completion-pack rules.
7. `ST-P1-17` last: revision loop depends on review-gate semantics and should
   not preempt normal review authority.

## Common Verification Plan

For planning-only work:

- `python3 scripts/todo-report.py --fail-on-active`
- `rg -n "ST-P1-13|ST-P1-14|ST-P1-15|ST-P1-16|ST-P1-17|ST-P1-18|ST-P1-19" plans/AI_AUTO_WORKFLOW_PROMOTION_DETAIL_PLAN_2026-05-29.md`
- `./scripts/verify.sh`
- `./scripts/review-gate.sh`

For future implementation work:

- targeted fixtures per item
- `./scripts/verify.sh` after every coherent medium group
- `./scripts/review-gate.sh` before commit candidate or any required-gate
  promotion

## Rollback Strategy

- Plan-only changes can be reverted by deleting this detail plan and removing
  references from the backlog/audit.
- Future helper implementation must be separately reversible: helper file
  deletion, tests deletion, docs rollback, no migration state.
- Any fail-closed behavior must have an explicit feature flag or warning-only
  fallback before promotion.

## AI Council Review Ledger

| Iteration | Reviewer | Verdict | Findings | Resolution |
| --- | --- | --- | --- | --- |
| 1 | Planner | `approve_with_notes` | Split policy definition from future script/gate integration in 13.5, 14.6, 16.5, 19.4. | Applied by splitting units into `a` doc/manual units and `b` later integration units. |
| 1 | Architect | `request_changes` | Clarify backlog/audit/detail ownership chain; narrow Markdown source-of-truth rule. | Applied in common principles and backlog/audit references. |
| 1 | Critic | `request_changes` | Do not call degraded fallback unanimity; strengthen review loop stop condition; remove ambiguous documentation pack wording; add fixture tables. | Applied in unanimity rule, review loop, ST-P1-19 wording, and fixture tables. |
| 2 | Planner | `approve_with_notes` | No required changes; previous Planner notes resolved, dependency order and micro sizing acceptable. | No change required. |
| 2 | Architect | `approve_with_notes` | No required changes; ownership chain and authority boundaries acceptable. Minor future note: align ST-P1-19 UI source lists to reduce rediscovery ambiguity. | Tracked for non-blocking cleanup. |
| 2 | Critic | `request_changes` | Add fixture tables for `ST-P1-13`, `ST-P1-15`, `ST-P1-17`; make `ST-P1-17` cycle limit explicit. | Applied with representative fixture tables and max 2 revision-cycle stop rule. |
| 3 | Planner | `request_changes` | Align PRD dependency criterion with detail-plan format; align ST-P1-19 gap-audit wording so documentation-generation is not treated as a completion pack. | Applied in PRD success criteria and gap-audit ST-P1-19 wording. |
| 3 | Architect | `approve_with_notes` | No required changes; source-of-truth ownership, authority boundaries, fixture coverage, and ST-P1-19 alignment acceptable. | No change required. |
| 3 | Critic | `request_changes` | Add fixtures for unreviewed Excalidraw spec, positive CDP-safe report-only path, repeated verification failure, and unclear reviewer output. | Applied in ST-P1-13, ST-P1-15, and ST-P1-17 representative fixtures. |
| 4 | Planner | `approve_with_notes` | No remaining sequencing, micro-sizing, or ST-P1-19 wording blockers; ledger needed final bookkeeping. | Applied by recording final verdicts. |
| 4 | Critic | `approve` | No remaining blocking acceptance, fixture, rollback, verification, or degraded-review issues. | No change required. |

## Current Decision

These seven TODOs are promoted to `complete_contract` by the non-active
promotion Ralph pass. The promoted scope is contract-level workflow behavior:
runtime shell wiring, browser/CDP execution, external push, install, deployment,
or fail-closed gate enforcement still requires a later explicit execution
request and fresh verification/review evidence.
