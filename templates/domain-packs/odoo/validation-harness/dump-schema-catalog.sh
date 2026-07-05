#!/usr/bin/env bash
# Dump the warm-base Odoo registry schema catalog from ir.model.fields.
# Usage: dump-schema-catalog.sh <base_db> <output_json> <module_set_sha>
set -euo pipefail
BASE_DB="${1:?usage: dump-schema-catalog.sh <base_db> <output_json> <module_set_sha>}"
OUT="${2:?usage: dump-schema-catalog.sh <base_db> <output_json> <module_set_sha>}"
MODULE_SET_SHA="${3:-}"
tmp="${OUT}.tmp"

psql_csv="$(mktemp)"
trap 'rm -f "$psql_csv" "$tmp"' EXIT

docker compose -f docker-compose.validate.yml exec -T db psql -U odoo -d "$BASE_DB" -At -F $'\t' -c "
SELECT m.model,
       f.name,
       COALESCE(f.ttype, ''),
       COALESCE(f.relation, ''),
       COALESCE(f.related, ''),
       COALESCE(f.modules, '')
FROM ir_model_fields f
JOIN ir_model m ON m.id = f.model_id
ORDER BY m.model, f.name;
" > "$psql_csv"

python3 - "$psql_csv" "$BASE_DB" "$MODULE_SET_SHA" > "$tmp" <<'PY'
import datetime as dt
import json
import sys
from pathlib import Path

rows = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
base_db = sys.argv[2]
module_set_sha = sys.argv[3]
models = {}
for row in rows:
    model, name, ttype, relation, related, modules = (row.split("\t") + [""] * 6)[:6]
    fields = models.setdefault(model, {"fields": {}})["fields"]
    fields[name] = {
        "ttype": ttype,
        "relation": relation,
        "related": related,
        "modules": [m for m in modules.split(",") if m],
    }

json.dump(
    {
        "schema": 1,
        "source": "odoo.ir_model_fields",
        "base_db": base_db,
        "module_set_sha": module_set_sha,
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "models": models,
    },
    sys.stdout,
    sort_keys=True,
    indent=2,
)
print()
PY

mv "$tmp" "$OUT"
echo "[schema-catalog] wrote $OUT"
