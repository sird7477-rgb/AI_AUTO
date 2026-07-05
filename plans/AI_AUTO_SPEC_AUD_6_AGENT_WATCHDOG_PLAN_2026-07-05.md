# AI_AUTO SPEC-AUD-6 agent watchdog plan

## Contract

Build `ai-agent-watchdog` as an external continuity supervisor for long-running AI
agent panes. It must be agent-agnostic, tmux-pane based, non-destructive, and usable
in observe mode. It must not claim that the current agent can supervise its own
teardown; the tool is installed for an external user/session/keepalive to run.

## Design Decisions

- Detection seam: tmux pane polling is the portable baseline. Native agent hooks are
  out of scope for this first tool because they would bind the implementation to one
  runtime.
- State model: one JSON registry under `${XDG_STATE_HOME:-$HOME/.local/state}/ai-auto/agent-watchdog/registry.json`.
  Entries are keyed by pane id and carry resume file, stall threshold, operation
  silence budget, heartbeat file, rate limit, relaunch command, and counters.
- Execution shape: `tools/ai-agent-watchdog` provides `register`, `list`,
  `observe`, `daemon`, `keepalive-install`, and `keepalive-once`. `observe` performs
  one or more dry-run scans and never injects or relaunches. `daemon` performs the
  same scan loop and may act only when the registered entry allows it.
- Stall safety: pane output silence alone is never enough. A stall requires unchanged
  pane fingerprint plus no heartbeat freshness plus no live child process activity
  signal plus exceeded configured silence budget. A positive heartbeat or active
  child signal suppresses injection.
- Idle safety: resume injection requires two consecutive stable idle observations
  before `tmux send-keys`. Each action is rate-limited per entry and bounded by
  `max_actions`.
- Limit/reset safety: reset text schedules a future resume and logs the decision; it
  does not inject immediately.
- Relaunch safety: relaunch uses an explicit command array from the registry, never a
  shell string. Retry count is bounded. No kill, cleanup, or reaper behavior is added.
- Self-persistence: provide a shell-profile keepalive installer plus `keepalive-once`
  as the WSL2-feasible restart primitive. Tests prove it writes an idempotent managed
  block and that `keepalive-once --dry-run` reports whether it would start a missing
  daemon. Actual long-lived supervision remains external execution, not self-monitoring.

## Files

- Add `tools/ai-agent-watchdog`.
- Wire `scripts/install-global-files.sh` and `scripts/automation-doctor.sh` helper
  inventory/link checks.
- Document in `docs/GLOBAL_TOOLS.md`.
- Add targeted machinery tests in `scripts/verify-machinery.sh`.

## Acceptance Mapping

- AC1/AC4: fixture scans distinguish stall from quiet-but-live using heartbeat/child
  liveness, not output silence alone.
- AC2: idle fixtures require two stable observations before an action is reported.
- AC3: reset fixtures schedule future action instead of immediate injection.
- AC5: `observe` logs decisions and reports `inject=0 relaunch=0`.
- AC6: relaunch attempts stop at configured maximum.
- AC7: pane/runtime label is metadata only; Claude and Codex entries use the same
  decision path.
- AC8: doctor warns on missing helper link.
- AC9: keepalive installer and dry-run one-shot prove an external restart primitive
  without assuming systemd or running the watchdog from the protected session.

## Non-Goals

- No OPS-4 reaper behavior: no killing, orphan cleanup, or destructive process
  management.
- No systemd unit as the required persistence path.
- No automatic registration from tmux/worktree hooks in this slice unless needed by
  tests; manual registration is the first supported contract.
