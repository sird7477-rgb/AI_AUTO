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
