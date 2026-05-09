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
- latest commit diff when the working tree is clean, for post-commit review context
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

- before the first AI reviewer call in a run, `scripts/discover-ai-models.sh` inspects local CLI capabilities and writes `.omx/model-routing/latest.env` plus `.omx/model-routing/latest.md`
- model routing avoids dated hardcoded model names; it is role-first, then resolves against explicit env overrides, advertised CLI aliases, the current OMX/Codex model contract, or provider defaults
- the active Codex/GPT leader is treated as runtime-selected; cost/latency optimization is handled by bounded delegated subagent or OMX lanes instead of claiming the leader changed models mid-session
- model availability inferred from local help/config must be reported as inferred; do not present uncertain provider/model availability as fact
- long-session quality management draft is in `docs/SESSION_QUALITY_PLAN.md`; it covers model routing cache, working memory, checkpoints, and token/context hygiene
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

Current parsing guard:

- reviewer failure and timeout markers take precedence over any prompt-like `## Verdict` text in a failed reviewer output
- failure detection is limited to the runner failure footer shape, not arbitrary error words in a valid review body
- fixture coverage includes a failed reviewer output that echoes `approve_with_notes`, a valid review mentioning failure-like words, and a valid review quoting failure footer text in a code fence

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
- onboarding placeholder verification script
- automation doctor
- review context collector
- review prompt generator
- AI review runner
- review summarizer
- review gate

Current behavior:

- template AGENTS/WORKFLOW defaults are generic and do not assume the ai-lab Flask todo sample
- `scripts/verify.example.sh` is intentionally unconfigured and exits non-zero after showing onboarding guidance
- new projects must define project-specific AGENTS, WORKFLOW, and verify checks before the gate can be treated as ready

### Template installer

Completed.

./scripts/install-automation-template.sh installs the automation template into a target git repository.

### Domain packs

Domain-specific standards are separated from the generic `aiinit` template.
`aiinit` installs only the reusable automation baseline into project files. It
also copies optional domain packs into `.omx/domain-packs/` as ignored
onboarding references so the AI running inside the target repository can read
them. During `프로젝트 초기설정 해줘`, the agent should ask whether an optional
domain pack applies and merge only the applicable guidance into the target
project's `AGENTS.md`, `docs/WORKFLOW.md`, and `scripts/verify.sh`.

Current optional domain pack:

- `templates/domain-packs/odoo/`

The shorter global command is:

- aiinit

Expected usage inside a target git repository:

    aiinit

Alternative usage from anywhere:

    aiinit /path/to/target-repo

After installation, aiinit automatically runs:

    DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh

Then it prints the recommended AI handoff request:

    프로젝트 초기설정 해줘

The installed template AGENTS.md routes this request to the onboarding workflow:
interview the project owner, inspect existing reference materials, customize
AGENTS.md, docs/WORKFLOW.md, and scripts/verify.sh, then run automation-doctor,
verify, and review-gate before reporting.

The installer also creates `.omx/reviewer-state` and adds `.omx/` to the target repository's local `.git/info/exclude` so generated reviewer, review, and model-routing artifacts stay out of commit candidates by default.

If target automation files already exist, aiinit refuses to overwrite them. The
conflict message directs users of existing or advanced projects to ask the AI:

    기존 프로젝트에 자동화 기반을 병합 도입해줘.
    기존 AGENTS.md, docs, scripts/verify.sh는 덮어쓰지 말고 먼저 분석한 뒤
    필요한 자동화 파일과 지침만 제안/반영해줘.

Then run a project onboarding interview and customize:

    AGENTS.md
    docs/WORKFLOW.md
    scripts/verify.sh

Then run:

    ./scripts/automation-doctor.sh
    ./scripts/verify.sh
    ./scripts/review-gate.sh

### Global helper tools

Completed.

Global helper tool sources are tracked in:

- tools/ai-auto-init
- tools/ai-register
- tools/workspace-scan

Expected links:

- ~/bin/ai-auto-init -> ~/workspace/ai-lab/tools/ai-auto-init
- ~/bin/aiinit -> ~/workspace/ai-lab/tools/ai-auto-init
- ~/bin/ai-register -> ~/workspace/ai-lab/tools/ai-register
- ~/bin/workspace-scan -> ~/workspace/ai-lab/tools/workspace-scan

Clone recovery command:

- `./scripts/install-global-files.sh`

When a user opens a cloned checkout and asks `전역파일 설치해줘`, AGENTS.md routes the AI
to run this command from the repository root.

It only creates or repairs safe repo-owned helper symlinks under `~/bin`; it does
not install external programs, edit shell profiles, configure credentials, run
`automation-doctor --fix`, or overwrite non-symlink files.

Project registry:

- new `aiinit` runs append/update the target repository in
  `~/.local/state/ai-auto/projects.tsv`
- `ai-register` registers older already-initialized projects without modifying
  project files
- `ai-register --prune` removes deleted or moved repositories from the local
  registry
