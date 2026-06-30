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
# Per-project isolation: COMPOSE_PROJECT_NAME namespaces this project's container/network/
# volume so a DIFFERENT project never shares the postgres/base. Must precede any `dc` call.
. "$HERE/harness-slug.sh"
COMPOSE_PROJECT_NAME="$(harness_proj_slug "$PROJECT")"
export COMPOSE_PROJECT_NAME
export HARNESS_SLUG="$COMPOSE_PROJECT_NAME"
# Concurrency: cloning the shared base is a READ — coexist with other validations, wait
# only while prepare-base-db.sh rebuilds the base.
. "$HERE/harness-lock.sh"
harness_lock read

if [ "$#" -gt 0 ]; then
  EXPLICIT_MODS=1
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

# (F) Asset-only no-op skip: a diff touching ONLY static assets (custom-addons/<mod>/
# static/**) and/or a __manifest__.py version-line bump cannot change registry/install
# state, so the `-u` warm load is pure cost — skip it (the change is installable as-is).
# FAIL-SAFE by construction: an explicit module request, WARM_NO_ASSET_SKIP=1, or ANY
# changed custom-addons file not positively classified as install-irrelevant forces the
# full validation. (Server views live in <mod>/views/**, NOT static/**, so they are never
# treated as assets.) WARM_CLASSIFY_ONLY=1 prints the decision and exits before docker.
manifest_version_only_change() {  # $1=path ; 0 iff the only changed content lines are the version line
  local f="$1" d
  d="$( { git -C "$PROJECT" diff HEAD -- "$f" 2>/dev/null;
          [ -n "${up:-}" ] && git -C "$PROJECT" diff "${up}...HEAD" -- "$f" 2>/dev/null; } \
        | grep -E '^[+-]' | grep -Ev '^(\+\+\+|---)' || true )"
  [ -n "$d" ] || return 1   # no detectable content change -> be safe, validate
  printf '%s\n' "$d" | grep -vqE "^[+-][[:space:]]*[\"']version[\"'][[:space:]]*:" && return 1
  return 0
}
asset_only_noop() {
  [ "${WARM_NO_ASSET_SKIP:-0}" = "1" ] && return 1
  [ "${EXPLICIT_MODS:-0}" = "1" ] && return 1
  local ca f
  ca="$({ git -C "$PROJECT" diff --name-only HEAD 2>/dev/null;
          [ -n "${up:-}" ] && git -C "$PROJECT" diff --name-only "${up}...HEAD" 2>/dev/null; } \
        | sort -u | sed -n 's#^custom-addons/.*#&#p' || true)"
  [ -n "$ca" ] || return 1   # nothing under custom-addons -> let the normal flow run
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      custom-addons/*/static/*) : ;;                                        # asset -> irrelevant
      custom-addons/*/__manifest__.py) manifest_version_only_change "$f" || return 1 ;;
      *) return 1 ;;                                                        # anything else -> relevant
    esac
  done <<< "$ca"
  return 0
}
if asset_only_noop; then
  [ "${WARM_CLASSIFY_ONLY:-0}" = "1" ] && { echo "[warm] CLASSIFY: skip"; exit 0; }
  echo "[warm] SKIP (no-op): changed custom-addons files are static assets and/or a __manifest__.py version-line bump only; the -u registry/install load cannot change and is not run. Installable as-is. (override: WARM_NO_ASSET_SKIP=1)"
  exit 0
fi
[ "${WARM_CLASSIFY_ONLY:-0}" = "1" ] && { echo "[warm] CLASSIFY: validate"; exit 0; }

echo "[warm] modules: $MODCOMMA  (-u on a clone of '$BASE_DB')"
echo "[warm] validating at --log-level=warn (~tens of seconds to ~2 min, quiet is normal — do not interrupt); a PASS/FAIL line follows."

dc up -d db >/dev/null
dc exec -T db sh -c 'until pg_isready -U odoo -q; do sleep 1; done'
dc exec -T db psql -U odoo -lqt | cut -d'|' -f1 | tr -d ' ' | grep -qx "$BASE_DB" \
  || { echo "[warm] base DB '$BASE_DB' missing — run prepare-base-db.sh first" >&2; exit 3; }

CLONE="val_$$_$(date +%s%N)"
RUNC="${COMPOSE_PROJECT_NAME}-warmrun-$$"
# --rm removes the ephemeral odoo `run` container on a NORMAL finish, but a SIGTERM mid-run
# (e.g. a 2-min tool timeout on a slow/contended validation) kills `docker compose run`
# WITHOUT --rm firing -> the odoo container is orphaned and the clone DB leaks. This trap
# removes ONLY this invocation's ephemeral artifacts (its named run container, the clone
# DB, and the temp log); it deliberately does NOT touch the shared, by-design-persistent
# `db` container that concurrent sibling validations of this project reuse under the READ
# lock. Idempotent — safe on the normal path (where --rm/explicit drops already ran).
cleanup_warm() {
  { docker ps -aq --filter "name=${RUNC}" 2>/dev/null | xargs -r docker rm -f; } >/dev/null 2>&1 || true
  dc exec -T db dropdb -U odoo --if-exists "$CLONE" >/dev/null 2>&1 || true
  [ -n "${LOG:-}" ] && rm -f "$LOG" 2>/dev/null || true
}
trap cleanup_warm EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
{ docker ps -aq --filter "name=${RUNC}" 2>/dev/null | xargs -r docker rm -f; } >/dev/null 2>&1 || true  # clear a stale same-name run container (pid reuse)
dc exec -T db createdb -U odoo -T "$BASE_DB" "$CLONE"
LOG="$(mktemp)"
set +e
dc run --rm --name "$RUNC" -e VDB="$CLONE" -e MODS="$MODCOMMA" odoo bash -c '
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
