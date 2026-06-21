# AI_AUTO Patch Notes

This file records template-level changes by AI_AUTO template version. Review it
before patching an existing project, then use `ai-auto-template-status` to check
which files are template-owned, hybrid, or project-owned.

## 2026.06.20.9

- off-manifest shadow detection (Phase 2, the literal jw_dev trigger). The version-staleness
  gate (1c) is scoped to managed files, so it cannot see a project-PRIVATE hand-copy of a
  home script the install never tracked -- exactly jw_dev's stale scripts/verify-machinery.sh.
  `ai-auto-template-status --inventory` now lists the home script/tool basenames a project
  could shadow, and automation-doctor (downstream only) WARNs about any project-local
  scripts/ or tools/ file whose basename is in that inventory but is NOT in the install
  manifest -- a likely stale hand-copy to remove or send upstream. Managed files (in the
  manifest) and a project's own non-home scripts are not flagged; the source checkout and
  an unreachable home both skip (fail-open). verify-machinery asserts the shadow is flagged,
  a non-home script and a managed file are not, and the source checkout skips. (Phase 2 of
  the template-distribution redesign; plans/AI_AUTO_TEMPLATE_DISTRIBUTION_REDESIGN_PLAN_2026-06-20.md.)

## 2026.06.20.8

- downstream template-staleness gate in `review-gate.sh` (Phase 1c, the jw_dev-class fix).
  Before verification, the gate calls the global `ai-auto-template-status --json` and surfaces
  template-OWNED drift that means "behind" the home template (drift outdated/missing): WARN by
  default (loud, with the `ai-template-refresh --apply` remediation) and ENFORCE (blocked
  verdict, exit 6) under AI_AUTO_TEMPLATE_STALENESS=block; =off silences it. hybrid /
  project-owned drift and template-owned local divergence (locally_edited/conflict) are
  reported but never gate. Fails OPEN: an absent status helper, an unreachable home template,
  or the AI_AUTO source checkout skips without blocking. Warn-by-default honors the migration
  order (re-sync shipped in 1b; flip to block per project once converged). verify-machinery
  asserts block/warn/off/fail-open end-to-end through the installed gate. (Phase 1c of the
  template-distribution redesign; plans/AI_AUTO_TEMPLATE_DISTRIBUTION_REDESIGN_PLAN_2026-06-20.md.)

## 2026.06.20.7

- `ai-template-refresh` -- one-command project re-sync to the current template (new
  single-source global helper `tools/ai-template-refresh`, registered in install-global-files
  / bootstrap / automation-doctor). Consumes the 3-way drift from ai-auto-template-status
  and, modeling the ai-domain-pack refresh contract, refreshes ONLY template-owned files
  that are `outdated` (upstream moved on, no local edit) or `missing`; it reports and never
  overwrites template-owned `locally_edited`/`conflict`/`no_baseline`, every `hybrid` file
  (AGENTS.md, docs/WORKFLOW.md -> manual review-merge), and every `project-owned` file
  (scripts/verify.sh). Dry-run by default; `--apply` is gated to the stable (main) channel,
  re-stamps the version, regenerates the guidance baseline, and re-baselines ONLY the
  refreshed files in the install manifest (so a local edit keeps its classification and a
  later refresh cannot clobber it). verify-machinery asserts the refresh/preserve/channel-
  gate contract incl. local edits surviving repeated refreshes. (Phase 1b of the template-
  distribution redesign; plans/AI_AUTO_TEMPLATE_DISTRIBUTION_REDESIGN_PLAN_2026-06-20.md.)

## 2026.06.20.6

- `ai-auto-template-status` 3-way drift classification. Now reads the install baseline
  (`.ai-auto/template-manifest.json`) and emits a per-file `drift` (text DRIFT column +
  `--json` field): `in_sync`, `outdated` (upstream moved on, no local edit -> safe to
  refresh), `locally_edited` (project edited, upstream unchanged), `conflict` (both
  changed), `missing`, `no_baseline` (pre-manifest install). This is the shared comparison
  authority the planned re-sync (`ai-template-refresh`) and downstream gate consume: the
  gate must BLOCK on template-owned `outdated`/`missing` (behind) but only WARN on
  `locally_edited` (legitimate customization). verify-machinery asserts a project edit
  classifies as locally_edited and an upstream change as outdated. single-source helper;
  the bump is for the verify-machinery test. (Phase 1a of the template-distribution
  redesign; plans/AI_AUTO_TEMPLATE_DISTRIBUTION_REDESIGN_PLAN_2026-06-20.md.)

