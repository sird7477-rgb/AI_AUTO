# AI_AUTO Structural Weakness Backlog

## Language Note

This artifact is written in English to preserve continuity with the existing
GStack and structural-audit input artifacts used in this Ralph branch. Korean
remains the default for new strategy, architecture, and operational-judgment
documents; field names, state values, paths, and schema labels stay in English
where they are easier to reuse mechanically.

## Scope

This backlog materializes the priority TODO branch for structural audit items
1-5. It originally excluded:

- small-tool adoption review, candidate-tool scoring, helper wiring, and
  implementation
- guidance-budget warning cleanup and consolidation

Follow-up approval on 2026-05-28 reopened the read-only small-tool discovery and
adoption scoring slice only. The resulting no-install candidate matrix is
recorded in `plans/GSTACK_SMALL_TOOL_ADOPTION_CANDIDATES_2026-05-28.md`.
The broader non-GStack small-tool review is recorded separately in
`plans/AI_AUTO_SMALL_TOOL_ADOPTION_REVIEW_2026-05-28.md`.
Helper wiring for approved internal tools has since started. New package
installation, browser/runtime adoption, and broad guidance consolidation remain
outside this backlog's execution approval unless a new scoped plan explicitly
reopens them.

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
- `boundary_note`

Status values:

- `open`: identified backlog item with no scoped implementation started.
- `contract_started`: tracked pure contract or test coverage exists, but no
  runtime caller or fail-closed gate has been adopted.
- `complete_contract`: scoped repo-native contract, caller, or verification
  evidence exists and no active implementation work remains.
- `complete`: completed by implementation plus verification evidence.
- `complete_observe_mode`: observational capability is complete; policy
  promotion remains later-gated, not active.
- `display_only_complete`: functional behavior is complete; only optional
  presentation polish could be requested later.
- `installed_required`: installed and wired into the required verification path.
- `reference_only`, `excluded`, `later_gated`: not active TODO statuses.

## P0: False Completion And Authority Leakage

`blocker` severity describes the structural risk class. It is not a current
blocker to this documentation-only Ralph branch unless the active micro-review
verdict cites it as unresolved.

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Boundary Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P0-01 | Policy Authority / Review Gate | blocker | `docs/WORKFLOW.md`, `scripts/review-gate.sh`, `scripts/test-review-summary.sh`, `plans/AI_AUTO_STRUCTURAL_AUDIT_EXECUTION.md` | Degraded review or sidecar result is reported as normal approval. | Commit readiness, user trust, future automation claims. | contract + review discipline | none | complete_contract | P0 shell summary cases require normal trust only for multi-reviewer proceed, and `review-gate.sh` reports degraded coverage explicitly. |
| SA-P0-02 | Reflection Sidecars | blocker | `plans/AI_AUTO_REFLECTION_LOOP_V1.md`, `scripts/reflection_contracts.py`, `tests/test_reflection_contracts.py` | Reflection draft or knowledge sidecar appears to own completion, field truth, or Obsidian promotion. | Knowledge integrity and completion reporting. | contract + tests | Reflection contract surface | complete_contract | Sidecar failure remains warning-only; authority claims are rejected by contract tests. |
| SA-P0-03 | Reviewer Eligibility | blocker | `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`, `scripts/reflection_contracts.py`, `scripts/self_demo_contracts.py`, subagent review notes | Unanimous language is used without reviewer eligibility, context completeness, and degraded-state labels. | Ralph completion claims and review artifacts. | contract + acceptance tests | review summary semantics | complete_contract | Independent approvals require eligible context; degraded paths require explicit reporting. |

