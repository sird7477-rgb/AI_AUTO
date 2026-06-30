# Defense R8 — MINIMALITY + GOAL (RED TEAM, HEAD b581bf5)

Read-only audit. Suite GREEN: **237 passed, 1 skipped** (.venv pytest, 78s) — matches documented 237/1.
Verdict: **CLEAN.** GOAL fully met; no dead code; 2-layer git defense non-redundant; docs+SPEC.v3 in sync.
The sole prior open item (R7 LOW-1) was fixed before this round.

## NET DIFF & BLOAT
- `git diff 6e90184..HEAD --stat`: 5529 insert / 31483 delete — overwhelmingly DELETION (good).
- The entire second engine copy `templates/automation-base/` (~30 scripts, 22 docs, AGENTS/README,
  PATCH_NOTES, AI_AUTO_TEMPLATE_VERSION, hooks/), `install-automation-template.sh`,
  `check-template-version.sh`, `refresh-guidance-baseline.sh`, `ai-auto-init`,
  `ai-auto-template-status`, `ai-template-refresh`, `test_template_global_contracts.py`,
  `template-version-gate.yml` all gone from the index. No surviving bloat in the kept tree.

## 2-LAYER GIT DEFENSE — verified non-redundant (NEITHER layer removable)
Verified which vectors each layer UNIQUELY closes before judging removal:
- **Layer A — chokepoint `hooks/git-scrub.sh`** (sourced by launcher + both engine hooks + baked
  shim; process-level, inherited by children through `exec`/`export`): closes the ENV surface
  (unset GIT_DIR family / exec-vars / GIT_CONFIG_* injection / GIT_TRACE*), THEN re-exports a
  controlled `GIT_CONFIG_COUNT=2` pinning `core.fsmonitor=''`/`diff.external=''` for the ~15 PLAIN
  `git` call-sites (e.g. review-gate.sh:48 `git rev-parse`, :54 `git ls-files`). This is the ONLY
  defense those plain calls have against in-repo `.git/config` exec keys.
- **Layer B — `review_git()` (`scripts/git-harden.sh`, single-source)** (sourced by
  review-gate/summarize/collect): `-c diff.external= -c core.fsmonitor= -c core.attributesFile=/dev/null`
  + callers' `--no-ext-diff --no-textconv --no-filters` on patch-producing calls.
- review-gate.sh / summarize-ai-reviews.sh / collect-review-context.sh **do NOT source git-scrub.sh**
  — when any is invoked DIRECTLY (not via the `ai-auto` launcher that execs them with the chokepoint
  env), Layer B's `-c` flags are the ONLY config-exec defense for the patch-producing calls. So
  Layer B is NOT redundant with Layer A.
- **`--no-ext-diff` is NOT redundant with the chokepoint's `diff.external=''`:** `--no-ext-diff`
  ADDITIONALLY disables ATTRIBUTE-selected diff drivers (`*.x diff=foo` → `[diff "foo"] command=`),
  a distinct vector that emptying the `diff.external` CONFIG key cannot reach. `core.attributesFile=
  /dev/null` + `--no-textconv`/`--no-filters` likewise close attribute-driven textconv/clean drivers
  the chokepoint cannot touch. Layers cover DISJOINT call-site sets (plain vs patch-producing) and
  DISJOINT vectors (env/config vs attribute). Per the brief's caution: removing either opens a real
  vector. No removal warranted.

## SINGLE-SOURCE / DEAD CODE — CLEAN
- `review_git()` DEFINED only in `scripts/git-harden.sh`; git-exec-env unset list lives only in
  `hooks/git-scrub.sh`. The `verify-machinery.sh` occurrences (7104/7152/7169) are GUARD TESTS that
  grep for drift + assert shim repointing — not second copies.
- Whole-tree grep for every P1-R7 deleted artifact (install-automation-template, check-template-version,
  refresh-guidance-baseline, ai-auto-init, ai-auto-template-status, ai-template-refresh,
  AI_AUTO_TEMPLATE_VERSION/STALENESS, template-version-gate, guidance-baseline, template-manifest,
  automation-base, test_template_global_contracts, check_template_staleness, check_offmanifest):
  ZERO live refs. Sole survivor = the intentional historical-provenance comment at
  `tools/ai-auto:22-23` (cites the deleted installer as FRAMEWORK_PATHS provenance; no live ref).
- `git-harden.sh` in FRAMEWORK_PATHS (tools/ai-auto:41) is CORRECT, not stray: a project that
  vendored `review-gate.sh` under the old model needs its co-vendored helper removed in lockstep.

## GOAL §13/§14 FINAL e2e — throwaway already-patched project → `ai-auto setup`
Vendored pristine AGENTS.md + docs/WORKFLOW.md + scripts/verify.sh + scripts/review-gate.sh, then
locally customized review-gate.sh; committed; ran `ai-auto setup`. All 7 assertions PASS:
1. zero committed framework files — AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh staged+committed
   away; only app.py + the CUSTOMIZED review-gate.sh remain tracked ✓
2. `.omx/` gitignored (`git check-ignore .omx/x` → IGNORED) ✓
3. baked-path shims — `.git/hooks/{pre,post}-commit` carry `AI_AUTO_HOME="/root/workspace/ai-lab-globalize"`
   + `AI_AUTO shim` marker ✓
4. gate from global engine — `tools/ai-auto:258 exec "$AI_AUTO_HOME/scripts/review-gate.sh"` ✓
5. idempotent re-run → "Nothing to remove (already migrated) … exit 0" ✓
6. self-host abort → `ai-auto setup <engine>` ABORT, exit 1, no changes ✓
7. adoption commit SUCCEEDS — pre-commit shim runs, finds no verify-project.sh, LOUDLY WARNS +
   ALLOWS, commit exit 0; post-commit advisory warns, never blocks ✓

**GOAL fully met: YES (definitive).**

## DOCS + SPEC.v3 truthfulness — IN SYNC
- SPEC.v3:116 now reads "an **existing** `tools/ai-auto`" — the R7 LOW-1 drift (was "executable",
  vs code's `-f` existence test at ai-auto:83-84) is FIXED. Spec matches code.
- README + NEW_PROJECT_GUIDE + GLOBAL_TOOLS + CURRENT_STATE all onboard via `ai-auto setup`; no
  stale `cp templates/automation-base` / install-automation-template instructions survive. `aiinit`
  appears only as a legacy `~/bin` symlink repointed at `tools/ai-auto` (install-global:1063) — truthful.

## FINDINGS
None (HIGH/MED/LOW). No code change recommended.
