# AI_AUTO Small-Tool Micro Execution - 2026-05-29

## Scope

This Ralph pass executes the open small-tool TODOs in micro steps. The goal is
to establish repo-native contracts and focused verification before broader
runtime helper adoption.

## Results

| ID | Result | Evidence | Remaining Work |
| --- | --- | --- | --- |
| ST-P1-01 | `display_only_complete` | `review_gate_short_summary()` plus `scripts/summarize-ai-reviews.sh` short summary output and `scripts/test-review-summary.sh` assertions | None. Later UI/report wording polish is not active TODO. |
| ST-P1-02 | `complete_contract` | `untracked_artifact_review_guard()` plus `collect-review-context.sh` `Untracked Review Guard` section, `summarize-ai-reviews.sh` verdict blocking, and verify fixture | None. Commit-candidate reviews with material untracked artifacts must include content or report manual review. |
| ST-P1-03 | `complete` | `todo_report_reconciliation()` plus `scripts/todo-report.py --fail-on-active` and `tests/test_todo_report.py` | None. The canonical backlog now fails verification if active TODOs remain. |
| ST-P1-04 | `complete` | `diff_scope_classification()`, `collect-review-context.sh` `Diff Scope Summary`, required-check output, and `review-gate.sh` scope consumption | None. Review gate consumes and reports the scope hint before verdict synthesis. |
| ST-P1-05 | `complete_observe_mode` | `benchmark_wrapper_plan()` validates JSON/Markdown output shape, `benchmark-command.py` writes JSON/Markdown evidence, `hyperfine` is used when available, missing-tool fallback is tested, and degraded evidence cannot claim readiness | Later benchmark trigger policy, sufficient-history thresholds, and any warn/gate promotion remain separate work. Benchmark evidence is observational and does not replace verify/review gates. |
| ST-P1-06 | `complete_contract` | `process_cleanup_evidence()` rejects lingering or unreaped timeout evidence, and `tests/test_process_cleanup_runtime.py` exercises a deterministic timeout/reap fixture | None. |

## Non-Goals

- No additional external tool installation beyond the explicitly approved
  `hyperfine` and `shellcheck` installs.
- No runtime GStack adoption.
- No parallel sprint execution.
- No required benchmark gate.
- No claim that contracts alone prove production readiness.

## Benchmark Auto-Capture Update

Benchmark auto-capture is an active micro task for this Ralph slice. The runner
must:

- use `hyperfine` when it is available
- install nothing from inside the benchmark wrapper
- write JSON and Markdown evidence even when `hyperfine` is unavailable
- keep unavailable evidence outside `benchmark_evidence()` readiness claims
- never replace `./scripts/verify.sh` or `./scripts/review-gate.sh`
- start in `observe` mode; `warn` and `gate` require accumulated baselines

Current evidence:

- `plans/benchmarks/20260528T162317Z-verify-smoke.json`
- `plans/benchmarks/20260528T162317Z-verify-smoke.md`
- `plans/benchmarks/20260528T203315Z-verify-smoke-installed.json`
- `plans/benchmarks/20260528T203315Z-verify-smoke-installed.md`

The first capture was taken before `hyperfine` was installed and records
`benchmark_run_status: unavailable`. After explicit approval, `hyperfine 1.18.0`
was installed and the second capture records `benchmark_run_status: pass` with
`verdict: observed`. Neither evidence file claims readiness.

## Guidance Stage 2

Guidance Stage 2 remains a separate consolidation candidate, not a blocking
TODO from the former aggregate warning. Stage 1 brought root `AGENTS.md` to 150
lines, and the follow-up audit found that a single 9000-line aggregate limit was
counting live project guidance together with intentionally mirrored template
guidance. `doc-budget.sh` now enforces separate primary and template budgets
and reports the combined total as informational.

Stage 2 should run only if real duplication pressure appears or a later Ralph
slice explicitly takes on a completion-pack skeleton, template version, patch
notes, verify, and review-gate.
