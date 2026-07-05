# AI_AUTO AA-10 Targeted Recheck + CDP Micro-Plan Plan (2026-07-04)

## Decision

Implement both AA-10 slices in one narrow change:

1. Target review context and reviewer prompts to accepted finding files only
   during a revision recheck.
2. Require the Browser QA micro-plan before CDP access, not only for detailed
   behavior requests.

## Targeted Recheck Design

Use the existing `REVIEW_TARGETED_RECHECK` and
`REVIEW_ACCEPTED_FINDINGS_FILE` contract. Do not add a new mode.

When all of these are true:

- `REVIEW_DECISION_GATE` is not `1`
- `REVIEW_TARGETED_RECHECK` is `1`
- `REVIEW_ACCEPTED_FINDINGS_FILE` exists
- `REVIEW_REVISION_CYCLE_COUNT` is within the existing 1-2 revision limit
- every changed file is listed in an accepted finding's `file` column

then `review-gate.sh` exports `REVIEW_TARGETED_RECHECK_FILES` as the unique
accepted finding file set. `collect-review-context.sh` uses that newline list to
narrow changed-file summaries and patch output to those paths.

If any changed file falls outside that set, the gate does not export a narrowed
scope. The run falls back to the normal full review path and exports
`REVIEW_TARGETED_RECHECK_SCOPE_OK=0`, preserving the existing
`targeted_recheck_scope_expanded` reporting contract.

The decision gate remains unchanged: it still forces
`REVIEW_TARGETED_RECHECK=0`, full context, and full panel review.

## CDP Micro-Plan Design

Change the Browser QA condition from:

```text
detailed_behavior_request
```

to:

```text
detailed_behavior_request OR cdp_access
```

The required rows stay the existing six rows:

- `layout`
- `click_targets`
- `input_handling`
- `alerts_errors`
- `sync_update`
- `business_mapping`

Credential-boundary blocks still run before the micro-plan check. The
micro-plan remains report-only evidence and does not authorize credential export
or patching.

## Tests

- Extend Browser QA context tests so safe CDP without rows reports
  `qa_attention:micro_plan_required`, and safe CDP with all rows remains OK.
- Extend Python contract tests so `browser_qa_evidence_policy` requires rows
  when `cdp_access=True`.
- Extend review summary machinery tests to cover targeted recheck scope
  extraction, narrowed context output, and expanded-scope fallback.

## Boundaries

- Do not weaken `REVIEW_DECISION_GATE=1`.
- Do not mix this with provenance skip.
- Do not make targeted recheck available without an accepted findings file.
- Do not move Browser QA out of report-only mode.
