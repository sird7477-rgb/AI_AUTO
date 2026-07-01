# Defense R11 — HOLISTIC/INTEGRATION + SUITE-INTEGRITY (red-team, final gauntlet)

Target: feat/global-toolize HEAD 70fd6e5. Read-only audit; all probes in mktemp temp repos.

## Verdict: DEFECTS: 2 (highest HIGH)

The clean-filter RCE class that R5–R9 closed for the gate/verify/validator trust-paths was
NEVER closed for the `ai-auto setup` command's OWN worktree `git diff` calls — and the R10-hardened
drift-guard CANNOT SEE them because it skips extensionless files, so `tools/ai-auto` (the launcher)
is entirely unscanned. This is a live, reproduced RCE plus the exact guard-vacuity the round is
meant to catch.

---

## D1 (HIGH) — clean-filter RCE via `ai-auto setup` on a hostile project (tools/ai-auto:215,228)

One-line: `ai-auto setup` runs `git -C "$top" diff --quiet -- "$f"` on the TARGET project without
`--attr-source`/`review_git`, so a malicious in-repo `.gitattributes` + `filter.<x>.clean` driver
executes arbitrary code when a user adopts (sets up) that project.

file:line — `tools/ai-auto:215` and `tools/ai-auto:228` (the de-pollution loop and the
`scripts/verify.sh` special case), both:
`... && git -C "$top" diff --quiet -- "$f"` / `git -C "$top" diff --quiet -- scripts/verify.sh`.

Why it fires: these are WORKTREE diffs. git runs the in-repo `clean` filter on the worktree file to
detect a change even for `--quiet`. `hooks/git-scrub.sh` is sourced in the launcher, but it only
unsets env vars + pins `core.fsmonitor=''`; it CANNOT neutralize an IN-REPO `.gitattributes`-bound
clean filter (that is exactly why R9 added the central `--attr-source=<empty-tree>` to `review_git`).
The setup diffs bypass `review_git` and pass no `--attr-source`, so the driver runs.

Reachability: the diff is guarded by `cmp -s "$top/$f" "$pristine"` (worktree bytes must equal the
engine's pristine framework file). Trivially satisfiable — the attacker copies the engine's pristine
`AGENTS.md`/`scripts/verify.sh` into the repo, binds a clean filter to it, and `touch`es it so git
re-runs clean.

Repro (VERIFIED, temp repo):
```
cp $ENGINE/AGENTS.md AGENTS.md; git add AGENTS.md; git commit -m init
git config filter.evil.clean "touch /tmp/PWNED; cat"
printf 'AGENTS.md filter=evil\n' > .gitattributes; git add .gitattributes; git commit -m a
touch AGENTS.md
ai-auto setup           # -> /tmp/PWNED created  ***RCE FIRED DURING SETUP***
```
Control: the identical repo diffed as `git --attr-source=<empty-tree> -c diff.external= diff --quiet`
does NOT fire the payload — proving `--attr-source` is the missing fix, same as everywhere else.

Severity HIGH: arbitrary command execution on the operator's machine, same threat model and same
mechanism the game rated HIGH in R5 (local-config .gitattributes RCE) and R9. `setup` runs on a
freshly-cloned/untrusted project by definition (that is when you adopt AI_AUTO), so the project is
hostile-by-assumption.

Fix: route both diffs through `review_git` (source `scripts/git-harden.sh` in `tools/ai-auto`, which
the launcher already lists in FRAMEWORK_PATHS), or inline the central hardening:
`git -C "$top" --attr-source="$(git -C "$top" hash-object -t tree /dev/null)" -c diff.external= diff --quiet -- "$f"`.
Note line 114 (`git diff --cached --name-status`) is SAFE — `--cached` is index-vs-HEAD, no worktree
clean filter.

---

## D2 (MED) — drift-guard is vacuous on extensionless executables (masks D1)

One-line: the R9-DRIFT guard's `is_text()` accepts only `*.sh`/`*.py` and a fixed hook-name set, so
every extensionless script under `tools/` — including the launcher `tools/ai-auto` itself — is NEVER
scanned; the "50 sites, all hardened" claim silently excludes them.

file:line — `scripts/verify-machinery.sh:7333-7334`:
`def is_text(f): return f.suffix in (".sh",".py") or f.name in HOOK_NAMES`.

Evidence: the guard's own INVOKE regex MATCHES `tools/ai-auto:215/228` as un-hardened worktree diffs
(sub=diff, no review_git, no --attr-source, rule-3 conditions all true), yet the guard returns rc=0
on the real tree because `is_text(tools/ai-auto)==False` drops the file before any line is read.
`tools/` ships ~28 extensionless launchers (`ai-auto`, `ai-worktree`, `ai-domain-pack`, …); all are
outside the guard. This is the precise guard-vacuity/masking the round asked to audit: the mechanism
built to prevent un-hardened-diff drift is blind to the launcher that has the un-hardened diffs.

Severity MED: enables/hides D1 and any future un-hardened diff added to an extensionless tool.
Fix: in `is_text()`, also treat files whose first line matches `^#!.*\b(bash|sh|python)` as text
(or enumerate tools/ executables), so extensionless launchers are scanned. After the fix the guard
must FLAG the current `tools/ai-auto` until D1 is fixed (proving non-vacuity), then pass.

---

## Cleared (exhaustively exercised, NO defect)

- FULL lifecycle (derived), 7 edge cases, all correct: normal derive (setup→adoption commit→pre-commit
  shim warn+allow onboarding→post-commit gate warn→doctor 0→verify fail-closed 1→verify 0 with
  verify-project.sh); path with SPACES + UNICODE (shim installed, commit/doctor 0); EMPTY repo no
  commits (setup 0, nothing-to-remove); DETACHED HEAD (setup+commit 0); project with its OWN
  `.gitattributes`+textconv driver (setup does NOT touch project git config — the project's own
  `git diff` still uses its driver, rc=0, driver intact — `--attr-source` does NOT break legit
  workflow beyond the engine's own review context); `core.hooksPath` project (shim correctly lands in
  the configured `.githooks`, commit fires it); self-host guard REFUSES the engine.
- Engine self-host: `ai-auto gate`/`verify`/`doctor` all resolve engine correctly; verify.sh scope
  folds to `full` only on the engine toplevel, `product` on derived.
- SUITE INTEGRITY: `verify-machinery.sh` plain = 237 passed/1 skipped, VMEXIT=0, R9-DRIFT OK 50 sites;
  `( . git-scrub.sh && verify-machinery.sh )` = 237/1 (VMEXIT confirmed 0); `pytest -q` twice = 237/1
  rc 0, non-flaky, no order dependence. The `1 skipped` is the documented todo-report quarantine.
- FIXTURE POLLUTION: worktree common-config md5 = 00c0b2ab… UNCHANGED before/after ALL runs +
  lifecycle + the RCE PoC; `git config --local` carries no evil/textconv/external/fsmonitor driver;
  zero new /tmp PWNED/FIRED markers; every R5–R10 fixture stays inside its `mktemp -d` + `trap rm -rf`
  sandbox. My OWN probes (lifecycle + PoC) also left nothing behind (mktemp + cleanup).
- Drift-guard positive controls b1–b7 all genuinely fire (verified by extracting the guard and
  re-running); the `--attr-source` mechanism empirically neutralizes the clean-filter payload.
