# RED TEAM — DESIGN CERTIFICATION pass on SPEC v3 (feat/global-toolize, HEAD 6e90184)

Read-only audit of `.globalize-work/{SPEC.v3.md,DEFECT-MATRIX.md,IMPL-PLAN.md}` + v2 findings
(F1–F10), cross-checked against the LIVE tree by independent grep.

VERDICT: **NOT certified.** One HIGH integrity defect in the DELETE-set accounting (mandate items
2 + 5), plus one MED specification gap and LOW residuals. The C3 ripple and verify seam (mandate
items 1, 3) hold up.

---

## G1 — HIGH — DELETE of `templates/automation-base` makes TWO KEPT test files go RED; v3 deletes only one test file

IMPL-PLAN STEP 2 ("DELETE the apparatus's tests, SAME commit as STEP 1 — resolves D1") deletes
ONLY `tests/test_template_global_contracts.py` + the `verify-machinery.sh` retired blocks. Its
grep check (STEP 2, line 23) scans **`scripts/verify-machinery.sh` only** — never the `tests/` dir.
DEFECT-MATRIX D1 claims residual NONE ("delete the test blocks + unit test in the SAME commit…
IMPL greps to zero"). That accounting is INCOMPLETE.

`scripts/verify-machinery.sh:7` runs `pytest -q` (the whole suite) — this IS the engine self-test
folded into the gate (`review-gate.sh:604-624`) and `verify.sh full|machinery`. Two KEPT tests
read the to-be-deleted tree from disk and will raise `FileNotFoundError`:

1. `tests/test_principal_runtime_contracts.py:690-697`
   `test_template_principal_runtime_files_match_root` asserts byte-identity:
   `(ROOT / "templates/automation-base/scripts/ai-principal-runtime.sh").read_bytes()` (+ run-ai-reviews,
   summarize-ai-reviews). After STEP 1 deletes the tree → `read_bytes()` raises → test ERROR.
2. `tests/test_model_routing_lanes.py` — reads `templates/automation-base/...` at lines **31, 91,
   101, 230, 292** (`TEMPLATE_SCRIPT`, `TEMPLATE_DOC`, `TEMPLATE_RECORDER`, `TEMPLATE_CONTEXT_SCRIPT`),
   each a root↔template parity assert. Multiple functions raise after deletion.

Consequence: after the STEP 1/2 commit, `pytest -q` is RED → `verify-machinery.sh` RED → engine
self-test RED → gate cannot pass. This violates (a) D1's "atomic delete, IMPL greps to zero",
(b) IMPL-PLAN's stated invariant "each step independently safe/green", and (c) the §14 DONE
criterion "all engine self-tests green". It is exactly mandate item 2 (a KEPT test broken by the
wholesale delete) and item 5 (a step that leaves the self-test suite RED).

FIX: add to STEP 2 — DELETE `test_template_principal_runtime_files_match_root` (and the three
root↔template parity asserts inside `test_model_routing_lanes.py`, or that whole file's
template-parity assertions) in the SAME commit as STEP 1. Extend the STEP 2 grep gate to
`git grep -nE 'templates/automation-base' tests/` MUST be empty (currently it would still match
test_self_demo_contracts.py:813 — see note below). The byte-identity-with-template contract is the
whole point of these tests; once the template copy is gone the contract is vacuous and must be
removed, not just left to crash.

(NOTE — `tests/test_self_demo_contracts.py:813` also names `templates/automation-base/AGENTS.md`,
but it only feeds the string to `diff_scope_classification` (pure string match, `self_demo_contracts.py:365`
keeps the `startswith("templates/automation-base/")` branch). No filesystem read → it PASSES.
Safe, but the STEP 2 grep-to-zero check must whitelist this one or it will false-trip.)

---

## G2 — MED — `automation-doctor.sh` home-detection sentinel keys off the deleted dir; SPEC §12 only fixes one of two dead conditions

`scripts/automation-doctor.sh:58` `TEMPLATE_DIR="${ROOT}/templates/automation-base"` and `:67`
gates source-repo detection on `[ -d "${TEMPLATE_DIR}" ] && [ -x .../ai-auto-template-status ] && …`.
SPEC §12 / STEP 7 say only: "the `:67` source-repo gate drops its `ai-auto-template-status`
condition." Taken literally, the `[ -d "${TEMPLATE_DIR}" ]` sentinel SURVIVES — and after STEP 1
deletes `templates/automation-base` it is permanently FALSE → `IN_AI_LAB=0` even in the engine
home → `automation-doctor --home` never recognises the home → engine inventory silently does
nothing. This is on the UNSAFE side (masks a broken engine), not a safe no-op.

FIX: the `--home` rewrite must replace the home sentinel with a surviving one
(`templates/domain-packs/` + `scripts/verify-machinery.sh`), exactly as C3 does for obsidian /
ai-tmux-worktree. STEP 7 should name `:58`+`:67`'s `-d TEMPLATE_DIR` explicitly, not just the
`ai-auto-template-status` clause. Likely subsumed by a faithful rewrite, but the anchor-level
instruction as written is wrong.

---

## LOW residuals (safe side; do not individually block, but should be folded in)

- L1 `scripts/install-global-files.sh:577` + `:773` bake `${ROOT}/templates/automation-base/docs/PATCH_NOTES.md`
  into `patch_notes_quoted`; its only consumer is `:817` ("[AI_AUTO] review notes: ${patch_notes}")
  INSIDE the `791-818` block STEP 4(f) removes. So after STEP 4 the var is dead (baked path to a
  deleted file, unused) — harmless but STEP 4(f) should also drop `:577`/`:773` (else a dead var /
  shellcheck warning). Not integrity-breaking.
- L2 `scripts/guidance-duplicate-report.sh:12` default `SCOPE=(AGENTS.md docs templates/automation-base)`
  → after deletion the no-arg default scans a missing path (find under `set -e` would abort). BUT
  every gate/verify caller passes explicit args (`verify-machinery.sh:1156` etc.; automation-doctor:554
  is an existence check, not a run). Default is manual-only → stale, low. Drop the dead element.
- L3 `scripts/collect-review-context.sh:206,298,436-437,488` keep `templates/automation-base/*`
  diff-classification branches — dead-but-harmless after deletion (no path matches). v3 doesn't
  mention them; cosmetic.
- L4 STEP 11 doc-scrub list is INCOMPLETE: it names GLOBAL_TOOLS/NEW_PROJECT_GUIDE/CURRENT_STATE
  but MISSES `docs/AI_RUNTIME_ADAPTERS.md` (ai-auto-template-status :22,:40), `docs/AUTOMATION_OPERATING_POLICY.md`
  (guidance-baseline + refresh-guidance-baseline.sh :355,:359), and `docs/CODEX_SHADOWING_DESIGN.md`
  (heavy ai-auto-template-status + automation-base PATCH_NOTES refs — describes the very codex
  post-commit feature STEP 4(f) deletes). KEPT docs → doc rot only; no test gates them post-delete
  (verify-machinery:6068/6083 doc-grep blocks are in the STEP 2 delete clusters). Not a tool/test
  break, but the "scrub refs" mandate is not actually complete.

---

## Mandate spot-checks that PASSED (independently grep-verified)

- **Item 1 (C3 ripple completeness):** the THREE runtime/tool consumers of the deleted marker FILE /
  concept are correctly and completely enumerated — `obsidian-autopush.sh:81`, `ai-domain-pack:122`,
  `ai-tmux-worktree:27-28`. No OTHER tool execs/reads `AI_AUTO_TEMPLATE_VERSION` or the marker file:
  the only remaining live callers of `ai-auto-template-status`/`ai-template-refresh`/`check-template-version`/
  `template-manifest` are all in v3's handled set (automation-doctor :67,:442-455,:732-734;
  install-global-files :29-30,:791-818,:1003-1005,:1110-1112; bootstrap :209-227,:355-357;
  review-gate :339-392,:606; ai-rebuild-plan :134-137; ai-home :74; ai-auto-init pointer). Residual
  is doc-only (L4).
