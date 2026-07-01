# Defense R12 — HOLISTIC/INTEGRATION + SUITE-INTEGRITY (RED TEAM)

Verdict: **CLEAN** — no functional regression, no vacuous/masking fixture, no suite flake.
Worktree aa51a76 (feat/global-toolize). Read-only; temp repos via mktemp; this worktree's
.git/config was NOT mutated.

## What was exercised

### R11 setup lifecycle (de-pollution correctness)
Built temp repos and ran the REAL launcher `tools/ai-auto setup`:
- PATCH_NOTES with marker `# AI_AUTO Patch Notes`, clean worktree -> STAGED for deletion (correct retire).
- PATCH_NOTES WITHOUT the marker (project-authored) -> KEPT, still tracked (correct).
- PATCH_NOTES with marker but DIRTY worktree -> KEPT (retire gated on `review_git diff --quiet`; dirty fails it -> else -> kept).
- PATCH_NOTES with marker STAGED-modified -> dirty-index precheck ABORTs before any mutation; nothing changed.
- PATCH_NOTES marker with NO trailing newline -> KEPT (read hits EOF -> `return 1`; fails safe/conservative).
- setup `[dir]` invoked from a NON-git CWD -> git-harden.sh sources fine (hash-object fallback), PATCH_NOTES removed. No slowdown/break: git-harden.sh is sourced ONLY inside `ai_auto_setup` (tools/ai-auto:225), NOT at launcher top, so gate/verify/doctor never touch it.
- Pristine framework files still de-polluted, customized files still kept (F4/F6 fixtures + manual).
- Marker string validated against the REAL vendored template `templates/automation-base/docs/PATCH_NOTES.md:1` (`# AI_AUTO Patch Notes`) -> retire fires on real projects, not just fixtures.
- No engine component outside tools/ai-auto references PATCH_NOTES (grep), so removing it cannot break gate/verify/doctor.

### git rm safety (flock + dirty-precheck)
Retired set is folded into the SAME single atomic `review_git rm -- pristine+retired` (tools/ai-auto:261-269). git validates all pathspecs up front (all-or-nothing) -> no half-migration. Ordering (F5) puts the destructive rm LAST, after hooks/.omx are installed. Idempotent re-run: already-removed paths fail `ls-files --error-unmatch` -> skipped. flock serializes; flock-absent degrades to clean abort of the racer.

### Engine self-host / fake-engine test
`globalize_mk_engine` now `cp`s the REAL scripts/git-harden.sh (verify-machinery.sh:6551) — non-masking: it ships the genuine wrapper, and without it setup would die sourcing a missing file (loud fail, not silent pass). doctor --home exit 0.

### Fixture non-vacuity audit
- R11-SETUP-RCE positive control: neuters ONLY `--attr-source` via sed; the same hostile project then FIRES the clean filter (asserts PWNED created). Discriminating pair -> negative (real launcher, NOT PWNED) is non-vacuous; control proves setup reaches the diff.
- R11-1: tests BOTH marker->removed AND no-marker->kept -> marker gate proven non-vacuous.
- b8 (extensionless), b8-nonscript (shebang gate), b9 (command-prefix) controls all discriminate.
- Drift-guard extracted + run standalone: real tree = **55 sites scanned, all hardened**; injected un-hardened worktree `git diff` is CAUGHT in .sh, .py, AND extensionless-shebang files. All 14 tools/ git-diff callers carry shebangs -> all scanned (no blind spot).

### Suite integrity (each TWICE, non-flaky)
- `bash scripts/verify-machinery.sh`: 237 passed / 1 skipped, exit 0 (x2).
- `( . hooks/git-scrub.sh && bash scripts/verify-machinery.sh )`: 237/1, exit 0 (x2).
- `python3 -m pytest -q` (.venv): 237/1, exit 0 (x2).
Embedded pytest inside verify-machinery: 237/1 each. No flake.

### Post-suite pollution
.git/config clean (no evil/pwn/fsmonitor/external/textconv/filter); no /tmp PWNED markers; no unexpected staged deletions; worktree shows only .globalize-work/ files (STATE.md + other agents' r12 notes) — no fixture leak.

## Findings
None. The R11 changes (setup sourcing git-harden.sh, retired-file `git rm`, extensionless-guard, RCE positive control) are correct, safe, and covered by non-masking fixtures.
