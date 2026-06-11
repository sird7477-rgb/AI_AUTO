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
- for Odoo 19 on odoo.sh, the project-local access runbook for SSH, temporary
  admin password handling, branch routing, and Playwright environment variables
- when odoo.sh SSH is run from WSL, whether the required key is present in WSL
  `~/.ssh`; a key that exists only in Windows PowerShell's SSH location is not
  available to WSL `ssh`

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

## Knowledge Retrieval

Before Odoo schema/view/field/security work, consult the relevant `Odoo19_Docs_KB/slim/<topic>`
navigation file first (token-cheap), and the project's `Odoo.sh KB/` decision guides; read
`raw/<topic>` only when slim is insufficient. The KB is **advisory** — current repo evidence
(actual code, registry-load validation, tests) always overrides a KB note; a stale slim entry
must never justify code that contradicts the live module. (A domain-gated retrieval hook may
surface this slim pointer automatically when the project profile is `odoo`; the boundary is the
same — repo evidence wins.)

## Verification Rule

Odoo changes are not complete until the project-specific verification command
passes. At minimum, verification should cover syntax/import checks and one Odoo
module install/update or test path when the runtime is available.

Trigger "로컬띄워" (also "로컬 띄워" / "serve 띄워" / "UI 확인"): start the harness
`serve.sh <project> [changed modules]` in the BACKGROUND (long-running HTTP server —
never block the session), then report `http://localhost:<port>` and `admin / admin` so
the user verifies the rendered UI by hand before push. See the workflow pack's "Local UI
Preview" section for details.

Project-specific deployment workflows such as odoo.sh SSH access, branch routing,
temporary admin password handling, Playwright login variables, commit-message
approval rules, and customer-specific attachment or document automation rules
belong in the target project's own `AGENTS.md` or `docs/WORKFLOW.md`, not in
this reusable pack.

Never paste private key material into project docs, prompts, logs, memories, or
feedback queues. Project runbooks may document commands that verify key presence,
copy a key into WSL, set file permissions, or choose an `IdentityFile`, but must
leave actual key values in the user's local SSH store.
