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
