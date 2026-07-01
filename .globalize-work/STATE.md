# Globalize — orchestration state

Worktree: /root/workspace/ai-lab-globalize  (branch feat/global-toolize, base 6e90184)
Orchestrator: main loop. All build/red/blue work = subagents. Report to user ONLY "완성되었습니다".

## Stages
- [~] S1 DESIGN
   - v1 attacked: correctness 8 (D1 CRITICAL) + simplicity 6 → redteam-design-{correctness,simplicity}.md
   - v2 written: SPEC.v2.md + DEFECT-MATRIX.md + IMPL-PLAN.md. All resolved; D6 → orchestrator chose FULL closure (read global+project AGENTS.md at collect-review-context:187 & doc-budget:167).
   - v2 RE-ATTACK dispatched (redteam-design-v2.md). Gate: CERTIFIED.
- [ ] S2 IMPLEMENT — blue-team per IMPL-PLAN (14 steps), shortest code. Include D6 full-closure edit.
- [ ] S3 TEST/DEBUG — red-team certify implementation
- [ ] S4 DEFENSE GAME — red hunt / blue fix, loop until 2 dry red rounds

## Locked decisions (R1–R9 + D6-full): see SPEC.v2.md / DEFECT-MATRIX.md
Core: DELETE templates/automation-base + installer + version/drift/staleness machinery + their tests;
PATH-based sibling resolution; verify.sh global + optional scripts/verify-project.sh; one idempotent
content-aware `ai-auto setup`; framework pre-commit/post-commit shims (no hooksPath hijack); run-parts
pack extensibility; doctor two-mode; KEEP templates/domain-packs.

## Defense game protocol
Red/blue = subagents. Loop until 2 consecutive red rounds find nothing new. All in this worktree.

## S1 DESIGN — CERTIFIED (conditional) after 3 rounds
v3 re-attack: G1(HIGH) + G2(MED) + LOW = IMPL-completeness only (incomplete delete-ripple), not design flaws.
Conditions folded into IMPL hard gates: (a) grep-to-zero for every deleted identifier in KEPT files;
(b) test suite GREEN after each phase; (c) doctor home-detection + collect-review-context D6 + LOW residuals.
redteam-design-v3.md has the exact ref list (test_principal_runtime_contracts:697, test_model_routing_lanes:31/91/101/230/292, automation-doctor:58/67, install-global-files:577/773 dead path, doc-scrub misses).

## S2 IMPLEMENT — dispatched P1 (delete copy-model + complete ripple)

## S2 IMPLEMENT — progress (each phase committed, suite green gate)
- P1 eb21263: delete copy-model + ripple (grep-to-zero; 238 pass)
- P2 2a171df: self-dir sibling resolution + AI_AUTO_HOME/PATH export (smoke proven)
- P2.5 5179df6: GREEN baseline — fixed 5 P1 regressions, doc'd 2 pre-existing (BASELINE.md)
- P3 5df204b: verify seam (global verify.sh -> optional project verify-project.sh, fail-closed)
- P4 [dispatched]: ai-auto launcher + content-aware setup (self-host guard, baked-path shims)
- P5 [pending]: doctor 2-mode finalize + D6 collect-review-context (read global+project AGENTS) + LOW residuals
- P6 [pending]: global-mode tests + end-to-end migrate proof; then S3 red-cert; then S4 defense game

