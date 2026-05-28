# AI_AUTO Structural Audit Plan

## Language Note

This artifact is written in English to preserve continuity with the existing
GStack and structural-audit input artifacts used in this Ralph branch. Korean
remains the default for new strategy, architecture, and operational-judgment
documents; field names, state values, paths, and schema labels stay in English
where they are easier to reuse mechanically.

## Purpose

This plan defines a read-only structural audit before adopting additional small
tools. The audit slices AI_AUTO by authority, state, verification, write
boundary, sidecar behavior, and template lifecycle instead of treating the repo
as one large automation surface.

Primary goals:

- identify structural weak points and improvement candidates
- separate documentation/test/process fixes from tool-worthy gaps
- classify any small-tool adoption as advisory, fail-open, or fail-closed
- prevent new tools from becoming hidden authority or unnecessary friction

This plan does not approve implementation, new required gates, runtime hooks,
Obsidian push, worktree orchestration, or write-capable tool adoption.

## Current Ralph Scope

This Ralph branch executes only the current priority TODO items 1-5:

1. keep the structural audit index commit/push-ready
2. run the structural audit as read-only documentation analysis
3. materialize the weakness backlog
4. define the self-demo validation design
5. reflect GStack benchmark follow-up without runtime adoption

Explicitly deferred:

- item 6: small-tool adoption review, candidate-tool evaluation, helper wiring,
  or implementation
- item 7: guidance-budget warning cleanup or guidance consolidation

For this branch, references to small tools remain background design material
only. They do not authorize candidate discovery, adoption scoring, new gates, or
implementation.

## Operating Rules

- Audit is read-only by default.
- Use subagents for independent slice review when it improves coverage.
- Keep findings evidence-grounded with file references.
- Do not turn warnings into blockers without a repeated failure pattern or a
  high-risk boundary.
- Default new small tools to `advisory + read-only + fail-open`.
- Promote a tool to fail-closed only for approved high-risk paths such as
  rebuild-run, migration, production, security, real-data, or domain-critical
  execution.

## Micro Slices

### 1. Policy Authority

Scope:

- `AGENTS.md`
- `docs/WORKFLOW.md`
- `docs/AUTOMATION_OPERATING_POLICY.md`

Checks:

- execution approval boundaries
- plan-first triggers
- verify/review completion gates
- Korean completion-report rules
- contradictions between root guidance and linked docs

Likely weaknesses:

- guidance bloat
- duplicated rules
- stale or conflicting authority language

Stop condition:

- Stop if a contradiction changes execution authority, approval boundary, or
  completion criteria.

### 2. Model And Delegation

Scope:

- `docs/AI_MODEL_ROUTING.md`
- subagent and reviewer routing rules

Checks:

- role-first routing
- no stale hardcoded model assumptions
- leader vs subagent vs external reviewer responsibilities
- degraded fallback reporting

Likely weaknesses:

- delegated lanes accidentally owning final claims
- Codex fallback being mistaken for independent Claude/Gemini approval

Stop condition:

- Stop if local runtime evidence is required but absent, or if degraded review
  can be reported as normal approval.

### 3. Global Tools And Install Surface

Scope:

- `docs/GLOBAL_TOOLS.md`
- `tools/`
- `scripts/install-global-files.sh`
- `scripts/bootstrap-ai-lab.sh`
- `scripts/automation-doctor.sh`

Checks:

- tool capability class: read-only, write-capable, external, credentialed
- symlink repair safety
- non-symlink conflict handling
- shell profile mutation boundaries
- global helper docs/install/doctor parity

Likely weaknesses:

- duplicated helper lists drifting
- install-time side effects being under-documented
- new helper wiring missing in one surface

Stop condition:

- Stop before any real shell-profile write probe unless using an isolated fake
  HOME or a separately approved install action.

### 4. Template Lifecycle

Scope:

- `templates/automation-base/`
- `scripts/install-automation-template.sh`
- `tools/ai-auto-template-status`

Checks:

- managed-file manifest parity
- template-owned vs hybrid review-merge vs project-owned inspect-only behavior
- patch-enabled branch gate
- template version and patch-note coupling

Likely weaknesses:

- duplicated manifests
- semantic drift in hybrid files
- template patch notes missing user-visible changes

Stop condition:

- Stop if a path could overwrite project-owned files or if template versioning
  changes without matching patch notes.

### 5. Verification Gate

Scope:

- `scripts/verify.sh`
- `tests/`
- template verify examples

Checks:

- exact checks performed by `verify.sh`
- required vs advisory vs template-only checks
- temporary directories and cleanup
- Docker smoke behavior
- placeholder or weak verify detection

Likely weaknesses:

- oversized shell fixture surface
- weak target-project verify scripts passing existence checks
- behavior coverage without coverage visibility

Stop condition:

- Stop if a failure can be hidden by a placeholder/weak verify path or if a new
  check would block unrelated small changes without evidence.

