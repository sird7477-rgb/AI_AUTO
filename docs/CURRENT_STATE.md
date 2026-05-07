# Current State

This document summarizes the current state of the ai-lab automation project.

## Purpose

ai-lab is a testbed for building a CLI-based AI development automation workflow.

The current goal is to make a reliable workflow where:

1. Codex performs small scoped changes.
2. The project runs a fixed verification command.
3. AI review context is collected.
4. Claude reviews the change.
5. Gemini is supported as an optional reviewer, but disabled by default.
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
- Gemini review is disabled by default.
- Gemini can be enabled with RUN_GEMINI_REVIEW=1.
- Reviewer failures are captured instead of blocking the whole script.

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

### Review gate

Completed.

./scripts/review-gate.sh runs the full final gate:

1. ./scripts/verify.sh
2. ./scripts/run-ai-reviews.sh
3. ./scripts/summarize-ai-reviews.sh

This is the current final check before presenting a commit candidate.

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
- Gemini: skipped by default

### Automation template

Completed.

A reusable template exists under:

- templates/automation-base/

It contains:

- repo-local AGENTS.md
- workflow documentation
- example verification script
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

## Current operating commands

For ai-lab itself:

    ./scripts/verify.sh
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

### Explore Harness warning

omx doctor still reports a warning about the Explore Harness.

Current handling:

- non-blocking
- can be fixed later by installing Rust or configuring a compatible prebuilt harness

### Gemini review disabled by default

Gemini CLI previously caused hangs and capacity errors.

Observed issues:

- Gemini entered an agent/tool mode
- unauthorized run_shell_command call
- model capacity error: RESOURCE_EXHAUSTED
- long hang during non-interactive invocation

Current handling:

- Gemini review is disabled by default
- enable only with RUN_GEMINI_REVIEW=1
- Claude is the current stable external reviewer

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

Deferred.

Gemini should only be re-enabled after confirming a reliable non-interactive review invocation.

## Current stage

The project has completed:

- Codex single-agent workflow
- Claude-backed review gate
- reusable automation template
- global helper command setup
- workspace scanning

The next recommended stage is:

1. keep this current-state document updated
2. design an Odoo-specific verification strategy
3. later add clone/bootstrap setup automation
