# Fix P5 — DOC_BUDGET reason quality + deferred follow-ups (2026-06-18)

Source: `.aiauto-audit/SYNTHESIS.md` #4-#5 (audit DOC_BUDGET reason strings; hook
skips; Odoo validation), plus a finding surfaced during this work.

## Implemented: DOC_BUDGET reason quality
`doc-budget.sh` already required a non-empty `DOC_BUDGET_TEMPLATE_PATCH_REASON`.
It now also rejects a trivially short reason (< 12 non-space chars), so recycled
placeholder reasons cannot wave the budget bypass through. verify-machinery adds a
short-reason fail-closed case.

A stronger "this reason is recycled from a prior commit" check was considered and
rejected: it needs commit-history comparison and risks false positives. A
"template-patch mode must touch template-owned guidance" check was implemented and
then reverted: in an INSTALLED project the template-owned files live at `docs/` /
`AGENTS.md` (not `templates/automation-base/`), so that check would wrongly fail
the legitimate template-adoption flow. The portable, low-risk improvement is the
substantive-reason requirement.

## Deferred (investigative / out of scope for a bounded code change)
- **Hook-skip taxonomy** (Codex 06-17 rec #4: `unmanaged_session`,
  `target_not_found`, `pane_has_active_task`, `mode_not_allowed`): operational
  investigation of why hook automation frequently no-ops; not a single code fix.
- **Odoo domain validation** (manifest/missing-file pre-push gaps): belongs to the
  Odoo domain pack / a different repo, not the ai-lab automation core.
- **verify-machinery not run by the gate or pre-commit hook**: surfaced this
  session — the review gate runs `verify.sh` at `product` scope and the pre-commit
  hook runs pytest; neither runs `verify-machinery.sh`, so machinery regressions
  (e.g. the P3 `write_disabled_result` text drift) slip past both. Worth a
  follow-up: have the gate/hook also run a `machinery`-scope verify for changes
  touching `scripts/**` or `templates/automation-base/scripts/**`.

## Verify
verify-machinery (reason fail-closed case) + parity + shellcheck -> review-gate to
unanimous. version 2026.06.18.4 -> .5 + PATCH_NOTES.