- `workspace-scan` reports both repositories discovered under `~/workspace` and
  registered repositories, with an `INIT` column for registry membership

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

workspace-scan scans git repositories under ~/workspace and the AI_AUTO project
registry.

It reports:

- project name
- branch
- clean/dirty status
- whether scripts/verify.sh exists
- whether scripts/review-gate.sh exists
- latest commit
- whether origin remote exists
- whether the repository is registered by aiinit/ai-register
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
    ./scripts/install-global-files.sh
    ./scripts/bootstrap-ai-lab.sh
    ./scripts/automation-doctor.sh
    ./scripts/review-gate.sh
    omx doctor
    ai-register
    ai-register --prune
    workspace-scan

For a new project:

    cd ~/workspace/new-project
    aiinit

Then interview the project owner and edit:

    AGENTS.md
    docs/WORKFLOW.md
    scripts/verify.sh

Then run:

    ./scripts/automation-doctor.sh
    ./scripts/verify.sh
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
- when one reviewer is disabled, the remaining external reviewer prompt stays role-pure instead of simulating the missing model's perspective
- Codex/GPT writes separate fallback review artifacts such as `codex-architect-fallback-*.md` and `codex-test-fallback-*.md`; summaries mark this as degraded/informational coverage and never count it as independent Claude/Gemini approval
- Codex fallback execution uses `codex exec` when available; set `RUN_CODEX_FALLBACK_REVIEW=0` only for diagnostics, because both external reviewers disabled plus skipped fallback remains blocked
- Codex fallback model selection can use `CODEX_ARCHITECT_REVIEW_MODEL`, `CODEX_TEST_REVIEW_MODEL`, `CODEX_FALLBACK_MODEL`, or `OMX_DEFAULT_FRONTIER_MODEL`
- Codex/GPT fallback lanes and native subagents are delegated lanes with explicit trust boundaries; they do not make the main leader equivalent to an external reviewer or imply a leader model switch
- the most stable non-API-key workaround is `REVIEW_EXECUTION_MODE=external`, which prepares a runner for an unrestricted interactive terminal
- each AI review run now writes a `review-run-*.md` manifest that links the context, prompts, outputs, fallback artifacts, external runner, model routing report, and disabled reviewer state for that run
- disabled reviewer markers include `source_run_id`, `next_action`, and `reset_hint` fields so doctor/external runs can show the recovery path without guessing
- external review mode reports current disabled reviewers before stopping, because the generated external runner shares `.omx/reviewer-state/` and will skip disabled reviewers until reset
- review-gate and automation doctor `--fix` archive old `.omx/review-results`
  files when retention thresholds are exceeded; latest run evidence remains
  active, and deletion still requires explicit `archive-omx-artifacts.sh --delete`
- `scripts/record-project-memory.sh` appends sanitized durable entries to
  `.omx/project-memory.json`
- `scripts/write-session-checkpoint.sh` writes `.omx/state/session-checkpoint.md`;
  review-gate runs it automatically after successful summary unless
  `OMX_AUTO_CHECKPOINT=0`

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
- automation doctor reports Gemini CLI capability signals from `gemini --help`,
  including prompt mode, approval mode, skip-trust, output format, explicit
  model flag support, timeout default, and stdin threshold

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

### Odoo-specific workflow

Partially addressed as an optional domain pack.

The reusable Odoo pack lives under `templates/domain-packs/odoo/` and is copied
by `aiinit` as an ignored onboarding reference under `.omx/domain-packs/odoo/`.
It is not blindly merged into project instructions. During project onboarding,
the agent should confirm that the target is Odoo-based, then adapt only the
version, addon scope, localization baseline, verification patterns, and review
checklist that match the target project.

Current pack coverage:

- Odoo version and major-version lock prompts
- addon scope and upstream `odoo/` / `enterprise/` reference-only guidance
- Korean localization prompt examples: `ko_KR`, KRW, and 10% VAT
- static syntax/XML verification examples
- module install/update/test command shapes
- Docker Compose runtime pattern
- review checklist for runtime, data model, security, localization, and
  project-specific rule separation

Remaining work:

- dogfood the pack on a real Odoo project
- harden the generated `scripts/verify.sh` shape from that real project
- keep customer-specific odoo.sh, SSH, branch, commit, and access rules in the
  target project instructions instead of the reusable pack

### Gemini non-interactive mode

Partially addressed.

The review runner now prefers Gemini's non-interactive prompt mode and read-only approval settings when the installed CLI supports them.

Remaining limitation:

- Gemini failures may still happen because of CLI capacity, tool-mode, or timeout behavior; failures are captured and summarized instead of stopping review collection.

## Current stage

The generic automation foundation is complete for the current scope.

Completed capabilities:

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
- generic aiinit onboarding defaults with no Flask todo/testbed assumption
- optional completion packs for UI, deployment, security, data, performance,
  and observability

No additional generic automation implementation is planned unless a real first-time setup or target-project initialization gap appears.

Recommended next stage:

1. keep this current-state document updated
2. define Odoo-specific verification patterns when the Odoo work resumes
