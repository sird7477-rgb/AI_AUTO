# RED TEAM Round 9 — git-exec hardening audit (HEAD 1ae7dd7)

Threat model: a malicious PROJECT repo whose in-repo `.git/config` + `.gitattributes`
weaponize a git call the global engine / shipped domain-pack validators make over it.
The R7→R8 chokepoint pins ONLY `core.fsmonitor=` in the env; the `diff.external` and
`.gitattributes`-driven (`diff`/`textconv`/`filter`) exec vectors are NOT neutralizable by
an empty config override and MUST be closed at every patch/content-producing call site with
`--no-ext-diff --no-textconv` (and `--no-filters` for `--no-index`). The R8 work fixed the
engine `review_git` sites and added `--no-ext-diff` to the two python odoo validators, but
two reachable patch-producing call sites remain under-flagged.

---

## DEFECT 1 — HIGH (RCE): odoo python validators missing `--no-textconv`

`templates/domain-packs/odoo/validation-harness/check-inherited-field-overlap.py:127`
`templates/domain-packs/odoo/validation-harness/check-action-shape.py:87`

Both run a PATCH-producing diff:
```
out = run(["git", "diff", "--no-ext-diff", "-U0", base, "--", path])
```
`--no-ext-diff` blocks `diff.external` but does NOT disable a `.gitattributes` **textconv**
driver. A malicious project ships `.gitattributes` (`*.py diff=pwn`) + `.git/config`
(`[diff "pwn"] textconv = ./tc.sh`); when the validator scans any changed tracked `.py`
(`added_lines()` → the diff above), git runs `tc.sh`. The git-scrub.sh header itself states
the invariant — ".gitattributes ATTRIBUTE-driven diff/textconv/filter drivers ... stay
closed at the call site" — but then lists the odoo validators as getting only `--no-ext-diff`,
which is insufficient for textconv. Self-contradicted by its own design doc.

Repro (verified, fires through a git-scrub-sourced shell):
```
git init; printf 'x=1\n'>a.py; git add -A; git commit -m b; printf 'x=2\n'>a.py
printf '*.py diff=pwn\n' > .gitattributes
git config diff.pwn.textconv /path/tc.sh   # tc.sh: touch PWNED; cat "$1"
( . hooks/git-scrub.sh; git diff --no-ext-diff -U0 HEAD -- a.py )   # -> PWNED created
# adding --no-textconv -> blocked
```
Fix: `["git","diff","--no-ext-diff","--no-textconv","-U0",base,"--",path]` in both files.

## DEFECT 2 — HIGH (RCE): validate-warm.sh patch diff missing `--no-ext-diff --no-textconv`

`templates/domain-packs/odoo/validation-harness/validate-warm.sh:51-52`
(function `manifest_version_only_change`):
```
d="$( { git -C "$PROJECT" diff HEAD -- "$f" 2>/dev/null;
        [ -n "${up:-}" ] && git -C "$PROJECT" diff "${up}...HEAD" -- "$f" 2>/dev/null; } ...
```
A PATCH-producing diff over the attacker-controlled `$PROJECT`, with NEITHER hardening flag.
Both the `diff.external` (in-repo `.git/config`) and `.gitattributes` textconv vectors fire.
Reachable on the default auto-detect path: `asset_only_noop` → for any changed
`custom-addons/*/__manifest__.py` it calls `manifest_version_only_change "$f"` → the diff.

Repro (verified, fires through a git-scrub-sourced shell):
```
# victim with diff.external = ./pwn.sh in .git/config, changed __manifest__.py
( . hooks/git-scrub.sh; git -C victim diff HEAD -- custom-addons/mod/__manifest__.py )
# -> PWNED_EXTDIFF created; with --no-ext-diff -> blocked
```
Fix: add `--no-ext-diff --no-textconv` to BOTH diff invocations on lines 51-52.

## DEFECT 3 — MED: drift-guard fixture is incomplete (lets DEFECT 1 & 2 slip)

`scripts/verify-machinery.sh` R8-H8-1 (~7263-7271) and R8-DRIFT (~7274-7305).
- R8-DRIFT (b) parses ONLY the 4 engine scripts (collect-review-context / review-gate /
  summarize-ai-reviews / run-ai-reviews) for `review_git diff` — it never inspects the odoo
  domain-pack validators at all.
- The R8-H8-1 odoo check only does `grep -q 'no-ext-diff'` on check-inherited-field-overlap.py
  (file-wide, not line-anchored), does NOT require `--no-textconv`, and never checks
  check-action-shape.py or validate-warm.sh.
So the structural guard is satisfiable while DEFECT 1 & 2 drift. Fix: extend the drift loop
to the validator set and require `--no-textconv` on every patch-producing diff there.

---

## Re-verified CLEAN (no R8 regression / not vulnerable)

- `( . hooks/git-scrub.sh && bash scripts/verify-machinery.sh )` — suite runs (no
  diff.external='' DoS; plain `git diff` works through the sourced chokepoint).
- `core.fsmonitor=` env override alone still blocks the fsmonitor RCE.
- collect-review-context.sh:142 `git show --stat ...` and :123/:131 `git diff --stat` —
  stat-only, produce no patch; verified ext-diff/textconv do NOT fire.
- All `--name-only` / `--quiet` / `--numstat` sites (collect-review-context, review-gate:518,
  pre-commit:60, doc-budget numstat, check-manifest-files.py, validate-odoo/full.sh
  auto-detect, asset_only_noop) — no patch text, safe.
- Engine `review_git diff`/`show` sites all carry `--no-ext-diff --no-textconv`
  (+`--no-filters` on the `--no-index` content read at :1400).
