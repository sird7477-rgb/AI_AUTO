# Defense R7 — HOLISTIC / INTEGRATION + SUITE-INTEGRITY lens (red)

Target: feat/global-toolize @ 54d2b3e (R6 blue: collect-review-context git-harden sourcing,
derived pre-commit warn-and-allow onboarding, single git-harden.sh helper, conftest.py).
Read-only. Full lifecycle on real temp repos; suite integrity + fixture validity audited;
pytest x3, verify-machinery x2 for flakiness.

## Verdict: DEFECTS 1 (highest LOW). All HIGH/MED concerns CLEAN — no crash / wrong-verdict /
silent-skip / masking-or-vacuous-fixture / self-host-regression introduced by R6.

---

## GREEN baseline (re-run fresh, three times)
- `python -m pytest -q` x3 (default order; `-p no:randomly`; default again) → **237 passed,
  1 skipped** every run. The 1 skip = `test_todo_report.py:112` documented quarantine
  (active ST-P1-72..77 on base 6e90184), reason string matches BASELINE.md. No flakiness,
  no order-dependence.
- `bash scripts/verify-machinery.sh` x2 → **VMEXIT=0** both; embedded pytest 237/1 both;
  doctor 30 pass/0 fail; doctor --home 102 pass/0 fail/6 skip. Failure-pattern grep over the
  log = only test-name prose ("failed_*: pass") and "0 failed". No real failure masked by
  the `echo $?`-style VMEXIT (per known gotcha). Identical across both runs.

## Lifecycle exercised GREEN (real temp repo, live engine as AI_AUTO_HOME)
- `ai-auto setup` → de-pollutes (AGENTS.md + review-gate.sh staged for deletion), bakes hook
  shims. **Setup-printed adoption commit now SUCCEEDS** (R6 H1 fix verified): pre-commit
  warns-and-allows when verify-project.sh is absent, commit lands.
- Edit→commit: pre-commit prints "scripts/verify-project.sh absent — … NOT gated" and ALLOWS
  (disclosed, not a silent no-op). PASSING verify-project.sh → hook RUNS it (commit lands).
  FAILING verify-project.sh → hook BLOCKS the commit. All three legs correct.
- `ai-auto verify`: PASSING → rc 0; **absent verify-project.sh → fail-closed rc 1**
  ("NOTHING was verified"). The intended R6 asymmetry holds: the commit HOOK warn-and-allows
  on absence, the explicit `verify` QUERY stays fail-closed. `ai-auto doctor` → rc 0.
- Gate's first git work (collect-review-context.sh, now sourcing git-harden.sh) produces a
  correct context file with the live diff captured; git-harden sources cleanly via sibling in
  a real engine layout (no env var) AND via AI_AUTO_GIT_HARDEN_SH override. No crash/regression.
  (Note: full `ai-auto gate` blocks on the AI-reviewer subprocess in this reviewer-less env —
  environmental, NOT an R6 surface; the R6-touched collector path is green.)
- Re-adopt idempotent ("Nothing to remove; already migrated. exit 0"). Pre-existing custom
  odoo pre-push hook left untouched (coexistence preserved).

## Suite-integrity audit (the emphasis) — CLEAN
- **conftest.py does NOT mask and does NOT alter collection unsafely.** It only does
  `os.environ.setdefault("AI_AUTO_GIT_HARDEN_SH", <engine>/scripts/git-harden.sh)` at import
  — no collection hooks, no skips, no autouse fixtures. Audited the shadowing risk: NO python
  test creates/copies its own git-harden.sh (only conftest references it), so the override
  cannot shadow a test-local copy. The bypassed default (sibling-resolution) path IS covered
  by verify-machinery (fixtures copy git-harden.sh into scripts/ and run WITHOUT the override).
  Confirmed independently that a truly-missing git-harden.sh makes the collector **fail LOUDLY
  (rc 1, "No such file or directory")**, not silently run un-hardened — so the override can
  only hide a *present-but-broken-default-expression*, which verify-machinery still exercises.
