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
| `prepare-base-db.sh` | build the **regenerable warm base** (full module set + baseline) |
| `validate-warm.sh` | routine fast validation: clone base, `-u` changed, drop |

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
