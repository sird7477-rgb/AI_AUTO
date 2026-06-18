# Automation Base Template

This template contains the base files for a CLI-based AI development workflow.

## Included

- AGENTS.md: repo-local agent operating rules
- AI_AUTO_TEMPLATE_VERSION: installed template version marker for status comparison
- docs/WORKFLOW.md: project workflow documentation
- docs/AI_AUTOMATION_TREND_HARDENING.md: compact agent identity, permission, revocation, observability, and trend hardening contract
- docs/AI_PRINCIPAL_RUNTIMES.md: principal runtime permission parity, reviewer rotation, and shared `.omx/*` artifact paths
- docs/research/AI_AUTOMATION_TRENDS.md: recurring AI automation trend research report structure
- docs/AUTOMATION_OPERATING_POLICY.md: review-intensity and feedback policy
- docs/DEPLOYMENT_COMPLETION.md: optional deployment/release completion pack
- docs/DOMAIN_PACKS.md: domain-pack lifecycle, selection, and application rules
- docs/DOMAIN_PACK_AUTHORING_GUIDE.md: authoring standard for reusable domain packs
- docs/INTERVIEW_PLAN_LAYER.md: reusable interview, plan, ambiguity, and execution-gate contract
- docs/INCIDENT_OPS.md: dry-run and field-test incident operations policy
- docs/OBSIDIAN_INTEGRATION.md: curated Obsidian knowledge-store operating rules
- docs/SECURITY_COMPLETION.md: optional security/auth completion pack
- docs/DATA_COMPLETION.md: optional data/migration completion pack
- docs/PERFORMANCE_COMPLETION.md: optional performance completion pack
- docs/OBSERVABILITY_COMPLETION.md: optional observability/operations completion pack
- docs/PATCH_NOTES.md: template version changes to review before patching
- docs/UI_COMPLETION.md: optional UI completion and verification pack
- docs/PLANNING_VISUALIZATION_GUIDE.md: planning diagrams, framework-native UI wireframes, and vector wireframe fidelity guidance
- scripts/automation-doctor.sh: diagnoses automation readiness and suggests safe repairs
- scripts/archive-omx-artifacts.sh: archives old ignored review artifacts while preserving latest evidence
- scripts/ai-principal-runtime.sh: active principal runtime contract helper for `codex`, `claude`, and `gemini`
- scripts/audit-obsidian-vault.py: read-only Obsidian vault labeling/index audit
- scripts/benchmark-command.py: optional benchmark evidence capture using
  `hyperfine` when available
- scripts/todo-report.py: canonical backlog TODO report and active-work guard
- scripts/verify.example.sh: onboarding placeholder; replace with project-specific verification
- scripts/collect-review-context.sh: collects git diff and workflow context
- scripts/docker-config-guard.sh: uses a temporary Docker config for WSL Docker Desktop credential-helper failures
- scripts/doc-budget.sh: reports guidance document volume and bloat warnings
- scripts/refresh-guidance-baseline.sh: (re)writes the install-time guidance baseline so doc-budget excludes inherited-unchanged docs; run after adopting a newer template
- scripts/guidance-duplicate-report.sh: creates read-only Stage 2 guidance duplicate reports
- scripts/discover-ai-models.sh: discovers local AI CLI model routing capabilities
- scripts/capture-knowledge-drafts.py: captures sanitized local knowledge draft candidates
- scripts/knowledge-notes.py: creates and validates sanitized knowledge notes
- scripts/make-review-prompts.sh: generates reviewer prompts
- scripts/record-feedback.sh: appends sanitized failure/improvement feedback
- scripts/record-project-memory.sh: appends sanitized durable memory entries
- scripts/resolve-feedback.sh: marks feedback queue items resolved, ignored, or deferred
- scripts/run-ai-reviews.sh: runs available AI reviewers
- scripts/summarize-ai-reviews.sh: summarizes reviewer verdicts
- scripts/test-review-summary.sh: fixture tests for review verdict decisions
- scripts/review-gate.sh: runs verification, reviews, and verdict summary
- scripts/write-session-checkpoint.sh: writes resume checkpoints after review gates

## How to use in a new project

Copy the template into the target repository.

