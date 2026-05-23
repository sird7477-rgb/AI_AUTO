# Browser Macro Domain Pack

This pack is an optional reference for projects that automate a browser UI
through a Chrome extension, content script, injected page script, userscript,
bookmarklet, Playwright helper, or similar frontend manipulation macro.

It is copied by `aiinit` only as an ignored onboarding reference under
`.omx/domain-packs/browser-macro/`. It is not merged into project instructions
automatically. During project onboarding, inspect the target project first,
confirm that browser UI automation is actually in scope, then apply only the
parts that match the runtime surface, target site, permissions, and verification
environment.

Use the installed `docs/DOMAIN_PACKS.md` as the common lifecycle and application
contract for all domain packs, and `docs/DOMAIN_PACK_AUTHORING_GUIDE.md` for
pack authoring standards. This README contains only browser-macro-specific
applicability and onboarding guidance.

## When To Use

Use this pack when the project includes one or more of:

- Chrome Extension Manifest V3 development
- content scripts, service workers, or MAIN-world bridge scripts
- userscripts, bookmarklets, or injected page scripts
- Playwright-driven browser macros that operate an existing frontend
- ERP, admin, or back-office UI automation where the page owns important
  JavaScript state beyond the visible DOM
- Ecount ERP Chrome extension work

Do not apply this pack to backend-only projects, static websites without
automation behavior, or ordinary frontend feature work where the application
source is directly owned by the project.

## Files

- `AGENTS.patch.md` - guidance to merge into project `AGENTS.md`
- `WORKFLOW.md` - browser-macro workflow guidance for project `docs/WORKFLOW.md`
- `verify-patterns.md` - verification patterns for `scripts/verify.sh`
- `review-checklist.md` - review checklist for browser automation changes
- `ecount-reference.md` - verbatim Ecount Chrome extension patterns for
  Ecount-specific work

## Reference Material

This pack includes a verbatim Ecount reference at:

- `ecount-reference.md`

When applying this pack to an Ecount project, read that reference before editing
extension code. Preserve project-specific Ecount page names, company URLs,
credentials, customer workflows, and production data rules in the target
project's own instructions, not in this reusable pack.

## Guidance Hierarchy

To prevent instruction bloat, apply this pack in layers:

- Basic guidance: copy only durable rules from `AGENTS.patch.md` into the
  target project's `AGENTS.md`.
- Detailed workflow: keep planning method, runtime investigation, selector
  strategy, and completion evidence in the target project's `docs/WORKFLOW.md`.
- Technical references: keep long vendor-specific notes, DOM discoveries,
  selector maps, and page-model findings in linked reference files.
- Source evidence: keep raw observations and verbatim notes in references, not
  in `AGENTS.md`.

Browser macro work differs from ordinary coding because the project often does
not own the target page runtime. Planning should start from the live DOM,
selector address, browser boundary, and page state model before implementation
details are chosen.

## Onboarding Prompt

During `프로젝트 초기설정 해줘`, ask whether the project automates an existing
browser UI. If it does, confirm:

- automation surface: Chrome extension, userscript, bookmarklet, Playwright
  macro, injected script, or mixed
- target site or app class, without storing private URLs unless the project
  already owns them
- whether the project owns the target frontend source or only manipulates it
- required browser permissions, such as `tabs`, `scripting`, `storage`, or host
  permissions
- whether page JavaScript state must be accessed from MAIN world
- whether DOM edits are only visual or must update an internal page data model
- selector strategy and fallback diagnostics for unstable DOM structures
- DOM scope: top document, iframe, popup, shadow root, virtualized grid, or
  nested component
- whether live investigation should use a user-visible Chrome remote debugging
  session instead of a background/headless Playwright browser
- test environment, sample data, and rollback procedure
- whether automation touches real orders, inventory, accounting, personal data,
  or other production-sensitive state
- whether Ecount-specific rules apply

Then adapt `AGENTS.md`, `docs/WORKFLOW.md`, and `scripts/verify.sh` from this
pack. Keep final files project-specific; do not paste unused checklist items or
example commands.