## 2026.06.20.5

- review reviewer invocation no longer inherits the caller's stdin (fixes a split-review
  gate/verify flake). `scripts/ai-runtime-adapter.sh` invoked `agy` (Gemini) WITHOUT
  redirecting stdin, so a reviewer CLI that reads stdin (and the verify stub that models
  one) blocked until the review timeout (exit 124) whenever run-ai-reviews was called with
  an open stdin -- a gate, a pipe, or a background harness. agy gets its prompt via
  --prompt/--prompt-file, so its stdin is now /dev/null (codex/claude already redirect
  stdin from the prompt file). verify-machinery's agy split test now feeds run-ai-reviews a
  held-open FIFO stdin so a regression fails deterministically instead of flaking.

## 2026.06.20.4

- base-file install manifest (`install-automation-template.sh` -> `.ai-auto/template-manifest.json`,
  tracked). aiinit now records the install-time baseline: `template_version` + sha256 of every
  managed file AS INSTALLED (path set reused from the conflict-check `MANAGED_PATHS`, so it never
  drifts from what was copied), modeling the domain-pack manifest. This is the load-bearing
  prerequisite for the planned downstream staleness gate's 3-way diff (template source /
  installed / install baseline) -- it distinguishes a project edit (installed != baseline) from
  an upstream change (source != baseline, installed == baseline). Base files previously had no
  per-file baseline (only AGENTS.md + docs via guidance-baseline). verify-machinery asserts the
  manifest exists, is valid, covers managed files, and its baseline shas match the installed
  files. (Phase 0b of the template-distribution redesign;
  plans/AI_AUTO_TEMPLATE_DISTRIBUTION_REDESIGN_PLAN_2026-06-20.md.)

## 2026.06.20.3

- `ai-auto-template-status --json` (single-source global helper): machine-readable
  per-file `{state, path, template_path, ownership, patch_policy}` + installed/current
  version + counts, mirroring `ai-domain-pack --json`. This is the data prerequisite for a
  downstream template-staleness gate that must block on `ownership==template-owned` drift
  only (warn on hybrid/project-owned) -- the human text table was unsafe to scrape.
  verify-machinery asserts the JSON structure and that a template-owned edit is reported
  `different` with ownership intact. (Phase 0 of the template-distribution redesign;
  plans/AI_AUTO_TEMPLATE_DISTRIBUTION_REDESIGN_PLAN_2026-06-20.md.)

## 2026.06.20.2

- knowledge harvest writes to the PRIMARY checkout (`tools/knowledge-capture`, a
  single-source global helper -- no template mirror). The post-commit auto-harvest wrote
  finding drafts into the COMMITTING worktree's `.omx/knowledge/drafts`, but linked
  worktrees are ephemeral: `ai-tmux-worktree` auto-removes a clean worktree (its
  removability check ignores gitignored `.omx`), silently DESTROYING the orphaned draft,
  and `obsidian-autopush` never collected them (HOME_ROOT + registry only). Harvest now
  resolves the primary worktree via `git rev-parse --git-common-dir` (its parent --
  resolving the relative result against the repo path) and writes+dedups there, so every
  worktree feeds the durable primary `.omx` that autopush already collects (zero
  collection change). `write_draft` is concurrency-safe (mkstemp in the dest dir + atomic
  replace; deterministic content makes concurrent same-finding writes idempotent).
  verify-machinery asserts a linked-worktree harvest lands in the primary, not the
  worktree -- that test addition is the only template-mirrored change (the harvest fix is
  single-source). Migration of existing live-worktree orphans is a one-time manual sweep.

## 2026.06.20.1

- migrate-vault duplicate-target collision guard (`knowledge-notes.py` + template
  mirror). `migrate_vault` only guarded against overwriting an already-existing target;
  two DISTINCT source notes mapping to the same not-yet-existing target (e.g.
  `Inbox/<proj>/x.md` and `Legacy/x.md` both -> `Projects/<proj>/x.md`) each passed, and
  the second `shutil.move` then silently clobbered the first -- data loss, with no signal
  even in `--dry-run`. A collision check now runs before the dry-run return (dry-run and
  real execution both fail closed) with `multiple notes would migrate to the same target:
  <target>`. verify-machinery asserts the dup-target case is blocked. Surfaced by a
  downstream jw_dev gate failure; the canonical coverage lives in verify-machinery (the
  drifted standalone test-knowledge-notes.sh is superseded on template re-sync).

## 2026.06.19.1

