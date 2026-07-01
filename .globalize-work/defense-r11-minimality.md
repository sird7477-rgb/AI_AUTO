# Defense R11 — MINIMALITY + GOAL lens (RED TEAM, final gauntlet, HEAD 70fd6e5)

Read-only audit. Suite GREEN: **237 passed, 1 skipped** via `.venv` (104s).

## Verdict: DEFECTS: 1 (highest MED). GOAL met = YES for standard migrations; NO for the PATCH_NOTES-vendored class.

---

## FINDING R11-1 (MED) — orphaned FRAMEWORK_PATHS entry ⇒ de-pollution gap + mislabel
`tools/ai-auto:33` lists `"docs/PATCH_NOTES.md"` in `FRAMEWORK_PATHS`, but the engine ships
NO `docs/PATCH_NOTES.md` pristine (it exists neither at base 6e90184 nor HEAD; the engine
carries only dated `docs/PATCH_NOTES_*.md`). It is the ONLY orphaned path in the list.

- The OLD copy model DID vendor it: `install-automation-template.sh` MANAGED_PATHS@79 +
  `cp .../docs/PATCH_NOTES.md`@200, from `templates/automation-base/docs/PATCH_NOTES.md`.
  So essentially EVERY old-copy-model project carries a committed `docs/PATCH_NOTES.md`.
- De-pollution requires a pristine for `cmp -s` (ai-auto:215). With no pristine, the
  `[ -f "$pristine" ]` guard is false → the file always lands in `kept` and is reported
  `~ docs/PATCH_NOTES.md (customized — review)`.
- PROVEN e2e: a byte-identical vendored copy (old template blob) → `Removed: 0 / Kept: 1`.
  The file stays committed forever, mislabeled "customized" though it is pristine framework
  content. Goal assertion #1 ("zero committed framework files") FAILS for this class.
- No test exercises it (`tests/` has zero PATCH_NOTES setup refs), so the gap is unguarded.

Shorter/correct fix (pick one, both 1-line):
- Honest minimal: delete `"docs/PATCH_NOTES.md"` from FRAMEWORK_PATHS — the entry can NEVER
  fire, so it is dead + only produces a misleading "customized" report. (Leaves the legacy
  file in place, now treated as project-owned.)
- Full de-pollution: re-add a canonical `docs/PATCH_NOTES.md` pristine to the engine so `cmp`
  can prove byte-identity and `git rm` it like the other ~40 paths. Without a pristine, safe
  byte-identity removal is impossible, so the current entry is strictly non-functional.

---

## GOAL §13/§14 e2e — 7/7 PASS on the standard patched project (throwaway, manual)
Vendored pristine AGENTS.md + docs/WORKFLOW.md + scripts/review-gate.sh + scripts/verify.sh
+ locally-edited docs/DOMAIN_PACKS.md + tracked .omx, then `ai-auto setup`:
1. Zero committed framework files — PASS (4 pristine `git rm`'d; only app.py + customized
   DOMAIN_PACKS.md remain). *Caveat: see R11-1 for docs/PATCH_NOTES.md class.*
2. .omx gitignored — PASS (`.omx/` in info/exclude; untracked `.omx/x` → check-ignore hit).
3. Baked shims — PASS (pre/post-commit carry `AI_AUTO shim` + literal
   `AI_AUTO_HOME=/root/workspace/ai-lab-globalize`).
4. Gate from global engine — PASS (no local review-gate.sh; launcher `exec`s engine copy).
5. Idempotent — PASS (`Nothing to remove… exit 0`).
6. Self-host abort — PASS (setup on engine → ABORT exit 1, no mutation).
7. Adoption commit succeeds — PASS (commit exit 0; shims fired pre+post, 4 deletions).
Customized DOMAIN_PACKS.md correctly KEPT.

## DEAD CODE — CLEAN (all live/intentional)
Tree-wide grep for every P1–R10 deletion. All hits are LIVE engine scripts now at top-level
`scripts/` (record-project-memory/resolve-feedback/todo-report/validate-odoo-docs-kb/
session-lock/write-session-checkpoint/record-lane-decision — the deletions were the
`templates/automation-base/scripts/` COPIES, not these). Remaining:
- `tools/ai-auto:22-23` — provenance comments (install-automation-template / TEMPLATE_VERSION).
- `verify-machinery.sh:5850/6327/6383` — INTENTIONAL fixture seeding a stale `aiinit→
  ai-auto-init` symlink that install-global-files.sh repoints to `tools/ai-auto`. Not dead.

## DOCS + SPEC.v3 + AGENTS.md — truthful, in sync
NEW_PROJECT_GUIDE / GLOBAL_TOOLS / README / DOMAIN_PACKS / CURRENT_STATE describe the global
model; documented onboarding commands (`ai-auto setup/gate/verify/doctor`) match the launcher
dispatch table exactly. `aiinit` documented as legacy symlink → launcher (matches fixture). No
active-doc instruction points at any deleted tool (ai-auto-init/template-status/template-refresh/
template-version-gate/TEMPLATE_STALENESS all absent from active docs).

## MINIMALITY of the hardening — near-minimal
R10's single LOW (`-c diff.external=` fail-closed belt at git-harden.sh:39/41) is an
acknowledged deliberate defense-in-depth belt (converts a future un-`--no-ext-diff`'d patch
call from RCE to a loud fatal); NOT re-raised. `--no-ext-diff`/`--no-textconv` proven
non-removable in prior rounds; not re-flagged. git-harden.sh 43 lines, git-scrub.sh 65 lines —
compact; no new duplicate flag, dead helper, or stale comment found beyond R11-1.
