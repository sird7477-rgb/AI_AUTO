# Defense R8 — HOLISTIC/INTEGRATION + SUITE-INTEGRITY (RED TEAM)

Worktree `feat/global-toolize` HEAD `b581bf5`. Read-only audit; built temp projects only. No code edited.

Lens: full lifecycle (derived + self-host) after R7 (process-level GIT_CONFIG chokepoint in
`hooks/git-scrub.sh`, non-exec verify-project handling). Hunt for a functional regression from
the chokepoint; engine self-host green; suite/fixture integrity + GIT_CONFIG leak.

## RESULT: DEFECTS: 1 (highest HIGH)

---

## H8-1 (HIGH — chokepoint-functional-regression + self-host-regression + shipped-tool silent masking)

**One line:** The R7 `export diff.external=''` env override (git-scrub.sh:45) breaks EVERY plain
(non-`--no-ext-diff`) patch-producing `git diff` in the engine process tree and in every
`ai-auto`-launched child — git treats an EMPTY external-diff command as "run the empty program"
(`fatal: external diff died`, exit 128, empty stdout), NOT as "no external diff". This silently
blinds the shipped odoo QC validators and fails the engine's own self-host machinery.

**Root cause / mechanism (file:line):** `hooks/git-scrub.sh:43-45`
```
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0='core.fsmonitor' GIT_CONFIG_VALUE_0=''
export GIT_CONFIG_KEY_1='diff.external'  GIT_CONFIG_VALUE_1=''
```
`core.fsmonitor=''` is harmless (empty == disabled). But `diff.external=''` is NOT equivalent to
"no external diff": git tries to exec the empty command per file →
`error: cannot run : No such file or directory` / `fatal: external diff died` (exit 128, empty
patch). There is NO env-config equivalent of `--no-ext-diff`; only the call-site flag forces the
builtin. `review_git()` (git-harden.sh:18) is safe because it adds `--no-ext-diff`; PLAIN
`git diff` sites — the very ~15 sites the R7 comment claims to "neutralize without touching the
call site" — are exactly what breaks.

**This is leaked into the real lifecycle, not a synthetic env:**
- `tools/ai-auto:19` (launcher) AND the baked per-project shim `tools/ai-auto:165` source
  git-scrub.sh → `diff.external=''` is exported into EVERY `ai-auto` subcommand and all children
  (`ai-auto verify`/`gate` → verify.sh → verify-project.sh → checksheet → validators).
- `hooks/pre-commit:18` sources git-scrub.sh top-level, then (engine self-host, framework files
  staged) runs `verify-machinery.sh` at :62 → the leaked env reaches the machinery.

**Victims:**
1. Engine self-host: `scripts/verify-machinery.sh:565` (ST-P1-62 odoo inherited-field overlap)
   FAILS LOUD (exit 1, "inherit-overlap did not flag the same-field/two-addon case") under the
   real pre-commit→verify-machinery path. So a clean self-host commit of framework files through
   the hook is BLOCKED (currently only masked by committing with `--no-verify`).
2. Shipped domain-pack QC validators go SILENTLY BLIND (their `run()` helper uses
   `subprocess.run(check=False)` and swallows the fatal-error/empty stdout):
   - `templates/domain-packs/odoo/validation-harness/check-inherited-field-overlap.py:127`
   - `templates/domain-packs/odoo/validation-harness/check-action-shape.py:87`
   both do `git diff -U0 base -- path` → empty → no changed lines parsed → report NO findings even
   when defects exist. A derived odoo project running `ai-auto verify`/`gate` gets a false-green QC.

**Exact repro (deterministic, isolated — no concurrency):**
```
cd /root/workspace/ai-lab-globalize
( . hooks/git-scrub.sh && bash scripts/verify-machinery.sh ); echo $?
#   -> "[verify] inherit-overlap did not flag the same-field/two-addon case" ; exit 1
```
Minimal proof of the git semantics:
```
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.external GIT_CONFIG_VALUE_0='' \
  git diff -U0 HEAD -- some_changed_file
#   -> error: cannot run : No such file or directory
#   -> fatal: external diff died, stopping at ... ; rc=128 ; empty stdout
```
Isolation of the culprit key (only diff.external; fsmonitor is innocent):
```
# diff.external='' only  -> NO FLAG (broken)
# core.fsmonitor='' only -> flag present (fine)
# --name-only / --numstat / --porcelain / --quiet  -> UNAFFECTED (no patch, no ext-diff)
```

**Why per-component tests miss it:** run DIRECTLY, `verify-machinery.sh` and `pytest` are green
(diff.external unset → builtin diff). The regression only bites when git-scrub.sh is in the
process ancestry (launcher / pre-commit), which is precisely the production path. Classic
holistic/integration gap. New in R7 — the `diff.external=''` export did not exist pre-b581bf5.

**Fix:** Remove `diff.external` from the env override (keep `core.fsmonitor=''`, which is benign).
env-config cannot express `--no-ext-diff`, so the config-driven external-diff RCE must stay closed
at the CALL SITE: ensure every patch-producing `git diff` is routed through `review_git()`
(`--no-ext-diff --no-textconv`), and add `--no-ext-diff` to the two shipped odoo validators'
`git diff -U0` calls (check-inherited-field-overlap.py:127, check-action-shape.py:87). The empty
external-diff override does not even cleanly neutralize the attack — it converts an in-repo RCE
into a process-wide DoS on every plain patch diff.

---

## Areas confirmed CLEAN

- **pytest:** 237 passed / 1 skipped, run TWICE (76.0s, 74.9s). Stable, no order-dependence,
  no flakiness. Green even with GIT_CONFIG_COUNT=2 leaked in (engine pytest fixtures do not rely
  on fsmonitor/diff.external being honored) — the leak corrupts the bash machinery validators, not
  pytest. VMEXIT=0 on the clean machinery path.
- **verify-machinery (clean, direct invocation):** GREEN (run 1: pytest 237/1 + machinery
  "102 passed, 0 failed"). Run 2 confirmatory.
- **core.fsmonitor='' override:** functionally inert — `git status --porcelain` / `--name-only` /
  `--numstat` outputs identical with and without it; only disables an fsmonitor hook (perf, not
  correctness). No regression.
- **R7-F1 fixture (positive control via sed-stripping the override block):** genuinely
  non-vacuous — targets the real vector (collect-review-context.sh:17 plain `git status
  --porcelain` at module-load) and the stripped control DOES fire `core.fsmonitor` (touch FSM).
  The leading unset block (git-scrub.sh:22-30, retained in the stripped control) clears
  GIT_CONFIG_COUNT/KEY_* BEFORE any re-export, so even a leaked parent GIT_CONFIG_COUNT=2 cannot
  flip the control to a false pass. No hidden cross-fixture pass/fail flip.
- **R7-F2 fixture (present-non-exec verify-project.sh):** non-vacuous — asserts the passing
  non-exec file RUNS (NONEXEC_VERIFY_RAN), that a FAILING non-exec file BLOCKS, and that the hook
  discloses "present but NOT executable" and never mislabels it "absent". pre-commit:75 (`-e`
  guard) + verify.sh:63 (bash fallback) handle the lost-exec-bit case correctly.
- **GIT_CONFIG env leak across fixtures:** the R7-F1/HARDENED subshells are `( ... )` — the export
  dies with the subshell; no leak to subsequent fixtures. git-scrub.sh always unsets before
  re-export, so re-sourcing is idempotent.
