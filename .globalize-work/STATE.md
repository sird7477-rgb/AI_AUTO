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
