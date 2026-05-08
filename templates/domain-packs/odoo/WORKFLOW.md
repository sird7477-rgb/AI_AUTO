# Odoo Workflow Pack

Use this as source material for the target project's `docs/WORKFLOW.md` after
confirming that the project is Odoo-based.

## Onboarding Questions

- Which Odoo version is targeted?
- Which addon directories are in scope?
- Which modules are owned by this project?
- How is the Odoo runtime started locally?
- How is the test database created and destroyed?
- Which command installs or updates the changed module?
- Which business flow is the required smoke check?
- Are enterprise/private addons required to run tests?

## Development Loop

1. Identify the affected module, model, view, security file, report, or data
   file.
2. Keep the change inside the confirmed addon scope.
3. Update or add tests when project test infrastructure exists.
4. Run the project Odoo verification command.
5. Run the business smoke check when the change affects user workflow.
6. Run the standard review gate before presenting a commit candidate.

## Odoo-Specific Completion Evidence

Report:

- Odoo version and module names
- changed addon paths
- install/update/test command used
- database strategy used for verification
- smoke scenario result
- any skipped checks and why they were unavailable

## Default Non-Goals

Unless explicitly requested, do not:

- change production deployment settings
- perform real production database operations
- add broad migration tooling
- introduce new external services
- change unrelated addons
- harden infrastructure beyond the requested development workflow