## P1: Source-Of-Truth And Artifact Drift

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Boundary Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P1-01 | Template Lifecycle | high | `templates/automation-base/`, `tools/ai-auto-template-status`, `scripts/verify.sh`, `tests/test_template_global_contracts.py` | Template-owned, hybrid, and project-owned surfaces drift across docs, installer, doctor, status, and verify. | Template patch safety and downstream project updates. | manifest parity test | template ownership rules | complete_contract | Current tests lock manifest path existence, uniqueness, template version, patch notes, and template script parity for touched scripts. Broader manifest tooling is not active. |
| SA-P1-02 | Global Tools | high | `docs/GLOBAL_TOOLS.md`, `scripts/install-global-files.sh`, `scripts/automation-doctor.sh`, `scripts/bootstrap-ai-lab.sh`, `tests/test_template_global_contracts.py` | Helper added to one install/status/doc surface but omitted elsewhere. | Broken helper repair or misleading installation state. | helper parity test | helper registry surfaces | complete_contract | Current tests compare existing link surfaces and doctor/bootstrap reports required helper availability. Central manifest tooling is not active. |
| SA-P1-03 | Artifact Sync | high | `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`, `scripts/self_demo_contracts.py`, `tests/test_self_demo_contracts.py`, `scripts/todo-report.py` | Final answer contains material findings absent from the latest artifact. | Traceability, review quality, user decisions. | pure contract + delta tests + report wrapper | plan/TODO reconciliation | complete_contract | Current checker validates recorded finding metadata, and the TODO report wrapper fails verification when active canonical TODOs remain. Runtime artifact scanning is not active. |

## P1: Self-Demo Validation

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Boundary Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P1-04 | Self-Demo | high | `plans/AI_AUTO_REFLECTION_LOOP_V1_ENHANCEMENT_REVIEW.md`, `plans/AI_AUTO_STRUCTURAL_AUDIT_PLAN.md`, `scripts/self_demo_contracts.py` | AI_AUTO upgrade is called ready without representative user-action evidence. | User has to manually validate every upgrade; hidden workflow regressions. | pure contract + demo schema | upgrade class definition | complete_contract | Pure self-demo schema rejects readiness without representative evidence. Runtime demo runner/global helper is not active. |
| SA-P1-05 | Self-Demo | medium | `scripts/verify.sh`, `scripts/review-gate.sh`, `tests/test_self_demo_contracts.py` | Demo evidence is confused with formal verification or review-gate approval. | Completion reporting and readiness claims. | pure contract + tests | verify/review authority | complete_contract | Contracts reject replacing `verify.sh` or `review-gate.sh`; completion authority requires both gates. |
| SA-P1-06 | Benchmark Runtime Evidence | high | `scripts/self_demo_contracts.py`, `tests/test_self_demo_contracts.py`, `scripts/benchmark-command.py`, `plans/benchmarks/`, `plans/AI_AUTO_BENCHMARK_BASELINE_2026-05-28.md` | Benchmark contract exists, but no representative workflow benchmark has been run, sampled, baselined, or recorded as evidence. | Performance readiness may be inferred from contract tests instead of measured runtime evidence. | measured baseline artifact + contract clarification | self-demo representative workflow | complete_observe_mode | Observe-mode capture exists with `hyperfine`; warn/gate policy is later-gated and not active. |

## P2: Structural Audit Evidence Quality

| ID | Slice | Severity | Evidence | Failure Mode | Blast Radius | Fix Type | Dependency | Status | Boundary Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SA-P2-01 | Verify Coverage | medium | `scripts/verify.sh`, `tests/test_structural_boundary_contracts.py`, `scripts/todo-report.py` | Broad shell fixture coverage is hard to audit for exact behavioral guarantees. | Maintenance cost and regression diagnosis. | audit marker test | changed behavior surface | complete_contract | Current tests lock critical verify fixture markers, and verify now checks canonical TODO clearance. Broader coverage tooling is not active. |
| SA-P2-02 | Rebuild And Split | medium | `tools/ai-rebuild-plan`, split helper docs, `tests/test_structural_boundary_contracts.py` | Read-only plan output is mistaken for approval to run write-capable refactors. | Broad code churn and behavior drift. | read-only boundary test | approved execution plan | complete_contract | Current tests check read-only wording and unchanged target file set; write-capable apply remains outside active TODO. |
| SA-P2-03 | GStack Follow-Up | medium | `plans/GSTACK_BENCHMARK.md`, `plans/GSTACK_BENCHMARK_RALPH_DEEP_DIVE.md`, `scripts/gstack_benchmark_contracts.py`, `tests/test_gstack_benchmark_contracts.py` | GStack reference language becomes mandatory process or duplicate authority. | Workflow bloat and authority conflict. | boundary regression test | benchmark boundaries | complete_contract | Runtime GStack adoption is excluded from active and later-gated TODOs; current tests reject installation, standing roster, and worktree execution from benchmark context. |

