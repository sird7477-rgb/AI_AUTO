# Global Tools

This repository keeps source copies of helper commands that are linked into `~/bin`.

## Commands

- `aiinit`
  - Short alias for `ai-auto-init`
  - Installs the automation template into the current git repository by default
  - Accepts an optional target repository path: `aiinit /path/to/repo`
  - Creates `.omx/reviewer-state`
  - Runs the installed `./scripts/automation-doctor.sh` after installation with the install-time dirty-tree check skipped

- `ai-auto-init`
  - Resolves the ai-lab checkout from the helper symlink target
  - Runs `scripts/install-automation-template.sh` against the current directory or provided target path

- `workspace-scan`
  - Scans git repositories under `~/workspace`
  - Shows branch, dirty status, automation script availability, latest commit, remote presence, and path

Repo-local command installed by the automation template:

- `./scripts/automation-doctor.sh`
  - Diagnoses whether the current repository has the expected automation foundation
  - Suggests repair commands by default
  - Applies only safe non-overwriting setup fixes with `--fix`
  - Checks helper symlinks and whether `~/bin` is on PATH when running inside ai-lab

ai-lab ships its own copy at `scripts/automation-doctor.sh`; the template copy is what gets installed into new projects.

## Link setup

Expected links:

    ~/bin/ai-auto-init -> ~/workspace/ai-lab/tools/ai-auto-init
    ~/bin/aiinit -> ~/workspace/ai-lab/tools/ai-auto-init
    ~/bin/workspace-scan -> ~/workspace/ai-lab/tools/workspace-scan

To recreate the links:

    mkdir -p ~/bin
    ln -sf ~/workspace/ai-lab/tools/ai-auto-init ~/bin/ai-auto-init
    ln -sf ~/workspace/ai-lab/tools/ai-auto-init ~/bin/aiinit
    ln -sf ~/workspace/ai-lab/tools/workspace-scan ~/bin/workspace-scan

Make sure `~/bin` is in PATH:

    export PATH="$HOME/bin:$PATH"

For permanent setup, add this to `~/.bashrc`:

    export PATH="$HOME/bin:$PATH"
