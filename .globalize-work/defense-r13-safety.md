# Defense R13 — RED TEAM safety findings

HEAD 26d96db (feat/global-toolize). Read-only; temp repos only. No code/.git/config mutated.

## FINDING R13-1 (HIGH): `git worktree add` runs an in-repo `.gitattributes`+`.git/config` SMUDGE filter → RCE, and this subcommand is OUTSIDE the drift-guard's set + auto-triggered by a tmux hook

**One-line:** The R12 guard hardened the 12 clean/smudge-running subcommands
{diff,show,log,blame,status,checkout,restore,reset,stash,apply,archive,cat-file}, but
`git worktree add` — which populates a new working tree and therefore runs the in-repo
`filter.<x>.smudge` driver on every checked-out blob — is NOT in that set, IS a live
production site (`tools/ai-worktree:93,97`), is UN-hardened (no `--attr-source`, does not
source git-scrub/git-harden), and is AUTO-INVOKED when a tmux window/session opens.

**Vulnerable sites:**
- `tools/ai-worktree:93`  `git worktree add "$target" "$wt_branch"`      — no --attr-source
- `tools/ai-worktree:97`  `git worktree add -b "$wt_branch" "$target" "${BRANCH_BASE:-HEAD}"` — no --attr-source

**Auto-trigger chain (no `ai-auto gate` needed):**
- `scripts/install-global-files.sh:941-942` installs tmux hooks
  `after-new-session` / `after-new-window` → `ai-tmux-worktree create #{...} #{pane_current_path}`.
- `tools/ai-tmux-worktree:54` calls `command ai-worktree "$name"` → `git worktree add` (above).
- So merely **opening a new tmux window/pane whose cwd is inside a hostile repo** checks out
  its HEAD through the in-repo smudge filter and runs attacker code. Far lower friction than
  the R12 `ai-auto gate` path.

**Why the guard misses it:** `scripts/verify-machinery.sh:7357`
`SUBS = 'diff|show|log|blame|status|checkout|restore|reset|stash|apply|archive|cat-file'`
— `worktree` is absent, and rule-4 lists only the 8 status/checkout-class subs. `worktree add`
is therefore structurally invisible to the drift-guard; a new un-hardened site is never flagged.

**Threat model:** identical premise to the R12 finding that the round accepted — an attacker
controls the in-repo `.git/config` (a repo delivered as a full `.git` directory: tarball,
shared dir, `scp -r`, USB — NOT via `git clone`, which rewrites config). Under that model
`.git/config filter.evil.smudge=<cmd>` + tracked `.gitattributes` `path filter=evil` fires on
worktree checkout.

**Exact repro (verified, git 2.43.0):**
```
d=$(mktemp -d); cd "$d"; git init -q r; cd r
git config user.email t@t; git config user.name t
printf 'hello\n' > a.txt; git add a.txt; git commit -qm init
printf 'a.txt filter=evil\n' > .gitattributes; git add .gitattributes; git commit -qm attr
git config filter.evil.smudge 'touch /tmp/PWNED_WT; cat'   # in-repo .git/config
rm -f /tmp/PWNED_WT
git worktree add ../wt HEAD >/dev/null 2>&1                # what ai-worktree runs
[ -f /tmp/PWNED_WT ] && echo RCE                           # -> RCE
# fix proven:
rm -f /tmp/PWNED_WT
git --attr-source="$(git hash-object -t tree /dev/null)" worktree add ../wt2 HEAD >/dev/null 2>&1
[ -f /tmp/PWNED_WT ] && echo still || echo blocked         # -> blocked
```

**Fix:**
1. Harden both `tools/ai-worktree` sites: prepend the empty-tree attr-source, e.g.
   `_et="$(git hash-object -t tree /dev/null)"; git --attr-source="$_et" worktree add ...`
   (mirrors the pattern already used at `tools/ai-tmux-worktree:72` and `tools/ai-home:56`
   for `git status`). `--attr-source` fully blocks the smudge (proven above).
2. Add `worktree` to the drift-guard `SUBS` + a rule-4 clause so any `git worktree add` site
   is required to carry `--attr-source`/`review_git`. Note in that clause that `worktree add`
   is a SMUDGE (write-side checkout) runner, like checkout/restore.

## Surfaces exhaustively attacked — SOUND (no other live defect)

- **Other filter-running subcommands outside the 12-set** (`update-index --refresh`,
  `checkout-index`, `git am`, `fast-export`, `format-patch`, `bundle`, `merge-tree`,
  `range-diff`, `notes`, `replace`, `submodule`): grepped scripts/tools/hooks/templates
  (excl. verify-machinery) — **zero production invocations**. Only `worktree` has a live site.
- **`git rebase`** (`safe-push.sh:64`) runs smudge during checkout, but the smudge DRIVER
  command must live in YOUR local `.git/config` (you rebase your own work onto a remote);
  attacker controls only fetched CONTENT, not your config — not an attacker-content-only RCE.
- **Merge driver** (`odoo-manifest-version-merge.sh`, README `git config merge.*.driver`):
  user-registered in local config; attacker `.gitattributes merge=x` cannot bind without the
  local driver definition. Not attacker-reachable.
- **Write-side rule-4 subs** (checkout/restore/reset/stash/apply/archive/cat-file): NO
  production sites exist — they were pre-emptive guard additions. All real status sites
  (`collect-review-context`, `automation-doctor`, `write-session-checkpoint`,
  `ai-tmux-worktree:72`, `ai-home:56`) now carry `--attr-source`. R12-1 is closed.
- **`--attr-source` efficacy:** neutralizes clean AND smudge on the subcommands the code uses
  (status verified R12; worktree add verified above). No subcommand ignores it in git 2.43.
- **Config-only (non-attribute) exec keys on the read path:** `core.fsmonitor` pinned empty by
  the `GIT_CONFIG_*` chokepoint; `diff.external` closed at call site; `core.hooksPath`/
  `core.sshCommand`/`core.pager` do not fire on the engine's read-only diff/status/worktree-add
  path (no `git commit`/fetch/push over the untrusted repo; `--no-pager` in review_git).
- **Non-git injection sweep:** no `os.system`/`shell=True`/`os.popen`/`printf %b`; the sole
  `eval` (`ai-home:39 eval "$(ai-home --cd)"`) emits `printf 'cd %q'` of a self-derived path
  (safe, prior rounds). No `xargs` without `-0`. `for m in $(… tr ',' ' ')`
  (`validate-warm.sh:108/117`) word-splits module names used only inside quoted
  `find "$PROJECT/custom-addons/$m"` / `[ -d … ]`; a glob-char module name yields a cache
  MISS (fail-safe), not exec — LOW, not a real defect.
- **Correctness edges:** `ai-worktree` refuses removing the current/primary worktree, is
  idempotent on re-enter, and prints path only on stdout; `worktree_path_for` uses
  `printf %s` (no injection from a project directory name). No crash/false-pass found.