## Later-Gated Items

These are not active TODOs. They may become TODOs only if their trigger appears
and a new scoped plan records verification, rollback, and review coverage.

| Item | Trigger | Minimum Later Approval Gate |
| --- | --- | --- |
| Guidance Stage 2 consolidation | Real duplication pressure appears after primary/template budgets pass, or a human explicitly asks for consolidation. | Dedicated completion-pack skeleton plan, template version and patch notes, `./scripts/verify.sh`, and `./scripts/review-gate.sh`. |
| Self-demo runtime evidence | A specific AI_AUTO upgrade needs representative user-action evidence beyond pure contracts. | Dogfood plan with side-effect boundary, cleanup state, benchmark sample method, and proof that pure contracts caught at least one real or fixture workflow regression. |
| Benchmark warn/gate policy | At least several comparable observe-mode captures exist for the same command class and environment. | Baseline variance analysis, explicit threshold rationale, and proof that a failing benchmark cannot block unrelated correctness fixes. |

## Excluded / Reference-Only Items

These items must not appear in future active or deferred TODO reports. They are
kept only so future agents do not rediscover and re-propose them without a new
user request that explicitly reopens the risk.

| Excluded Item | Reason |
| --- | --- |
| Runtime GStack installation | Adds duplicate runtime authority, memory/state surface, and workflow overlap without a repo-local need. |
| Parallel sprint execution | Requires separate branch ownership, concurrency, and review hierarchy policy; current native subagent/team surfaces cover bounded parallel lookup. |
| Browser daemon / cookie / pair-agent paths | Persistent browser state, auth cookies, local HTTP, tunnel, or remote-agent access creates credential and session-boundary risk. |
| Ship/deploy/canary automation | Conflicts with explicit commit/push/deploy approval boundaries in this repository. |
| GBrain or second memory runtime | Duplicates Reflection/Obsidian/project-memory authority and adds sync/index permissions. |
| Autoplan/full external pipeline adoption | Duplicates ralplan/Ralph/structural-audit authority and would blur plan/run gates. |
| Bulk shell formatting with `shfmt` | High churn for low behavioral value; ShellCheck warning gate already covers actionable shell risk. |
| Markdown style lint as a required gate | Existing long-form operational docs would need many style exceptions and doc-budget already controls the actual problem. |
| Broad Semgrep adoption | Rule selection, false positives, and account-backed policy surfaces are out of scope for this local automation testbed. |
| `cloc`/`tokei`, `fd`, `yq` installation | Current repo has enough counting/search/YAML handling through existing shell, Python, `find`, `rg`, and `doc-budget.sh`. |

## Small-Tool Detailed TODO

These items capture the current detailed-review backlog from the GStack and
non-GStack small-tool candidate reviews. They are TODOs, not approval to
implement or install tools.

