# Odoo Local Pre-Commit Validation Harness — Spec & Implementation Plan (2026-06-10)

Status: **draft for AI-reviewer review** (Ralph step 1). Not yet implemented.

## 1. Goal & evidence basis

Build a local validation tool that runs the Odoo registry-load (and, when
relevant, post-install test / demo install) **before push** so build errors are
caught off the developer's machine instead of on odoo.sh after a remote build +
manual log paste.

Evidence: `plans/ODOO_BUILD_ERROR_ANALYSIS_2026-06-10/` — 41 build-error
occurrences / 36 odoo.sh builds across jw_dev + hanseoindustry. A single
registry-load gate (with tests/demo switches) would catch ~35-40/41. Static XML
parse caught **0/8** of the view-inheritance (T2) class. 21/41 were recurrences,
T2 re-broke 5 consecutive builds same-day — i.e. the remote-build feedback loop is
both slow and human-in-the-loop. See `INDEX.md` / `PREVENTION.md` there.

This realizes the later-gated CI/registry-load slice of **ST-P1-51**.

## 2. Architecture — the harness

Core operation (feasibility-plan §6):

```bash
docker compose -f docker-compose.validate.yml run --rm odoo \
  odoo -d val_<ts> \
  --addons-path=/mnt/enterprise,/mnt/extra-addons \
  -u <changed+dependent modules> --stop-after-init [--test-enable --test-tags=/<mods>]
# fail on exit!=0 OR log match: ParseError | "cannot be located" |
#   "Field ... does not exist" | "Failed to load registry" | "Model ... does not exist"
```

Switches by change kind (auto-selected from the diff):
- view/model/data `*.xml`/`*.py` changed → `-u … --stop-after-init` (registry load)
- test file changed → add `--test-enable --test-tags=/<module>`
- demo file changed → install with demo (NOT `--without-demo=all`)

Scope: changed modules **+ their reverse-dependents** in the custom-addons graph
(catches cross-module collisions like T6 `jw_site_name`), never the whole set.

## 3. Local storage layout

