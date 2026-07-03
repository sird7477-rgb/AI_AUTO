# AI_AUTO AA-1 Diff-Scope And Docs/Plans Allowlist Plan

## Packet Contract

- Item: AA-1, gate diff-scope plus docs/plans allowlist.
- Tier: plan-first.
- Scope: `scripts/doc-budget.sh`, `scripts/collect-review-context.sh`, `scripts/review-gate.sh`, `scripts/verify-machinery.sh`, and related docs.
- Boundaries: do not touch `templates/automation-base`; do not rework lock/EX_TEMPFAIL logic; do not delete branch-cumulative reporting; do not use path-prefix "other session churn" as an automatic out-of-scope decision.

## ST-P1-75 Diagnosis

ST-P1-64 added a launcher-derived completion base so prior shared-branch guidance debt becomes warning-only while current-run guidance bloat remains hard-failing. The ST-P1-75 recurrence shows that this did not cover the jw_dev shared-branch path: the reported change touched non-guidance paths while `AGENTS.md` and `docs/*.md` delta was zero, yet doc-budget blocked on cumulative guidance debt (`completion-scoped net added 336 > 300`). That is a coverage gap rather than evidence that branch-cumulative reporting is wrong: doc-budget still needs to report cumulative debt, but readiness should not hard-fail when the current change's own guidance delta is within budget.

Decision: keep branch-cumulative and completion-scoped reporting, but add a distinct own-change guidance delta. When cumulative debt exceeds the hard limit and own-change delta is zero or within budget, downgrade the cumulative excess to a warning with an explicit reason. When own-change delta exceeds the hard limit, fail.

## Untracked Guard Design

`REVIEW_UNTRACKED_ALLOWLIST` and auto changed-scope allowlisting already exist. AA-1 adds a default local-artifact relaxation only for document-shaped untracked files under `docs/` and `plans/`, matching the plan-files-stay-local convention without treating arbitrary files in those directories as safe. Code-like extensions under `plans/` or `docs/` stay material and blocking.

Decision: default allowlist only `docs/**/*.md`, `docs/**/*.mdx`, `docs/**/*.txt`, `plans/**/*.md`, `plans/**/*.mdx`, and `plans/**/*.txt`. Keep explicit allowlists and auto changed-scope behavior intact. Emit the default source/reason in review context so review-gate verdicts carry the diagnosis.

## Acceptance Mapping

1. Fixture where own guidance delta is zero while branch-cumulative exceeds the limit: doc-budget warning/pass with reason.
2. Fixture where own guidance delta exceeds the limit: doc-budget fails.
3. Fixture with only untracked `plans/x.md`: guard clears; `plans/x.py` remains blocking.
4. Add these fixtures to `scripts/verify-machinery.sh`.
5. This plan records the ST-P1-75 diagnosis and selected design before implementation.
