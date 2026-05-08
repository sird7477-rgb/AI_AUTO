# Odoo Domain Pack

This pack is an optional reference for projects that build, customize, or test
Odoo modules.

It is copied by `aiinit` only as an ignored onboarding reference under
`.omx/domain-packs/odoo/`. It is not merged into project instructions
automatically. During project onboarding, inspect the target project first,
confirm that it is an Odoo project, then apply only the parts that match the
project version, deployment model, and test environment.

## When To Use

Use this pack when the project includes one or more of:

- custom Odoo addons
- Odoo module tests
- Odoo version-specific migration or compatibility work
- Docker or local Odoo runtime configuration
- business workflow customization inside Odoo

Do not apply this pack to non-Odoo projects.

## Files

- `AGENTS.patch.md` - guidance to merge into project `AGENTS.md`
- `WORKFLOW.md` - Odoo-specific workflow guidance for project `docs/WORKFLOW.md`
- `verify-patterns.md` - verification patterns for `scripts/verify.sh`
- `review-checklist.md` - review checklist for Odoo changes

## Onboarding Prompt

During `프로젝트 초기설정 해줘`, ask whether the project is Odoo-based. If it is,
confirm:

- Odoo version
- addon paths
- test database strategy
- module install/update command
- whether Docker Compose is available
- whether enterprise/private addons are required
- smoke scenario that proves the customized business flow works

Then adapt `AGENTS.md`, `docs/WORKFLOW.md`, and `scripts/verify.sh` from this
pack. Keep the final files project-specific; do not paste unused checklist items
or commands.
