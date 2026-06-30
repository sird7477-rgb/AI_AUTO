# Defense R4 — Holistic / Integration hunt (RED TEAM)

Worktree `/root/workspace/ai-lab-globalize`, branch `feat/global-toolize`, HEAD `58bcb42`.
Lens: whole global-mode lifecycle; look for where the R3 fixes interact badly or a new
lifecycle path breaks. Read-only; exercised real flows in temp git projects.

## Lifecycle exercised (all PASS)
- Built a derived project that vendored pristine framework copies (`AGENTS.md`,
  `docs/WORKFLOW.md`, `scripts/review-gate.sh`, `scripts/verify.sh`) + own code + tests +
  `scripts/verify-project.sh`.
- `ai-auto setup` → de-polluted the 4 pristine copies (staged for deletion), installed
  baked-path `pre-commit`/`post-commit` shims, `.omx/` excluded. **OK.**
- broken commit → pre-commit shim → engine pre-commit ran project pytest, **fail-closed**
  (blocked the import-error commit); fixed commit passed; post-commit warned (no recent
  proceed verdict). **OK** — worktree-safe, GIT_* scrubbed.
- `ai-auto verify` (derived) → **product scope**, delegated to `./scripts/verify-project.sh`,
  never ran engine machinery. Removing the hook → **fail-closed exit 1** ("NOTHING was
  verified"). **OK.**
- `ai-auto doctor` (--project) → clean (handles globalized state: absent framework
  `verify.sh` is a WARN not a FAIL; present `verify-project.sh` → PASS). `ai-auto doctor
  --home` runs (its "failed" count here is environmental: ~/bin links point at the installed
  checkout, not this worktree). **OK.**
- `ai-auto gate` (derived) → ran verify(product, passed) → collect-review-context (wrote
  `.omx/review-context/...`, D6 base+overlay fine with project `AGENTS.md` de-polluted) →
  run-ai-reviews (Claude ran to a result via absolute paths) → no pwd/path crash on the
  zero-framework-file project. (Stopped only on the external codex principal-subagent runner
  not being available — environmental, not a defect.) **OK.**
- Odoo pack coexistence: pre-installed the pack `pre-push` hook, ran `ai-auto setup` →
  pre-push **byte-identical after** (md5 unchanged); pre-commit/post-commit shims installed
  alongside. setup only touches pre-commit/post-commit. **OK.**
- Re-adopt / stale-shim upgrade: planted an OLD shim (`AI_AUTO_HOME=/old/stale/...`, no
  GIT_CONFIG scrub) → `ai-auto setup` overwrote it with the current baked path + scrub.
  (First attempt aborted on a dirty index — F3 guard working as designed; clean re-run
  refreshed.) **OK.**
- Engine self-host scope: from engine root `dirname($AH) -ef pwd` → **scope=full**; gate
  passes `AI_AUTO_VERIFY_SCOPE=product` explicitly and verify.sh honors it (default only
  computed when unset) → no R3 regression to the engine's own gate. **OK.**
- Baseline: `python3 -m pytest -q` portion of verify-machinery → **237 passed, 1 skipped**
  (GREEN 237/1). Full bash machinery suite green up to the "knowledge note helper"
  integration test, which hangs on a `sleep`-based poll in this sandbox (knowledge/obsidian
  helper reaching an unavailable external dep) — environmental, no FAIL line, not part of the
  globalize feature surface.

## Findings

### L1 (LOW) — review machinery still names `scripts/verify.sh`, which `ai-auto setup` deletes
`ai-auto setup` de-pollutes `scripts/verify.sh` out of a globalized project (the real
entrypoint becomes `ai-auto verify` → global verify.sh → project `verify-project.sh`). But
the live review flow still tells the operator/AI reviewer to run that now-deleted file:
- `scripts/collect-review-context.sh:269` — `local checks=("./scripts/verify.sh")` →
  emitted at `:402` as `- required checks: ./scripts/verify.sh, docker smoke` into the
  review context that reviewers consume. Observed verbatim in the live derived-project gate
  run.
- `scripts/collect-review-context.sh:1414` — "Before completion, run ./scripts/verify.sh".
- `scripts/review-gate.sh:242,248,256` — blocked-verdict text: "verify.sh failed", "Fix
  verify.sh".
Impact: advisory text only; the gate actually invokes the global verify.sh via `$AH`, so the
flow is unaffected — but the guidance points a human/reviewer at a file that no longer exists
in a globalized project. Repro: in the derived project above, `ai-auto gate` and read
`.omx/review-context/latest-review-context.md` ("required checks: ./scripts/verify.sh").
Fix: make the messages mode-aware — say `ai-auto verify` (or `scripts/verify-project.sh`)
when `scripts/verify.sh` is absent / when running in global mode.

### L2 (LOW) — `ai-auto verify`/`gate` from a non-root cwd or a secondary engine worktree silently drops to product scope
The R3 default-scope guard `[ -f "$AH/verify-machinery.sh" ] && [ "$(dirname "$AH") -ef
$(pwd)" ]` (scripts/verify.sh:14; mirrored at review-gate.sh:506 for the machinery fold)
keys "this is the engine self-host" off `dirname($AH) == pwd`. Consequences:
- `cd scripts && ai-auto verify` on the engine → scope=product → fail-closed needing
  `scripts/verify-project.sh` relative to the subdir (absent) instead of running machinery.
  Confirmed by replicating the guard from `scripts/`.
- Engine worktree B while the global `~/bin/ai-auto` resolves `$AH` to engine worktree A
  (`dirname($AH)`=A root ≠ pwd=B root) → `ai-auto verify` runs product-only; `ai-auto gate`
  skips the machinery fold (line 506 same guard) when committing framework changes in B.
Impact: scope REDUCTION, not a crash and not a silent green — product (`verify-project.sh`)
still runs / or fail-closes. Pre-R3 (`AI_AUTO_VERIFY_SCOPE=...:-full`) would have run
machinery here; this is the price of the R3 fix that stopped the derived-project exit-127
crash, and it is consistent with the pre-existing pre-commit self-host guard
(`hooks/pre-commit:56`). Using the worktree-local `./tools/ai-auto` (so `$AH`=that worktree)
restores scope=full. Fix (optional): treat "pwd is inside a checkout that itself has
`scripts/verify-machinery.sh` AND `tools/ai-auto`" (the engine-marker pair already used by
setup) as self-host, rather than requiring `$AH` to be that same checkout — would also fix
the subdir case.

## Verdict
No HIGH/MED defect: no broken lifecycle, no self-host regression, no pollution
re-introduced, no silently-skipped verification (the only scope-drop fails closed or runs
product). Two LOW cosmetic/edge findings (L1 text drift naming a de-polluted file; L2
scope-reduction off non-root/secondary-worktree cwd). Baseline GREEN (237/1).
