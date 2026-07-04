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

- `ai-auto`
  - The GLOBAL launcher; operates on the project in the current directory
  - `ai-auto setup [dir]` adopts global AI_AUTO mode: installs baked-path
    `pre-commit`/`post-commit`/`pre-push` hook shims, adds `.omx/` to the project's local
    git exclude, detects the project domain, and de-pollutes any byte-identical
    leftover vendored framework files (`git rm`, staged; modified/symlinked files
    are kept and reported). It never vendors files and never auto-commits
  - `ai-auto gate` / `verify` / `doctor` run `review-gate.sh` / `verify.sh` /
    `automation-doctor.sh --project` from the global engine against `$PWD`
  - `aiinit` is a legacy symlink kept pointing at this launcher; prefer
    `ai-auto setup`

- `ai-domain-pack`
  - Reports or refreshes optional domain-pack references under `.omx/domain-packs/`
  - Uses sidecar manifests under `.omx/domain-packs/.manifest/` for a three-way comparison between installed copy, install-time baseline, and current AI_AUTO source
  - `status` is read-only; `refresh` is dry-run by default and writes only with `--apply`
  - Clean managed copies can be updated mechanically, exact-match legacy copies can be adopted, and locally modified, dirty legacy, unreadable, or deliberately removed packs fail closed
  - Never merges pack content into project `AGENTS.md`, `docs/WORKFLOW.md`, or `scripts/verify.sh`
  - Advanced/test-only source overrides may set `AI_AUTO_DOMAIN_PACK_SOURCE_OVERRIDE`; normal use should read source packs from the AI_AUTO checkout

AI review context defaults to `REVIEW_CONTEXT_DETAIL=auto`. Small tracked diffs
use a lightweight diff-centered context; set `REVIEW_CONTEXT_DETAIL=full` for
reviews that need planning artifacts or full workflow reference file excerpts.

- `ai-gstack-contract`
  - Runs one side-effect-free GStack benchmark adoption contract against JSON stdin
  - Supported contracts: `product`, `browser-qa`, `retro`, `persona`, `security-release`, `parallel`
  - Does not install GStack, create agents, start worktrees, push notes, deploy, or modify files

- `ai-refactor-scan`
  - Scans a repository without modifying files and reports likely refactoring candidates
  - Highlights large source files, long Python functions/classes, and import-heavy files
  - Useful before asking AI_AUTO/Codex to split monolithic trading automation code into modules

- `ai-rebuild-plan`
  - Read-only rebuild preflight for `리빌드 플랜`, `리빌딩 플랜`, or `rebuild plan` requests
  - Checks target repo status, installed/source domain packs, and refactoring candidates
  - Does not modify files and does not start rebuild execution
  - `리빌드 실행`, `리빌딩 실행`, or `rebuild run` must remain a separate execution request backed by an approved plan artifact

- `ai-split-plan`
  - Creates a JSON plan for conservative Python top-level function/class extraction
  - Can read `.omx/domain-packs/<name>/split-rules.json` to propose module moves without hand-picking symbols
  - Does not modify files

- `ai-split-dry-run`
  - Prints the diff for an approved Python split plan
  - Does not modify files

- `ai-split-apply`
  - Applies a Python split plan only with `--execute-approved-plan` and completed approval-gate fields
  - Creates rollback backups under `.omx/rebuild/backups/`
  - Moves top-level Python functions/classes only; it does not rewrite imports or call sites

- `ai-plan-status`
  - Read-only status check for a full-schema interview/plan artifact
  - Computes `ready_to_execute`, ambiguity, missing fields, open questions, stale evidence, and next action
  - May write `.omx/state/plan-status.json` with `--write-state`

- `ai-interview-record`
  - Records one interview answer into a JSON plan artifact
  - Keeps user decisions separate from AI assumptions
  - Does not approve execution

- `ai-plan-review`
  - Read-only plan quality check built on the same computed status as `ai-plan-status`
  - Reports whether the plan needs work before execution
  - Does not approve execution

- `ai-plan-export`
  - Exports a concise execution summary from a plan artifact
  - Includes status, blockers, next action, and a reminder that export is not approval

