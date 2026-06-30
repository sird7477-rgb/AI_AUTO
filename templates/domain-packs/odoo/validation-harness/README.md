# Odoo Local Registry-Load Validation Harness

Reference harness that runs the **registry load** (and module install/update) of
changed addons on a disposable Odoo 19 DB **before push**, catching the
view-inheritance / field / registry errors that static XML parsing cannot (see
`../verify-patterns.md` "view inheritance is registry-validated, not
XML-validated"). It realizes the ST-P1-51 fail-closed `-u` gate operationally.

This is **onboarding reference tooling**, not an auto-run mainline gate. A project
copies it, points it at its parity-pinned Odoo source, and wires the pre-push gate.

## Prerequisites
- Docker + Docker Compose.
- The project's Odoo **community + enterprise source**, fetched from an odoo.sh
  build for module-set + point-release **parity** (enterprise is **mounted,
  never baked** into an image — license/leak). Store outside the repo.
- The project's `custom-addons/`.

## Setup
```bash
export ODOO_COMMUNITY=/path/to/odoo-community-source      # e.g. fetched src/odoo
export ODOO_ENTERPRISE=/path/to/odoo-enterprise-source    # e.g. fetched src/enterprise
# one-time (or to rebuild the cache): full module set + locale baseline
./prepare-base-db.sh /path/to/project_repo
# per change: fast (~tens of s) — clone base, -u changed modules, drop
./validate-warm.sh /path/to/project_repo                  # auto-detects via git diff
```
Korean projects default to `ko_KR` / `base.kr`; override with
`ODOO_LOAD_LANGUAGE` / `ODOO_COMPANY_COUNTRY`.

## Files
| File | Role |
|---|---|
| `docker-compose.validate.yml` | disposable postgres + odoo:19 (deps) with community/enterprise/custom + harness mounts |
| `Dockerfile` | odoo:19 + project python deps auto-collected to `.deps.txt` |
| `setup_company.py` | 1-lite baseline: set company fiscal country (no full chart), stateless |
| `validate-odoo.sh` | stateless full/single validation on a fresh DB |
| `prepare-base-db.sh` | build the **regenerable warm base**; `ODOO_WITH_DEMO=1` builds a `base_demo` (demo kept) for the demo pass |
| `validate-warm.sh` | routine fast validation: clone base, `-u` changed, drop |
| `validate-full.sh` | **on-demand / pre-PR** test + demo pass (scoped `--test-enable` on `base` + `-u` on `base_demo`), reverse-dep closure |
| `gen-requirements.sh` | generate / `--check` root `requirements.txt` from manifest `external_dependencies.python` (deps parity with odoo.sh) |
| `harness-slug.sh` | derive a per-project `COMPOSE_PROJECT_NAME` slug so each project gets its own container/network/**volume**/base — different projects run fully parallel |
| `harness-lock.sh` | reader/writer lock on the shared base (`validate-*` = read, `prepare-base-db` = write) so concurrent validations coexist but never clone a base mid-rebuild |
| `serve.sh` | serve Odoo locally over HTTP for hands-on UI verification before push (clone warm base → serve DB, `-u` changed modules, browse at `localhost`) |

## Local UI verification before push (`serve.sh`)
The `validate-*` gates catch registry/test errors headlessly, but do not show the rendered
UI. `serve.sh` closes that gap: it clones the warm base into a persistent `serve` DB (your
custom modules already installed), updates the changed modules to your current code, and
serves Odoo over HTTP so you can open it in a browser and click through the real forms by
hand before pushing.

```
serve.sh <project_repo> [module ...]      # then open http://localhost:8069  (admin / admin)
```
- `ODOO_SERVE_PORT` host port — **unset = auto-pick the first free port from 8069**, so
  several projects can be served at once with no manual port juggling (set it to pin a
  fixed port). `ODOO_SERVE_DB=serve` persistent (records you create stay across runs) ·
  `ODOO_SERVE_SOURCE=base_demo` clone source (demo data to click; use `base` for empty) ·
  `ODOO_SERVE_FRESH=1` drop+re-clone · `ODOO_SERVE_DEV=xml` live-reloads view XML without a
  restart. Ctrl-C to stop. Uses the per-project compose stack, so it is concurrency-safe.
- WSL2/first-load: the all-module + enterprise registry load + first `/web` asset compile
  overruns Odoo's stock 120s request watchdog and triggers a restart loop (`/web` stuck
  "loading"). serve.sh therefore disables the **time** watchdogs by default
  (`ODOO_SERVE_LIMIT_TIME_REAL=0`, `_TIME_CPU=0`) and runs cron off
  (`ODOO_SERVE_MAX_CRON_THREADS=0`); memory stays **high-but-capped**
  (`_LIMIT_MEMORY_SOFT≈6 GiB`, `_LIMIT_MEMORY_HARD≈8 GiB`), **not** unlimited — the compose
  stack sets no `mem_limit`, so `=0` would hand a runaway to the host OOM killer. Each is a
  pass-through (set a stock value, e.g. `ODOO_SERVE_LIMIT_TIME_REAL=120`, to re-enable).
