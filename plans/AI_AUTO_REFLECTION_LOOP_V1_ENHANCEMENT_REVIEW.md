# AI_AUTO Reflection Loop V1 Enhancement Review

Date: 2026-05-28

Scope:

- `plans/AI_AUTO_REFLECTION_LOOP_V1.md`
- `plans/AI_AUTO_NATIVE_WORKBENCH.md`
- `plans/AI_AUTO_REFLECTION_LOOP_V1_PHASE0.md`
- `plans/GSTACK_BENCHMARK.md`

Advisor artifacts:

- `.omx/artifacts/claude-ai-root-workspace-ai-lab-plans-ai-auto-reflection-loop-v1-md-2026-05-27T23-48-12-596Z.md`
- `.omx/artifacts/gemini-ai-root-workspace-ai-lab-plans-ai-auto-reflection-loop-v1-md-2026-05-27T23-46-46-093Z.md`

## Consensus Summary

Reflection Loop V1 has the right backbone, but several rules need to be made
more explicit before the plan is used as an execution source of truth. The main
risk is not missing a whole phase. The main risk is letting later findings,
phase boundaries, reviewer status, or user-provided UI references become
implicit and then drift during execution.

Claude and Gemini agreed on the following high-priority themes:

- user-provided UI design templates need source-of-truth priority over generic
  external references
- each phase needs stronger scope locking and evidence requirements
- late research findings must sync back into the active artifact before final
  reporting or be explicitly deferred
- degraded, fallback, skipped, or self-review states must not be presented as
  independent unanimous approval
- privacy blocking needs durable audit evidence, not only pass/fail behavior

## Must

### M1. User UI Template Source Of Truth

Current state:

- The UI Visual Alignment Layer defines reference intake, principle extraction,
  `ui-spec.md`, screenshot QC, and anti-AI UI taste checks.
- It does not clearly state that a user-provided design template is a higher
  authority than external product references.

Risk:

- A user template can be treated as another inspiration source, then distorted
  under the label of principle extraction.

Required refinement:

- Add a Source-of-Truth hierarchy to the UI Visual Alignment Layer:

```text
user_design_template
> existing_project_screen
> external_reference
```

- Add `source_of_truth_class` to UI spec requirements:

```text
user_template | project_screen | external_reference
```

- Add a no-distortion fixture or checklist for user templates.

Primary reflection target:

- `plans/AI_AUTO_REFLECTION_LOOP_V1.md` UI Visual Alignment Layer

### M2. Phase Scope Lock

Current state:

- Phase 0 has a boundary plan.
- The main V1 plan lists Phase 1 through Phase 6 in one document.

Risk:

- Execution can accidentally mix later-phase artifacts into an earlier phase.

Required refinement:

- Define allowed paths, artifacts, scripts, and outputs per phase.
- Require a phase containment check before a phase is marked complete.
- Treat out-of-phase files as blocked unless explicitly deferred or approved.

Primary reflection target:

- `plans/AI_AUTO_REFLECTION_LOOP_V1_PHASE0.md`
- `plans/AI_AUTO_REFLECTION_LOOP_V1.md` implementation priorities

### M3. Artifact Sync Gate

Current state:

- `plans/GSTACK_BENCHMARK.md` documents a failure mode where a later finding was
  discussed in conversation but not reflected in the benchmark artifact.
- The rule has not yet been absorbed into Reflection Loop V1.

Risk:

- Active plans, benchmarks, or research documents stop being the source of truth.

Required refinement:

- If a material finding appears after an artifact is written, patch the artifact
  before final reporting or record `deferred_with_reason`.
- Before final reporting, run a delta check: what important facts were learned
  after the last artifact write?
- Final answers must not contain material conclusions absent from the artifact.

Primary reflection target:

- `plans/AI_AUTO_REFLECTION_LOOP_V1.md` Report Contract or a new Research /
  Benchmark Artifact Sync Gate section
- `plans/GSTACK_BENCHMARK.md` backlink to the Reflection Loop rule after adoption

### M4. Reviewer Eligibility And Unanimous Approval

Current state:

- The V1 plan warns that degraded or fallback reviewers must not count as
  independent unanimous approval.
- The eligibility criteria are still too qualitative.

Risk:

- `proceed_degraded`, Codex fallback, skipped Claude, prompt truncation, or
  host self-review can be summarized as consensus.

Required refinement:

- Add a reviewer eligibility matrix:

```text
eligible = independent_session
  AND not_host_executor
  AND not_fallback_substitute
  AND context_completeness >= threshold
```

- Define degraded signals:

```text
rate_limited
model_downgraded
prompt_truncated
context_inspection_failed
same_session_as_executor
```

- Use unanimous language only when eligibility, coverage, and zero-block status
  are evidenced in the artifact.

Primary reflection target:

- `plans/AI_AUTO_REFLECTION_LOOP_V1.md` Plan Review Output Format
- Phase 0 review-integrity fixtures

