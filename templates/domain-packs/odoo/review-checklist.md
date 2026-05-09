# Odoo Review Checklist

Use this checklist during review-gate prompt design or manual review for Odoo
changes.

## Functional Fit

- The change is limited to the requested module or business flow.
- Model fields, computes, constraints, and onchange logic match the intended
  behavior.
- Views reference valid fields and groups.
- Reports, wizards, and data files are updated consistently.

## Security And Data

- Access rights and record rules are intentional and minimal.
- No production database command is required for verification.
- Data files do not unintentionally overwrite user-managed records.
- Migration or irreversible data behavior is explicitly planned.

## Odoo Runtime

- Odoo version is reported.
- Code/API usage matches the confirmed Odoo major version.
- Module install or update path is verified when runtime is available.
- Test database strategy is clear.
- Enterprise/private dependencies are called out if unavailable.
- Skipped runtime checks include a concrete reason.

## Localization And Project Rules

- Localization assumptions are reported when business data is touched.
- Korean projects use `ko_KR`, KRW, and 10% VAT unless the target project says
  otherwise.
- Project-specific deployment, SSH, branch, commit, attachment, and document
  workflow rules are kept in the target project instructions rather than this
  reusable pack.

## Completion Evidence

- `scripts/verify.sh` passes.
- Odoo module/test command result is reported.
- Business smoke scenario is reported when user workflow changes.
- Remaining risks are explicit.
