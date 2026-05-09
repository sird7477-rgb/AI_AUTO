# Odoo Workflow Pack

Use this as source material for the target project's `docs/WORKFLOW.md` after
confirming that the project is Odoo-based.

## Onboarding Questions

- Which Odoo version is targeted?
- Is the project locked to one major version, for example Odoo 19?
- Which addon directories are in scope?
- Which modules are owned by this project?
- How is the Odoo runtime started locally?
- How is the test database created and destroyed?
- Which command installs or updates the changed module?
- Which business flow is the required smoke check?
- Are enterprise/private addons required to run tests?
- Which localization baseline applies, for example Korean `ko_KR`, KRW, and
  10% VAT?
- Are there project-specific deployment, SSH, branch, or commit rules that must
  stay in the target project instructions?

## Development Loop

1. Identify the affected module, model, view, security file, report, or data
   file.
2. Keep the change inside the confirmed addon scope.
3. Update or add tests when project test infrastructure exists.
4. Run the project Odoo verification command.
5. Run the business smoke check when the change affects user workflow.
6. Run the standard review gate before presenting a commit candidate.

## Project-Specific Rules

Keep reusable Odoo guidance separate from project-specific operations:

- reusable pack: Odoo version discipline, addon-scope rules, verification
  patterns, localization prompts, and review checklist
- target project files: customer-specific modules, odoo.sh URLs, SSH keys,
  branch routing, commit approval rules, attachment/document automation rules,
  and production-like access procedures

## Odoo-Specific Completion Evidence

Report:

- Odoo version and module names
- changed addon paths
- install/update/test command used
- database strategy used for verification
- localization baseline used for demo/test data
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
