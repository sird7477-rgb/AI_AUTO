# Defense R5 — Minimality + Maintainability (RED TEAM)

Branch feat/global-toolize, HEAD 775a081. Read-only audit. Lens: "shortest code wins"; drift = hole.

## Verdict: DEFECTS 2 (highest MED). No HIGH (no live security drift, e2e DONE proven, suite green).

---

## Suite (baseline — both GREEN)
- `bash scripts/verify-machinery.sh` → VMEXIT=0 (Summary: 30 passed, 27 warnings, 0 failed).
- `.venv/bin/python -m pytest -q` → **237 passed, 1 skipped**. (NOTE: a bare `python3 -m pytest`
  errors — system python lacks `flask`; the suite is venv-scoped. Not a defect, but the 237/1
  baseline only reproduces under `.venv`.)

## §14 DONE e2e — PROVEN
Throwaway repo vendoring 5 pristine framework files (AGENTS.md, docs/WORKFLOW.md,
scripts/{review-gate,verify,doc-budget}.sh) → `ai-auto setup` staged all 5 for `git rm`,
0 kept → commit → `git ls-files` = **only `app.py`** (ZERO committed framework files). Shims
baked with absolute engine path + scrub block; `.omx/` excluded. `ai-auto gate` dispatched to
the GLOBAL `review-gate.sh`; it fail-closed exit 1 because the de-polluted project has no
`scripts/verify-project.sh` — that is the intended C4/F4 behavior (missing real verification is
visible, not a silent green), not a defect.

## DENYLIST DRIFT (priority) — byte-identical TODAY
Extracted all 4 literal lists and diffed (heredoc-normalized the baked shim): launcher top
(tools/ai-auto:23-29), generated shim (tools/ai-auto:172-178), hooks/pre-commit:19-25,
hooks/post-commit:14-20 → **ALL 4 BYTE-IDENTICAL** (same 22 vars). No security hole right now.
verify-machinery.sh references the vars only in *behavioral* RCE tests (inject malicious
GIT_EXTERNAL_DIFF / core.hooksPath / core.fsmonitor, assert no PWNED file) — NOT a 5th literal
copy, so it cannot itself drift. Good.

---

## F1 (MED — maintainability trap): 4 hand-maintained scrub copies, NO byte-identity guard
- Where: tools/ai-auto:23-29 (= source of the :172-178 generated shim), hooks/pre-commit:19-25,
  hooks/post-commit:14-20. Plus ~24 lines of near-duplicate justification prose across the sites.
- Risk: the "kept BYTE-IDENTICAL; do not let it drift" invariant is enforced by COMMENT ONLY. The
  behavioral tests exercise only 3 representative vars (GIT_EXTERNAL_DIFF, core.hooksPath via
  GIT_CONFIG_*, core.fsmonitor). Drop/typo of any OTHER var in ONE copy (e.g. remove
  GIT_PROXY_COMMAND from post-commit only) → suite stays GREEN, one path silently scrubs less.
  Latent security hole the moment the lists diverge. R1-R4 grew the list from 3→22 vars across 4
  sites; the next growth is the likely divergence point.
- Shortest correct fix: single source of truth `hooks/scrub.sh` containing the `unset … / for
  _gcv …` block + the rationale comment ONCE. The two engine hooks (which ALWAYS run through the
  engine, so $AI_AUTO_HOME/hooks/scrub.sh is guaranteed present) and the launcher each resolve
  AI_AUTO_HOME first (they already do) then `. "$AI_AUTO_HOME/hooks/scrub.sh"`. The baked SHIM
  keeps an inline copy ONLY because it must scrub even if the engine is later moved/unreachable —
  but generate it: have `ai-auto setup` inline `hooks/scrub.sh`'s contents into the heredoc at
  setup time instead of a hand-written literal. Net: 1 maintained list, 0 hand-copied duplicates,
  ~30 lines of duplicated list+prose deleted. (If de-dup is judged not worth it, the minimum is a
  verify-machinery assertion that the 4 extracted blocks are byte-identical — converts a silent
  drift into a RED test.)

## F2 (LOW — SPEC vs code drift): SPEC.v3 §4/§9 PATH + unset lines are stale
- Where: .globalize-work/SPEC.v3.md:52 and :138 show `PATH="$AI_AUTO_HOME/scripts:$PATH"`; the
  M1 fix in code prepends BOTH dirs: `…/scripts:$AI_AUTO_HOME/tools:$PATH` (tools/ai-auto:10,188;
  hooks/pre-commit:9; hooks/post-commit:8; install-global-files.sh). SPEC §9:136 also still shows
  the shim unsetting only 3 vars ("worktree safety (v2, unchanged)") while the live shim unsets
  22. Design-doc only (not code), hence LOW, but it misrepresents the current guard/scrub.
- Fix: update the two SPEC snippets to `…/scripts:$AI_AUTO_HOME/tools:$PATH` and note the shim
  now scrubs the full canonical denylist.

---

## Checked CLEAN
- DEAD CODE: grep of active code/tests/docs (scripts,tools,hooks,tests,docs,README,AGENTS) for
  install-automation-template / check-template-version / refresh-guidance-baseline /
  ai-auto-template-status / ai-template-refresh / AI_AUTO_TEMPLATE_VERSION /
  check_template_staleness / template-version-gate / guidance-baseline.sha256 / template-manifest /
  templates/automation-base / test_template_global_contracts → **0 live references**. Remaining
  hits are all in historical `plans/*.md` (archival, legitimate) and two provenance COMMENTS in
  tools/ai-auto:32-33 (explaining where FRAMEWORK_PATHS came from — intentional, not dead code).
- BLOAT R1-R4: `install-global-files.sh` is a NET DELETION (-83/+… ; drift-notice codex block
  removed cleanly). verify.sh case dispatch, hooks, launcher are tight; no verbose construct with
  a materially shorter form found beyond F1.
- verify-machinery fixtures: the R3/R4 RCE fixtures (core.hooksPath, core.fsmonitor,
  GIT_EXTERNAL_DIFF gate+shim) are distinct scenarios, no duplicate fixture.