- `workspace-scan`
  - Scans git repositories under `~/workspace`
  - Set `AI_AUTO_WORKSPACE_SCAN_MAX_DEPTH=N` to discover repositories nested deeper than the default depth of 2
  - Shows branch, dirty status, automation script availability, latest commit, remote presence, and path

- `feedback-collect`
  - Lists local `.omx/feedback/queue.jsonl` items from `OMX_FEEDBACK_QUEUE_FILE`, the current git root, registered projects, and workspace-discovered repositories
  - Uses the same `AI_AUTO_WORKSPACE_SCAN_MAX_DEPTH` setting for workspace discovery
  - Treats missing item status as `open`
  - `--proposals` shows only template-improvement proposals (items whose `repeat_key` starts with `template-proposal:`). This is the project->home upstream channel: instead of changing the shared AI_AUTO baseline directly, a project records `record-feedback --type improvement --repeat-key template-proposal:<slug> --summary ...`, and the home triages them with `feedback-collect --proposals` (which scans registered projects + the workspace by default)

- `feedback-resolve`
  - Resolves local feedback queue items by `repeat_key` across the same discovery surface as `feedback-collect`
  - Dry-run is the default; pass `--write` or `--apply` to mutate queue files
  - Write mode requires both `--note` and `--source` so queue closure keeps an audit trail
  - Uses per-queue locks, refuses unknown keys and secret-like notes/sources, and avoids timestamp churn when the same resolution is already recorded

- `knowledge-collect`
  - Lists validated `.omx/knowledge/drafts/*.md` from the current repository and any explicit `--project` paths
  - Broad review is opt-in with `--include-registry` or `--include-workspace`
  - Vault writes require `--project <repo> --vault-dir <vault-path>/AI_AUTO --push`; local/private drafts additionally require `--allow-local-private`
  - Successful pushes mark both the local draft and vault copy with `sync_state: pushed_to_obsidian` plus `obsidian_pushed_hash`; normal listing hides unchanged pushed notes, while `--include-pushed` shows them for audit

- `micro-work`
  - `micro-work validate <file.json>` checks a MicroWork unit definition (goal, scope_paths, smallest_useful_wedge, non_goals, required_evidence, completion_criteria)
  - Read-only: validates shape, reports `scope_drift`/`non_goal_leak` against `--changed` paths, and never executes work or holds completion authority
  - `scripts/micro-check.sh` is a thin repo wrapper that validates `.omx/micro/current.json` (or `MICRO_WORK_FILE`) against the current git changes

- `ai-worktree` (+ the `aiwt` shell function)
  - Create-or-enter a per-terminal git worktree (`aiwt <name>` → `<repo>-<name>` on
    branch `wt/<name>`), so concurrent terminals on one project never share a working
    tree or `.omx` review/validation state. `--list` / `--remove <name>` (refuses the
    current/primary tree); prints the path on stdout for the `aiwt` cd.

- `ai-tmux-worktree`
  - Hook-driven (not for manual use): once `install-global-files.sh
    --install-tmux-worktree` has added the `~/.tmux.conf` hook block, each tmux
    **window** in an AI_AUTO project gets its own worktree, auto-created on open (the
    pane lands in it) and auto-removed on close — but only if clean; uncommitted or
    unpushed work is kept and logged, never forced. On by default; set
    `AI_AUTO_TMUX_WORKTREE=0` to opt out, `AI_AUTO_TMUX_WORKTREE_KEEP=1` to keep all.

- `ai-kb-retrieval-hook`
  - Hook-driven (not for manual use): once `install-global-files.sh --install-kb-retrieval-hook`
    has registered it as a Claude Code `UserPromptSubmit` hook, it reads the prompt and injects a
    capped slim-KB routing block ONLY when both gates pass — the project profile is a registered
    domain (Odoo) AND the prompt matches that domain's keyword classifier
  - Calls `knowledge-retrieve` (slim pointers only, advisory) and is **fail-open**: any error,
    missing tool, unknown domain, generic prompt, or no match → no output, never blocks the prompt

