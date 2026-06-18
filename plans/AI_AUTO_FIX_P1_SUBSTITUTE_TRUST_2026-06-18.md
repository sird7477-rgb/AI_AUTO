# Fix P1 — Substitute coverage must report degraded trust (2026-06-18)

Source: `.aiauto-audit/SYNTHESIS.md` #1; corroborated by Codex 06-17 report rec #3.

## Defect
`scripts/summarize-ai-reviews.sh` reports `TRUST_LEVEL=normal` / `decision=proceed`
when `REVIEW_COVERAGE` is `principal_subagent_substitute` or
`principal_rotation_with_substitute`. Those coverages always involve ≥1
decision-relevant lane covered by the *active principal's own subagent substitute*
(if both externals were usable, `multi_reviewer` would have fired first). Reporting
that as normal trust overstates independence. Field `principal_subagent_substitute_regular`
and docs ("with regular trust") encode the same overstatement.

## Fix (principle: normal trust ⇔ no self-substituted decision lane)
1. `scripts/summarize-ai-reviews.sh` (+ identical `templates/automation-base/` copy):
   - Downgrade `proceed` → `proceed_degraded` when coverage is substitute-based.
   - Normal-trust set = `{multi_reviewer, principal_rotation}` only.
   - Rename `principal_subagent_substitute_regular` → `_degraded`.
   - Rewrite doc blocks: "regular trust" → degraded / not independent external review.
2. `scripts/test-review-summary.sh`: `case_principal_subagent_substitute` expect
   `proceed_degraded` + degraded; drop the two substitute coverages from the
   proceed-allowed set in `assert_summary`.
3. `templates/automation-base/AI_AUTO_TEMPLATE_VERSION` 2026.06.11.2 → 2026.06.18.1;
   PATCH_NOTES.md top entry; README.md:432 substitute-coverage wording.

## Verify
`test-review-summary.sh` → `AI_AUTO_VERIFY_SCOPE=machinery scripts/verify.sh` (incl.
template↔local parity) → `scripts/review-gate.sh` to unanimous.
