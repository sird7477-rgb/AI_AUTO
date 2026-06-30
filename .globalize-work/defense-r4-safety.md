# Defense Game R4 — RED TEAM safety findings (post-round-3 hardening)

Target: branch `feat/global-toolize`, HEAD 58bcb42. Files: `tools/ai-auto`,
`hooks/{pre-commit,post-commit}`, `scripts/verify.sh`. All repros on throwaway temp
projects (git 2.43.0, bash 5.2.21). Engine source never edited; no engine repo mutated.

Result: **R3-1, R3-2 (GIT_DIR family), R3-3 (GIT_CONFIG family), R3-5, H1 HOLD.**
But the launcher's "scrub ALL git env" claim is **incomplete** — the RCE that R3-3 closed
via the GIT_CONFIG family is **still reachable through the dedicated `GIT_EXTERNAL_DIFF`
env var** (HIGH). Plus 4 lower defects. Ranked: 1 HIGH, 1 MED, 3 LOW.

---

## R4-1 — HIGH — `ai-auto gate` executes inherited `GIT_EXTERNAL_DIFF` → RCE (R3-3 fix moved, not closed)
The R3-2/R3-3 top-of-launcher scrub (`tools/ai-auto:17-21`) unsets the GIT_DIR family and
the **GIT_CONFIG_*** injection family, but NOT the dedicated git-influencing env vars —
notably **`GIT_EXTERNAL_DIFF`**. The gate computes a working-tree provenance hash early
(`scripts/review-gate.sh:39-40` → `git diff` / `git diff --cached`, **patch-producing**),
and patch-producing `git diff` invokes `GIT_EXTERNAL_DIFF` as a command. So an inherited
`GIT_EXTERNAL_DIFF` (a poisoned parent context — the exact threat model R3-3 targets, OR a
developer who legitimately has difftastic/custom difftool exported) runs arbitrary commands
through `ai-auto gate`. R3-3 closed the config-injection form (`GIT_CONFIG_KEY_n=diff.external`
is scrubbed) but the env-var form — which is MORE commonly already set in a real shell — is
not, so the RCE merely changed spelling.

Repro (verified — `/tmp/GATE_PWNED` created):
```
# derived project with a passing scripts/verify-project.sh, an unstaged edit present
export GIT_EXTERNAL_DIFF='touch /tmp/GATE_PWNED'
ai-auto gate            # => /tmp/GATE_PWNED exists  (arbitrary command run)
```
Confined to `gate` (the pre/post-commit shim chain runs NO patch-producing diff, verified —
a shimmed commit with `GIT_EXTERNAL_DIFF` set does NOT fire it). But `gate` is the core
verify-review workflow, so impact is HIGH.
File:line `tools/ai-auto:17-18` (launcher scrub), reached at `scripts/review-gate.sh:39-40`.
Fix: extend the launcher scrub (and, defensively, the hook/shim scrubs) to also unset the
non-config git command-exec / influence vars: `GIT_EXTERNAL_DIFF GIT_DIFF_OPTS GIT_PAGER
GIT_SSH GIT_SSH_COMMAND GIT_PROXY_COMMAND GIT_OBJECT_DIRECTORY
GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_ATTR_NOSYSTEM GIT_CEILING_DIRECTORIES`. Of these,
`GIT_EXTERNAL_DIFF` is the live RCE; `GIT_OBJECT_DIRECTORY`/`GIT_ALTERNATE_OBJECT_DIRECTORIES`
can also silently garble the provenance hash (gate then fails-open to a full review — LOW).

## R4-2 — MED — `ai-auto verify` from a SUBDIR of the engine silently downgrades scope (machinery self-test skipped)
`verify.sh:14` defaults to `full` only when `[ "$(dirname "$AH")" -ef "$(pwd)" ]` — i.e. cwd
is EXACTLY the engine root. Run `ai-auto verify` from any engine subdir (`cd engine/scripts;
ai-auto verify`) and the guard is false → defaults to **product** → the engine's own
`verify-machinery.sh` self-test is **silently skipped**, and `run_product` looks for
`./scripts/verify-project.sh` under the subdir (absent) → exit 1 "NOTHING was verified". A
developer self-testing the engine from a subdir gets a misleading exit-1 instead of the
machinery run; and if that subdir happens to carry a passing `scripts/verify-project.sh` it
exits 0 GREEN with the machinery never run (silent-skipped verification). Same `-ef` also
mis-fires for an engine reached via a bind-mount on a *different* filesystem (dev/inode differ
→ product). Verified: from `$ENGINE/scripts` the guard resolves `scope=product`; from
`$ENGINE` it resolves `scope=full`.
File:line `scripts/verify.sh:14`.
Fix: anchor self-host detection on the repo, not cwd — `git -C "$(pwd)" rev-parse
--show-toplevel` `-ef` `$(dirname "$AH")` (or string-compare resolved toplevels), so any cwd
inside the engine worktree still selects `full`.