### 6. Review Gate And Context Integrity

Scope:

- `scripts/review-gate.sh`
- `scripts/run-ai-reviews.sh`
- `scripts/collect-review-context.sh`
- `scripts/summarize-ai-reviews.sh`

Checks:

- review context collection and truncation behavior
- split manifest and synthesis requirements
- disabled reviewer state
- Codex fallback boundaries
- final verdict rules

Likely weaknesses:

- split/compressed context approval without complete synthesis
- disabled reviewer state causing accidental degraded trust
- prompt output parsing fragility

Stop condition:

- Stop if compressed or split context can produce approval without explicit
  complete synthesis.

### 7. Reflection, Feedback, And Knowledge Sidecars

Scope:

- `plans/AI_AUTO_REFLECTION_LOOP_V1*.md`
- `scripts/reflection_contracts.py`
- `scripts/capture-knowledge-drafts.py`
- `scripts/knowledge-notes.py`
- `tools/knowledge-collect`
- `scripts/record-feedback.sh`
- `scripts/resolve-feedback.sh`

Checks:

- sidecar outputs cannot own execution, promotion, completion, or field state
- privacy redaction and raw artifact blocking
- Obsidian push remains explicit and gated
- knowledge drafts remain local/private until reviewed

Likely weaknesses:

- `.omx` sidecar authority leakage
- draft promotion without review-gate evidence
- pattern-based secret redaction misses domain-specific sensitive values

Stop condition:

- Stop if raw `.omx` data, secrets, private paths, or drafts can become durable
  guidance or Obsidian output without explicit review evidence.

### 8. Rebuild And Split Helpers

Scope:

- `tools/ai-rebuild-plan`
- `tools/ai-refactor-scan`
- `tools/ai-split-plan`
- `tools/ai-split-dry-run`
- `tools/ai-split-apply`
- `tools/ai-python-split`

Checks:

- plan/run separation
- dry-run before apply
- approval fields
- rollback path
- domain-pack advisory status

Likely weaknesses:

- read-only plan output being treated as execution approval
- apply-capable paths expanding beyond approved symbol movement
- missing behavior-locking tests before structural edits

Stop condition:

- Stop before write-capable split/apply paths unless an approved scoped
  execution plan and rollback evidence exist.

### 9. GStack And Small-Tool Adoption

Scope:

- `plans/GSTACK_BENCHMARK.md`
- `plans/GSTACK_BENCHMARK_RALPH_DEEP_DIVE.md`
- `docs/GSTACK_ADOPTION_CHECKLISTS.md`
- `scripts/gstack_benchmark_contracts.py`
- `tools/ai-gstack-contract`

Checks:

- benchmark contracts remain read-only
- no GStack runtime installation authority
- no permanent persona roster
- no worktree, browser-state, release, deploy, or Obsidian side effects
- candidate small tools mapped to specific weakness categories

Likely weaknesses:

- benchmark language becoming runtime authority
- small tools over-tightening routine work
- persona/review lenses becoming mandatory overhead

Stop condition:

- Stop if a small tool would become a required gate before proving repeated
  value and acceptable false-positive rate.

### 10. Guidance Budget And Duplication

Scope:

- `scripts/doc-budget.sh`
- `scripts/guidance-duplicate-report.sh`
- core guidance docs and template copies

Checks:

- warning vs failure semantics
- stage-2 duplicate report trigger
- guidance details split into linked docs instead of `AGENTS.md`
- template/current doc parity where required

Likely weaknesses:

- line-count warning becoming edit pressure
- duplicate guidance diverging across root/template docs
- fixing volume without fixing authority clarity

Stop condition:

- Stop if cleanup would change authority semantics without a separate plan and
  user approval.

## Structural Audit Index

Current index:

- plan: `plans/AI_AUTO_STRUCTURAL_AUDIT_PLAN.md`
- execution ledger: `plans/AI_AUTO_STRUCTURAL_AUDIT_EXECUTION.md`
- weakness backlog: `plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md`
- Ralph context: `.omx/context/priority-todo-ralph-20260528T092238Z.md`

Required index fields for each slice:

| Field | Meaning |
| --- | --- |
| Slice | Micro-slice name and number. |
| Status | `pending`, `reviewing`, `pass`, `blocked`, or `deferred`. |
| Evidence artifact | File or command output that supports the status. |
| Blocker count | Number of unresolved blocker findings. |
| Deferred items | Excluded work such as small-tool adoption or budget cleanup. |
| Next action | Next safe step, or `none` when complete. |
| Owner lane | Leader, architect, test-engineer, critic, or other bounded reviewer. |
| Updated | Date or run identifier of the latest status change. |

## Read-Only Audit Output Schema

Every micro-slice review must record:

