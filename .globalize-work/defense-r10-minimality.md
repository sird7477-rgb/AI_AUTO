# Defense R10 — MINIMALITY + GOAL lens (RED TEAM, HEAD 5494d4c)

Read-only audit. Suite GREEN: **237 passed, 1 skipped** via `.venv` (86s).

## Verdict: DEFECTS: 1 (highest LOW). GOAL met = YES.

---

## GOAL §13/§14 e2e — DEFINITIVE PASS (manual, throwaway patched project)
Vendored AGENTS.md + docs/WORKFLOW.md + scripts/review-gate.sh + scripts/verify.sh (pristine)
+ docs/DOMAIN_PACKS.md (locally edited) + .omx/, then `ai-auto setup`:
1. Zero committed framework files — PASS (4 pristine `git rm`'d; only app.py + customized DOMAIN_PACKS.md remain).
2. .omx gitignored — PASS (`git check-ignore` hits via info/exclude).
3. Baked shims — PASS (pre/post-commit carry `AI_AUTO shim` + literal baked `AI_AUTO_HOME=/root/workspace/ai-lab-globalize`).
4. Gate from global engine — PASS (no local review-gate.sh; `ai-auto gate` execs engine).
5. Idempotent re-run — PASS (`Nothing to remove… exit 0`, worktree clean).
6. Self-host abort — PASS (setup on engine repo → ABORT exit 1, no mutation).
7. Adoption commit succeeds — PASS (commit exit 0; shims actually fired pre+post-commit).
Customized/edited framework file correctly KEPT, never deleted.

## DEAD CODE — CLEAN
Tree-wide grep for refs to every P1–R9b deletion (install-automation-template, check-template-version,
refresh-guidance-baseline, ai-auto-init, ai-auto-template-status, ai-template-refresh,
template-version-gate, AI_AUTO_TEMPLATE_VERSION/STALENESS, automation-base, test_template_global_contracts):
- No refs in active tools/scripts/hooks/tests/.github or active docs (GLOBAL_TOOLS/NEW_PROJECT_GUIDE/README/AGENTS).
- `tools/ai-auto:22-23` — explanatory provenance comment only (not a live ref).
- `verify-machinery.sh:5850/6327/6383` — INTENTIONAL: fixture seeds a STALE `aiinit→ai-auto-init`
  symlink and asserts install-global-files.sh REPOINTS it to `tools/ai-auto` (install-global-files.sh:1063).
  Tested at :5873. Not dead.
- Remaining hits are historical `plans/*` design docs + `.globalize-work/*` notes (records, not code).

## DOCS + SPEC.v3 — truthful, in sync
- SPEC.v3 §2 references to deleted paths are the DELETE-set inventory (documenting removals) — truthful.
- README/AGENTS/GLOBAL_TOOLS/NEW_PROJECT_GUIDE describe global model ("no vendored files",
  "de-pollutes old copy model"); no instruction tells a user to run a deleted tool. No stale instruction.
- F4 self-host guard in code (ai-auto:84 = `verify-machinery.sh` AND `tools/ai-auto`) matches SPEC.v3 §-F4.

## MINIMALITY of the security hardening — near-minimal; the two prompt candidates are NOT removable
Central wrapper `review_git()` single-sourced in scripts/git-harden.sh (verified single-def by
R6-1 guard); literal `--attr-source=` only at the domain-pack validator sites + run-ai-reviews
name-only sites; ONE uniform tree-wide drift-guard (verify-machinery R9-DRIFT, rules 1/2/3).

- **`--no-ext-diff` — KEEP (proven NOT redundant).** Closes CONFIG-level `diff.external` (not
  attribute-driven); `--attr-source=<empty-tree>` only disarms ATTRIBUTE-bound drivers, so it does
  not cover `diff.external`. Distinct vector.
- **`--no-textconv` — KEEP (proven NOT cleanly redundant).** Although `--attr-source=<empty-tree>`
  disarms attribute-bound textconv on the wrapper's worktree/cached/range/show calls, it is
  LOAD-BEARING at `collect-review-context.sh:1402` — the `--no-index` content read deliberately gets
  NO `--attr-source` (case arm in git-harden.sh:38-39), only `--no-filters`, and `--no-filters` does
  NOT disable textconv. Also uniformly required by drift-guard rule 1/2. Removal would break the
  --no-index defense AND the guard contract — net more complexity, not less.

## DEFECT (LOW) — marginal redundancy in the wrapper
**`-c diff.external=`** at `scripts/git-harden.sh:39` and `:41` closes no DISTINCT vector.
- Config-level `diff.external` RCE fires only on PATCH-producing diffs; every patch-producing
  `review_git` call already carries `--no-ext-diff` (enforced by drift-guard rule 2), which fully
  disables external diff regardless of config. Non-patch calls (`--name-only/--stat/--quiet`) never
  invoke external diff. So the flag is redundant with the call-site `--no-ext-diff`.
- Minimal form: drop `-c diff.external=` from both case arms.
- CAVEAT (why LOW, not MED): it is a deliberate fail-closed belt — if a future `review_git` patch
  call is added WITHOUT `--no-ext-diff` (before the drift-guard's next run catches it), this flag
  converts an RCE into a loud `fatal: external diff died` (R8's documented behavior) rather than
  arbitrary code-exec. It changes a failure-MODE, not a vector. Keep-as-defense-in-depth is
  defensible; under the strict "shortest code" mandate it is removable (1 token, both arms).

No HIGH/MED. Hardening is otherwise minimal and the 9-round accretion left no other duplicate flag.
