# Defense R4 — Portability & Environment (WSL2 / drvfs-9p / multi-terminal / minimal hook shells)

Hunter: RED TEAM round 4. Worktree `feat/global-toolize` HEAD 58bcb42. Read-only.
Tested on a REAL WSL2 host: `/mnt/z` is genuinely `Z:\ on /mnt/z type 9p (drvfs)`. Empirical
results below run on that mount, not reasoned in the abstract.

## Empirical drvfs/9p results (prior-round HIGH worries DID NOT reproduce)

Ran a battery in `/mnt/z/JSJEON/.globalize-r4-test.$$`:

- `flock` on 9p: **REAL.** Concurrent `flock -n` exclusive: second waiter blocked (rc=1).
  The `ai-auto setup` advisory lock is NOT a silent no-op here. (NOTE: this is the current
  WSL2 9p/drvfs; not a guarantee for SMB/older 9p — see L3.)
- `readlink -f` on a 9p symlink: resolves correctly (rc=0).
- `[ a -ef b ]` on 9p: hardlink→SAME, copy→different, self-dir→SAME. device+inode stable, so
  pre-commit's `-ef` self-host check (line 56) and `cmp` de-pollution work on drvfs.
- Atomic `mv -f` rename + `mktemp`: work (session-lock write is fine on 9p).
- **drvfs is CASE-INSENSITIVE** (`CaseTest.txt` == `casetest.txt`). See L1.

Net: the scary "no-lock-race-on-9p / broken-on-drvfs" axes are CLEAN on the real target.
The genuine defects are in the PATH model and macOS/non-bash portability, below.

---

## DEFECT M1 (MED) — tools/ helpers unreachable from launcher/hook/shim in a minimal env

One-line: the launcher, both hooks, and the baked shim prepend only `$AI_AUTO_HOME/scripts`
to PATH, but several helpers they invoke by bare name live in `$AI_AUTO_HOME/tools` — so in a
minimal env (git hook from IDE/cron, or any shell that never sourced the managed .bashrc and
lacks `~/bin` on PATH) those helpers are silently not found.

Repro / reasoning:
- PATH prepend adds scripts only: `tools/ai-auto:8`, `tools/ai-auto:170` (baked shim),
  `hooks/pre-commit:8`, `hooks/post-commit:7` — all `PATH="$AI_AUTO_HOME/scripts:$PATH"`.
- But `install-global-files.sh:394` bakes BOTH onto the interactive PATH:
  `PATH="$AI_AUTO_HOME/scripts:$AI_AUTO_HOME/tools:$PATH"`. So interactive shells find tools/,
  hook/launcher subprocesses do not. The two PATH models disagree.
- Bare-name `tools/` helpers reached from these entrypoints:
  - `hooks/post-commit:24-25` `command -v knowledge-capture` → knowledge auto-harvest. In a
    minimal commit env (~/bin not on PATH) `command -v` fails → harvest silently never runs.
  - `tools/ai-auto:178` `command -v ai-project-profile` (in `ai-auto setup`) → domain detect.
    Launcher PATH has scripts only; unless ~/bin is on the ambient PATH the detect is skipped.
- Both are `|| true` / `command -v`-guarded, so FAIL-OPEN (no broken commit). Impact is silent
  feature-loss exactly in the minimal hook/IDE/cron context this round targets — not a crash.
- Install script never adds `~/bin` to PATH (only warns, `install-global-files.sh:1100-1103`),
  so even an interactive non-managed shell can hit this.
Severity MED: degraded, not failed; but invisibly inert in the very env the round probes.
Fix: prepend `$AI_AUTO_HOME/tools` alongside scripts in `tools/ai-auto:8`, the baked shim
(`tools/ai-auto:170`), `hooks/pre-commit:8`, `hooks/post-commit:7` — e.g.
`PATH="$AI_AUTO_HOME/scripts:$AI_AUTO_HOME/tools:$PATH"`, mirroring install-global-files.sh:394.

## DEFECT M2 (MED) — `readlink -f` is non-portable (breaks on macOS / BSD readlink)

One-line: every engine entrypoint resolves itself with `readlink -f`, which does not exist in
BSD `readlink` (macOS default) — a global tool installed on a Mac fails to locate AI_AUTO_HOME.

Repro / reasoning:
- `readlink -f` usages in shipped runtime: `tools/ai-auto:7` and `:141` (baked path),
  `hooks/pre-commit:7`, `hooks/post-commit:6`, `scripts/verify.sh:6`, `scripts/review-gate.sh:6`,
  `scripts/automation-doctor.sh:6`, `scripts/collect-review-context.sh:192`.
