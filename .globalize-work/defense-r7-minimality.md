# Defense R7 — MINIMALITY + GOAL (RED TEAM, HEAD 54d2b3e)

Read-only audit. Suite GREEN: **237 passed, 1 skipped** (.venv pytest, 66s) — matches documented 237/1.

## NET DIFF MINIMALITY
- `git diff 6e90184..HEAD --stat`: 5195 insert / 31483 delete — overwhelmingly DELETION (good).
  templates/automation-base (the second full engine copy, ~30 scripts + 22 docs + PATCH_NOTES),
  install-automation-template.sh, check-template-version.sh, refresh-guidance-baseline.sh,
  ai-auto-init, ai-auto-template-status, ai-template-refresh, test_template_global_contracts.py,
  template-version-gate.yml all gone from the index (verified `git ls-files --error-unmatch`).

## SINGLE-SOURCE EXTRACTION (R6) — CLEAN
- `review_git()` defined ONLY in scripts/git-harden.sh:17; sourced by review-gate.sh,
  summarize-ai-reviews.sh, collect-review-context.sh, test-review-summary.sh, verify-machinery.sh.
  NO inline copy survives. (verify-machinery.sh:7104 is a GUARD TEST grepping for drift, not a copy.)
- git-exec-env scrub body defined ONLY in hooks/git-scrub.sh; sourced by tools/ai-auto,
  hooks/{pre,post}-commit, the baked shim, verify-machinery.sh. NO inline `unset GIT_DIR` copy
  survives. (verify-machinery.sh:7152/7169 are GUARD TESTS.)
- No dead branch / redundant double-check found. pre-commit:75 presence-check vs verify.sh:60
  re-check is INTENTIONAL (hook warn-and-allow on absence vs verify.sh fail-close) — not redundant.

## DEAD CODE — none live
- Zero live code refs to any deleted artifact across scripts/ tools/ hooks/ tests/ docs/.
  Sole survivors: explanatory provenance comment (tools/ai-auto:22-23) and INTENTIONAL stale-link
  migration fixtures (verify-machinery.sh:5850/6327/6383 seed `aiinit -> ai-auto-init` to test
  repointing). `aiinit` in docs = truthful legacy-symlink-repointed-at-tools/ai-auto migration note.

## GOAL §13/§14 FINAL e2e — throwaway already-patched project
Vendored pristine AGENTS.md+docs/WORKFLOW.md+verify.sh, customized review-gate.sh; ran `ai-auto setup`:
- zero committed framework files: AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh STAGED+committed away ✓
- .omx gitignored: `.omx/` appended to .git/info/exclude ✓
- baked-path shims: .git/hooks/{pre,post}-commit carry `AI_AUTO_HOME="/root/workspace/ai-lab-globalize"` + `exec "$AI_AUTO_HOME/hooks/pre-commit"` ✓
- gate runs from global engine: tools/ai-auto:257 `exec "$AI_AUTO_HOME/scripts/review-gate.sh"` ✓
- idempotent re-run: exit 0, "Nothing to remove (already migrated)" ✓
- self-host abort: `ai-auto setup <engine>` → ABORT, exit 1, no changes ✓
- **R6 onboarding fix: the printed adoption commit SUCCEEDS** — pre-commit shim runs, finds no
  verify-project.sh, LOUDLY WARNS + ALLOWS (exit 0), commit lands ✓
- customized review-gate.sh KEPT (never deleted) ✓

**GOAL fully met: YES.**

## DOCS + SPEC.v3 truthfulness
- User-facing onboarding (README, NEW_PROJECT_GUIDE, GLOBAL_TOOLS) all say `ai-auto setup`; no stale
  cp-template / install-automation-template instructions. Verified by running the command.
- One spec/code drift (below).

---

## FINDINGS

### LOW-1 — SPEC.v3:116 says self-host guard uses "an **executable** `tools/ai-auto`"; code uses `-f` (existence)
file: .globalize-work/SPEC.v3.md:116 vs tools/ai-auto:83
The R3-1 fix deliberately changed `-x` → `-f` (a tarball / `cp`-without-`-p` / core.fileMode=false
checkout can lose the exec bit while content survives; `-x` would miss the guard and de-pollute the
engine). The code self-documents this at ai-auto:80-81. SPEC.v3's "executable" adjective is now stale;
code is MORE correct than spec. Harmless (internal design note, no runnable command affected).
FIX: in SPEC.v3:116 change "an executable `tools/ai-auto`" → "an existing `tools/ai-auto`".

(No HIGH/MED findings. No code change recommended beyond the one-word SPEC text.)
