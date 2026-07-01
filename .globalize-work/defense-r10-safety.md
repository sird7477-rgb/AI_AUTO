# RED TEAM Round 10 — safety findings (feat/global-toolize @ 5494d4c)

Scope: git-exec RCE bypass of `--attr-source=<empty-tree>`; drift-guard soundness;
new non-git classes. Read-only; all repros run in TEMP repos (this worktree's
`.git/config` was NOT mutated).

## DEFECTS: 1 (highest MED)

---

### D1 (MED) — R9-DRIFT drift-guard is EVADABLE: idiomatic worktree-diff forms scan to ZERO sites and pass clean

`scripts/verify-machinery.sh:7343-7344` (the `INVOKE` regex inside the temp
`git-harden-drift.py`).

The guard is the tree-wide safety net that is supposed to FAIL on any newly
introduced un-hardened worktree `git diff` (clean-filter RCE vector). Its bash
matcher requires `git`/`review_git` in *command position* — immediately preceded by
`^` or one of `[;&|(){` `` ` ``]` (line 7344). Its python matcher only recognizes a
**single contiguous list literal** `"git", ... "diff"` (line 7345). Several
extremely common, syntactically valid worktree-diff forms match NEITHER branch, so
the scanner counts them as 0 sites and reports `R9-DRIFT OK`.

EXACT REPRO (each planted as the only `git diff` in a temp `fake/` tree; guard
returns rc=0 / "0 site(s) scanned"):

Shell (command preceded by a keyword, not punctuation → command-position anchor misses):
- `if true; then git diff --name-only HEAD; fi`      → EVADES (`then` before git)
- `for x in a; do git diff --name-only HEAD; done`    → EVADES (`do` before git)
- `while read l; do git diff --name-only HEAD; done`  → EVADES (`do` before git)
- `eval "git diff --name-only HEAD"`                  → EVADES (`"` before git)
- `xargs -I{} git diff --name-only {}`                → EVADES (`xargs ` before git)

Python (argv built by list concatenation instead of one literal):
- `subprocess.run(GIT + ["diff", "--name-only", base])`   → EVADES (`"git"` followed by `]`, not `,`)
- `subprocess.run(["git"] + flags + ["diff", base])`      → EVADES

Control (proves the guard is otherwise live): `cmd && git diff --name-only HEAD`
IS caught (`&` is in the anchor class), and `["git", "-C", root, "diff", ...]`
IS caught. So the gap is specifically keyword-prefixed / quoted / xargs'd shell
invocations and concat-built python argv.

Verified with the guard extracted verbatim from verify-machinery.sh:
```
$ python3 guard.py fake   # fake/ contains only the evading forms
R9-DRIFT OK: 0 git diff/show/log/blame site(s) scanned, all hardened   (rc=0)
```

Impact: latent regression risk (MED, not active). The CURRENT shipped tree uses
none of these forms (grep over scripts/ hooks/ tools/ templates/domain-packs/ for
`then|do` + git-diff and for python concat is clean), so there is no live RCE today.
But the guard's entire purpose is to *prevent* a future un-hardened worktree diff —
a clean-filter RCE — from being added. A blue-team author who later writes a
validator loop as `for f in $files; do git diff --name-only "$base" -- "$f"; done`,
or a python validator that builds `GIT_BASE + ["diff", ...]`, introduces an
un-hardened worktree clean-filter-RCE site and the guard stays GREEN. The guard
gives false assurance for the most idiomatic shell/python forms.

Fix: broaden the matcher.
1. Shell: allow command-position after shell keywords, not just punctuation —
   add `then|do|else|elif|;;|&&|\|\|` and a leading-whitespace-after-keyword case
   to the prefix alternation (or, simpler/robuster: drop the command-position
   anchor and instead positively exclude the known false-positive prose by
   requiring the `diff|show|log|blame` token, then post-filter comment/prose lines —
   the line-is-comment skip already exists).
2. Add `eval`/quoted detection: also match `(?:review_)?git` when preceded by a
   quote or by `eval `.
3. Python: match `"diff"` (etc.) as a standalone argv string token within any
   `subprocess`/`check_output`/`run`/`Popen` call that also contains `"git"` on the
   same logical line, regardless of `+`-concatenation — i.e. don't require the
   single-literal `"git", ... "diff"` adjacency. Add positive controls b6
   (`do git diff`), b7 (`GIT + ["diff"]`) to the fixture so the gap can't reopen.

---

## Probes that came back CLEAN (exhaustive effort, documented)

- **`--attr-source` bypass via non-diff subcommand `git status`**: TESTED in a temp
  poison repo (`.gitattributes a.txt filter=evil` + `.git/config filter.evil.clean`).
  `git status` / `git status --porcelain` did NOT execute the clean filter (git
  2.43 uses stat-based change detection); ONLY a worktree `git diff` ran it. Since
  collect-review-context.sh's early `git status` does not trip the filter, it needs
  no review_git wrapping. The diff-routing chokepoint is the correct and sufficient
  cut point. CLEAN.

- **fsmonitor / config-driven exec keys on the gate/verify/hook command set**:
  the gate path is read-only-ish (status/diff/show/hash-object/rev-parse/ls-files/
  rev-list) — no commit/fetch/push/clone/checkout/add/stash. `core.fsmonitor` is
  pinned empty via env GIT_CONFIG_* (hooks/git-scrub.sh). `sequence.editor`,
  `core.editor`, `gpg.program`/`commit.gpgsign`, `credential.helper`,
  `core.sshCommand`, `uploadpack.packObjectsHook`, `protocol.*`/`url.*.insteadOf`,
  `core.hooksPath` all require a subcommand absent from the gate set
  (commit/merge/rebase/fetch/push/clone/checkout) — none reachable. CLEAN.

- **`.git/info/attributes`**: local-only, not clone-delivered (out of the malicious-
  clone threat model, as the prompt notes); `--attr-source` does not cover it, but it
  is not attacker-reachable through a delivered repo. Noted, not a finding.

- **Python concat false-NEGATIVE is the only argv gap**: single-literal
  `["git", ..., "diff", ...]` IS caught (verified).

- **New non-git classes**: no attacker-controlled content (commit msg / branch /
  path / AGENTS.md / manifest / .omx) observed reaching eval / printf %b / unquoted
  expansion / sed / python in the gate/hook/setup/validator scripts within this
  pass; no predictable-tmp/symlink race found (all fixtures use `mktemp -d`). CLEAN
  for this round's effort.