Example:

    cp -r templates/automation-base/* /path/to/target-repo/

Then customize:

    mv scripts/verify.example.sh scripts/verify.sh
    mkdir -p .omx/reviewer-state
    chmod +x scripts/*.sh

Check the automation setup:

    ./scripts/automation-doctor.sh

Template-specific helper link and `~/bin` PATH checks only run when the script detects the ai-lab source tree.

From any terminal, use `AI_AUTO` to jump to the AI_AUTO checkout:

    AI_AUTO
    AI_AUTO --status
    ai-auto-template-status /path/to/target-repo

`./scripts/install-global-files.sh` installs `AI_AUTO` through
`~/.config/ai-lab/AI_AUTO.sh` and sources it from `~/.bashrc`; reload the shell
or run `source ~/.bashrc` after installation.

`ai-auto-template-status` compares a project against the current template and
prints version, per-file states, ownership, and patch policy. Generated/runtime
files such as `.omx/` review artifacts are outside the managed-file manifest.
Review `docs/PATCH_NOTES.md` first to understand version-level changes. The
status command is status-only: review differences manually before copying or
editing files. If it reports `template_patch_enabled: no`, do not apply the
template as a patch source; switch AI_AUTO to `main` or do a manual review-only
merge. Use `--record-feedback` only when the detected drift should
become a project queue item; feedback is written through AI_AUTO's trusted
helper, not by executing scripts from the inspected project.

AI reviewer context defaults to `REVIEW_CONTEXT_DETAIL=auto`. Small tracked
diffs use a lightweight context focused on the patch, git state, and
verification tail. Set `REVIEW_CONTEXT_DETAIL=full` when planning artifacts or
full workflow reference excerpts are needed for the review.

For a targeted docs/spec-draft review, set `REVIEW_UNTRACKED_ALLOWLIST` to a
comma/newline-separated list of paths, directory prefixes, or globs. Only
matching untracked artifacts then count as blocking review material; other
untracked files are still reported but treated as out of the declared review
scope, so an unrelated working tree does not stall the gate. Empty (default)
keeps every material untracked file in scope.

Codex is the default active principal runtime. Claude/Gemini principal runs
require launcher-owned evidence before that runtime is skipped as a
self-reviewer. Without matching evidence, review-gate fails closed with
`principal_unavailable`.

Guidance context budget is a staged workflow. The installed `scripts/doc-budget.sh`
is Stage 1: it reports document-volume warnings during verification and
recommends the next step. It budgets primary project guidance and template
guidance separately because template-owned mirrored docs are intentionally
duplicated for distribution. In an installed project, doc-budget excludes
guidance docs byte-identical to the install-time baseline
(`.ai-auto/guidance-baseline.sha256`) from the absolute size budget, so the
budget measures only what the project authored or changed; after adopting a
newer template, run `scripts/refresh-guidance-baseline.sh <target>` to refresh
it. Stage 2 is a read-only duplicate or consolidation
report produced by `scripts/guidance-duplicate-report.sh` and should run only
when the user asks for it after seeing a Stage 1 recommendation. The Stage 2
tool prefers an existing duplicate detector such as `jscpd` when available and
uses a local read-only fallback otherwise. Do not edit guidance documents from a
Stage 1 warning alone.

ShellCheck may be promoted by a project-specific `scripts/verify.sh`. AI_AUTO's
source checkout requires `shellcheck -S warning` for repo/template shell
scripts; downstream projects should only make ShellCheck required after they
have cleaned or explicitly suppressed warning-level findings.

Use `ai-rebuild-plan /path/to/project` for `리빌드 플랜`, `리빌딩 플랜`, or
`rebuild plan` requests. This is read-only: it checks git state, automation
template drift, domain-pack references, and refactoring candidates, then stops
at a plan/report boundary. `리빌드 실행`, `리빌딩 실행`, or `rebuild run` is a
separate execution request and requires an approved plan artifact, refreshed
domain-pack assumptions, behavior-locking tests or smoke checks, and explicit
module boundaries.

For Python rebuilds, `ai-split-plan` can turn conservative domain-pack
`split-rules.json` rules into proposed top-level function/class moves. Use
`ai-split-dry-run` to inspect the diff first; `ai-split-apply` requires
`--execute-approved-plan` plus completed approval-gate fields and writes rollback
backups under `.omx/rebuild/backups/`.

Use `docs/OBSIDIAN_INTEGRATION.md` and `scripts/knowledge-notes.py` when a
project needs curated debugging notes, work-review notes, or user-requested
technical references. Obsidian is only a sanitized knowledge store; AI_AUTO
keeps authority for verification, review gates, approvals, commits, patches, and
runtime state. `record` is dry-run by default; note writes require `--write` and
an explicit output path. `.omx/knowledge` requires the local-draft flag and is
not durable vault storage. `review-gate` captures local review-gate draft
candidates by default. The AI_AUTO home checkout uses
`knowledge-collect --include-registry` for broad review. Vault writes require
`knowledge-collect --project <repo> --vault-dir <vault-path>/AI_AUTO --push`;
local/private vaults additionally require `--allow-local-private`. Do not copy
raw `.omx/` logs or prompts into an Obsidian vault.

If the optional Codex startup notice is installed and Codex starts from the
AI_AUTO home checkout, the wrapper can print an `OBSIDIAN OUTPUT CHECK` block
when validated drafts are pending across AI_AUTO plus registered projects. This
notice is read-only and only prints an approval handoff; it never pushes to a
vault automatically.

Then ask the AI:

    프로젝트 초기설정 해줘

Equivalent detailed request:

    프로젝트 요구사항을 인터뷰하고, docs/*_COMPLETION.md 완료팩과
    .omx/domain-packs/에 설치된 도메인팩 중 적용할 항목이 있는지 확정한 뒤,
    리뷰 강도, 실패 패턴 기록, 승인 마찰 관리, 서브에이전트 사용 기준,
    플랜/인터뷰 강도 기준, Incident Ops 감시/장애대응 기준을 정하고
    AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 프로젝트에 맞게 설정해줘

The AI should interview the project owner, then update the generated files for the target project:

    AGENTS.md
    docs/WORKFLOW.md
    scripts/verify.sh

During the interview, decide which completion dimensions apply:

- Outcome: confirm purpose, users, final deliverable, and non-goals after
  reading local evidence first
- Review intensity: choose `lightweight`, `standard`, or `strict` using
  `docs/AUTOMATION_OPERATING_POLICY.md`
- Feedback: decide whether sanitized failure patterns and common improvement
  ideas may be written to `.omx/feedback/queue.jsonl`
- Approval friction: decide which recurring safe commands should use narrow
  approved prefixes or repo helpers; do not bypass approval for destructive,
  credentialed, or production actions
- Advisory reviewers: decide whether warm Claude/Gemini sessions may be used
  for local iteration. If allowed, they are advisory only, should be cleared
  before each request when supported, and never replace stateless
  `review-gate` for commit candidates.
- Subagents: decide when native subagents may be used for bounded lookup,
  implementation slices, testing, UX, dependency research, or critique; the
  leader keeps final integration and completion responsibility
- Resource-aware parallelism: inspect local CPU, memory, disk, and load first,
  then ask about shutdown history, active heavy sessions, thermal limits, and
  maximum acceptable parallelism
- Planning/interview intensity: choose when to execute directly, ask one short
  question, or run a plan-first interview. Use `none`, `light`, `standard`, or
  `deep`. Use `docs/INTERVIEW_PLAN_LAYER.md` to keep questions narrow, map
  answers into plan fields, and preserve plan/run boundaries.
- Operational readiness: define required inputs, fail-closed blockers, accepted
  operating artifacts, read-only/auth/network preflight,
  sandbox-vs-real-network evidence, and analysis-only fallback boundaries.
- Incident Ops: define dry-run/field-test monitoring, automatic action classes,
  incident log fields, UI field-test evidence, and heartbeat/quiet/active
  incident reporting intervals using `docs/INCIDENT_OPS.md`.
- Plan management: define the current plan index, TODO reconciliation, checkpoint
  update expectations, and where detailed runbooks or long checklists should
  live.
- Spec/design alignment: define which plan, specification, or design artifacts
  should be checked after code edits, and how to report aligned, updated, not
  applicable, or blocked outcomes.
- User-facing report language: report outcomes in plain Korean first and avoid
  leading with internal variable names unless reproduction or user action needs
  them.
- Guidance context budget: decide what belongs in `AGENTS.md` versus linked docs
  so project instructions stay scannable.
- AI automation hardening: use `docs/AI_AUTOMATION_TREND_HARDENING.md` when
  agent identity, tool permissions, revocation, local automation observability,
  or recurring trend research are in scope. Use
  `docs/research/AI_AUTOMATION_TRENDS.md` for dated research reports. Do not let
  trend notes change runtime defaults without a reviewed patch.

- UI: use `docs/UI_COMPLETION.md` when the final outcome includes a UI
- Deployment: use `docs/DEPLOYMENT_COMPLETION.md` when release or operations
  outside local development are in scope
- Security: use `docs/SECURITY_COMPLETION.md` when auth, secrets, personal
  data, privileged operations, or external integrations are in scope
- Data: use `docs/DATA_COMPLETION.md` when persistent data, migrations, seed
  data, import/export, or recovery are in scope
- Performance: use `docs/PERFORMANCE_COMPLETION.md` when latency, throughput,
  scale, cost, or resource targets are in scope
- Observability: use `docs/OBSERVABILITY_COMPLETION.md` when health checks,
  logs, metrics, traces, audits, or support diagnostics are in scope
- Domain packs: use `docs/DOMAIN_PACKS.md` to select, reject, or defer installed
  `.omx/domain-packs/` references. Use
  `docs/DOMAIN_PACK_AUTHORING_GUIDE.md` when creating or changing reusable
  packs. Run `ai-domain-pack status` before relying on old installed
  references; `ai-domain-pack refresh --apply` updates only clean managed or
  exact-match legacy copies and never patches project instruction files.
  `automation-base` is the generic baseline; there is no separate generic
  domain pack.

For dimensions that do not apply, record them as non-goals instead of merging
their checks into the project workflow. After onboarding, unused completion pack
files may be deleted from `docs/` to keep the target project documentation
small; `automation-doctor` does not require optional completion packs to remain.

The installed `scripts/verify.sh` is intentionally not project-ready. It exits
non-zero until it is replaced with real checks for the target repository.

## Smoke test the template

You can test this template in a temporary repository before applying it to a real project.

Example:

    cd ~/workspace
    rm -rf automation-template-smoke
    mkdir automation-template-smoke
    cd automation-template-smoke
    git init

    cp -r ~/workspace/ai-lab/templates/automation-base/* .

    mv scripts/verify.example.sh scripts/verify.sh
    mkdir -p .omx/reviewer-state
    chmod +x scripts/*.sh

    cat > scripts/verify.sh <<'VERIFY'
    #!/usr/bin/env bash
    set -euo pipefail

    echo "[verify] smoke test for automation template"
    test -f AGENTS.md
    test -f docs/WORKFLOW.md
    test -x scripts/review-gate.sh

    echo "[verify] success"
    VERIFY

    chmod +x scripts/verify.sh

    ./scripts/automation-doctor.sh
    git add .
    git commit -m "test: initialize automation template smoke repo"

    ./scripts/verify.sh
    ./scripts/review-gate.sh

The smoke test should complete with verification success, Claude review if available, Gemini review if available, and a review verdict summary. Set RUN_GEMINI_REVIEW=0 to skip Gemini for a specific run. Large Gemini prompts use `--prompt-file` when supported; prompt-only large prompts fail closed instead of relying on stdin append behavior. Reviewer-specific timeouts are available as CLAUDE_REVIEW_TIMEOUT_SECONDS and GEMINI_REVIEW_TIMEOUT_SECONDS, with REVIEW_TIMEOUT_KILL_AFTER_SECONDS as the forced-kill grace period. Claude defaults to a longer reviewer timeout because login-based CLI calls can take more than a minute.

Reviewer failures are stateful. Session, weekly, quota, or rate-limit failures disable that reviewer immediately. Other failures retry up to REVIEW_RETRY_LIMIT times before disabling the reviewer. Disabled reviewer state is stored under `.omx/reviewer-state` and is announced on every run until reset with RESET_DISABLED_AI_REVIEWERS=claude, RESET_DISABLED_AI_REVIEWERS=gemini, or RESET_DISABLED_AI_REVIEWERS=all.

Each review run writes a `review-run-*.md` manifest under `.omx/review-results/` linking the context, prompts, outputs, model routing report, fallback artifacts, external runner, and disabled reviewer state for that run.

Before the first AI reviewer invocation in a run, `scripts/discover-ai-models.sh` writes `.omx/model-routing/latest.env` and `.omx/model-routing/latest.md`. The review runner sources that env file and applies model selectors only when the installed CLI supports `--model`.

Model routing is role-first: choose the role/capability first, then resolve it against the current local CLI/runtime/account surface. Provider docs are reference material, not proof that this local CLI can use a model. Use `CLAUDE_REVIEW_ROLE`, `GEMINI_REVIEW_ROLE`, `CODEX_ARCHITECT_REVIEW_ROLE`, `CODEX_TEST_REVIEW_ROLE`, `CLAUDE_REVIEW_MODEL`, `GEMINI_REVIEW_MODEL`, `CODEX_ARCHITECT_REVIEW_MODEL`, `CODEX_TEST_REVIEW_MODEL`, or `CODEX_FALLBACK_MODEL` to override routing without editing scripts. Set `AI_MODEL_DISCOVERY=0` to use provider defaults.

The active Codex/GPT leader is runtime-selected and should not claim to switch
itself to another model mid-session. Use bounded child-agent or OMX lanes for
cost/latency optimization, and keep final integration, verification, and
completion claims with the leader or stronger reviewer roles.

Long-running session operation is described in `docs/SESSION_QUALITY_PLAN.md`.
Use it for model-routing cache policy, working memory capture, checkpoints, and
token/context hygiene.

When a reviewer is disabled, the remaining reviewer prompt stays focused on its
own role. The disabled lane is covered by the active principal's subagent
substitute in a separate review artifact, such as
`codex-architect-fallback-*.md` or `codex-test-fallback-*.md`. The substitute is
always degraded coverage, not independent external review: with a usable verdict
and direct file inspection evidence it is reported as proceed_degraded with
degraded trust; otherwise the verdict remains blocked. Set
`RUN_PRINCIPAL_SUBAGENT_SUBSTITUTE_REVIEW=0` only for diagnostics.

If the current agent context blocks reviewer network access or runtime writes, use:

    REVIEW_EXECUTION_MODE=external ./scripts/review-gate.sh

Then run the generated `.omx/external-review/run-reviewers-latest.sh` script from an unrestricted interactive terminal. The script resolves the repository root from its own location before running the reviewers, shows reviewer output with `tee`, uses the already-prepared prompts by default, and allows execution-time timeout overrides.

External reviewer preparation reports disabled reviewers before stopping. The generated external runner shares `.omx/reviewer-state/`, so reset a disabled reviewer first if the interactive terminal should retry it.

Review context lists untracked files but omits their content by default. Set `REVIEW_INCLUDE_UNTRACKED_CONTENT=1` for review-gate runs, or `INCLUDE_UNTRACKED_CONTENT=1` when calling `scripts/collect-review-context.sh` directly, to include untracked text files up to `MAX_UNTRACKED_BYTES` bytes after confirming secrets and generated output are covered by `.gitignore`.

`aiinit` adds `.omx/` to the target repository's local `.git/info/exclude` so generated review, model-routing, and reviewer-state artifacts do not become commit candidates by default.

`aiinit` also registers the target repository in the local AI_AUTO project
registry at `~/.local/state/ai-auto/projects.tsv`. Older projects can be
registered later with `ai-register /path/to/repo`, and `workspace-scan` shows
both workspace-discovered and registered projects. Use `ai-register --prune`
to remove deleted or moved repository entries from the registry. The scan
supports normal repositories and linked worktrees, and registry writes use a
local lock. On Linux/WSL, `flock` releases the lock when the process exits, so
stale lock deletion is not needed.

`./scripts/review-gate.sh` and `./scripts/automation-doctor.sh --fix` automatically archive old `.omx/review-results` files when runtime artifacts grow beyond `OMX_REVIEW_ARCHIVE_THRESHOLD` or `OMX_ARTIFACT_WARN_COUNT`. The archive keeps recent/latest evidence active, moves older files under `.omx/review-results/archive/`, and never deletes unless `./scripts/archive-omx-artifacts.sh --delete --confirm-delete` is explicitly used (a deliberate double-confirm; `--delete` alone refuses).
