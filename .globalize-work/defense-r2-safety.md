# Defense Game R2 — RED TEAM safety findings (post-round-1 hardening)

Target: branch `feat/global-toolize`, HEAD e29a5fe. Files: `tools/ai-auto`,
`hooks/{pre-commit,post-commit}`. All findings reproduced with throwaway temp projects
(git 2.43.0, bash 5.2). Engine source never edited; engine never mutated in any repro.

Result: round-1 fixes F4/F5/F6 hold, but **F1 and F3 are BYPASSED**, **F2 is incomplete**,
and concurrent setup is a new race. Ranked: 1 HIGH, 3 MED, 2 LOW.

---

## R2-1 — HIGH — F1 BYPASSED: baked engine hook that is a DIRECTORY blocks every commit
The F1 guard is `if [ ! -x "$AI_AUTO_HOME/hooks/$hook" ]` (`tools/ai-auto:126`). `[ -x DIR ]`
is TRUE for a directory (search bit), so when the baked engine hook PATH exists but is a
directory the guard is skipped and the shim runs `exec ".../hooks/pre-commit"` → bash
"cannot execute: Is a directory" → exit 126 → pre-commit nonzero → **commit ABORTED**.
Same blast radius as the original F1: every project baked to that engine, cryptic message,
only `--no-verify` escapes. A bare-file-with-exec-bit-but-not-runnable triggers the same.
The guard tests executability, not "is a runnable regular file".

Repro (verified — c2 blocked, log shows only init+c1, `--no-verify` is the only escape):
```
cp -a <engine> /tmp/eng1
mkdir P && cd P && git init && echo hi>f && git add -A && git commit -m init
/tmp/eng1/tools/ai-auto setup "$PWD"
echo a>>f; git add -A; git commit -m c1            # OK
rm -f /tmp/eng1/hooks/pre-commit
mkdir -p /tmp/eng1/hooks/pre-commit                # path exists, is a DIR, passes [ -x ]
echo b>>f; git add -A; git commit -m c2            # BLOCKED: "Is a directory", exit 1
```
File:line `tools/ai-auto:126`.
Fix: gate on regular-file-AND-executable: `if ! [ -f "$AI_AUTO_HOME/hooks/$hook" ] || ! [ -x "$AI_AUTO_HOME/hooks/$hook" ]; then` (warn + exit 0). Optionally also reject if it is not a runnable script.

## R2-2 — MED — F3 BYPASSED: unstaged worktree-vs-HEAD divergence half-migrates then aborts
The F3 pre-check only inspects the INDEX: `git diff --cached --name-status | grep -qvE '^D'`
(`tools/ai-auto:84`). But the de-pollution `cmp -s` compares the WORKING TREE to the engine
pristine (`:153`), and `git rm --quiet` (no `-f`/`--cached`) refuses a file whose WORKING
TREE differs from HEAD ("has local modifications"). A managed file whose committed HEAD is an
OLD vendored copy but whose working tree was refreshed to exactly the CURRENT engine pristine
(the normal "old template refresh, not yet committed" migration state) is UNSTAGED, so the
`--cached` pre-check passes, but `cmp` matches → `git rm` errors → `set -e` aborts AFTER
earlier pristine files (e.g. `AGENTS.md`, first in `FRAMEWORK_PATHS`) were already staged-
deleted. Partial migration. Re-run does NOT recover: the staged `D` passes the pre-check, but
the same file errors again every time → stuck until manual `git restore --staged`.

Repro (verified — exit 1, index left `D AGENTS.md` + ` M docs/WORKFLOW.md`):
```
# HEAD: AGENTS.md==engine pristine, docs/WORKFLOW.md == OLD "v1"
cp <engine>/docs/WORKFLOW.md docs/WORKFLOW.md     # refresh worktree to engine pristine, UNSTAGED
ai-auto setup "$PWD"                              # AGENTS staged-deleted, then git rm WORKFLOW errors, abort
```
File:line `tools/ai-auto:84` (pre-check scope) + `:153-154`.
Fix: the pre-flight must also reject worktree-vs-HEAD divergence on managed paths (compare
`git status --porcelain` per managed path), or build the removable set and stage it atomically
(`git rm --cached`/single pathspec) instead of a per-file loop under `set -e`.

