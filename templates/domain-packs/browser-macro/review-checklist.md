# Browser Macro Review Checklist

Use this checklist during review-gate prompt design or manual review for browser
automation, Chrome extension, frontend manipulation, or macro changes.

## Scope And Permissions

- The change is limited to the requested browser workflow.
- Basic `AGENTS.md` guidance remains compact, with detailed page/vendor notes
  split into workflow or reference docs.
- Host matches and permissions are as narrow as practical.
- `tabs`, `scripting`, `storage`, and host permissions are justified by actual
  behavior.
- No unrelated scraping, export, background scheduling, or broad automation was
  added.

## Extension And Runtime Boundaries

- Asynchronous tab creation does not rely on `window.open()`.
- Service worker message handlers return `true` when using async
  `sendResponse`.
- Content script isolated-world limits are respected.
- MAIN-world bridge APIs are small, namespaced, validated, and do not expose
  broad page execution.
- Service worker restart behavior does not lose required durable state.
- Real browser phenomena were confirmed in a user-visible Chrome session when
  focus, popup, extension, login state, or vendor UI behavior mattered.
- Playwright/headless evidence is not overstated when the real issue depends on
  the user's visible browser session.

## Page State And Selectors

- The page source of truth is identified.
- DOM scope is identified when relevant: top document, iframe, popup, shadow
  root, virtualized grid, or nested component.
- Selector addresses use stable anchors where possible and include diagnostics
  for missing elements.
- DOM-only edits are not treated as saved state when the page has an internal
  model.
- Selector strategy is stable enough for the target page and includes useful
  diagnostics.
- Polling intervals and observers are bounded and cleaned up.
- Cross-tab storage messages include timestamps or request IDs to avoid stale
  results.

## Safety And Data

- The macro does not bypass authentication, authorization, CAPTCHA, or vendor
  safeguards.
- No credentials, cookies, private URLs, raw page dumps, screenshots with
  sensitive data, or business records are committed.
- Production-sensitive operations are not exercised unless explicitly allowed by
  project instructions.
- Bulk, destructive, financial, inventory, accounting, upload, or irreversible
  actions have a plan and rollback evidence.

## Ecount-Specific Review

- Ecount globals such as `window.gridRegistered` are accessed through a
  MAIN-world bridge.
- Grid value changes update the internal model, such as through `setCell()`, not
  only the DOM.
- Model updates are not conditional on an input element being present.
- Ecount attributes use `data-columnid` where appropriate.
- Registered grid keys are built and diagnosed according to the target page's
  actual structure.

## Completion Evidence

- Syntax, manifest, lint, build, or test checks pass.
- Runtime smoke passes in a safe environment, or skipped runtime verification is
  reported with a concrete reason.
- Changed permissions and host matches are reported.
- Remaining risks are explicit.
