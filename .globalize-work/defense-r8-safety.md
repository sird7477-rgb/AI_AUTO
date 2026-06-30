# RED TEAM Round 8 — git-exec defense bypass + new-class hunt

HEAD b581bf5 (feat/global-toolize). Read-only analysis + temp-repo PoCs. git 2.43.0.

## DEFECTS: 1 (highest HIGH)

### [HIGH — RCE] clean-filter executes via `git diff --no-index` on untracked content (bypasses BOTH defense layers)

`scripts/collect-review-context.sh:1400`

```
review_git diff --no-ext-diff --no-textconv --no-index -- /dev/null "$file"   # MISSING --no-filters
```

This is the ONE `--no-index` content-read call site, and it OMITS `--no-filters`.
A repo-local `.gitattributes` mapping (`u.txt filter=evil`) + a repo-local `.git/config`
`[filter "evil"] clean = <cmd>` causes `git diff --no-index` to run the **clean** filter
command on the file content. Neither defense layer stops it:
- Process chokepoint (`hooks/git-scrub.sh`) pins only `core.fsmonitor` / `diff.external`
  empty — it does NOT pin `filter.<name>.clean`.
- `review_git` (`-c diff.external= -c core.fsmonitor= -c core.attributesFile=/dev/null
  --no-pager` + call-site `--no-ext-diff --no-textconv`) neutralizes the diff/textconv/
  external-diff drivers but NOT the clean filter. `core.attributesFile=/dev/null` only
  ignores the USER/GLOBAL attributes file; the IN-REPO `.gitattributes` is still honored.

The invariant is even documented in `scripts/git-harden.sh:13` ("`--no-filters` on
hash-object / `--no-index` content reads") and is correctly applied on the provenance
path (`review-gate.sh:57` `hash-object --no-filters`) — but this one untracked-content
diff site drifted un-hardened. Untracked files are the most attacker-controlled surface
(a brand-new file the malicious project drops).

REPRO (verified — fires under the full two-layer form):
```
T=/tmp/poc; rm -rf $T; mkdir -p $T; cd $T
git init -q; git config user.email t@t.t; git config user.name t
echo 'u.txt filter=evil' > .gitattributes
git config filter.evil.clean "touch $T/PWNED; cat"
printf 'hello\n' > u.txt        # untracked
GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0='' \
  GIT_CONFIG_KEY_1=diff.external GIT_CONFIG_VALUE_1='' \
  git -c diff.external= -c core.fsmonitor= -c core.attributesFile=/dev/null --no-pager \
  diff --no-ext-diff --no-textconv --no-index -- /dev/null u.txt   # -> $T/PWNED created
```
Adding `--no-filters` to the call blocks it (verified).

TRIGGER PATH (gate): operator runs `ai-auto gate` with the documented opt-in
`REVIEW_INCLUDE_UNTRACKED_CONTENT=1`. `tools/ai-auto` sources git-scrub.sh (chokepoint env
active) -> `review-gate.sh:650` runs `run-ai-reviews.sh` (the gate's `env -u
REVIEW_INCLUDE_UNTRACKED_CONTENT` at :499/:532 is scoped to verify.sh only, NOT to
run-ai-reviews) -> `run-ai-reviews.sh:222` invokes collect-review-context.sh with
`INCLUDE_UNTRACKED_CONTENT=1` -> `collect-review-context.sh:1387` gate true ->
`:1400` runs on each untracked text file -> clean filter executes = RCE.
Precondition: the `REVIEW_INCLUDE_UNTRACKED_CONTENT=1` opt-in (a supported review mode
whose entire purpose is to inspect untracked attacker files). Default (flag unset) is not
vulnerable because line 1400 is not reached.

FIX: add `--no-filters` to `collect-review-context.sh:1400`
(`review_git diff --no-ext-diff --no-textconv --no-filters --no-index -- /dev/null "$file"`),
matching the documented git-harden.sh invariant and the provenance path.

## Vectors probed and found CLEAN

- **`--stat` / `--name-only` / `--quiet` / `git show --stat` (the "plain git is safe"
  claim):** empirically confirmed they do NOT fire textconv or external-diff drivers; only
  a full `git diff` does, and every such call is routed through `review_git` with
  `--no-ext-diff --no-textconv`. Claim holds.
- **Other config-exec keys (core.pager / core.editor / sequence.editor /
  core.sshCommand / credential.helper / url.*.insteadOf / uploadpack / receivepack /
  core.hooksPath / filter.*.smudge):** none fire, because the engine's git command set on
  the victim repo is read-only (rev-parse, diff, ls-files, show --stat, hash-object, rm)
  and never includes a command that triggers these (no commit/merge/am/rebase/fetch/push/
  clone/add/checkout/stash/archive, and no TTY-stdout pager-using call). core.pager needs
  an interactive TTY the gate/hooks never provide (output piped/captured).
- **`core.hooksPath` -> project hook:** no engine git call fires a git hook (hash-object,
  diff, status, ls-files, rm don't), so an in-repo `core.hooksPath` is inert against the
  engine. The user's own `git commit` runs the installed scrubbing shim.
- **`include.path` / `includeIf` chaining:** can only set keys repo-local config could
  already set; cannot beat the env `GIT_CONFIG_*` pins (highest precedence after `-c`).
- **`GIT_CONFIG_COUNT` clobber / attacker append:** git-scrub.sh unsets the entire
  `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_@` / `GIT_CONFIG_VALUE_@` / `GIT_TRACE@` family
  (wildcard `${!prefix@}` loop) BEFORE exporting COUNT=2; an inherited attacker
  KEY_2/VALUE_2 is dropped. No engine script in the gate path re-sets GIT_CONFIG_COUNT
  (only verify-machinery tests do), so the pins are never un-set downstream. `review_git`
  uses `-c` (higher precedence), not the env count, so no conflict.
- **`ai-auto setup` (git rm / symlink / filter):** `git rm` does not run clean/smudge
  filters; symlinked managed paths are detected (`-L`) and kept; `git rm -- "${removed[@]}"`
  is atomic with `--`; self-host + dirty-index guards run before any mutation; no `git add`/
  `commit`/`stash`/`checkout` is run on the victim repo. CLEAN.
- **eval / source / sed -i / xargs on attacker content:** `doc-budget.sh:260` xargs->awk
  treats file content as DATA (no eval); no gate/setup/hook script evals AGENTS.md /
  manifest / .omx / commit-message / branch-name content. `eval` only in `ai-home --cd`
  (engine-internal, not attacker-fed). CLEAN.
- **provenance untracked hashing (`review-gate.sh:57`):** correctly uses
  `hash-object --no-filters`. CLEAN (this is what line 1400 should have mirrored).
