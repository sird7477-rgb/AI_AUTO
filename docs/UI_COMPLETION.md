# UI Completion Pack

Use this pack during onboarding only when the final project outcome includes a
user-facing or operator-facing UI. If the project is API-only, CLI-only,
library-only, or a backend service with no required UI, record UI as a non-goal
in `AGENTS.md` and `docs/WORKFLOW.md`.

## Onboarding Questions

Clarify these before implementing UI work:

- who will use the UI
- what primary workflow must be completed on the first screen
- whether the UI is customer-facing, internal operations, admin, dashboard, or
  prototype-only
- required viewports: desktop, mobile, tablet, kiosk, embedded, or responsive
- required states: empty, loading, success, validation error, server error,
  permission denied, offline, and destructive confirmation
- required data freshness and real-time behavior
- accessibility expectations, at minimum keyboard navigation and readable
  contrast
- visual source of truth: existing design system, brand guide, screenshots, or
  local product conventions
- frontend stack and package commands
- screenshot or browser smoke checks that prove completion
- whether Playwright should launch its own isolated browser, use a project-owned
  wrapper script, or attach to a user-launched Chrome remote debugging port
- field-test incident evidence: route, viewport, screenshot, console status,
  network status, operator flow step, and whether the next action is possible

## Workflow Additions

When UI is in scope, add these steps to the project workflow:

1. define the primary user journey and expected completion state
2. inspect existing design and component patterns before adding new UI
3. implement the smallest end-to-end slice that proves the journey
4. cover important empty/loading/error/success states
5. run frontend lint/typecheck/build/test commands when available
6. run browser or screenshot smoke checks for the main journey
7. inspect the UI at the required viewports before claiming completion
8. when UI is part of field-test monitoring, write incident evidence according
   to `docs/INCIDENT_OPS.md`
9. include screenshots, browser check results, or exact smoke evidence in the
   completion report

## Verification Patterns

Adapt `scripts/verify.sh` to the project stack. Prefer real project commands
over placeholders.

Common checks:

```bash
npm run lint
npm run typecheck
npm test
npm run build
npx playwright test
```

Use only the commands that exist and are meaningful for the project. Do not add
frontend dependencies during onboarding unless the user approves them.

For repeated browser checks, prefer a project-owned wrapper script with a narrow
approved prefix instead of long inline commands with changing URLs or
environment variables. The wrapper should validate required inputs, print the
target environment, and call the real Playwright command without accepting
arbitrary shell fragments. Keep credentialed, production, destructive, and
dependency-installing paths behind explicit approval.

For static HTML or simple browser apps, a lighter smoke check may be enough:

```bash
test -f index.html
```

For apps with a dev server, verify at least one real page:

```bash
npm run build
npx playwright test --project=chromium
```

## Playwright CDP Access

Attaching Playwright to a user-launched Chrome remote debugging port is an
optional diagnostic path, not the default browser verification path. Treat CDP
access as credential-equivalent because the browser may expose cookies, logged
in sessions, tabs, local storage, and authenticated application state.

Allowed use:

- bind remote debugging to loopback only, such as `127.0.0.1`
- when attaching to an already running user-launched browser, verify the target
  port is loopback-bound before connecting
- use a unique port per parallel session
- prefer an isolated temporary `--user-data-dir` test profile and remove it
  when the session ends
- record the route, viewport, target environment, and whether the browser state
  came from a user-launched session
- stop at observation or non-destructive smoke checks unless the user
  explicitly approves a credentialed or production action

Do not:

- bind remote debugging to `0.0.0.0` or a public interface
- reuse a personal/default Chrome profile for automated checks
- assume a production login session is safe to automate
- store cookies, tokens, private URLs, screenshots with secrets, or raw browser
  state in repo files, `.omx`, logs, review prompts, or feedback queues
- use CDP access to bypass sandbox, credential, deployment, or production
  approval gates

Project-specific wrappers should keep the command prefix stable while moving
changeable values into validated arguments or `.env` files that are not committed.
The wrapper is a friction-reduction surface only; it must not widen what the
agent is allowed to do.

## Completion Criteria

UI work is complete only when:

- the primary workflow works without relying on hidden manual steps
- text fits its containers at required viewport sizes
- interactive controls have visible disabled, hover/focus, loading, and error
  states where applicable
- the implementation follows the existing design system or explicitly recorded
  project UI rules
- browser console errors are checked when a browser test or manual browser smoke
  is part of the project workflow
- any Playwright CDP run documents loopback binding, isolated profile decision,
  target environment, and credential/production boundary
- screenshots or browser test results are captured for the changed main path
- field-test UI incidents include route, viewport, screenshot, console/network
  status, operator flow step, and recoverability evidence
- `./scripts/verify.sh` and `./scripts/review-gate.sh` pass, or any degraded
  trust state is reported explicitly

## Non-Goals

Do not create a landing page, marketing page, animation layer, design system, or
new frontend stack unless the project outcome requires it or the user explicitly
requests it.
