# Defense R9 — HOLISTIC/INTEGRATION + SUITE-INTEGRITY (RED TEAM)

Worktree `feat/global-toolize` HEAD `1ae7dd7`. Read-only audit; built temp projects only. No code edited.

Lens: full-engine run through a shell that SOURCED `hooks/git-scrub.sh` (real hook/launcher child),
on both engine self-host and a derived odoo project, after the R8 fix (chokepoint reduced to
`GIT_CONFIG_COUNT=1 core.fsmonitor=''`, `diff.external` removed). Hunt the NEXT R8-class
integration/lifecycle gap; suite/fixture integrity.

## RESULT: DEFECTS: 1 (highest HIGH)

The single HIGH (odoo validators execute in-repo `.gitattributes` attribute drivers under the
chokepoint) was independently found by the R9 SAFETY lens (`defense-r9-safety.md` DEFECT 1/2).
My integration-lens contribution is an **EXTENSION that the safety fix misses** + the suite-coverage
confirmation. Reported here as H9-1 to keep the holistic record complete; it is the same root cause,
not a second distinct vulnerability.

---

## H9-1 (HIGH — silent RCE on the shipped-validator lifecycle path; safety-fix-as-proposed is INCOMPLETE)

**One line:** The two shipped odoo QC validators run `git diff --no-ext-diff -U0 base -- path` — a
PATCH-producing, worktree-vs-tree diff — over an attacker-influenced project. `--no-ext-diff` closes
ONLY `diff.external`; it does NOT disable a `.gitattributes` **textconv** driver NOR a **clean
filter** driver. Both execute. The R7→R8 chokepoint (`core.fsmonitor=''`) does not touch
attribute-driven drivers. So a malicious project achieves RCE through the validators on the real
pre-push lifecycle path, even under the sourced chokepoint.

**Files:**
- `templates/domain-packs/odoo/validation-harness/check-action-shape.py:87`
- `templates/domain-packs/odoo/validation-harness/check-inherited-field-overlap.py:127`
- Reached in the lifecycle by `templates/domain-packs/odoo/hooks/pre-push:85,95`
  (`( cd "$PROJECT" && python3 "$HARNESS/check-action-shape.py" )` etc.) on every `git push`.

