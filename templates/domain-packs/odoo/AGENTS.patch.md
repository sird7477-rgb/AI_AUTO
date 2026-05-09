# Odoo Agent Guidance Patch

Merge these rules into the target project's `AGENTS.md` only when the project is
confirmed to be Odoo-based.

## Odoo Scope

Before changing Odoo code, confirm:

- target Odoo version
- whether the project requires an explicit version rule such as Odoo 19 only
- addon paths and module names
- community vs enterprise dependency boundary
- database/test database name and lifecycle
- local country baseline, for example `ko_KR`, KRW, and 10% VAT for Korean
  projects
- whether changes affect models, views, security, reports, cron, or business
  workflows

## Version And Localization

- Use APIs and patterns for the confirmed target Odoo version. Do not copy code
  from another Odoo major version without checking compatibility.
- If the project targets Korea, configure demo/test data with Korean language,
  KRW currency, and 10% VAT unless the project owner says otherwise.
- Test companies should use the same localization assumptions as the target
  project.

## Odoo Development Principles

- Prefer standard Odoo extension points over hardcoded Python branches.
- For user-editable categories, classifications, or business labels, prefer a
  dedicated model with `Many2one` over hardcoded `fields.Selection` values.
- Use `ir.config_parameter` or a dedicated settings model for configuration.
- Keep fixed seed data in `data/` XML files.
- Treat upstream `odoo/` and `enterprise/` directories as reference-only unless
  the project explicitly owns a fork.
- Search the relevant base module before choosing what to inherit.

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
- deployment credentials, hosted build IDs, SSH endpoints, or production-like
  access paths that are project-specific

## Verification Rule

Odoo changes are not complete until the project-specific verification command
passes. At minimum, verification should cover syntax/import checks and one Odoo
module install/update or test path when the runtime is available.

Project-specific deployment workflows such as odoo.sh SSH access, branch routing,
commit-message approval rules, and customer-specific attachment or document
automation rules belong in the target project's own `AGENTS.md` or
`docs/WORKFLOW.md`, not in this reusable pack.