- `ai-project-profile`
  - Detects a repo's domain from repo signals (Odoo = `custom-addons/` with module
    `__manifest__.py`) and records it in machine-local `.omx/project-profile.json`
    (`{domain, version, addons, detected_by, confirmed_at}`)
  - `detect` (print, no write) · `write` (detect + persist, preserving an
    interview-confirmed entry) · `read` · `domain`. Advisory metadata only — changes no project
    behaviour; read by the domain-gated retrieval hook and written by `ai-auto setup` for
    detected Odoo projects

- `knowledge-capture`
  - Harvests reusable findings the author already distilled into sanitized local knowledge
    drafts (`.omx/knowledge/drafts/`, the schema `knowledge-collect` reads) — instead of an
    end-of-session "what did we learn?" recall
  - `harvest [--since <ref>] [--write]` scans commits carrying single-line Lore-style Finding
    trailers (`Finding:`, `Finding-Evidence:`, `Finding-Scope:`, optional `Finding-NotWhen:` /
    `Finding-Surface:` / `Finding-Share:`); `list` is dry-run
  - **Reuse-test gate** (junk-vault defence): a finding is drafted only if it states rule +
    evidence + scope; missing any → skipped. All harvested text is secret/path-redacted, and
    drafts are `local_private` unless `Finding-Share: shareable`. Push to the vault stays a
    separate, user-triggered step — capture is local only

- `knowledge-retrieve`
  - The PULL worker (symmetric to `knowledge-collect`): `knowledge-retrieve <keywords>` searches a
    registered domain KB's slim index (Odoo first) and prints a CAPPED routing block of slim-file
    pointers — never raw content
  - `--domain` (else read from `.omx/project-profile.json`), `--vault-dir` (else
    `obsidian.ai_auto_vault_dir`), `--limit` (default 3), `--json`. Output is tagged ADVISORY —
    current repo evidence overrides any KB note
  - **Fail-graceful**: no reachable vault / unknown domain / no match / no keywords → prints nothing
    and exits 0, so a retrieval miss never blocks the caller. Called by the domain-gated retrieval
    hook and runnable on demand to deepen into a topic
  - **Coverage boundary**: it searches the registered domain's **reference baseline** slim routing
    index only (e.g. `Odoo19_Docs_KB/00_Index.md`). It does **not** search the curated-findings lane
    (`Projects/`, `Surfaces/`, `RepeatKeys/`, `AI_AUTO_INDEX.md`) — those stay browse-only in Obsidian.
    So a captured `surface: odoo` finding is not auto-surfaced by the hook even after push. Making the
    findings lane retrievable is a tracked backlog item (see
    `plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md`), not current behavior

Automation diagnostic command:

- `./scripts/automation-doctor.sh`
  - Diagnoses whether the current repository has the expected automation foundation
  - Suggests repair commands by default
  - Applies only safe non-overwriting setup fixes with `--fix`
  - Checks helper symlinks and whether `~/bin` is on PATH when running inside ai-lab

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
  - With `--install-codex-drift-notice`, adds an opt-in managed `codex` shell
    function that prints a read-only notice for pending Obsidian/knowledge
    drafts before calling the real Codex binary
  - With `--install-codex-tmux-auto-entry`, adds support for
    default-on project-scoped tmux auto-entry for interactive terminal `codex`
    calls outside tmux; use `AI_AUTO_CODEX_TMUX_AUTO=0 codex` to opt out
  - With `--install-ai-tmux-auto-entry`, adds the same interactive tmux
    auto-entry behavior for `codex`, `claude`, and `agy`; use
    `AI_AUTO_TMUX_AUTO=0` to opt out for all wrappers, or
    `AI_AUTO_CLAUDE_TMUX_AUTO=0` / `AI_AUTO_AGY_TMUX_AUTO=0` for one runtime
  - Does not install external programs, configure credentials, run `automation-doctor --fix`, or overwrite non-symlink files

## Link setup

