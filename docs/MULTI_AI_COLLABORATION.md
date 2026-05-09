# Multi-AI Collaboration

This document defines the intended collaboration model for the ai-lab automation project.

## Goal

The goal of this project is not just to automate a single AI coding assistant.

The goal is to build a CLI-based development workflow where multiple AI agents can cooperate through a structured loop:

1. implement
2. verify
3. review
4. summarize
5. revise
6. re-check
7. present a commit candidate

The system should help AI agents work together while keeping the human user in control of final decisions.

## Current foundation

Current working pieces include:

- Codex as the primary implementation agent
- ./scripts/verify.sh as the fixed project verification command
- ./scripts/collect-review-context.sh for collecting review context
- ./scripts/make-review-prompts.sh for generating reviewer prompts
- Claude as the stable AI reviewer
- Gemini as an optional but currently disabled reviewer
- ./scripts/summarize-ai-reviews.sh for review result summarization
- ./scripts/review-gate.sh as the current final review gate
- templates/automation-base/ as the reusable automation template
- aiinit as the template installer command
- ./scripts/automation-doctor.sh as the repo-local automation readiness doctor
- workspace-scan as the workspace status scanner

## Current limitation

The current system is not yet a true multi-AI collaboration loop.

It is currently closer to:

- Codex implements
- verify.sh checks
- Claude reviews
- summary is generated
- human decides whether to commit

This is useful, but it is not enough.

A true collaboration loop requires reviewer feedback to be converted into follow-up implementation tasks and checked again.

## Intended agent roles

### Human user

The human user remains the final authority.

Responsibilities:

- define the goal
- approve or reject commits
- decide whether to continue, revise, or stop
- override AI suggestions when needed

The system must not commit without user approval.

### Codex

Codex is the primary implementation agent.

Responsibilities:

- make small scoped code or documentation changes
- orchestrate delegated child-agent lanes without claiming the active leader
  model changed mid-session
- use fast or lower-cost delegated lanes only for bounded lookup, scan, or
  synthesis tasks, not final authority
- follow repository instructions
- avoid unrelated edits
- run or respect the fixed verification command
- revise changes based on review findings

Codex should not claim completion if verification fails.

### Verification script

./scripts/verify.sh is the mechanical verifier.

Responsibilities:

- run deterministic checks
- fail loudly when the project is not valid
- provide a single command that both humans and AI agents can rely on

The verification script is project-specific.

### Claude

Claude is the current stable AI reviewer.

Responsibilities:

- review diffs
- catch logic, design, safety, and maintainability issues
- identify missing tests or weak verification
- produce a clear verdict

Claude is currently the default external reviewer.

### Gemini

Gemini is intended as a second reviewer.

Responsibilities:

- provide an independent review perspective
- catch issues Claude may miss
- challenge assumptions
- improve multi-agent confidence

Current status:

- implemented as an optional reviewer
- enabled by default when gemini is available
- disabled only with RUN_GEMINI_REVIEW=0
- unstable in non-interactive CLI usage

Gemini must not block the whole workflow when unavailable.

### Review summarizer

./scripts/summarize-ai-reviews.sh combines reviewer outputs.

Responsibilities:

- find latest review results
- classify reviewer verdicts
- produce a final summary
- identify whether the change can proceed, needs revision, is blocked, or needs manual review

The summarizer should eventually distinguish between:

- single-reviewer approval
- multi-reviewer approval
- reviewer disagreement
- incomplete review
- blocked review

## Target collaboration loop

The desired future loop is:

1. Human gives task
2. Codex implements scoped change
3. verify.sh runs
4. review context is collected
5. Claude reviews
6. Gemini reviews, if available
7. review results are summarized
8. findings are classified
9. if revision is needed, Codex receives a follow-up task
10. verify.sh runs again
11. reviewers re-check
12. final summary is generated
13. human approves or rejects commit

## Required future behavior

### Reviewer findings must become revision tasks

The system should convert review findings into a clear follow-up task for Codex.

Example:

Claude finding:
The script does not quote paths safely.

Generated Codex revision task:
Update the script to quote path variables safely. Keep the change scoped. Then run ./scripts/verify.sh.

### The loop should stop safely

The system should avoid endless revision cycles.

Possible limits:

- maximum 2 revision cycles by default
- stop immediately if verification fails repeatedly
- stop if reviewer findings are unclear or contradictory
- ask the human user before continuing beyond the limit

### Reviewer disagreement must be explicit

If Claude and Gemini disagree, the system should not hide it.

Possible result:

final_decision: review_manually
reason: reviewer_disagreement

### Incomplete multi-agent review must be explicit

If Gemini is unavailable, the system may still proceed, but the summary should say that multi-agent review was incomplete.

Possible result:

final_decision: proceed
review_coverage: single_reviewer
missing_reviewers:
  - gemini

## Known unresolved issues

