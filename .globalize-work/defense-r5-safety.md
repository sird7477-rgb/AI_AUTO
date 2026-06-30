# Defense Game R5 — RED TEAM safety findings (post-round-4 hardening)

Target: branch `feat/global-toolize`, HEAD 775a081. Files: `tools/ai-auto`,
`hooks/{pre-commit,post-commit}`, `scripts/{verify.sh,review-gate.sh}`. git 2.43.0, bash 5.2.21.
All repros on throwaway temp projects under the scratchpad. Engine source never edited.

Result: **R4-1 (GIT_EXTERNAL_DIFF now scrubbed), R4-2 (verify-scope toplevel `-ef`), tools/ PATH
M1, setup atomic-rm/flock/dirty/self-host, R4-5 legacy-hook upgrade — ALL HOLD.** BUT the
round-4 "comprehensive git-exec-env scrub" is **DEFEATED**: the gate's provenance `git diff` +
`git hash-object` execute attacker code from a **project-local `.gitattributes` + `.git/config`
diff/filter driver**, which env scrubbing CANNOT touch (HIGH). Plus 2 denylist-incompleteness
defects (the scrub is a denylist; it is still missing vars) and 1 persisting LOW.
Ranked: **1 HIGH, 3 LOW. The denylist design is the root cause — see meta note.**

---

