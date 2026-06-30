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