- Scope boundary: local serve still does NOT reproduce prod asset bundling/minification,
  real-data volume, or prod infra (workers/cron/mail/CDN) — those remain an odoo.sh/staging
  concern. It DOES let you verify form layout and per-field interactive behavior locally.

## Concurrency (multiple sessions / multiple projects)
The harness is concurrency-safe by construction:
- **Same project, many sessions in parallel**: each validation clones the base under a
  unique name (`val_$$_$(date +%s%N)`) and takes a **shared** base lock, so they run
  together; a `prepare-base-db` rebuild takes the **exclusive** lock and waits for
  in-flight validations (and blocks other rebuilds) — no clone ever reads a half-rebuilt
  base. (`docker compose` is invoked from the harness dir so spaces in the path are safe.)
- **Different projects in parallel**: `harness-slug.sh` sets `COMPOSE_PROJECT_NAME` to a
  stable docker-safe slug of each project's path, which namespaces the container, network,
  AND the `odoo_pgdata` volume per project. Two projects therefore have **separate postgres
  servers, volumes, bases, and lock files** — zero cross-project contention or corruption.
  Adopting this on an existing single-tenant checkout means each project rebuilds its base
  once under its own volume (the base is a regenerable cache).

## On-demand test + demo tier (`validate-full.sh`)
The warm push gate catches the registry-load class; the slower test/demo classes
(post-install tests, demo data) run **on demand before push/PR**, not on every push:
```bash
# one-time: a second base WITH demo data
ODOO_WITH_DEMO=1 ./prepare-base-db.sh /path/to/project_repo
# per change (auto git-diff, or pass modules): scoped tests + demo-data load
./validate-full.sh /path/to/project_repo
```
Scope = changed modules **+ their reverse-dependents** (a dependent's test catches a
break in a module it depends on); registry coverage stays **full-set**. Sub-routing
(git-diff mode) runs the demo pass only on `demo/` changes and the test pass on
code/test/data changes — and a `demo/` change also runs the test pass to re-validate
module load (`[test=N demo=N]` banner). Because `-u` does not reload demo, a `demo/`
change fails closed unless `ODOO_DEMO_REBUILD=1` rebuilds `base_demo` to validate the
changed demo data. `MAX_FULL_SCOPE` warns on a wide reverse-dep blast radius so this
stays off the push hot path.

Measured behavior (keep these in mind — they shaped the design):
- **`-u` does not reload `demo/` data** (only data/security/views reload). The demo
  pass `-u`s the full `base_demo` to validate module load against demo-populated
  tables; to validate a **changed** `demo/` file's data, rebuild `base_demo`
  (`ODOO_WITH_DEMO=1 prepare-base-db.sh`).
- A fresh `-i $SCOPE` on an **empty** DB false-fails on partial module graphs (a field
  whose comodel lives in an unrelated/enterprise module), so the demo pass never does a
  partial install — it always runs against the full `base_demo`.
- `createdb -T` clone is ~instant (~0.8 s) and the harness already runs the pinned
  source via explicit `odoo-bin` path, so **click-odoo is not adopted** (optional only).

## Deps parity (`gen-requirements.sh`)
odoo.sh installs python deps from a **root `requirements.txt`**; a manifest
`external_dependencies.python` entry absent from it passes locally but fails the
odoo.sh build. Generate and drift-check it:
```bash
./gen-requirements.sh /path/to/project_repo            # write root requirements.txt
./gen-requirements.sh --check /path/to/project_repo    # M\R = error (breaks odoo.sh), R\M = warn (stale)
```
When a root `requirements.txt` is present, `prepare-base-db.sh` installs the harness
image from **it** (not the manifest scan) and drift-checks it, so the local image and
odoo.sh install the same set automatically. Versions are unpinned (names only) — pin in
`requirements.txt` if odoo.sh parity needs exact versions.

