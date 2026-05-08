# Global Tools

This repository keeps source copies of helper commands that are linked into `~/bin`.

## Commands

- `aiinit`
  - Short alias for `ai-auto-init`
  - Installs the automation template into the current git repository

- `ai-auto-init`
  - Runs `scripts/install-automation-template.sh` against the current directory

- `workspace-scan`
  - Scans git repositories under `~/workspace`
  - Shows branch, dirty status, automation script availability, latest commit, remote presence, and path

Repo-local command installed by the automation template:

- `./scripts/automation-doctor.sh`
  - Diagnoses whether the current repository has the expected automation foundation
  - Suggests repair commands by default
  - Applies only safe non-overwriting setup fixes with `--fix`

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