Expected links:

    ~/bin/AI_AUTO -> ~/workspace/ai-lab/tools/ai-home
    ~/bin/ai-auto -> ~/workspace/ai-lab/tools/ai-auto
    ~/bin/ai-home -> ~/workspace/ai-lab/tools/ai-home
    ~/bin/aiinit -> ~/workspace/ai-lab/tools/ai-auto
    ~/bin/ai-register -> ~/workspace/ai-lab/tools/ai-register
    ~/bin/ai-domain-pack -> ~/workspace/ai-lab/tools/ai-domain-pack
    ~/bin/ai-gstack-contract -> ~/workspace/ai-lab/tools/ai-gstack-contract
    ~/bin/ai-refactor-scan -> ~/workspace/ai-lab/tools/ai-refactor-scan
    ~/bin/ai-rebuild-plan -> ~/workspace/ai-lab/tools/ai-rebuild-plan
    ~/bin/ai-split-plan -> ~/workspace/ai-lab/tools/ai-split-plan
    ~/bin/ai-split-dry-run -> ~/workspace/ai-lab/tools/ai-split-dry-run
    ~/bin/ai-split-apply -> ~/workspace/ai-lab/tools/ai-split-apply
    ~/bin/ai-plan-status -> ~/workspace/ai-lab/tools/ai-plan-status
    ~/bin/ai-interview-record -> ~/workspace/ai-lab/tools/ai-interview-record
    ~/bin/ai-plan-review -> ~/workspace/ai-lab/tools/ai-plan-review
    ~/bin/ai-plan-export -> ~/workspace/ai-lab/tools/ai-plan-export
    ~/bin/feedback-collect -> ~/workspace/ai-lab/tools/feedback-collect
    ~/bin/feedback-resolve -> ~/workspace/ai-lab/tools/feedback-resolve
    ~/bin/knowledge-collect -> ~/workspace/ai-lab/tools/knowledge-collect
    ~/bin/workspace-scan -> ~/workspace/ai-lab/tools/workspace-scan
    ~/bin/micro-work -> ~/workspace/ai-lab/tools/micro-work
    ~/bin/ai-worktree -> ~/workspace/ai-lab/tools/ai-worktree
    ~/bin/ai-tmux-worktree -> ~/workspace/ai-lab/tools/ai-tmux-worktree
    ~/bin/ai-project-profile -> ~/workspace/ai-lab/tools/ai-project-profile
    ~/bin/knowledge-capture -> ~/workspace/ai-lab/tools/knowledge-capture
    ~/bin/knowledge-retrieve -> ~/workspace/ai-lab/tools/knowledge-retrieve
    ~/bin/ai-kb-retrieval-hook -> ~/workspace/ai-lab/tools/ai-kb-retrieval-hook

To recreate the links:

    ./scripts/install-global-files.sh

Manual equivalent for a clean helper directory. Prefer the installer above; it
refuses to overwrite non-symlink files, while manual `ln -sf` commands can
replace existing paths if used carelessly.

    mkdir -p ~/bin
    ln -sf ~/workspace/ai-lab/tools/ai-home ~/bin/AI_AUTO
    ln -sf ~/workspace/ai-lab/tools/ai-auto ~/bin/ai-auto
    ln -sf ~/workspace/ai-lab/tools/ai-home ~/bin/ai-home
    ln -sf ~/workspace/ai-lab/tools/ai-auto ~/bin/aiinit
    ln -sf ~/workspace/ai-lab/tools/ai-register ~/bin/ai-register
    ln -sf ~/workspace/ai-lab/tools/ai-domain-pack ~/bin/ai-domain-pack
    ln -sf ~/workspace/ai-lab/tools/ai-gstack-contract ~/bin/ai-gstack-contract
    ln -sf ~/workspace/ai-lab/tools/ai-refactor-scan ~/bin/ai-refactor-scan
    ln -sf ~/workspace/ai-lab/tools/ai-rebuild-plan ~/bin/ai-rebuild-plan
    ln -sf ~/workspace/ai-lab/tools/ai-split-plan ~/bin/ai-split-plan
    ln -sf ~/workspace/ai-lab/tools/ai-split-dry-run ~/bin/ai-split-dry-run
    ln -sf ~/workspace/ai-lab/tools/ai-split-apply ~/bin/ai-split-apply
    ln -sf ~/workspace/ai-lab/tools/ai-plan-status ~/bin/ai-plan-status
    ln -sf ~/workspace/ai-lab/tools/ai-interview-record ~/bin/ai-interview-record
    ln -sf ~/workspace/ai-lab/tools/ai-plan-review ~/bin/ai-plan-review
    ln -sf ~/workspace/ai-lab/tools/ai-plan-export ~/bin/ai-plan-export
    ln -sf ~/workspace/ai-lab/tools/feedback-collect ~/bin/feedback-collect
    ln -sf ~/workspace/ai-lab/tools/feedback-resolve ~/bin/feedback-resolve
    ln -sf ~/workspace/ai-lab/tools/knowledge-collect ~/bin/knowledge-collect
    ln -sf ~/workspace/ai-lab/tools/workspace-scan ~/bin/workspace-scan
    ln -sf ~/workspace/ai-lab/tools/micro-work ~/bin/micro-work
    ln -sf ~/workspace/ai-lab/tools/ai-worktree ~/bin/ai-worktree
    ln -sf ~/workspace/ai-lab/tools/ai-tmux-worktree ~/bin/ai-tmux-worktree
    ln -sf ~/workspace/ai-lab/tools/ai-project-profile ~/bin/ai-project-profile
    ln -sf ~/workspace/ai-lab/tools/knowledge-capture ~/bin/knowledge-capture
    ln -sf ~/workspace/ai-lab/tools/knowledge-retrieve ~/bin/knowledge-retrieve
    ln -sf ~/workspace/ai-lab/tools/ai-kb-retrieval-hook ~/bin/ai-kb-retrieval-hook

