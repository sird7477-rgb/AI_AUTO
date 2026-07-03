# Odoo Verify Patterns

Use these patterns when replacing the generated `scripts/verify.sh` placeholder
in an Odoo project. Pick the smallest set that proves the requested project
workflow; do not copy commands that the project cannot actually run.

## Lightweight Static Checks

Useful when Odoo runtime is not available yet:

```bash
python - <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET

for path in Path("custom_addons").rglob("*.py"):
    compile(path.read_text(encoding="utf-8"), str(path), "exec")

for path in Path("custom_addons").rglob("*.xml"):
    ET.parse(path)
PY
```

Compile Python source in memory instead of using `compileall` or `py_compile`
when `__pycache__` churn would dirty the working tree.

Prefer project-local linters when already present, such as `ruff`, `pylint`, or
`pylint-odoo`. Do not add new dependencies during onboarding unless the user
explicitly requests it.

**Static XML parsing is syntax-only, not a validity check.** `ET.parse` confirms
well-formed XML; it cannot confirm that a view inheritance anchor (xpath/`field`
selector) resolves against the model's fields or the combined parent arch. View
inheritance is **registry-validated, not XML-validated**: Odoo resolves selectors
at registry load against base view + every inheriting module's contribution, so a
clean static parse does **not** mean the change is installable. Cross-module and
enterprise-view anchors are the common gap. Treat static checks as a fast
pre-filter and a fallback only — never as installable-evidence.

### Client Action-Shape Screen

`validation-harness/check-action-shape.py` flags CHANGED `ir.actions.act_window`
dicts that are `target: 'new'` (popup) with no `views` key — the Odoo 19 crash
class where the web client's `_preprocessAction` runs `undefined.map` because a
raw `doAction(dict)` (e.g. a JS field widget dispatching an RPC result) was never
normalized. `view_mode` alone does not cover this raw-dispatch path.

This is a SCREEN, not a judge: the same shape is safe when dispatched via a
button/server round-trip, so it is diff-scoped (only new/edited actions) and
advisory (the pre-push hook runs it without blocking). It over-approximates by
design — **confirm each flagged popup at runtime, never on inspection alone**:

```bash
# serve the changed module locally (background), then open the flagged popup and
# assert zero client errors:
ODOO_BASE_URL=http://localhost:<port> \
  node validation-harness/popup-smoke.mjs --recipe ./recipes/<popup>.mjs
```

`popup-smoke.mjs` is the runtime oracle: it logs in to the local serve build,
runs a small per-popup recipe (`export async function run(page)` that opens the
popup), and FAILS on any console error / uncaught promise (`exit 1`). PASS = the
popup dispatched with no client crash. Fix a real failure by adding
`'views': [(False, 'form')]` to the action dict. This is the cheap escaped-defect
loop: the screen narrows, the local popup run decides.

> WSL2 note: the local serve build's first all-module + enterprise load overruns
> Odoo's stock 120s request watchdog and restart-loops (`/web` stuck "loading"),
> which would make this oracle hang/flake. `serve.sh` disables the time watchdogs
> by default (`ODOO_SERVE_LIMIT_TIME_REAL=0`/`_TIME_CPU=0`, cron off) and keeps
> memory high-but-capped (`≈6/8 GiB`, never `0` — no compose `mem_limit`). Wait for
> Odoo's `HTTP service (werkzeug) running` line before running the oracle.

### Inherited-Field Overlap Screen

`validation-harness/check-inherited-field-overlap.py` flags a
`(inherited model, field name)` pair written by **two or more CHANGED addons**
(e.g. `account.move.jw_billing_type_code` defined by both a sale and a purchase
addon) — the cross-addon BEHAVIORAL collision class (queue
`odoo:post-install-gap-field-semantic-collision`). Warm registry-load stays
GREEN because both modules install; only the post-install tests see which
addon's `compute`/`related`/`store`/override order wins.

This is NOT a duplicate-field lint (forbidden by `commit-tier/README.md`
Article 1.1) and it NEVER flags the legal single-addon override: the signature
is the rare, high-precision case of the SAME field name on the SAME inherited
model from **≥2 distinct changed addons**. It is diff-scoped and advisory (the
pre-push hook runs it without blocking). Confirm each flagged pair with
`validate-full.sh` (the post-install test tier) before push/PR — that is the
oracle; the screen only nominates. Prefer module-prefixed field names
(`jw_sale_billing_type_code` vs `jw_purchase_billing_type_code`) to avoid the
collision at the source.

### Manifest File-Reference Screen

`validation-harness/check-manifest-files.py` checks every changed module's
`__manifest__.py` and FAILS (`exit 1`) when a `data` / `demo` entry points to a
file that does not exist in the module. That is a deterministic post-push build
failure — `odoo -u <module>` and odoo.sh raise `FileNotFoundError` loading the data
file — so unlike the action-shape screen this is a **fail-closed gate, not
advisory**: the pre-push hook blocks the push. It needs no docker and is co-installed
next to the pre-push hook (`.githooks/`, wired by the pack's validation-harness
setup), so -- unlike the docker
warm-base validation -- it runs even when `ODOO_HARNESS_DIR` is unset, before the
harness/docker skips. That closes the gap where a stale-path or never-committed data
file reached odoo.sh because the warm-base validation was skipped.
Only `data`/`demo` (exact module-relative paths) are checked; `assets` entries are
addons-root-relative and may be globs, so the warm-base/web build stays their
oracle. Run standalone with `python3 validation-harness/check-manifest-files.py
--all` (or `--modules <mod> ...`).