### Gemini CLI context instability

Gemini is enabled by default, but its failures are still treated as context-dependent and non-blocking.

Observed problems include:

- non-interactive invocation instability
- agent/tool mode behavior
- unauthorized tool call attempts
- model capacity errors
- long hangs
- browser-auth prompts when credentials are unavailable

Current handling:

- Gemini is enabled by default
- Gemini can be disabled with RUN_GEMINI_REVIEW=0
- Gemini failures are captured instead of blocking the entire review gate
- large Gemini prompts switch to stdin mode to avoid command-line argument length limits
- Gemini has its own timeout via GEMINI_REVIEW_TIMEOUT_SECONDS
- reviewer timeouts use REVIEW_TIMEOUT_KILL_AFTER_SECONDS as a forced-kill grace period
- session, weekly, quota, or rate-limit failures disable that reviewer immediately
- other reviewer failures retry up to REVIEW_RETRY_LIMIT times before disabling that reviewer
- disabled reviewer state is stored under .omx/reviewer-state and announced on every run until RESET_DISABLED_AI_REVIEWERS=claude|gemini|all is used
- disabled reviewer markers include the source review run id, next action, and reset hint so recovery instructions remain explicit across later runs
- disabled reviewer perspectives are not injected into the remaining external reviewer prompt
- Codex/GPT fallback reviews run as separate degraded artifacts when reviewers are disabled, and the summary reports that coverage separately without counting it as independent external review coverage
- Codex fallback execution uses `codex exec` when available and can be disabled for diagnostics with RUN_CODEX_FALLBACK_REVIEW=0
- AI model routing is discovered at review-run start by `scripts/discover-ai-models.sh`; it writes `.omx/model-routing/latest.env` and `.omx/model-routing/latest.md`, then the runner applies provider-specific `--model` flags only for explicit overrides or opt-in auto routing when supported
- model routing is role-first: choose the role/capability first, then resolve it against the current local CLI/runtime/account surface
- model routing avoids dated hardcoded model names; use env overrides such as CLAUDE_REVIEW_ROLE, GEMINI_REVIEW_ROLE, CLAUDE_REVIEW_MODEL, GEMINI_REVIEW_MODEL, CODEX_ARCHITECT_REVIEW_MODEL, CODEX_TEST_REVIEW_MODEL, or CODEX_FALLBACK_MODEL when a specific current route should be forced
- provider docs are reference material only; local CLI support, account access, and OMX/Codex runtime metadata are the operational source of truth
- when model availability is inferred rather than verified, report it as inferred and fall back to provider default instead of presenting a guess as fact
- each review run writes a `review-run-*.md` manifest linking context, prompts, outputs, fallback artifacts, model routing, and disabled reviewer state
- long-running sessions should checkpoint durable decisions and use `docs/SESSION_QUALITY_PLAN.md` for memory, routing-cache, and token/context hygiene rules
- REVIEW_EXECUTION_MODE=external can move reviewer execution to an unrestricted interactive terminal
- external reviewer execution uses REVIEW_OUTPUT_MODE=tee by default so prompts and approval waits remain visible
- external reviewer execution uses SKIP_CONTEXT_GENERATION=1 by default so it reviews the already-prepared prompts
- external reviewer preparation shows disabled reviewers before stopping, because the generated runner shares `.omx/reviewer-state/`

Future work:

- keep validating reliable non-interactive Gemini invocation across authenticated and unauthenticated contexts
- keep validating strict timeout handling in real CLI contexts
- prevent tool/agent mode when used as reviewer
- classify Gemini absence as incomplete review coverage

### External reviewer lane

When API-key based bare/headless mode is not being used, the most stable workaround for reviewer network or runtime write restrictions is to prepare reviewer inputs in the agent-run context and execute reviewer CLIs from the user's unrestricted interactive terminal.

Use:

    REVIEW_EXECUTION_MODE=external ./scripts/review-gate.sh

The generated `.omx/external-review/run-reviewers-latest.sh` script resolves the repository root from its own location, runs Claude/Gemini reviews with visible `tee` output against the already-prepared prompts, and then summarizes the verdicts. Generated timeout/path values are defaults, so execution-time overrides such as `CLAUDE_REVIEW_TIMEOUT_SECONDS=600 .omx/external-review/run-reviewers-latest.sh` still work.

The generated runner shares `.omx/reviewer-state/` with normal review runs. If a reviewer is disabled, external preparation prints the disabled state and reset hint; reset the reviewer before running the external script if the interactive terminal should retry it.

### Codex fallback review

When an independent reviewer is disabled, Codex records separate fallback review artifacts:

- Claude disabled -> `codex-architect-review`
- Gemini disabled -> `codex-test-alternative-review`
- both disabled -> both fallback reviews are required