- On macOS, BSD `readlink -f` errors/empties → `cd "$(dirname "")/.." ` resolves wrong → engine
  root misdetected. WSL2 (the user's box) ships GNU coreutils, so this WORKS for the named user;
  flagged because the deliverable is a *global* tool and macOS is a realistic target.
- Inconsistency proof: `tools/ai-home:4-19` deliberately uses a portable manual symlink-walk
  (`while [ -L ]; readlink; cd -P`) instead of `readlink -f`. The other entrypoints don't.
Severity MED (HIGH on macOS, N/A on WSL).
Fix: reuse the `ai-home` portable resolver, or guard: `realpath "$0" 2>/dev/null || readlink -f "$0"`,
or `command -v greadlink`. At minimum bake the resolved path once (setup already does for shims).

## DEFECT L1 (LOW) — drvfs case-insensitivity weakens the string-equality self-host check

One-line: `ai-auto setup` self-host guard compares paths with string `=`; on case-insensitive
drvfs a different-case engine path would not string-match — but the `-f` marker fallback saves it.

Reasoning: `tools/ai-auto:84` `[ "$top" = "$AI_AUTO_HOME" ]`. On drvfs `/mnt/z/AI-Lab` vs
`/mnt/z/ai-lab` are the same dir but `=` is false. The OR fallback on `:85`
(`-f .../verify-machinery.sh && -f .../ai-auto`) is filesystem-case-insensitive, so the engine is
still detected and the guard holds. No exploit demonstrated; noted as fragility (the equality arm
is dead on drvfs and only the marker arm protects). Fix (optional): use `-ef` for the path-identity
arm (`[ "$top" -ef "$AI_AUTO_HOME" ]`), which is inode-based and case-proof (verified `-ef` works on 9p).

## DEFECT L2 (LOW) — multi-terminal session lock is a PID-marker with a TOCTOU window (no flock)

One-line: the real multi-terminal concurrency guard (`session-lock.sh`) does check-then-write on a
PID-marker file, not `flock`; two terminals sharing ONE working tree can both pass the gate.

Reasoning: `session-lock.sh:41-71`. The soft-block (`return 75`) fires only if the lock file
already exists with a live foreign holder AT READ TIME. Two concurrent acquires that both read
"no lock" each `mktemp`+`mv` and both set `SESSION_LOCK_HELD=1` → both proceed, racing `.omx`
review/verify state. This is filesystem-agnostic (not drvfs-specific) and is by design "advisory /
prefer one worktree per terminal" (header comment), so it's an accepted limitation, not a regression.
Fix (if hardening wanted): wrap acquire in an `flock` on the lockfile (verified flock works on this
9p) so the read-decide-write is atomic; keep the PID-marker as the holder record.

## DEFECT L3 (LOW) — PID-liveness check is host-relative but the lock can live on a cross-host mount

One-line: `kill -0 $held_pid` checks the LOCAL pid table, but `.omx/state/session.lock` on a
shared `/mnt/z` is visible to other hosts/distros — a foreign-host PID can false-positive "alive".

Reasoning: `session-lock.sh:32,49`. `holder_session` carries `$$@hostname` (`:28`) so OWN-session
re-entry is safe, but the staleness decision (`:49 _session_lock_pid_alive`) uses only the bare PID
against the local kernel. If the same `.omx` is reached from two WSL distros / a second machine over
the drvfs share, a dead holder's PID that happens to be live locally → false contention (spurious
return 75) or a live holder's PID dead locally → wrong stale-reclaim. The named user runs a single
WSL2 distro (one pid namespace, multiple terminals), so this is an edge. Fix: gate the liveness
check on `holder host == local host` before trusting `kill -0`; treat foreign-host holders as opaque
(never reclaim by local PID).

## Non-findings (verified safe on the real target)

- `flock` degradation in `ai-auto setup` (`tools/ai-auto:102-108`): flock present AND real on 9p;
  and even absent, the only destructive step is the single atomic `git rm` (`:222`), all-or-nothing.
  The pre-`git rm` steps (exclude append `:134`, shim writes `:150-173`) are idempotent/guarded.
  Degradation is genuinely safe. CLEAN.
- `${!GIT_CONFIG_KEY_@}` under `set -u` with none set: does NOT trip unbound-var; loop body's
  `[ -n "$_gcv" ]` handles the empty arg. Verified on bash 5.2. The prefix-name indirection is
  bash 2.04+, not a bash-4 dependency. CLEAN.
- `-ef`, `readlink -f`, `mv` atomic rename, `mktemp`, hardlinks: all work on real 9p. CLEAN.
- Hook→shim→engine→sibling chain needs nothing from the profile for its scripts/ helpers
  (PATH self-prepended); the only profile dependency is the tools/ gap in M1.
- `mapfile` (bash 4) appears only in interactive/install paths
  (`install-global-files.sh:296`, `run-ai-reviews.sh`), not in the hook/commit critical path.

## Test suite
- `python3 -m pytest -q`: **237 passed, 1 skipped** (GREEN, matches 237/1).
- `bash scripts/verify-machinery.sh`: GREEN (clean run; see vm log).
