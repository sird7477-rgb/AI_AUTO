# Defense R12 — RED TEAM safety findings

HEAD aa51a76 (feat/global-toolize). Read-only; temp repos only.

## FINDING R12-1 (HIGH): unhardened `git status` over an untrusted project runs an in-repo `.gitattributes`+`.git/config` clean filter → RCE

**One-line:** The R9/R11 hardening closes the clean-filter vector only for `git diff/show/log/blame` (via `review_git`/`--attr-source`), and the R12 drift-guard scans ONLY those four subcommands — but `git status` ALSO runs the in-repo `filter.<x>.clean` driver on a stat-dirty tracked file, and every engine `git status` over the project is BARE git, so `ai-auto gate` / `ai-auto doctor --project` on a hostile repo executes attacker code.

**Why the existing defenses miss it:**
- `hooks/git-scrub.sh:46-48` explicitly names `git status` as a "worktree-scanning git call" but only closes the **fsmonitor** exec vector (env `core.fsmonitor=''`). The **clean-filter** vector (in-repo `.gitattributes` `filter=evil` + in-repo `.git/config` `filter.evil.clean = <cmd>`) is closed ONLY at the call site by `--attr-source=<empty-tree>`, which `git status` never receives. Env scrubbing cannot reach an in-repo `.git/config` filter driver.
- The R9-DRIFT guard (`scripts/verify-machinery.sh:7364-7368`, `INVOKE` regex) matches only `(diff|show|log|blame)`. It never scans `status`, so these sites silently escaped the tree-wide rule.

**Exact repro (verified):**
```
d=$(mktemp -d); cd $d; git init -q r; cd r
git config user.email t@t; git config user.name t
printf 'hello\n' > a.txt; git add a.txt; git commit -qm init
printf 'a.txt filter=evil\n' > .gitattributes
git config filter.evil.clean 'touch /tmp/PWNED; cat'      # attacker driver, in-repo .git/config
git add .gitattributes; git commit -qm attr
sleep 1; touch a.txt                                       # content UNCHANGED, only stat-dirty (normal mid-review)
rm -f /tmp/PWNED; git status --porcelain >/dev/null 2>&1
[ -f /tmp/PWNED ] && echo RCE                              # -> RCE   (fires on --porcelain / --short / --porcelain=v2)
git --attr-source="$(git hash-object -t tree /dev/null)" status --porcelain >/dev/null 2>&1  # fix: does NOT fire
```
Live trigger: `review-gate.sh:608` runs `collect-review-context.sh` over the project during `ai-auto gate`; that script's `git status --porcelain` (top-level, line 17) fires before it has even sourced `git-harden.sh`.

**Vulnerable sites (all bare `git status` over the untrusted project, none `--attr-source`/`review_git`):**
- `scripts/collect-review-context.sh:17`  — `REPO_STATUS_BEFORE_CONTEXT=$(git status --porcelain ...)` (runs at script top during `ai-auto gate`; BEFORE git-harden.sh is sourced) — HIGH
- `scripts/collect-review-context.sh:426` — `current_status="$(git status --porcelain ...)"` (write_tree_churn_audit, in-gate) — HIGH
- `scripts/collect-review-context.sh:1319` — `git status --short` (report block, in-gate) — HIGH
- `scripts/automation-doctor.sh:498`  — `git status --short` under `ai-auto doctor --project` (runs in `git rev-parse --show-toplevel`) — MED
- `scripts/write-session-checkpoint.sh:64` — `status_output="$(git status --short)"` — MED

**Fix:**
1. Route every engine `git status` over the project through `review_git` (already single-sourced in `scripts/git-harden.sh`; its central `--attr-source=<empty-tree>` neutralizes the clean driver) — e.g. `review_git status --porcelain`. For `collect-review-context.sh:17`, move the `. git-harden.sh` source ABOVE line 17 (or compute the empty-tree OID inline and pass `git --attr-source=... status`).
2. Broaden the R9-DRIFT guard so `status` (and any other worktree-scanning subcommand) is scanned and required to carry `--attr-source=`/`review_git` — the `INVOKE` regex + rules currently whitelist only `diff|show|log|blame`, leaving `status` (a confirmed clean-filter runner) structurally invisible to the guard. Update `hooks/git-scrub.sh` comment: it claims to enumerate the worktree-scanning calls but leaves their clean-filter vector open.

## Surfaces exhaustively attacked (no other live defect found)
- **Other filter-running git subcommands over the project** (`checkout`/`restore`/`reset --hard`/`stash`/`apply`/`archive`/`checkout-index`/`cat-file --filters`): grepped all of scripts/tools/hooks/templates (excl. verify-machinery fixtures) — **zero** production invocations. `git add` appears only as suggestion *text* (automation-doctor:394/500). Setup's `git rm` is routed through `review_git` (tools/ai-auto:268), as are its de-pollution `git diff --quiet` (236/238/253). `git write-tree` operates on the index (no worktree filter).
- **git built from a variable / eval / here-doc / shell=True:** no `GIT_BIN=…; $GIT_BIN`, no `shell=True` anywhere; all python `subprocess` use list argv (knowledge-capture, ai-domain-pack, check-*.py). `tools/ai-home:39 eval "$(ai-home --cd)"` is safe — `--cd` emits `printf 'cd %q'` of a self-derived path, not attacker input.
- **Merge/push tier** (`odoo-manifest-version-merge.sh`, `safe-push.sh`): attacker %O/%A/%B content is read into quoted bash arrays and `git merge-file` (paths quoted); `version_value` feeds line content to `sed` via stdin (`printf … | sed`), NOT into the sed script — no injection. safe-push matches git's own rejection strings case-sensitively; refs are quoted.
- **Non-git RCE via attacker content** (commit msg, branch/tag, path, symlink, AGENTS.md, manifest): no `eval`/`printf %b`/`os.system`/`shell=True` reached by attacker data; `git show --format=%B` (knowledge-capture:155) is hardened and its output is handled as a python string.
- **setup data-safety (R11-1 retired-file heuristic):** `is_retired_framework_file` (tools/ai-auto:70) fires ONLY for `docs/PATCH_NOTES.md` whose first line is exactly `# AI_AUTO Patch Notes` AND worktree-clean (`review_git diff --quiet`); symlinks kept (line 232); atomic all-or-nothing `git rm`. Cannot mangle or over-remove a legit project file (a user file literally headed `# AI_AUTO Patch Notes` is the framework marker by construction).
- **Edge cases:** empty repo / detached HEAD (safe-push refuses HEAD), symlinked managed file (kept), staged-index pre-check (setup aborts). No crash/false-pass found.
