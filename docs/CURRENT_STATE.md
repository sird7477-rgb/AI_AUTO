# Current State

This document summarizes the current state of the ai-lab automation project.

## Purpose

ai-lab is a testbed for building a CLI-based AI development automation workflow.

The current goal is to make a reliable workflow where:

1. Codex performs small scoped changes.
2. The project runs a fixed verification command.
3. AI review context is collected.
4. Claude reviews the change.
5. Gemini runs as an optional second reviewer by default when available.
6. Review results are summarized.
7. A final review gate runs before a commit candidate is presented.

## Completed

### Codex single-agent workflow

Completed.

The repository now has a stable single-agent workflow based on:

- AGENTS.md
- docs/WORKFLOW.md
- docs/AI_ROLES.md
- scripts/verify.sh

The basic rule is:

- use ./scripts/verify.sh for project verification
- do not claim completion if verification fails
- do not commit without user approval

### Verification script

Completed.

./scripts/verify.sh verifies the ai-lab sample target.

It checks:

- pytest test suite
- Docker Compose startup
- API root endpoint
- /todos endpoint
- Docker Compose cleanup

### Review context collection

Completed.

./scripts/collect-review-context.sh collects:

- repository path
- git status
- diff stat
- full diff
- workflow rules
- relevant project instruction files

The output is written under:

- .omx/review-context/

### Review prompt generation

Completed.

./scripts/make-review-prompts.sh generates review prompts for:

- Claude
- Gemini

The output is written under:

- .omx/review-prompts/

### AI review runner

Completed.

./scripts/run-ai-reviews.sh runs available AI reviewers.

Current behavior:

- Claude review runs automatically if claude is available.
- Gemini review runs automatically if gemini is available.
- Gemini can be disabled for a specific run with RUN_GEMINI_REVIEW=0.
- REVIEW_EXECUTION_MODE=external prepares review prompts and a runner script for unrestricted interactive execution.
- Reviewer failures are captured instead of blocking the whole script.
- Claude is invoked in non-interactive print mode when supported.
- Claude uses plan permission mode when supported.
- Claude has a shorter default reviewer timeout in agent-run contexts.
- Gemini is invoked in non-interactive prompt mode.
- Gemini uses plan approval mode, skip-trust, and text output when supported.
- Large Gemini prompts switch to stdin mode to avoid command-line argument length limits.
- Review context, prompts, and results can use separate output directories.

The output is written under:

- .omx/review-results/

### Review summarizer

Completed.

./scripts/summarize-ai-reviews.sh finds the latest review results and produces a final verdict summary.

Possible final decisions include:

- proceed
- revise
- blocked
- review_manually

The summary also reports:

- decision reason
- review coverage
- missing or unusable reviewers
- reviewer disagreement

### Review gate

Completed.

./scripts/review-gate.sh runs the full final gate:

1. ./scripts/verify.sh
2. ./scripts/run-ai-reviews.sh
3. ./scripts/summarize-ai-reviews.sh

This is the current final check before presenting a commit candidate.

Current behavior:

- exits successfully only when the final review decision is proceed
- exits non-zero for revise, blocked, or review_manually
- exits with the external review preparation status when REVIEW_EXECUTION_MODE=external is used
- prints the review verdict summary before exiting

### Integrated rehearsal

Completed.

A small docs-only change was successfully run through:

- Codex task execution
- ./scripts/verify.sh
- ./scripts/review-gate.sh
- Claude review
- review verdict summary
- user-approved commit

Result:

- final verdict: proceed
- Claude: approve_with_notes
- Gemini: skipped by the old default behavior at that time

### Automation template

Completed.

A reusable template exists under:

- templates/automation-base/

It contains:

- repo-local AGENTS.md
- workflow documentation
- example verification script
- automation doctor
- review context collector
- review prompt generator
- AI review runner
- review summarizer
- review gate

### Template installer

Completed.

./scripts/install-automation-template.sh installs the automation template into a target git repository.

The shorter global command is:

- aiinit

Expected usage inside a target git repository:

    aiinit

Alternative usage from anywhere:

    aiinit /path/to/target-repo

After installation, aiinit automatically runs:

    DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh

The installer also creates `.omx/reviewer-state` so a newly initialized repository does not need a follow-up doctor fix for reviewer state storage.

Then customize:

    scripts/verify.sh

Then run:

    ./scripts/review-gate.sh

### Global helper tools

Completed.

Global helper tool sources are tracked in:

- tools/ai-auto-init
- tools/workspace-scan

Expected links:

