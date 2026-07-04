# Chrome CDP Access

Use this guidance when a task needs direct browser phenomenon confirmation with
a user-visible Chrome session. This applies to UI work, Chrome extensions,
browser macros, vendor UIs, and other workflows where headless/background
automation may not reproduce focus, popup, session, extension, or permission
behavior.

## Default Position

Attaching tools to a user-launched Chrome remote debugging port is an optional
diagnostic path, not the default verification path. Treat CDP access as
credential-equivalent because the browser may expose cookies, logged-in
sessions, tabs, local storage, and authenticated application state.

Prefer this path when the user and AI need to inspect the same visible page,
DevTools state, popup, extension behavior, iframe, shadow root, selector path,
or page-owned JavaScript model.

## Allowed Use

- bind remote debugging to loopback only, such as `127.0.0.1`
- when attaching to an already running user-launched browser, verify the target
  port is loopback-bound before connecting
- use a unique port per parallel session
- prefer an isolated temporary `--user-data-dir` test profile and remove it
  when the session ends
- use project-owned wrapper scripts for repeated checks so command prefixes,
  ports, profile paths, and target URLs are validated consistently
- record the route, viewport, target environment, and whether the browser state
  came from a user-launched session
- stop at observation or non-destructive smoke checks unless the user explicitly
  approves a credentialed or production action

## Do Not

- bind remote debugging to `0.0.0.0` or a public interface
- reuse a personal/default Chrome profile for automated checks
- assume a production login session is safe to automate
- store cookies, tokens, private URLs, screenshots with secrets, localStorage
  dumps, raw browser state, or business records in repo files, `.omx`, logs,
  review prompts, or feedback queues
- use CDP access to bypass sandbox, credential, deployment, or production
  approval gates

## Evidence To Report

When CDP access is used, report:

- wrapper or command used, without secrets
- loopback binding and port
- profile isolation decision
- target route or page class
- viewport and browser state source
- whether the action was observation-only, non-destructive smoke, or explicitly
  approved credentialed/production work
- what DOM, console, storage, network, extension, or page-model evidence was
  observed

## Micro-Plan Before CDP

Before opening or attaching to a CDP session, record a Browser QA micro-plan with
these rows: `layout`, `click_targets`, `input_handling`, `alerts_errors`,
`sync_update`, and `business_mapping`. Each row must be marked `evidence` or
`not_applicable`.

The micro-plan does not grant credential authority. Loopback binding, isolated or
user-launched browser state, approval, and no cookie/token export remain required
for CDP access.

Project-specific wrappers should keep the command prefix stable while moving
changeable values into validated arguments or `.env` files that are not
committed. The wrapper is a friction-reduction surface only; it must not widen
what the agent is allowed to do.