- Finding-trailer auto-harvest (`hooks/post-commit` + `docs/WORKFLOW.md` dev-loop step,
  + template mirrors). Substantive-finding capture was manual-only: `knowledge-capture`
  harvests `Finding:`/`Finding-Evidence:`/`Finding-Scope:` commit trailers into local
  knowledge drafts, but nothing auto-ran it, so reusable rules were caught only by a manual
  sweep (the review-gate auto-capture stores verdict-state notes only). The post-commit hook
  now runs `knowledge-capture harvest --write` after its GIT_* unset (worktree-safe), guarded
  by `command -v` (no-op where the global helper is absent), never blocking, and a no-op on
  untrailered commits (dedup makes the re-scanned `@{u}..HEAD` range idempotent). The WORKFLOW
  dev-loop adds the trailer convention (write the reusable rule + evidence + scope; relativize
  paths -- absolute private paths are still not stored). verify-machinery asserts the installed
  hook wires the harvest and that a trailered commit is captured while an untrailered one is not.

## 2026.06.18.8

- Odoo domain pack: new static manifest-integrity screen
  (`validation-harness/check-manifest-files.py`, wired into `hooks/pre-push`). It
  fails closed when a changed module's `__manifest__.py` lists a `data`/`demo` file
  that does not exist -- a deterministic post-push `odoo -u` / odoo.sh build failure
  (`FileNotFoundError`) that the warm-base validation only catches when docker + the
  harness are configured. The screen needs no docker and is co-installed next to the
  pre-push hook (`.githooks/`, by the installer), so it runs before the harness/docker
  skips and catches the missing-file class even when `ODOO_HARNESS_DIR` is unset --
  closing the post-push manifest/missing-file gap named in the 7-day audit. Only
  `data`/`demo` (exact
  module-relative paths) are checked; `assets` entries (addons-root-relative,
  possibly globs) stay the warm-base/web build's oracle. `verify-patterns.md`
  documents it and verify-machinery covers the block / pass / report cases.

## 2026.06.18.7

- machinery-scope verify on automation-script changes (`review-gate.sh` +
  `hooks/pre-commit`, + template mirrors): the product-scope gate verify and the
  pre-commit pytest run never exercised the `verify-machinery.sh` harness, so a
  regression in the automation scripts (the P3 reviewer-text-drift class) slipped
  past BOTH the gate and the commit hook. When a change touches the automation
  machinery surface -- `scripts/**`, `templates/automation-base/scripts/**`, or
  `templates/automation-base/hooks/**` (the hooks are machinery the harness
  dedicatedly tests) -- AND the harness is present (the AI_AUTO source repo only --
  it is not installed into derived projects, so the guard makes this a no-op there),
  the gate now runs the harness after a green product verify
  and folds its status into the verify result (a machinery failure takes the same
  recorded-`blocked` / override path as any other red verify), and the pre-commit
  hook runs the harness in place of the plain pytest run (the harness runs pytest
  as its first step, so it supersedes rather than doubles it). verify-machinery
  asserts both the positive (scripts change -> harness runs) and negative
  (docs-only -> harness skipped despite presence) cases for the gate and the hook.

## 2026.06.18.6

- worktree-safe pre-commit hook exit-5 fix (`hooks/pre-commit`): `pytest` exit 5
  ("no tests were collected") is no longer treated as a commit-blocking failure.
  A freshly installed template or a test-less repo collects no tests, and the
  hook's `set -e` previously turned that exit 5 into a fail-closed block,
  preventing the first commit in such a project (surfaced when the installer
  self-test commits the freshly installed tree through the hook). The hook now
  runs the suite via a helper that treats exit 5 as non-blocking while keeping a
  real failing run (exit 1-4) fail-closed and the no-runner case warn+defer.
  `verify-machinery.sh` (+ template mirror) adds an exit-5 non-blocking assertion
  alongside the existing fail-closed and no-runner assertions.

## 2026.06.18.5

- DOC_BUDGET template-patch reason quality (`doc-budget.sh`): the
  `DOC_BUDGET_TEMPLATE_PATCH=1` budget escape hatch now requires a SUBSTANTIVE
  `DOC_BUDGET_TEMPLATE_PATCH_REASON` (>= 12 non-space chars), rejecting trivial or
  recycled placeholder reasons in addition to the existing empty-reason check.
  Addresses the 7-day-audit finding that the bypass sometimes carried recycled
  boilerplate. verify-machinery asserts a too-short reason fails closed.

## 2026.06.18.4

