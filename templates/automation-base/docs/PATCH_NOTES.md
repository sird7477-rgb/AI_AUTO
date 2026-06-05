# AI_AUTO Patch Notes

This file records template-level changes by AI_AUTO template version. Review it
before patching an existing project, then use `ai-auto-template-status` to check
which files are template-owned, hybrid, or project-owned.

## 2026.06.05.3

- Review gate verification now marks in-gate runs with
  `AI_AUTO_IN_REVIEW_GATE=1`, letting the AI_AUTO home `verify.sh` skip nested
  review-runner self-tests that otherwise re-enter reviewer fixtures during an
  active review gate.
- This preserves full standalone `./scripts/verify.sh` coverage while reducing
  review-gate contention for real changes.

## 2026.06.05.2

- Added the `advisory_contract` backlog status to distinguish report-only or
  test-only contract surfaces from fail-closed runtime enforcement.
- Synchronized the template `todo-report.py` status taxonomy with the root copy
  so advisory contract rows remain non-active TODOs.

## 2026.06.05.1

- Added the global `ai-domain-pack` helper for deterministic optional
  domain-pack maintenance. It reports status read-only, keeps refresh dry-run by
  default, writes only with `--apply`, compares installed copy / install-time
  manifest / current AI_AUTO source, updates clean managed copies mechanically,
  adopts exact-match legacy copies, and fails closed for local modifications,
  dirty legacy copies, unreadable manifests, deliberately removed packs, or
  experimental source branches.
- New `aiinit` installs now seed sidecar domain-pack manifests under
  `.omx/domain-packs/.manifest/` while still preserving pre-existing installed
  pack directories. `ai-rebuild-plan`, global helper installation, bootstrap,
  and doctor checks now know about `ai-domain-pack`.
- `DOMAIN_PACKS.md`, `NEW_PROJECT_GUIDE.md`, `GLOBAL_TOOLS.md`, and the
  template README now distinguish managed domain-pack reference refresh from
  manual project instruction merges; refresh never patches project
  `AGENTS.md`, `docs/WORKFLOW.md`, or `scripts/verify.sh`.

## 2026.06.04.6

- Added `feedback-resolve`, a dry-run-by-default global helper that resolves
  feedback queue items by `repeat_key` across the same discovery surface as
  `feedback-collect`. It uses per-queue locks, refuses unknown keys and
  secret-like notes/sources, and avoids timestamp churn for idempotent repeated
  resolutions.
- Review-loop and browser-QA promotion refinements: accepted reviewer findings
  can now carry a targeted-recheck boundary that falls back to manual/full
  review when scope expands, and detailed UI behavior verification now requires
  a micro-plan covering layout, click targets, input handling, alerts/errors,
  sync/update behavior, and business mapping before browser/CDP evidence is
  treated as sufficient.
- Regularized remaining later-gated proposals as explicit contracts: reviewer
  first-pass posture must match the existing read-only reviewer mode, Stage 2
  guidance consolidation remains user-request/report-gated and blocks low-ROI
  edits, and domain-pack retrospectives require sanitized closeout feedback plus
  reusable-vs-project-specific separation.
- Documented scoped plain-guide folder publishing for Obsidian with reusable
  template wording: frontmatter-free guide bundles should use their own
  inventory/source/link validator before vault copy instead of being forced
  through `knowledge-notes.py` validation.

## 2026.06.04.5

- `collect-review-context.sh` adds a report-only `Standard Flow Preservation
  Audit`. Driven by `STANDARD_FLOW_*` env signals, it mirrors the
  `standard_flow_preservation_policy` contract: hiding or replacing a
  framework's standard business field behind custom UI requires an impact map
  plus regression evidence, a parallel-replacement-only custom field is flagged,
  and the audit never blocks the gate. `PLANNING_VISUALIZATION_GUIDE.md` adds
  framework-neutral wireframe-structure, wireframe-authoring, and
  standard-flow-preservation kernels; framework-specific names stay
  project-owned.

## 2026.06.04.4

