# Odoo git-tier: shared-branch push helpers

Reference tooling for the shared-branch concurrency friction observed when several AI
sessions push the same Odoo project branch at once (ST-P1-73(B) + ST-P1-74). Opt-in,
per-clone — nothing here changes history or skips validation.

## 1. `odoo-manifest-version-merge.sh` — version-line merge driver (ST-P1-74)

A pre-commit hook that bumps `__manifest__.py` `version` on every commit makes each rebase
onto origin conflict on that one line (`.207` vs `.206`). The answer is always "take the
higher version", so this merge driver does exactly that — and **nothing else**.

**Safe by construction:** a hunk is auto-resolved ONLY when both sides are exactly one line
AND that line is the `version` key and **nothing else** (key + quoted value + optional comma
+ end-of-line). A multi-line hunk, a non-version line, a version line that ALSO carries
another key (`'version': '..', 'auto_install': False,`), or an unparseable version is left
as a normal conflict (driver exits non-zero) for manual resolution — it can never silently
drop a code change. It also merges on a **copy** of the file, so a `git merge-file` error
never truncates or corrupts the manifest.

Install (per clone):

```sh
H="/abs/path/to/git-tier"   # wherever this domain-pack dir lives locally
git config merge.odoo-manifest-version.name   "Odoo __manifest__.py version max-merge"
git config merge.odoo-manifest-version.driver "$H/odoo-manifest-version-merge.sh %O %A %B"
# attribute (commit it, or use .git/info/attributes for a local-only mapping):
echo '**/__manifest__.py merge=odoo-manifest-version' >> .gitattributes
```

A merge driver is configured per-clone (git never reads a driver command from a tracked
file, for safety), so each environment runs the `git config` once; the `.gitattributes`
mapping can be committed and shared.

## 2. `safe-push.sh` — bounded fetch+rebase retry on a lost race (ST-P1-73(B))

```sh
safe-push.sh [remote] [branch]      # defaults: origin, current branch
```

On a busy shared branch a push is often rejected non-fast-forward because a sibling pushed
first. This wraps the manual `fetch -> rebase -> push` loop with a bounded retry
(`SAFE_PUSH_MAX_TRIES`, default 5; `SAFE_PUSH_BACKOFF` seconds, default 2). It composes
with the rest of the stack:

- the **pre-push hook still runs on every attempt** — validation is never bypassed — and is
  made cheap on a pure rebase by the validate-warm **warm-PASS cache** (ST-P1-73(A));
- the **version merge driver** above auto-resolves the per-commit version conflict that
  would otherwise stall every rebase.

It **never force-pushes** and **never skips validation**. It retries ONLY a genuine
non-fast-forward rejection; a rebase conflict the driver cannot resolve, or a push failure
that is not a race (a validation block, an auth error), stops the loop immediately and hands
back to you.

## 3. Companion guidance: skip the version bump during a rebase

If the project's pre-commit hook bumps `version`, also have it **no-op while a rebase is in
progress**, so replaying commits neither re-bumps nor slows the rebase:

```sh
# near the top of the version-bump pre-commit hook
if [ -d "$(git rev-parse --git-path rebase-merge 2>/dev/null)" ] \
   || [ -d "$(git rev-parse --git-path rebase-apply 2>/dev/null)" ]; then
  exit 0
fi
```

The merge driver resolves the *existing* conflict; this skip stops new bumps from piling on
during the replay. Both together make `safe-push.sh`'s auto-rebase clean.