- red-signal handling at the review gate (`review-gate.sh` + `summarize-ai-reviews.sh`):
  a failed `verify.sh` no longer aborts the gate opaquely (the opaque `set -e`
  crash gave no recorded verdict and pushed operators to `--no-verify`). The gate
  now captures the real verify exit status (`PIPESTATUS`) and, on failure, records
  an explicit `decision: blocked` / `reason: verify_failed` verdict without running
  the AI panel. To proceed past a known-unrelated failure the gate requires BOTH
  `AI_AUTO_VERIFY_OVERRIDE_REASON` and `AI_AUTO_VERIFY_OVERRIDE_APPROVED_BY`; that
  path warns loudly, still runs the panel, and `summarize-ai-reviews.sh` forces the
  result to `proceed_degraded` with degraded trust plus a recorded `verify_override:`
  field in the verdict — never a clean proceed. Closes the silent red->proceed /
  `--no-verify` gap (7-day-audit finding); block-vs-recorded-override resolved by
  AI council. verify-machinery and test-review-summary cover both paths.

## 2026.06.18.3

- transient reviewer-disable auto-recovery (`run-ai-reviews.sh`): when an external
  reviewer (Claude/Gemini) is disabled for a transient reason (`usage_limit`,
  `network_or_sandbox`, or connection/timeout/rate-limit details) it is recorded
  `disable_class=transient` and auto-expires after
  `REVIEW_REVIEWER_DISABLE_COOLDOWN_SECONDS` (default 1800) on a later run, instead
  of staying disabled until a manual `RESET_DISABLED_AI_REVIEWERS`. Persistent or
  unclassified disables still require a manual reset. Stops a usage-limit/network
  blip from leaving Codex self-substitution as the de-facto reviewer (7-day-audit
  finding). `AI_REVIEWS_EXPIRE_ONLY=1` runs the expiry sweep then exits;
  verify-machinery asserts transient-old expires while persistent and still-fresh
  disables are retained.

## 2026.06.18.2

- worktree-safe git hooks (new `templates/automation-base/hooks/pre-commit` +
  `post-commit`, installed by `install-automation-template.sh` into the target's
  real hooks dir; a pre-existing non-AI_AUTO hook is left untouched with a loud
  warning — fail-closed, never clobbered). The pre-commit hook `unset`s `GIT_DIR`/`GIT_INDEX_FILE`/
  `GIT_WORK_TREE`/`GIT_PREFIX`/`GIT_COMMON_DIR`/`GIT_NAMESPACE` before running the
  test suite, so test git subprocesses no longer inherit this repo's GIT_* and
  corrupt the shared common git dir/index across linked worktrees -- the
  corruption that pushed sessions to `git commit --no-verify` and left the full
  suite ungated. When a pytest runner is present the pre-commit hook now runs the
  suite worktree-safely as an early pre-filter (fail-closed on any test failure);
  when no runner exists at all it warns and defers to `review-gate.sh`, which
  remains the authoritative gate of record. The post-commit
  hook (which still runs under `--no-verify`) warns loudly when no review-gate
  `proceed`/`proceed_degraded` verdict exists in the last 30 min, making
  gate-bypassing commits non-silent (it cannot block; git-design limit). Closes
  the `--no-verify`/ungated-commit gap from the 7-day audit. verify-machinery
  asserts the installed pre-commit is worktree-safe.

## 2026.06.18.1