- ~/bin/ai-auto-init -> ~/workspace/ai-lab/tools/ai-auto-init
- ~/bin/aiinit -> ~/workspace/ai-lab/tools/ai-auto-init
- ~/bin/workspace-scan -> ~/workspace/ai-lab/tools/workspace-scan

### ai-lab bootstrap

Completed first slice.

./scripts/bootstrap-ai-lab.sh checks first-time ai-lab setup for this checkout.

Default behavior:

- checks ai-lab source helper scripts
- checks git, Docker, Claude, Gemini, and OmX command availability
- checks expected `~/bin` helper symlinks and PATH
- runs automation-doctor with `DOCTOR_SKIP_DIRTY_CHECK=1`
- prints suggested fixes without installing external tools or editing shell profiles

Fix behavior:

- `./scripts/bootstrap-ai-lab.sh --fix` may create safe helper symlinks
- it delegates automation setup fixes to `./scripts/automation-doctor.sh --fix`
- it does not install external tools, configure git remotes, reset reviewer state, or mutate shell profile files

### Workspace scan

Completed.

workspace-scan scans git repositories under ~/workspace.

It reports:

- project name
- branch
- clean/dirty status
- whether scripts/verify.sh exists
- whether scripts/review-gate.sh exists
- latest commit
- whether origin remote exists
- path

### Automation doctor

Completed.

./scripts/automation-doctor.sh diagnoses whether a repository is ready for the generic automation loop.

Default behavior:

- prints pass, warning, and failure status lines
- suggests repair commands
- does not modify files
- checks whether expected helper links exist and whether `~/bin` is on PATH when running inside ai-lab

Fix behavior:

- `./scripts/automation-doctor.sh --fix` applies only safe non-overwriting setup fixes
- allowed fixes include missing automation directories, executable bits, missing template files when running in ai-lab, and expected helper symlinks
- it does not install external tools, overwrite existing files, or run destructive git operations

Verification behavior:

- `./scripts/verify.sh` runs automation-doctor with `DOCTOR_SKIP_DIRTY_CHECK=1` so normal pre-commit verification does not report the active working tree as a warning
- standalone `./scripts/automation-doctor.sh` still reports dirty working trees

## Current operating commands

For ai-lab itself:

    ./scripts/verify.sh
    ./scripts/bootstrap-ai-lab.sh
    ./scripts/automation-doctor.sh
    ./scripts/review-gate.sh
    omx doctor
    workspace-scan

For a new project:

    cd ~/workspace/new-project
    aiinit

Then edit:

    scripts/verify.sh

Then run:

    ./scripts/review-gate.sh

## Known issues

### Codex CLI EPERM in agent-run context

Sometimes Codex reports an EPERM failure when omx doctor is run from an agent-run context.

However, the same command passes from the user's interactive terminal:

    Results: 14 passed, 1 warnings, 0 failed

Current handling:

- treat it as context-dependent unless it reproduces in the interactive terminal
- do not block the workflow if the interactive terminal passes
- record it as a known environment limitation

### Claude CLI timeout in agent-run context

Claude can time out when invoked from this agent-run context even for a very small prompt.

Observed diagnostics:

- `claude --print` with a short prompt timed out.
- `claude --print --permission-mode plan` with a short prompt also timed out.
- `claude --bare --print` failed immediately with `Not logged in`.
- Debug logs showed repeated Anthropic API connection errors such as `ECONNREFUSED`.
- Debug logs also showed read-only filesystem errors while Claude tried to write under `/root/.claude`.

Current interpretation:

- this is a context-dependent network/auth/filesystem issue, not a review prompt size issue
- reviewer failures remain non-blocking inside `./scripts/run-ai-reviews.sh`
- `./scripts/review-gate.sh` can still proceed when another reviewer returns a usable approval
- `CLAUDE_REVIEW_TIMEOUT_SECONDS` defaults to 300 because observed Claude CLI runs can need more than 60 seconds before producing a usable result
- reviewer timeouts use `REVIEW_TIMEOUT_KILL_AFTER_SECONDS` as a short forced-kill grace period after the initial timeout
- reviewers with session, weekly, quota, or rate-limit failures are disabled immediately and stay disabled via `.omx/reviewer-state/` until reset by the user
- other reviewer failures retry up to `REVIEW_RETRY_LIMIT` times before the reviewer is disabled
- disabled reviewers are announced on every review run and skipped until `RESET_DISABLED_AI_REVIEWERS=claude|gemini|all` is used
- when one reviewer is disabled, the remaining reviewer prompt receives additional coverage for the disabled reviewer's perspective
- Codex also writes a `codex-self-review-*.md` persona fallback artifact and the summary reports Codex self-review coverage separately; this is informational only and does not count as independent reviewer approval
- the most stable non-API-key workaround is `REVIEW_EXECUTION_MODE=external`, which prepares a runner for an unrestricted interactive terminal

