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
#   ODOO_SERVE_PORT              host port -> http://localhost:<port>; unset = auto-pick the
#                                first free port from 8069 (serve several projects at once)
#   ODOO_SERVE_SOURCE=base_demo  warm base to clone on first run (base_demo = demo data to
#                                click; set =base for an empty-but-installed instance)
#   ODOO_SERVE_FRESH=1           drop + re-clone the serve DB (discard prior interactions)
#   ODOO_SERVE_DEV=xml           odoo --dev value (xml = live-reload views without restart;
#                                =all also reloads python via auto-restart)
#   Resource watchdogs (serve is manual UI verification, not a perf/resource test, so the
#   container odoo.conf stock limits — 120s time, ~2.5GB hard mem — only cause a restart loop
#   here: the first all-module + enterprise registry load + /web asset compile overruns 120s
#   on WSL2 and Odoo force-restarts every ~2-3min, leaving /web stuck "loading"). Each knob is
#   a pass-through; set a stock value to re-enable a limit:
#   ODOO_SERVE_LIMIT_TIME_REAL   request wall-clock watchdog seconds  (default 0 = off; e.g. 120 restores stock)
#   ODOO_SERVE_LIMIT_TIME_CPU    request CPU-time watchdog seconds    (default 0 = off)
#   ODOO_SERVE_LIMIT_MEMORY_SOFT graceful worker-recycle bytes        (default 6 GiB)
#   ODOO_SERVE_LIMIT_MEMORY_HARD hard restart bytes                   (default 8 GiB, kept < the
#                                WSL VM ceiling — the compose stack sets no mem_limit, so 0/
#                                unlimited would hand a runaway straight to the host OOM killer;
#                                0 = unlimited only on a box that can afford it. NB serve runs
#                                threaded (workers=0): Odoo's memory cap triggers a reload via
#                                its watchdog, and the .wslconfig VM ceiling is the ultimate
#                                backstop — so keep this bounded rather than relying on either)
#   ODOO_SERVE_MAX_CRON_THREADS  background cron threads              (default 0 = off during
#                                verify; set 1+ to verify a cron-driven flow)
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
SOURCE="${ODOO_SERVE_SOURCE:-base_demo}"
DEV="${ODOO_SERVE_DEV:-xml}"

# Host port: an explicit ODOO_SERVE_PORT wins; otherwise auto-pick the first FREE port
# from 8069 so several projects can be served at once without manual port juggling.
serve_port_in_use() {  # 0/true = something is already listening on port $1
  if command -v ss >/dev/null 2>&1; then
    [ -n "$(ss -ltnH "sport = :$1" 2>/dev/null)" ]
  elif command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$1" >/dev/null 2>&1
  else
    (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1 && { exec 3>&- 2>/dev/null; return 0; }
    return 1
  fi
}
if [ -n "${ODOO_SERVE_PORT:-}" ]; then
  PORT="$ODOO_SERVE_PORT"
else
  PORT=8069
  while serve_port_in_use "$PORT" && [ "$PORT" -lt 8119 ]; do PORT=$((PORT + 1)); done
  echo "[serve] auto-selected free port $PORT (set ODOO_SERVE_PORT to pin it)"
fi

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
echo "[serve] first load of all modules + enterprise can take several minutes on WSL2 (drvfs);"
echo "[serve]   /web may 503 until Odoo logs 'HTTP service (werkzeug) running' — don't interrupt."
# Resource watchdogs threaded host-side into the container via -e (the odoo-bin call below is
# in a single-quoted block, so ${ODOO_SERVE_*} must be expanded HERE, not inside the quotes —
# inside, those vars are unset in the container and the override would silently die). Time
# watchdogs default OFF (the slow first load is legit); memory stays high-but-CAPPED, never 0
# by default, because the compose stack has no mem_limit so unlimited would reach the WSL OOM.
exec docker compose -f docker-compose.validate.yml run --rm -p "${PORT}:8069" \
  -e VDB="$SERVE_DB" -e MODS="$MODCOMMA" -e DEVOPT="$DEV" \
  -e LTR="${ODOO_SERVE_LIMIT_TIME_REAL:-0}" \
  -e LTC="${ODOO_SERVE_LIMIT_TIME_CPU:-0}" \
  -e LMS="${ODOO_SERVE_LIMIT_MEMORY_SOFT:-6442450944}" \
  -e LMH="${ODOO_SERVE_LIMIT_MEMORY_HARD:-8589934592}" \
  -e CRON="${ODOO_SERVE_MAX_CRON_THREADS:-0}" \
  odoo bash -c '
set -e
python3 /mnt/community/odoo-bin -d "$VDB" \
  --addons-path=/mnt/community/addons,/mnt/enterprise,/mnt/extra-addons \
  --db_host=db --db_user=odoo --db_password=odoo \
  --http-interface=0.0.0.0 --http-port=8069 \
  --limit-time-real="$LTR" --limit-time-cpu="$LTC" \
  --limit-memory-soft="$LMS" --limit-memory-hard="$LMH" \
  --max-cron-threads="$CRON" \
  ${MODS:+-u $MODS} --dev="$DEVOPT"
'
