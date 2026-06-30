# Defense Game R1 — RED TEAM safety findings (ai-auto setup / migration / hook-shim)

Target: branch `feat/global-toolize`, HEAD aa8d028. Files: `tools/ai-auto`,
`hooks/{pre-commit,post-commit}`, SPEC.v3.md. All findings reproduced with throwaway
temp projects (git 2.43.0, bash 5.2). Engine never mutated (verified).

Ranked: 1 HIGH, 4 MED, 1 LOW + 1 version-note. Plus positives (guard holds).

---

## F1 — HIGH — engine move/rename bricks EVERY normal commit in EVERY globalized project
`tools/ai-auto:120-127` bakes an absolute engine path into the shim; the shim does
`exec "$AI_AUTO_HOME/hooks/<hook>"` with NO existence check or fallback. If the engine
dir is later moved/renamed/reinstalled to a new path, `exec` hits a dead path → bash
exits 127 → pre-commit returns nonzero → commit ABORTED. Affects all projects set up
against that engine simultaneously, with a cryptic `No such file or directory`.

Repro:
```
cp -a <engine> /tmp/engine-copy
mkdir P && cd P && git init && echo hi>f && git add -A && git commit -m init
/tmp/engine-copy/tools/ai-auto setup "$PWD"        # bakes /tmp/engine-copy
echo a>>f; git add -A; git commit -m c1            # OK
mv /tmp/engine-copy /tmp/engine-moved
echo b>>f; git add -A; git commit -m c2            # FAILS: .git/hooks/pre-commit: line 6:
                                                   #   /tmp/engine-copy/hooks/pre-commit: No such file or directory
git commit --no-verify -m x                        # only escape (also errors on post-commit)
```
Only `--no-verify` works; post-commit shim also errors (advisory, non-blocking, but noisy).
Recovery = re-run `ai-auto setup` in *every* project. SPEC C5 chose baked-path for
profile-independence but never guarded engine relocation.
Fix: shim should test `[ -x "$AI_AUTO_HOME/hooks/<hook>" ]`; on miss emit an actionable
message ("engine moved — re-run `ai-auto setup`") instead of a raw exec failure (decide
fail-open advisory vs clear fail-closed; current behavior is opaque fail-closed).

## F2 — MED — launcher never unsets GIT_*; stray GIT_DIR makes setup mutate the WRONG repo
`ai_auto_setup` (`tools/ai-auto:55-130`) runs `git -C "$proj" rev-parse --show-toplevel`
and all `git -C "$top" rm/ls-files` WITHOUT clearing inherited GIT_*. The hooks bodies
unset GIT_* (`hooks/pre-commit:14`), but the launcher does not. Git env vars override `-C`
discovery, so when GIT_DIR/GIT_INDEX_FILE/GIT_WORK_TREE are present (any git-invoked
context: a parent hook, `git rebase --exec`, husky/lefthook, some IDE terminals mid git-op)
setup resolves toplevel = GIT_DIR's repo and `git rm`s framework files in THAT repo, not
the named project.

Repro (verified): target & victim each vendor a pristine `docs/WORKFLOW.md`; running
`GIT_DIR=$VICTIM/.git GIT_WORK_TREE=$VICTIM ai-auto setup "$TARGET"` printed
`project=…/g2-victim` and staged `D docs/WORKFLOW.md` in VICTIM; TARGET untouched.
(Engine itself stays protected — GIT_DIR=engine still trips the `[ "$top" = AI_AUTO_HOME ]`
guard — but any other repo is fair game.)
Fix: `unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_NAMESPACE`
at the top of `ai_auto_setup`, before resolving `proj`/`top`.

## F3 — MED — non-atomic de-pollution: a staged-modified managed file aborts setup mid-loop
`tools/ai-auto:74-83` does `git rm` per file inside a `set -euo pipefail` loop. `cmp`
compares WORKING TREE to pristine, but `git rm` (no -f) also refuses if the file has index
content differing from HEAD. A managed file that is pristine in the working tree but has
staged (uncommitted) index changes → `git rm` errors → set -e aborts the whole run AFTER
earlier files were already staged-deleted. Hooks/.omx-exclude never installed. The error
is a raw git message; re-run hits the same file again → cannot recover without manual
`git reset` of that path. SPEC §8 promised "fail-closed on a dirty tree that risks loss"
but there is no pre-flight dirtiness check.

