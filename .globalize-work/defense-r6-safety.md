# Defense Game R6 — RED TEAM safety findings (post-round-5 hardening)

Target: branch `feat/global-toolize`, HEAD b9a480e. git 2.43.0, bash 5.2.21.
All repros on throwaway temp projects under the scratchpad. Engine source never edited (read-only).

Result: **R5 env-scrub single-source + R5-2/R5-3 denylist additions HOLD. BUT R5-1 (the
project-local `.gitattributes`/config diff-driver RCE) is only PARTIALLY fixed — it was
neutralized in `review-gate.sh` + `summarize-ai-reviews.sh` provenance, but the SAME RCE class
is still LIVE in `scripts/collect-review-context.sh`, which `ai-auto gate` runs UNCONDITIONALLY
(`review-gate.sh:608`) before any skip check. So `ai-auto gate` is STILL RCE under a project
with a malicious `.git/config` + `.gitattributes`.** The R5-1 regression test gives false
confidence: it only extracts `review_provenance_hash`, never the context collector.
Ranked: **1 HIGH (R5-1 fix incomplete), rest CLEAN.**

---

## R6-1 — HIGH — `ai-auto gate` STILL runs project-local `.gitattributes`/config diff drivers via `collect-review-context.sh` → RCE (R5-1 fix is incomplete)
R5-1 hardened the provenance `git diff`/`hash-object` at `review-gate.sh:39-59` and
`summarize-ai-reviews.sh:820-840` (via the `review_git` wrapper + `--no-ext-diff/--no-textconv/
--no-filters`). But the gate runs `"$AH/collect-review-context.sh"` UNCONDITIONALLY at
`review-gate.sh:608` — BEFORE the docs-only skip (`:611`) and BEFORE the provenance exact-match
skip (`:628`). `collect-review-context.sh` uses RAW `git` (no `review_git`, no `-c diff.external=`,
no `--no-ext-diff/--no-textconv`) at multiple PATCH-PRODUCING call sites, so a project-local
`.gitattributes` (`a.txt diff=evil`) + `.git/config` (`[diff "evil"] command=…` or `textconv=…`)
executes attacker code through the gate. Env scrubbing cannot touch this — it lives IN the repo.

Vulnerable call sites in `scripts/collect-review-context.sh` (all raw, all patch-producing):
- `:76-77` `tracked_diff_bytes()` — `git diff` / `git diff --cached` (runs in `auto` mode to size light-vs-full; fires the external-diff/textconv driver).
- `:147` / `:155` `write_diff()` — `git diff` / `git diff --cached` (full review context).
- `:166` `write_diff()` — `git show --format= --find-renames HEAD` (post-commit / clean-tree context path).
- `:1390` `git diff --no-index -- /dev/null "$file"` (untracked-content path, gated on `INCLUDE_UNTRACKED_CONTENT=1`).

