# Defense R6 — RED TEAM minimality + goal-completion (HEAD b9a480e)

Read-only audit. Verdict: GOAL fully met, suite green, no dead code. One LOW minimality observation.

## GOAL §13/§14 e2e FINAL PROOF (throwaway already-patched project → `ai-auto setup`)
All PASS — goal fully met:
- (a) ZERO committed framework files remain after setup+commit (only `app.py` tracked).
- (b) `.omx/` gitignored via `.git/info/exclude` (`git check-ignore .omx/state` ✓).
- (c) hook shims `pre-commit`/`post-commit` installed, `AI_AUTO shim` marker + baked `AI_AUTO_HOME="/root/workspace/ai-lab-globalize"`.
- (d) `ai-auto gate`/`verify`/`doctor` all dispatch from the global engine (`$AI_AUTO_HOME/scripts/*`); pre-commit shim runs `ai-auto verify` (product scope) on commit.
- (e) idempotent re-run → "Nothing to remove… exit 0"; self-host `ai-auto setup <engine>` → ABORT, no changes.

## Dead code / orphans — CLEAN
- All P1-R5 deletions truly gone: `tools/ai-auto-init`, `ai-auto-template-status`, `ai-template-refresh`, `scripts/check-template-version.sh`, `install-automation-template.sh`, `refresh-guidance-baseline.sh`, `templates/automation-base/`, `tests/test_template_global_contracts.py`.
- No orphaned refs to deleted fns/sentinels (`check_offmanifest_shadows`, `template_parity_boundary`, `staleness`, `AI_AUTO_TEMPLATE_STALENESS`, off-manifest) in code/tests/docs. The lone `staleness` hit (review-gate.sh:276) is unrelated reviewer-disable logic.
- NOT defects (intentional):
  - `tools/ai-auto:22-23` — comment cites deleted `install-automation-template.sh` / `AI_AUTO_TEMPLATE_VERSION` as historical provenance for FRAMEWORK_PATHS. Accurate, no live ref.
  - `verify-machinery.sh:5842/6319/6375` — `ai-auto-init` appears only as a STALE symlink fixture; the test asserts `install-global-files.sh` REPOINTS a legacy `aiinit` link at `tools/ai-auto`. Required to test migration.

## R5 review_git()/single-source scrub — no leftover
- `hooks/git-scrub.sh` is the single source; all 4 sites SOURCE it (launcher tools/ai-auto:19, hooks/pre-commit:18, hooks/post-commit:15, baked shim ai-auto:164). No inline denylist copy remains. GIT_TRACE*/GIT_TEMPLATE_DIR additions present.
- `review_git()` provenance block is byte-identical across `review-gate.sh:23-160` and `summarize-ai-reviews.sh:804-...`, fenced with `# >>> review-provenance-shared: keep byte-identical >>>` and ENFORCED by a test (`scripts/test-review-summary.sh:1292`). Verified identical (138 lines). No old/unused copy or dead var.

## FINDING R6-1 (LOW — verbosity/minimality)
`scripts/review-gate.sh:23-160` + `scripts/summarize-ai-reviews.sh:804-941` carry a 138-line byte-identical provenance block kept in sync by hand + a test guard. Under the "shortest code" mandate this is extractable: both scripts already source helpers via `$AH` (review-gate.sh:19 `. "$AH/session-lock.sh"`, and both source `$AH/hooks/git-scrub.sh`). Shorter form: hoist the block to `scripts/review-provenance.sh` and `. "$AH/review-provenance.sh"` in each — deletes ~138 duplicated lines + the byte-identity test, single source of truth. Intentional + guarded today, so not a correctness defect; purely a minimality reduction.

## Docs truthfulness — CLEAN
- `NEW_PROJECT_GUIDE.md` literal `ai-auto setup [/path]` flow matches verified e2e behavior (zero vendored files, .omx exclude, hook shims, verify-project seam, self-host/staged-non-deletion aborts).
- `GLOBAL_TOOLS.md`/`README.md` `aiinit` refs accurately described as a LEGACY symlink kept pointed at `tools/ai-auto` (matches install-global repair test). No stale copy-model / aiinit-creates instructions survive.

## SPEC.v3 vs code — in sync
- git-scrub single-source + GIT_TRACE*/GIT_TEMPLATE_DIR (§ line 145-148), review_git call-site flags (§151), self-host guard via verify-machinery.sh+tools/ai-auto markers (ai-auto:82-83), verify.sh engine-aware default scope (`-ef` toplevel, full=machinery+product / product=verify-project seam, verify.sh:18/70-74) all match. No stale claim.

## Suite — GREEN
`python3 -m pytest tests/` → 227 passed, 1 skipped (framework suite green). `tests/test_app.py` (10 sample-flask-app tests) fails COLLECTION only because `flask` is not installed in this env (environmental, not a regression); 227+10 = baseline 237/1.