## Module Install Or Update

This is the **only complete detection** for view-inheritance/registry errors and
is therefore a **fail-closed gate whenever an addon view `*.xml` changed**: run
`-u <changed module> --stop-after-init` on a disposable test DB and fail on any
`ParseError`, `Element ... cannot be located`, or `Field ... does not exist`.

When no Odoo runtime is available, do **not** record this as "skipped/Not-tested":
mark it **build-blocking risk** and require alternative evidence before merge
(strongest first): a lightweight Docker `-u` of the standard module that defines
the view; an odoo.sh staging build as the pre-merge validator; or a non-runtime
parent-arch source check across the installed inheriting modules. Commit such a
change with an explicit marker, e.g.
`odoo-view-registry: NOT validated locally; evidence=<...>; risk=build-blocking
until staging registry load passes`. Gate reliability requires **module-set +
point-release parity** with the odoo.sh build; without parity, "local green" is
false confidence.

Example shape:

```bash
odoo-bin \
  -c ./odoo.conf \
  -d "${ODOO_TEST_DB}" \
  -i "${ODOO_MODULE}" \
  --stop-after-init
```

For an existing test database:

```bash
odoo-bin \
  -c ./odoo.conf \
  -d "${ODOO_TEST_DB}" \
  -u "${ODOO_MODULE}" \
  --stop-after-init
```

For localized projects, set up the test database/company with the confirmed
country, language, currency, and tax baseline before treating business-flow
verification as complete. For Korean projects this usually means `ko_KR`, KRW,
and 10% VAT.

## Odoo Tests

Example shape:

```bash
odoo-bin \
  -c ./odoo.conf \
  -d "${ODOO_TEST_DB}" \
  -u "${ODOO_MODULE}" \
  --test-enable \
  --test-tags "${ODOO_TEST_TAGS}" \
  --stop-after-init
```

## Docker Compose Runtime

When the project already uses Docker Compose, prefer the project's compose file
and service names:

```bash
docker compose up -d db
docker compose run --rm odoo odoo-bin -d "${ODOO_TEST_DB}" -i "${ODOO_MODULE}" --stop-after-init
```

## Verification Script Guardrails

- Fail fast on missing required environment variables.
- Never target a production database.
- Print the Odoo version, module name, and database name before running tests.
- Print the localization baseline when business data, taxes, currency, or demo
  data are part of the verification.
- Clean up disposable test databases only when the project defines a safe cleanup
  command.
- If runtime verification is unavailable, report the skipped reason clearly and
  keep static checks as the fallback, not as full completion evidence. For
  changed addon view XML this fallback is **build-blocking risk**, not a clean
  skip: record the marker and alternative evidence from Module Install Or Update.

## Local Registry-Load Validation Harness

`validation-harness/` is a reference harness that runs the registry-load gate
locally before push: a disposable Odoo 19 DB (parity-pinned community+enterprise
source from an odoo.sh build) installs/updates the changed addons and fails on
`ParseError` / `cannot be located` / `Field ... does not exist` /
`Failed to load registry`. A one-time **regenerable warm base** (full module set
+ locale baseline) makes per-change validation ~tens of seconds via clone + `-u`.
See `validation-harness/README.md`. Wire it as a `pre-push` gate. Enterprise
source is mounted, never baked; reliability requires odoo.sh module-set +
point-release parity.

The warm base must carry a parity stamp. Build or rebuild it with
`ODOO_SH_POINT_RELEASE=<odoo.sh-build-point-release> prepare-base-db.sh ...`;
`check-parity.sh` blocks when the stamp is missing, the point release is
unconfirmed, or the current full custom module set differs from the base stamp.
For CI, run `check-parity.sh "$PROJECT_DIR"` before any cached warm validation.
When `changed-module-scope.py --reverse-deps` is available, expand changed
modules before `validate-warm.sh` so dependents' inherited views are updated too.

## Validation Tiers (commit → push → merge)

Match cost to cadence; do not stack everything on one stage:

- **commit (fast, static):** adopt the off-the-shelf OCA tools in `commit-tier/`
  (`pylint-odoo` + `odoo-pre-commit-hooks`) — manifest/XML/CSV/PO hygiene, duplicate
  id/field, deprecated nodes, `odoolint`. Do **not** build a custom static lint.
  Catches a pre-filter subset; **misses view-inheritance (T2) and renamed/removed
  schema (the bulk of T1)** — a clean static pass is never proof of installability.
- **push (definitive):** `validation-harness/validate-warm.sh` registry load on
  parity-pinned Odoo 19 — the only tier that catches T2 and field/model/registry/NOT-NULL
  errors. Wire it as the `pre-push` gate.
- **pre-PR (test + demo, on demand):** `validation-harness/validate-full.sh` — scoped
  post-install tests (`--test-enable --test-tags`) on the warm base plus a demo-data `-u`
  pass on `base_demo`; catches the post-install test (T4) and demo-data (T5) classes the
  warm push gate does **not**. Slow (minutes), so run before a push/PR, not on every push.
  Scope = changed modules + reverse-dependents. See `validation-harness/README.md`. This
  tier ships in the harness; surface it in the project runbook rather than leaving it
  undocumented.
- **merge (final):** odoo.sh staging + AI review-gate for data-baseline-dependent
  cases the warm base only best-effort covers.
