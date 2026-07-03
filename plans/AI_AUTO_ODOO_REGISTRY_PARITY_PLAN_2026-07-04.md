# Odoo Registry Parity Harness Plan (ORACLE-1)

## Scope

Finish the remaining parity layer for the shipped Odoo warm registry-load
harness. This change does not replace the existing warm harness, does not add a
Tier-1 static view-inheritance lint, and does not make mainline
`verify.sh`/`review-gate.sh` run Odoo.

## Decisions

- Use a warm-base parity stamp written by `prepare-base-db.sh`, not a live
  odoo.sh metadata fetch. The stamp records the operator/CI-provided
  odoo.sh point release plus the full installable custom module set hash.
- Treat a missing or unconfirmed stamp as `BLOCKED (parity unconfirmed)`.
  A stale local warm base must not read as a clean local oracle.
- Expand pushed changed modules through a deterministic reverse-dependency
  closure before calling `validate-warm.sh`. This catches dependent addon view
  inheritance failures without inventing a static view validator.
- Keep enterprise source mounted and external. The scripts record parity
  metadata only; they never bake or copy enterprise/private source.

## Non-Goals

- No static view-inheritance selector lint.
- No Odoo schema-catalog field validator; that is ORACLE-3.
- No new mainline gate authority above `verify.sh` or `review-gate.sh`.
- No odoo.sh API/client integration or credential handling.

## Acceptance Mapping

- Missing parity stamp exits nonzero with `BLOCKED (parity unconfirmed)` and no
  `PASS`: covered in `scripts/verify-machinery.sh`.
- A fake Odoo `-u` registry-load failure containing a missing view anchor is
  rejected by `validate-warm.sh`: covered in `scripts/verify-machinery.sh`.
- Changed module reverse-dependency closure is exact on a fixture graph:
  covered in `scripts/verify-machinery.sh`.
- CI wiring and operator setup are documented in the Odoo harness README and
  verify patterns.

## External Dependencies

None for this slice. Real odoo.sh build metadata and Odoo source remain
project/operator inputs, supplied as environment and mounted paths.
