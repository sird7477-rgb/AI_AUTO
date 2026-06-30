# Global-tool-ization — SPEC v2 (feat/global-toolize)

GOAL (unchanged): AI_AUTO is a globally-installed tool operating ON project dirs. A project repo
carries ZERO vendored framework files. No version pin. Mandate: shortest code wins; delete > add.

This v2 supersedes SPEC.md. It encodes the orchestrator-locked decisions R1–R9 and closes every
red-team defect (see DEFECT-MATRIX.md). Counts verified against the tree (see IMPL-PLAN.md).

## 1. Boundary (what lives where)
- GLOBAL (in `$AI_AUTO_HOME`, engine-owned): all `scripts/*` (incl. `verify.sh`), all `docs/*`,
  the base `AGENTS.md` guidance, `hooks/`, `templates/domain-packs/`, `tools/*`.
- PROJECT-OWNED (committed, legitimate, NOT churn):
  - `scripts/verify-project.sh` — OPTIONAL project verification hook (the project's "what
    verification means here"). Replaces the old project-owned `verify.sh`.
  - `AGENTS.md` — a THIN project overlay (engine reads this path at runtime; see §6).
- RUNTIME (project, gitignored): `.omx/`.
- DELETED outright (copy-model + drift/version apparatus + their tests): see §2.

## 2. DELETE set (the bulk of the win — copy model entirely)
Engine duplicate + installer:
- `templates/automation-base/` (whole tree: 29 scripts, 22 docs, AGENTS.md, README.md,
  AI_AUTO_TEMPLATE_VERSION, hooks/).
- `scripts/install-automation-template.sh`.
Version/drift/staleness apparatus:
- `scripts/check-template-version.sh`, `scripts/refresh-guidance-baseline.sh`.
- `tools/ai-auto-template-status`, `tools/ai-template-refresh`.
- `AI_AUTO_TEMPLATE_VERSION` (concept + the template `docs/PATCH_NOTES.md`).
- `check_template_staleness()` gate in `scripts/review-gate.sh:339-392` (+ its verdict writer + the
  6 call refs).
- `.github/workflows/template-version-gate.yml`.
- `.ai-auto/` per-project state: `guidance-baseline.sha256`, `template-manifest.json` consumers.
Their tests (SAME change — resolves D1):
- `scripts/verify-machinery.sh` blocks for `check-template-version` (~1074-1140), `template_staleness`
  (~4363-4436), `ai-auto-template-status` drift/ownership/promotion (~897, ~4070, ~6068-7666),
  guidance-baseline (~1026-1041) — 78 grep hits total, zeroed atomically.
- `tests/test_template_global_contracts.py` — DELETE (it asserts on the retired surfaces); replace
  with a tiny zero-framework-file contract test (see IMPL-PLAN).

## 3. KEEP set
- `templates/domain-packs/` (real global packs: odoo, browser-macro) — the extensibility model.
- Every engine `scripts/*` (now incl. `verify.sh` as global framework), `docs/*`, `tools/*` except
  the two deleted tools.
- The existing worktree-safe `GIT_*`-unset hook bodies (relocated to global `hooks/`, §5).

## 4. Sibling resolution = PATH-based (R2)
- `install-global-files.sh` exports `AI_AUTO_HOME` into the shell profile AND prepends
  `$AI_AUTO_HOME/scripts` (+ each `templates/domain-packs/*/bin` if present) to `PATH`.
- Framework scripts call siblings by BARE name: mechanical `s|\./scripts/||` so `./scripts/X.sh`
  → `X.sh`, resolved via PATH regardless of `cwd`. This is one PATH line, not per-file `SCRIPT_DIR`
  boilerplate. It also makes verify-machinery's fixtures (which `cd "$tmp"`) resolve the engine via
  PATH — no per-fixture repoint needed for KEPT tests.
- Project context stays `$(pwd)` for `.omx/`, git (`git rev-parse --show-toplevel`), artifacts,
  and the project's `AGENTS.md`. NO `$AI_AUTO_PROJECT` (dropped — unused; YAGNI). NO `cd` by the
  launcher.

## 5. verify seam (R3) — resolves D2
- `verify.sh` is GLOBAL framework. It: sources siblings by bare name on PATH
  (`docker-config-guard.sh`, `session-lock.sh`), runs `verify-machinery.sh` (bare), then runs the
  project hook `scripts/verify-project.sh` IF present (project-owned, committed).
- A real project's old `verify.sh` product logic migrates into `scripts/verify-project.sh`. In THIS
  repo (self-host), ai-lab's `run_product_*` logic moves to `scripts/verify-project.sh`; framework
  `verify.sh` stays global and calls it.

## 6. AGENTS.md (R6) — resolves D6
- Engine reads PROJECT `AGENTS.md` at runtime: `collect-review-context.sh:187` (reviewer context),
  `:209/:292/:439` (scope/persona), `doc-budget.sh:167`, `guidance-duplicate-report.sh` (via
  verify-machinery). None read `~/.claude/CLAUDE.md`.
- KEEP a thin PROJECT `AGENTS.md` overlay so the read target exists (no crash, no fail-soft skip).
  Base guidance lives global (Claude Code layers global+project for the Claude runtime).
- RESIDUAL (flagged): the engine's file-read sees only the overlay, not the global base. Full
  closure = optional engine edit to also read `$AI_AUTO_HOME/AGENTS.md` in collect-review-context /
  doc-budget. Out of the locked design scope; recommended follow-up. See DEFECT-MATRIX D6.

## 7. doc-budget (R7) — resolves D8
- Inherited-baseline was built for the template-patch/copy case only. Sole consumer is
  `doc-budget.sh:20` (`.ai-auto/guidance-baseline.sha256`), written only by the deleted
  `refresh-guidance-baseline.sh`. RETIRE it: remove the `GUIDANCE_BASELINE` branch and all
  `templates/automation-base/*` budget branches. doc-budget then measures only the project's own
  guidance (the thin AGENTS.md overlay + project docs). Caps are upper bounds, so a thin overlay
  passes. Update its verify-machinery tests in lockstep (folded into §2).

## 8. ai-auto setup (R4) — resolves D3, folds init+migrate, ONE idempotent command
`ai-auto setup` (run in a project, `pwd`=project):
1. For each managed framework file currently tracked in the project, compare bytes to the global
   pristine in `$AI_AUTO_HOME`:
   - byte-match → `git rm` (safe: it's an unmodified vendored copy).
   - differs → LEAVE untouched + REPORT (never delete customized work).
2. `AGENTS.md`: pristine (==global base) → remove the full base, seed a thin project overlay stub
   so the engine read target persists (§6); customized → keep as-is (it IS the overlay).
3. Ensure `.omx/` is gitignored.
4. Detect domain via existing `ai-project-profile`.
5. Resolve the hooks dir and install thin framework shims (§9).
Idempotent: re-running on an already-clean project is a no-op (keys off git state + hash compare;
NO `.ai-auto` marker file). Fail-closed: refuse on a dirty tree that risks loss.

## 9. Hooks (R5) — resolves D7
- Do NOT hijack `core.hooksPath`. Resolve the project's ACTUAL hooks dir once
  (`git rev-parse --git-path hooks`, worktree-safe / shared common-dir aware) and install thin
  shims there (uncommitted, as today) that `exec` the global engine dispatcher.
- Framework OWNS `pre-commit` + `post-commit`. The odoo pack OWNS `pre-push`
  (`templates/domain-packs/odoo/hooks/pre-push`). Different filenames → they coexist in one resolved
  hooks dir under a single `core.hooksPath` value. No collision, no clobber.
- Shims keep the existing `unset GIT_* ; repo_root=$(git rev-parse --show-toplevel)` worktree-safety,
  then `exec "$AI_AUTO_HOME/hooks/<hook>"`.

## 10. Extensibility = dir-discovery / run-parts (R8) — addresses non-extensibility finding
- Global `hooks/pre-commit` and `hooks/post-commit` are DISPATCHERS that run-parts over
  `$AI_AUTO_HOME/hooks/<hook>.d/*` (sorted, executable). The framework's own commit-test body is
  `hooks/pre-commit.d/00-framework`. A QC/design/odoo pack registers a hook by DROPPING one file
  into `<hook>.d/` — ZERO core edit.
- Launcher dispatch: `ai-auto <verb>` resolves a built-in (setup|gate|verify|doctor) else dispatches
  to `$AI_AUTO_HOME/packs/<verb>` or PATH. A pack adds a verb by shipping an executable — no
  subcommand-table edit. Mirrors the existing directory-discovered `ai-domain-pack` model.

## 11. Launcher `tools/ai-auto` (thin, UX only)
- `ai-auto setup|gate|verify|doctor|<pack-verb>`. Self-resolves `$AI_AUTO_HOME` from `readlink -f`,
  ensures PATH, runs the engine with `pwd`=project. Load-bearing resolution is PATH (§4); the
  launcher is convenience. `gate`==`review-gate.sh`, `verify`==`verify.sh`, `doctor`==
  `automation-doctor.sh --project`.

## 12. doctor (R9) — resolves D4/D5
- `automation-doctor.sh` gets two modes:
  - `--project` (default in a project): checks ONLY `scripts/verify-project.sh` (optional, warn if
    absent), the installed hook shims, and `.omx/` gitignored. A zero-framework-file project PASSES.
  - `--home` (in `$AI_AUTO_HOME`): the engine inventory (REQUIRED_FILES = `scripts/*`, `docs/*`,
    `tools/*`) — minus the two deleted tools, and the `:67` source-repo gate drops its
    `ai-auto-template-status` condition.
- The old monolithic `REQUIRED_FILES` (AGENTS.md + ~30 managed files) is replaced; it no longer
  flags a globalized project as broken.

## 13. DONE criteria
design certified ∧ implementation certified ∧ defense game converged (2 dry red rounds) ∧ all engine
self-tests + new global-mode tests green ∧ clean end-to-end `ai-auto setup` of a throwaway project
proven (setup → gate runs from global → no framework files committed → doctor --project green).