Repro (verified — payload markers created; this is the EXACT child `ai-auto gate` runs at :608):
```
tmp=$(mktemp -d); cd "$tmp"; git init -q; git config user.email t@t; git config user.name t
echo hello>a.txt; git add a.txt; git commit -qm init
git config diff.evil.command  '/bin/sh -c "touch /tmp/PWN_EXT; true"'
git config diff.evil.textconv '/bin/sh -c "touch /tmp/PWN_TXT; cat"'
printf 'a.txt diff=evil\n' > .gitattributes
echo changed>>a.txt                         # unstaged edit -> has_worktree_diff
OUT_DIR="$tmp/.omx/rc" bash /root/workspace/ai-lab-globalize/scripts/collect-review-context.sh
ls /tmp/PWN_EXT                              # => exists (external-diff command EXECUTED)
# textconv-only variant (unset command, keep textconv) -> /tmp/PWN_TXT created  [verified]
# git show --format= HEAD path (committed change) -> driver fires             [verified]
# git diff --no-index untr.txt (INCLUDE_UNTRACKED_CONTENT=1)                   [verified]
```
Verified SAFE (R5's "name-only/--stat are inert" claim HOLDS): `git diff --stat` (`:113,121`),
`git show --stat` (`:132`), `git diff --name-only` and `git diff --quiet`/`--exit-code`
(`:28,46,360-361,…`) do NOT exec — confirmed clean against the same poisoned repo.

File:line `scripts/collect-review-context.sh:76-77,147,155,166,1390`, reached via
`scripts/review-gate.sh:608` (unconditional, pre-skip).
Fix: add a `review_git()` wrapper (mirror `review-gate.sh:39-40`) and route EVERY patch-producing
call through it with `--no-ext-diff --no-textconv` (and `--no-filters` on any hash-object/no-index
content read): `:76,77,147,155` `git diff … --no-ext-diff --no-textconv`; `:166`
`git show --no-ext-diff --no-textconv --format= …`; `:1390`
`git -c diff.external= --no-pager diff --no-ext-diff --no-textconv --no-index …`. Confirmed with
those flags every marker stays UN-created.

### R6-1b — supporting — the R5-1 regression test does NOT cover this call site (false-green)
`verify-machinery.sh:7045-7080` extracts ONLY the `# >>> review-provenance-shared <<<` block from
`review-gate.sh` and calls `review_provenance_hash` in a poisoned repo. It never invokes
`collect-review-context.sh`, so the suite reports R5-1 "closed" while the gate's real, earlier
exec surface stays open. Fix: extend the fixture to run `collect-review-context.sh` (full +
`INCLUDE_UNTRACKED_CONTENT=1`) in the poisoned repo and assert no EXT/TXT marker.

---

## Surfaces re-checked under R6 attack — CLEAN / HELD
- **Single-source scrub (F1)**: `hooks/git-scrub.sh` is the only copy; `tools/ai-auto:19`,
  `hooks/pre-commit:18`, `hooks/post-commit:15`, and the baked shim (`tools/ai-auto:163-165`)
  all SOURCE it. Shim bakes `AI_AUTO_HOME` via `readlink -f` and sources the baked path — correct.
- **R5-2 / R5-3 denylist additions PRESENT**: `git-scrub.sh:19-26` now unsets `GIT_TRACE@`
  (loop), `GIT_TEMPLATE_DIR GIT_ATTR_NOSYSTEM GIT_CEILING_DIRECTORIES`, plus the GIT_DIR /
  GIT_CONFIG_* / exec families. The two R5 env misses are closed.
- **Env scrub is inherited by gate children**: `ai-auto` sources the scrub at `:19`, so
  `collect-review-context.sh` / `run-ai-reviews.sh` / `summarize` / `verify.sh` run under the
  scrubbed env. (R6-1 is LOCAL-config, not env — unaffected by this and that is the whole point.)
- **`run-ai-reviews.sh`**: only `git diff --name-only` (`:1808-1809,1878-1879,1949-1950`) — safe
  (verified non-exec). `summarize-ai-reviews.sh` provenance uses its own `review_git` (`:820`).
- **argv injection**: `ai-auto` dispatch (`:256-260`) is a `case` with `exec … "$@"` — no `eval`,
  proper quoting; no injection. `setup` path-normalizes `$1` via `cd && pwd` (`:69-70`).
- **`git config --local` alias expansion**: git aliases cannot shadow built-in subcommands, and
  every engine git call is a builtin (`diff`/`show`/`rev-parse`/`hash-object`/`ls-files`/`status`),
  so a project `[alias]` (incl. `!shell`) never expands. Not exploitable.
- **project `.git/hooks/` pre-existing**: `ai-auto setup` refuses to clobber a non-shim,
  non-legacy hook (`tools/ai-auto:149-153`, warns + skips). The engine/gate never invokes a
  project hook itself (it does not `git commit`); only the user's own commit triggers it (normal
  git). No engine-side escalation.
- **setup lock CLOEXEC (R5-4)**: the advisory `ai-project-profile` child now closes the lock fd
  (`tools/ai-auto:188-189`, `{_lockfd}>&-`). The remaining `exec {_lockfd}>` at `:113` is still
  non-CLOEXEC but the only post-lock child is fd-closed, so the leak is mitigated in practice.
- **verify-scope**: `verify.sh` engine-vs-product fold unchanged (R4-2 held); no derived fold.

## META
R5 fixed R5-1 at the provenance call site but treated "the gate's exec surface" as just the
provenance hash. The gate's FIRST git work is the context collector, which was never wrapped.
Root cause confirms the R5 META: a per-call-site neutralization that is applied file-by-file WILL
miss a sibling. The durable fix is the allowlist approach (reconstruct a minimal git env) PLUS a
single shared `review_git` wrapper sourced by collect-review-context.sh / review-gate.sh /
summarize so a new patch-producing call cannot be added un-hardened.