## R5-1 — HIGH — `ai-auto gate` runs project-local `.gitattributes`/config diff+filter drivers → RCE (env scrub does NOT close it)
The round-4 scrub is sold as the comprehensive RCE defense ("NO inherited git-exec-env var can
run arbitrary commands", `tools/ai-auto:16-20`). But git's **standard code-exec mechanism is the
repo's OWN local config + `.gitattributes`, not env vars** — and the gate produces patches that
honor them. `review_provenance_hash` (`scripts/review-gate.sh:36-49`) runs **patch-producing**
`git diff` (`:39-40`) and `git hash-object <file>` on each untracked file (`:47`). A patch-
producing `git diff` invokes a per-attribute external-diff `command` AND a `textconv`; `git
hash-object` (no `--no-filters`) runs the `clean` **filter** driver. All three are defined by a
project-local `.gitattributes` (`path diff=evil` / `filter=evilf`) + `.git/config`
(`[diff "evil"] command/textconv`, `[filter "evilf"] clean`). These live in the repo, NOT the
env, so unsetting `GIT_EXTERNAL_DIFF`/the GIT_CONFIG_* family does **nothing**.
`review_provenance_hash` is reached on EVERY proceed via `review_provenance_record`
(`:85-87`) and on every subsequent gate via `review_provenance_decision` (`:141`, called at
`:618`). So `ai-auto gate` = arbitrary code execution under a project whose `.git/config` an
attacker can write (a cloned/shared/templated repo, a malicious setup script `git config` line,
a prior low-priv write to `.git/`), or a fail-open hit for a dev with a legit custom difftool.

Repro (all three verified — PWNED markers created, with the FULL launcher scrub applied):
```
cd $tmp; git init -q; echo hello>a.txt; git add a.txt; git commit -qm init
git config diff.evil.command  '/bin/sh -c "touch /tmp/EXT;     true"'
git config diff.evil.textconv '/bin/sh -c "touch /tmp/TXT; cat"'
git config filter.evilf.clean '/bin/sh -c "touch /tmp/CLEAN; cat"'
printf 'a.txt diff=evil\nuntr.txt filter=evilf\n' > .gitattributes
echo changed>>a.txt; echo secret>untr.txt          # unstaged edit + untracked file
# under full launcher env scrub:
git diff >/dev/null 2>&1                              # => /tmp/EXT (and /tmp/TXT) created
git ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
  git hash-object "$f" >/dev/null 2>&1; done          # => /tmp/CLEAN created
```
File:line `scripts/review-gate.sh:39-40,47` (reached via `:141` and `:85-87`).
Fix (neutralize AT THE CALL SITE — env-independent, VERIFIED clean): `git diff
--no-ext-diff --no-textconv` on `:39-40` (and any other patch-producing diff), and `git
hash-object --no-filters` on `:47`. Confirmed all three markers stay clean with these flags.
NOTE the safe siblings do NOT exec: `git diff --quiet` (setup de-pollution `tools/ai-auto:219,232`)
and `git diff --name-only` (machinery-fold `review-gate.sh:508`, hooks) are non-patch — verified
clean — so only the provenance path needs the flags.

## R5-2 — LOW — denylist still missing `GIT_TRACE*` → arbitrary-file append/clobber through any gate/hook git call
The scrub is a DENYLIST and `GIT_TRACE` / `GIT_TRACE2*` are not in it. An inherited
`GIT_TRACE=/abs/path` makes EVERY `git` the launcher/gate/hook runs append trace text to that
absolute path (verified: 94 bytes written through a scrubbed `git diff`). Not RCE, but a
poisoned-parent-context primitive (the same threat model R3-3/R4-1 target) to append-fill /
clobber a victim file (e.g. append junk to a config/authorized_keys-adjacent path the user can
write) on every git op. Survives the round-4 scrub untouched.
File:line `tools/ai-auto:23-26` (+ the 3 byte-identical copies).
Fix: add `GIT_TRACE GIT_TRACE2 GIT_TRACE2_EVENT GIT_TRACE2_PERF GIT_TRACE_PACKET
GIT_TRACE_SETUP GIT_TRACE_PACK_ACCESS` to the denylist — OR (preferred) stop denylisting.

## R5-3 — LOW — denylist missing `GIT_TEMPLATE_DIR` → hook injection into verify-machinery's throwaway `git init` fixtures (engine self-test RCE)
Not in the denylist. The engine self-test (`scripts/verify-machinery.sh`) creates throwaway
repos with `git init -q` (`:6475,6503,6520,6565,…`) and then commits in them. An inherited
`GIT_TEMPLATE_DIR=/evil` makes each `git init` copy `/evil/hooks/*` into the fixture, so the
fixture's own `git commit` executes the attacker hook → RCE during `ai-auto verify` (full scope)
under a poisoned env. Narrow: engine-self-host only (`git init` never runs in a derived project —
`automation-doctor.sh:513` only *prints* "git init"), and needs a poisoned parent env. Still a
clean denylist miss.
File:line `scripts/verify.sh` / `tools/ai-auto:23-26` (scrub does not list it).
Fix: add `GIT_TEMPLATE_DIR GIT_ATTR_NOSYSTEM GIT_CEILING_DIRECTORIES` to the denylist — OR
allowlist (below).

## R5-4 — LOW — setup lock fd still NOT close-on-exec (R4-3 / R3-4 unfixed; re-confirmed)
Unchanged from R4-3: `exec {_lockfd}>"$_lockfile"` (`tools/ai-auto:113`) opens the flock fd
without CLOEXEC, so a long-lived grandchild (an fsmonitor daemon, a backgrounded
`ai-project-profile`) inherits fd and holds the advisory lock after setup exits → the next
`ai-auto setup` on that project blocks. Verified the fd is still inheritable on bash 5.2.21.
File:line `tools/ai-auto:113`.
Fix: hold the lock via `flock -x "$fd" -c '…'` in a subshell, or open the fd CLOEXEC.

---

## META — the git-env DENYLIST is structurally the wrong fix (root cause of R5-1/2/3)
R4 doubled down on enumerating git-exec env vars. R5-1 proves the **primary** RCE surface
(`.gitattributes`+local config) is NOT env at all, and R5-2/R5-3 add two more env vars the
denylist forgot. A denylist over git's influence surface is unwinnable. Recommend BOTH:
(1) neutralize at every git call site that touches project content (`--no-ext-diff
--no-textconv --no-filters`, and for the de-pollution compares already-safe `--quiet`); and
(2) replace the four-copy denylist with an ALLOWLIST — run the engine's git under a minimal,
explicitly-reconstructed git env (clear the whole `GIT_*` namespace via `${!GIT_@}`, then
re-export only what's needed) so future git versions adding new exec vars are closed by default.

## Positives — R4 fixes / surfaces that HELD under R5 attack
- **R4-1** `GIT_EXTERNAL_DIFF` is now in the launcher+shim+hook denylist (verified present,
  byte-identical across all 4 copies); the env-var form of the diff-driver RCE is closed
  (the LOCAL-CONFIG form is R5-1, a different mechanism).
- **R4-2** verify-scope: `git rev-parse --show-toplevel -ef "$(dirname "$AH")"` (`verify.sh:18`)
  folds machinery from ANY engine subdir and selects `product` for a derived project; cwd
  outside any repo → empty toplevel → `product` → fail-closed. No derived-project fold, no
  engine fail-to-fold found.
- **tools/ PATH (M1)**: all bare-name helpers the engine calls resolve — the 22 `.sh`/`.py`
  helpers + `verify-machinery.sh` are in `scripts/`; the 3 dashless internals
  (`ai-project-profile`, `knowledge-capture`, `knowledge-collect`) are in `tools/`, now on PATH.
  No bare-name helper in neither dir.
- **setup**: self-host guard ABORTs (exit 1, no mutation); dirty-index precheck; atomic
  all-or-nothing `git rm --quiet -- …`; flock on the common git dir; `.gitattributes` on a
  managed file does NOT exec during de-pollution (`git diff --quiet` is non-patch — verified).
- **R4-5** legacy full-body hooks (`AI_AUTO worktree-safe hook` / `AI_AUTO post-commit guard`)
  are now recognized and upgraded to the scrubbing shim (`tools/ai-auto:159-161`).