- **R6-1 fixture positive control is GENUINE — independently reproduced.** Built the poisoned
  repo (`.gitattributes` diff=evil/evilt + `.git/config` external-diff/textconv drivers):
  the real hardened collector fired NO markers (EXT=no, TXT=no); the stripped control
  (review_git→git, flags removed) fired BOTH (EXT=YES, TXT=YES). The negative assertion is
  not vacuous; the payload provably fires when unhardened.
- **D2/H1 fixture has real positive controls**: asserts warn+ALLOW leg (disclosure strings +
  exit 0 + absence of the old "NOTHING was verified"), the actual setup-printed adoption
  commit succeeding through the installed hook, the present-verify-project.sh RUN leg, and the
  FAILING-verify-project.sh BLOCK leg. Single-source assertion proves review_git() is defined
  in exactly one file and all three consumers source it.
- All 14 verify-machinery fixtures that copy a git-harden-sourcing script (review-gate /
  collect-review-context / summarize-ai-reviews) were correctly paired with a git-harden.sh
  copy or AI_AUTO_GIT_HARDEN_SH override — none fail-closes on a missing sibling. test-review-
  summary.sh exports the override for the process-substitution standalone block.
- Engine self-host NOT regressed: the git-harden.sh sourcing + conftest.py left verify-machinery
  (VMEXIT=0) and pytest (237/1) unchanged; no verdict change (provenance handshake unaffected).

---

## FINDING

### R7-1 (LOW, latent) — git-harden.sh is not a managed framework path; the scripts that hard-depend on it are
- One-line: review-gate.sh / collect-review-context.sh / summarize-ai-reviews.sh now hard-
  source a *sibling* `scripts/git-harden.sh`, but git-harden.sh is NOT in `FRAMEWORK_PATHS`
  (tools/ai-auto:24-47, the de-pollution managed set) and there is no forward-vendoring
  manifest on this branch that would ship it.
- Why inert TODAY: there is NO live path that copies those three scripts to a non-engine
  location (grep for cp/rsync/install/ln of them outside verify-machinery fixtures = empty);
  the globalize model runs them in-place from the engine, where git-harden.sh is always the
  sibling. So no current project ever lacks the sibling, and `ai-auto setup` has nothing to
  de-pollute that depends on it.
- Latent risk (forward-consistency only): if a vendoring/copy path is ever reintroduced, or a
  legacy project carries an R6-era review-gate.sh without git-harden.sh, the gate/pre-commit
  would **fail-closed** on the missing sibling (rc 1 — loud, never false-green); conversely a
  project that vendored git-harden.sh would have it left un-de-polluted (stray) by setup since
  it is off the managed list.
- Severity: LOW. Zero current lifecycle impact; fail-closed (not masking/false-green) if ever
  hit. A maintainability/forward-consistency gap, not a broken lifecycle or self-host regression.
- File: `tools/ai-auto:24-47` (FRAMEWORK_PATHS) vs `scripts/{review-gate,collect-review-context,
  summarize-ai-reviews}.sh` (sibling source of `scripts/git-harden.sh`).
- Fix: add `scripts/git-harden.sh` to FRAMEWORK_PATHS so setup treats it as a managed (de-
  pollutable) framework file co-equal with its dependents — keeps the de-pollution list a
  superset of the framework's own dependency graph. (Pure consistency; no behavior change on
  the current branch.)

## Non-defects confirmed
- `ai-auto gate` blocking in a reviewer-less temp env = AI-reviewer subprocess wait, not an R6
  regression; the R6-touched collector path is green.
- pre-commit warn-and-allow vs `verify` query fail-close asymmetry = deliberate R6 design,
  verified correct on both sides.
- conftest.py process-global env var = acceptable; setdefault yields to an externally-exported
  value, no test asserts its absence.
</content>
</invoke>
