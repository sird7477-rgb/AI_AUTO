#!/usr/bin/env bash
# Build the REGENERABLE warm-base DB: the full project module set + locale baseline
# installed once into a persistent 'base' DB. Re-run anytime to rebuild from pristine
# source (drops first) — this is a cache, not hand-maintained state.
# Usage: prepare-base-db.sh <project_repo>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="$(cd "$HERE/.." && pwd)"
export ODOO_COMMUNITY="${ODOO_COMMUNITY:-$DATA/01. Odoo.19(커뮤니티)}"
export ODOO_ENTERPRISE="${ODOO_ENTERPRISE:-$DATA/02. Odoo.19(enterprise)}"
export HARNESS_DIR="$HERE"
PROJECT="${1:?usage: prepare-base-db.sh <project_repo>}"
export PROJECT_ADDONS="$PROJECT/custom-addons"
[ -d "$PROJECT_ADDONS" ] || { echo "[base] no custom-addons at $PROJECT_ADDONS" >&2; exit 2; }
LANGCODE="${ODOO_LOAD_LANGUAGE:-ko_KR}"
COMPANY_COUNTRY="${ODOO_COMPANY_COUNTRY:-base.kr}"
# Demo variant (U-A1): ODOO_WITH_DEMO=1 builds a second base named 'base_demo' that
# keeps module demo data (drops --without-demo=all) so a validate-full demo pass can
# surface T5 demo-data errors. Default 0 = the lean no-demo 'base'.
ODOO_WITH_DEMO="${ODOO_WITH_DEMO:-0}"
if [ "$ODOO_WITH_DEMO" = "1" ]; then
  BASE_DB="${ODOO_BASE_DB:-base_demo}"
  DEMO_FLAG=""
else
  BASE_DB="${ODOO_BASE_DB:-base}"
  DEMO_FLAG="--without-demo=all"
fi
cd "$HERE"   # so `docker compose -f docker-compose.validate.yml` avoids spaces in $HERE
dc() { docker compose -f docker-compose.validate.yml "$@"; }
# Per-project isolation: COMPOSE_PROJECT_NAME namespaces this project's container/network/
# volume so a DIFFERENT project never shares the postgres/base. Must precede any `dc` call.
. "$HERE/harness-slug.sh"
COMPOSE_PROJECT_NAME="$(harness_proj_slug "$PROJECT")"
export COMPOSE_PROJECT_NAME
export HARNESS_SLUG="$COMPOSE_PROJECT_NAME"
# Concurrency: rebuilding the shared base is a WRITE — block concurrent rebuilds and any
# in-flight validations (which read/clone the base) until this finishes.
. "$HERE/harness-lock.sh"
harness_lock write

MODS="$(python3 - "$PROJECT_ADDONS" <<'PY'
import ast,glob,os,sys
root=sys.argv[1]; mods=[]
for m in sorted(glob.glob(os.path.join(root,"*","__manifest__.py"))):
    name=os.path.basename(os.path.dirname(m))
    try:
        d=ast.literal_eval(open(m,encoding="utf-8").read())
        if d.get("installable",True): mods.append(name)
    except Exception: pass
print(",".join(mods))
PY
)"
[ -n "$MODS" ] || { echo "[base] no installable custom modules" >&2; exit 2; }
echo "[base] full module set: $MODS"

# Deps source of truth: install EXACTLY what odoo.sh installs. If the project has a
# root requirements.txt (U-C1), the local image installs from it (drift-checked vs
# manifests); else fall back to the manifest python deps. This is the Dockerfile
# "repoint" — the build context's .deps.txt is now requirements.txt content when present.
if [ -f "$PROJECT/requirements.txt" ]; then
  tr -d '\r' < "$PROJECT/requirements.txt" | grep -vE '^[[:space:]]*(#|$)' > "$HERE/.deps.txt" || true
  echo "[base] deps source: $PROJECT/requirements.txt (odoo.sh parity)"
  # Surface drift (do not silently swallow): the build proceeds with requirements.txt
  # as-is, but a manifest dep missing from it WILL break the odoo.sh build. The enforced
  # gate is the standalone `gen-requirements.sh --check` (rc 1); here it is advisory.
  if [ -x "$HERE/gen-requirements.sh" ] && ! "$HERE/gen-requirements.sh" --check "$PROJECT"; then
    echo "[base] WARNING requirements.txt drift detected above (advisory) — regenerate with gen-requirements.sh before pushing to odoo.sh."
  fi
else
  python3 - "$PROJECT_ADDONS" > "$HERE/.deps.txt" <<'PY'
import ast,glob,os,sys
root=sys.argv[1]; deps=set()
for m in glob.glob(os.path.join(root,"*","__manifest__.py")):
    try:
        d=ast.literal_eval(open(m,encoding="utf-8").read())
        for p in (d.get("external_dependencies",{}) or {}).get("python",[]) or []: deps.add(p)
    except Exception: pass
print("\n".join(sorted(deps)))
PY
  echo "[base] deps source: custom-addons manifests (no root requirements.txt)"
fi
echo "[base] python deps: $(paste -sd' ' "$HERE/.deps.txt" 2>/dev/null || echo none)"
dc build odoo >/dev/null
dc up -d db >/dev/null
dc exec -T db sh -c 'until pg_isready -U odoo -q; do sleep 1; done'
dc exec -T db dropdb -U odoo --if-exists "$BASE_DB" >/dev/null 2>&1 || true
echo "[base] installing full set into '$BASE_DB' (one-time, ~10min)..."
dc run --rm \
  -e VDB="$BASE_DB" -e LANGCODE="$LANGCODE" -e COMPANY_COUNTRY="$COMPANY_COUNTRY" -e MODS="$MODS" -e DEMO_FLAG="$DEMO_FLAG" \
  odoo bash -c '
set -e
OPTS="-d $VDB --addons-path=/mnt/community/addons,/mnt/enterprise,/mnt/extra-addons --db_host=db --db_user=odoo --db_password=odoo --log-level=warn"
python3 /mnt/community/odoo-bin $OPTS -i base ${LANGCODE:+--load-language=$LANGCODE} --stop-after-init
python3 /mnt/community/odoo-bin shell $OPTS --no-http < /mnt/harness/setup_company.py
python3 /mnt/community/odoo-bin $OPTS -i $MODS $DEMO_FLAG --stop-after-init
'
echo "[base] '$BASE_DB' ready. Fast validate: validate-warm.sh \"$PROJECT\" [module ...]"