- review-gate substitute-trust honesty fix (`summarize-ai-reviews.sh`): coverage
  that relies on the active principal's own subagent substitute for a
  decision-relevant lane (`principal_subagent_substitute`,
  `principal_rotation_with_substitute`) is no longer reported as `proceed` with
  `normal` trust. It is now downgraded to `proceed_degraded` with `degraded`
  trust, because a principal reviewing via its own subagent is not independent
  external review. The `Principal/Codex Review Coverage` field renames
  `principal_subagent_substitute_regular` -> `principal_subagent_substitute_degraded`.
  Normal trust now requires `multi_reviewer` or `principal_rotation` coverage
  (no self-substituted lane). `test-review-summary.sh` updated to assert the
  degraded outcome, and its `proceed` invariant guard no longer admits substitute
  coverages. Closes the substitute-trust overstatement flagged by the 7-day audit
  and by the Codex 2026-06-17 review-gate self-audit (rec #3). Docs:
  `MULTI_AI_COLLABORATION.md`, `README.md`.
## 2026.06.15.2

- Odoo domain pack: new **client action-shape screen** for the Odoo-19
  raw-`doAction(dict)` crash class (a `target:'new'` `act_window` returned to the
  web client without `views` → `_preprocessAction` runs `undefined.map`).
  `validation-harness/check-action-shape.py` is a diff-scoped, advisory AST screen
  (flags only changed `target:'new'` act_window dicts missing `views`; the same
  shape is safe via button/server dispatch, so it over-approximates by design).
  `validation-harness/popup-smoke.mjs` is the runtime oracle: it opens a flagged
  popup on the local `serve.sh` build and fails on any console error / uncaught
  promise. The `hooks/pre-push` gate runs the screen (advisory, no docker needed);
  `AGENTS.patch.md` + `verify-patterns.md` make confirming each flagged popup via
  the local smoke a required step (no static-read or AI self-certify pass).
- `scripts/check-template-version.sh` (+ AGENTS.md commit-prep step 4) now also
  gate `templates/domain-packs/` changes on a version bump + patch note, closing
  the gap where shipped domain-pack changes were not version-governed.

## 2026.06.15.1

- `scripts/doc-budget.sh` (+ template mirror): in a project installed from the
  template, guidance docs byte-identical to the install-time baseline
  (`.ai-auto/guidance-baseline.sha256`) are now excluded from the absolute size
  budget, so a derived project's budget measures only what it authored or
  changed. The branch-cumulative diff lane is unchanged; the excluded count is
  surfaced, not silently dropped. The AI_AUTO source repo has no baseline file
  and keeps budgeting all guidance.
- New `scripts/refresh-guidance-baseline.sh`: (re)generates that baseline from
  the current template by recording guidance docs that match it. The installer
  now calls it instead of an inline hash list, and `ai-auto-template-status`'s
  update-available resolution tells the operator to run it after adopting a
  newer template (so newly adopted but unchanged docs count as inherited again).
- `docs/AUTOMATION_OPERATING_POLICY.md` + template `README.md`: document the
  inherited-baseline exclusion and the refresh step.
- `verify-machinery.sh`: added inherited-baseline exclusion tests and installer
  assertions (baseline written, tracked, fresh-install primary total 0).
- `docs/NEW_PROJECT_GUIDE.md` / `docs/GLOBAL_TOOLS.md`: updated the stale
  `Project_JW/99. 개발개발` grouping example to the current Z-drive `99. odoo`.

## 2026.06.12.5

- `AGENTS.md` (+ template mirror): added a `## Delegation Recording Protocol`
  rule. When the leader delegates a unit of code work onto a model-class lane
  (`fast_scan`/`low_cost_impl`/`standard_impl`/`frontier_review`), recording the
  decision via `scripts/record-lane-decision.py` into
  `.omx/model-routing/lane-decisions.tsv` is a required, observability-only step
  (no completion authority). Backed by a `delegation_recording_policy` contract
  in `scripts/self_demo_contracts.py` with tests in
  `tests/test_self_demo_contracts.py`. `docs/AI_MODEL_ROUTING.md` (+ mirror) drops
  the "no caller / no accumulated evidence" framing in § Evidence-driven tuning,
  and `scripts/verify-machinery.sh` locks the rule marker in both AGENTS copies
  plus AI_MODEL_ROUTING parity. Normalizes ST-P1-22 Phase 1 recording.

## 2026.06.12.4

- `docs/WORKFLOW.md` (+ template mirror) dev-loop step 13: added an intra-session
  reflexion / anti-thrash rule. When the same verification/failure recurs ≥2 times in
  one task, instead of blindly retrying, append 3 lines (tried / why it failed / next
  hypothesis or avoid-rule) to the active `plans/*.md` `## Tried & Failed` section and
  re-read before the next attempt. This is the intra-session complement to the existing
  post-hoc cross-session `feedback_pattern` capture; it targets thrashing (retrying minor
  variations of an already-failed fix). Guidance-only, reuses `plans/*.md` (no new file or
  tooling); enforcement (observe failure signatures → advisory → soft-block) is a tracked
  later-gated backlog item, not shipped here. Absorbed from a loops.elorm.xyz review +
  unanimous AI council (codex + gemini).

## 2026.06.12.3

- `OBSIDIAN_INTEGRATION.md`: documented the two-lane index boundary for the KB.
  Automated retrieval (`knowledge-retrieve` / the domain-gated hook) covers the
  **reference-baseline lane** (`Odoo19_Docs_KB` slim routing index) ONLY; the
  **curated-findings lane** (`AI_AUTO_INDEX.md` + `Projects/`/`Surfaces/`/
  `RepeatKeys/`) is browse-only and is NOT auto-retrieved, so a captured
  `surface: odoo` finding is not surfaced by the hook even after push. Also
  clarified that the findings index is fully rebuilt (idempotent) from
  frontmatter on every push, so routing a new draft to a different `project:`
  never requires reindexing existing notes. Doc-only clarification of existing
  behavior; extending retrieval to the findings lane is tracked as a later-gated
  backlog item, not shipped here. The same coverage-boundary note was added to the home-only
  `docs/GLOBAL_TOOLS.md` (`knowledge-retrieve` entry); that file is not template-owned, so it is not
  mirrored under `templates/` and needs no template-status sync.

## 2026.06.12.2

- KB bidirectional retrieval, Stage 2 + 1B (the READ path). `automation-doctor.sh` now checks the
  `knowledge-retrieve` and `ai-kb-retrieval-hook` global-helper links. New helper
  `tools/knowledge-retrieve` is the PULL worker (symmetric to `knowledge-collect`): given keywords
  it searches a registered domain KB's slim index (Odoo first, matched against topic names AND slim
  headings) and prints a CAPPED routing block of slim pointers — never raw content, tagged advisory,
  fail-graceful on any miss. New `tools/ai-kb-retrieval-hook` is a Claude Code `UserPromptSubmit`
  hook that injects that block ONLY when both gates pass (project profile is a registered domain AND
  the prompt matches the domain keyword classifier); it is fail-open (never blocks a prompt) and
  opt-in via `install-global-files.sh --install-kb-retrieval-hook`, which idempotently registers it
  in `~/.claude/settings.json` (backed up, merge-safe). Behavior contract tests lock retrieval
  matching, the gates, and fail-open/graceful posture.

