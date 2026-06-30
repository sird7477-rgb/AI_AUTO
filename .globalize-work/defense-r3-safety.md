# Defense Game R3 — RED TEAM safety findings (post-round-2 hardening)

Target: branch `feat/global-toolize`, HEAD c3b4781. Files: `tools/ai-auto`,
`hooks/{pre-commit,post-commit}`. All findings reproduced with throwaway temp projects
(git 2.43.0, bash 5.2.21). Engine source never edited; no engine repo mutated in any repro
except the deliberate R3-1 copy.

Result: **all four round-2 fixes HOLD** (R2-1 non-regular-file shim, R2-2 worktree-divergence
half-migrate, R2-3 setup config-scrub, R2-4 concurrent-setup race — all re-attacked, all clean).
But **3 NEW defects** found, one HIGH. Ranked: 1 HIGH, 2 MED, 2 LOW.

---

## R3-1 — HIGH — self-host guard BYPASSED by a missing exec bit → engine gets de-polluted
The engine-detection guard ANDs two markers: `[ -f "$top/scripts/verify-machinery.sh" ] &&
[ -x "$top/tools/ai-auto" ]` (`tools/ai-auto:81`). The second marker depends on the **exec
bit** of `tools/ai-auto`. An engine *copy/checkout* that lost that bit — tarball/zip extract,
`cp` without `-p`, `git archive`, a clone with `core.fileMode=false` or on Windows/WSL mounts —
still has `verify-machinery.sh` (content survives) but fails `[ -x ]`, so the AND collapses and
the guard MISSES. Running another engine's launcher against such a copy then treats the engine
as an ordinary project and **stages `git rm` of all 48 canonical framework files** (AGENTS.md,
every `docs/*.md`, every `scripts/*`). This is exactly the engine-mutation / data-loss class the
guard exists to prevent. (The first condition `top = $AI_AUTO_HOME` only catches the engine's
OWN launcher run against itself; a sibling launcher targeting a copy is the realistic path.)

Repro (verified — 48 staged deletions in the engine copy):
```
cp -a <engineA> engB && chmod -x engB/tools/ai-auto    # drop exec bit (tar/cp/Windows reality)
cd engB && rm -rf .git && git init -q && git add -A && git commit -m snap
bash <engineA>/tools/ai-auto setup "$PWD"
git status --porcelain | grep -c '^D '                  # => 48  (engine de-polluted)
```
File:line `tools/ai-auto:80-81`.
Fix: make engine markers **not** depend on the exec bit. Test regular-file presence only
(`[ -f "$top/tools/ai-auto" ]`), and/or grep an engine-only signature line inside
`tools/ai-auto` / a dedicated sentinel file, instead of `[ -x ]`.

## R3-2 — MED — launcher dispatch (gate/verify/doctor) does NOT scrub GIT_* → wrong-repo gate
`ai_auto_setup` carefully clears `GIT_DIR/GIT_WORK_TREE/GIT_CONFIG_*/...` (`:63-68`) because a
stray git env from a parent context (`git rebase --exec`, a parent hook, husky/lefthook, an IDE
git terminal) overrides `git -C` discovery. But the `gate`/`verify`/`doctor` dispatch
(`:228-232`) just `exec`s the scripts with **no scrub**, and `review-gate.sh` resolves the
workspace with a bare `git rev-parse --show-toplevel` (`scripts/review-gate.sh:115`). An
inherited `GIT_DIR` therefore points the gate at the WRONG repository — it analyzes a different
tree/HEAD and can emit a proceed verdict for the wrong workspace (silent-wrong / inert gate),
the same threat model setup defends against.

Repro (verified — resolves OTHER repo, not the cwd repo):
```
cd REAL_repo
GIT_DIR=/path/OTHER/.git GIT_WORK_TREE=/path/OTHER git rev-parse --show-toplevel  # => /path/OTHER
# 'ai-auto gate' run in REAL under that inherited env feeds review-gate.sh the OTHER repo
```
File:line `tools/ai-auto:228-232`.
Fix: scrub the same GIT_* / GIT_CONFIG_* set (factor the setup scrub into a helper) before the
`gate`/`verify`/`doctor` execs, or have the gate scripts scrub on entry.

## R3-3 — MED — engine hooks + installed shim scrub GIT_DIR family but NOT GIT_CONFIG_* (config injection / RCE survives into the gate)
R2-3 added the `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_*` scrub to **setup only**. The two engine
hooks (`hooks/pre-commit:14`, `hooks/post-commit:9`) and the **installed shim** (the generated
`unset` line, `tools/ai-auto:145`) still unset only the `GIT_DIR` family. So inherited
config-injection env survives into every git call the hook/gate makes. With
`GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0='<cmd>'` a normal commit
through the shim runs `<cmd>` (arbitrary command execution); `core.hooksPath` / `include.path`
inject equally. Threat-symmetric with the GIT_DIR scrub the hooks already perform against a
poisoned parent git context.

