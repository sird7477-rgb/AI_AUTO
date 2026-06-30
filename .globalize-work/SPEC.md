# Global-tool-ization — design spec (feat/global-toolize)

GOAL: AI_AUTO becomes a globally-installed tool operating ON project dirs. A project repo
carries ZERO vendored framework files (no churn from AI_AUTO version bumps). Decided: NO
version pin (solo, single box, no AI_AUTO CI; odoo.sh parity is the Odoo-source pin, separate).

ABSOLUTE MANDATE: shortest code is the most perfect code. Prefer DELETING machinery over
adding. Every artifact must justify its existence; when in doubt, remove.

## Boundary (what lives where)
- GLOBAL (framework engine, in $AI_AUTO_HOME): every `scripts/*` framework file EXCEPT
  `verify.sh`; all `docs/*.md`; the base `AGENTS.md` guidance; domain packs.
- PROJECT-OWNED (committed, legitimate — NOT churn): `scripts/verify.sh` ONLY (the project's
  definition of "what verification means here"), and an optional short project guidance overlay
  (CLAUDE.md / AGENTS.md addendum).
- RUNTIME (project, gitignored): `.omx/`.
- RETIRED (deleted, not globalized): `AI_AUTO_TEMPLATE_VERSION` + the whole drift/refresh/
  staleness/bump-on-change apparatus (`ai-auto-template-status` 3-way drift, `ai-template-refresh`,
  off-manifest detection, the staleness gate in review-gate, `check-template-version` bump gate).
  Rationale: that apparatus exists ONLY to manage per-project COPIES; with no copies it is dead
  weight. Removing it is the bulk of the "shortest code" win.

## Mechanism (minimal)
- `$AI_AUTO_HOME` = the global install dir (the ai-lab checkout, or `~/.ai-auto`). Exported by
  install-global-files.sh into the shell profile.
- Framework scripts resolve framework SIBLINGS via their own location
  (`AI_AUTO_HOME="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"`), NOT via `$(pwd)`/`./scripts`.
  The project working dir stays `$(pwd)` (or `$AI_AUTO_PROJECT`) for `.omx/`, git, artifacts.
- The ONE project-owned seam: `review-gate.sh` invokes the project's verification as
  `"$PROJECT/scripts/verify.sh"` (pwd-relative), while ALL other sibling calls
  (collect-review-context, run-ai-reviews, summarize, verify-machinery, archive, checkpoint,
  capture) resolve from `$AI_AUTO_HOME`. User-facing message strings that mention
  `./scripts/review-gate.sh` become `ai-auto gate` etc. (cosmetic).
- Launcher `ai-auto` (PATH): `ai-auto gate|verify|init|migrate|doctor`. Runs the engine from
  `$AI_AUTO_HOME` with the project = `$PWD`.
- Hooks: GLOBAL, via `git config core.hooksPath "$AI_AUTO_HOME/hooks"` set per-clone by
  `ai-auto init`. Global hooks call `ai-auto gate`/engine. (`.git/hooks` was never committed,
  so hooks are not the churn source — but routing them globally removes the per-clone copy.)
- `ai-auto init <project>`: set core.hooksPath; ensure `.omx/` gitignored; auto-detect domain
  (existing `ai-project-profile`) — writes NO framework files. Idempotent.
- `ai-auto migrate <project>`: `git rm` the vendored framework files (managed set MINUS
  verify.sh) + AGENTS.md/docs + version file; KEEP verify.sh; run init; ONE commit. Fail-closed:
  refuse if verify.sh is missing or if the tree is dirty in a way that risks loss.
- Guidance: base AI_AUTO guidance installed once to global `~/.claude/CLAUDE.md` by
  install-global-files (Claude Code already layers global + project). Project keeps only overlay.

## Extensibility (QC, design, future packs)
- Domain packs are already pluggable global dirs. New capability (QC pack, design pack) = a new
  global pack dir + (optional) a launcher subcommand + global hook entry. ZERO project change to
  adopt. The launcher subcommand table and the global hooks dir are the only extension seams.

## Defense protocol (red/blue, ALL via subagents; orchestrator = main loop)
- Every stage (design, implement, test, debug) is gated by RED-TEAM certification: a red-team
  subagent must find NO integrity defect for the stage to pass.
- After implementation, a defense game: red-team subagents hunt defects (unrestricted, relentless);
  blue-team subagents debug + VERIFY each fix. Loop until 2 consecutive red rounds find nothing
  new (convergence = red defeated = certified). Blue must keep the structure simple/short so
  fixes+verification are fast.
- ALL work in worktree `/root/workspace/ai-lab-globalize` (branch feat/global-toolize). Never
  touch other worktrees / projects. State persists in `.globalize-work/STATE.md`.

## DONE criteria (the only thing reported to the user afterwards: "완성되었습니다")
design certified ∧ implementation certified ∧ defense game converged (2 dry red rounds) ∧
all engine self-tests + new global-mode tests green ∧ a clean end-to-end migrate of a throwaway
project proven (init → gate runs from global → no framework files committed).