Make sure `~/bin` is in PATH:

    export PATH="$HOME/bin:$PATH"

For permanent setup, add this to `~/.bashrc`:

    export PATH="$HOME/bin:$PATH"

`./scripts/install-global-files.sh` also writes the `AI_AUTO()` function to
`~/.config/ai-lab/AI_AUTO.sh` and adds a managed source block to `~/.bashrc`.
Reload the shell or run:

    source ~/.bashrc

The same managed shell integration adds small convenience functions:

- `jwlist`
  - Lists project folders directly under `/mnt/z/JSJEON/Project_JW`
  - Set `AI_AUTO_JW_PROJECT_ROOT` if your JW projects live under an extra
    grouping folder such as `Project_JW/99. odoo`
  - If the default root does not exist, the function prints a hint to set
    `AI_AUTO_JW_PROJECT_ROOT=/path/to/root`
  - Prompts for a number; choose `0` to enter the current folder, or choose a
    subfolder to drill down through grouped projects
  - Stops drilling down and enters a folder when common project markers are
    present, such as `.git`, `AGENTS.md`, `package.json`, `pyproject.toml`,
    `requirements.txt`, `docker-compose.yml`, or `scripts/verify-project.sh`
  - Override the root with `AI_AUTO_JW_PROJECT_ROOT=/path/to/root`

- `sirdlist`
  - Lists project folders directly under `/mnt/z/JSJEON/Project_SirD`
  - If the default root does not exist, the function prints a hint to set
    `AI_AUTO_SIRD_PROJECT_ROOT=/path/to/root`
  - Prompts for a number; choose `0` to enter the current folder, or choose a
    subfolder to drill down through grouped projects
  - Stops drilling down and enters a folder when common project markers are
    present, such as `.git`, `AGENTS.md`, `package.json`, `pyproject.toml`,
    `requirements.txt`, `docker-compose.yml`, or `scripts/verify-project.sh`
  - Override the root with `AI_AUTO_SIRD_PROJECT_ROOT=/path/to/root`

- `tmux`
  - When called with no arguments, starts a new tmux session named with the
    first available positive integer (`1`, `2`, `3`, ...)
  - Calls with arguments are passed through to the real tmux command unchanged

## Codex Knowledge-Autopush Notice

The normal global install does not replace or shadow `codex`. To opt into a
read-only startup notice for pending Obsidian/knowledge drafts, run:

    ./scripts/install-global-files.sh --install-codex-drift-notice

This writes `~/.config/ai-lab/codex-drift-notice.sh` and a managed `.bashrc`
source block. The generated function resolves the real Codex executable at
install time and then calls the real Codex binary with the original arguments.