### M5. Privacy Audit Field Contract

Current state:

- Privacy blocking exists as a core concept.
- Durable audit fields are not consistently required across all draft, report,
  and promotion outputs.

Risk:

- A privacy gate can reject content without leaving enough evidence to debug or
  prove why it was blocked.

Required refinement:

- Require privacy audit metadata on durable artifacts:

```text
privacy_scan:
  scanner: string
  version: string
  skipped: number
  reasons:
    - reason_code
```

- Store counts and reason codes, not raw secret-bearing source content.

Primary reflection target:

- `plans/AI_AUTO_REFLECTION_LOOP_V1.md` Phase 1 Privacy Gate

## Should

### S1. Multi-Session / Worktree Boundary

Current state:

- GStack parallel sprint is recorded as an observation, not an adoption plan.
- V1 resource-aware execution focuses mostly on sidecar/subagent/resource
  contention within the current operating lane.

Risk:

- If tmux/worktree parallel sprinting is introduced later, branch ownership,
  draft deduplication, lock scope, and conductor responsibility may be invented
  ad hoc.

Required refinement:

- Add only the contract boundary to V1:

```text
session_id
worktree_id
branch_owner
conductor
integration_gate
```

- Keep full parallel sprint execution in a separate plan.

Primary reflection target:

- `plans/AI_AUTO_REFLECTION_LOOP_V1.md` Resource-Aware Execution
- `plans/AI_AUTO_NATIVE_WORKBENCH.md` Project Board / Session Monitor

### S2. Promotion Reviewer Contract

Current state:

- Promotion reviewer and instruction promotion are named, but not fully defined.

Risk:

- Obsidian notes or feedback items can accumulate without a clear accept, reject,
  defer, or field-evidence path.

Required refinement:

- Define decisions:

```text
accepted
rejected_with_reason
deferred
needs_field_evidence
```

- Preserve rejected promotion rationale to prevent repeated re-submission.
- Add queue/backpressure behavior for Obsidian or promotion overload.

Primary reflection target:

- `plans/AI_AUTO_REFLECTION_LOOP_V1.md` Phase 5

### S3. Field Validation Profiles

Current state:

- Field validation is listed as a boundary, but project-type profiles are still
  an open decision.

Risk:

- Field completion can be interpreted differently for doc-only, pure-code,
  browser, Odoo, or operational tasks.

Required refinement:

- Define project/task profiles and minimum evidence per profile.
- Keep Reflection from owning field truth; it should record field state and
  required evidence.

Primary reflection target:

- `plans/AI_AUTO_REFLECTION_LOOP_V1.md` Phase 2

## Could

- Workbench trace visualization from draft to trigger, privacy scan, and sidecar
  result
- automatic Excalidraw to `ui-spec.md` traceability matrix
- reviewer cooldown and quota telemetry
- cross-project backfill index visualization

These are useful but should remain later-phase enhancements until the Must and
Should contracts are stable.

## Recommended Application Order

1. Add user UI template Source-of-Truth hierarchy.
2. Add Phase Scope Lock and phase containment evidence.
3. Add Artifact Sync Gate.
4. Add Reviewer Eligibility / unanimous approval criteria.
5. Add Privacy Audit Field Contract.
6. Add Multi-Session / Worktree Boundary as contract only.
7. Expand Promotion Reviewer and Field Validation Profiles.

## Follow-Up TODO

- After the GStack/Rebuild V1 macro structure is stable, run a repository-wide
  contract-gap audit beyond Reflection Loop V1. Compare existing modules,
  scripts, helpers, templates, review flows, knowledge flows, and guidance
  documents against the same gap classes found in this review:
  documented-but-not-enforced rules, source-of-truth drift, degraded-state
  mislabeling, artifact-sync failures, privacy audit gaps, and phase/scope
  leakage.
- For every proposed stricter gate or small tool, evaluate the downside before
  adoption:
  - false positives that block valid work
  - slower feedback loops
  - extra reviewer or user fatigue
  - guidance bloat
  - overfitting to one incident
  - bypass pressure when the gate is too strict
  - maintenance cost versus risk reduction
- Do not treat tighter enforcement as automatically better. Prefer small,
  reversible, warning-first checks unless a gap can cause privacy leakage,
  source-of-truth corruption, unsafe promotion, or false completion claims.
- Add self-demo validation for AI_AUTO feature upgrades. As AI_AUTO gains more
  modules and guidance behavior, users should not have to manually validate
  every upgraded workflow. For module, script, helper, template, or guidance
  changes, define a representative demo scenario that the system can run or
  simulate before claiming the upgrade is ready. The demo should prove the
  intended user-facing behavior, capture evidence, and report remaining manual
  checks separately.

## Stop Condition

This review is a planning artifact. It does not approve implementation by
itself. Each item should be reflected into the relevant V1 plan section or
explicitly deferred before V1 is used as an execution source of truth.