Repro (verified — sentinel file created during a shimmed commit):
```
ai-auto setup "$P"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0="touch /tmp/PWNED" \
  git commit -m c1            # => /tmp/PWNED exists
```
File:line `tools/ai-auto:145` (shim heredoc) + `hooks/pre-commit:14` + `hooks/post-commit:9`.
Fix: extend every scrub site to also clear `GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
GIT_CONFIG_NOSYSTEM` and the indexed `GIT_CONFIG_KEY_*/GIT_CONFIG_VALUE_*` (loop), matching
setup. (Self-inflicted env is low-risk; the real exposure is an inherited parent git context —
the exact thing the hooks' existing GIT_DIR unset targets.)

## R3-4 — LOW — setup lock fd is NOT close-on-exec → a daemon child pins the per-project lock
`exec {_lockfd}>"$_lockfile"` (`tools/ai-auto:97`) opens the flock fd WITHOUT close-on-exec, so
it is inherited by every child setup spawns (verified: child `bash` sees fd 10 open after exec).
Short-lived children (`git rm`, etc.) are harmless, but a long-lived child — a git **fsmonitor
daemon** (spawned by `git diff`/`git rm` when `core.fsmonitor` is enabled) or
`ai-project-profile` if it backgrounds anything — inherits the open fd and holds the advisory
lock after setup exits, so the **next `ai-auto setup` on that project blocks indefinitely**.
File:line `tools/ai-auto:97`.
Fix: open the lock fd close-on-exec — `exec {_lockfd}>"$_lockfile"` then `flock` is fine if you
also set CLOEXEC; simplest is to wrap the locked region with `flock -x "$_lockfile" -c '...'`, or
explicitly `exec {_lockfd}>&-` is not enough (need it closed in children). Use `flock` on a
subshell so the fd never leaks to the long-lived grandchildren.

## R3-5 — LOW — cross-worktree setup: per-worktree lock does not cover the SHARED info/exclude
The lock path is per-worktree (`git rev-parse --git-path ai-auto-setup.lock` →
`.git/worktrees/<wt>/ai-auto-setup.lock`, `tools/ai-auto:92-93`), but the `.omx/` exclude append
target (`:119-126`) and the hook shims (`:131`) resolve to the **shared common dir**
(`.git/info/exclude`, `.git/hooks` — verified). Two concurrent `ai-auto setup` runs on two
DIFFERENT worktrees of one repo take DIFFERENT locks (no mutual exclusion) yet both append to the
one shared `info/exclude`; the `grep -q` guard is racy, so a duplicate `.omx/` line is possible
(cosmetic). The de-pollution `git rm` is per-worktree-index and stays safe; shim writes are
identical content. Low impact, but the per-worktree lock gives a false sense of full coverage.
File:line `tools/ai-auto:92-93` vs `:119-126`.
Fix: for the shared-state writes (exclude append) lock on the COMMON dir
(`git rev-parse --git-common-dir`), or accept the cosmetic dup and tighten the grep guard.

---

## Positives — round-2 fixes that HELD under R3 re-attack
- **R2-1** non-regular-file shim exec: FIFO, directory, broken symlink, symlink-to-dir engine
  hooks all fail-OPEN (warn + `exit 0`, commit proceeds) — the `[ -f ] && [ -x ]` guard
  (`:151`) rejects every non-regular path. No commit ever blocked.
- **R2-2** worktree-vs-HEAD divergence: the old half-migrate repro now removes the pristine file
  and KEEPS the worktree-modified one (`git diff --quiet` guard `:186`); no abort, no partial
  index, exit 0.
- **R2-3** setup config-scrub: `GIT_CONFIG_COUNT=... core.hooksPath` no longer redirects shim
  install (`:63-68`); shims land in `.git/hooks`. `GIT_CONFIG` single-file var is inert for
  `rev-parse` (git scopes it to `git config`), so it is not an injection path here.
- **R2-4** concurrent setup (same project): 12/12 race iterations → 0 nonzero exits, 0 partial
  indexes; flock serializes (`:94-100`), atomic `git rm` (`:206-208`) is all-or-nothing.
- Idempotency after the atomic-rm change: re-run on a migrated project x3 → exit 0, clean tree.
  The bare `((${#removed[@]})) && printf` lines do NOT trip `set -e`.
- Empty HEAD (no commits): nothing-staged → exit 0; vendored-files-staged → clean ABORT exit 1.
- `.git/hooks` is a symlink-to-dir: shims written through it correctly, link preserved.
