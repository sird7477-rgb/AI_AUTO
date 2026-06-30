# Global-tool-ization — SPEC v3 (feat/global-toolize)

GOAL (unchanged): AI_AUTO is a globally-installed tool operating ON project dirs. A project repo
carries ZERO vendored framework files. No version pin. Mandate: shortest code wins; delete > add.

v3 supersedes v2. It applies the orchestrator-LOCKED corrections C1–C7 (which fix red-team
F1–F10) on top of v2's already-passed mechanisms (D1 ordering, D3 content-compare safe-side, D7
hook coexistence — re-affirmed UNCHANGED). All counts/anchors re-verified against the live tree
(branch feat/global-toolize, HEAD 6e90184). See DEFECT-MATRIX.md and IMPL-PLAN.md.

## 1. Boundary (what lives where)
- GLOBAL (in `$AI_AUTO_HOME`, engine-owned): all `scripts/*` (incl. `verify.sh`), all `docs/*`,
  the base `AGENTS.md`, top-level `hooks/{pre-commit,post-commit}`, `templates/domain-packs/`,
  `tools/*` (minus the two deleted tools).
- PROJECT-OWNED (committed, legitimate, NOT churn):
  - `scripts/verify-project.sh` — OPTIONAL project verification hook. Replaces the old
    project-owned `verify.sh` product logic.
  - `AGENTS.md` — a THIN project overlay (engine reads this path at runtime; see §6).
- RUNTIME (project, gitignored): `.omx/`.
- DELETED outright: see §2.

## 2. DELETE set (the bulk of the win — copy model entirely) — UNCHANGED from v2
Engine duplicate + installer:
- `templates/automation-base/` (whole tree: 29 scripts, 22 docs, AGENTS.md, README.md,
  AI_AUTO_TEMPLATE_VERSION, hooks/).
- `scripts/install-automation-template.sh`.
Version/drift/staleness apparatus:
- `scripts/check-template-version.sh`, `scripts/refresh-guidance-baseline.sh`.
- `tools/ai-auto-template-status`, `tools/ai-template-refresh`.
- `AI_AUTO_TEMPLATE_VERSION` (concept + the template `docs/PATCH_NOTES.md`).
- `check_template_staleness()` gate in `review-gate.sh` (§3) + verdict writer + call refs.
- `.github/workflows/template-version-gate.yml`.
- `.ai-auto/` per-project state: `guidance-baseline.sha256`, `template-manifest.json` consumers.
Their tests (SAME change — resolves D1): the `verify-machinery.sh` blocks + the unit test
`tests/test_template_global_contracts.py`; replaced by a tiny zero-framework-file contract test.

## 3. KEEP set — UNCHANGED from v2
- `templates/domain-packs/` (odoo, browser-macro) — the extensibility model.
- Every engine `scripts/*` (incl. `verify.sh`), `docs/*`, `tools/*` (minus two deleted).
- The worktree-safe `GIT_*`-unset commit-test bodies (relocated to global `hooks/`, §9).

## 4. Sibling resolution = PATH + self-heal guard (R2; C5/C7 harden F5/F8)
- `install-global-files.sh` exports `AI_AUTO_HOME` into the shell profile AND prepends
  `$AI_AUTO_HOME/scripts` (+ each `templates/domain-packs/*/bin` if present) to `PATH`.
- Framework scripts call siblings by BARE name: mechanical `s|\./scripts/||`. One PATH line, no
  per-file `SCRIPT_DIR` boilerplate.
- **C7 self-heal (closes F5/F8): every engine ENTRYPOINT** (`verify.sh`, `review-gate.sh`, the
  global `hooks/pre-commit`, `hooks/post-commit`, the `ai-auto` launcher) begins with ONE guard
  line so resolution never depends solely on a profile a given process may not have sourced:

      : "${AI_AUTO_HOME:=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)}"
      case ":$PATH:" in *":$AI_AUTO_HOME/scripts:"*) ;; *) PATH="$AI_AUTO_HOME/scripts:$AI_AUTO_HOME/tools:$PATH";; esac

  (M1: BOTH `scripts/` and `tools/` are prepended — helpers like `ai-project-profile` /
  `knowledge-capture` live under `tools/`.)

  This makes bare-name siblings resolve in ANY context (IDE/GUI git, cron, CI, un-sourced shell).
  Non-entrypoint helpers are only ever reached THROUGH an entrypoint, so they inherit the fixed
  PATH; no per-helper edit needed.