Repro (verified): commit pristine `docs/INCIDENT_OPS.md` + `docs/WORKFLOW.md`; stage an
edit to WORKFLOW then restore its working copy to pristine (`MM` state). `ai-auto setup`
→ INCIDENT_OPS staged `D`, then `error: ... has staged content different from both the
file and the HEAD: docs/WORKFLOW.md`, exit 1, partial migration.
Fix: pre-scan all managed paths for index/worktree divergence and abort cleanly BEFORE
any mutation; or collect the removable set and stage atomically.

## F4 — MED — false-positive self-host ABORT blocks a legit project from globalizing
The sentinel `[ -f "$top/scripts/review-gate.sh" ] && [ -d "$top/templates/domain-packs" ]`
(`tools/ai-auto:64`) misfires. `scripts/review-gate.sh` IS in `FRAMEWORK_PATHS` (line 37),
so any OLD vendored-copy project HAS it. A project that also authored its own domain pack
under `templates/domain-packs/` (explicitly encouraged by `DOMAIN_PACK_AUTHORING_GUIDE.md`)
trips both sentinel halves → `ABORT — target is the AI_AUTO engine repo` → it can NEVER be
de-polluted.

Repro (verified): project with vendored `scripts/review-gate.sh` + own
`templates/domain-packs/my-pack/pack.yaml` → ABORT, exit 1.
Fix: use an engine-unique marker not in FRAMEWORK_PATHS (e.g. `scripts/verify-machinery.sh`
+ `scripts/install-global-files.sh`), or rely on path identity (`$top -ef $AI_AUTO_HOME`)
rather than a content sentinel that overlaps with legitimate project content.

## F5 — MED — mutation-before-install ordering: any step-(c)/(d) failure leaves staged deletions
The order is git rm (step b) FIRST, then `.omx` exclude (c) and hook install (d). The hook
`cat > "$dst"` and `chmod` run under set -e. On a genuinely unwritable hooks dir
(non-root user, immutable/read-only FS, restrictive CI) or any cat failure, setup aborts
AFTER deletions are staged → half-migrated repo with no hooks. (As root, `chmod 555
.git/hooks` did NOT reproduce — root ignores dir perms — so this needs a non-root/immutable
FS to trigger; same root cause and fix family as F3.)
Fix: install hooks + exclude FIRST (or build the full plan), do the index `git rm`s last as
one atomic step, so a late failure leaves nothing staged.

## F6 — LOW — symlink content-compare: a deliberately-symlinked managed path is git-rm'd
`cmp -s "$top/$f" "$pristine"` (`tools/ai-auto:77`) follows symlinks and ignores file
TYPE/MODE. A project that replaced a framework file with a symlink (mode 120000) whose
target content equals pristine is judged "pristine vendored copy" → `git rm` removes the
symlink customization. Same blind spot drops a tracked exec-bit change (cmp = content only).
Repro (verified): `docs/WORKFLOW.md` as a symlink to an external copy of the pristine bytes
→ staged `D` ("Removed (pristine vendored copies)").
Fix: skip non-regular tracked entries, or compare `git ls-files -s` mode alongside content.

## N1 — NOTE/LOW — core.hooksPath shim placement is git-version-dependent
On git 2.43 `git rev-parse --git-path hooks` HONORS `core.hooksPath` — shims correctly
landed in the active `.githooks` dir (verified, not a defect here). On older git
(roughly < 2.34) `--git-path hooks` returns `.git/hooks` regardless of core.hooksPath, so
shims would be installed where git never runs them → gate silently inert while setup
reports success. Latent on older toolchains.
Fix/guard: read `core.hooksPath` explicitly (`git config --get core.hooksPath`) and resolve
relative to the worktree, instead of relying solely on `--git-path hooks`.

---

## Positives (guard held — no defect)
- Self-host guard ABORTS correctly for: engine via symlinked path, a linked engine
  WORKTREE (domain-packs present in checkout), running from an engine SUBDIR with no arg,
  and a clean engine home (EXP H/I/J verified).
- Missing global pristine (a path the old model vendored but engine no longer ships):
  `[ -f "$pristine" ]` false → file KEPT + reported, never deleted (safe, per code).
- Whitespace/CRLF customizations are byte-differences → `cmp` reports DIFF → KEPT. No
  customized file is wrongly rm'd via whitespace/CRLF (the data-loss direction is safe).
- Pre-existing NON-shim hooks are detected (`grep 'AI_AUTO shim'`) and left untouched with a
  warning (`tools/ai-auto:116-118`).
- pre-commit preserves pytest exit-5 / no-runner handling and fails closed; post-commit
  always exit 0 (advisory) — both correct per SPEC C7.
