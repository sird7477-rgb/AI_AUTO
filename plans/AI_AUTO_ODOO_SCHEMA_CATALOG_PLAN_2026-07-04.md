# Odoo Schema Catalog Screen Plan (ORACLE-3)

## Scope

Add a registry-derived schema catalog screen to the shipped Odoo validation
harness. This is not a replacement for the warm `-u` registry-load oracle and
does not duplicate `pylint-odoo` or static style linting.

## Decisions

- The catalog is a regenerable warm-base artifact, written by
  `prepare-base-db.sh` from the Odoo registry (`ir.model.fields`) after the full
  module set installs. It is never hand maintained.
- Catalog absence or unreadability prints `catalog unavailable, NOT screened`
  and exits 0 by default. A clean output is never emitted when no catalog was
  used. `--strict` turns unavailable catalog into rc 1 for CI projects that make
  the screen required.
- The screen checks changed addon Python field definitions, `related=` chains,
  and XML `<field name="...">` references against the catalog. It is a cheap
  pre-build screen; registry-load remains the final judge.
- Existing-addon semantic collision detection extends the shipped
  `check-inherited-field-overlap.py` behavior in the new catalog checker: one
  changed addon redefining a `(model, field)` that is already owned by another
  installed addon is reported as advisory, not a hard invalid-field failure.

## Non-Goals

- No OCA/static lint reimplementation.
- No claim that screen PASS means the module is installable.
- No Obsidian KB authority.
- No mainline `verify.sh`/`review-gate.sh` Odoo runtime calls.

## Acceptance Mapping

- Missing field/model references in Python/XML fixtures fail under `--strict`
  with `Invalid field`/`Invalid model` wording.
- Valid fixtures using catalog-known models and fields are silent/OK.
- Missing catalog emits `catalog unavailable, NOT screened` instead of a quiet
  green.
- A changed addon defining an installed addon-owned `(model, field)` is flagged
  as an advisory catalog collision.
- `scripts/verify-machinery.sh` carries non-vacuous fixtures for these cases.
