# Defense R1 — Minimality + Goal-Completeness red-team (HEAD aa8d028)

Surface: MINIMALITY ("shortest code wins") + COMPLETENESS of §13/§14 DONE.
Method: read full changed tree, ran the suite, built a throwaway already-patched
project and ran `ai-auto setup` → commit → `doctor` → hook-shim end-to-end.

## SUITE — GREEN, matches claimed baseline
- `python3 -m pytest -q` (.venv): **238 passed, 1 skipped** (66s). Matches baseline.
- `bash scripts/verify-machinery.sh`: exit 0 — **101 passed / 0 failed / 6 skipped**
  (machinery) + the embedded pytest 238/1. No NEW failure.

## END-TO-END DONE (§14) — substantially MET, one spec divergence
Built a repo with byte-pristine vendored AGENTS.md + review-gate.sh + doc-budget.sh +
docs/WORKFLOW.md + verify.sh + a CUSTOMIZED automation-doctor.sh, then `ai-auto setup`:
- Pristine copies `git rm`'d (5), customized file KEPT + reported. ✓
- After commit: ZERO tracked framework files except the legitimately-customized one. ✓
- `doctor --project` on the clean project: **exit 0, 0 failed** (green). ✓
- pre-commit hook shim execs the GLOBAL engine body (`[pre-commit] running tests…`),
  exit-5 "no tests" correctly non-blocking. ✓  Gate is runnable from global. ✓
- FRAMEWORK_PATHS verified against the deleted installer's MANAGED_PATHS (git show
  6e90184): faithful mirror minus verify.sh + version marker — **no framework file is
  missed** by the migrate set. (session-lock.sh / record-lane-decision.py were never in
  MANAGED_PATHS, so correctly excluded — checked, NOT a defect.)

---

## RANKED FINDINGS

### HIGH-1 — User-facing docs still prescribe the DELETED `aiinit` copy model; the real `ai-auto setup` is undocumented
`aiinit`/`ai-auto-init` is now a do-nothing stub (`tools/ai-auto-init:23-26`, `exit 1`).
Yet the kept docs still present it as THE project-setup command, so a user who follows the
official guide runs `aiinit` and gets a hard error; the actual command (`ai-auto setup`)
appears in NONE of the setup guides. Stale, now-wrong instructions:
- `docs/NEW_PROJECT_GUIDE.md:9,13,15,21,108-109,157,159,161,219,249,285,314-316`
  — "Manual setup: `aiinit`" — the entire guide. (Note :18 already claims the global
  outcome "No framework files are vendored" while still prescribing the dead command —
  internally inconsistent.)
- `docs/GLOBAL_TOOLS.md:14-26,213-215,250-252` — documents `aiinit`/`ai-auto-init` as the
  live setup tool ("Sets up the AI_AUTO workflow…"); the `ai-auto` launcher (the central
  deliverable) is entirely absent.
- `docs/DOMAIN_PACKS.md:29,43` — "`aiinit` copies available packs into the target repo"
  (false — nothing is copied now).
- `README.md:31,193,363-364,371,390` — `aiinit`/`ai-auto-init` as setup command.
- `docs/CURRENT_STATE.md:214,224-259,284,305-307,446,598,645-648`,
  `docs/WORKFLOW.md:87,314`, `docs/MULTI_AI_COLLABORATION.md:33,363,414`,
  `docs/INTERVIEW_PLAN_LAYER.md:22`, `docs/AUTOMATION_OPERATING_POLICY.md:564`,
  `docs/OBSIDIAN_INTEGRATION.md:32,325` — same stale copy/template narrative.
FIX (shorter + correct): replace every `aiinit … (copies/installs template)` instruction
with `ai-auto setup` (de-vendors), and document the `ai-auto setup|gate|verify|doctor`
launcher in GLOBAL_TOOLS.md. Delete the copy/template prose, don't reword it.

### MED-2 — `ai-auto setup` removes a pristine AGENTS.md but never seeds the thin overlay stub SPEC §8.2/§6 mandates
`tools/ai-auto:14-83` treats `AGENTS.md` as a generic FRAMEWORK_PATHS entry → `git rm` on
byte-match, with NO overlay seeded. SPEC §8.2: "pristine → remove base, **seed a thin
overlay stub** (§6 read target)"; §6: "KEEP a thin PROJECT AGENTS.md overlay so every
engine read target exists." e2e confirmed: after setup the project has NO AGENTS.md
(tracked or untracked). Not a crash — `collect-review-context.sh:192-194` degrades to
base-only and `doc-budget.sh` pathspec matches nothing — but reviewers permanently lose
any project overlay and the impl contradicts its own spec. FIX: either seed the 1-line
stub in setup (spec), or amend §6/§8.2 to bless zero-overlay (shorter). Pick one; the
spec/impl disagreement is the defect.

### MED-3 — `tools/ai-auto-init` is a dead stub kept alive by a chain of install/doctor/test references (shortest-code violation)
The tool does nothing but print an error and `exit 1` (`tools/ai-auto-init:22-26`). Yet it
is still treated as a REQUIRED engine helper and symlinked into the user's PATH:
- `scripts/bootstrap-ai-lab.sh:188-192` (fails the bootstrap if missing/!x), `:337,339`
  (creates `~/bin/ai-auto-init`, `~/bin/aiinit`).
- `scripts/install-global-files.sh:958-959,1064,1066` (source-helper check + both links).
- `scripts/automation-doctor.sh:83` (source-repo gate ANDs `-x tools/ai-auto-init`),
  `:186` (`suggest "aiinit"`), `:738-740` (helper-link checks).
- `scripts/verify-machinery.sh:5832-6390` — ~8 fixtures still assert the `aiinit`/
  `ai-auto-init` symlink install, pinning the dead stub in place.
FIX (delete > add): remove `tools/ai-auto-init`; repoint the `~/bin/aiinit` link (and all
checks/fixtures) at `tools/ai-auto` (so `aiinit`→`ai-auto`), or drop `aiinit` entirely.
Net: one fewer file + ~40 fewer ref lines.

### LOW-4 — `doctor --project` runs far more than the §12 minimal triple
SPEC §12: `--project` "checks ONLY `scripts/verify-project.sh`, the hook shims, and `.omx/`
gitignored." Live `--project` run also probes Gemini reviewers, reviewer-state, `docs/`,
`docs/research/`, git remote, script exec bits (`scripts/automation-doctor.sh`, ~20 extra
checks). All non-fatal (warn) so a clean project still exits 0/green, but it is broader and
noisier than the spec's minimal contract. FIX: gate the extra batteries behind `--home`, or
relax §12 to match. (Minimality: the spec's 3-check version is shorter.)

### LOW-5 — launcher passes `--help` straight through to the engine instead of showing usage
`tools/ai-auto:156-158`: `gate`/`verify`/`doctor` `exec` the engine with `"$@"`, so
`ai-auto gate --help` starts a REAL review (observed: hung until 2-min timeout) rather than
printing usage. Minor UX; not load-bearing. FIX: none required, or intercept `-h/--help`
per-verb.

---
## Verdict
Core mechanism is sound and the suite is green; the ZERO-framework-file + gate-from-global
DONE claims hold end-to-end. The blocking gap is DOCS truthfulness (HIGH-1): the kept guides
still command users to run the gutted `aiinit` and never mention `ai-auto setup`. MED-2/3 are
shortest-code/spec-consistency cleanups.
