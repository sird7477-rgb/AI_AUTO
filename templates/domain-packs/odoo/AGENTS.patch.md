# Odoo Agent Guidance Patch

Merge these rules into the target project's `AGENTS.md` only when the project is
confirmed to be Odoo-based.

## Odoo Scope

Before changing Odoo code, confirm:

- target Odoo version
- addon paths and module names
- community vs enterprise dependency boundary
- database/test database name and lifecycle
- whether changes affect models, views, security, reports, cron, or business
  workflows

## Allowed Changes

- narrow custom addon changes inside the confirmed module scope
- Odoo view, model, wizard, report, security, and data-file changes needed for
  the requested workflow
- project-specific tests and smoke checks
- verification script improvements for Odoo commands

## Ask Or Plan First

Do not proceed without a clear plan when the change involves:

- production database operations
- migrations or irreversible data changes
- access rights, record rules, or security-sensitive behavior
- accounting, payroll, inventory valuation, or other regulated workflows
- enterprise/private addon behavior that cannot be inspected locally
- broad refactors across multiple addons

## Verification Rule

Odoo changes are not complete until the project-specific verification command
passes. At minimum, verification should cover syntax/import checks and one Odoo
module install/update or test path when the runtime is available.