| ID | Item | Priority | Source | Status | Next Gate |
| --- | --- | --- | --- | --- | --- |
| ST-P1-01 | Review-gate short summary detail design | high | `plans/AI_AUTO_SMALL_TOOL_ADOPTION_REVIEW_2026-05-28.md`, `plans/AI_AUTO_SMALL_TOOL_MICRO_EXECUTION_2026-05-29.md` | display_only_complete | Fixture-based verdict parser design has a short summary contract and output. Optional future polish is not active TODO. |
| ST-P1-02 | Untracked artifact review guard | high | `plans/AI_AUTO_SMALL_TOOL_ADOPTION_REVIEW_2026-05-28.md`, review-gate omission observation, `plans/AI_AUTO_SMALL_TOOL_MICRO_EXECUTION_2026-05-29.md` | complete_contract | Review context flags material untracked artifacts; review summary blocks unless content is included or manual review is reported. |
| ST-P1-03 | TODO/report normalizer | high | User TODO reconciliation concern, `plans/AI_AUTO_SMALL_TOOL_ADOPTION_REVIEW_2026-05-28.md`, `plans/AI_AUTO_SMALL_TOOL_MICRO_EXECUTION_2026-05-29.md`, `scripts/todo-report.py` | complete | `scripts/todo-report.py --fail-on-active` reads the canonical backlog and fails verification if active TODOs remain. |
| ST-P1-04 | Diff scope classifier | medium-high | `plans/AI_AUTO_SMALL_TOOL_ADOPTION_REVIEW_2026-05-28.md`, `plans/AI_AUTO_SMALL_TOOL_MICRO_EXECUTION_2026-05-29.md`, `scripts/review-gate.sh` | complete | Review context reports scope, intensity, and required checks; `review-gate.sh` consumes and prints the generated scope summary before verdict synthesis. |
| ST-P1-05 | Benchmark auto-capture wrapper | medium-high | `plans/AI_AUTO_BENCHMARK_BASELINE_2026-05-28.md`, `plans/AI_AUTO_SMALL_TOOL_ADOPTION_REVIEW_2026-05-28.md`, `plans/AI_AUTO_SMALL_TOOL_MICRO_EXECUTION_2026-05-29.md` | complete_observe_mode | Optional JSON/Markdown capture path exists, `hyperfine` is installed after explicit approval, missing-tool fallback is tested, and benchmark evidence remains observational. Long-term baseline/gate rules are separate future work. |
| ST-P1-06 | Verify/review process leak guard | medium-high | Observed nested review-gate timeout and cleanup need, `plans/AI_AUTO_SMALL_TOOL_MICRO_EXECUTION_2026-05-29.md`, `tests/test_process_cleanup_runtime.py` | complete_contract | Pure cleanup evidence contract exists and a deterministic timeout fixture validates reaped process evidence. |
| ST-P2-01 | External tool install evaluation | medium | `plans/AI_AUTO_SMALL_TOOL_ADOPTION_REVIEW_2026-05-28.md`, `plans/AI_AUTO_EXTERNAL_TOOL_INSTALL_EVALUATION_2026-05-29.md` | installed_required | `shellcheck` is installed and required at warning severity; `hyperfine` is installed and remains observational benchmark capture. |
| ST-P2-02 | ShellCheck warning triage | medium | `plans/AI_AUTO_EXTERNAL_TOOL_INSTALL_EVALUATION_2026-05-29.md` | complete | Warning-severity findings are clean and enforced by `verify.sh`; info/style findings remain optional cleanup candidates only. |

There is no separate P3 backlog in this Ralph branch. Later-gated work is not
active; excluded work is reference-only and must not be reported as remaining
TODO.

Runtime GStack installation and parallel sprint execution are intentionally
excluded from active and later-gated TODOs. The useful GStack parts are its review
vocabulary, planning lenses, quality scoring, and evidence formats; adopting
its daemon/runtime or sprint execution model would add authority overlap and
operating surface without clear benefit for this repository.

## Active TODO Classification

The current active TODO report excludes runtime GStack adoption and parallel
sprint execution, and uses these buckets:

1. Immediately executable TODOs: none. The TODO report wrapper, process cleanup
   runtime fixture, and diff-scope review-gate consumption are implemented.
2. Structural-audit TODOs not complete: none. Current SA items are closed by
   scoped contracts/evidence or explicitly outside active scope.
3. Small-tool TODOs: none. `ST-P1-01` is display-only complete, `ST-P1-03` and
   `ST-P1-04` are implemented, `ST-P1-05` is complete for observe-mode capture,
   and `ST-P1-06` has a deterministic runtime fixture.
4. Currently needed external-tool candidates: none. `shellcheck` is installed
   and required at warning severity; `hyperfine` is installed and remains
   observational. All other candidate installs are excluded or reference-only
   until a new explicit trigger reopens them.
5. Documentation cleanup TODOs: none from the former 9000-line aggregate budget.
   Guidance Stage 2 is later-gated only, not an active TODO.

## Current Status

This backlog is an execution artifact, not broad implementation approval. Active
TODO clearance is verified by `scripts/todo-report.py --fail-on-active`.
Runtime GStack, parallel sprint execution, browser/session automation,
second-memory runtime, and broad external lint/security/counting tools are
excluded, not deferred. Guidance Stage 1 is complete; the former aggregate
guidance warning is resolved by separate primary/template budgets. `shellcheck`
and `hyperfine` are installed and documented; only `shellcheck` is a required
gate.
