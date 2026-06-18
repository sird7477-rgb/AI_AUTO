# Fix P3 — transient reviewer-disable auto-recovery (2026-06-18)

Source: `.aiauto-audit/SYNTHESIS.md` #3 (Claude reviewer lane disabled by
usage_limit/network retry-exhaustion → stays disabled → Codex self-substitution
becomes the de-facto reviewer).

## Defect
`run-ai-reviews.sh` writes `.omx/reviewer-state/<r>.disabled` on retry exhaustion
with `next_action=user_reset_required`. A transient failure (usage limit, network,
ConnectionRefused) therefore disables the reviewer until a human runs
`RESET_DISABLED_AI_REVIEWERS`. Across the audit window this left Claude/Gemini
disabled and Codex substituting for them as the de-facto reviewer.

## Fix
- `disable_reviewer` classifies the failure: `usage_limit` / `network_or_sandbox`
  / connection|timeout|rate-limit details → `disable_class=transient`; everything
  else → `persistent`. Transient disables get `next_action=auto_recover_after_cooldown`.
- New `expire_transient_disabled_reviewers` runs at startup: a transient disable
  older than `REVIEW_REVIEWER_DISABLE_COOLDOWN_SECONDS` (default 1800) is removed,
  re-enabling the lane. Persistent/unclassified disables are untouched.
- `AI_REVIEWS_EXPIRE_ONLY=1` runs the sweep and exits (test/ops seam).
- Docs (`MULTI_AI_COLLABORATION.md`) note transient auto-recovery.

## Verify
verify-machinery asserts: transient+old → expired; persistent+old → kept;
fresh-transient → kept. shellcheck + parity. Then review-gate to unanimous.