- `doc-budget.sh` adds a plan/spec filename-label convention: files named
  `*.plan.md` or `*.spec.md` are exempt from the guidance-bloat budget by
  default (no `DOC_BUDGET_EXEMPT_GLOBS` config needed), in both the
  `doc_budget_is_exempt` check and the cumulative-diff pathspecs. Their
  net-added line volume is printed on a separate
  `plan/spec labeled artifacts net added lines` line so it stays visible rather
  than silently dropped. Builds on the ST-P1-24 guidance/content scoping.

## 2026.06.04.3

- `collect-review-context.sh` adds a report-only `Spec Code Alignment Audit`.
  Driven by `SPEC_ALIGN_*` env signals, it mirrors the
  `spec_code_alignment_policy` contract: after a medium-or-larger patch, or
  before applying a reviewer-suggested scope change, the spec-row to code
  mapping is mandatory. It validates each row like the contract — an unknown
  patch size or a malformed/unknown-status row is reported as invalid rather
  than counted as a clear mapping — and `blocked` / `needs_user_confirmation`
  rows are surfaced as report-only attention. The audit never blocks the gate.

## 2026.06.04.2

- `collect-review-context.sh` adds a report-only `Planning Visual Gate Audit`.
  Driven by `PLANNING_VISUAL_*` env signals, it mirrors the
  `planning_visual_gate_policy` contract: when a spec crosses complexity or
  layout thresholds it proposes the structure model / flow visual / optimizer
  pass (and a UI wireframe for layout-heavy specs) as candidates, keeps the
  source spec authoritative, and never blocks the gate.

## 2026.06.04.1

- `OBSIDIAN_INTEGRATION.md` documents the large-reference baseline pattern:
  split large ERP schema/SDK/version references into `index`, `slim`, and
  `full` tiers; run micro-level consistency checks before vault storage; and
  keep one curated baseline in the vault instead of copying full exports into
  every project.
- `summarize-ai-reviews.sh` infers the active principal from the run summary's
  `Active principal:` line when `AI_AUTO_PRINCIPAL` is unset, so a post-hoc
  summary or a Claude/Gemini principal-rotation run is not misclassified as
  Codex-only coverage. A trailing CR is stripped and an unsupported inferred
  token keeps the existing default rather than blanking the principal.
  `test-review-summary.sh` covers the inferred-principal and unsupported-token
  paths.

## 2026.06.03.3

- MicroWork (ST-P1-21), part 2: `collect-review-context.sh` adds a self-contained,
  report-only `MicroWork Audit` section. When a micro-unit file (`MICRO_WORK_FILE`
  or `.omx/micro/current.json`) is present, it reports `scope_drift` /
  `non_goal_leak` against the current changes (porcelain parsing handles renames
  and spaces; non-object JSON is reported, not fatal). It never blocks the review
  gate and adds no runtime or authority.

## 2026.06.03.2

- MicroWork (ST-P1-21), part 1: registered the side-effect-free `micro-work`
  global helper in the managed helper-link set checked by `automation-doctor.sh`
  (and the home-only `install-global-files.sh` / `bootstrap-ai-lab.sh`). The
  validator/CLI/wrapper add no runtime, scheduler, queue, UI, or completion
  authority.

## 2026.06.03.1

- `OBSIDIAN_INTEGRATION.md` documents the on-demand `scripts/obsidian-autopush.sh`
  publish path: it pushes only shareable drafts (`shareable_summary` /
  `external_private_vault`) that pass a secret/redaction preflight, reads the
  vault from `obsidian.ai_auto_vault_dir` in `.omx/local-config.json`, fails
  closed on secret-like content, and never pushes `local_private`. The home
  startup notice stays read-only and does not push automatically.

## 2026.06.02.9

- `collect-review-context.sh` adds `REVIEW_UNTRACKED_ALLOWLIST` (comma/newline
  list of paths, directory prefixes, or globs). When set, only matching
  untracked artifacts count as blocking review material; out-of-scope untracked
  files are still reported but do not stall the gate, so a docs/spec-draft
  targeted review is not blocked by an unrelated working tree. Empty (default)
  keeps every material untracked file in scope. README documents the targeted
  review usage.

