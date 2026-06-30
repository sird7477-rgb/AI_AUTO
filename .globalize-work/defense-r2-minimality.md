# Defense R2 — Minimality + Docs-truthfulness + Goal-completeness (HEAD e29a5fe)

Round 2: defeat the R1 fixes (docs rewritten to `ai-auto setup`; dead stub removed)
and hunt NEW issues. Method: executed the documented onboarding on a throwaway
already-patched project, independently grepped for surviving stale refs, ran the
full suite, whole-diff review `6e90184..HEAD`, SPEC.v3 vs code cross-check.

## SUITE — GREEN, matches the claimed baseline
- `python3 -m pytest -q` (.venv): **237 passed, 1 skipped** (102s). PTEXIT=0.
- `bash scripts/verify-machinery.sh`: **VMEXIT=0** — machinery 101 passed / 0 failed /
  6 skipped + embedded pytest 237/1. No NEW failure.

## R1 FIXES — VERIFIED, all hold
- **H1 (docs truthfulness): FIXED.** Every onboarding guide now prescribes `ai-auto
  setup`; NEW_PROJECT_GUIDE.md is fully rewritten; GLOBAL_TOOLS.md documents the
  `ai-auto setup|gate|verify|doctor` launcher (16-26). Every surviving `aiinit`
  mention now truthfully describes it as a *legacy symlink kept pointing at
  tools/ai-auto* (README.md:366, GLOBAL_TOOLS.md:25,217,254, CURRENT_STATE.md:311).
  No surviving `aiinit copies/installs template`, `ai-template-refresh`,
  `template-version`, `install-automation-template`, or "customize docs/WORKFLOW"
  user instruction in any kept *.md. DOMAIN_PACKS.md now says "not auto-copied".
- **M3 (dead stub): FIXED.** `tools/ai-auto-init` is deleted (not in `git ls-files`).
  The only 3 surviving `ai-auto-init` refs (verify-machinery.sh:5842,6319,6375) are
  INTENTIONAL stale-link seeds — they create an old `aiinit -> ai-auto-init` symlink
  and assert install/bootstrap/doctor REPOINT it at `tools/ai-auto`. Correct, not dead
  code. No orphan left.
- **MED-2 (AGENTS overlay): FIXED by spec amendment.** SPEC.v3 §6/§8.2 (82-87,120-121)
  now blesses zero-overlay ("setup does NOT seed a stub; the overlay is OPTIONAL,
  base-only degrades gracefully"). Spec and impl (tools/ai-auto:146-159) now agree.

## GOAL §13 END-TO-END on the hardened build — MET
Throwaway already-patched repo (pristine AGENTS.md + docs/WORKFLOW.md + review-gate.sh
+ doc-budget.sh + verify.sh, plus a CUSTOMIZED automation-doctor.sh) → `ai-auto setup`
→ commit:
- 5 pristine copies `git rm`'d (staged), customized file KEPT + reported. exit 0.
- After commit: tracked tree = `app.txt` + the customized `automation-doctor.sh` only —
  **ZERO committed framework files remain.** ✓
- `ai-auto gate` runs from the GLOBAL engine (`[gate] running verification…` →
  `verify-project.sh absent → NOTHING verified` → blocked verdict). Hook shims bake the
  global engine path and exec it; post-commit warns from the global engine. ✓
- `.omx/` added to `.git/info/exclude`. ✓  No gap.

---

## NEW FINDINGS

### NEW-LOW-1 — Project-marker doc/code contradiction introduced by the R1 doc rewrite
`docs/NEW_PROJECT_GUIDE.md:158` lists the `jwlist`/`sirdlist` auto-enter project marker
as `scripts/verify-project.sh`, but the ACTUAL function (`scripts/install-global-files.sh:343`)
checks `scripts/verify.sh`, and `docs/GLOBAL_TOOLS.md:305,316` also say `scripts/verify.sh`.
R1 rewrote the guide to the new name but left code + GLOBAL_TOOLS on the old one — a
doc-vs-doc AND doc-vs-code contradiction. Functional nuance: an *adopted* project has
`verify-project.sh` (its `verify.sh` is `git rm`'d at setup), so the code's `verify.sh`
marker silently MISSES every globalized project. Navigation convenience only; no onboarding
break. FIX (align to the new model, shortest): change `verify.sh`→`verify-project.sh` at
install-global-files.sh:343 and GLOBAL_TOOLS.md:305,316 (one token each). Same-token edit at
GLOBAL_TOOLS.md:33 ("never merges into …/scripts/verify.sh") — that path no longer exists in
an adopted project.

## RESIDUAL (acknowledged in R1, still present — LOW)
- `tools/ai-auto:192-196`: `gate/verify/doctor --help` still `exec`s the engine with `"$@"`,
  so `ai-auto gate --help` starts a REAL gate run instead of usage (observed). R1 ruled this
  "none required". Optional: intercept `-h/--help` per-verb.
- `doctor --project` still probes more than SPEC §12's minimal triple (all warn-only; green
  unaffected). R1 LOW-4.

## Verdict
The R1 fixes survive R2: docs are truthful by execution, the dead stub is genuinely gone,
the spec/impl overlap is reconciled, GOAL §13 (zero framework files + gate-from-global) holds
end-to-end, and the suite is GREEN at the claimed 237/1. Only one new defect — a LOW
doc/code marker contradiction (NEW-LOW-1) seeded by the R1 doc rewrite.
</content>
</invoke>
