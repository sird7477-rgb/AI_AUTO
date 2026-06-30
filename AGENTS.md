# Agent Instructions

This repository is a Codex/OMX single-agent workflow testbed.

## Operating Rule

Article 1.1: the best code is code never written. Before adding code, check
whether the problem can be removed, solved by existing behavior, config/docs,
simplification, or deletion; when still necessary, make the smallest verifiable
change.

Before claiming a task is complete, the agent must:

1. keep the change small and within scope
2. inspect the diff
3. compare edits against any applicable plan/spec/design artifact and classify
   as aligned, updated, not applicable, or blocked (size the search per
   `docs/AUTOMATION_OPERATING_POLICY.md`); re-check if verification adds edits
4. run `./scripts/verify.sh` for basic verification
5. run `./scripts/review-gate.sh` before presenting a commit candidate
6. report the verification, review, and spec/design alignment results
7. mention any remaining warnings or limitations

If `./scripts/verify.sh` fails, the task is not complete.
If `./scripts/review-gate.sh` fails or returns a decision other than `proceed` or `proceed_degraded`, do not present the change as ready to commit. A `proceed_degraded` result may continue only when its degraded trust level and missing reviewer state are reported clearly.

## Scope

Allowed: documentation cleanup, workflow clarification, narrow reliability fixes,
verification script improvements, and small testbed maintenance.

Not allowed without a new explicit plan: new todo app features, UI work,
authentication, background jobs, large architecture rewrites, or deployment hardening.

## Writer Isolation

Use one writer per working tree. When multiple agents must work in parallel,
give each writer a separate git worktree or keep downstream agents confined to
their own project tree. Do not stage unrelated files produced by another agent.

## Planning And Interview Escalation

Use `docs/AUTOMATION_OPERATING_POLICY.md` for the full policy. In short:

- execute directly for clear, small, reversible work
- treat feasibility, advice, recommendation, and brainstorming questions as answer-only unless the user explicitly asks for execution
- ask one focused question when a single missing decision materially changes the result
- use a plan-first interview for broad, strategic, high-risk, or long-lived workflow changes
- inspect local evidence before asking, and label assumptions instead of presenting guesses as facts
- do not let "바로 진행" bypass destructive, credentialed, production, or materially scope-changing approval gates

## Required References

Use these files as the workflow baseline:

- `docs/WORKFLOW.md`
- `docs/AI_ROLES.md`
- `docs/AI_MODEL_ROUTING.md`
- `docs/AUTOMATION_OPERATING_POLICY.md`
- `docs/DOMAIN_PACKS.md`
- `docs/DOMAIN_PACK_AUTHORING_GUIDE.md` when creating or changing reusable domain packs
- `docs/INTERVIEW_PLAN_LAYER.md`
- `docs/SESSION_QUALITY_PLAN.md`
- applicable completion packs from `docs/*_COMPLETION.md`
- `scripts/verify.sh`
- `scripts/review-gate.sh`

## Model And Delegation Boundary

Use `docs/AI_MODEL_ROUTING.md` as the source of truth for leader-vs-subagent model
routing. The active Codex/GPT leader is runtime-selected; optimize cost/latency by
delegating bounded work to role-appropriate child agents or OMX lanes, not by
claiming the leader changed models mid-session.

## Ralph Completion Discipline

When Ralph is active, do not stop with plan-only, unpromoted, or tool/document drift
inside the user's requested scope. If a micro-review finds an unpromoted rule, missing
regular tool wiring, stale plan-only item, or operational gap that is safe and in scope,
promote it to the regular script/docs/template surface and verify it in the same loop.
Report only hard external blockers such as unavailable credentials, provider quota, or
explicit permission limits.

User-defined completion criteria are immutable acceptance scope; never narrow them. An
intermediate fail-closed safety gate (e.g. a no-order/no-candidate guard) is not completion:
complete only by proving the user's deliverable with its required evidence, or by an explicit
no-result final report carrying every required item (candidates, backtests, fallback loops,
AI unanimity), per the `completion_acceptance_scope` contract.