## 2026.06.02.8

- Ralph Completion Discipline now states that user-defined completion criteria
  are immutable acceptance scope and that an intermediate fail-closed safety
  gate (e.g. a no-order or no-candidate guard) is not completion: completion
  requires either the proven deliverable with its required evidence or an
  explicit no-result final report that still carries every required evidence
  item. (Home repo adds the matching `completion_acceptance_scope` contract.)

## 2026.06.02.7

- Restored the double-confirm deletion guard in `archive-omx-artifacts.sh`:
  `--delete` alone now refuses and exits non-zero before touching any files;
  destructive cleanup requires `--delete --confirm-delete`, while
  `--dry-run --delete` still previews the deletions. This is the recommended
  template safety default; weaken it only as a documented opt-in.
- README and `SESSION_QUALITY_PLAN.md` updated to describe the double-confirm,
  and `verify.sh` covers refusal, dry-run preview, and confirmed deletion.

## 2026.06.02.6

- Hardened `summarize-ai-reviews.sh` verdict parsing so an echoed prompt can no
  longer be read as a reviewer's approval: `extract_verdict` now skips
  code-fenced blocks, analyzes only the first real Verdict heading, and treats
  more than one distinct verdict token in that section (a prompt-echoed choice
  list) as ambiguous, yielding no verdict (fail safe).
- Added `test-review-summary.sh` coverage for both paths: a prompt-echo choice
  list and a fenced-only verdict each fall back to single-reviewer
  `review_manually` instead of being counted as an approving reviewer.

## 2026.06.02.5

- Reworked `doc-budget.sh` to separate lean AI guidance from legitimately large
  project/spec docs: the net-added budget now measures cumulatively against the
  integration branch merge-base (`DOC_BUDGET_BASE_REF`, default `main`) so
  splitting a guide across commits cannot evade it; guidance scope is top-level
  only so content/spec docs in subdirectories (e.g. `docs/specs/`) are exempt,
  with `DOC_BUDGET_EXEMPT_GLOBS` for extra exemptions, applied consistently to
  both the net-added diff and the totals (fixing the prior scope mismatch).
- Duplicate-line detection now also covers template docs, and the
  `DOC_BUDGET_TEMPLATE_PATCH` escape hatch requires
  `DOC_BUDGET_TEMPLATE_PATCH_REASON` so the bypass is recorded, not silent.

## 2026.06.02.4

- Fixed principal misdetection in `run-ai-reviews.sh`: valid launcher evidence
  now selects the principal when `AI_AUTO_PRINCIPAL` is unset, an explicit
  selection that contradicts valid evidence fails closed, and defaulting to
  codex with no declaration emits a visible notice instead of silently
  misrouting a non-codex session into its own reviewer slot.
- Anchored principal evidence lookup and workspace comparison to the repo root
  (`git rev-parse --show-toplevel`, with a `pwd -P` fallback) in both the
  `run-ai-reviews.sh` reader and the `ai-principal-runtime.sh` launcher writer,
  so a launch recorded from a subdirectory still matches the runner, and
  switched the evidence-line checks to fixed-string matching (`grep -Fqx`) so
  paths with regex metacharacters compare correctly.

## 2026.06.02.3

- Added the evidence-driven tuning guard to `docs/AI_MODEL_ROUTING.md`: a lane's
  default model-class selector changes only after repeated `lane-decisions.tsv`
  evidence across several runs, never from a single announcement or one-off, and
  the standard/planner/verifier/reviewer lanes are never globally downgraded.
  With no accumulated evidence yet, no default change is warranted.

## 2026.06.02.2

