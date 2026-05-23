# Browser Macro Workflow Pack

Use this as source material for the target project's `docs/WORKFLOW.md` after
confirming that the project automates an existing browser UI.

## Onboarding Questions

- Which automation surface is in scope: Chrome extension, userscript,
  bookmarklet, Playwright macro, injected script, or mixed?
- Which browser and extension manifest version are targeted?
- Which pages, URL match patterns, and host permissions are required?
- Does the project own the target frontend source, or is it manipulating a
  vendor/third-party UI?
- What is the page's source of truth for the changed value: DOM, framework
  state, grid model, form model, localStorage, IndexedDB, network API, or page
  global?
- Is a MAIN-world bridge required to access page-owned globals?
- What selectors are stable, and what diagnostics should print when selectors
  fail?
- Which environment is safe for smoke testing?
- Can the macro touch real orders, inventory, accounting, deletes, messages,
  uploads, personal data, or irreversible state?
- What rollback or cleanup action exists if the macro partially runs?
- Do Ecount-specific rules apply?

## Development Loop

1. Identify the exact browser surface and affected files: manifest, service
   worker, content script, injected page script, Playwright script, or helper.
2. Observe the live runtime before assuming the implementation path. Record
   which DOM scope contains the target and what rerenders, navigation, or
   virtualization can reset the change.
3. Identify the page source of truth before editing behavior.
4. Keep permissions, host matches, selectors, and storage keys as narrow as the
   workflow allows.
5. Add or preserve diagnostics for failed selectors, missing page globals,
   missing tabs, stale messages, and timeout paths.
6. Test the smallest safe workflow in a non-production environment when
   available.
7. Run the standard project verification and review gate before presenting a
   commit candidate.

## Planning-First Macro Method

Before coding, the AI should present a short plan that covers:

- DOM scope: top document, iframe, popup, shadow root, virtualized grid, or
  nested component
- selector address: primary selector, fallback selector, and diagnostic log for
  selector failure
- state source of truth: DOM, framework state, grid/form model, page global,
  storage, or network/API result
- browser execution boundary: content script, service worker, MAIN-world bridge,
  page script, userscript, or Playwright runner
- live investigation tool: user-visible Chrome remote debugging, DevTools,
  extension inspection page, or project smoke runner
- permission changes and why each is needed
- async lifecycle: observer/polling timeout, duplicate action guard, stale
  result guard, tab close cleanup
- safe smoke scenario and rollback or cleanup path

This planning step is mandatory when selector addresses, DOM scope, or state
model are unknown.

## Tooling And Stack Selection

Choose the smallest tool that can observe or control the required browser
boundary:

- Chrome Extension Manifest V3: durable user workflow, content scripts,
  service workers, extension storage, permissions, context menus, alarms, or
  cross-tab coordination.
- Content script: DOM reads, DOM events, lightweight UI injection, and page
  detection inside the isolated extension world.
- MAIN-world bridge or injected page script: page-owned globals, grid/form
  model APIs, framework internals, or vendor JavaScript state that content
  scripts cannot access directly.
- Service worker: tab creation, tab closing, long-lived extension messaging,
  alarms, downloads, context menus, and browser APIs that should not run in the
  page context.
- Userscript or bookmarklet: small operator-driven macros where extension
  packaging, permissions, and store distribution are unnecessary.
- Playwright test runner: repeatable smoke tests, deterministic project-owned
  UI checks, screenshots, trace capture, and CI-friendly browser verification.
- Playwright over CDP: inspection or automation attached to a user-visible
  Chrome debugging session when focus, popups, extension behavior, login state,
  or operator confirmation matters.
- DevTools Protocol clients: low-level DOM, runtime, console, network,
  storage, target, and extension inspection when Playwright's high-level API is
  not enough.
- Chrome DevTools: authoritative manual evidence for element paths, iframes,
  shadow roots, event listeners, storage, console globals, rerenders, and
  network calls.
- Browser extension inspection pages: service worker logs, content script
  injection status, permissions, extension errors, and message lifecycle.
- Static checks: `node --check`, manifest JSON parsing, permission/host-match
  checks, grep-based bridge-boundary checks, and selector-name regression
  checks.

Avoid choosing a heavier stack just because it is available. For example,
prefer a content script for simple DOM observation, a MAIN-world bridge only
when page-owned JavaScript state is required, and CDP only when the user-visible
browser state is part of the evidence.

