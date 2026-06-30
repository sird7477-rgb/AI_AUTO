# Defense R2 — RED TEAM: Engine correctness in global mode (post-R1 hardening)

Worktree: feat/global-toolize @ e29a5fe. Surface: ENGINE correctness in global mode +
the R1 engine/external-runner/machinery-fold fixes. Read-only on source; all repros in
throwaway temp projects + the engine repo itself.

## Verdict
CLEAN — no NEW defect; all attacked R1 fixes hold. Baseline GREEN
(`verify-machinery.sh` VMEXIT=0; `pytest -q` = 237 passed / 1 skipped). Two pre-existing
R1 LOWs persist unchanged (not new — see §C); they are cosmetic/defensible, not gate-
affecting.

## R1 fixes — attacked, all DEFEATED

### machinery-fold (review-gate.sh:505-506, pre-commit:49) — HOLDS, no regression
- Engine repo: from the engine root all four conjuncts are TRUE
  (`-f scripts/verify-machinery.sh` + `-f "$AH/verify-machinery.sh"` +
  `$(dirname "$AH") -ef .`), so the fold STILL runs when editing the real engine — no
  silent-skip regression. pre-commit's `$AI_AUTO_HOME -ef $repo_root` also TRUE in engine.
- Derived project: cwd ≠ engine root ⇒ `$(dirname "$AH") -ef .` is FALSE even when the
  derived project coincidentally ships its own `scripts/verify-machinery.sh` and edits
  `scripts/`. R1 finding #2 (engine harness triggered against a derived tree) is now
  blocked by the `-ef .` inode guard. Confirmed by direct condition eval in both trees.

### external runner (run-ai-reviews.sh:352-447) — HOLDS
- `REVIEW_EXECUTION_MODE=external` from a globalized zero-`scripts/` project generates
  `.omx/external-review/run-reviewers-*.sh` whose engine calls are the ABSOLUTE baked
  `${RUN_AI_REVIEWS_SCRIPT_DIR}/run-ai-reviews.sh` and `…/summarize-ai-reviews.sh`
  (= /root/workspace/ai-lab-globalize/scripts/…, verified to exist + be executable).
  `repo_root` = `script_dir/../..` (project root). The ONLY `./scripts/` text left in the
  runner is a comment (line 7). No pwd-relative survivor in the runner/summarize chain.
  R1 finding #1 (runner died on `./scripts/...`) is fixed.

### verify seam (verify.sh:42-71) — fail-closed, no silent green
- Derived project, no `scripts/verify-project.sh` ⇒ `run_product` exits 1 ("NOTHING was
  verified"). Present + `-x` ⇒ delegates and passes. A non-executable hook also fails
  closed (`-x` test).
- No skip-path bypasses verify: review-gate runs verify at :484 BEFORE both the docs-only
  skip (:600) and the provenance exact-match skip (:614) — both only skip the AI panel
  (explicit comment :610-611). Could not sneak a green no-op. Gate env-scrub (`env -u …`
  at :486-494 and :515-526) intact.

### D6 base+overlay feed (collect-review-context.sh:185-211) — robust on all inputs
Tested in a derived temp project, all exit 0, no crash, correct feed:
- missing project AGENTS.md, base present → base-only, fed once.
- project AGENTS.md a SYMLINK to base → `-ef` dedup ⇒ fed ONCE (no double-feed).
- base ALSO missing (engine without AGENTS.md) → neither emitted, no crash.
- AI_AUTO_HOME unset → irrelevant (path derived from `readlink -f "$0"`), exit 0.
- DANGLING AGENTS.md symlink → `! -e` true / `-f` false ⇒ base fed, project dropped, no crash.

### R1 finding #4 (template_parity_boundary residue) — REMOVED
`template_parity_boundary` / `template_version_updated` / `patch_notes_updated` /
`template_sync_check` no longer present in `scripts/*.py`. Cleaned up.

## NEW-surface sweeps
- `bash scripts/verify-machinery.sh` → VMEXIT=0 (machinery summaries: 0 failed).
- `python3 -m pytest -q` (.venv) → 237 passed, 1 skipped — matches baseline, no new failure.
- Deletion completeness: zero dangling refs in live `.sh/.py/.yml` to
  install-automation-template, check-template-version, refresh-guidance-baseline,
  ai-auto-template-status, ai-template-refresh, automation-base, template-manifest,
  guidance-baseline, template-version-gate, AI_AUTO_TEMPLATE_VERSION/STALENESS.
- Every engine-relative invocation (`$AH/…`, `$AI_AUTO_HOME/scripts/…`,
  `${RUN_AI_REVIEWS_SCRIPT_DIR}/…`) resolves to an existing sibling (14/14 OK).
- `ai-auto gate` end-to-end on a fresh derived temp project: runs verify → context (base
  AGENTS.md fed) → prompts → AI panel via absolute engine paths; no crash, no wrong
  verdict (run only times out on real AI-CLI latency, not a defect).
- `ai-auto doctor` on derived project: exit 0 (PASS), no crash.

## C. Pre-existing R1 LOWs that PERSIST (not new, not gate-affecting)
- R1 #3 — `ai-auto setup` `git rm`s a pristine AGENTS.md and seeds no overlay stub;
  globalized project ends with NO local AGENTS.md. collect degrades to base-only (verified),
  gate unaffected. Spec-literal deviation only.
- R1 #5 — `automation-doctor.sh --project` still WARNs on absent engine dirs; doctor exits
  0, so "project passes" holds. Cosmetic.
