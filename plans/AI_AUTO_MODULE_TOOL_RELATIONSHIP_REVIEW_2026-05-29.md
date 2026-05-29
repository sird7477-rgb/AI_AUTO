# AI_AUTO Module And Tool Relationship Review - 2026-05-29

## Purpose

This report re-checks the relationships between AI_AUTO modules and tools after
the later-gated planning work for `ST-P1-07`, `ST-P1-08`, and `ST-P1-09`.

Scope is read-only relationship verification. This report does not activate the
three TODOs, implement auto-push, change update notice behavior, or grant
Obsidian, feedback queues, or AI reviewers new authority.

## Review Method

Evidence used:

- file and symbol scans across `tools/`, `scripts/`, `docs/`,
  `templates/automation-base/`, and `plans/`
- current plan artifacts for persona/review-gate, Obsidian auto-push, and update
  visibility
- existing AI council and review-gate artifacts from this Ralph branch

Reviewer rule for this branch:

- Claude should participate for small-or-larger grouped work when available
- if Claude is disabled because of quota or usage limit, GPT architect review is
  accepted as Claude-equivalent for the unanimity check
- the final state must still report degraded trust when Claude is substituted

## Relationship Map

### MR-1 Review Gate Chain

Primary chain:

```text
scripts/review-gate.sh
  -> scripts/verify.sh
  -> scripts/run-ai-reviews.sh
  -> scripts/collect-review-context.sh
  -> scripts/make-review-prompts.sh
  -> scripts/summarize-ai-reviews.sh
  -> scripts/archive-omx-artifacts.sh
  -> scripts/write-session-checkpoint.sh
  -> scripts/capture-knowledge-drafts.py
```

Supporting surfaces:

- `scripts/discover-ai-models.sh`
- `scripts/ai-runtime-adapter.sh`
- `.omx/reviewer-state`
- `.omx/review-prompts`
- `.omx/review-results`

Relationship finding:

- The review-gate chain is the correct authority for commit-candidate review.
- The proposed persona lens classifier must feed policy labels into this chain;
  it must not become a separate review authority.
- Large untracked planning artifacts can exceed practical review prompt context,
  so large plans need either included untracked content with enough budget or
  narrower per-file/per-unit AI council reviews.

Risk:

- `REVIEW_INCLUDE_UNTRACKED_CONTENT=1` is the correct control for untracked
  plan contents. Confusing it with unrelated environment names can affect other
  verification paths.
- When Docker or external reviewer access is sandbox-sensitive, the exact
  prefixed review command matters.

### MR-2 Knowledge And Obsidian Chain

Primary chain:

```text
scripts/capture-knowledge-drafts.py
  -> .omx/knowledge/drafts/*.md
tools/knowledge-collect
  -> scripts/knowledge-notes.py validate
  -> configured vault/AI_AUTO
  -> scripts/knowledge-notes.py index
```

Supporting docs:

- `docs/OBSIDIAN_INTEGRATION.md`
- template copy under `templates/automation-base/docs/OBSIDIAN_INTEGRATION.md`

Relationship finding:

- Obsidian remains a durable knowledge sink, not a workflow authority.
- `ST-P1-08` should reuse `knowledge-collect`; it should not create a second
  validator or bypass `scripts/knowledge-notes.py`.
- Registry-inclusive collection is acceptable for AI_AUTO home preflight, but
  mounted-drive or whole-workspace crawling is outside the safe boundary.

Risk:

- Vault writes cross the filesystem/sandbox boundary and must stay explicit,
  configured, idempotent, and warning-only on failure.
- `local_private`, disallowed `sync_class`, symlink escape, and `.omx` vault
  guards must remain stronger than auto-push convenience.

### MR-3 Registry And Workspace Chain

Primary chain:

```text
tools/ai-register
  -> ~/.local/state/ai-auto/projects.tsv
tools/workspace-scan
  -> registered projects and workspace repo scan
tools/feedback-collect
  -> registry/workspace status
tools/knowledge-collect --include-registry
  -> registered project knowledge drafts
```