**INTEGRATION value-add over safety DEFECT 1 — the proposed `--no-textconv`-only fix is INCOMPLETE:**
A `git diff <tree> -- <worktree-path>` applies the **clean filter** to the worktree blob before
comparing. `--no-textconv` does NOT imply `--no-filters`. So adding only `--no-textconv` (the safety
report's fix) leaves the **clean-filter RCE** wide open. The validators need
`--no-ext-diff --no-textconv --no-filters`.

**Exact repro (both fire through the ACTUAL shipped validator under a sourced chokepoint):**
```
# textconv vector
mkdir -p p/custom-addons/m && cd p && git init -q && git branch -m main
printf 'X=1\n' > custom-addons/m/m.py && git add -A && git commit -qm i
git config diff.evil.textconv "touch $PWD/PWNED; cat"
printf 'custom-addons/m/m.py diff=evil\n' > .gitattributes
printf 'Y=2\n' >> custom-addons/m/m.py
( . /root/workspace/ai-lab-globalize/hooks/git-scrub.sh
  python3 .../validation-harness/check-action-shape.py --root custom-addons )
# -> PWNED created (textconv ran)

# clean-FILTER vector (NOT closed by --no-textconv) — same setup but:
git config filter.evil.clean "touch $PWD/PWNED_FILTER; cat"
printf 'custom-addons/m/m.py filter=evil\n' > .gitattributes
# -> PWNED_FILTER created via the shipped validator
```
Both verified RESULT-positive on HEAD 1ae7dd7.

**Self-contradicting comment (false assurance):** `hooks/git-scrub.sh:19-23` claims the
".gitattributes ATTRIBUTE-driven diff/textconv/filter drivers ... stay closed at the call site
(... odoo QC validators: --no-ext-diff)". `--no-ext-diff` does not close textconv OR filter — the
design doc asserts a closure the code does not provide.

**Fix:** `["git","diff","--no-ext-diff","--no-textconv","--no-filters","-U0",base,"--",path]` in BOTH
validators (do NOT stop at `--no-textconv`). Also `validate-warm.sh:51-52` (safety DEFECT 2) needs
`--no-ext-diff --no-textconv` (no `--no-filters` there since the `--no-index`-style worktree filter
does not apply to its `git diff HEAD -- f` / `up...HEAD -- f`; verify per-call).

---

## SUITE INTEGRITY (all required runs — GREEN, no R8 regression, no flakiness)

| run | embedded pytest | machinery | exit |
|-----|-----------------|-----------|------|
| `verify-machinery.sh` #1 (direct)              | 237 passed / 1 skipped | 102 + 30 passed, 0 failed, 6 skip | reached end |
| `verify-machinery.sh` #2 (direct)              | 237 / 1 | 102 + 30, 0 failed | **VMEXIT=0** |
| `( . git-scrub.sh && verify-machinery.sh )` #1  | 237 / 1 | 102 + 30, 0 failed | reached end |
| `( . git-scrub.sh && verify-machinery.sh )` #2  | 237 / 1 | 102 + 30, 0 failed | **VMEXIT=0** |
| `pytest -q` #1                                  | 237 passed / 1 skipped | — | 0 |
| `pytest -q` #2 (`-p no:randomly`)               | 237 / 1 | — | 0 |

- Direct vs SOURCED-chokepoint outputs are **byte-for-byte identical** (102+30 passed, 0 failed in
  all four machinery runs). The R8 `diff.external=''` DoS does NOT recur; plain `git diff` works
  through the sourced chokepoint. No R8 regression. No order-dependence (pt2 ran randomly-disabled).
- The "Suggested fixes: ... --fix" tail in every run is a **host-env advisory** (doctor: `/root/bin/*`
  global helper symlinks point at the main ai-lab, not this worktree). "0 failed" / "automation
  doctor completed" — non-fatal, identical direct vs sourced, not a chokepoint effect.
- **`1 skipped` is legit:** `tests/test_todo_report.py:112` — documented BASELINE quarantine
  (live backlog ST-P1-72..77 active by design, proven to fail identically pre-branch). Nothing else.

## NEW R8 fixtures audited — non-vacuous (positive controls fire)

- **R7-F1** (`verify-machinery.sh:7178`): poisoned in-repo `core.fsmonitor` stays inert under the
  sourced chokepoint; control (override block sed-stripped) DOES fire FSM. Now also asserts
  `GIT_CONFIG_COUNT=1` and NO `diff.external` re-export (the R8 guard). Genuine.
- **R8-H8-1** (`:7228`): plain `git diff` through sourced git-scrub yields a real `+world` patch;
  control re-injects `diff.external=''` and DOES die `external diff died`. Genuine.
- **R8-DRIFT** (`:7275`) / **R8-safety** (`:7306`): structural flag-presence + clean-filter RCE on the
  `--no-index` collector path; control strips `--no-filters` and DOES fire PWNED. Genuine.
- **GIT_CONFIG_COUNT collision:** no engine code mutates `GIT_CONFIG_COUNT` non-scoped; the only
  other users are single-command env-prefixes in verify-machinery (6831/6908/6915) that fully
  override KEY_0/VALUE_0 — no collision with the chokepoint's inherited pair.

## SUITE-COVERAGE GAP (corroborates safety DEFECT 3 — MED)

No fixture exercises the odoo validators' textconv/filter neutralization. R8-H8-1 only `grep -q
'no-ext-diff'` (file-wide, not line-anchored, no `--no-textconv`/`--no-filters`, ignores
check-action-shape.py). R8-DRIFT parses only the 4 engine `.sh` files. So H9-1 drifts uncaught. The
drift loop must extend to the validator set AND require `--no-textconv --no-filters` on patch diffs.

## Areas confirmed CLEAN

- `--name-only` / `--numstat` / `--quiet` / `--stat` sites: no patch, ext-diff/textconv/filter do not fire.
- Engine `review_git diff`/`show` sites carry `--no-ext-diff --no-textconv` (+`--no-filters` on the
  `--no-index` content read). Gate provenance hash (`review-gate.sh:49-50`) hardened.
- `core.fsmonitor=''` override: functionally inert (perf only); no git command changes correctness output.