- Project context stays `$(pwd)` for `.omx/`, git, artifacts, project `AGENTS.md`. NO
  `$AI_AUTO_PROJECT`. NO `cd` by the launcher.

## 5. verify seam (R3; C4 keeps scope + scrub + single fold) — resolves D2, fixes F4
`verify.sh` is GLOBAL framework. It KEEPS its `AI_AUTO_VERIFY_SCOPE` case dispatch EXACTLY
(`full|product|machinery`, default `full`); KEEPS the scrubbed single machinery entry; does NOT
run machinery twice; does NOT drop the env-scrub.
- It sources `docker-config-guard.sh` + `session-lock.sh` by BARE name on PATH via `command -v`
  (NOT the `-f "${repo_root}/scripts/..."` guard, which would SILENTLY skip the lock in a
  zero-vendor project).
- Scope branches (C4 — derived-project verify is NOT a green no-op):
  - `full`  → `verify-machinery.sh` (engine self-test) + `scripts/verify-project.sh` (if present).
  - `product` → `scripts/verify-project.sh` (if present); NO machinery.
  - `machinery` → `verify-machinery.sh` only.
- The GATE seam is UNCHANGED: `review-gate.sh:592` calls `verify.sh` with
  `AI_AUTO_VERIFY_SCOPE=product` (real project tests, no machinery), and the scrubbed
  machinery-FOLD at `review-gate.sh:604-624` remains the SINGLE machinery entry with its full
  `env -u REVIEW_DECISION_GATE -u REVIEW_PROVENANCE_SKIP -u REVIEW_INTEGRATION_ONLY
  -u REVIEW_TARGETED_RECHECK …` scrub. Machinery runs ONCE per gate.
- CREATE `scripts/verify-project.sh` in THIS repo: ai-lab's `run_product_pytest` /
  `run_product_smoke` / `API_PORT` logic migrates out of `verify.sh` into it. `doctor --project`
  warns loudly when a derived project lacks `verify-project.sh` (§12), so a missing real test is
  visible, never a silent green.

## 6. AGENTS.md (R6; C1 scopes the closure) — resolves D6
- A thin PROJECT `AGENTS.md` overlay is OPTIONAL. The engine read targets degrade gracefully to
  the global base when the project has no overlay: `collect-review-context.sh` feeds the global
  base `AGENTS.md` (C1) and `doc-budget.sh` simply matches nothing — no crash, no skip, gate
  unaffected (verified, defense-r1). `ai-auto setup` therefore does NOT seed a stub when it removes
  a pristine base (delete > add); base-only is the intended global-mode behavior. A project MAY add
  its own `AGENTS.md` overlay at any time and it is read alongside the base.
- **C1 — reviewer-context closure (`collect-review-context.sh` ONLY):** in
  `collect-review-context.sh:187` (the `for file in AGENTS.md …` reference-file collector) ALSO
  read the global base `$AI_AUTO_HOME/AGENTS.md` alongside the project overlay, so reviewer
  context regains the base operating rules. **C7 dedup (closes F9):** skip the global base when it
  `-ef` the project file (self-host: `AI_AUTO_HOME == pwd`), so the same file is never fed/flagged
  twice (guidance-duplicate-report stays clean).
- **C1 — `doc-budget.sh:167` is NOT a content read; DO NOT add the global base there.** It is a
  220-line volume CAP on the project's own guidance. Live fact: root `AGENTS.md` = 169 lines,
  fail cap = 220; concatenating base+overlay (169+169=338) would exceed the cap and turn the
  self-host gate RED, and would count engine-owned (growing) base lines against a derived
  project's own budget. `doc-budget.sh:167` stays reading the PROJECT `AGENTS.md` ONLY. If full
  guidance volume is ever wanted, it must be a SEPARATE non-gating informational line — never
  folded into the capped measurement.

## 7. doc-budget (R7) — resolves D8 — UNCHANGED from v2
Retire the inherited-baseline (sole consumer `doc-budget.sh:20` `.ai-auto/guidance-baseline.sha256`,
sole writer = the deleted `refresh-guidance-baseline.sh`). Remove the `GUIDANCE_BASELINE` branch
and ALL `templates/automation-base/*` budget branches (incl. `:171-180`). doc-budget then measures
only the project's own guidance (thin overlay + project docs). Caps are upper bounds → thin overlay
passes. Update its verify-machinery tests in lockstep (folded into §2).

