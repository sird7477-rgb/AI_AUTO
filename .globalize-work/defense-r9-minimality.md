# Defense R9 — RED TEAM minimality + GOAL audit (HEAD 1ae7dd7)

Net change `git diff 6e90184..HEAD`: 151 files, +5939 / −31484 (template copy-model tree
`templates/automation-base/` fully deleted; copy/version-gate machinery removed). Suite GREEN.

## Verdict
- Suite: **237 passed, 1 skipped** via `.venv/bin/python -m pytest -q` (72s). GREEN.
- GOAL §13/§14 e2e: **MET = Y** (all 7 assertions pass on a throwaway already-patched project).
- Dead code: **none** (every grepped P1–R8 deletion has no surviving live ref).
- Docs/SPEC.v3: **synced**, no stale instruction.
- Minimality: 1 LOW comment-provenance nit; no R8 leftovers.

## GOAL e2e (throwaway patched project → `ai-auto setup`)
1. Zero committed framework files — PASS (AGENTS.md/WORKFLOW.md/review-gate.sh/verify.sh git-rm'd; customized DOMAIN_PACKS.md correctly KEPT).
2. .omx gitignored — PASS (`.omx/` appended to .git/info/exclude).
3. Baked-path shims — PASS (pre/post-commit carry `AI_AUTO shim` + `AI_AUTO_HOME="/root/workspace/ai-lab-globalize"`; legacy full-body hook UPGRADED to shim).
4. Gate runs from global engine — PASS (`gate) exec "$AI_AUTO_HOME/scripts/review-gate.sh"`; absolute path, project copy removed → no shadow).
5. Idempotent — PASS (re-run: "Nothing to remove… exit 0").
6. Self-host abort — PASS (setup on engine root: "ABORT — target is the AI_AUTO engine repo").
7. Adoption commit succeeds — PASS (commit OK; post-commit advisory warning fired = shim live).

## Dead-code sweep (CLEAN)
- `templates/automation-base` refs in kept tree: none.
- Deleted tools/scripts (`ai-auto-init`, `ai-template-refresh`, `ai-auto-template-status`, `install-automation-template`, `check-template-version`, `refresh-guidance-baseline`, `AI_AUTO_TEMPLATE_VERSION/STALENESS`, `template-version-gate`, `test_template_global_contracts`): no live refs in scripts/tools/hooks/tests/docs.
  - `verify-machinery.sh:5850/6327/6383` symlink `old-checkout/tools/ai-auto-init` — INTENTIONAL stale-link fixture; test asserts install-global REPOINTS `aiinit`→`tools/ai-auto`. Not dead.
- `tests/conftest.py` `AI_AUTO_GIT_HARDEN_SH` override — consumed by collect-review-context.sh:30 / review-gate.sh:41 / summarize-ai-reviews.sh:822. Not dead.

## R8-edit residue check (CLEAN)
- `hooks/git-scrub.sh:44-53` — comment now correctly states `diff.external` is NOT pinned (R8-H8-1); env exports EXACTLY one key (core.fsmonitor=''). No stale "diff.external=''" pin.
- `git-scrub.sh`/`verify-machinery.sh` mentions of `diff.external=''` are in explanatory comments + the R8 regression fixtures (verify-machinery.sh:7186-7260, sourced-chokepoint integration) — all backed by real call-site usage (`-c diff.external= --no-ext-diff` in review_git; `--no-ext-diff --no-textconv --no-filters` at collect-review-context.sh:1400, review-gate.sh:57, summarize:838). No leftover.
- No unused var; lock-fd close (ai-auto:188-194) is the live R5-4 fix.

## Findings
1. **LOW — tools/ai-auto:24-41** — comment claims `FRAMEWORK_PATHS` = "MANAGED_PATHS from the deleted install-automation-template.sh", but `scripts/git-harden.sh` (line 41) is a NET-NEW engine file that the old copy model NEVER vendored, so no old-model project can carry it; the entry is forward-defensive but provenance-imprecise. Fix: amend the parenthetical (note git-harden.sh as an engine-owned addition) OR drop the line. Functionally harmless (a pristine-identical copy would still be correctly de-polluted; a differing one KEPT).

## Non-findings (audited, intentional — NOT defects)
- `review_git` (git-harden.sh:18) re-pins `-c core.fsmonitor=` although git-scrub.sh exports it empty — defense-in-depth: review_git is sourced standalone by tests WITHOUT git-scrub. Not redundant.
- pre-commit existence-check of verify-project.sh duplicates verify.sh:run_product's fail-closed branch — different surfaces (commit-gate onboarding warn vs explicit `ai-auto verify` query). Not redundant.
