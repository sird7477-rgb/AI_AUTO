# AI_AUTO Feedback Queue Regular Promotion Plan

Date: 2026-06-04
Status: complete; full verify/review-gate passed, queue resolution ready
Scope: open improvement items from `tools/feedback-collect`

## 1. Queue Snapshot

Open items found by:

```bash
tools/feedback-collect | awk -F'\t' 'NR==1 || $1=="open"'
```

| Repeat Key | Severity | Type | Source Queue | Summary |
| --- | --- | --- | --- | --- |
| `review-gate:targeted-recheck-after-finding` | high | improvement | `/mnt/z/JSJEON/Project_JW/99. odoo/01. A1/jw_dev/.omx/feedback/queue.jsonl` | Review-gate should support targeted finding recheck loops instead of rerunning whole-diff multi-part reviews after every single `request_changes` item. |
| `ui-verification:micro-plan-required-before-cdp` | high | failure_pattern | `/mnt/z/JSJEON/Project_JW/99. odoo/01. A1/jw_dev/.omx/feedback/queue.jsonl` | UI verification was collapsed into representative CDP smoke instead of a micro checklist for layout, click targets, data entry, alerts/errors, immediate sync, and business mapping. |

## 2. Validity Review

### `review-gate:targeted-recheck-after-finding`

Verdict: valid, high-value follow-up.

Why valid:

- It addresses repeated review-loop cost after a focused fix.
- It extends the already promoted `ST-P1-17` review finding revision loop instead of inventing a new review authority.
- It can stay bounded: target one accepted finding, require changed-file evidence, and escalate to full review when scope expands.

Risk:

- A targeted recheck can miss unrelated regressions if it is treated as final commit approval.

Required boundary:

- Targeted recheck is a loop accelerator, not a replacement for the final full verify/review gate unless the change is explicitly docs/spec-only and scoped by review policy.

Promotion candidate: `ST-P1-44`.

### `ui-verification:micro-plan-required-before-cdp`

Verdict: valid, high-value follow-up.

Why valid:

- It captures a real failure mode: UI/browser evidence can look green while user-specified micro requirements were never enumerated.
- It extends the already promoted `ST-P1-15` UI/browser QA evidence workflow.
- It aligns with the user's micro-step operating requirement and with existing visual/spec-alignment gates.

Risk:

- Over-prescribing CDP steps could create slow or credential-adjacent workflows.

Required boundary:

- The micro-plan is required before browser/CDP verification when the user requests detailed UI behavior verification; CDP remains optional and credential-equivalent. The plan can be satisfied by non-CDP evidence where appropriate.

Promotion candidate: `ST-P1-45`.

## 3. Regular Promotion Strategy

Promote in two independent micro-units.

1. `ST-P1-44`: targeted review finding recheck loop.
2. `ST-P1-45`: UI verification micro-plan before CDP/browser evidence.

Do not bundle implementation unless both touch the same narrow review-context surface after inspection. Keep each unit separately verifiable and separately resolvable in the feedback queue.

## 4. ST-P1-44 Execution Plan

Target outcome:

- A targeted recheck lane exists for one accepted reviewer finding after a focused fix.
- The lane produces explicit evidence of what was rechecked and why broader review was or was not required.

Likely touchpoints:

- `scripts/summarize-ai-reviews.sh`
- `scripts/run-ai-reviews.sh`
- `scripts/collect-review-context.sh`
- `scripts/test-review-summary.sh`
- `tests/*review*` if Python contracts are the cleaner local pattern
- `docs/MULTI_AI_COLLABORATION.md` or existing review workflow docs
- template copies only if a touched script/doc is template-owned

Micro-steps:

1. Inspect current review finding revision loop behavior and artifacts.
2. Define targeted recheck input shape: finding ID/key, original reviewer, accepted finding text, changed files, fix evidence, recheck question.
3. Add a fail-closed rule: if changed files exceed accepted finding scope, reviewer output is unclear, or verification failed, route to full review/manual review.
4. Add fixtures for:
   - one accepted finding, one changed file, targeted recheck allowed;
   - multiple unrelated changed files, targeted recheck rejected;
   - unclear reviewer output, manual review;
   - final full gate still required for implementation-affecting changes.
5. Update docs with the boundary: targeted recheck accelerates loops; it is not blanket approval.
6. Run targeted tests.
7. Run `./scripts/verify.sh`.
8. Run AI review gate with eligible reviewers.
9. Promote backlog row to `complete_contract`.
10. Mark the source queue item resolved with evidence.

Acceptance criteria:

- Targeted recheck cannot silently approve unrelated changes.
- Targeted recheck artifacts name the finding, file scope, verification evidence, and final route.
- Full review/manual review remains the fallback for scope expansion or ambiguous reviewer output.

## 5. ST-P1-45 Execution Plan

Target outcome:

- UI/browser verification requires a micro-plan before CDP/browser evidence when the user asks for detailed UI behavior validation.
- Representative smoke cannot satisfy detailed UI verification unless every requested micro-check is enumerated and mapped to evidence.

