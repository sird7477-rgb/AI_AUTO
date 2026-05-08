# Odoo Verify Patterns

Use these patterns when replacing the generated `scripts/verify.sh` placeholder
in an Odoo project. Pick the smallest set that proves the requested project
workflow; do not copy commands that the project cannot actually run.

## Lightweight Static Checks

Useful when Odoo runtime is not available yet:

```bash
python -m compileall custom_addons
python - <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET

for path in Path("custom_addons").rglob("*.xml"):
    ET.parse(path)
PY
```

Prefer project-local linters when already present, such as `ruff`, `pylint`, or
`pylint-odoo`. Do not add new dependencies during onboarding unless the user
explicitly requests it.

## Module Install Or Update

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
- Clean up disposable test databases only when the project defines a safe cleanup
  command.
- If runtime verification is unavailable, report the skipped reason clearly and
  keep static checks as the fallback, not as full completion evidence.