## 8. ai-auto setup (R4; C2 self-host guard) — resolves D3, fixes F2
`ai-auto setup` (run in a project, `pwd`=project), ONE idempotent command folding init+migrate:
0. **C2 SELF-HOST GUARD (FIRST, before any hashing or `git rm`):** ABORT with a clear message if
   `git rev-parse --show-toplevel` resolves to `$AI_AUTO_HOME`, OR the target tree carries the
   ENGINE-ONLY markers (`scripts/verify-machinery.sh` AND an executable `tools/ai-auto`) that are
   never vendored into a project. (F4 fix: the earlier `scripts/review-gate.sh` + `templates/
   domain-packs/` sentinel false-aborted a legitimate project that vendored review-gate.sh and
   authored its OWN domain pack; both halves overlap real project content, so they cannot identify
   an engine checkout.) NEVER `git rm` inside the engine repo.
1. For each tracked managed framework file, compare bytes to the global pristine in `$AI_AUTO_HOME`:
   byte-match → `git rm` (unmodified vendored copy); differs → LEAVE + REPORT (never delete work).
2. `AGENTS.md`: pristine (==global base) → remove base (do NOT seed a stub; the overlay is OPTIONAL,
   §6 — base-only degrades gracefully); customized → keep as-is (it IS the overlay).
3. Ensure `.omx/` is gitignored.
4. Detect domain via existing `ai-project-profile`.
5. Install thin hook shims (§9).
Idempotent (no marker file; keys off git state + hash). Fail-closed on a dirty tree that risks loss.

## 9. Hooks (R5; C5 baked path, C7 fail-closed) — resolves D7, fixes F5/F6/F7
- Do NOT hijack `core.hooksPath`. Resolve the project's ACTUAL hooks dir once
  (`git rev-parse --git-path hooks`, worktree / shared-common-dir aware) and install thin shims
  there (uncommitted, as today).
- **C5 baked absolute path:** `ai-auto setup` resolves the engine path with `readlink -f` at
  install time and BAKES that absolute path into each shim. The shim does NOT depend on a profile
  PATH / `$AI_AUTO_HOME` being set in the git-hook env:

      #!/usr/bin/env bash
      AI_AUTO_HOME="<readlink -f baked absolute engine root>"
      . "$AI_AUTO_HOME/hooks/git-scrub.sh"   # canonical git-exec-env scrub (single source, F1)
      PATH="$AI_AUTO_HOME/scripts:$AI_AUTO_HOME/tools:$PATH"
      exec "$AI_AUTO_HOME/hooks/<hook>" "$@"

  The shim, the launcher `tools/ai-auto`, and both engine `hooks/{pre,post}-commit` ALL source
  the ONE canonical git-exec-env scrub list — `hooks/git-scrub.sh` (R5 single-source fix, F1):
  the GIT_DIR family, the GIT_CONFIG_* injection family, the command-exec vars
  (GIT_EXTERNAL_DIFF/PAGER/EDITOR/SSH/PROXY/ASKPASS + object-dir overrides), plus GIT_TRACE*
  (loop-unset via `${!GIT_TRACE@}`) and GIT_TEMPLATE_DIR/GIT_ATTR_NOSYSTEM/GIT_CEILING_DIRECTORIES.
  No four-copy denylist to drift. (The project-local `.gitattributes`/`.git/config` diff/filter
  RCE — which env scrubbing cannot reach — is closed at the call site in `review-gate.sh`
  provenance: `--no-ext-diff --no-textconv` on diffs, `--no-filters` on `git hash-object`.)

- The global `hooks/pre-commit` and `hooks/post-commit` ARE the framework bodies directly (the
  worktree-safe commit-test bodies relocated from the deleted `templates/automation-base/hooks/`).
  No run-parts, no `.d/` dirs (C6). They begin with the §4 self-heal guard and call siblings by
  bare name on the now-fixed PATH.
- **C7 fail-closed semantics:** `pre-commit` runs fail-CLOSED (nonzero blocks the commit) and
  PRESERVES the existing pytest exit-5 / no-runner handling (a "no tests collected" exit-5 must
  NOT block). `post-commit` is advisory: it must NEVER block — it always `exit 0`.
- **C7 machinery-fold grep gap (closes F7):** the relocation of the commit-test body to top-level
  `hooks/**` means a change to a framework hook body no longer matches the old
  `^(scripts/|templates/automation-base/...)` trigger. UPDATE both fold-trigger greps to
  `^(scripts/|hooks/)` — at `review-gate.sh:606` AND in the relocated `hooks/pre-commit` body
  (was `templates/automation-base/hooks/pre-commit:54`). Drop the now-dead
  `templates/automation-base/*` alternatives.
