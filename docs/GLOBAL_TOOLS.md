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
    ln -sf ~/workspace/ai-lab/tools/workspace-scan ~/bin/workspace-scan

Make sure `~/bin` is in PATH:

    export PATH="$HOME/bin:$PATH"

For permanent setup, add this to `~/.bashrc`:

    export PATH="$HOME/bin:$PATH"

`./scripts/install-global-files.sh` also writes the `AI_AUTO()` function to
`~/.config/ai-lab/AI_AUTO.sh` and adds a managed source block to `~/.bashrc`.
Reload the shell or run:

    source ~/.bashrc