## 2026.06.12.1

- KB bidirectional retrieval, Stage 1A + 1A.2 (the WRITE path). `automation-doctor.sh` now
  checks the `knowledge-capture` global-helper link. New helper `tools/knowledge-capture`
  harvests reusable findings the author already distilled — commits carrying Lore-style
  `Finding:`/`Finding-Evidence:`/`Finding-Scope:` trailers (+ optional `Finding-NotWhen:` /
  `Finding-Surface:` / `Finding-Share:`, each a single line) → sanitized local
  `.omx/knowledge/drafts/` (the schema `knowledge-collect` reads). A **reuse-test gate** drops
  any finding missing rule/evidence/scope (junk-vault defence); all harvested text is
  secret/path-redacted; drafts are `local_private` unless `Finding-Share: shareable`. Capture is
  local + opt-in; the vault push stays user-triggered. `obsidian-autopush.sh` gains a vault
  preflight: fails loud on a non-writable vault and warns when a more-recently-modified
  AI_AUTO_Vault exists on a sibling drive (the /mnt/c-vs-/mnt/z config-drift class).

## 2026.06.12.0

- KB bidirectional retrieval, Stage 0 (foundation). `automation-doctor.sh` now checks the
  `ai-project-profile` global-helper link. New helper `tools/ai-project-profile` detects a
  repo's domain (Odoo = `custom-addons/` with module `__manifest__.py`) and records it in
  machine-local `.omx/project-profile.json`; `aiinit` writes it for detected Odoo projects
  (no-op otherwise). The odoo domain pack gains a "consult the slim KB first; KB is advisory —
  repo evidence wins" retrieval rule (WORKFLOW.md dev-loop step 0 + AGENTS.patch.md). Advisory
  metadata + guidance only — no runtime behaviour change; the domain-gated retrieval hook
  (later stage) reads the profile.

## 2026.06.11.3

- The odoo domain pack now ships a `hooks/pre-push` validation gate, and `aiinit`
  (`install-automation-template.sh`) auto-installs it into Odoo projects (those with a
  `custom-addons/` directory): the hook is copied to `.githooks/pre-push`
  non-destructively and `core.hooksPath` is set to `.githooks` only when unset. The hook
  is fail-closed (a missing warm base is auto-built, never silently skipped) but stays
  inert with a loud "NOT VALIDATED" notice until `ODOO_HARNESS_DIR` is configured, so it
  never blocks a project that has not set up the local harness. Non-Odoo projects are
  unaffected.

## 2026.06.11.2

- `automation-doctor.sh` now checks the `ai-tmux-worktree` global-helper link
  alongside `ai-worktree`. New helper `tools/ai-tmux-worktree` (root-only) drives a
  tmux-integrated worktree lifecycle: with `install-global-files.sh
  --install-tmux-worktree` + `AI_AUTO_TMUX_WORKTREE=1`, each tmux window in an
  AI_AUTO project gets its own worktree (auto-created on open, removed on close only
  when there is no uncommitted or unpushed work).

## 2026.06.11.1

