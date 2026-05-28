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
| SA-P0-01 | Policy Authority / Review Gate | blocker | `docs/WORKFLOW.md`, `scripts/review-gate.sh`, `scripts/test-review-summary.sh`, `plans/AI_AUTO_STRUCTURAL_AUDIT_EXECUTION.md` | Degraded review or sidecar result is reported as normal approval. | Commit readiness, user trust, future automation claims. | contract + review discipline | none | contract_started | P0 shell summary cases now require normal trust only for multi-reviewer proceed. |
| SA-P0-02 | Reflection Sidecars | blocker | `plans/AI_AUTO_REFLECTION_LOOP_V1.md`, `scripts/reflection_contracts.py`, `tests/test_reflection_contracts.py` | Reflection draft or knowledge sidecar appears to own completion, field truth, or Obsidian promotion. | Knowledge integrity and completion reporting. | contract + tests | Reflection contract surface | contract_started | Sidecar failure remains warning-only; authority claims are rejected. |
| SA-P0-03 | Reviewer Eligibility | blocker | `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`, `scripts/reflection_contracts.py`, `scripts/self_demo_contracts.py`, subagent review notes | Unanimous language is used without reviewer eligibility, context completeness, and degraded-state labels. | Ralph completion claims and review artifacts. | contract + acceptance tests | review summary semantics | contract_started | Independent approvals now require eligible context; degraded paths require explicit reporting. |

## P1: Source-Of-Truth And Artifact Drift

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Deferred Tool Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P1-01 | Template Lifecycle | high | `templates/automation-base/`, `tools/ai-auto-template-status`, `scripts/verify.sh`, `tests/test_template_global_contracts.py` | Template-owned, hybrid, and project-owned surfaces drift across docs, installer, doctor, status, and verify. | Template patch safety and downstream project updates. | manifest parity test | template ownership rules | contract_started | Manifest tooling review deferred; current test locks manifest path existence and uniqueness. |
| SA-P1-02 | Global Tools | high | `docs/GLOBAL_TOOLS.md`, `scripts/install-global-files.sh`, `scripts/automation-doctor.sh`, `scripts/bootstrap-ai-lab.sh`, `tests/test_template_global_contracts.py` | Helper added to one install/status/doc surface but omitted elsewhere. | Broken helper repair or misleading installation state. | helper parity test | helper registry surfaces | contract_started | Central manifest tool deferred; current test compares existing link surfaces. |
| SA-P1-03 | Artifact Sync | high | `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`, `scripts/self_demo_contracts.py`, `tests/test_self_demo_contracts.py` | Final answer contains material findings absent from the latest artifact. | Traceability, review quality, user decisions. | pure contract + delta tests | plan/TODO reconciliation | contract_started | Runtime artifact scanner remains deferred; current checker validates recorded finding metadata. |

## P1: Self-Demo Validation

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Deferred Tool Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P1-04 | Self-Demo | high | `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`, `plans/AI_AUTO_STRUCTURAL_AUDIT_PLAN.md`, `scripts/self_demo_contracts.py` | AI_AUTO upgrade is called ready without representative user-action evidence. | User has to manually validate every upgrade; hidden workflow regressions. | pure contract + demo schema | upgrade class definition | contract_started | Runtime demo runner/global helper remains deferred. |
| SA-P1-05 | Self-Demo | medium | `scripts/verify.sh`, `scripts/review-gate.sh`, `tests/test_self_demo_contracts.py` | Demo evidence is confused with formal verification or review-gate approval. | Completion reporting and readiness claims. | pure contract + tests | verify/review authority | contract_started | No new fail-closed gate in this branch. |
| SA-P1-06 | Benchmark Runtime Evidence | high | `scripts/self_demo_contracts.py`, `tests/test_self_demo_contracts.py`, `plans/AI_AUTO_BENCHMARK_BASELINE_2026-05-28.md` | Benchmark contract exists, but no representative workflow benchmark has been run, sampled, baselined, or recorded as evidence. | Performance readiness may be inferred from contract tests instead of measured runtime evidence. | measured baseline artifact + contract clarification | self-demo representative workflow | contract_started | Runner/tooling deferred; first baseline records median 0.257s without claiming readiness. |

## P2: Structural Audit Evidence Quality

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Deferred Tool Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P2-01 | Verify Coverage | medium | `scripts/verify.sh`, `tests/test_structural_boundary_contracts.py` | Broad shell fixture coverage is hard to audit for exact behavioral guarantees. | Maintenance cost and regression diagnosis. | audit marker test | changed behavior surface | contract_started | Coverage tooling deferred; current test locks critical verify fixture markers. |
| SA-P2-02 | Rebuild And Split | medium | `tools/ai-rebuild-plan`, split helper docs, `tests/test_structural_boundary_contracts.py` | Read-only plan output is mistaken for approval to run write-capable refactors. | Broad code churn and behavior drift. | read-only boundary test | approved execution plan | contract_started | Apply automation deferred; current test checks read-only wording and unchanged target file set. |
| SA-P2-03 | GStack Follow-Up | medium | `plans/GSTACK_BENCHMARK.md`, `plans/GSTACK_BENCHMARK_RALPH_DEEP_DIVE.md`, `scripts/gstack_benchmark_contracts.py`, `tests/test_gstack_benchmark_contracts.py` | GStack reference language becomes mandatory process or duplicate authority. | Workflow bloat and authority conflict. | boundary regression test | benchmark boundaries | contract_started | Runtime GStack adoption deferred; current test rejects installation, standing roster, and worktree execution from benchmark context. |

## Deferred Items

These are still TODOs, but they are not approved for write-capable execution by
this structural Ralph branch.

| Deferred Item | Reason | Minimum Later Approval Gate |
| --- | --- | --- |
| Candidate small-tool discovery | Excluded by current structural branch. | Explicit tool-discovery scope, no-install default, and a read-only candidate report. |
| Adoption matrix scoring | Excluded with item 6; scoring criteria should not be invented inside this Ralph branch. | Approved scoring criteria before any package, SDK, or helper adoption recommendation. |
| Guidance-budget cleanup | Excluded with item 7. Existing warnings may be reported but not fixed here. | Separate cleanup plan, behavior-locking checks, and doc-budget acceptance threshold. |
| Runtime GStack installation | Explicitly rejected by benchmark boundary. | Separate runtime adoption decision with install target, rollback path, and authority conflict review. |
| Parallel sprint execution | Recorded as benchmark observation only. | Approved parallel execution plan with branch/worktree ownership, conductor, and integration gate. |
| Self-demo global helper or runtime runner | Deferred until SA-P1-04 moves beyond `contract_started`. | Dogfood plan with representative workflow, side-effect boundary, cleanup state, benchmark sample method, and proof that pure contracts caught at least one real or fixture workflow regression. |

There is no separate P3 backlog in this Ralph branch. Later-approval work is
absorbed by the deferred table above so it stays visible without implying
approval to execute it now.

## Current Status

This backlog is an execution artifact, not broad implementation approval. Items
with `contract_started` have a narrow regression contract or evidence artifact;
runtime adoption, new helper installation, write-capable rebuild execution, and
guidance-budget cleanup remain deferred until separately approved.