This fallback is explicitly marked degraded and informational-only. It reduces blind spots but does not upgrade coverage to `multi_reviewer`; summaries use `single_external_plus_codex_fallback` or `codex_only_degraded` to keep trust boundaries visible.

If Codex fallback cannot run, its artifact is marked skipped or failed and the summary stays blocked when no external reviewer produced a usable result.

`proceed_degraded` is an allowed review-gate success state only when the degraded trust level, missing reviewer state, and Codex fallback files are reported to the user.

### Session artifact management

Review context, prompts, model routing inventories, external runners, manifests, and results are ignored runtime artifacts under `.omx/`.

Review-gate and `automation-doctor.sh --fix` automatically archive old `.omx/review-results` files when retention thresholds are exceeded. Latest run evidence and referenced reviewer files remain active; older files move under `.omx/review-results/archive/`. Deletion requires the explicit `archive-omx-artifacts.sh --delete` option because review artifacts may be needed for handoff, audit, or debugging.

### Command group

The user-facing keyword `명령어` means: show the current automation, AI review, and recovery command group.

Current command group:

- `자동화 진단`: run `./scripts/automation-doctor.sh` to inspect automation readiness and suggested repairs.
- `자동화 수정`: run `./scripts/automation-doctor.sh --fix` to apply safe non-overwriting setup fixes.
- `부트스트랩 진단`: run `./scripts/bootstrap-ai-lab.sh` to inspect first-time ai-lab checkout setup.
- `부트스트랩 수정`: run `./scripts/bootstrap-ai-lab.sh --fix` to create safe ai-lab helper links and run doctor fixes.
- `초기화`: run `aiinit` inside a target git repository, or `aiinit /path/to/repo`, to install the automation template and run the installed doctor.
- `워크스페이스 스캔`: run `workspace-scan` to inspect repositories under `~/workspace`.
- `리뷰 상태`: inspect `.omx/reviewer-state/` and summarize which reviewers are disabled and why.
- `클로드 복구`: re-enable Claude review with `RESET_DISABLED_AI_REVIEWERS=claude`.
- `제미나이 복구`: re-enable Gemini review with `RESET_DISABLED_AI_REVIEWERS=gemini`.
- `AI 복구`: re-enable all disabled reviewers with `RESET_DISABLED_AI_REVIEWERS=all`.
- `외부 리뷰`: prepare external reviewer execution with `REVIEW_EXECUTION_MODE=external ./scripts/review-gate.sh`.
- `리뷰 게이트`: run `./scripts/review-gate.sh`.

Rule:

- Any future user-facing operational keyword for this review workflow belongs to the `명령어` group.
- When the user says `명령어`, list the full current group with purpose, command, and caveats.
- Do not treat these keywords as independent reviewer approvals; they are operator shortcuts only.

### OMX / Codex / Explore Harness environment issues

Current known symptoms:

- omx doctor may show an Explore Harness warning
- Codex CLI may hit EPERM in agent-run context
- the same commands may pass in the user's interactive terminal

Current interpretation:

- user interactive terminal success is the primary operational baseline
- agent-run failures are treated as environment-dependent
- Explore Harness warning is non-blocking for now

Future work:

- document exact reproduction conditions
- separate interactive-terminal diagnostics from agent-context diagnostics
- avoid depending on unstable agent-run behavior for the core workflow

## Roadmap Status

### Phase 1: Foundation

Status: complete.

Includes:

- scoped Codex work
- fixed verification command
- Claude review
- Gemini review by default when available
- review summary
- review gate
- reusable template
- automation doctor
- aiinit
- ai-lab bootstrap
- workspace scanning

### Phase 2: Multi-AI review clarity

Status: complete for the current generic automation scope.

Completed:

- Gemini absence or failure is explicit in summaries.
- single-reviewer and multi-reviewer approvals are distinguished.
- reviewer failures are classified and stored.
- reviewer disagreement does not silently proceed.
- disabled reviewer perspectives are no longer injected into the remaining reviewer prompt.
- Codex/GPT fallback reviews are separate degraded artifacts and do not count as independent approval.

### Phase 3: Revision loop

Status: deferred.

Possible future tasks:

1. generate Codex revision tasks from reviewer findings
2. run verification again after revision
3. run second review pass
4. limit revision cycles
5. present final human decision point

This is deferred until a real repeated-review need appears. Current practice is manual acceptance of reviewer findings followed by another verify/review-gate run.

### Phase 4: Real project application

Status: next non-generic stage.

Tasks:

1. apply the template to a real or sample Odoo customization repository
2. customize scripts/verify.sh
3. evaluate whether the collaboration loop works in realistic development tasks

### Phase 5: Clone/bootstrap packaging

Status: complete for first slice.

`./scripts/bootstrap-ai-lab.sh` now diagnoses first-time ai-lab checkout setup and can repair safe helper symlinks with `--fix`. Expand it only if a real first-time setup gap appears.
