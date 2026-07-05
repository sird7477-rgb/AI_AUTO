# SPEC-AUD-3 Plan: Odoo validator unavailable fails closed

## Contract

SPEC-AUD-3 requires the Odoo domain-pack pre-push validator to stop treating
unavailable validation as a successful push gate. A push that changes
`custom-addons/` and cannot run the warm registry-load validator must report
`NOT VALIDATED (validator unavailable)` and exit non-zero unless there is
launcher-backed human acknowledgement evidence. This is a pre-push gate only;
local commits remain allowed.

## Design Decisions

1. Treat all warm-validator unavailable states as the same gate outcome:
   missing `ODOO_HARNESS_DIR`, unavailable docker, or missing
   `validate-warm.sh` all block with `NOT VALIDATED (validator unavailable)`.
   The packet calls out docker, but the other two states have the same
   "NOT VALIDATED then exit 0" failure mode.
2. Keep `no custom-addons changes` as a clean skip. The validator is irrelevant
   when the pushed range contains no custom addon module.
3. Replace the old env-only `SKIP_ODOO_VALIDATE=1` bypass with an authenticated
   acknowledgement path. `SKIP_ODOO_VALIDATE=1` is honored only when the active
   principal launcher evidence is valid for this workspace and
   `AI_AUTO_ODOO_UNVALIDATED_ACK_BY` names that principal.
4. Reuse the existing principal evidence HMAC format instead of inventing a new
   approval file. If the evidence is missing, forged, stale, or for a different
   workspace, the push remains blocked.
5. Record the acknowledged bypass in hook output with
   `unvalidated push, human-acked` so the path is visible in logs.

## Implementation Surface

- `templates/domain-packs/odoo/hooks/pre-push`
- `templates/domain-packs/odoo/validation-harness/README.md`
- `templates/domain-packs/odoo/verify-patterns.md`
- `scripts/verify-machinery.sh`

No `templates/automation-base/` files are touched.

## Verification Plan

- Add a hermetic `verify-machinery.sh` fixture that creates a pushed
  `custom-addons` commit and runs the domain-pack pre-push hook directly.
- Assert docker unavailable exits non-zero and prints
  `NOT VALIDATED (validator unavailable)`.
- Assert env-only `SKIP_ODOO_VALIDATE=1` remains blocked.
- Assert launcher HMAC evidence plus matching
  `AI_AUTO_ODOO_UNVALIDATED_ACK_BY` allows the unvalidated push and prints
  `unvalidated push, human-acked`.
- Assert a fake docker plus executable `validate-warm.sh` still reaches the
  warm validator path.