## Pre-push gate
Install a `pre-push` hook (project `core.hooksPath`) that **computes changed
`custom-addons` modules from the pushed ref range (pre-push stdin), or relies on
the upstream-aware default**, runs `validate-warm.sh` on them, and **blocks push
on failure**; allow `SKIP_ODOO_VALIDATE=1` for an explicit emergency override.

> Module detection: no-arg `validate-warm.sh`/`validate-odoo.sh` detect both
> uncommitted changes and committed-but-not-yet-pushed changes (`@{u}...HEAD`).
> `git diff HEAD` alone would skip the very commits being pushed (clean tree after
> commit), so a pre-push hook should pass the exact pushed range explicitly or use
> this default with a tracking upstream set.

> Asset-only no-op skip: when the changed `custom-addons` files are ALL static
> assets (`<mod>/static/**`) and/or a `__manifest__.py` **version-line** bump, the
> `-u` registry/install load cannot change, so `validate-warm.sh` skips it (`[warm]
> SKIP (no-op)`, exit 0 — installable as-is) instead of paying the full build. This
> is FAIL-SAFE: an explicit module argument, `WARM_NO_ASSET_SKIP=1`, or ANY other
> changed file (models, **`views/**`** — server views are registry-validated and are
> NOT under `static/`, data, security, i18n, a non-version manifest line, …) forces
> the full validation. `WARM_CLASSIFY_ONLY=1` prints the `skip`/`validate` decision
> and exits before touching Docker.

> Warm-PASS cache: the warm base is fixed and `-u <changed> --stop-after-init`
> installs the changed modules' **on-disk content** onto it, so the result depends
> only on `(changed module set, that content, the base identity)` — NOT on git
> history. `validate-warm.sh` records each PASS keyed by `sha256(sorted modset |
> on-disk content hash | base epoch)` (under `.warm-pass-cache.<slug>/`, a runtime
> artifact) and carries it forward on an exact re-hit, so a rebase that only reshuffles
> unrelated commits skips the multi-minute re-build. SAFE BY CONSTRUCTION: any content
> difference misses and re-validates; `prepare-base-db.sh` bumps a base epoch on every
> rebuild so a new parity pin / module set invalidates the cache; only a PASS is ever
> cached. Opt out with `WARM_NO_CACHE=1`.

> Liveness: the warm validation runs Odoo at `--log-level=warn`, so a clean
> install is quiet for ~tens of seconds to ~2 min between the `[warm] modules:`
> start line and the `[warm] PASS/FAIL` result line — this is normal, **do not
> interrupt it**; an interrupted clone DB is a throwaway and self-heals on the
> next run. If it *is* killed (e.g. a tool timeout sends SIGTERM), `validate-warm.sh`
> now traps the signal and removes its own ephemeral `…-warmrun-<pid>` odoo container
> and clone DB — the shared, by-design-persistent `db` container is left running for
> concurrent sibling validations, so no manual `docker rm` is needed. A `git fetch` issued mid-validation can show `origin` in a stale
> state; confirm the true push outcome by comparing revisions
> (`git rev-list --left-right --count @{u}...HEAD`), not by the interim fetch.

When docker / warm base / harness is unavailable the hook does **not** certify the
change: it must report that validation was **not performed** and that changed
addon view XML therefore carries **build-blocking risk** (per `../verify-patterns.md`
and ST-P1-51) — record the `odoo-view-registry: NOT validated locally` marker and
alternative evidence, and treat the staging registry load as the gate. Not running
is an unvalidated/at-risk state, never a clean pass. (The hook may avoid a hard
process block so missing tooling does not halt unrelated work, but it must surface
the risk, not imply success.)

## Boundaries
- Reliability == odoo.sh **module-set + point-release parity**; rebuild the base
  when the odoo.sh build's point release changes ("local green" without parity is
  false confidence).
- The warm base is a **regenerable cache**, not hand-maintained state.
- Registry/view/field errors are caught regardless of DB data; **data-baseline**
  dependent errors are best-effort — odoo.sh staging remains the final validator.
- Custom modules that assume the full installed set (undeclared deps) are
  validated against the **full module set**, mirroring odoo.sh.
