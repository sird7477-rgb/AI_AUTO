#!/usr/bin/env bash
# Dump the warm-base Odoo registry schema catalog from ir.model.fields.
# Usage: dump-schema-catalog.sh <base_db> <output_json> <module_set_sha>
set -euo pipefail
BASE_DB="${1:?usage: dump-schema-catalog.sh <base_db> <output_json> <module_set_sha>}"
OUT="${2:?usage: dump-schema-catalog.sh <base_db> <output_json> <module_set_sha>}"
MODULE_SET_SHA="${3:-}"
tmp="${OUT}.tmp"

psql_csv="$(mktemp)"
poison=""
trap 'rm -f "$psql_csv" "$tmp" "$poison"' EXIT

# LOUD, fail-closed failure path (defect: a dump failure used to just `set -e`
# out, leaving whatever catalog previously lived at $OUT (if any) untouched and
# looking fresh/valid -- check-schema-catalog.py would then silently reuse a
# STALE catalog as if it were current, and the caller's `|| echo WARNING ...`
# buries the one line that hints otherwise. Mirror the NOT-VALIDATED idiom used
# by verify-machinery.sh / hooks/pre-push: print an un-missable banner AND
# POISON $OUT (schema != 1) so check-schema-catalog.py's load_catalog() treats
# it as "catalog unavailable, NOT screened" and --strict callers (hooks/pre-
# push always passes --strict) fail closed instead of silently passing.
fail_loud() {
  local reason="$1"
  {
    echo "[schema-catalog] ============================================================"
    echo "[schema-catalog] NOT-VALIDATED (dump failed): ${reason}"
    echo "[schema-catalog] The schema/model-field reference screen did NOT run for"
    echo "[schema-catalog] base_db=${BASE_DB}. 'push validated' does NOT imply"
    echo "[schema-catalog] 'schema-catalog-checked' until this is fixed and the base"
    echo "[schema-catalog] is rebuilt."
    echo "[schema-catalog] Poisoning ${OUT} so a stale prior-success catalog is never"
    echo "[schema-catalog] silently reused as fresh -- downstream --strict checks will"
    echo "[schema-catalog] now fail closed instead of passing green."
    echo "[schema-catalog] ============================================================"
  } >&2
  poison="$(mktemp)"
  printf '{"schema": 0, "source": "odoo.ir_model_fields", "error": "dump failed: %s"}\n' \
    "$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')" > "$poison"
  mv -f "$poison" "$OUT"
  poison=""
  exit 1
}

# NOTE (fixed defect): `ir_model_fields.modules` is NOT a real column in this
# Odoo/Postgres version -- it errored with `column f.modules does not exist,
# HINT: Perhaps you meant to reference the column "f.model"`. `f.model` is
# unrelated (it's just the model name string, already selected via m.model);
# following that hint verbatim would silently produce the WRONG data, not fix
# anything. The module(s) that define a given ir.model.fields record are
# tracked the same way Odoo tracks ownership of every model record for
# uninstall/cleanup: via ir_model_data, where model='ir.model.fields' and
# res_id=<the field's id>. ir_model_data has existed since Odoo's earliest
# versions and is the correct, version-safe source for this join (unlike a
# maybe-present computed/physical column that varies across versions).
docker compose -f docker-compose.validate.yml exec -T db psql -U odoo -d "$BASE_DB" -At -F $'\t' -c "
SELECT m.model,
       f.name,
       COALESCE(f.ttype, ''),
       COALESCE(f.relation, ''),
       COALESCE(f.related, ''),
       COALESCE(string_agg(DISTINCT d.module, ','), '')
FROM ir_model_fields f
JOIN ir_model m ON m.id = f.model_id
LEFT JOIN ir_model_data d
       ON d.model = 'ir.model.fields' AND d.res_id = f.id
GROUP BY f.id, m.model, f.name, f.ttype, f.relation, f.related
ORDER BY m.model, f.name;
" > "$psql_csv" || fail_loud "psql schema dump query failed (see docker compose/psql output above)"

python3 - "$psql_csv" "$BASE_DB" "$MODULE_SET_SHA" > "$tmp" <<'PY' || fail_loud "catalog JSON post-processing failed"
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