Relationship finding:

- Registry is the right boundary for broad AI_AUTO-home knowledge checks.
- `workspace-scan` is useful for manual workspace health, but it should not be
  added to ordinary AI startup paths.

Risk:

- Auto-push must not silently turn registry review into an expensive workspace
  crawl.
- Registry pruning and moved projects remain explicit maintenance actions.

### MR-4 Template And Global Helper Chain

Primary chain:

```text
scripts/install-automation-template.sh
  -> templates/automation-base/*
scripts/install-global-files.sh
  -> ~/bin helpers
  -> ~/.config/ai-lab/AI_AUTO.sh
  -> optional codex drift notice
tools/ai-auto-template-status
  -> AI_AUTO_TEMPLATE_VERSION
  -> managed-file ownership and patch policy
```

Supporting docs:

- `docs/GLOBAL_TOOLS.md`
- `docs/NEW_PROJECT_GUIDE.md`
- `docs/CODEX_SHADOWING_DESIGN.md`

Relationship finding:

- `ST-P1-09` belongs on the existing opt-in drift notice/status path.
- The status provider should remain read-only and should not call
  `--record-feedback` during ordinary startup notice checks.
- Any template-owned file change must preserve template parity, version, and
  patch notes.

Risk:

- Global shell wrappers can accidentally shadow the real AI command. Every
  notice path must pass through with original arguments even on status failure.
- Startup latency must be stricter here than for Obsidian auto-push.

### MR-5 Rebuild And Split Planning Chain

Primary chain:

```text
tools/ai-rebuild-plan
  -> tools/ai-auto-template-status
  -> refactor/split evidence
tools/ai-split-plan
tools/ai-split-dry-run
tools/ai-split-apply
tools/ai-python-split
tools/ai-plan-review
```

Relationship finding:

- Rebuild planning is read-only by default and should remain separate from the
  three later-gated TODOs.
- Split/apply tools are implementation surfaces and require explicit execution
  approval tied to an approved scoped plan.

Risk:

- Persona/review-gate improvements should classify rebuild/split work more
  accurately, but must not auto-promote rebuild execution.

### MR-6 State, Feedback, And Memory Chain

Primary chain:

```text
scripts/record-feedback.sh
scripts/resolve-feedback.sh
tools/feedback-collect
scripts/record-project-memory.sh
scripts/write-session-checkpoint.sh
.omx/state/*
.omx/project-memory.json
```

Relationship finding:

- Feedback and memory are advisory records. They do not replace verification,
  review-gate, or user approval for commit/push.
- Review-gate checkpoints and knowledge draft capture are useful side effects,
  but their failures should be reported with clear authority boundaries.

Risk:

- Auto status notice must not write feedback automatically because that would
  turn a display path into a queue mutation path.

### MR-7 Documentation And Template Parity Chain

Primary chain:

```text
docs/*
templates/automation-base/docs/*
templates/automation-base/AI_AUTO_TEMPLATE_VERSION
templates/automation-base/docs/PATCH_NOTES.md
scripts/verify.sh
```

Relationship finding:

- The repo already enforces documentation and template consistency through
  verification.
- Plan-only work does not require template version changes unless template files
  are edited.

Risk:

- Broad policy-document rewrites can trigger guidance bloat. Keep later
  implementation docs minimal and tied to behavior that exists.

## Micro Relationship Work Units

