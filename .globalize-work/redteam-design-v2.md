# RED TEAM — re-attack of SPEC v2 (feat/global-toolize)

Scope: read-only audit of `.globalize-work/{SPEC.v2.md,DEFECT-MATRIX.md,IMPL-PLAN.md}` cross-checked
against the LIVE tree (branch `feat/global-toolize`, HEAD `6e90184`). Includes validation of the
orchestrator's added decision to FULLY close D6 (read global base + project AGENTS.md, concatenated,
at `collect-review-context.sh:~187` and `doc-budget.sh:~167`).

VERDICT: **NOT certified.** Multiple integrity-breaking defects survive the revision. Ranked below.

---

## F1 — CRITICAL — D6 full-closure applied to `doc-budget.sh:167` breaks the self-host gate

The orchestrator decision says BOTH read-sites read global base + project AGENTS.md "concatenated."
That is correct for reviewer context but WRONG for `doc-budget.sh:167`, which is NOT a context read —
it is a **volume cap**:

    scripts/doc-budget.sh:167  budget_primary_file "AGENTS.md lines" AGENTS.md 150 220
    scripts/doc-budget.sh:80   budget_primary_file -> check_number(line_count) ; value>fail_at -> FAIL_COUNT++
    scripts/doc-budget.sh      FAIL_COUNT>0 -> exit 1

Measured facts: root `AGENTS.md` = **169 lines**; hard fail cap = **220**.

- Self-host (THIS repo, `AI_AUTO_HOME == pwd`): global base == project overlay == the SAME 169-line
  file. "Read both concatenated" = 169 + 169 = **338 > 220 -> FAIL -> doc-budget exits 1 -> gate RED.**
  This directly violates the §13 DONE criterion ("self-host verify.sh green").
- Derived project: base (169, engine-owned, expected to GROW) is counted against the PROJECT's own
  220 cap, defeating the entire point of §7 (budget must measure only project-authored guidance) and
  guaranteeing a future false bloat-failure for guidance the project never wrote.

Root cause: DEFECT-MATRIX D6 enumerates `doc-budget:167` as an "engine reads project AGENTS.md"
read-site, conflating a measurement with a content read. The two read-sites are different in KIND.

FIX: scope the D6 closure to `collect-review-context.sh` ONLY. `doc-budget.sh` must continue to
measure ONLY the project overlay (consistent with §7); do NOT add the global base to any
`budget_primary_file`/`line_count` call. If full guidance coverage is wanted in the budget, it must be
a SEPARATE non-gating informational line, not folded into the capped AGENTS.md measurement.

---

## F2 — CRITICAL — `ai-auto setup` has no self-host guard: run in `$AI_AUTO_HOME` it `git rm`s the engine

§8 / IMPL STEP 10: "for each tracked managed framework file, sha256 vs global pristine: match ->
`git rm`." The only guard is "Fail-closed: refuse on a dirty tree."

If `ai-auto setup` is run with `pwd == $AI_AUTO_HOME` (the source repo) on a CLEAN tree, every managed
framework file is byte-identical to "the global pristine" because it IS the global pristine ->
every file byte-matches -> `git rm` of the ENTIRE ENGINE. The clean-tree precondition is satisfied,
so nothing stops it. Total, silent self-destruction; only recoverable via git.

This is reachable: the §13 proof runs setup on a throwaway project, but there is zero guard against a
fat-fingered `ai-auto setup` in the home, and the launcher self-resolves `$AI_AUTO_HOME` so the two
paths can coincide.

FIX: `ai-auto setup` MUST refuse when `git rev-parse --show-toplevel` resolves to `$AI_AUTO_HOME`
(or when the engine sentinel — e.g. `scripts/verify-machinery.sh` + `tools/ai-auto` — is present in
the target). Add this to STEP 10 as a hard precondition, before any hashing.

---

## F3 — HIGH — 3 KEPT live tools dangle on the deleted `AI_AUTO_TEMPLATE_VERSION` sentinel (missing from ripple list)

IMPL-PLAN STEP 11 + DEFECT-MATRIX "retirement-ripple call-sites" enumerate refs to the deleted
*tools/scripts*, but MISS three KEPT, LIVE consumers that key off the deleted marker FILE
`templates/automation-base/AI_AUTO_TEMPLATE_VERSION`:

1. `scripts/obsidian-autopush.sh:81` — home-checkout guard is
   `[ ! -f "${HOME_ROOT}/templates/automation-base/AI_AUTO_TEMPLATE_VERSION" ]` -> after deletion the
   file NEVER exists -> guard ALWAYS takes the skip branch -> obsidian knowledge-push **silently dies**
   even in the home. Silent (no crash), so it survives the suite. HIGH.
2. `tools/ai-domain-pack:122` (`write_manifest`) — stamps pack manifests' `template_version` from
   `ai_lab_root/templates/automation-base/AI_AUTO_TEMPLATE_VERSION`; after deletion it degrades to the
   literal `"unknown"`. ai-domain-pack is the tool the design REDIRECTS staleness reporting onto
   (matrix: "redirect domain_packs drift to `ai-domain-pack status`"), so the redirect lands on a tool
   whose version field is now meaningless. MED-HIGH.
3. `tools/ai-tmux-worktree:27-28` (`is_ai_auto_project`) — detects an AI_AUTO repo via
   `AI_AUTO_TEMPLATE_VERSION` OR `templates/automation-base/AI_AUTO_TEMPLATE_VERSION` OR
   `.omx/tmux-worktree`. Deleting the marker AND retiring the `AI_AUTO_TEMPLATE_VERSION` concept leaves
   only `.omx/tmux-worktree` — so a freshly-globalized project (no tmux worktree yet) and the home both
   fail detection. MED.

DEFECT-MATRIX claims "Verified inbound refs to the deleted apparatus" — that verification covered tool
NAME refs but NOT marker-FILE refs. FIX: add these three to STEP 11; replace the sentinel with a
home/project detector that does not depend on a deleted file (e.g. presence of `tools/ai-auto` +
`scripts/verify-machinery.sh` for home; `.omx/` for a globalized project).
(`tools/ai-tmux-worktree`, `scripts/obsidian-autopush.sh`, `tools/ai-domain-pack` are all KEPT.)

---

## F4 — HIGH — `verify.sh` §5 drops `AI_AUTO_VERIFY_SCOPE`, re-introducing the closed REVIEW_* env-leak + double machinery

The gate calls verify TWICE with DIFFERENT env hygiene:

    review-gate.sh:586-593  env -u RUN_CLAUDE_REVIEW -u REVIEW_CONTEXT_DETAIL ... \
                            AI_AUTO_VERIFY_SCOPE=product ./scripts/verify.sh
    review-gate.sh:604-625  (machinery-fold) env -u REVIEW_DECISION_GATE -u REVIEW_PROVENANCE_SKIP \
                            -u REVIEW_INTEGRATION_ONLY -u REVIEW_TARGETED_RECHECK ... \
                            ./scripts/verify-machinery.sh

The :592 product call scrubs a DIFFERENT (smaller) REVIEW_* set than the :604 fold; the fold's extra
unsets (`REVIEW_DECISION_GATE`, `REVIEW_PROVENANCE_SKIP`, `REVIEW_INTEGRATION_ONLY`,
`REVIEW_TARGETED_RECHECK`) exist precisely because machinery's own review-gate sub-tests flip under a
leaked decision-gate env (the documented "verify-in-gate flakes under leaked env" regression).

SPEC §5 / IMPL STEP 5 say the new `verify.sh` "runs `verify-machinery.sh` (bare), then runs
`verify-project.sh` IF present" with NO mention of `AI_AUTO_VERIFY_SCOPE`. If implemented literally
(machinery unconditional), then:
- the gate's :592 product call now runs machinery WITHOUT the fold's extra scrub -> REVIEW_* leak
  regression returns; and
- machinery runs TWICE per gate (at :592 inside verify.sh AND at :604).

Also: in a DERIVED project with no `verify-project.sh` (it is OPTIONAL, §1), an unconditional-machinery
verify.sh runs the global engine self-test (which tests the ENGINE, not the project) and NOTHING
project-specific -> `ai-auto verify` returns GREEN having verified nothing about the project (fail-open).

