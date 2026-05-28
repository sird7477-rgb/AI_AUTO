# AI_AUTO Structural Weakness Backlog

## Language Note

This artifact is written in English to preserve continuity with the existing
GStack and structural-audit input artifacts used in this Ralph branch. Korean
remains the default for new strategy, architecture, and operational-judgment
documents; field names, state values, paths, and schema labels stay in English
where they are easier to reuse mechanically.

## Scope

This backlog materializes the priority TODO branch for structural audit items
1-5. It excludes:

- small-tool adoption review, candidate-tool scoring, helper wiring, and
  implementation
- guidance-budget warning cleanup and consolidation

## Backlog Fields

Each item uses:

- `id`
- `slice`
- `severity`
- `evidence`
- `failure_mode`
- `blast_radius`
- `fix_type`
- `dependency`
- `status`
- `deferred_tool_note`

Status values:

- `open`: identified backlog item with no scoped implementation started.
- `contract_started`: tracked pure contract or test coverage exists, but no
  runtime caller or fail-closed gate has been adopted.

## P0: False Completion And Authority Leakage

`blocker` severity describes the structural risk class. It is not a current
blocker to this documentation-only Ralph branch unless the active micro-review
verdict cites it as unresolved.

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Deferred Tool Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P0-01 | Policy Authority / Review Gate | blocker | `docs/WORKFLOW.md`, `scripts/review-gate.sh`, `plans/AI_AUTO_STRUCTURAL_AUDIT_EXECUTION.md` | Degraded review or sidecar result is reported as normal approval. | Commit readiness, user trust, future automation claims. | document + review discipline | none | open | No tool adoption in this branch. |
| SA-P0-02 | Reflection Sidecars | blocker | `plans/AI_AUTO_REFLECTION_LOOP_V1.md`, `plans/AI_AUTO_STRUCTURAL_AUDIT_EXECUTION.md` | Reflection draft or knowledge sidecar appears to own completion, field truth, or Obsidian promotion. | Knowledge integrity and completion reporting. | document + future contract test candidate | Reflection contract surface | open | Future tool/check discussion deferred. |
| SA-P0-03 | Reviewer Eligibility | blocker | `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`, subagent review notes | Unanimous language is used without reviewer eligibility, context completeness, and degraded-state labels. | Ralph completion claims and review artifacts. | document + acceptance criteria | review summary semantics | open | Future eligibility checker deferred. |

## P1: Source-Of-Truth And Artifact Drift

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Deferred Tool Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P1-01 | Template Lifecycle | high | `templates/automation-base/`, `tools/ai-auto-template-status`, `scripts/verify.sh` | Template-owned, hybrid, and project-owned surfaces drift across docs, installer, doctor, status, and verify. | Template patch safety and downstream project updates. | document + future test checklist | template ownership rules | open | Manifest tooling review deferred. |
| SA-P1-02 | Global Tools | high | `docs/GLOBAL_TOOLS.md`, `scripts/install-global-files.sh` | Helper added to one install/status/doc surface but omitted elsewhere. | Broken helper repair or misleading installation state. | document + parity checklist | helper registry surfaces | open | Central manifest tool deferred. |
| SA-P1-03 | Artifact Sync | high | `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md` | Final answer contains material findings absent from the latest artifact. | Traceability, review quality, user decisions. | document + acceptance criteria | plan/TODO reconciliation | open | Automated delta checker deferred. |

## P1: Self-Demo Validation

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Deferred Tool Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P1-04 | Self-Demo | high | `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`, `plans/AI_AUTO_STRUCTURAL_AUDIT_PLAN.md`, `scripts/self_demo_contracts.py` | AI_AUTO upgrade is called ready without representative user-action evidence. | User has to manually validate every upgrade; hidden workflow regressions. | pure contract + demo schema | upgrade class definition | contract_started | Runtime demo runner/global helper remains deferred. |
| SA-P1-05 | Self-Demo | medium | `scripts/verify.sh`, `scripts/review-gate.sh`, `tests/test_self_demo_contracts.py` | Demo evidence is confused with formal verification or review-gate approval. | Completion reporting and readiness claims. | pure contract + tests | verify/review authority | contract_started | No new fail-closed gate in this branch. |
| SA-P1-06 | Benchmark Runtime Evidence | high | `scripts/self_demo_contracts.py`, `tests/test_self_demo_contracts.py` | Benchmark contract exists, but no representative workflow benchmark has been run, sampled, baselined, or recorded as evidence. | Performance readiness may be inferred from contract tests instead of measured runtime evidence. | benchmark run plan + evidence artifact | self-demo representative workflow | open | Runner/tooling deferred; first step is a measured baseline artifact, not adoption. |

## P2: Structural Audit Evidence Quality

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Deferred Tool Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P2-01 | Verify Coverage | medium | `scripts/verify.sh` | Broad shell fixture coverage is hard to audit for exact behavioral guarantees. | Maintenance cost and regression diagnosis. | document + future targeted tests | changed behavior surface | open | Coverage tooling deferred. |
| SA-P2-02 | Rebuild And Split | medium | `tools/ai-rebuild-plan`, split helper docs | Read-only plan output is mistaken for approval to run write-capable refactors. | Broad code churn and behavior drift. | document | approved execution plan | open | Apply automation deferred. |
| SA-P2-03 | GStack Follow-Up | medium | `plans/GSTACK_BENCHMARK.md`, `plans/GSTACK_BENCHMARK_RALPH_DEEP_DIVE.md` | GStack reference language becomes mandatory process or duplicate authority. | Workflow bloat and authority conflict. | document | benchmark boundaries | open | Runtime GStack adoption deferred. |

## Deferred Items

| Deferred Item | Reason |
| --- | --- |
| Candidate small-tool discovery | Excluded by current user scope. Needs a later approval after structural backlog review. |
| Adoption matrix scoring | Excluded with item 6. |
| Guidance-budget cleanup | Excluded with item 7. Existing warnings may be reported but not fixed here. |
| Runtime GStack installation | Explicitly rejected by benchmark boundary. |
| Parallel sprint execution | Recorded as benchmark observation only. |
| Self-demo global helper or runtime runner | Deferred until SA-P1-04 moves beyond `contract_started` with tracked evidence that pure contracts catch real workflow regressions. |

## Current Status

This backlog is an execution artifact, not implementation approval. Items remain
`open` until a later scoped task chooses one backlog item and defines its
verification path.