- Added the `low_cost_impl` lane contract to `docs/AI_MODEL_ROUTING.md`: a
  separate, guardrail-gated, non-authoritative bounded fast-class lane (applied
  at runtime as a per-principal agent outside this repo's review-gate).
- Added `scripts/record-lane-decision.py`, a validated per-unit recorder that
  appends model-routing lane decisions to a dedicated
  `.omx/model-routing/lane-decisions.tsv`; records are evidence only and carry
  no completion authority.

## 2026.06.02.1

- Added an observe-only "Principal Class Lanes" block to the model-routing
  report (`discover-ai-models.sh`) and a report-only "Model Routing Lane Audit"
  to review context (`collect-review-context.sh`), recording the per-principal
  fast/standard/frontier lane contract without changing routing behavior or
  granting routing records any completion authority.
- Documented the four provider-neutral model-class lanes (`fast_scan`,
  `low_cost_impl`, `standard_impl`, `frontier_review`) in
  `docs/AI_MODEL_ROUTING.md`, including the Gemini agy-only / class-fixed
  constraint.

## 2026.06.01.2

- Raised the generated AI tmux wrapper's runtime `nofile` soft limit before
  launching `codex`, `claude`, or `agy`, including inside tmux command strings,
  so existing low-limit shells or tmux servers do not trigger Claude/agy startup
  failures.
- Scoped generated tmux session names by runtime as well as project, so
  parallel terminals can open `codex`, `claude`, and `agy` for the same project
  without later runtimes attaching to the first runtime's session.
- Added `AI_AUTO_NOFILE_LIMIT` as a numeric override for the wrapper's default
  file descriptor target.

## 2026.06.01.1

- Added `--install-ai-tmux-auto-entry` to install managed interactive tmux
  wrappers for `codex`, `claude`, and `agy`, with `AI_AUTO_TMUX_AUTO=0` as the
  shared opt-out and runtime-specific opt-outs for Claude and agy.
- Preserved the existing Codex-only `--install-codex-tmux-auto-entry` behavior
  and kept non-interactive review/adapter calls outside tmux auto-entry.
- Documented that shell wrappers do not change runtime adapter permission
  contracts: Codex remains the read-only sandboxed adapter, while Claude and
  agy/Gemini remain logical-read-only adapters.

## 2026.05.31.5

- Promoted Obsidian vault organization from flat inbox storage to generated
  project namespace folders, project/surface/repeat-key hubs, promotion/views
  pages, and generated note `## Links` sections.
- Added `knowledge-notes.py migrate-vault` for reviewed vault backups and
  migration from `Inbox/<project--hash>` to `Projects/<project--hash>`.
- Updated `knowledge-collect --push` to preserve the project namespace collision
  guard while writing new vault notes into the promoted `Projects/` layout.

## 2026.05.31.4

- Mark Obsidian knowledge drafts after approved vault pushes with
  `sync_state: pushed_to_obsidian` plus `obsidian_pushed_hash`, and document
  that normal pending checks hide unchanged mirrored notes unless
  `--include-pushed` is used for audit.
- Clarified that the startup pending-output check only covers registered
  projects, with an `ai-register --prune` / `ai-register /path/to/repo` handoff
  for moved or missing project paths.

## 2026.05.31.3

- Updated the template README smoke-test guidance so Gemini large-prompt
  behavior matches the fail-closed runtime adapter contract instead of the old
  stdin fallback wording.

## 2026.05.31.2

- Changed agy/Gemini prompt-only large prompt handling to fail closed when
  `--prompt-file` is unavailable, so automation no longer depends on placeholder
  prompts plus stdin append behavior.
- Added verification for the unsafe agy placeholder path and wired
  `GEMINI_PROMPT_ARG_MAX_BYTES` into the runtime adapter threshold.
- Added an External SSD Migration Runbook to `docs/OBSIDIAN_INTEGRATION.md` for
  moving AI_AUTO projects and Obsidian vaults while preserving internal
  control-plane state and curated `.omx` export boundaries.
- Added the UI Design Quality Gate to the UI completion pack for domain fit,
  layout stability, text fit, assets, controls, and browser evidence.

## 2026.05.31.1

- Added the principal runtime contract so `codex`, `claude`, or `gemini` can be
  recorded as the active AI_AUTO/OMX principal while preserving the same
  repo-local permission matrix and `.omx/*` artifact paths.
- Added principal-aware review rotation: the active principal is excluded from
  self-review, and the remaining runtimes are assigned as reviewers.
- Added `scripts/ai-principal-runtime.sh` as the shared contract helper for
  principal normalization, reviewer rotation, permission-profile reporting, and
  launcher-owned external-principal evidence markers.
- Updated the workflow guide so Codex principal-rotation coverage is documented
  separately from degraded fallback coverage.
- Promoted principal-subagent substitute review: when an expected reviewer is
  unavailable, the active principal's subagent can cover that lane as regular
  review coverage when it provides a usable verdict and direct file inspection
  evidence.
- Added Ralph completion discipline to the regular agent contract: plan-only
  gaps, unpromoted rules, missing tool wiring, and doc/tool drift inside the
  requested scope must be promoted and verified in the same loop unless blocked
  by an external hard limit.
- Added fail-closed external-principal validation: `AI_AUTO_PRINCIPAL=claude` or
  `AI_AUTO_PRINCIPAL=gemini` requires matching launcher-owned evidence before
  self-review is skipped.
- Added `scripts/docker-config-guard.sh` so WSL Docker Desktop credential-helper
  failures can be avoided with a temporary Docker config during verification.
- Normalized reviewed template-patch guidance budget handling so duplicated
  root/template guide additions below the hard limit do not leave warning-only
  residue after review.
- Updated `ai-auto-template-status` so the AI_AUTO source checkout reports
  `source_checkout` instead of confusing install-target missing marker rows.
- Tightened review artifact retention defaults to archive old `.omx/review-results`
  files after 120 active files while preserving recent evidence by default.
- Renamed gate-facing principal review summaries away from legacy Codex fallback
  wording while keeping old artifact names and manifest labels readable for
  compatibility.

## 2026.05.29.8

- Enforced persona review-gate classifier integrity in the review summary:
  missing or malformed `Diff Scope Summary` classifier fields now force manual
  review instead of allowing a normal proceed verdict.
- Added review-summary fixtures for missing policy, malformed strict policy,
  valid strict policy, and docs-only `verify_only` classification.

## 2026.05.29.7

- Updated user-facing docs for the optional Codex startup notice so the
  documented output matches the `AI_AUTO UPDATE CHECK` block and
  `action: AI_AUTO 최신 패치 적용해줘` wording.
- Documented the AI_AUTO home `OBSIDIAN OUTPUT CHECK` startup notice as a
  bounded read-only pending-draft check that only prints an approval handoff and
  never pushes to a vault automatically.

## 2026.05.29.6

- Added the `operational_clear` TODO status so completed workflow items can be
  distinguished from contract-only coverage after their real caller, runtime
  guard, synchronized surfaces, and verification evidence exist.
- Added explicit tool-adoption status output to the template automation doctor
  and source checkout bootstrap for `shellcheck` and `hyperfine` so
  required-vs-optional tool state is visible in the regular readiness workflow.
- Added a phase/scope guard section to review context and a matching review
  summary block so out-of-phase edits require an allowed path, a deferred
  `path|reason` record, or manual review before commit readiness.
- Added a bounded review-revision task artifact path for explicitly accepted
  structured reviewer findings, with stop artifacts for unclear output,
  reviewer disagreement, repeated verification failure, missing changed diff,
  or more than two revision cycles.
- Added a report-only completion-pack routing audit to review context so pack
  inventory, explicit triggers, file-scope trigger hints, and GStack
  documentation-generation reference-lens handling are visible without adding a
  new runtime lane.
- Added a report-only product challenge audit to review context so broad or
  strategic planning work records a challenge reason while routine small work
  and already approved plans are explicitly skipped.
- Added a report-only visual artifact audit to review context so Excalidraw,
  paired specs, stale exports, and ambiguous source ownership are visible
  without installing diagram tooling or treating unreviewed drawings as
  implementation contracts.
- Added a report-only browser QA evidence audit to review context so target,
  steps, screenshot notes, CDP credential boundaries, redaction warnings, and
  visual-verdict authority limits are visible without enabling an auto-fix loop.
- Added persona lens fields to diff scope context so active lenses, integrator
  requirement, review-gate policy, and policy reasons are visible without
  creating a standing persona roster or new reviewer process.

## 2026.05.29.5

- Tightened `scripts/todo-report.py` so complete-status items that still mention
  missing runtime wiring, contract-only coverage, non-active tooling, parity
  drift, contract-cleared-only risk work, separate future work, or later
  execution are reported as policy attention and fail active-TODO verification.
- Kept the template-owned TODO report script in sync with the source checkout so
  downstream AI_AUTO patch checks inherit the partial-completion guard.

## 2026.05.29.4

- Added `scripts/todo-report.py` to read the canonical backlog and fail
  verification when active TODO items remain.
- Wired review-gate diff-scope consumption so generated scope, review intensity,
  and required checks are printed before verdict synthesis.
- Added process-cleanup runtime fixture coverage for timeout/reap evidence.

## 2026.05.29.3

- Promoted ShellCheck warning-level diagnostics for the AI_AUTO source checkout
  by wiring `shellcheck -S warning` into `scripts/verify.sh`.
- Split guidance budget accounting into primary project guidance and template
  guidance budgets so intentional template mirrors do not trip a single
  aggregate 9000-line warning.
- Updated template documentation for the installed ShellCheck/Hyperfine tool
  relationship and required-vs-observational gate boundaries.

## 2026.05.29.2

- Added optional `scripts/benchmark-command.py` evidence capture. It uses
  `hyperfine` only when already available and otherwise records unavailable
  evidence without installing tools or claiming readiness.
- Added benchmark helper wiring to template installation and doctor checks.
- Scoped the untracked-artifact review guard to its own context section so
  fixture text inside diffs cannot falsely force manual review.
- Treat untracked tests as material review artifacts so new tests cannot be
  omitted from commit-candidate review context without a manual-review signal.

## 2026.05.29.1

- Added a short review-verdict summary block so final decision, coverage, trust,
  missing reviewers, and authority caveats are visible without reading the whole
  reviewer artifact.
- Added diff-scope and untracked-review guard sections to review context
  generation so material untracked plan/doc/script/tool artifacts are visible or
  explicitly require manual review before commit readiness.
- Wired the untracked-review guard into review verdict summarization so material
  untracked artifacts without included content force manual review instead of
  proceeding from reviewer approvals alone.
- Synced review-summary and review-context regression fixtures with the new
  summary and untracked-artifact safeguards.

## 2026.05.28.4

- Tightened review summary regression coverage so `proceed` requires normal
  multi-reviewer trust, degraded fallback success reports degraded trust, and
  failed or missing external reviewers cannot be silently counted as normal
  approvals.
- Added contract expectations for degraded review reporting: callers must
  provide explicit degraded-trust and missing-reviewer reporting evidence before
  a degraded review gate can support completion authority.
- Documented the P0 contract-shape changes: reflection sidecars cannot own any
  work-state transition, promotion requests must carry review-integrity
  evidence, and sidecar verdict preservation now exposes authority violations
  for consumers to handle explicitly.

## 2026.05.28.3

- Added the read-only `ai-gstack-contract` helper wiring for AI_AUTO's GStack
  benchmark adoption contracts, including global helper installation,
  bootstrap/doctor checks, and verification coverage.
- Added missing-root override hints for `jwlist` and `sirdlist` so users see the
  exact environment variable to set when local project folders live elsewhere.
- Synced automation-doctor's ai-lab helper-link awareness with
  `ai-gstack-contract` so global helper repair checks stay consistent between
  the repo copy and template copy.

## 2026.05.28.2

- Clarified ambiguity handling for follow-up meta requests so root-cause,
  guidance-update, or recurrence-prevention questions stay anchored to the
  specific failure event the user identified instead of drifting to adjacent
  technical topics.
- Moved the repo-owned default local project and vault paths from
  `/mnt/c/JSJEON/...` to `/mnt/z/JSJEON/...`; users who keep projects on the old
  drive or under the former `Project_JW/99. 개발개발` grouping should override
  `AI_AUTO_JW_PROJECT_ROOT`, `AI_AUTO_SIRD_PROJECT_ROOT`, and local vault paths.
- Made installed Codex tmux auto-entry default on after
  `--install-codex-tmux-auto-entry`; use `AI_AUTO_CODEX_TMUX_AUTO=0 codex` for
  direct execution while scripts, pipes, redirects, and nested tmux sessions
  still bypass tmux. Reverting to direct execution is currently a per-shell
  opt-out or managed shell-function removal.
- Documented the external SSD sandbox boundary so `/mnt/z` sandbox read-only
  evidence is not mistaken for SSD failure without an approved real write probe.
- Added post-Ralph guidance-bloat handling guidance: analyze first, then propose
  a two-stage cleanup plan before editing guidance documents.

## 2026.05.27.2

- Added opt-in `codex` tmux auto-entry support through the managed shell
  wrapper. The feature activates only with `AI_AUTO_CODEX_TMUX_AUTO=1` for
  interactive terminal calls outside tmux, and it preserves direct execution for
  scripts, pipes, redirects, nested tmux sessions, and normal Codex calls.
- Kept the tmux wrapper in the same generated `codex()` chain as the existing
  template drift notice so opt-in shell integrations do not overwrite each
  other.

## 2026.05.27.1

- Added managed shell shortcuts `jwlist` and `sirdlist` for drilling into local
  project folders and entering directories once common project markers are
  found.
- Documented the local project-list shortcuts alongside the existing `AI_AUTO`
  and bare `tmux` shell integration, with verification coverage for generated
  shell functions and override roots.

## 2026.05.25.3

- Hardened Obsidian knowledge vault pushes so invalid explicit projects cannot
  regenerate an empty index, validation rejects symlink note escapes, failed
  review-gate verdicts can still produce local drafts, and same-name projects
  use hash-suffixed vault inbox namespaces.
- Clarified `knowledge-collect` operating docs, sync boundaries, global helper
  lists, Codex drift notice output, and local/private vault push requirements.

## 2026.05.25.2

- Added automatic local knowledge draft capture from sanitized feedback and
  review-gate signals, plus AI_AUTO home `knowledge-collect` for validated
  cross-project inspection and explicit vault push.

## 2026.05.25.1

- Added `docs/OBSIDIAN_INTEGRATION.md` to define Obsidian as a sanitized
  knowledge store under AI_AUTO control, not a review, approval, or runtime
  authority.
- Added `scripts/knowledge-notes.py` for curated incident, finding, lesson,
  technical-spec, and promotion-candidate notes with frontmatter validation,
  dry-run default behavior, explicit write/output controls, local-draft guards,
  secret checks, source hashing, and generated indexes.
- Wired the Obsidian knowledge workflow into template installation, doctor,
  template-status, and verification coverage, including external SSD/vault
  operating guidance. Because the helper is Python-based, doctor now treats
  `python3 >= 3.9` as a required runtime.

## 2026.05.24.5

- Split AI automation trend hardening so the always-loaded control contract
  stays short while recurring trend research lives under `docs/research/`.
- Added template installer, status, and verification coverage for the nested
  trend research guide.

## 2026.05.24.4

- Clarified hybrid/project-owned template patch reporting with
  absorbed/rejected/deferred outcomes.
- Added `DOC_BUDGET_TEMPLATE_PATCH=1` for reviewed template-owned guide additions.
- Downgraded missing optional Gemini/agy stabilizing flags to doctor info notes.

## 2026.05.24.3

- Added AI automation trend hardening guidance for agent identity, tool
  permission classes, kill switch/revoke handling, local automation
  observability, and recurring trend research.
- Linked the hardening guide from workflow, runtime adapter, model routing,
  observability, session-quality, and template onboarding docs without granting
  new runtime permissions.
- Added verification coverage so root/template hardening guidance and template
  status entries stay in sync.

## 2026.05.24.2

- Reduced guidance document budget pressure by moving low-cost lane routing
  details into `docs/AI_MODEL_ROUTING.md` while keeping delegation safety
  boundaries in `docs/AUTOMATION_OPERATING_POLICY.md`.
- Shortened template `AGENTS.md` onboarding and rebuild keyword guidance by
  preserving triggers/fail-closed behavior and delegating detailed mechanics to
  linked workflow documents.
- Mirrored the active and template `docs/AUTOMATION_OPERATING_POLICY.md`
  structure so new projects receive the same guidance-budget reduction.
- Added template-sync verification for active/template routing and operating
  policy docs.

## 2026.05.24.1

This version consolidates the runtime-adapter branch changes and records the
template versioning guard added after review.

- Added the AI runtime adapter contract and `scripts/ai-runtime-adapter.sh` so
  Codex, Claude, Gemini, and agy review paths use explicit read-only capability
  checks before execution.
- Routed Claude/Gemini split reviews and degraded Codex substitute review through the
  adapter while preserving command overrides, external runner propagation,
  sandbox/no-edit flags, and failure diagnostics in review artifacts.
- Added `docs/AI_RUNTIME_ADAPTERS.md` and verification coverage for capability
  refusal, relative path handling with `--cd`, external runner adapter
  propagation, adapter diagnostics, and template/root sync.
- Added experimental template source reporting and install guards so non-main
  AI_AUTO branches report disabled template patching unless explicitly
  overridden.
- Tightened completion guidance and verification so template-owned changes must
  bump `AI_AUTO_TEMPLATE_VERSION` and keep the latest patch-note heading in sync.

## 2026.05.21.2

- Added the `AI_AUTO 최신 패치 적용해줘` keyword so projects can request the
  AI_AUTO template patch workflow without retyping the full prompt.
- Updated the optional Codex drift notice to print the short patch keyword when
  template drift is detected.
- Documented that the keyword still preserves project-specific rules, avoids
  generated `.omx/` artifacts, and requires normal verification/review gates.

## 2026.05.21.1

- Documented Codex native goal mode as an optional thread-local completion aid,
  not an AI_AUTO control plane.
- Clarified that AI_AUTO/OMX state, checkpoints, plan artifacts, verification,
  review gates, approvals, and latest user instructions remain separate sources
  of truth.
- Added verification coverage so root and template session-quality guidance keep
  the same native-goal boundary.

## 2026.05.20.2

- Updated the opt-in Codex drift notice so each AI_AUTO-managed project reports
  template drift only once per shell session.
- Added the latest template patch-note heading and patch-note path to the drift
  notice so users can inspect the home checkout review notes before patching.
- Bumped the template version marker to match the latest patch-note version used
  by `ai-auto-template-status`.

## 2026.05.20.1

- Added `scripts/doc-budget.sh` as the Stage 1 guidance document budget check.
- Added `scripts/guidance-duplicate-report.sh` for read-only Stage 2 duplicate
  and consolidation reports when requested after a budget warning.
- Updated verification to run the guidance budget check, exercise budget
  accounting, test duplicate-report fallback behavior, and confirm template
  installation coverage.
- Added workflow policy requiring final code diffs to be compared with
  applicable plan, specification, or design artifacts before completion reports.
- Added completion-report guidance to explain user-facing results in plain
  Korean first, with technical identifiers included only when needed for
  reproduction or user action.
- Updated onboarding and template guidance so new projects decide spec/design
  alignment ownership, Korean-first report language, and guidance document
  budget handling during setup.

## 2026.05.15.1

- Added ownership and patch-policy columns to `ai-auto-template-status` output.
- Classified managed files as `template-owned`, `hybrid`, or `project-owned`.
- Marked `AGENTS.md` and `docs/WORKFLOW.md` as `review-merge` so project-specific
  rules are preserved during patch review.
- Marked `scripts/verify.sh` as `inspect-only` because target projects are
  expected to replace the onboarding placeholder with project-specific checks.
- Documented that generated/runtime `.omx/` artifacts are outside the managed
  patch manifest.
- Added this patch-note file so projects can inspect version changes before
  applying template updates.
- Added automatic lightweight AI review context for small tracked diffs. The
  default review context now stays diff-centered for small changes and omits
  planning/reference-file bodies unless `REVIEW_CONTEXT_DETAIL=full` is set.

## 2026.05.14.1

- Initial managed automation template version marker.