FIX: the new `verify.sh` MUST preserve `AI_AUTO_VERIFY_SCOPE` semantics (`product` => verify-project
only, no machinery; `machinery`/`full` => machinery). Keep the :604 fold as the SINGLE machinery entry
with its full scrub. Document that a derived project's "real" verification is `verify-project.sh`, and
have `doctor --project` warn loudly when it is absent (STEP 7 already plans the warn).

---

## F5 — HIGH — hook shims + run-parts dispatcher hard-depend on `$AI_AUTO_HOME`/PATH being in the git-hook env

`AI_AUTO_HOME` is a NEW variable (grep: not referenced anywhere in the current tree). §4 exports it
"into the shell profile" and §9's shim does `exec "$AI_AUTO_HOME/hooks/<hook>"`; §10's dispatcher and
`hooks/pre-commit.d/00-framework` call siblings (`verify-machinery`) by BARE name via PATH.

Git hooks inherit the env of the `git commit` INVOCATION, not a login shell. Non-interactive contexts —
IDE/GUI git, `git` from cron, a CI runner, a subprocess that didn't source the profile — have NEITHER
`AI_AUTO_HOME` NOR the prepended PATH. Failure modes:
- shim: `exec "$AI_AUTO_HOME/hooks/pre-commit"` with `AI_AUTO_HOME` unset -> `exec "/hooks/pre-commit"`
  -> ENOENT -> **pre-commit fails -> commit blocked** (or, depending on shim, a confusing error).
- dispatcher / 00-framework: bare `verify-machinery` not on PATH -> "command not found" -> the
  framework's commit-test body silently no-ops or errors.

This is strictly WORSE than today: the current `templates/automation-base/hooks/pre-commit` is
self-contained (resolves the engine via `./scripts/` relative to `git rev-parse --show-toplevel`, and
treats global helpers as optional via `command -v`). Note the existing `tools/ai-auto-init` already
shows the correct pattern (readlink self-resolution at lines 4-19).

FIX: the installer must BAKE the resolved absolute `$AI_AUTO_HOME` into each shim at install time (or
the shim must `readlink -f "$0"`-resolve it), and the shim must re-establish PATH
(`PATH="$AI_AUTO_HOME/scripts:$PATH"`) before `exec`. Do NOT rely on the profile export for hook
contexts. Bare-name sibling calls inside framework scripts should also keep a fallback for any
non-profile context (see F8).

---

## F6 — MEDIUM — run-parts failure semantics unspecified (pre-commit must fail-closed; post-commit must isolate)

§10 says the dispatchers "run-parts over `$AI_AUTO_HOME/hooks/<hook>.d/*` (sorted, executable)" but
does NOT specify failure propagation. A naive `for f in "$dir"/*; do "$f"; done`:
- under `set -e` aborts on the first failing part — OK for `pre-commit` (fail-closed) but means a later
  pack part is skipped, and a part returning the pytest-exit-5 ("no tests") code would wrongly block
  (the current `00-framework` body has explicit exit-5 handling that a generic dispatcher loses);
- in `post-commit` (advisory, must NEVER block), one part's nonzero must not abort the rest.

Also unspecified: ignoring backup/editor files (`*~`, `*.disabled`) and non-executables, and the
ordering contract (`00-framework` first).

FIX: specify in §10 — pre-commit.d: run in sorted order, fail-closed on first nonzero EXCEPT preserve
the exit-5/no-runner handling; post-commit.d: run all, isolate failures, always `exit 0`. Skip
non-executable and `*~`/`*.disabled` entries.

---

## F7 — MEDIUM — machinery-fold trigger grep won't fire on the new top-level `hooks/` tree

`review-gate.sh:605` (and the mirror in the pre-commit body) gates the machinery-fold on:
`grep -Eq '^(scripts/|templates/automation-base/scripts/|templates/automation-base/hooks/)'`.

v2 MOVES the commit-test bodies to top-level `hooks/pre-commit.d/00-framework` etc. A change to
`hooks/**` no longer matches `^scripts/` (and the `templates/automation-base/*` alternatives become
permanently-dead). So edits to the framework's OWN hook bodies would skip the machinery re-run that is
meant to catch automation regressions. IMPL-PLAN does not list updating this grep.

FIX: update both grep anchors to `^(scripts/|hooks/)` (drop the dead `templates/automation-base/*`
alternatives) in STEP 3 / STEP 8.

---