## R2-3 — MED — F2 INCOMPLETE: GIT_CONFIG_* survives the unset and redirects hook install
F2 unsets `GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_NAMESPACE`
(`tools/ai-auto:60`) but NOT the config-injection family `GIT_CONFIG_COUNT` /
`GIT_CONFIG_KEY_n` / `GIT_CONFIG_VALUE_n` (nor `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`). These
inject arbitrary config into every `git` call, including `core.hooksPath`, which
`git rev-parse --git-path hooks` (`:108`) honors. An inherited
`GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=<dir>` makes setup
install both shims into `<dir>`; a normal commit (without that env) looks in `.git/hooks`,
finds nothing → **gate silently inert**, while setup reports success ("Hook shims ... in:
<dir>"). Same threat model F2 addressed (stray GIT_* from a parent git context).

Repro (verified — shims landed in evil dir, `.git/hooks/pre-commit` absent, normal commit ran no hook):
```
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/tmp/evil \
  ai-auto setup "$PWD"
git commit -m c1            # no shim output -> gate inert
```
File:line `tools/ai-auto:60`.
Fix: also `unset GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES`
and the indexed `GIT_CONFIG_KEY_* / GIT_CONFIG_VALUE_*` (loop over `GIT_CONFIG_COUNT`), or run the
git ops with an explicit clean env.

## R2-4 — MED — concurrent `ai-auto setup` (two terminals, one project) aborts mid-loop
The per-file `git rm` loop (`:146-159`) holds no index lock across the run. Two simultaneous
setups on one project race: the loser hits `fatal: pathspec '...' did not match` (the other run
already rm'd it) or `fatal: Unable to create '.git/index.lock'` and, under `set -e`, exits 128
mid-loop. Observed in 10/12 race iterations. The winner usually finishes (net index ends fully
migrated here), but one process exits non-zero with a partial/alarming run, and a tighter race
(both losing on different files) can leave a partial index — same non-atomic root cause as R2-2.

Repro (verified — 10/12 iters one job `Exit 128`):
```
ai-auto setup "$P" & ai-auto setup "$P" & wait    # one exits 128: pathspec/index.lock
```
File:line `tools/ai-auto:146-159`.
Fix: stage the de-pollution atomically (single `git rm` pathspec) and/or hold an advisory lock /
detect a concurrent run; tolerate already-removed paths (skip on `did not match`).

## R2-5 — LOW — core.hooksPath with a pre-existing custom hook: gate not installed, report misleading
When the project already sets `core.hooksPath` (e.g. Odoo `.githooks`) AND ships its own
`.githooks/pre-commit`, setup correctly resolves the active hooks dir and (correctly) leaves the
custom hook untouched with a warning — but it then prints "Hook shims (...) in: .../.githooks"
even though the pre-commit shim was NOT installed there. The engine gate never fires for
pre-commit; the success-shaped summary obscures that. (post-commit shim IS installed.) Behavior
is safe (no clobber, warns) but the final report overstates coverage.
File:line `tools/ai-auto:115-118,180`.
Fix: track per-hook install/skip and report "1 shim installed, 1 skipped (custom)" accurately.

## R2-6 — LOW/ACCEPTED — F1 fail-open: engine hook losing its exec bit silently skips the gate
The F1 design choice is fail-open: if the engine hook is non-executable, the shim warns to
stderr and `exit 0`. In a DERIVED project that means EVERY commit thereafter skips the gate with
only a stderr warning (easily lost in tooling). This is the documented F1 tradeoff, not a new
hole, but worth flagging: a single `chmod -x` on the engine disables gating fleet-wide silently.
File:line `tools/ai-auto:126-129`. Fix (if undesired): make the missing/again-non-exec engine a
loud post-commit advisory too, or fail-closed with an explicit override.

---

## Positives (round-1 fixes that HELD under R2 attack)
- **F4** self-host sentinel (`verify-machinery.sh` + executable `tools/ai-auto`): engine copies
  still detected; no false abort observed for ordinary projects.
- **F5** ordering: hooks + `.omx` exclude installed before `git rm`; abort in R2-2 left hooks
  intact, no "deletions staged with no hooks" state.
- **F6** symlinked managed paths: a managed path that is a SYMLINK whose target bytes equal
  pristine is detected via `[ -L ]` and KEPT, never `git rm`'d (verified). Dir-symlink same.
- core.hooksPath (git 2.43) resolution lands shims in the active `.githooks` dir (verified).