## R4-3 — LOW — setup lock fd is still NOT close-on-exec (R3-4 unfixed; re-confirmed)
R3-5 (common-dir lock) was applied (`tools/ai-auto:99`) but R3-4 was NOT: `exec
{_lockfd}>"$_lockfile"` (`:105`) opens the flock fd without CLOEXEC. Verified on bash 5.2.21
— a child after `exec` still sees fd 10 open on the lockfile. A long-lived grandchild (git
`core.fsmonitor` daemon spawned by a later git op, or anything `ai-project-profile`
backgrounds) inherits the open fd and holds the advisory lock after setup exits → the next
`ai-auto setup` on that project blocks indefinitely.
File:line `tools/ai-auto:105`.
Fix: run the locked region under `flock -x "$fd" -c '…'` in a subshell, or close the fd in
children (open it `>&-`-safe), so the descriptor never leaks to long-lived grandchildren.

## R4-4 — LOW — self-host guard false-positive: a legit project vendoring BOTH marker files is refused
The existence-based guard (`tools/ai-auto:85`, R3-1) ABORTs setup whenever `$top` has BOTH
`scripts/verify-machinery.sh` AND `tools/ai-auto`. A legitimate project that vendors a tool
literally named `tools/ai-auto` plus any `scripts/verify-machinery.sh` (as data, not the
engine) is wrongly classified as the engine and can never be globalized. Fail-SAFE (exit 1,
no mutation — verified), so not data loss, but the guard is content-blind: it matches names,
not engine identity. Niche.
File:line `tools/ai-auto:84-85`.
Fix: confirm engine identity by a content signature (grep an engine-only sentinel line inside
`tools/ai-auto`/`verify-machinery.sh`) rather than mere co-presence of the two filenames.

## R4-5 — LOW — re-adopt from the PRE-shim copy-model era does NOT upgrade hooks (stale unscrubbing hooks persist)
The shim-overwrite guard keys on the literal marker `AI_AUTO shim` (`tools/ai-auto:146`).
Across rounds 1-3 the marker is stable, so re-adopting an older *shim* upgrades correctly
(verified). BUT a project onboarded under the OLD copy model had **full hook bodies** copied
into `.git/hooks` (no `AI_AUTO shim` marker); on `ai-auto setup` those match the
"existing custom hook" branch → left untouched with only a WARNING. The stale pre-globalize
hook (which lacks the R3-3 GIT_CONFIG / R3-2 GIT_DIR scrubs) therefore persists silently, and
the upgrade requires a manual merge the user may never do.
File:line `tools/ai-auto:146-149`.
Fix: recognize legacy engine-hook bodies too (grep a broader engine signature, e.g.
`AI_AUTO worktree-safe hook` / `AI_AUTO post-commit guard`) and treat them as
framework-owned → safe to replace with the current shim.

---

## Positives — R3 fixes / new surfaces that HELD under R4 attack
- **R3-1** existence guard: engine self-host ABORTs (exit 1); bind-mounted engine still
  caught (files exist via mount); engine-as-submodule of a parent does NOT cause parent
  de-pollution to touch engine files (FRAMEWORK_PATHS are root-relative). Dangerous-miss closed.
- **R3-2** GIT_DIR family scrub: `ai-auto gate` under inherited `GIT_DIR/GIT_WORK_TREE`
  resolves the cwd repo, not the foreign one. Wrong-repo gate closed.
- **R3-3** GIT_CONFIG family: `GIT_CONFIG_KEY_n=core.fsmonitor/diff.external/...` no longer
  reaches the shim/hook/gate git calls. (The RCE survives only via the *non*-config
  `GIT_EXTERNAL_DIFF` env var — R4-1.)
- **R3-5** common-dir lock: lock path now `git rev-parse --git-common-dir` (`:99`), with
  relative/empty fallbacks; cross-worktree setups serialize on the shared dir.
- **Spaces / newline / unicode** path through the WHOLE setup→shim→commit chain: project dir
  `"we ird\nnéwline proj"` — setup de-pollutes correctly, shims install, a subsequent commit
  fires the shim. No word-splitting/quoting break (engine path baked via quoted `"$baked"`).
- **`git rm` flag-injection**: removal is `git rm --quiet -- "${removed[@]}"` (`:222`) — the
  `--` separator is present and all FRAMEWORK_PATHS are literal non-`-` names; a `-rf…`-looking
  pathspec cannot be interpreted as a flag.
- **Empty `removed[]` under set -e**: `git rm` is guarded by `((${#removed[@]}))` (`:221`);
  the report `((…)) && printf` lines do not trip `set -e`.
- **Abort exit codes**: no-such-dir, not-a-git-repo, self-host, dirty-index, legit-vendor
  false-positive — all exit 1 (verified), none leave a partial index.
- **H1** engine-aware default scope from the engine ROOT and from a derived project resolves
  correctly (full vs product); only the engine-SUBDIR case regresses (R4-2).
