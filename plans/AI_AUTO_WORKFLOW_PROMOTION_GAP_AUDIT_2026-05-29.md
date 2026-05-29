# AI_AUTO Workflow Promotion Gap Audit

## Purpose

This audit records plan or guidance surfaces that existed in the repository but
were not yet promoted into a regular AI_AUTO workflow, gate, helper, or
canonical TODO lane at discovery time. As of the 2026-05-29 non-active
promotion Ralph pass, `ST-P1-13` through `ST-P1-19` are promoted to
`complete_contract` through workflow policy contracts and tests.

## Audit Rule

A candidate is included when all of these are true:

- repo-local evidence describes a workflow, phase, checklist, or operating
  surface
- the surface is not already implemented, completed by contract, or explicitly
  excluded
- a future agent could reasonably rediscover it and assume it is ready unless
  the boundary is tracked

A candidate is not included when it is already tracked by an existing
`later_gated` TODO, completed contract, installed required gate, or excluded
item in `plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md`.

## Newly Tracked Promotion Gaps

| ID | Candidate | Evidence | Current State | Promotion Boundary |
| --- | --- | --- | --- | --- |
| `ST-P1-13` | Planning visualization workflow: Mermaid, Structurizr, Excalidraw, and paired `*-spec.md` operations | `docs/PLANNING_VISUALIZATION_GUIDE.md`, `docs/plans/_templates/excalidraw-spec-template.md`, `docs/plans/_templates/high-risk-diagrams.md`, `plans/AI_AUTO_NATIVE_WORKBENCH.md` | Guidance exists, but no canonical TODO, validator, stale-diagram gate, or source-of-truth checker owns it. | Promote only with source-of-truth rules, stale detection, paired spec handling, and review/verify evidence. |
| `ST-P1-14` | Product challenge planning gate | `plans/GSTACK_BENCHMARK.md`, `plans/GSTACK_BENCHMARK_RALPH_DEEP_DIVE.md`, `docs/AUTOMATION_OPERATING_POLICY.md` | Planning policy has no-code-first language, but the sharper product challenge surface remains a roadmap item. | Promote as a lightweight planning lens before broad plans, not as a blocking gate for routine work. |
| `ST-P1-15` | UI/browser QA evidence workflow | `plans/GSTACK_BENCHMARK.md`, `plans/GSTACK_BENCHMARK_RALPH_DEEP_DIVE.md`, `docs/UI_COMPLETION.md`, `docs/CHROME_CDP_ACCESS.md`, `plans/AI_AUTO_REFLECTION_LOOP_V1.md` | UI completion and CDP safety docs exist, but report-only QA evidence, visual/browser checklist, and fix-loop boundary are not a regular workflow. | Promote read-only/report-only first; keep credentialed browser state security-gated. |
| `ST-P1-16` | Phase/scope guard workflow | `plans/GSTACK_BENCHMARK_RALPH_DEEP_DIVE.md`, `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`, `docs/AUTOMATION_OPERATING_POLICY.md` | Phase scope lock is documented as a risk and small-tool idea, but no canonical guard detects out-of-phase edits or missing deferral records. | Promote only after defining allowed phase fields, false-positive handling, and artifact-sync behavior. |
| `ST-P1-17` | Review finding revision loop | `docs/MULTI_AI_COLLABORATION.md`, `scripts/review-gate.sh`, `scripts/summarize-ai-reviews.sh` | Review-gate exists, but automatic task generation from findings, bounded revision cycles, and second-pass review remain deferred. | Promote only when repeated review-fix-review friction appears; keep human acceptance of findings explicit. |
| `ST-P1-18` | Tool availability and adoption status workflow | `plans/AI_AUTO_SMALL_TOOL_ADOPTION_REVIEW_2026-05-28.md`, `scripts/automation-doctor.sh`, `scripts/bootstrap-ai-lab.sh`, `docs/GLOBAL_TOOLS.md` | Doctor/bootstrap report installed tools, but there is no single adoption-status surface for optional, required, reference-only, rejected, and missing tools. | Promote as read-only status/reporting only; it must not install packages or silently upgrade gates. |
| `ST-P1-19` | Completion-pack trigger and lens routing audit | `docs/SECURITY_COMPLETION.md`, `docs/DEPLOYMENT_COMPLETION.md`, `docs/OBSERVABILITY_COMPLETION.md`, `docs/PERFORMANCE_COMPLETION.md`, `docs/DATA_COMPLETION.md`, `docs/UI_COMPLETION.md`, `plans/GSTACK_BENCHMARK_RALPH_DEEP_DIVE.md` | Completion packs exist as reference docs, but named trigger routing and regular review lenses for security, release, ops, performance, data, and UI are uneven. Documentation-generation remains a GStack reference lens, not a current completion pack. | Promote as routing/checklist audit before adding any new runtime lane. |

## Already Tracked Or Closed

| Surface | Current Tracking |
| --- | --- |
| Persona lens and review-gate enforcement | `ST-P1-07` complete_contract |
| Obsidian pending-output auto-push | `ST-P1-08` complete_contract |
| Project AI_AUTO update visibility | `ST-P1-09` complete_contract |
| High/medium/low relationship clearance | `ST-P1-10` through `ST-P1-12` complete_contract |
| Guidance Stage 2 consolidation | Later-gated item in the structural backlog |
| Self-demo runtime evidence | Later-gated item in the structural backlog |
| Benchmark warn/gate policy | Later-gated item in the structural backlog |
| Runtime GStack, parallel sprint execution, persistent browser/session runtime, deployment automation, second memory runtime | Excluded/reference-only by structural backlog |
| ShellCheck warning gate and Hyperfine observe-mode benchmark capture | Completed or observe-mode in structural backlog |

## Not Promoted To TODO

| Surface | Reason |
| --- | --- |
| `ruff`, `markdownlint`, `actionlint`, `shfmt`, `cloc`/`tokei`, `fd`, `yq` | Already rejected or reference-only in tool reviews; no current repo trigger justifies a regular workflow. |
| Structurizr CLI or Excalidraw rendering installation | `ST-P1-13` should first define the operating contract; tool installation is a later implementation detail. |
| GBrain or external memory runtime | Explicitly excluded because Reflection/Obsidian/project-memory already own the memory boundary. |
| Pair-agent or persistent browser coordination | Security-gated future only; current CDP guidance keeps browser access optional and credential-equivalent. |

## Stop Condition

This audit is complete when each newly discovered promotion gap appears in the
canonical structural backlog as `complete_contract`, and `scripts/todo-report.py
--fail-on-active` still reports zero active and zero non-active TODOs for these
items.

## Detail Plan

The micro-unit execution planning surface for `ST-P1-13` through `ST-P1-19` is
`plans/AI_AUTO_WORKFLOW_PROMOTION_DETAIL_PLAN_2026-05-29.md`. That file is the
planning and contract-promotion record for future execution review; this audit
remains the discovery and inclusion/exclusion record.

## Ownership Chain

- `plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md` is the canonical status and
  TODO index consumed by `scripts/todo-report.py`.
- This file is the discovery and inclusion/exclusion record for the workflow
  promotion gaps.
- `plans/AI_AUTO_WORKFLOW_PROMOTION_DETAIL_PLAN_2026-05-29.md` is the governing
  future execution plan for `ST-P1-13` through `ST-P1-19`.
