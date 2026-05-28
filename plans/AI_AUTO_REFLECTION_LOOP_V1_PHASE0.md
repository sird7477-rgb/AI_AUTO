# AI_AUTO Reflection Loop V1 Phase 0 Execution Plan

## Source Plan

- Primary PRD: `plans/AI_AUTO_REFLECTION_LOOP_V1.md`
- Companion PRD: `plans/AI_AUTO_NATIVE_WORKBENCH.md`
- Source snapshots:
  - `.omx/plans/prd-ai-auto-reflection-loop-v1.md`
  - `.omx/plans/prd-ai-auto-native-workbench.md`

Phase 0 exists to prevent the full v1 plan from turning into broad automation
execution. It locks the boundary, authority, privacy, review-integrity, and
report contracts before any implementation phase starts.

## Phase 0 Scope

Allowed:

- Normalize the v1 scope as local sanitized draft capture and explicit
  collection.
- Define the authority matrix for Reflection Loop, Workbench, Obsidian,
  review-gate core, review-gate sidecar, field validation, and execution.
- Define separate work item and knowledge item state models.
- Define trigger contract fields.
- Define privacy blocking rules before durable local artifacts or Obsidian push.
- Define review-integrity reporting, including degraded/fallback reviewer status.
- Define acceptance checks for Phase 1 readiness.

Not allowed:

- Implement hooks, commands, UI, Workbench actions, Obsidian push, promotion
  automation, historical backfill, or field-validation automation.
- Treat Obsidian notes, feedback items, or AI consensus language as runtime
  authority.
- Mark degraded/fallback reviewer coverage as independent unanimous approval.
- Store raw logs, raw prompts, credential-like strings, private absolute paths,
  or sensitive screenshots.

## Execution Order

### Step 0.1: Source Fidelity Check

Compare the tracked PRDs with the `.omx/plans` sources.

Required evidence:

- `cmp -s .omx/plans/prd-ai-auto-reflection-loop-v1.md plans/AI_AUTO_REFLECTION_LOOP_V1.md`
- `cmp -s .omx/plans/prd-ai-auto-native-workbench.md plans/AI_AUTO_NATIVE_WORKBENCH.md`

Stop condition:

- Any mismatch must be explained as an intentional tracked-doc edit, or the
  tracked PRD must be refreshed from the source before continuing.
- Privacy redaction is an allowed source-preserving edit only when the source
  and tracked PRD both replace raw private values with the same anonymized
  category such as `<local-private-path>`.

### Step 0.2: Boundary Extraction

Extract the following sections from the source PRDs into an implementation-ready
contract without changing their meaning:

- plan/run separation
- v1 scope
- authority matrix
- work item state
- knowledge item state
- field validation boundary
- privacy blocking contract
- review integrity / degraded reviewer reporting
- explicit v1 non-goals

Stop condition:

- The extracted contract must not add execution authority beyond the source PRDs.

### Step 0.3: Contract Test Shape

Define tests or static checks before writing implementation:

- state transition schema rejects unknown or cross-owned transitions
- privacy scan rejects raw logs, raw prompts, credential-like strings, private
  absolute paths, and sensitive screenshot originals
- review integrity report preserves skipped/degraded/fallback labels
- sidecar draft failures do not override review-gate core verdicts
- duplicate draft keys remain idempotent

Stop condition:

- If a behavior cannot be tested or smoke-checked, it stays out of Phase 1.

Required Phase 1 fixture contract:

```text
state_transition_valid_work_item.json
→ input: editing -> code_ready with verify evidence
→ expected: accepted as work-item transition

state_transition_invalid_cross_owner.json
→ input: Reflection attempts pending_field_validation -> field_verified
→ expected: rejected; Reflection may mirror evidence but cannot own transition

state_transition_invalid_unknown_state.json
→ input: draft -> magic_done
→ expected: rejected with unknown_state reason

privacy_raw_log_rejected.txt
→ input: raw stack/log dump with private path
→ expected: durable draft/report/index contains only redacted summary,
  count, and reason; raw payload is absent

privacy_credential_rejected.txt
→ input: token/key/session-like value
→ expected: rejected; no credential-like substring persists

privacy_sensitive_screenshot_rejected.md
→ input: screenshot reference marked sensitive
→ expected: only redacted note or reference principle may persist; original
  asset path/content is absent

review_integrity_degraded_golden.json
→ input: Gemini approved, Claude skipped, Codex fallback approved
→ expected: decision may be proceed_degraded; report preserves skipped,
  degraded, fallback, context completeness, and does not claim unanimity

sidecar_failure_core_verdict_golden.json
→ input: review-gate core approve, knowledge draft generation fails
→ expected: core verdict unchanged; sidecar failure appears as warning/trace

draft_idempotency_duplicate_key.jsonl
→ input: two draft candidates with the same repeat_key/source/event id
→ expected: one durable draft or deterministic merge; no duplicate write
```

Each fixture must name the command or static checker that evaluates it before
Phase 1 implementation starts. If no checker exists yet, Phase 1 starts by
adding the smallest checker for that fixture, not by implementing runtime hooks.

### Step 0.4: AI Consensus Gate

Run independent AI reviews against the Phase 0 contract.

Required reviewer questions:

- Does this preserve the source PRDs without distortion?
- Does it keep v1 narrow enough?
- Are authority boundaries explicit enough?
- Are privacy and review-integrity gates blocking at the right points?
- Is there any hidden implementation work that slipped into Phase 0?

Stop condition:

- Phase 0 may pass only when every available independent reviewer returns
  `APPROVE` and no reviewer returns `BLOCK`.
- If a reviewer is skipped or degraded, Phase 0 may continue only as
  `proceed_degraded` for planning documentation, not as true unanimity and not
  as approval to start Phase 1 implementation.
- Phase 1 implementation requires either full reviewer coverage or a separate
  explicit user decision accepting degraded review coverage.

## Phase 0 Acceptance Criteria

- Tracked PRDs are source-faithful to `.omx/plans` or intentional differences
  are documented.
- V1 scope is limited to local sanitized draft capture and explicit collection.
- Reflection Loop cannot execute commands, push to Obsidian, promote guidance,
  or own field validation state.
- Workbench v1 cannot persist or display sensitive artifact content without the
  privacy blocking contract.
- Review reports include reviewer identity, unavailable reviewers,
  degraded/fallback status, disagreements, and context completeness.
- Phase 1 has a test-first contract and a clear list of excluded work.

## Phase 1 Handoff

Phase 1 may start only after Phase 0 passes verification and AI review. Its
initial implementation scope should be the smallest useful contract slice:

```text
schema/state contract
→ privacy rejection fixtures
→ review-integrity report fixture
→ sidecar non-blocking behavior fixture
→ draft idempotency fixture
```

Workbench UI, File Drop, UI Reference & Spec Studio, Obsidian sync UI, promotion
review UI, and Session Monitor work are not Phase 1 implementation scope unless
they receive a separate scoped plan and approval.

Everything else remains deferred until the preceding slice is verified.