## Delegation Recording Protocol

When the leader delegates a unit of code work onto a model-class lane
(`fast_scan`, `low_cost_impl`, `standard_impl`, `frontier_review`), record the
decision via `scripts/record-lane-decision.py` into
`.omx/model-routing/lane-decisions.tsv`. Recording is required whenever a
delegation happens, not a one-time log step. It is observability evidence only:
it never carries completion authority or a reviewer verdict and never replaces
the delegation guardrails or the leader's diff review, per the
`delegation_recording_policy` contract.

## Evidence And Uncertainty

- Do not present guesses, inferred model availability, undocumented behavior, or unverified project assumptions as facts.
- If something is unclear, say what is known, what is inferred, and what evidence would confirm it.
- Prefer local runtime evidence for CLI/model availability; provider documentation is reference material unless the current task explicitly asks for external research.
- When forced to proceed with an assumption, label it as an assumption and keep the change reversible.

## Command Keywords

When the user asks `전역파일 설치해줘`, `전역 파일 설치`, or `global files install`,
run `./scripts/install-global-files.sh` from the repository root.

It creates/repairs repo-owned `~/bin` helper symlinks, writes the `AI_AUTO` shell
function to `~/.config/ai-lab/AI_AUTO.sh`, and adds a managed `~/.bashrc` source block.
It does not install external programs, configure credentials, run `automation-doctor
--fix`, or overwrite non-symlink files.

When the user asks `프로젝트 등록`, `ai-register`, or to register an existing project,
run `ai-register [/path/to/repo]` from the target repo. This records the repo in the
local registry without installing or overwriting project files. To clean stale entries,
run `ai-register --prune`.

When the user asks `옵시디언 푸시해줘`, `옵시디언 푸시`, or `obsidian push`, run
`./scripts/obsidian-autopush.sh` from the home checkout. It auto-promotes
allowlisted-surface, sanitized `local_private` drafts to `shareable_summary` and publishes
shareable drafts to the vault; off-allowlist or secret-like drafts stay local
(fail-closed). `--dry-run` previews; `--no-auto-promote` publishes only already-shareable.

When the user asks `AI_AUTO 최신 패치 적용해줘`, expand it as updating the globally-installed
AI_AUTO tool and refreshing installed domain packs: confirm the AI_AUTO source checkout is
current (`git -C ~/workspace/ai-lab pull`, or via `ai-home`) so work targets the latest
mainline, not a stale local copy, then run `ai-domain-pack` to refresh installed packs
(advisory; fail-closed on locally-edited/dirty packs). A project repo carries no vendored
framework files, so there is nothing to patch inside the project itself. Run
`./scripts/verify.sh` and `./scripts/review-gate.sh` for any resulting changes.
Do not patch `.omx/`, commit, or push unless explicitly asked.

When the user asks for `리빌드 플랜`, `리빌딩 플랜`, `rebuild plan`, or
`ai-rebuild-plan`, run `ai-rebuild-plan [/path/to/repo]` from the target repo.
Read-only planning: it may inspect git state, domain-pack references, and
refactoring candidates, but must not modify files or start rebuild.

When the user asks for `리빌드 실행`, `리빌딩 실행`, or `rebuild run`, do not
treat the phrase as approval to improvise a rebuild. Execution requires an
approved rebuild plan, refreshed domain-pack assumptions, behavior-locking tests
or smoke checks, explicit module boundaries, and the normal verify/review gates.

Optional rebuild support gates (context packing, codemod scan, boundary check)
are read-only by default; suggest them for explicit requests, material boundary
changes, stale required evidence, domain-critical work, or structural
verify/review failures. Missing optional tools must not block small reversible
work. `codemod apply`, autofix, or any write-capable tool requires an explicit
execution command tied to an approved scoped plan, reviewed dry-run diff/summary,
rollback path, and post-apply verification.

## Completion Report Format

Completion reports must start with a plain Korean summary, avoiding internal
variable names unless needed for reproduction or user action, then include:

- changed files
- diff summary
- verification command and result
- known warnings or limitations
