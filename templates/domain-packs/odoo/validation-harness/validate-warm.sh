#!/usr/bin/env bash
# Fast warm validation: clone the warm base, -u the changed modules, check, drop clone.
# Catches the registry/view/field error class in ~tens of seconds (vs full fresh install).
# Requires prepare-base-db.sh to have built the base DB first.
# Usage: validate-warm.sh <project_repo> [module ...]   (no module -> git diff)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="$(cd "$HERE/.." && pwd)"
export ODOO_COMMUNITY="${ODOO_COMMUNITY:-$DATA/01. Odoo.19(커뮤니티)}"
export ODOO_ENTERPRISE="${ODOO_ENTERPRISE:-$DATA/02. Odoo.19(enterprise)}"
export HARNESS_DIR="$HERE"
PROJECT="${1:?usage: validate-warm.sh <project_repo> [module ...]}"; shift || true
export PROJECT_ADDONS="$PROJECT/custom-addons"
BASE_DB="${ODOO_BASE_DB:-base}"
cd "$HERE"   # so `docker compose -f docker-compose.validate.yml` avoids spaces in $HERE
dc() { docker compose -f docker-compose.validate.yml "$@"; }

if [ "$#" -gt 0 ]; then
  MODCOMMA="$(echo "$*" | tr ' ' ',')"
else
  # Detect changed custom modules from BOTH uncommitted changes and committed-but-
  # not-yet-pushed changes (@{u}...HEAD). After commit the working tree is clean, so
  # `git diff HEAD` alone would skip the very commits being pushed in a pre-push hook.
  up="$(git -C "$PROJECT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  MODCOMMA="$({ git -C "$PROJECT" diff --name-only HEAD 2>/dev/null;
                [ -n "$up" ] && git -C "$PROJECT" diff --name-only "$up...HEAD" 2>/dev/null; } \
    | sed -n 's#^custom-addons/\([^/]*\)/.*#\1#p' | sort -u | paste -sd, -)"
fi
[ -n "$MODCOMMA" ] || { echo "[warm] no changed custom modules; skip"; exit 0; }
echo "[warm] modules: $MODCOMMA  (-u on a clone of '$BASE_DB')"

dc up -d db >/dev/null
dc exec -T db sh -c 'until pg_isready -U odoo -q; do sleep 1; done'
dc exec -T db psql -U odoo -lqt | cut -d'|' -f1 | tr -d ' ' | grep -qx "$BASE_DB" \
  || { echo "[warm] base DB '$BASE_DB' missing — run prepare-base-db.sh first" >&2; exit 3; }

CLONE="val_$(date +%s)"
dc exec -T db createdb -U odoo -T "$BASE_DB" "$CLONE"
LOG="$(mktemp)"
set +e
dc run --rm -e VDB="$CLONE" -e MODS="$MODCOMMA" odoo bash -c '
set -e
OPTS="-d $VDB --addons-path=/mnt/community/addons,/mnt/enterprise,/mnt/extra-addons --db_host=db --db_user=odoo --db_password=odoo --log-level=warn"
python3 /mnt/community/odoo-bin $OPTS -u $MODS --stop-after-init
' 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
dc exec -T db dropdb -U odoo --if-exists "$CLONE" >/dev/null 2>&1 || true

if [ "$rc" -ne 0 ] || grep -qiE "ParseError|cannot be located|does not exist|Invalid field|Element .* cannot|Failed to load registry|violates not-null" "$LOG"; then
  echo "[warm] FAIL (rc=$rc) — registry/view/field error above. NOT installable on odoo.sh as-is."
  rm -f "$LOG"; exit 1
fi
rm -f "$LOG"
echo "[warm] PASS — $MODCOMMA updates cleanly on warm base (parity-pinned Odoo 19)"