## S4 DEFENSE GAME
- P6 aa8d028: permanent global-mode fixtures. Implementation complete (P1-P6).
- R1 red (3 hunters): HIGH 2 (shim-no-block, docs-stale) + MED 6 + LOW many. Suite GREEN + E2E DONE confirmed.
- R1 blue-A 2c3a8bf: code hardening F1-F6,E,M3 + fixtures (237 pass/1 skip).
- R1 blue-B e29a5fe: docs truthfulness (ai-auto setup global model).
- R2 red: dispatched (verify R1 fixes hold + new defects). dry-count target = 2 consecutive.
- R2 red: safety HIGH 1+MED 3+LOW 2; engine CLEAN; minimality 1 LOW. NOT dry.
- R2 blue c3b4781: dir-guard, atomic git rm + flock, GIT_CONFIG scrub, marker align + fixtures (237/1 green).
- R3 red dispatched (3 hunters). dry-count=0; need 2 consecutive dry.
- R3 red: safety HIGH 1+MED 2; holistic HIGH 1 (ai-auto verify crash); minimality 0. NOT dry.
- R3 blue 58bcb42: engine-aware verify scope, existence guard, launcher+hooks+shim GIT_CONFIG scrub (RCE), common-dir lock, doctor --home + fixtures (237/1 green). R3-4 fd-CLOEXEC skipped (justified).
- R4 red dispatched (safety / holistic / portability-env). dry-count=0; need 2 consecutive.
- R4 red: safety HIGH 1 (GIT_EXTERNAL_DIFF RCE)+MED 1+LOW; portability MED 2(tools PATH, readlink)+LOW (flock/readlink CONFIRMED work on real /mnt/z 9p); holistic 2 LOW. NOT dry.
- R4 blue 775a081: comprehensive canonical git-exec-env scrub (4 places), toplevel engine-detect, tools/ PATH, advisory text, legacy-hook upgrade + fixtures (237/1). M2/R4-3/4 + portab LOW skipped (justified).
- R5 red dispatched (scrub-bypass+new-vectors / holistic / minimality+denylist-drift). dry-count=0; need 2 consecutive.
- R5 red: safety HIGH 1 (local-config .gitattributes RCE)+LOW; minimality MED 1 (scrub 4-copy drift)+LOW; holistic 2 LOW. NOT dry.
- R5 blue b9a480e: review_git() call-site hardening (--no-ext-diff/textconv/filters) closes local-config RCE; single-source hooks/git-scrub.sh (+GIT_TRACE*/TEMPLATE_DIR); derived pre-commit verify-seam; fd CLOEXEC; SPEC sync + fixtures (237/1 green).
- git-injection class closed at call-site. R6 red dispatched. dry-count=0; dry = no actionable (HIGH/MED or fix-needing-LOW) finding.
- R6 red: safety HIGH 1 (R5-1 incomplete — collect-review-context.sh raw git diff/show/--no-index still RCE via project-local .gitattributes; gate runs it pre-skip); holistic MED 1 (H1: derived pre-commit fail-closes the setup-printed adoption commit when verify-project.sh absent); minimality 1 LOW (R6-1 138-line provenance block extraction, optional). NOT dry.
- R6 blue: harden collect-review-context.sh patch calls (--no-ext-diff/--no-textconv on diff/show/--no-index); extract review_git to single-source scripts/git-harden.sh, sourced by review-gate.sh + summarize + collect (inline copies removed; provenance block stays byte-identical, sources the helper); derived pre-commit warns+ALLOWs onboarding commit when verify-project.sh absent (ai-auto verify keeps fail-closed exit 1); new fixtures (R6-1 real-collector RCE + control, D2/H1 warn-allow + onboarding commit + present-gates/failing-blocks); 237/1 green, VMEXIT=0. R6-1 LOW (full block extraction) SKIPPED — review_git extraction did not make it trivially natural; the remaining ~130 lines stay test-enforced byte-identical to avoid risk.
- R6 red: safety HIGH 1 (collect-review-context hardening gap = R5-1 incomplete); holistic MED 1 (onboarding fail-closed blocks adoption commit); minimality LOW 1. NOT dry.
- R6 blue 54d2b3e: single scripts/git-harden.sh sourced by all 3 trust-path scripts (review_git in ONE file), collect-review-context hardened -> local-config RCE FULLY closed w/ positive-control fixture; derived pre-commit warn-and-allow onboarding; conftest helper. 237/1 green.
- git-injection class architecturally closed. R7 red dispatched. dry-count=0; need a genuinely-clean round (then confirm with a 2nd).
- R7 red: safety HIGH 1 (core.fsmonitor RCE on all worktree git calls)+LOW; holistic LOW 1; minimality LOW 1. NOT dry.
- R7 blue b581bf5: process-level config chokepoint (git-scrub exports GIT_CONFIG core.fsmonitor=/diff.external=) + review_git 2-layer defense; non-exec verify-project; git-harden in FRAMEWORK_PATHS; SPEC word + positive-control fixtures (237/1 green).
- git-exec class closed 2-layer (config chokepoint + attribute call-site). R8 red dispatched. dry-count=0; need 2 consecutive clean.
- R8 red: safety HIGH 1 (--no-filters drift @1400); holistic HIGH 1 (R7 diff.external='' REGRESSION breaks plain git diff, victims engine+odoo QC); minimality CLEAN. NOT dry.
- R8 blue 1ae7dd7: diff.external removed from chokepoint -> call-site --no-ext-diff (incl 2 odoo validators); --no-filters@1400; sourced-chokepoint INTEGRATION fixture (closes the gap that hid H8-1) + structural drift-guard. ( . git-scrub && verify-machinery ) before=1 after=0; 237/1 green.
- git-defense mechanism corrected + integration-tested + drift-guarded. R9 red dispatched. dry-count=0; need 2 consecutive clean.
- R9 red: safety 2 HIGH + MED (domain-pack validators/harness git diff unhardened; drift-guard narrow); holistic HIGH (clean-filter on --name-only too); minimality LOW. NOT dry.
- R9 blue 410117f: --attr-source=<empty-tree> mechanism hardens ALL domain-pack worktree git diffs (7 files) + tree-wide drift-guard (50 sites) + 3-vector positive control.
- R9b blue 5494d4c: centralized --attr-source in review_git; hardened ENGINE worktree diffs (collect-review-context/review-gate/run-ai-reviews/doc-budget) closing the last disclosed residual; uniform tree-wide drift-guard. both gates green 237/1.
- CLEANUP: removed fixture-leaked malicious drivers from worktree .git/config (filter.evil*/diff.external) + marker files. config CLEAN.
- git-exec RCE class CLOSED tree-wide-uniform (review_git --attr-source + fsmonitor chokepoint + drift-guard). R10 red dispatched. dry-count=0; need 2 consecutive clean. NOTE for suite-integrity: verify no fixture pollutes real .git/config or worktree.
- R10 red: safety MED (drift-guard evadable, LATENT no active vuln); holistic MED (pre-existing config pollution, current fixtures clean); minimality LOW (removable belt). HIGH=0, no active vulnerability -> git-exec class confirmed closed.
- R10 blue 70fd6e5: drift-guard matcher hardened vs if/for/eval/xargs/python-concat evasion + controls. 50 sites all hardened, both gates green 237/1.
- CLEANUP: removed [diff.evil2] from shared /root/workspace/ai-lab/.git/config + all markers. all configs CLEAN.
- R11 red dispatched (final gauntlet). HEAD 70fd6e5. If R11+R12 both clean -> 2 consecutive dry -> DONE.
- R11 red: safety LOW (guard prefix latent); minimality MED (PATCH_NOTES orphan -> goal#1 gap); holistic HIGH (D1 ai-auto setup clean-filter RCE, live) + MED (D2 guard blind to extensionless launchers, MASKED D1). NOT dry.
- R11 blue aa51a76: is_text scans shebang/extensionless -> guard covers 27 tools/ launchers; setup diffs+git rm routed via review_git --attr-source (D1 closed, positive control); knowledge-capture hardened; retired-file (PATCH_NOTES marker) de-pollution meets goal#1; guard command-prefix hardened. 55 sites all hardened, both gates green 237/1.
- git-exec class closed across engine+domain-pack+tools (55 sites, guard covers all file types incl extensionless). R12 red dispatched (final gauntlet #2). dry-count=0.