| Unit | Group | Relationship | Check | Review Requirement |
| --- | --- | --- | --- | --- |
| MR-1 | Medium | review-gate, review context, AI reviewers | Confirm classifier output is consumed by gate without replacing reviewers. | Claude or GPT-equivalent plus review-gate. |
| MR-2 | Medium | knowledge capture, collect, validate, vault | Confirm auto-push uses existing validator and registry only. | Claude or GPT-equivalent plus targeted fixtures. |
| MR-3 | Small | registry, workspace scan, feedback collect | Confirm registry scope does not become workspace crawl. | Targeted static/fixture check; Claude if available. |
| MR-4 | Medium | global helper, template status, drift notice | Confirm read-only status, pass-through, timeout, and no feedback write. | Claude or GPT-equivalent plus verify. |
| MR-5 | Small | rebuild and split planning | Confirm no auto execution or TODO promotion. | Targeted static check; Claude if available. |
| MR-6 | Small | state, feedback, memory, checkpoint | Confirm records stay advisory and non-authoritative. | Targeted static/doc check; Claude if available. |
| MR-7 | Medium | docs/template parity | Confirm template-owned edits update version and patch notes. | Claude or GPT-equivalent plus verify. |

Loop rule:

1. inspect one micro relationship
2. record evidence and a risk decision
3. run the narrowest useful check
4. escalate to `./scripts/verify.sh` when a medium group or template/script path
   is touched
5. run review-gate before commit-candidate reporting
6. if Claude is unavailable due usage limit, use GPT architect review as the
   accepted substitute and label the result degraded

## AI Council Evidence

Existing AI council/review artifacts for this branch:

- `.omx/artifacts/gemini-review-the-ai-auto-later-gated-planning-artifacts-for-st-p1--2026-05-29T10-40-50-229Z.md`
- `.omx/review-results/review-verdict-20260529T202327.md`
- `.omx/review-results/gemini-review-20260529T203135.md`
- `.omx/review-results/codex-architect-fallback-20260529T203135.md`
- `.omx/review-results/review-verdict-20260529T203232.md`

Council interpretation:

- Gemini approved the later-gated planning direction with notes, including
  latency budgets, registry-only discovery, idempotent vault failures, explicit
  exclusions, throttle behavior, and degraded reviewer reporting.
- A later monolithic review-gate run produced a revise decision because plan
  context was truncated for Gemini, not because the relationship design was
  rejected after full inspection.
- Codex architect fallback inspected the relevant local files directly and
  approved with notes.
- Claude is currently unavailable because of usage limit state. Under the
  user's updated rule, GPT architect review can satisfy the Claude lane as a
  degraded substitute.

## Findings

No blocking module/tool relationship mismatch was found in this read-only pass.

The main integration risks are:

- large untracked plan artifacts can exceed monolithic AI review context
- update notice and knowledge auto-push must remain non-blocking startup
  preflights
- Obsidian, feedback queues, and memory files must not become approval or
  completion authorities
- template-owned changes must continue to update template version and patch
  notes
- Claude unavailability must be reported as degraded, even when GPT substitute
  review is accepted

## Risk Levels

| Level | Risk | Related Areas | Reason | Control |
| --- | --- | --- | --- | --- |
| High | Authority leakage from Obsidian, feedback, memory, or reviewer artifacts | MR-1, MR-2, MR-6 | If advisory artifacts are treated as approval, completion, or commit authority, AI_AUTO can make false completion claims. | Keep `verify.sh`, `review-gate.sh`, and explicit user approval as the only completion/commit/push authorities. |
| High | Startup preflight blocks the primary AI invocation | MR-2, MR-4 | `ST-P1-08` and `ST-P1-09` run near AI startup; blocking behavior would directly harm daily use. | Hard timeout, warning-only failure, pass-through tests, and no daemon/background mutation. |
| High | Vault write boundary is crossed unsafely | MR-2 | Auto-push touches external vault paths and can cross sandbox or mounted-drive boundaries. | Require explicit vault config, preserve sync_class/symlink/.omx guards, keep write failures idempotent and non-blocking. |
| Medium | Large untracked planning artifacts exceed monolithic review context | MR-1 | Single-context AI review can omit or misread plan contents, producing false `revise` or false confidence. | Use split-review or focused per-file AI council reviews; document the full untracked review command recipe. |
| Medium | Registry-inclusive scan expands into workspace or mounted-drive crawl | MR-2, MR-3 | Broad discovery during startup can become slow, noisy, or unsafe. | Use registry plus current repo only; keep `workspace-scan` manual, not startup-bound. |
| Medium | Template/global-helper parity drift | MR-4, MR-7 | Shell helper or template-owned changes can diverge from downstream template behavior. | Update template version and patch notes whenever template-owned files change; run template sync checks. |
| Medium | Claude unavailable but reported as normal unanimity | MR-1 | Missing independent reviewer coverage can be hidden if degraded state is not reported. | Treat GPT reviewer substitution as valid only under usage/quota disablement and always label trust as degraded. |
| Low | Rebuild/split planning is accidentally implied as execution approval | MR-5 | Current artifacts are plan-only, but adjacent tools include write-capable apply paths. | Keep rebuild/split execution behind explicit approved scoped plan and post-apply verification. |
| Low | Guidance bloat from broad policy-document edits | MR-7 | Later implementation could over-expand docs while fixing narrow behavior. | Prefer behavior tests and minimal docs tied to implemented surfaces. |
| Low | Status notice records feedback automatically | MR-4, MR-6 | This would mutate queues from a display-only startup path, but the plan already rejects it. | Keep `ai-auto-template-status --record-feedback` out of ordinary startup notice flow. |