Likely touchpoints:

- `scripts/self_demo_contracts.py`
- `scripts/collect-review-context.sh`
- `tests/test_browser_qa_context.py`
- `docs/UI_COMPLETION.md`
- `docs/CHROME_CDP_ACCESS.md` only if credential boundary wording needs a narrow clarification
- template copies only if a touched script/doc is template-owned

Micro-steps:

1. Inspect current `ST-P1-15` browser QA evidence audit and contract tests.
2. Define UI verification micro-plan schema:
   - layout/section placement;
   - click target/button location;
   - input value handling;
   - alert/error behavior;
   - immediate sync/update behavior;
   - business mapping or downstream document mapping;
   - evidence type per item.
3. Add a rule: when user explicitly asks for detailed UI verification, a representative smoke flow is insufficient unless it maps to each requested micro-check.
4. Keep CDP optional: if CDP is used, existing credential-equivalent boundary still applies; if not, screenshot/manual/test evidence can satisfy the row.
5. Add fixtures for:
   - detailed UI request without micro-plan: attention/fail contract;
   - smoke-only evidence with missing click/layout rows: attention/fail contract;
   - complete micro-plan with non-CDP evidence: pass;
   - CDP evidence without credential boundary: existing CDP block still applies.
6. Update docs with micro-plan-before-browser verification wording.
7. Run targeted tests.
8. Run `./scripts/verify.sh`.
9. Run AI review gate with eligible reviewers.
10. Promote backlog row to `complete_contract`.
11. Mark the source queue item resolved with evidence.

Acceptance criteria:

- A detailed UI verification request cannot be collapsed into generic smoke evidence.
- The micro-plan is evidence-mapped and checkable.
- CDP/browser access remains credential-bounded and optional, not a new default runtime.

## 6. Verification And Review Gate

For each micro-unit:

1. Run focused contract/tests for the touched surface.
2. Run `./scripts/verify.sh`.
3. Run AI reviewer gate.
4. Require unanimous eligible approval before completion.
5. If Claude remains disabled, report reviewer degradation explicitly and follow the repo's current principal/substitute policy rather than claiming full reviewer unanimity.

## 7. Queue Resolution Rule

Do not mark either queue item resolved until:

- implementation exists;
- tests and `verify.sh` pass;
- AI review gate is accepted under the current reviewer eligibility policy;
- `plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md` row is promoted to `complete_contract`;
- queue status records `status_note`, `status_source`, `resolved_at`, and `status_updated_at`.

Queue resolution path: use `tools/feedback-resolve` with `--write` after the
full verification/review evidence exists. The helper is dry-run by default,
discovers the same queues as `feedback-collect`, refuses unknown repeat keys,
and leaves already-resolved items unchanged.

## 8. Implementation Evidence

Promotion status as of 2026-06-04:

| Item | Promotion evidence | Targeted verification |
| --- | --- | --- |
| `ST-P1-20` | `domain_pack_retrospective_policy` regularizes project-closeout-only feedback and reusable/project-specific split. | `tests/test_self_demo_contracts.py` |
| `ST-P1-33` | `guidance_stage2_consolidation_policy` keeps broad compression user-request/report-gated and blocks low-ROI edits. | `tests/test_self_demo_contracts.py` |
| `ST-P1-35` | `run-ai-reviews.sh` reports reviewer first-pass read-only posture; contract blocks retry privilege drift. | `tests/test_self_demo_contracts.py` |
| `ST-P1-43` | `tools/feedback-resolve` added and wired into install/bootstrap/doctor/global docs/verify. | `scripts/verify.sh` feedback-resolve fixture |
| `ST-P1-44` | Review revision tasks include targeted-recheck metadata and fail closed when scope expands. | `scripts/test-review-summary.sh` |
| `ST-P1-45` | Browser QA context requires a micro-plan for detailed UI behavior requests. | `tests/test_browser_qa_context.py` |
| Odoo.sh KB | KB files are promoted, source-indexed, and covered by a scoped validator before Obsidian copy. | `scripts/validate-odoo-kb.py` |

Final gate evidence:

- `./scripts/verify.sh`: passed; 185 pytest cases, review-summary fixtures,
  KB validator, global helper fixtures, template sync checks, bootstrap/doctor,
  and Docker API smoke completed. Non-blocking warning: primary guidance
  markdown line budget remains above the warning threshold.
- `./scripts/review-gate.sh`: passed at `2026-06-04T23:15:06+09:00` with
  decision `proceed`, trust `normal`, coverage `principal_rotation`; Gemini and
  Codex reviewer lanes both approved with notes, untracked/phase/persona guards
  clear.

## 9. Non-Goals

- Do not add a persistent review daemon.
- Do not make targeted recheck a universal replacement for full review.
- Do not add browser/CDP execution as a default requirement.
- Do not promote Odoo-specific UI details into generic AI_AUTO guidance.
- Do not edit unrelated guidance surfaces while the current Odoo KB/guidance work is separated.
