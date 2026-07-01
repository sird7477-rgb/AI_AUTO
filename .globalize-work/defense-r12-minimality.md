# Defense R12 — MINIMALITY + GOAL lens (RED TEAM, final gauntlet, HEAD aa51a76)

Read-only audit. Suite GREEN: **237 passed, 1 skipped** via `.venv` (89s).

## Verdict: DEFECTS: 1 (highest HIGH). GOAL met = **NO** for the AI_AUTO_TEMPLATE_VERSION-vendored class.

R11-1 (docs/PATCH_NOTES.md retirement) is now CLOSED — e2e proves it is git-rm'd. But the R11
fix retired only ONE of the TWO retired vendored files. Its sibling is still orphaned.

---

## FINDING R12-1 (HIGH) — committed `AI_AUTO_TEMPLATE_VERSION` survives migration ⇒ goal #1 fails
`tools/ai-auto:24-50` (FRAMEWORK_PATHS) + `:70-77` (is_retired_framework_file) omit
`AI_AUTO_TEMPLATE_VERSION`; the comment at `:22-23` deliberately drops it ("minus … the
retired AI_AUTO_TEMPLATE_VERSION marker"), but that decision defeats goal #1.

- PROVEN old model vendored it: `install-automation-template.sh` MANAGED_PATHS@62 +
  `cp …/AI_AUTO_TEMPLATE_VERSION`@184. EVERY old-copy-model project carries a committed
  `AI_AUTO_TEMPLATE_VERSION` (engine blob 6e90184 = `2026.06.30.6`).
- It is NOT in FRAMEWORK_PATHS and NOT recognized by is_retired_framework_file (that case
  matches only `docs/PATCH_NOTES.md`). So the de-pollution loop never iterates it.
- DEFINITIVE e2e (throwaway already-patched project, committed AGENTS.md + docs/WORKFLOW.md +
  review-gate.sh + verify.sh pristines, committed docs/PATCH_NOTES.md + AI_AUTO_TEMPLATE_VERSION,
  customized docs/DOMAIN_PACKS.md, tracked .omx) → `ai-auto setup` → commit:
  - Removed 4 pristine + **docs/PATCH_NOTES.md** (R11-1 works) ✓
  - **`AI_AUTO_TEMPLATE_VERSION` STILL TRACKED** after adoption commit ✗ — a committed AI_AUTO
    framework file remains. Goal #1 ("zero committed framework files") FAILS for this class.
- This is the SAME defect class R11-1 closed for PATCH_NOTES; the retirement mechanism
  (`is_retired_framework_file` + `retired[]`) already exists — it was simply not extended to
  the second retired file.
- UNGUARDED: verify-machinery R11-1 test (`:7594`) exercises PATCH_NOTES only; no test seeds
  a vendored AI_AUTO_TEMPLATE_VERSION.
- Secondary: `docs/NEW_PROJECT_GUIDE.md:22` claims setup "de-pollutes **any** framework files
  left from the old copy model" — now untruthful for the AI_AUTO_TEMPLATE_VERSION class.

Shorter/correct fix (mirrors the existing R11-1 fix, ~3 lines):
- Add `"AI_AUTO_TEMPLATE_VERSION"` to FRAMEWORK_PATHS so the loop iterates it, and add a case
  to is_retired_framework_file:
  `AI_AUTO_TEMPLATE_VERSION) [[ "$first" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2} ]] ;;`
  The filename is itself unambiguous (no project authors a file literally named
  `AI_AUTO_TEMPLATE_VERSION`); the version-string first-line guard keeps a same-named,
  non-framework file safe. Engine ships no pristine, so the `[ ! -e "$pristine" ]` retired
  branch (`:238`) fires exactly as it does for PATCH_NOTES.

---

## GOAL §13/§14 e2e — 6/7 on the vendored-TEMPLATE_VERSION class
Standard assertions PASS: .omx gitignored, baked-path pre/post shims, gate exec's engine copy,
idempotent no-op re-run, self-host ABORT, adoption commit succeeds, customized DOMAIN_PACKS.md
KEPT, docs/PATCH_NOTES.md REMOVED. FAIL only on assertion #1 for AI_AUTO_TEMPLATE_VERSION
(see R12-1). Core goal "migrated project carries zero AI_AUTO framework files" = **NOT met**
for any old-copy-model project (all of them vendored AI_AUTO_TEMPLATE_VERSION).

## DEAD CODE — CLEAN
Tree-wide grep for every deleted tool/mechanism (install-automation-template, ai-auto-init,
ai-template-refresh, ai-auto-template-status, check-template-version, refresh-guidance-baseline,
template-version-gate, AI_AUTO_TEMPLATE_STALENESS). Only live hits: verify-machinery.sh
5850/6327/6383 — the INTENTIONAL `aiinit → ai-auto-init` stale-symlink fixture (install
repoints it); ai-auto:22-23 provenance comment. No surviving dangling ref.

## MINIMALITY of the R11 hardening — near-minimal
`is_retired_framework_file` + `retired[]`/`rmset[]` merge (ai-auto:65-77,226-276) is the
minimal shape for retired de-pollution — EXCEPT it is under-applied (R12-1). git-scrub.sh /
git-harden.sh sourcing at launcher top + baked shim is single-sourced (no four-copy drift).
No new dead helper, duplicate flag, or stale comment beyond the R12-1 gap. Adjudicated belts
(`-c diff.external=`, `--no-textconv`, `--no-ext-diff`) NOT re-raised.

## DOCS / SPEC.v3 / AGENTS — truthful except the R12-1 knock-on
Onboarding commands (`ai-auto setup/gate/verify/doctor`, `aiinit` legacy symlink) match the
launcher dispatch verbatim. Only stale line: NEW_PROJECT_GUIDE.md:22 "any framework files"
over-claims given R12-1.