Disable the notice for a shell command with:

    AI_AUTO_CODEX_DRIFT_NOTICE=0 codex

When the wrapper is invoked from the AI_AUTO home checkout, it checks
for validated knowledge drafts across AI_AUTO plus registered projects. If
drafts are pending, it prints a read-only `OBSIDIAN OUTPUT CHECK` block with up
to ten pending rows, an inspect command, and the publish command. It never
writes to a vault and never pushes automatically.

To publish, run `scripts/obsidian-autopush.sh` from the home checkout (or say
`옵시디언 푸시해줘`). By rule it auto-promotes `local_private` drafts to
`shareable_summary` when the draft's `surface` is on the allowlist (AI_AUTO
tooling surfaces: review-gate, workflow, ai-review, model-routing,
ai-auto-template, domain-pack, obsidian, shell-integration, verification,
browser-verification) and the note is sanitized and passes a secret/redaction
preflight, then publishes the shareable set. Off-allowlist surfaces (e.g. `ssh`
or project-specific surfaces), unsanitized, or secret-like drafts stay
`local_private` and are never published (default-deny, fail-closed). The vault
path comes from `obsidian.ai_auto_vault_dir` in `.omx/local-config.json`, and
when nothing is shareable the vault is left untouched. Override the allowlist
with `AI_AUTO_AUTOPROMOTE_SURFACES`, disable promotion with `--no-auto-promote`,
or preview with `--dry-run`. The startup notice does not scan mounted project
folders; if a moved or individual project is missing, run `ai-register --prune`
and `ai-register /path/to/repo` for the current path. Suppress the notice with:

    AI_AUTO_KNOWLEDGE_AUTOPUSH_NOTICE=0 codex

The notice path is read-only. It does not merge files, patch projects, or
install a `~/bin/codex` executable.

The same managed `codex` shell wrapper can optionally support tmux auto-entry:

    ./scripts/install-global-files.sh --install-codex-tmux-auto-entry

After installation, normal interactive `codex` calls outside tmux enter a stable
project-scoped tmux session automatically. Disable it for a shell or command
when direct execution is needed:

    AI_AUTO_CODEX_TMUX_AUTO=0 codex

Interactive `codex` calls outside tmux start in the current directory and use a
project-scoped tmux session name. If that session already exists, the wrapper
starts the next numbered session instead of attaching to the already-open Codex
command.
Calls already inside tmux, calls with non-terminal stdin/stdout such as pipes or
redirects, calls without `tmux` on `PATH`, and calls with
`AI_AUTO_CODEX_TMUX_AUTO=0` continue to run the real Codex binary directly. This
keeps scripts and short non-interactive checks from being captured by tmux.

To opt into the same interactive tmux auto-entry for the other AI CLI entry
points used by AI_AUTO, run:

    ./scripts/install-global-files.sh --install-ai-tmux-auto-entry

This installs managed shell functions for `codex`, `claude`, and `agy`. The
normal Gemini reviewer path uses `agy`, so no separate `gemini` wrapper is
installed by default. These wrappers affect only interactive terminal starts.
They do not change `scripts/ai-runtime-adapter.sh`, review-gate capability
rules, model routing, credentials, or tool permissions. Session names include
the runtime name and add a numeric suffix when an existing session is already
open, so parallel terminals in the same project keep `codex`, `claude`, and
`agy` in separate tmux sessions instead of attaching to an already-open AI
runtime.

Disable all AI_AUTO tmux auto-entry wrappers for a shell command with:

    AI_AUTO_TMUX_AUTO=0 claude

Disable only one runtime with:

    AI_AUTO_CLAUDE_TMUX_AUTO=0 claude
    AI_AUTO_AGY_TMUX_AUTO=0 agy

The generated wrapper also raises the soft `nofile` limit before launching an AI
runtime, including inside the tmux command string. This avoids Claude/agy
startup failures from shells or existing tmux servers that inherited a low file
descriptor limit. Override the default target with `AI_AUTO_NOFILE_LIMIT`; set
it to a numeric value supported by the current shell hard limit.
