# Checksheet Runner Completion Plan (ORACLE-2)

## Scope

Finish the existing checksheet runner without expanding it into an Odoo-specific
oracle system. The runner remains a generic deterministic acceptance-oracle
surface. Odoo registry and schema checks can later emit compatible checksheet
items, but this change does not build those Odoo oracles.

## Decisions

- Store the expected item set inside the checksheet as `expected_items`.
  A separate manifest would add a second artifact and a new drift surface without
  improving omission detection.
- Treat schema errors, unknown oracles, missing targets, and oracle selftest
  failures as exit `2`.
- Treat expected-item omissions and oracle rejections as exit `1`.
- Keep `implicit` as an assertion marker, not a reporting-only label. An
  implicit item uses the same fail-closed oracle path as any other item.
- Gate integration is scoped opt-in: `review-gate.sh` runs checksheets only when
  the current diff changes a checksheet artifact. The accepted artifact names are
  `*.checksheet.json` and files under `checksheets/`.

## Non-Goals

- No DB-delta or Excalidraw structural oracle implementation.
- No LLM judge path.
- No Odoo registry-load or schema-catalog implementation.
- No replacement authority for `verify.sh` or `review-gate.sh`.

## Acceptance Mapping

- Schema violation exits `2`: covered by `tests/test_checksheet_run.py`.
- Declared expected item missing exits nonzero by id comparison: covered by
  `tests/test_checksheet_run.py`.
- `implicit: true` rejected item fails the run: covered by
  `tests/test_checksheet_run.py`.
- Broken oracle selftest aborts before real verdicts: existing tests retained.
- Gate does not call the runner when no checksheet artifact changed: covered in
  `scripts/verify-machinery.sh`.
- Gate calls the runner and blocks on a failing changed checksheet artifact:
  covered in `scripts/verify-machinery.sh`.

## External Dependencies

None for this slice. The template-sync note in ST-P1-65 belongs to the original
ai-lab layout and is not implemented in this globalize worktree.
