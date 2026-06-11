#!/usr/bin/env bash
# Local Odoo serve for hands-on UI verification BEFORE pushing. Clones the warm base into
# a persistent serve DB (your custom modules already installed), updates the changed
# modules to your current code, and serves Odoo over HTTP so you can open it in a browser
# and click through the actual forms/flows. Ctrl-C to stop. The serve DB persists between
# runs (records you create stay) until you pass ODOO_SERVE_FRESH=1.
#
# Usage: serve.sh <project_repo> [module ...]     (no module -> git-diff changed modules;
#        a brand-new untracked module is not seen by git diff — pass its name explicitly)
# Env:
#   ODOO_SERVE_DB=serve          persistent DB you interact with
#   ODOO_SERVE_PORT=8069         host port -> http://localhost:<port>
#   ODOO_SERVE_SOURCE=base_demo  warm base to clone on first run (base_demo = demo data to
#                                click; set =base for an empty-but-installed instance)
#   ODOO_SERVE_FRESH=1           drop + re-clone the serve DB (discard prior interactions)
#   ODOO_SERVE_DEV=xml           odoo --dev value (xml = live-reload views without restart;
#                                =all also reloads python via auto-restart)
# Login: admin / admin
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="$(cd "$HERE/.." && pwd)"
export ODOO_COMMUNITY="${ODOO_COMMUNITY:-$DATA/01. Odoo.19(커뮤니티)}"
export ODOO_ENTERPRISE="${ODOO_ENTERPRISE:-$DATA/02. Odoo.19(enterprise)}"
export HARNESS_DIR="$HERE"
PROJECT="${1:?usage: serve.sh <project_repo> [module ...]}"; shift || true
export PROJECT_ADDONS="$PROJECT/custom-addons"
[ -d "$PROJECT_ADDONS" ] || { echo "[serve] no custom-addons at $PROJECT_ADDONS" >&2; exit 2; }
cd "$HERE"   # so `docker compose -f docker-compose.validate.yml` avoids spaces in $HERE
dc() { docker compose -f docker-compose.validate.yml "$@"; }
# Per-project isolation: same container/network/volume as this project's validation stack.
. "$HERE/harness-slug.sh"
COMPOSE_PROJECT_NAME="$(harness_proj_slug "$PROJECT")"
export COMPOSE_PROJECT_NAME

SERVE_DB="${ODOO_SERVE_DB:-serve}"
PORT="${ODOO_SERVE_PORT:-8069}"
SOURCE="${ODOO_SERVE_SOURCE:-base_demo}"
DEV="${ODOO_SERVE_DEV:-xml}"

# Changed custom modules to update into the serve DB (so the UI shows your latest code).
if [ "$#" -gt 0 ]; then
  MODCOMMA="$(echo "$*" | tr ' ' ',')"
else
  MODCOMMA="$(git -C "$PROJECT" diff --name-only HEAD 2>/dev/null \
    | sed -n 's#^custom-addons/\([^/]*\)/.*#\1#p' | sort -u | paste -sd, -)"
fi

dc build odoo >/dev/null
dc up -d db >/dev/null
dc exec -T db sh -c 'until pg_isready -U odoo -q; do sleep 1; done'

# (Re)create the serve DB from the warm base when missing or when ODOO_SERVE_FRESH=1.
exists="$(dc exec -T db psql -U odoo -lqt | cut -d'|' -f1 | tr -d ' ' | grep -qx "$SERVE_DB" && echo y || echo n)"
if [ "${ODOO_SERVE_FRESH:-0}" = "1" ] || [ "$exists" = "n" ]; then
  dc exec -T db psql -U odoo -lqt | cut -d'|' -f1 | tr -d ' ' | grep -qx "$SOURCE" \
    || { echo "[serve] source base '$SOURCE' missing — run prepare-base-db.sh${SOURCE:+ (ODOO_WITH_DEMO=1 for base_demo)} first" >&2; exit 3; }
  echo "[serve] creating serve DB '$SERVE_DB' from '$SOURCE'..."
  dc exec -T db dropdb -U odoo --force --if-exists "$SERVE_DB" >/dev/null 2>&1 || true  # --force: kick stale connections (pg16)
  dc exec -T db createdb -U odoo -T "$SOURCE" "$SERVE_DB"
fi

echo "[serve] starting Odoo — open http://localhost:${PORT}   (login: admin / admin)"
echo "[serve] updating: ${MODCOMMA:-<none>}   db=${SERVE_DB}   --dev=${DEV}   (Ctrl-C to stop)"
exec docker compose -f docker-compose.validate.yml run --rm -p "${PORT}:8069" \
  -e VDB="$SERVE_DB" -e MODS="$MODCOMMA" -e DEVOPT="$DEV" odoo bash -c '
set -e
python3 /mnt/community/odoo-bin -d "$VDB" \
  --addons-path=/mnt/community/addons,/mnt/enterprise,/mnt/extra-addons \
  --db_host=db --db_user=odoo --db_password=odoo \
  --http-interface=0.0.0.0 --http-port=8069 \
  ${MODS:+-u $MODS} --dev="$DEVOPT"
'
