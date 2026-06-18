# Fix P4 — red-signal (failed verify) guard at the review gate (2026-06-18)

Source: `.aiauto-audit/SYNTHESIS.md` #4 (Claude-principal rationalizes red signals
into proceeds; verify EXIT=1 → proceed_degraded; --no-verify past failing suites).

## Root cause (revised after investigation)
`review-gate.sh` runs `verify.sh 2>&1 | tee` under `set -euo pipefail`, so a failed
verify aborts the gate via `set -e` with NO recorded verdict and a bare nonzero
exit. That opaque crash is itself what drove operators to `git commit --no-verify`
(the gate "just dies"). There was no structural proceed-on-red in the gate, but the
red-handling was invisible and unrecorded.

## Fix (AI council: HYBRID)
- `review-gate.sh`: capture the real verify exit (`PIPESTATUS`, `set +e` around the
  pipe). On failure, by default write an explicit `decision: blocked` /
  `reason: verify_failed` verdict (`write_verify_failed_blocked_verdict`) and stop —
  recorded, not an opaque crash. The AI panel is not run.
- Override requires BOTH `AI_AUTO_VERIFY_OVERRIDE_REASON` and
  `AI_AUTO_VERIFY_OVERRIDE_APPROVED_BY` (two tokens, not one self-set env). That
  path warns loudly, runs the panel, and exports flags so `summarize-ai-reviews.sh`
  forces `proceed_degraded` + degraded trust and records `verify_override:` in the
  verdict. Never a clean proceed.

## Verify
verify-machinery: blocked-path (block + recorded verdict + panel not run) and
override-path (warns + panel runs); test-review-summary: override forces
proceed_degraded. version 2026.06.18.3 -> .4 + PATCH_NOTES. Then review-gate to
unanimous.
