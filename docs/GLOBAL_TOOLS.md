# Global Tools

This repository keeps source copies of helper commands that are linked into `~/bin`.

## Commands

- `AI_AUTO`
  - Shell function installed through `~/.config/ai-lab/AI_AUTO.sh` and sourced from `~/.bashrc`
  - With no arguments, changes the current terminal directory to the AI_AUTO checkout
  - With arguments, forwards to the global helper: `AI_AUTO --path`, `AI_AUTO --status`

- `ai-home`
  - Executable helper used by `AI_AUTO`
  - Prints the AI_AUTO checkout path, cd command, or git status

- `aiinit`
  - Short alias for `ai-auto-init`
  - Installs the automation template into the current git repository by default
  - Accepts an optional target repository path: `aiinit /path/to/repo`
  - Creates `.omx/reviewer-state`
  - Runs the installed `./scripts/automation-doctor.sh` after installation with the install-time dirty-tree check skipped

- `ai-auto-init`
  - Resolves the ai-lab checkout from the helper symlink target
  - Runs `scripts/install-automation-template.sh` against the current directory or provided target path

- `ai-auto-template-status`
  - Compares a project against the current AI_AUTO automation template
  - Reports installed template version, current template version, overall status, and per-managed-file states
  - Does not merge or patch files
  - With `--record-feedback`, records a sanitized project queue item through the trusted AI_AUTO feedback helper only when drift exists

- `ai-refactor-scan`
  - Scans a repository without modifying files and reports likely refactoring candidates
  - Highlights large source files, long Python functions/classes, and import-heavy files
  - Useful before asking AI_AUTO/Codex to split monolithic trading automation code into modules

- `ai-rebuild-plan`
  - Read-only rebuild preflight for `리빌드 플랜`, `리빌딩 플랜`, or `rebuild plan` requests
  - Checks target repo status, automation template status, installed/source domain packs, and refactoring candidates
  - Does not modify files and does not start rebuild execution
  - `리빌드 실행`, `리빌딩 실행`, or `rebuild run` must remain a separate execution request backed by an approved plan artifact

- `workspace-scan`
  - Scans git repositories under `~/workspace`
  - Set `AI_AUTO_WORKSPACE_SCAN_MAX_DEPTH=N` to discover repositories nested deeper than the default depth of 2
  - Shows branch, dirty status, automation script availability, latest commit, remote presence, and path

- `feedback-collect`
  - Lists local `.omx/feedback/queue.jsonl` items from `OMX_FEEDBACK_QUEUE_FILE`, the current git root, registered projects, and workspace-discovered repositories
  - Uses the same `AI_AUTO_WORKSPACE_SCAN_MAX_DEPTH` setting for workspace discovery
  - Treats missing item status as `open`

Repo-local command installed by the automation template:

- `./scripts/automation-doctor.sh`
  - Diagnoses whether the current repository has the expected automation foundation
  - Suggests repair commands by default
  - Applies only safe non-overwriting setup fixes with `--fix`
  - Checks helper symlinks and whether `~/bin` is on PATH when running inside ai-lab

ai-lab ships its own copy at `scripts/automation-doctor.sh`; the template copy is what gets installed into new projects.

ai-lab-only bootstrap command:

- `./scripts/bootstrap-ai-lab.sh`
  - Checks first-time ai-lab checkout setup
  - Verifies source helper scripts, command availability, helper links, and `~/bin` PATH
  - Runs automation-doctor with the dirty-tree check skipped
  - Applies only safe helper-link fixes with `--fix`

- `./scripts/install-global-files.sh`
  - User-facing wrapper for cloned checkouts
  - Intended AI keyword: `전역파일 설치해줘`
  - Creates or repairs safe repo-owned helper symlinks under `~/bin`
  - Adds a managed `AI_AUTO` shell function file under `~/.config/ai-lab` and a small source block to `~/.bashrc`
  - Does not install external programs, configure credentials, run `automation-doctor --fix`, or overwrite non-symlink files

## Link setup

Expected links:

    ~/bin/AI_AUTO -> ~/workspace/ai-lab/tools/ai-home
    ~/bin/ai-auto-init -> ~/workspace/ai-lab/tools/ai-auto-init
    ~/bin/ai-home -> ~/workspace/ai-lab/tools/ai-home
    ~/bin/aiinit -> ~/workspace/ai-lab/tools/ai-auto-init
    ~/bin/ai-register -> ~/workspace/ai-lab/tools/ai-register
    ~/bin/ai-auto-template-status -> ~/workspace/ai-lab/tools/ai-auto-template-status
    ~/bin/ai-refactor-scan -> ~/workspace/ai-lab/tools/ai-refactor-scan
    ~/bin/ai-rebuild-plan -> ~/workspace/ai-lab/tools/ai-rebuild-plan
    ~/bin/feedback-collect -> ~/workspace/ai-lab/tools/feedback-collect
    ~/bin/workspace-scan -> ~/workspace/ai-lab/tools/workspace-scan

To recreate the links:

    ./scripts/install-global-files.sh

Manual equivalent:

    mkdir -p ~/bin
    ln -sf ~/workspace/ai-lab/tools/ai-home ~/bin/AI_AUTO
    ln -sf ~/workspace/ai-lab/tools/ai-auto-init ~/bin/ai-auto-init
    ln -sf ~/workspace/ai-lab/tools/ai-home ~/bin/ai-home
    ln -sf ~/workspace/ai-lab/tools/ai-auto-init ~/bin/aiinit
    ln -sf ~/workspace/ai-lab/tools/ai-register ~/bin/ai-register
    ln -sf ~/workspace/ai-lab/tools/ai-auto-template-status ~/bin/ai-auto-template-status
    ln -sf ~/workspace/ai-lab/tools/ai-refactor-scan ~/bin/ai-refactor-scan
    ln -sf ~/workspace/ai-lab/tools/ai-rebuild-plan ~/bin/ai-rebuild-plan
    ln -sf ~/workspace/ai-lab/tools/feedback-collect ~/bin/feedback-collect
    ln -sf ~/workspace/ai-lab/tools/workspace-scan ~/bin/workspace-scan

Make sure `~/bin` is in PATH:

    export PATH="$HOME/bin:$PATH"

For permanent setup, add this to `~/.bashrc`:

    export PATH="$HOME/bin:$PATH"

`./scripts/install-global-files.sh` also writes the `AI_AUTO()` function to
`~/.config/ai-lab/AI_AUTO.sh` and adds a managed source block to `~/.bashrc`.
Reload the shell or run:

    source ~/.bashrc