- The odoo pack's `pre-push` (different filename) coexists in the one resolved hooks dir. (D7
  re-affirmed: framework owns `pre-commit`/`post-commit`, odoo owns `pre-push` — three distinct
  names, no collision.)

## 10. Extensibility = DOCUMENTED CONVENTION, not built (C6 — fixes F10, shortest-code)
DROP run-parts / `hooks/<hook>.d/*` dispatch and `packs/<verb>` routing ENTIRELY (YAGNI — exactly
one framework hook body and one domain-pack hook exist). Extensibility is a DOCUMENTED seam: "a
pack is a global directory; a future second hook part or pack verb is a known dispatch seam to add
WHEN a real second consumer exists." Mirrors the existing directory-discovered `ai-domain-pack`
model. No net-new dispatcher infrastructure now. (v2 §10 is removed.)

## 11. Launcher `tools/ai-auto` (thin, UX only)
- `ai-auto setup|gate|verify|doctor`. Self-resolves `$AI_AUTO_HOME` via `readlink -f` (§4 guard),
  ensures PATH, runs the engine with `pwd`=project. `gate`==`review-gate.sh`,
  `verify`==`verify.sh`, `doctor`==`automation-doctor.sh --project`. An UNKNOWN verb errors with
  usage (no `packs/` routing — C6). Load-bearing resolution is the §4 guard; the launcher is
  convenience.

## 12. doctor (R9) — resolves D4/D5 — UNCHANGED from v2 (+ F4 warn)
`automation-doctor.sh` gets two modes:
- `--project` (default in a project): checks ONLY `scripts/verify-project.sh` (optional — **warn
  LOUDLY if absent**, so a derived project's missing real verification is visible per C4/F4), the
  installed hook shims, and `.omx/` gitignored. A zero-framework-file project PASSES.
- `--home` (in `$AI_AUTO_HOME`): engine inventory (`scripts/*`, `docs/*`, `tools/*` minus the two
  deleted tools); the `:67` source-repo gate drops its `ai-auto-template-status` condition; remove
  the `.ai-auto/template-manifest.json` reads (`:442-455`) and `ai-template-refresh` suggestion.

## 13. Version-sentinel RIPPLE (C3 — fixes F3): KEPT tools that key off the deleted marker
The deleted marker FILE `templates/automation-base/AI_AUTO_TEMPLATE_VERSION` (and the
`AI_AUTO_TEMPLATE_VERSION` concept) is referenced by THREE KEPT, LIVE tools. Each must be edited to
drop the dependency cleanly — no "unknown"/silent-skip:
- `scripts/obsidian-autopush.sh:81` — home-checkout guard tests the marker file → after deletion it
  NEVER exists → home knowledge-push SILENTLY dies. FIX: detect the home checkout by a surviving
  sentinel — `[ -f "${HOME_ROOT}/scripts/verify-machinery.sh" ] && [ -d "${HOME_ROOT}/templates/domain-packs" ]`.
- `tools/ai-domain-pack:122` (`write_manifest`) — stamps `template_version` from the marker →
  degrades to literal `"unknown"`. FIX: drop the `template_version` field from the written manifest
  (the version concept is retired) and remove the `version_path` read; this is the tool the design
  redirects staleness reporting onto, so its manifest must not carry a dead field.
- `tools/ai-tmux-worktree:27-28` (`is_ai_auto_project`) — detects via `AI_AUTO_TEMPLATE_VERSION` OR
  the marker file OR `.omx/tmux-worktree`. FIX: replace the two marker tests with a
  deleted-file-free detector — home: `scripts/verify-machinery.sh` + `templates/domain-packs/`;
  globalized project: `.omx/`. Net: `[ -d "$top/templates/domain-packs" ] || [ -d "$top/.omx" ]`.
Plus the NAME-ref ripple (already in v2, re-affirmed): `automation-doctor.sh`,
`bootstrap-ai-lab.sh`, `install-global-files.sh`, `review-gate.sh`, `tools/ai-home`,
`tools/ai-rebuild-plan`, README/docs — scrub `ai-auto-template-status`/`ai-template-refresh`/
`check-template-version`/`template-manifest` refs; redirect any `domain_packs` drift report to
`ai-domain-pack status` (domain packs STAY).

## 14. DONE criteria — UNCHANGED
design certified ∧ implementation certified ∧ defense game converged (2 dry red rounds) ∧ all
engine self-tests + new global-mode tests green ∧ clean end-to-end `ai-auto setup` of a throwaway
project (setup → gate runs from global → no framework files committed → doctor --project green) ∧
self-host `verify.sh` (full) green.
