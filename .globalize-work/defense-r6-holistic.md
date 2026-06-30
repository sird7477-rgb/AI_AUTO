# Defense R6 — HOLISTIC / INTEGRATION + SUITE-INTEGRITY lens (red)

Target: feat/global-toolize @ b9a480e. Read-only. Full lifecycle exercised on real temp
git repos; baseline re-run fresh; ~25 globalize fixtures audited for validity.

## Verdict: DEFECTS 1 (highest MED). Suite integrity CLEAN; baseline holds.

---

## GREEN baseline (re-run fresh, this round)
- `.venv/bin/python -m pytest -q -rs` → **237 passed, 1 skipped (93s)**. The 1 skip is
  `tests/test_todo_report.py:112` — the documented todo-report quarantine, reason string
  matches BASELINE.md.
- `bash scripts/verify-machinery.sh` → **VMEXIT=0**; embedded pytest 237/1 (matches
  standalone); doctor 30 pass/0 fail; doctor --home 101 pass/0 fail/6 skip. Failure-pattern
  grep over the log = only test names / "0 failed" / expected-fail prose. No real failure.
- All R5-touched files `bash -n` clean; `hooks/git-scrub.sh` sources cleanly under `set -e`.

## Suite-integrity audit (the emphasis) — CLEAN
- **1 skip is legitimate, not masking a globalize regression.** Live active backlog items =
  `ST-P1-72,73,75,76,77` (74 closed). The ONLY globalize commit touching the backlog /
  todo-report / its test is `5179df6` (the P2.5 quarantine that ADDS the skip + advisory
  NOTE); `git diff 6e90184..HEAD` shows ZERO content change to those ST-P1-7x items. So the
  active items are pre-existing on the base, not globalize-introduced. `.globalize-work/
  BASELINE.md` quarantine #3/#4 still valid; not made worse.
- **No vacuous fixtures found.** Spot-audited the highest-value security/seam fixtures —
  each carries a POSITIVE CONTROL or a structural guarantee proving the negative assertion
  is real: R5-1 provenance-RCE (control fires EXT+CLEAN via bare git), F1 single-source
  (behavioral scrub of GIT_TRACE/TEMPLATE_DIR + "no inline copy" assertion), R3-3
  config-injection (CTRL marker), R4-1 GIT_EXTERNAL_DIFF (CTRL_XDIFF), D2 derived seam
  (real pre-commit+verify.sh+session-lock copied in, fail-closed leg + marker leg). The two
  provenance blocks in review-gate.sh / summarize-ai-reviews.sh are byte-identical (138
  lines) → R5-1 hardening single-sourced, no drift.

## Lifecycle exercised GREEN (real temp repos, live engine as AI_AUTO_HOME)
- DERIVED setup → stages pristine AGENTS.md deletion + bakes scrubbing shims.
- DERIVED pre-commit seam: no verify-project.sh → **fail-closed** ("NOTHING was verified",
  commit blocked); failing verify-project.sh → **blocks** commit; passing → commit proceeds
  and runs verify-project.sh. `ai-auto verify` mirrors (rc 1/0). `ai-auto doctor` rc 0.
- Engine self-host: `AI_AUTO_HOME -ef repo_root` TRUE → machinery branch; staged-framework
  grep predicate matches `scripts/`+`hooks/`. No verdict change from review_git (post-commit
  handshake uses verdict-file mtime, not the provenance hash). Self-host NOT regressed.
- Idempotent re-run ("Nothing to remove, already migrated"); legacy copy-model hook
  UPGRADED to shim; genuinely-custom hook PRESERVED + warned; F3 dirty-index guard aborts
  cleanly on staged non-deletions.

---

## DEFECT

### H1 (MED) — R5 derived pre-commit seam BLOCKS the documented adoption commit (onboarding contradiction)
- One-line: `ai-auto setup` prints, as the next step, `git commit -m 'adopt global AI_AUTO
  mode: drop vendored framework files'`, but the pre-commit shim it just installed
  fail-closes that very commit because a freshly-adopted project has no
  `scripts/verify-project.sh` yet → the first commit of the onboarding flow cannot be made.
- Repro (verbatim, reproduced):
  ```
  mkdir onboard && cd onboard && git init -q && git config user.email t@e.x && git config user.name T
  cp <engine>/AGENTS.md AGENTS.md; echo x>app.txt; git add -A; git commit -qm base
  <engine>/tools/ai-auto setup .            # prints "Review, then commit the de-pollution: git commit -m 'adopt...'"
  git commit -m 'adopt global AI_AUTO mode: drop vendored framework files'
  # -> [verify] no project verification: scripts/verify-project.sh is absent — NOTHING was verified
  # -> exit 1; AGENTS.md deletion NEVER committed (git log still at base)
  ```
- Why R5-specific: pre-R5 the pre-commit ran pytest, and a runner-less fresh project hit the
  `no pytest available … Not blocking` warn-and-defer (exit 0), so the adoption commit went
  through. R5's derived branch (`hooks/pre-commit:66-72`) replaced that with a fail-closed
  `verify.sh product` run, which has no warn-and-defer for "no verify-project.sh yet".
- Why the suite missed it: the D2 fixture (`verify-machinery.sh:7115`) exercises the seam in
  ISOLATION (fail-closed leg + verify-project.sh-present leg) but never runs the
  setup → printed-adoption-commit flow, so the contradiction is untested.
- Severity: MED. Fail-closed (never false-green), and workaroundable (`--no-verify`, which
  then trips the post-commit "may have bypassed review-gate" nag; or pre-author
  verify-project.sh). But it is a broken/self-contradictory documented lifecycle that EVERY
  new adopter hits on their first commit, with setup actively printing the failing command.
- File: `hooks/pre-commit:66-72` (derived fail-closed branch) × `tools/ai-auto:246-251`
  (setup's printed adoption-commit instruction).
- Fix (pick one, no code-correctness change to the seam): (a) in `ai_auto_setup`'s report,
  warn that commits are blocked until `scripts/verify-project.sh` exists and suggest the
  adoption commit run with `--no-verify` (or author verify-project.sh first); OR (b) extend
  the derived pre-commit's "absent verify-project.sh" message to name the file to create —
  pure UX, keeps fail-closed. Do NOT downgrade the seam to warn-and-defer (that re-opens the
  D2 silent-no-op). Add a fixture that runs setup → adoption commit and asserts a clear,
  documented outcome.

## Non-defects confirmed
- Cross-terminal `ai-auto verify` (term A) + `git commit` (term B) on one tree → commit
  blocked with session-lock contention (exit 75). Conservative-by-design concurrency guard,
  not a defect; no deadlock (single-threaded EXIT-trap release).
- Derived pre-commit now runs FULL verify-project.sh on every commit (no fast/full split for
  derived). Heavyweight but fail-closed and the deliberate D2 fix; usability tradeoff, not a
  broken lifecycle. (Folds into H1's UX surface.)
- BASELINE.md #3 prose says "238 passed, 1 skipped" while current is 237/1 — stale count in
  a doc (a test was consolidated post-R1); the quarantine itself is correct. Cosmetic.
</content>
</invoke>
