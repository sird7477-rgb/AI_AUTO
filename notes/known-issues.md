# Known Issues

## Codex CLI EPERM during agent-run doctor

During the single-agent rehearsal, `omx doctor` reported a Codex CLI EPERM failure from the agent-run context.

The issue did not reproduce in the user's interactive terminal afterward:

```text
Results: 14 passed, 1 warnings, 0 failed
Current handling:

Treat as context-dependent and non-blocking unless it reproduces.
If it occurs again, compare the agent-run shell with the interactive shell.
Check which codex, codex --version, ls -l "$(which codex)", and omx doctor.
Do not claim environment failure unless the issue reproduces in the interactive terminal.

Remaining known warning:

Explore Harness warning: Rust harness sources are packaged, but no compatible packaged prebuilt or cargo was found.