### Explore Harness warning

omx doctor still reports a warning about the Explore Harness.

Current handling:

- non-blocking
- can be fixed later by installing Rust or configuring a compatible prebuilt harness

### Gemini review enabled by default

Gemini CLI previously caused hangs and capacity errors.

Observed issues:

- Gemini entered an agent/tool mode
- unauthorized run_shell_command call
- model capacity error: RESOURCE_EXHAUSTED
- long hang during non-interactive invocation
- unauthenticated agent-run smoke tests can show an auth prompt that consumes stdin

Current handling:

- Gemini review is enabled by default
- disable only with RUN_GEMINI_REVIEW=0
- run in non-interactive prompt mode with plan approval mode where supported
- use stdin mode automatically for large prompts to avoid command-line argument length limits
- `GEMINI_REVIEW_TIMEOUT_SECONDS` can be set separately from the Claude timeout
- `REVIEW_TIMEOUT_KILL_AFTER_SECONDS` applies to both Claude and Gemini timeout cleanup
- Claude is the current stable external reviewer
- Gemini absence or failure is reported as incomplete review coverage

Gemini can hit a similar class of context-dependent failures as Claude, but the observed failure mode differs:

- Claude failed from API connection refusal and read-only writes under `/root/.claude`.
- Gemini has previously failed from capacity/tool-mode issues and can prompt for browser authentication when credentials are unavailable.
- Gemini's CLI documents that `--prompt` appends stdin, so large-prompt stdin fallback is valid when Gemini is authenticated.

### External reviewer lane

Use this when the agent-run context blocks reviewer network access or runtime writes, but the user's interactive terminal has working Claude/Gemini authentication.

Command:

    REVIEW_EXECUTION_MODE=external ./scripts/review-gate.sh

Behavior:

- runs normal project verification first
- collects review context
- generates Claude and Gemini prompts
- writes an executable runner under `.omx/external-review/`
- the runner resolves the repository root relative to `.omx/external-review/` before falling back to the generation-time path
- the runner uses `REVIEW_OUTPUT_MODE=tee` by default so reviewer prompts, approval waits, and errors are visible in the terminal while still being saved to result files
- the runner treats generated timeout/path settings as defaults, so execution-time environment overrides still work
- the runner carries `REVIEW_STATE_DIR` and `REVIEW_RETRY_LIMIT` so disabled reviewer state and retry policy are consistent across external runs
- the runner uses `SKIP_CONTEXT_GENERATION=1` by default so external execution reviews the prompts prepared by the agent instead of regenerating context
- exits before invoking reviewer CLIs in the restricted context

Then run the generated external runner from an unrestricted interactive terminal.

The runner executes reviewers and then runs:

    ./scripts/summarize-ai-reviews.sh

This is the preferred workaround when API-key based bare mode is intentionally excluded.

## Deferred

### Clone/bootstrap automation

Deferred.

A future script may automate first-time setup after cloning ai-lab on a new PC or for another user.

Candidate script:

- scripts/bootstrap-ai-lab.sh

Possible responsibilities:

- check required tools
- link aiinit
- link workspace-scan
- run automation-doctor
- update PATH
- check Codex/OMX/Claude/Gemini/Docker availability
- run basic diagnostics

### Odoo-specific workflow

Deferred.

Future work should define an Odoo-specific scripts/verify.sh pattern.

Possible checks:

- Python syntax check
- module manifest check
- addon path validation
- import smoke checks
- Odoo test database module install
- optional Docker-based Odoo test run

### Gemini non-interactive mode

Partially addressed.

The review runner now prefers Gemini's non-interactive prompt mode and read-only approval settings when the installed CLI supports them.

Remaining limitation:

- Gemini failures may still happen because of CLI capacity, tool-mode, or timeout behavior; failures are captured and summarized instead of stopping review collection.

## Current stage

The project has completed:

- Codex single-agent workflow
- Claude-backed review gate
- explicit single-reviewer and multi-reviewer review summaries
- reviewer disagreement handling
- reusable automation template
- generic automation doctor
- global helper command setup
- aiinit doctor handoff
- ai-lab bootstrap first slice
- workspace scanning

The next recommended stage is:

1. keep this current-state document updated
2. expand bootstrap only if a real first-time setup gap appears
3. later add Odoo-specific verification patterns
