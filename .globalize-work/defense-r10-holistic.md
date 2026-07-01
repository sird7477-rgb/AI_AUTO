# Defense R10 — HOLISTIC/INTEGRATION + SUITE/FIXTURE-HYGIENE (red-team)

Target: feat/global-toolize HEAD 5494d4c (R9b central `--attr-source`). Read-only audit.

## Verdict: DEFECTS: 1 (highest MED)

The R10 code under test is CLEAN on every functional axis (lifecycle, engine self-host,
diff-regression, suite green/non-flaky, fixtures sandboxed). The one defect is RESIDUAL
environment pollution in the canonical shared repo config + /tmp + a sibling worktree, left
over from PRIOR red-team rounds — not produced by the current suite.

---

## D1 (MED) — Residual malicious git config + marker files polluting the canonical AI_AUTO repo

One-line: the shared git common-config of the AI_AUTO repo (== this worktree's effective
`.git/config`) carries a leaked `[diff "evil2"]` textconv RCE driver, and stale PWNED/FIRED
markers sit in /tmp and a sibling worktree — residue from earlier rounds that lacked cleanup.

Evidence (observed, not caused by the R10 suite):
- `/root/workspace/ai-lab/.git/config` (common dir for the `ai-lab-globalize` worktree) contains:
  `[diff "evil2"]  textconv = "touch /root/workspace/ai-lab-tmux-w4/TEXTCONV_FIRED; cat"`
- `/tmp/GATE_PWNED` (Jul 1 03:15), `/tmp/R5_EXTDIFF_PWNED` (03:51), `/tmp/clean-filter-poc/` (05:52)
- sibling marker `/root/workspace/ai-lab-tmux-w4/TEXTCONV_FIRED` (05:51)

Source: NOT any tracked fixture. `grep -rnE "evil2|TEXTCONV_FIRED|GATE_PWNED|R5_EXTDIFF|clean-filter-poc"`
over scripts/ hooks/ tools/ tests/ returns nothing; every current fixture writes markers ONLY to
`${tmp_dir}` and all `git config` driver writes target temp repos under `mktemp -d`. The textconv
path points at the red-team's OWN worktree (ai-lab-tmux-w4), so this is leftover manual red-team
probing from a prior round (R5/R9 era timestamps) that lacked a temp-repo sandbox + cleanup trap.

Repro: `cat /root/workspace/ai-lab/.git/config | tail`  → shows the `[diff "evil2"]` block;
`ls /tmp/*PWNED* /root/workspace/ai-lab-tmux-w4/TEXTCONV_FIRED`.

Severity MED: a malicious textconv driver is live in the canonical repo config shared by ALL
worktrees of AI_AUTO. It is dormant for the engine (review_git passes `--no-textconv` and
`--attr-source`), but a bare `git diff` over any file bound `diff=evil2` would fire it, and it is
exactly the test-hygiene leak this round is meant to eliminate.

file:line — `/root/workspace/ai-lab/.git/config` `[diff "evil2"]` block (last 2 lines).
Fix: `git config --unset-all diff.evil2.textconv && git config --remove-section diff.evil2` on the
common dir; `rm -f /tmp/GATE_PWNED /tmp/R5_EXTDIFF_PWNED /root/workspace/ai-lab-tmux-w4/TEXTCONV_FIRED`;
`rm -rf /tmp/clean-filter-poc`. For future probes: ALWAYS inject malicious config in a `mktemp -d`
repo with a `trap 'rm -rf' EXIT`, never the real worktree.

---

## Cleared (NO defect) — current blue fixtures are hygienic

Audited every globalize security fixture in `scripts/verify-machinery.sh`:
- R5-1 (~7055), R6-1 (~7120), R7-F1 (~7178), R8-H8-1 (~7240), R9-VALIDATOR-RCE (~7260),
  R9-DRIFT (~7314), R9b-ENGINE-RCE (~7445), R8-safety (~7478).
- EVERY one: `tmp_dir="$(mktemp -d)"` + `trap 'rm -rf "${tmp_dir}"' EXIT`; every `git config`
  driver write runs inside `( cd "${proj}"; … )` where `proj`/`p` is a subdir of `${tmp_dir}`;
  every payload marker (EXT/TXT/CLEAN/PWNED*/FSM) is written to `${tmp_dir}/…`. The R9-DRIFT
  guard is written to a TEMP file and scans a `${tmp_dir}/fake` tree.
- EMPIRICAL: ran `bash scripts/verify-machinery.sh` (plain) and `( . hooks/git-scrub.sh && bash
  scripts/verify-machinery.sh )`. The common-config md5 stayed `a0dafef111d3c40e9748e193b717191a`
  BEFORE and AFTER both runs; zero new /tmp markers; no markers in the worktree cwd or sibling.
  => the suite does NOT pollute outside its sandbox.

## Cleared — lifecycle / `--attr-source` diff regression: NONE (functional)

- Real `collect-review-context.sh` on a NORMAL temp project (worktree edit) produces correct
  non-empty review context: `@@ -1,2 +1,2 @@` / `+    return 2`, rc=0.
- Behavioral change only: a project's legit IN-REPO textconv/diff/clean driver is bypassed (raw
  diff shown in review context). Acceptable, documented tradeoff — callers ALREADY pass
  `--no-textconv` (textconv bypassed pre-R9b), and `--attr-source=<empty-tree>` additionally
  neutralizes the `clean` filter (the R9 residual). docs-only detection uses `--name-only`
  (unaffected); provenance hash is deterministic either way — no gate-logic regression.
- review_git correctness gotcha (pre-existing, NOT a live bug): `-c diff.external=` (empty) makes
  a PATCH-producing `review_git diff` die with "external diff died" UNLESS the caller passes
  `--no-ext-diff`. Audited all 18 call sites (review-gate.sh / summarize-ai-reviews.sh /
  collect-review-context.sh): every patch-producing site (`diff`, `diff --cached`, `show`,
  `--no-index`) carries `--no-ext-diff --no-textconv`; the rest are `--name-only`/`--stat`/
  `--quiet`/`--cached` non-patch modes (verified safe with the empty external driver). No gap.

## Cleared — engine self-host + SUITE green / non-flaky

- `verify-machinery.sh` plain: 237 passed, 1 skipped, exit 0.
- `verify-machinery.sh` under sourced git-scrub: 237 passed, 1 skipped, exit 0 (47s).
- All R5–R9b security fixtures present and PASSING with non-vacuous positive controls;
  `R9-DRIFT OK: 50 git diff/show/log/blame site(s) scanned, all hardened`; R9b-ENGINE-RCE and
  R9-VALIDATOR-RCE both green (clean-filter NOT executed, validator still FLAGS).
- No order-dependence: plain and scrub runs both 237/1, identical verdict.
</content>
</invoke>