| Field | Required Content |
| --- | --- |
| Slice | The exact micro-slice under review. |
| Files inspected | Concrete local files or artifacts read. |
| Commands run | Read-only commands or `none`. |
| Finding status | Finding list or explicit no-finding statement. |
| Evidence | File references, command output, or reviewer artifact. |
| Stop condition | Whether the slice stop condition was hit. |
| Uncertainty | Known gaps, missing evidence, or deferred checks. |
| Verdict | `pass`, `pass_with_notes`, `blocked`, or `deferred`. |

## Finding Taxonomy

Use these levels:

- `blocker`: could cause unsafe write, wrong authority, false completion, or
  project-owned overwrite
- `high`: likely repeated failure or broad workflow drift
- `medium`: meaningful reliability or maintainability risk
- `low`: local polish or documentation clarity issue
- `observation`: useful context, no action yet

For every finding, record:

- slice
- evidence
- failure mode
- likely frequency
- blast radius
- candidate fix type: delete, document, test, refactor, small tool, or defer
- recommended gate: advisory, verify, review-gate, install, or template

## Small-Tool Adoption Matrix

Evaluate each candidate tool with:

| Field | Required Question |
| --- | --- |
| Purpose | What repeated failure or friction does it reduce? |
| Authority | Is it read-only, write-capable, external, or credentialed? |
| Failure Mode | Should it fail-open, fail-closed, or report-only? |
| Placement | Advisory, verify, review-gate, install, template, or manual? |
| Evidence | Which tests or fixtures prove the boundary? |
| Cost | Runtime, false positives, extra user prompts, or guidance bloat? |
| Rollback | How can it be disabled or bypassed safely? |

Default decision:

- `advisory`: first landing for most small tools
- `verify`: only after low false-positive evidence
- `review-gate`: only for shared automation or high-blast-radius changes
- `fail-closed`: only for approved high-risk execution paths

This matrix is deferred for the current Ralph branch. It remains here as the
future item 6 evaluation surface, not as part of the active execution order.

## Self-Demo Validation Design

Purpose:

- make AI_AUTO module, helper, script, template, and guidance upgrades easier to
  validate without asking the user to manually inspect every behavior
- capture representative evidence before an upgrade is called ready
- keep demo evidence below the authority of `verify` and `review-gate`

Default rule:

- self-demo is advisory and fail-open until a later scoped plan promotes a
  specific high-risk path
- demo success cannot replace targeted tests, `./scripts/verify.sh`, or
  `./scripts/review-gate.sh`

Required demo record fields:

| Field | Required Content |
| --- | --- |
| Change class | Module, script, helper, template, or guidance. |
| Scenario | Representative user action or workflow. |
| Command or simulation | Exact command, temp-repo/fake-HOME run, or static simulation. |
| Expected behavior | User-visible result the demo is proving. |
| Evidence | Output summary, artifact path, fixture, or screenshot if applicable. |
| Side effects | Files, shell profile, Docker, browser, network, or external state touched. |
| Cleanup state | How side effects were cleaned or why none exist. |
| Manual checks | Remaining checks the user or later field run must perform. |
| Demo verdict | `pass`, `fail`, `degraded`, or `not_applicable`. |

## Execution Order

Current Ralph branch:

1. Confirm the structural audit index and artifact paths.
2. Run micro-slice read-only analysis with reviewer verdicts.
3. Classify findings with the taxonomy above.
4. Materialize the weakness backlog grouped by risk and dependency.
5. Add self-demo validation design and acceptance fields.
6. Reflect GStack benchmark follow-up as documentation-only, with no runtime
   adoption.
7. Verify and review-gate the documentation artifacts.

Deferred future branch:

1. Identify candidate small tools.
2. Evaluate candidate tools with the adoption matrix.
3. Request separate approval before any write-capable implementation.

## Subagent Lanes

Suggested lanes:

- `architect`: authority, template, review-gate, sidecar boundaries
- `test-engineer`: verify coverage, fixture shape, false-positive risk
- `explore`: file/symbol mapping and duplicated manifest discovery
- `critic`: scope creep, over-tightening, and authority leakage review
- `security-review`: privacy, credential, Obsidian, browser-state, and
  production-adjacent boundaries

Use at most six concurrent lanes and keep each lane bounded to one or two
micro-slices.

## Completion Criteria

The structural audit planning phase is complete when:

- all slices have a scope, checks, likely weakness category, and stop condition
- small-tool adoption criteria are explicit
- subagent lanes are defined
- no implementation is implied by the audit plan itself
- current Ralph scope and deferred items are explicit

The current Ralph execution branch is complete only when:

- each active slice has evidence-backed findings or a no-finding statement
- every finding has a severity and recommended fix type
- weakness backlog and self-demo design artifacts exist
- GStack follow-up remains documentation-only and does not approve runtime
  adoption
- item 6 small-tool adoption and item 7 guidance-budget cleanup remain deferred
- high-risk or write-capable follow-up work is separated into its own plan