`Z:\JSJEON\Project_JW\99. odoo\00. DATA\` (WSL `/mnt/z/.../00. DATA/`),
folder rule `NN. <name>` (fixed `NN. ` prefix, nn+1 increment):
- `01. Odoo.19(커뮤니티)` — community source/runtime, pinned to odoo.sh point release.
- `02. Odoo.19(enterprise)` — (planned) enterprise source, read-only mount only.

The compose mounts these as the odoo core + addons-path; the project's
`custom-addons` mounts as `/mnt/extra-addons`.

## 4. Enterprise & parity (critical)

- jw_dev custom modules depend on **`account_accountant`, `approvals`,
  `documents`** = Odoo Enterprise. The community `odoo:19` image lacks these, so
  `jw_account_*` cannot load locally without enterprise source mounted.
- Enterprise source: obtain via the odoo.sh subscription (copy from the odoo.sh
  checkout, or clone `github.com/odoo/enterprise@19.0`), mount **read-only**,
  add **first** on addons-path. Never bake into an image (license/leak).
- If enterprise is unavailable locally → the enterprise-dependent tail delegates
  to an **odoo.sh staging build** as validator (hybrid: community local, enterprise
  staging).
- **Parity**: reliability == odoo.sh module-set + point-release parity. Pin
  `01. Odoo.19(커뮤니티)` to the odoo.sh build's point release; without parity,
  "local green" is false confidence.

## 5. Lightweighting strategy (pre-commit bottleneck countermeasure)

> **Concern (user):** stacking this Odoo gate on top of pytest hook + review-gate
> would make the commit-time bottleneck severe. **This section is a proposal;
> implementation is gated on user consultation.** It directly extends the original
> session-efficiency finding (review churn ~98/day) — shift-left must NOT re-add
> inner-loop friction.

### 5.1 Tier the gates by frequency (the main lever)
Move heavy gates OUT of the frequent inner loop. Match cost to cadence:

| Stage | Cadence | Runs | Budget |
|---|---|---|---|
| **commit** | very frequent | fast static only: XML parse, `ruff`/py-compile, changed-file lint | seconds |
| **pre-push** | moderate | **Odoo registry-load gate on changed+dependent modules** (warm DB), scoped tests | 1-3 min |
| **PR / pre-merge** | rare | full external review-gate (AI reviewers) + full module/test suite | minutes |

Today's pain is that pytest(199) + (potentially) review-gate sit at commit. The
plan keeps **commit cheap**, puts the Odoo gate at **push** (less frequent), and
keeps **AI review-gate at PR/merge**, not every commit.

### 5.2 Conditional triggering via the existing diff-scope classifier
AI_AUTO already classifies the diff (`ST-P1-04`, `collect-review-context.sh`) and
**skips external review for docs/plans-only** changes. Plug the Odoo gate into the
same signal: run it **only when addon `*.xml`/`*.py`/data changed**, skip for
docs/plan/config-only. No new triggering machinery.

### 5.3 Warm-DB incremental update (biggest per-run saving)
Fresh DB init dominates runtime. Keep a **pre-built warm DB** (base + deps
installed once) and only `-u <changed module>` incrementally per run
(feasibility §2 Tier-3 "scoped `-u` on a warm DB for speed"). Reserve fresh
`-i` init for dependency/manifest changes. Cuts a multi-minute init to ~tens of
seconds.

### 5.4 Reuse AI_AUTO's existing review levers (no new churn)
- `REVIEW_CONTEXT_DETAIL=light` for iterative changes.
- `REVIEW_TARGETED_RECHECK=1` after a single accepted finding (the ST-P1-44
  mechanism we found unused) — avoids full multi-part re-review.
- docs/plans-only `review skipped` path already exists.

### 5.5 Scope + parallel + cache
- Validate only changed + reverse-dependent modules (not all 19).
- Docker layer cache + persistent warm-DB volume; run Odoo gate in parallel with
  static checks.
- Fail-fast on first registry error.

### 5.6 Net effect
Commit stays in seconds; the build-error gate moves to push at ~tens of seconds
(warm DB) for the common case; full AI review only at PR/merge. The ~35-40/41
catch rate is preserved while the **inner loop gets faster, not slower**, because
remote build-fail + human-log-paste cycles (and their recurrence chains) are
removed.

## 6. Mainline promotion path (Ralph goal: 정규승격 + main merge)

Separate the reusable from the local:
- **AI_AUTO mainline (committed, promoted)**: a reusable
  `docker-compose.validate.yml` template + a `scripts/`/domain-pack wrapper
  pattern + the tiered-gate guidance, landed in `templates/domain-packs/odoo/`
  (and any generic helper), promoted as a backlog ST row, verified by
  `verify.sh` + unanimous `review-gate.sh`, merged to main. Sibling of ST-P1-51.
- **Local/project instantiation (NOT committed to ai-lab)**: the actual Odoo
  source under `00. DATA/`, enterprise mount, and jw_dev's concrete compose/hook
  wiring. Runtime material, project-owned.

## 7. Implementation plan (phased micro-units, post-review)

1. **U1** — community-only harness: `docker-compose.validate.yml` + `validate-odoo.sh`
   (auto-detect changed modules, `-u --stop-after-init`, fail-match), run against a
   community-only sample module to prove the loop. Store community source in
   `00. DATA/01. Odoo.19(커뮤니티)`.
2. **U2** — enterprise mount + parity pin; validate a `jw_account_*` module end to
   end (or document the staging-fallback path if enterprise source unavailable).
3. **U3** — warm-DB incremental + changed-module scoping (lightweighting §5.3/5.5).
4. **U4** — tiered gate wiring (commit=static, push=registry-load, PR=review)
   **— pending user consultation per §5**.
5. **U5** — promote the reusable harness/guidance into the odoo domain pack +
   backlog ST row; verify + review-gate unanimity; merge to main.

## 8. Open decisions for AI reviewers / user

- **D1**: community runtime = Docker `odoo:19` image (fast) **vs** source-from-DATA
  pinned to odoo.sh point release (parity-correct, heavier). Recommend source-pin
  for parity; image for speed in early phases.
- **D2**: gate placement — pre-commit hook vs pre-push hook vs `verify.sh` step.
  Recommend **pre-push** for the registry-load gate (§5.1).
- **D3**: enterprise availability — confirm whether enterprise 19.0 source is
  obtainable locally now, or U2 uses the staging-fallback.
- **D4**: how aggressively to scope (changed-only vs +reverse-deps) — tradeoff
  between speed and cross-module collision coverage (T6).

## 9. Risks / limitations

- Not a 100% replacement: enterprise tail + point-release drift keep odoo.sh
  staging as final validator.
- Warm-DB staleness can mask migration-order issues; periodic fresh-init refresh.
- Local env maintenance (parity sync) is ongoing, non-zero cost.
