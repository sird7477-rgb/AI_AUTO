# AI_AUTO AA-9 U2 Gate Surface Plan (2026-07-04)

## Decision

Adopt packet alternative (C): keep the current Bash review-context emitters and
Python contracts unchanged for this slice.

AA-9's intended win is drift reduction, not speed. The only implementation path
allowed by the packet is Phase 2a from `plans/AI_AUTO_U2_COLLAPSE_PLAN_2026-06-26.md`:
replace each paired `scripts/collect-review-context.sh` audit emitter with
`python3 scripts/self_demo_contracts.py <policy> --report`, preserving the
current reviewer-facing output byte-for-byte.

That path is not a small collapse in this repo state. It requires a new Python
report-rendering layer for nine policies:

- `spec_code_alignment`
- `standard_flow_preservation`
- `product_challenge`
- `browser_qa_evidence`
- `visual_artifact`
- `planning_visual_gate`
- `completion_pack_routing`
- `persona_lens`
- `phase_scope_guard`

The current Python contracts return `ContractResult` reasons and data, while the
Bash emitters produce reviewer report lines such as `standard_flow_status:
impact_map_required`, fenced changed-file blocks, and path-derived advisory
rows. Preserving those strings exactly would move the Bash rendering contract
into Python before any Bash body could be removed. That adds a second report
surface first, then requires byte-diff validation across every scenario.

## Rejected Path: Phase 2a Now

Rejected: implement `--report` for all nine paired policies in this slice.

Reasons:

- The report strings are the runtime contract consumed by review context and the
  existing `tests/test_*_context.py` files. Any non-byte-identical change is a
  gate-facing behavior change.
- The policy result names and report output names are not isomorphic. A direct
  wrapper around `ContractResult` would change output; an exact wrapper would
  duplicate rendering logic in Python.
- `persona_lens` and `phase_scope_guard` are especially coupled to changed-file
  scanning and report formatting in `collect-review-context.sh`, not only to a
  simple record-shaped policy.
- AA-10 is next and intentionally changes the `browser_qa_evidence` paired
  policy. Landing a broad report-mode migration immediately before that change
  increases conflict and review risk.
- The original U2 plan already measured and rejected speed as the justification;
  this change must stand only on drift reduction. The implementation cost is too
  high for the current packet slice without a separate golden-output harness
  first.

## Follow-up Gate If Reopened

Reopen Phase 2a only as a dedicated high-risk gate simplification after these
preconditions exist:

1. A golden-output harness captures each target section under normal, blocking,
   and missing-field scenarios.
2. `self_demo_contracts.py <policy> --report` is introduced for one low-coupling
   policy first and proves byte-diff zero against the Bash emitter.
3. The migration order excludes `browser_qa_evidence` until after AA-10 lands.
4. Existing `tests/test_*_context.py` remain unmodified and green.

## Acceptance Mapping

- Packet acceptance ①-③ apply only to replaced policies; no policy is replaced.
- Packet acceptance ④ is satisfied by recording this rejection rationale in a
  plan document and stopping with no code changes.
- Touched surface is limited to `plans/`; no `scripts/`, `tests/`, or
  `templates/automation-base/` files are changed.