## F8 — LOW-MEDIUM — bare-name sibling calls have no fallback; transient RED outside a re-sourced profile

The `s|\./scripts/||` sweep (§4/STEP 4) converts `./scripts/X.sh` -> bare `X.sh` with NO
`command -v ... || ./scripts/X.sh` fallback. Any context whose PATH was not updated by the profile
export — a dev shell that hasn't re-sourced after STEP 4, the hook contexts of F5, a future CI — gets
"command not found." This is not a committed-state defect for the suite (STEP 4 also exports PATH), but
it removes the current robustness where relative `./scripts/` always works from repo root regardless of
PATH. Combined with F5 it is the dominant real-world breakage surface.

FIX: prefer resolving siblings relative to a self-resolved engine dir, or keep a
`command -v X.sh || "$AI_AUTO_HOME/scripts/X.sh"` fallback, so resolution never depends solely on a
profile that a given process may not have sourced.

---

## F9 — LOW — D6 closure double-feeds AGENTS.md in self-host (reviewer-context + duplicate-report noise)

When `AI_AUTO_HOME == pwd` (self-host), adding `$AI_AUTO_HOME/AGENTS.md` to
`collect_review_reference_files` (`collect-review-context.sh:185-191`) emits the SAME file twice
(absolute + relative), so reviewer context — and `guidance-duplicate-report.sh`, whose job is to FLAG
duplication — sees the base guidance duplicated. Cosmetic, not integrity-breaking.

FIX: dedup — skip the global base when it `-ef` (resolves to) the project file.

---

## F10 — LOW-MEDIUM — minimality regression: §10 run-parts + pack-verb dispatch is YAGNI

Per the shortest-code mandate ("delete > add"), §10 ADDS net-new infrastructure — two dispatcher
scripts, `hooks/{pre,post}-commit.d/` trees, AND launcher verb-routing to `$AI_AUTO_HOME/packs/<verb>`
(a `packs/` dir that does not exist) — to satisfy the S6 "extensibility" CRITIQUE, which is not a
correctness defect. There is exactly ONE framework hook body and the only current packs are
domain-packs with a single `pre-push`. This is the same YAGNI the team correctly applied to kill
`$AI_AUTO_PROJECT` (S3). The minimal fix for D7 is just the shims (§9); the run-parts `.d/` dispatch
and `packs/` verb routing can be deferred until a SECOND framework hook part or a non-domain pack verb
actually exists.

RECOMMEND: ship §9 shims now; defer §10's run-parts dispatcher + `packs/` verb routing until a real
second consumer exists. (Non-blocking, but it is the clearest "added beyond the defect" in v2.)

---

## Spot-checks that PASSED
- D1 atomicity: STEP 1+2 land the apparatus deletion AND its `verify-machinery.sh` test blocks +
  `tests/test_template_global_contracts.py` in one commit; `review-gate.sh:341`'s
  `command -v ai-auto-template-status || return 0` fail-opens harmlessly in the interim before STEP 3,
  so no RED window between STEP 2 and STEP 3. Ordering is each-step-safe.
- D4: the ONLY workflow is `template-version-gate.yml` (being deleted); no other CI invokes engine
  scripts, so there is no CI-PATH dependency to break.
- D7 (hook filename coexistence): confirmed odoo pack ships `pre-push` only; framework owns
  `pre-commit`/`post-commit` — three distinct names coexist in one resolved hooks dir. Sound.
- D3 content-compare edge cases: renamed/CRLF/mode-diff all fall to the SAFE side (differ -> kept), per
  the matrix. The one unsafe direction is the self-host case — see F2.

---

## What MUST change before implementation (blocking)
- F1: do NOT fold the global base into `doc-budget.sh:167` (scope D6 closure to
  collect-review-context only).
- F2: add a self-host refusal guard to `ai-auto setup`.
- F3: add obsidian-autopush / ai-domain-pack / ai-tmux-worktree sentinel-file refs to the STEP 11
  ripple and replace the deleted-marker detection.
- F4: keep `AI_AUTO_VERIFY_SCOPE` in the new `verify.sh`; do not run machinery unconditionally.
- F5: shims/dispatcher must self-resolve `$AI_AUTO_HOME` + PATH (not depend on the profile export).
Non-blocking but should be addressed: F6, F7, F8, F9, F10.
