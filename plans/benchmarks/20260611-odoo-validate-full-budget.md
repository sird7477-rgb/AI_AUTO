# Odoo validate-full — bottleneck / budget verification (U-A3, 2026-06-11)

Measured on the parity-pinned Odoo 19 harness (`00. DATA/harness/`, project jw_dev,
19 custom modules, docker image `odoo19-validate:local`). Wall times are single
observed runs (not hyperfine-averaged — Docker DB clone dominates and is stable);
recorded so shift-left cost stays well under one odoo.sh build round-trip.

## Tier wall-times

| Tier | Command | Wall | Cadence |
|---|---|---|---|
| base / base_demo build | `[ODOO_WITH_DEMO=1] prepare-base-db.sh` | ~8–9 min **each, one-time** (regenerable cache) | rebuild only on source/full-set or demo change |
| push (registry-load) | `validate-warm.sh` (`-u` on a `base` clone) | ~95 s | every push (fast, blocking) |
| on-demand (test+demo) | `validate-full.sh` (test `--test-enable` + demo `-u` on `base_demo`) | **175 s** (2-module scope: jw_calendar → +jw_dashboard) | pre-PR / on-demand |

One odoo.sh build round-trip it removes = minutes of build + queue + log-scrape +
fix + re-push, multiplied by recurrence (21/41 historical errors recurred). So
validate-full at ~3 min is net-positive even before counting recurrence.

## Budget decision

- commit ≤ seconds (static OCA lint, ST-P1-55) · push ≤ 1–3 min (validate-warm ~95 s)
  · validate-full = on-demand minutes, **off the push hot path**.
- Sub-routing (in `validate-full.sh`): demo pass only when a `demo/` file changed, test
  pass on code/test/data change — a `demo/` change also runs the test pass to re-validate
  module load (`[test=N demo=N]` banner). Since `-u` does not reload demo, a `demo/`
  change fails closed unless `ODOO_DEMO_REBUILD=1` rebuilds base_demo to validate the
  changed demo data. A view-only push stays at warm speed.
- Reverse-dep explosion cap: `MAX_FULL_SCOPE=12` warns when a widely-depended-on base
  module pulls a large closure, keeping validate-full on-demand (not push-wired).

## Coverage corrections found by measurement

- **U-A0**: `-u` does NOT reload `demo/` data (only data/security/views reload). So the
  demo pass runs `-u` on the full-set `base_demo` (validates module load against
  demo-populated tables); a changed `demo/` file's data is validated by rebuilding
  `base_demo` (`ODOO_WITH_DEMO=1 prepare-base-db.sh`).
- **U-A2**: a fresh `-i $SCOPE` on an empty DB FALSE-FAILS on partial module graphs
  (`AssertionError: Field project.project.jw_document_folder_id with unknown
  comodel_name 'documents.document'` — the providing enterprise module is absent in a
  partial install). Registry coverage must stay full-set; the demo pass uses the
  full `base_demo`, not a partial install.

## U-B1 — click-odoo adoption: measured and rejected

- `createdb -U odoo -T base bench_clone` (PG template copy) = **0.779 s** — effectively
  instant. `click-odoo-initdb`'s template-cache exists to make repeated test-DB spin-up
  fast; it cannot beat a sub-second PG template copy, and adopting it adds an install +
  `import odoo` dependency.
- Source parity is already guaranteed without PYTHONPATH or click-odoo: the harness runs
  the pinned source by **explicit path** (`python3 /mnt/community/odoo-bin`), not via an
  importable site-packages `odoo`. So PYTHONPATH=/mnt/community parity (DR-B1) is moot
  for the current passes.
- Decision (DR-B1): **do not adopt click-odoo**; keep `validate-warm.sh`/`validate-full.sh`
  on `createdb -T` + explicit `odoo-bin`. (click-odoo stays a documented optional layer
  in the domain pack, gated on this benchmark.)

## Honest floor (unchanged)

P1 source-revision drift + real-data/migration-result failures stay staging-only;
this brings locally-catchable build-error classes to ~90% of the observed 41.