- **Item 3 (verify seam):** confirmed live & matching v3 — `verify.sh:7` `AI_AUTO_VERIFY_SCOPE`
  default full, `:78` case dispatch, machinery via bare `verify-machinery.sh`; `review-gate.sh:592`
  `AI_AUTO_VERIFY_SCOPE=product`, `:604` single scrubbed fold with `-u REVIEW_DECISION_GATE …`.
  Scope + scrub + single-machinery preserved; derived project's real test = `verify-project.sh`,
  doctor --project warns when absent → no green no-op. Sound.
- **Item 4 (setup self-host guard):** §8.0 / STEP 10 place the guard FIRST, before any hash/`git rm`;
  content-compare falls to the safe (kept) side; baked `readlink -f` shim. Design-sound.
- **Item 6 (minimality):** C6 drops run-parts/`packs/` (F10) — no net-new dispatcher. No regression.

## What MUST change before implementation begins
- G1 (BLOCKING): STEP 2 must also delete the automation-base byte-identity asserts in
  `test_principal_runtime_contracts.py` (697) AND `test_model_routing_lanes.py` (31/91/101/230/292),
  same commit as STEP 1; extend the grep-to-zero gate to `tests/` (whitelisting the string-only
  self_demo_contracts:813). Otherwise `pytest -q` is RED at STEP 1/2 and D1's "atomic, IMPL greps to
  zero" is false.
- G2 (should-fix): automation-doctor `--home` must replace the `-d templates/automation-base` home
  sentinel (:58/:67), not just drop the ai-auto-template-status clause.
- L1/L2/L4: drop the dead `patch_notes_quoted` (install-global :577/:773), the stale guidance-dup
  default-scope element, and finish the docs scrub (AI_RUNTIME_ADAPTERS / AUTOMATION_OPERATING_POLICY /
  CODEX_SHADOWING_DESIGN).