## Bridge Contract

When a macro crosses execution worlds, document the bridge before expanding it:

- request and response event or message names
- payload fields, expected types, and validation
- timeout, retry, and stale-response behavior
- error shape and diagnostic fields
- source-of-truth API being called on the page side
- sensitive fields that must never be logged
- whether the call is observation-only, visual DOM feedback, or persistent
  page-model mutation

## Live Phenomenon Confirmation

For real browser macro work, prefer confirming the phenomenon in a browser the
user can see and operate. Use `docs/CHROME_CDP_ACCESS.md` as the common safety
and evidence contract for Chrome remote debugging/CDP access:

1. Ask the project runbook or user for the approved Chrome remote debugging
   wrapper or command.
2. Attach inspection or Playwright tooling to that user-visible Chrome session
   through CDP.
3. Use DevTools-style evidence: selected element path, attributes, iframe/shadow
   scope, console-visible page globals, storage keys, network calls, and
   rerender triggers.
4. Use headless/background Playwright only for project-owned smoke tests where
   login/session, extension behavior, popups, and focus behavior are known not
   to affect the result.

## Basic Vs Detailed Guidance

Use a two-level structure in target projects:

- `AGENTS.md`: short rules that must always be followed, such as safety
  boundaries, service-worker tab creation, isolated-world bridge rules, selector
  discipline, and completion gates.
- `docs/WORKFLOW.md` or linked references: detailed selector maps, page
  observations, bridge event names, storage keys, troubleshooting logs, and
  vendor-specific findings.

If a rule is only true for one page, popup, selector, or customer workflow, put
it in a detailed reference rather than the basic agent instructions.

## DOM And Selector Investigation

Browser macro failures often come from the running page, not from static code.
For non-trivial changes:

1. Confirm whether the target is in the top document, iframe, popup, shadow DOM,
   virtualized table, or rerendered component.
2. Prefer selectors based on stable data attributes, roles, labels, column
   headers, row keys, and nearby structure.
3. Avoid brittle full CSS paths or nth-child chains unless the page offers no
   stable anchors.
4. Print available attributes, nearby headers, row identifiers, and model keys
   when a lookup fails.
5. Verify whether a visible DOM edit persists after focus, rerender, navigation,
   or save.
6. Prefer DevTools inspection against the user's visible browser when selector
   or model behavior is uncertain.

## Chrome Extension Workflow

- For tab creation from asynchronous code, send a message to the service worker
  and call `chrome.tabs.create({ active: false })` there.
- For async `sendResponse`, return `true` from the message listener.
- Keep service worker state resilient to restarts; persist necessary durable
  state in extension storage or page storage with explicit timestamps.
- Use MAIN-world scripts only for page-owned JavaScript access. Keep the bridge
  API small, namespaced, and validated.

## Frontend Macro Workflow

- Prefer direct project-owned APIs when the project owns the target frontend.
- For vendor UI manipulation, treat the DOM as unstable and add fallback
  diagnostics before widening selectors.
- Never treat visual success as proof when the page has a separate internal
  model. Verify the resulting model, saved value, or post-action page state.
- Bound polling and observer lifetimes. Clear intervals and disconnect observers
  on completion, timeout, or navigation.

## Ecount Workflow

For Ecount ERP projects:

- use the Ecount reference guidance before editing extension code
- route Ecount global access through a MAIN-world bridge
- update grid internal state with `setCell()` or the confirmed page API
- use Ecount's actual attributes, especially `data-columnid`
- compute the registered grid key from the popup and grid identifiers when
  required by the page
- keep logs that reveal available grid keys and element attributes without
  copying business data

## Browser-Macro Completion Evidence

Report:

- automation surface and changed files
- permissions or host matches changed
- page source-of-truth decision
- selector/model diagnostics added or preserved
- syntax/manifest check result
- smoke path result, or the concrete reason runtime smoke was unavailable
- any production-sensitive paths that were not exercised

## Default Non-Goals

Unless explicitly requested, do not:

- broaden host permissions beyond the target workflow
- bypass authentication, CAPTCHA, authorization, or vendor safeguards
- run against production data
- add background jobs or unattended scheduling
- add broad scraping, export, or data harvesting behavior
- change unrelated UI workflows
