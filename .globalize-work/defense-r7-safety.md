# Defense Round 7 — RED TEAM findings (HEAD 54d2b3e, feat/global-toolize)

## DEFECTS: 2 (highest HIGH)

---

## F1 — HIGH (RCE): `core.fsmonitor` code-exec bypasses the entire git-hardening

**One-line:** Every worktree-scanning trust-path git call that is NOT routed through
`review_git` (`git status`, `git diff --name-only`, `git diff --quiet`, `git diff --stat`,
`git ls-files --others`) still honors a `.git/config`-resident `core.fsmonitor`, so a
malicious project achieves RCE before any review_git call runs.

**Root cause:** The blue team's call-site analysis (collect-review-context.sh:26-27) only
verified that name-only/--stat/--quiet "do NOT exec a *diff driver*" (external-diff/textconv) —
which is TRUE and which I confirmed empirically (`git diff --stat` / `--name-only` on a binary
file with `diff.evil.command`/`.textconv` do NOT run them). But `core.fsmonitor` is a SEPARATE
code-exec vector that fires on any worktree-scanning command. review_git scrubs it
(`-c core.fsmonitor=`, git-harden.sh:17) and git-scrub.sh:11 explicitly names it as RCE, yet the
non-patch worktree calls were left as plain `git` and thus still execute it. Env scrubbing
(hooks/git-scrub.sh) cannot help: it only unsets `GIT_CONFIG_*`/`GIT_*` env injection, not a
`core.fsmonitor` living inside the repo's `.git/config` — the same reason the diff drivers needed
call-site neutralization.

**Exact repro (end-to-end, confirmed — wrote /tmp/victim/PROOF_OF_RCE):**
```
mkdir victim && cd victim && git init -q && git config user.email a@b.c && git config user.name a
echo hi > a.txt && git add a.txt && git commit -qm init && echo change >> a.txt
printf '#!/bin/sh\necho PWNED > "$PWD/PROOF_OF_RCE"\n' > .git/evil.sh && chmod +x .git/evil.sh
git config core.fsmonitor "$PWD/.git/evil.sh"
AI_AUTO_GIT_HARDEN_SH=<repo>/scripts/git-harden.sh bash <repo>/scripts/collect-review-context.sh
# -> PROOF_OF_RCE created. The very first line (module load) does it.
```

**Earliest/primary sink:** `scripts/collect-review-context.sh:17`
`REPO_STATUS_BEFORE_CONTEXT="${...-$(git status --porcelain ...)}"` — runs at module load,
unconditionally, BEFORE the gate's skip check. The gate runs this collector on every project.

**Other un-hardened sinks honoring fsmonitor (same class):**
- collect-review-context.sh: 38, 56 (`git diff --quiet`); 123, 131 (`git diff --stat`);
  370/451/641/752/854 (`git diff --name-only`); 424, 1224, 1317 (`git status`);
  507, 1331, 1401 (`git ls-files --others`).
- review-gate.sh:518 (`git diff --name-only`).
- summarize-ai-reviews.sh:835 (`git ls-files --others`), 906 (status path).
- run-ai-reviews.sh:1808-1810 (`git diff --name-only` interpolated into prompt files).
- automation-doctor.sh:498 (`git status --short`).

**Fix:** Route ALL worktree-touching calls through `review_git` (it already carries
`-c core.fsmonitor=`), or add a sibling `meta_git()` in git-harden.sh that prepends
`-c core.fsmonitor=` (plus `-c core.hooksPath=` for safety) and use it for every status/
diff-name-only/diff-quiet/diff-stat/ls-files call. Update the collect-review-context.sh:26-27
comment — the "plain git is safe" claim is correct only for diff DRIVERS, not for fsmonitor.

---

## F2 — LOW: warn-and-allow mislabels a present-but-non-executable verify-project.sh as "absent" → ungated commit

**One-line:** `hooks/pre-commit:75` gates on `[ -x ./scripts/verify-project.sh ]`; a project that
ships a verify-project.sh WITHOUT the execute bit (common via zip/Windows/`git` core.fileMode
loss) falls into the "absent" branch (lines 79-80), printing "verify-project.sh absent" and
allowing the commit UNGATED even though the project clearly intends commit-time verification.

**Repro:** In a derived project, `chmod -x scripts/verify-project.sh` then `git commit` — hook
prints "no project verification defined ... absent" and commits without running verification.

**Severity rationale:** LOW not HIGH — it is disclosed on stderr (not silent like the R6/D2 bug),
and commit-time gating is advisory. But the message is wrong ("absent" vs "present, not
executable") and a project that SHOULD be gated silently degrades to ungated.

**Fix:** Distinguish the states: if `[ -e ./scripts/verify-project.sh ] && ! [ -x ... ]`, fail
closed (or `chmod +x` / invoke via `bash ./scripts/verify-project.sh`) rather than treating
present-non-exec as absent. file:line `hooks/pre-commit:75`.

---

## Verified NOT vulnerable (residue pass)
- Patch-producing diff/show/hash-object calls: all use `review_git ... --no-ext-diff
  --no-textconv` / `--no-filters`. No 4th un-hardened external-diff/textconv/clean-filter call found.
- `git diff --stat` / `--name-only`: confirmed empirically they do NOT run textconv/external-diff
  (so the diff-DRIVER class is genuinely closed at these sites — only fsmonitor leaks, see F1).
- review-gate.sh provenance: atomic `mktemp+mv` in REVIEW_STATE_DIR (no predictable /tmp symlink sink).
- doc-budget.sh: no python/node/eval/sed -i/source on attacker content.