- Multi-terminal concurrency safety (one project, several terminals):
  - New global helper `ai-worktree` (+ `aiwt` shell function): create-or-enter a
    per-terminal git worktree (`aiwt <name>`), so each terminal has its own working
    tree AND its own `.omx/` — the robust fix for writer races and review-gate
    flakiness under concurrent sessions (operationalizes WORKFLOW.md "Writer 격리").
  - New `scripts/session-lock.sh` (sourced by `review-gate.sh` and `verify.sh`): a
    per-working-tree lock at `.omx/state/session.lock` (gitignored, tree-local). A
    second live session on the SAME tree is warned and soft-blocked, pointing at
    `aiwt`; override with `AI_AUTO_ALLOW_SHARED_TREE=1`. Re-entrant for the
    review-gate→verify nesting (shared `AI_AUTO_SESSION_ID`), stale locks are
    reclaimed by liveness check, and two SEPARATE worktrees never false-block.
  - Deferred: `.omx` per-session sub-scoping (only needed for those who insist on
    sharing one tree; the worktree-per-terminal model isolates `.omx` by construction).

## 2026.06.11.0

- Review-gate efficiency: cut redundant AI-panel churn (measured R0 baseline of
  531 verdicts / 33 days, 61% re-running <15min on an unchanged diff) without
  weakening the decisive gate.
  - `REVIEW_TARGETED_RECHECK` now defaults to `1`: after a finding, the revision
    task is scoped to the accepted finding instead of a fresh full gate. Fails
    closed to manual review when the changed files exceed that scope
    (`REVIEW_TARGETED_RECHECK_SCOPE_OK=0`).
  - Review provenance: `summarize-ai-reviews.sh` records a working-tree-inclusive
    hash of an approved change in `.omx/reviewer-state/` ONLY on proceed +
    normal trust. `review-gate.sh` skips the external AI panel (carrying the prior
    verdict) when the working tree is byte-identical, and fails open to a full
    review on any change, flag mismatch (`REVIEW_INCLUDE_UNTRACKED_CONTENT` /
    allowlist), or disabled reviewer. `verify.sh` always runs; the skip is
    AI-panel-only.
  - `REVIEW_INTEGRATION_ONLY=1` runs a mandatory light, cross-task-interaction
    review when combining already-approved task diffs (suppresses the exact-match
    skip; reviewer panel and trust logic unchanged).
  - `REVIEW_DECISION_GATE=1` (PR / pre-merge) forces the full unanimous panel:
    provenance skip, targeted recheck, and integration-only are all disabled and
    context is forced to full.
  - `docs/WORKFLOW.md` documents the iterate-light / decide-full cadence.
  - Deferred (documented): delta-scoped review against the last approval (needs a
    diff base in `collect-review-context.sh`); every non-exact case fails open to
    a full review until then.

## 2026.06.10.1

- Tightened Obsidian external-SSD guidance: the current local vault lives under
  `/mnt/z/JSJEON/Obsidian/AI_AUTO_Vault`, while legacy
  `/mnt/c/JSJEON/Obsidian/AI_AUTO_Vault` and
  `C:\JSJEON\Obsidian\AI_AUTO_Vault` paths are stale migration sources only and
  must not be used for new Obsidian writes.
- Clarified Obsidian labeling/index lanes so `AI_AUTO_INDEX.md` is not mistaken
  for a vault-wide table of contents, and required Inbox/Projects conflict
  review before real vault migration.
- Added a read-only Obsidian vault audit helper so cleanup can start from
  duplicate/conflict evidence instead of graph-view impressions.

## 2026.06.10.0

- Extended the Odoo official-docs baseline contract so user manuals can be
  mirrored as `user-manual/raw` plus `user-manual/slim` when user-facing
  workflows are part of normal work. The local Odoo 19 baseline now expects the
  index to route to mirrored raw/slim manual pages instead of index-only
  on-demand fetches.
- Strengthened Obsidian guidance for Odoo work: when `AI_AUTO_ODOO_DOCS_KB_PATH`
  or an explicit vault path is available, consult the local baseline before
  implementation-ready framework or user-flow guidance, while preserving that
  Obsidian is not authoritative for project schema, verification, review,
  queue resolution, completion, or upstream freshness.
- Migration note: existing Odoo docs vaults that still have only
  `01_UserManual_Index.md` must be recollected with
  `scripts/collect-odoo-docs-kb.py <vault>/AI_AUTO/Odoo19_Docs_KB` before
  enabling the `2026.06.10.0` validator through `AI_AUTO_ODOO_DOCS_KB_PATH`;
  otherwise verification will correctly fail on missing `user-manual/raw` and
  `user-manual/slim` coverage.

