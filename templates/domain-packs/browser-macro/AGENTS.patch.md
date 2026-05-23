# Browser Macro Agent Guidance Patch

Merge these rules into the target project's `AGENTS.md` only when the project is
confirmed to automate an existing browser UI through an extension, injected
script, or browser automation macro.

## Browser Automation Scope

Before changing browser automation code, confirm:

- target surface: Chrome extension, content script, service worker, userscript,
  bookmarklet, Playwright macro, or injected page script
- target browser and extension manifest version
- affected pages, URL match patterns, and host permissions
- whether the project owns the target frontend source or only manipulates a
  third-party or vendor UI
- whether changes affect visible DOM only or a page-owned JavaScript data model
- whether user credentials, production data, financial records, orders,
  inventory, accounting, or personal data can be touched

## Guidance Layering

- Keep `AGENTS.md` short: only durable rules, safety boundaries, and completion
  gates belong here.
- Put detailed browser workflows, selector maps, page-model discoveries, and
  vendor-specific notes in linked docs or references.
- Do not paste long DOM dumps, page observations, or one-off debugging notes
  into `AGENTS.md`.
- When guidance grows, split it into a basic rule plus a detailed reference and
  link the reference from the workflow.

## Safety Boundaries

- Do not automate credential entry, permission escalation, CAPTCHA bypass,
  anti-bot bypass, or access-control bypass.
- Do not run macros against production-like data unless the user explicitly
  identifies the safe environment and allowed operation.
- Do not store secrets, session cookies, private URLs, customer data, copied
  page dumps, or raw business records in docs, prompts, logs, screenshots, or
  feedback queues.
- Treat bulk edits, order submission, inventory movement, accounting changes,
  deletes, and irreversible workflow transitions as fail-closed operations that
  require explicit project instructions and rollback evidence.

## Chrome Extension Patterns

- Do not call `window.open()` from asynchronous contexts such as
  `MutationObserver`, `Promise.then`, `setTimeout`, `setInterval`, or
  `async/await`. Route tab creation through the extension service worker with
  `chrome.tabs.create({ active: false })` when background tab opening is needed.
- When a `chrome.runtime.onMessage` handler responds asynchronously, return
  `true` from the listener.
- Keep `manifest.json` permissions and `host_permissions` minimal and explicit.
  Add `tabs` only when the specific tab operation requires it, such as reading
  sensitive tab properties, querying tabs, or closing tabs; do not broaden
  permissions just because a reference example includes `chrome.tabs.create()`.
- Remember that content scripts run in an isolated world. Access to page-owned
  globals requires a MAIN-world bridge script and an explicit event/message
  boundary.
- Prefer typed, namespaced custom events or runtime messages over ad hoc global
  variables for crossing boundaries.

## Frontend Manipulation Principles

- Treat browser macro work as runtime integration with a live UI, not ordinary
  application coding. The visible DOM, extension process, page world, browser
  permissions, and page-owned model can all disagree.
- Do not assume a DOM text/input edit updates the application state. Identify
  the target page's source of truth first: DOM, framework state, grid model,
  form model, localStorage, IndexedDB, network API, or page global.
- When the page has an internal model, update the internal model through the
  page's supported API, then update DOM only for immediate visual feedback.
- Treat selector addresses as first-class design inputs. Confirm the DOM scope
  first: top document, iframe, popup, shadow root, virtualized grid, or nested
  component.
- Use stable selectors from semantic attributes, data attributes, roles, labels,
  or nearby structure. Avoid brittle absolute paths unless there is no stable
  alternative and diagnostics prove the page shape.
- Add diagnostics that print available attributes, nearby headers, row keys, or
  registered model keys when a selector fails, while avoiding business data.
- Timestamp cross-tab or cross-window localStorage messages so stale results are
  ignored.
- Avoid broad polling loops. Bound intervals with timeouts and clear them on
  success, failure, tab close, or navigation.

## Planning Method

Before implementation, the AI should propose a short macro plan containing:

- target page, popup, iframe, or shadow-root scope
- selector address strategy and fallback diagnostics
- source-of-truth decision for each changed value
- browser boundary: content script, service worker, MAIN-world bridge, or test
  runner
- permission and host-match changes
- live investigation approach: user-visible Chrome remote debugging, extension
  devtools, page console, or project smoke runner
- smallest safe smoke path and rollback/cleanup path

Do not start from code edits when these facts are unknown and materially affect
the implementation.

## Live Investigation Tools

- Follow `docs/CHROME_CDP_ACCESS.md` for Chrome remote debugging and CDP access.
- Prefer user-visible Chrome remote debugging for reproducing browser-macro
  issues with the operator. The user should be able to see the same page, login
  state, popups, tabs, and console behavior being inspected.
- Do not default to background or headless Playwright for phenomenon
  confirmation on real vendor UIs. Headless checks can miss popup focus,
  extension, permission, iframe, and user-session behavior.
- Use Playwright through Chrome DevTools Protocol only when the project has a
  user-launched debugging browser or a project-owned wrapper for that mode.
- Use DevTools console, element inspector, event listeners, storage inspection,
  and network observation as first-class evidence when diagnosing selectors,
  page globals, internal models, and rerenders.

## Common Pain Points

- popup blockers when tab creation happens outside a direct user gesture
- Manifest V3 service worker restarts losing in-memory state
- content script isolated-world access hiding page globals
- page rerenders overwriting DOM-only edits
- virtualized grids where visible rows do not equal the underlying data model
- shadow DOM, iframes, popups, and nested documents changing selector scope
- stale localStorage or cross-tab responses being consumed by the wrong request
- async observer loops opening duplicate tabs or applying duplicate actions
- vendor UI changes breaking brittle selectors without actionable diagnostics

## Ecount-Specific Rules

When the target is Ecount ERP, read the project-local Ecount guidance or the
ai-lab reference before editing. At minimum:

- use a MAIN-world bridge for Ecount globals such as `window.gridRegistered`
- call the grid model method such as `setCell()`; do not rely on DOM-only edits
- call model updates regardless of whether an input element is currently present
- use `data-columnid`, not `data-column-id`, when reading Ecount column IDs
- build grid keys from `popupId + gridEl.id` when that is how the page registers
  grids
- log available grid keys and element attributes when Ecount lookup fails

## Verification Rule

Browser macro work is not complete until project-specific verification passes.
At minimum, verification should cover syntax/manifest checks and one smallest
safe smoke path for the affected browser workflow when a test environment is
available.
