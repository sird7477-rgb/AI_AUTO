# Codex Drift Notice Design

This design covers an opt-in `codex` shadowing surface for projects that have
AI_AUTO automation files installed.

## Goal

When a user starts a shell session and first runs `codex` from a project where
AI_AUTO is installed, print a short update recommendation immediately if the
project-local AI_AUTO template differs from the current AI_AUTO home checkout.

The notice must be read-only. It must not update files, record feedback, change
Codex arguments, or weaken normal approval gates.

## Decision

Use an opt-in shell function, not a `~/bin/codex` executable symlink.

The installer should resolve the real Codex executable before defining the shell
function and write that absolute path into a managed shell integration file. The
function then:

1. detects the current git root
2. checks whether the root has `AI_AUTO_TEMPLATE_VERSION`
3. compares it with the AI_AUTO home template using `ai-auto-template-status`
4. prints a compact warning to stderr only when drift exists and the current
   shell session has not already shown it for that project
5. executes the real Codex binary with the original arguments

This keeps the official `codex` CLI as the execution authority. AI_AUTO only
adds a local preflight notice.

## User Experience

Example warning:

```text
[AI_AUTO] automation template update recommended for /path/to/project
[AI_AUTO] installed: 2026.05.17  current: 2026.05.18  status: customized_or_outdated
[AI_AUTO] latest patch note: 2026.05.20.2
[AI_AUTO] review notes: /path/to/ai-lab/templates/automation-base/docs/PATCH_NOTES.md
[AI_AUTO] inspect: ai-auto-template-status /path/to/project
```

No notice is printed when:

- the current directory is not inside a git repository
- the repository does not have `AI_AUTO_TEMPLATE_VERSION`
- `ai-auto-template-status` reports `status: current`
- `AI_AUTO_CODEX_DRIFT_NOTICE=0` is set
- the same shell session already printed a drift notice for that project

## Safety Rules

- Do not install or replace a `codex` executable file in `~/bin`.
- Do not call `codex` through PATH from inside the function; use the resolved
  real executable path to avoid recursion.
- Do not run `ai-auto-template-status --record-feedback` from the shadowing
  path.
- Do not auto-merge, patch, or copy template files.
- Do not block Codex startup if status detection fails.
- Do not print the same project drift notice repeatedly in one shell session.
- Preserve Codex arguments, stdin, stdout, stderr, and exit code.
- Print notices to stderr so normal stdout workflows remain usable.
- Keep all generated shell integration blocks marker-bounded and refuse to
  overwrite unmanaged user files.

## Installer Shape

Add a new explicit flag rather than changing current global install behavior:

```bash
./scripts/install-global-files.sh --install-codex-drift-notice
```

The flag may write:

- `~/.config/ai-lab/codex-drift-notice.sh`
- a managed source block in `~/.bashrc`

It should refuse installation when:

- `codex` is not available
- the resolved Codex path points to an AI_AUTO-managed wrapper
- the target shell integration file exists and is not AI_AUTO-managed
- `.bashrc` markers are unbalanced

## Function Sketch

```bash
codex() {
  local real_codex="/absolute/path/to/codex"
  local patch_notes="/absolute/path/to/ai-lab/templates/automation-base/docs/PATCH_NOTES.md"
  local repo_root=""
  local status_output=""
  local notice_key=""
  local latest_note=""

  if [ "${AI_AUTO_CODEX_DRIFT_NOTICE:-1}" != "0" ] &&
    command -v git >/dev/null 2>&1 &&
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" &&
    [ -f "${repo_root}/AI_AUTO_TEMPLATE_VERSION" ] &&
    command -v ai-auto-template-status >/dev/null 2>&1; then
    notice_key="$(printf '%s' "${repo_root}" | sha256sum | awk '{print $1}')"
    case "${AI_AUTO_CODEX_DRIFT_NOTICE_SEEN:-}" in
      *"|${notice_key}|"*) ;;
      *)
        status_output="$(ai-auto-template-status "${repo_root}" 2>/dev/null || true)"
        AI_AUTO_CODEX_DRIFT_NOTICE_SEEN="${AI_AUTO_CODEX_DRIFT_NOTICE_SEEN:-}|${notice_key}|"
        if printf '%s\n' "$status_output" | grep -q '^status: customized_or_outdated'; then
          latest_note="$(awk '/^## / {print; exit}' "${patch_notes}" 2>/dev/null || true)"
          printf '%s\n' "[AI_AUTO] automation template update recommended for ${repo_root}" >&2
          printf '%s\n' "$status_output" | awk '
            /^(installed_version|current_version|status): / {print "[AI_AUTO] " $0}
          ' >&2
          [ -n "${latest_note}" ] &&
            printf '%s\n' "[AI_AUTO] latest patch note: ${latest_note#\#\# }" >&2
          printf '%s\n' "[AI_AUTO] review notes: ${patch_notes}" >&2
          printf '%s\n' "[AI_AUTO] inspect: ai-auto-template-status ${repo_root}" >&2
        fi
        ;;
    esac
  fi

  "$real_codex" "$@"
}
```

The implementation should generate this file with the actual resolved
`real_codex` and `patch_notes` paths. The sketch is not meant to be copied
verbatim into `.bashrc`.

## Test Plan

- fake `codex`, `git`, and `ai-auto-template-status` in a temporary PATH
- verify no notice outside git repositories
- verify no notice when `AI_AUTO_TEMPLATE_VERSION` is missing
- verify no notice when status is `current`
- verify drift notice is printed to stderr for `customized_or_outdated`
- verify the latest patch-note heading and patch-note path are printed
- verify repeated `codex` calls in the same shell session show the notice once
- verify `AI_AUTO_CODEX_DRIFT_NOTICE=0` suppresses the notice
- verify original arguments are forwarded unchanged
- verify the real Codex exit code is preserved
- verify installer refuses unmanaged existing integration files
- verify installer refuses unbalanced `.bashrc` markers

## Rejected Alternatives

- `~/bin/codex` wrapper: too easy to create recursion, override the official CLI,
  or interfere with package manager updates.
- automatic project patching after drift detection: turns a read-only notice into
  cross-project mutation and bypasses normal review gates.
- always recording feedback on every `codex` launch: noisy and writes project
  state from a command that users expect to start Codex.