## 2026.06.09.0

- `scripts/ai-runtime-adapter.sh` no longer passes `--sandbox` to the raw
  `gemini` CLI when no *usable* container runtime (Docker/podman daemon actually
  reachable via a timeout-bounded `info` probe) or macOS Seatbelt is available,
  so external/WSL/desktop review runs no longer die on a missing Gemini sandbox
  image — including the common case where the docker CLI is installed but the
  daemon is down. Case-insensitive `GEMINI_SANDBOX=0|1` forces it off/on; `agy`
  and other wrappers keep `--sandbox`. `verify-machinery.sh` self-tests lock the
  explicit-override and installed-but-unusable-daemon paths.
- Documented in `docs/WORKFLOW.md` the external/Claude-unavailable review path:
  `RUN_CLAUDE_REVIEW=0` to skip Claude, `REVIEW_EXECUTION_MODE=external` runner,
  the raw-`gemini` degraded-last-resort caveat (not class-fixed; `agy` stays the
  default), and the Gemini Docker-sandbox/WSL no-sandbox handling.

## 2026.06.05.11

- Added `DOC_BUDGET_COMPLETION_BASE_REF` to `scripts/doc-budget.sh` so
  long-lived branch guidance bloat can remain visible as a warning while task
  completion is judged against the current work/run baseline.
- Documented the completion-scoped guidance budget workflow in the automation
  operating policy.

## 2026.06.05.10

- Changed the generated AI tmux wrapper so an interactive runtime call no
  longer attaches to an already-open session for the same runtime and project.
  It now tries the base session name first, then starts the next numbered
  session (`-2`, `-3`, ...) when that name is already in use, preserving
  parallel Codex/Claude/agy terminals without closing existing sessions.
- Updated wrapper verification to simulate a tmux session-name collision and
  assert that the generated wrapper retries with the numbered session name.

## 2026.06.05.9

- Added the official documentation baseline pattern to Obsidian guidance:
  project-authored guide first, official slim topic as navigation-only lookup,
  one raw topic only for exact semantics, source URL fallback for freshness, and
  index-only storage for end-user manuals. The local Odoo 19 reference baseline
  is documented as vault-owned (`odoo-19-docs-2026-06`) with validator guidance
  that does not make Obsidian authoritative.
- Added `scripts/validate-odoo-docs-kb.py` as a template-managed optional
  validator for projects that maintain an Odoo official-docs raw/slim baseline.
  `verify.sh` can run this optional check via `AI_AUTO_ODOO_DOCS_KB_PATH`; no
  user-specific vault path is embedded in the template.

## 2026.06.05.8

- Promoted `docs/PLANNING_VISUALIZATION_GUIDE.md` into the automation template
  so downstream projects receive the planning visualization gate guidance,
  framework-native wireframe structure rules, vector wireframe fidelity
  boundary, and standard-flow preservation kernel through normal template
  patch flow.
- Isolated the doc-budget template-patch fixture from inherited
  `DOC_BUDGET_TEMPLATE_PATCH_REASON` so `verify-machinery.sh` can validate the
  no-reason failure path even when the outer verify run uses template patch
  mode.

## 2026.06.05.7

- Split the AI_AUTO self-test/tooling suite into `scripts/verify-machinery.sh`.
  `verify.sh` keeps full coverage by default and now supports
  `AI_AUTO_VERIFY_SCOPE=product|machinery|full`.
- `review-gate.sh` now runs the product verify scope before external review, so
  the gate no longer replays the full machinery suite after standalone verify.

## 2026.06.05.6

- `collect-review-context.sh` now derives `REVIEW_UNTRACKED_ALLOWLIST` from the
  tracked diff when no explicit allowlist is set. Untracked-only states still
  keep every material untracked artifact in scope.
- `review-gate.sh` clears untracked allowlist overrides before running its
  internal verification so review-target scoping cannot leak into verify
  fixtures.

## 2026.06.05.5

- Added a one-writer-per-working-tree convention to the template instructions
  and workflow guide.
- Review context now includes a report-only Tree Churn Audit that warns when git
  status changes while context is being collected, including new untracked files.

## 2026.06.05.4

- `review-gate.sh` now consumes the diff-scope policy before launching external
  reviewers. Diffs whose scope is only `docs`/`plans` and whose guards are clear
  record `review skipped: docs-only` after verification instead of running
  Claude/Gemini.
- Code, script, template, guidance, unknown, or guarded diffs still fall through
  to the full external review path.

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