Risk summary:

- High: 3
- Medium: 4
- Low: 3

## Risk Clearance Evidence

The risks above are cleared as contract-backed TODOs by
`scripts/self_demo_contracts.py` and `tests/test_self_demo_contracts.py`.

| Cleared TODO | Covered Risks | Contract Evidence |
| --- | --- | --- |
| `ST-P1-10` | authority leakage, blocking startup preflights, unsafe vault writes | `completion_authority`, `startup_preflight_boundary`, `vault_write_boundary` |
| `ST-P1-11` | review context truncation, registry scan expansion, template/helper parity drift, degraded reviewer reporting | `review_context_boundary`, `registry_scan_boundary`, `template_parity_boundary`, `review_gate_short_summary` |
| `ST-P1-12` | rebuild/split execution-approval ambiguity, guidance bloat, display-only feedback mutation | `test_rebuild_plan_reports_read_only_boundary_without_modifying_target`, `guidance_minimality_boundary`, `status_notice_boundary` |

Focused verification:

```text
.venv/bin/python -m pytest tests/test_self_demo_contracts.py -q
```

Expected result:

```text
29 passed
```

## Review Command Recipe

Use split review when material untracked plans are large enough for single
review context to be misread or truncated:

```bash
env REVIEW_INCLUDE_UNTRACKED_CONTENT=1 \
  REVIEW_UNTRACKED_MANUAL_REVIEWED=1 \
  MAX_UNTRACKED_BYTES=200000 \
  REVIEW_CONTEXT_MAX_BYTES=50000 \
  REVIEW_CONTEXT_SPLIT_BYTES=50000 \
  REVIEW_CONTEXT_SPLIT_LINES=500 \
  ./scripts/review-gate.sh
```

This keeps the untracked artifact guard explicit, includes untracked text up to
the configured byte limit, and forces split-review synthesis rather than relying
on a monolithic prompt.

## Recommended Follow-Ups

Keep these as later-gated planning items unless separately approved:

- improve review-context chunking for large planning artifacts if split-review
  continues to require manual environment tuning
- add `--summary-json` surfaces where startup notices or auto-push wrappers need
  stable machine-readable status
- add small fixtures for registry-only knowledge scan, status notice timeout,
  and wrapper pass-through behavior

## Current Decision

The original three non-active TODOs are promoted to `complete_contract` by the
non-active promotion Ralph pass: `ST-P1-07` through persona lens contracts,
`ST-P1-08` through Obsidian auto-push dry-run/approval contracts, and `ST-P1-09`
through update visibility contracts. Later runtime wiring must still be done in
micro units, keep authority inside existing verification/review gates, and use
degraded GPT substitute review only when Claude is unavailable due quota or
usage limit.
