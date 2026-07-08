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
# Fail fast with a clear message if the Docker daemon is down (see harness-preflight.sh).
. "$HERE/harness-preflight.sh"
harness_require_docker || exit 4
PROJECT="${1:?usage: prepare-base-db.sh <project_repo>}"
# RED17b-2-class fix (validate-full.sh ODOO_DEMO_REBUILD path): a caller that has
# already materialized an IMMUTABLE snapshot of the reviewed ref (validate-full.sh's
# HARNESS_SNAPSHOT_DIR/custom-addons, HARNESS_VALIDATE_REF-pinned) must be able to hand
# THAT dir to the base rebuild instead of this script unconditionally re-deriving
# "$PROJECT/custom-addons" -- the live, mutable working tree -- which would silently
# reintroduce the "validate the live dir, not the reviewed ref" TOCTOU class RED17b-2/
# 18/18b closed everywhere else (deterministic under an overridden HARNESS_VALIDATE_REF;
# racy at defaults over this rebuild's multi-minute window). Default (no override) is
# UNCHANGED: "$PROJECT/custom-addons", so a direct/standalone invocation behaves exactly
# as before.
export PROJECT_ADDONS="${PREPARE_BASE_ADDONS_DIR:-$PROJECT/custom-addons}"
[ -d "$PROJECT_ADDONS" ] || { echo "[base] no custom-addons at $PROJECT_ADDONS" >&2; exit 2; }
# AUD-RCE1 fix (same class as PREPARE_BASE_ADDONS_DIR above, one field over, WORSE blast
# radius): requirements.txt content becomes `pip3 install -r` in the Dockerfile build of
# the SHARED base/base_demo image every later validate-warm/validate-full run reuses --
# so for a ref-scoped rebuild it must be the REVIEWED ref's requirements.txt, never the
# live/mutable $PROJECT/requirements.txt (a malicious --index-url, VCS/URL requirement,
# or poisoned pin in the live tree would otherwise get build-time-executed even though it
# was never reviewed/committed). validate-full.sh's harness_materialize_tree now
# materializes the reviewed ref's requirements.txt (if any) as a SIBLING of the snapshot
# custom-addons dir it already hands over via PREPARE_BASE_ADDONS_DIR, so deriving the
# default from dirname(PROJECT_ADDONS) picks that snapshot copy up automatically with NO
# further change needed at the call site -- while an explicit PREPARE_BASE_REQUIREMENTS
# still wins for a caller that wants to say otherwise. Default (no override at all, the
# standalone/direct invocation): dirname("$PROJECT/custom-addons") = "$PROJECT", so this
# is byte-identical to the old "$PROJECT/requirements.txt" behavior.
export PREPARE_BASE_REQUIREMENTS="${PREPARE_BASE_REQUIREMENTS:-$(dirname "$PROJECT_ADDONS")/requirements.txt}"
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
# RED-16 fix: the Docker build's ACTUAL input is this slug-namespaced path (see
# docker-compose.validate.yml's `build.args.DEPS_FILE`) so two DIFFERENT repos sharing
# one ODOO_HARNESS_DIR never clobber each other's build-context deps file. `.deps.txt`
# (written below, unchanged) remains a human-readable "last run" artifact only.
DEPS_FILE_NS="$HERE/.deps.${COMPOSE_PROJECT_NAME}.txt"
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
MODULE_SET_SHA="$(printf '%s' "$MODS" | sha256sum | cut -d' ' -f1)"

# Deps source of truth: install EXACTLY what odoo.sh installs. If the REVIEWED ref has a
# root requirements.txt (U-C1) -- $PREPARE_BASE_REQUIREMENTS above, never a direct read
# of $PROJECT/requirements.txt -- the local image installs from it (drift-checked vs
# manifests); else fall back to the manifest python deps. This is the Dockerfile
# "repoint" — the build context's .deps.txt is now requirements.txt content when present.
# FAIL-CLOSED (AUD-RCE1): a ref-scoped rebuild whose reviewed ref genuinely has no
# requirements.txt hits the `else` branch below -- manifest-derived deps only, ZERO bytes
# read from the live tree -- rather than silently falling back to the live file. That is
# a safe state (no extra deps beyond what the reviewed manifests themselves declare), not
# a loud refusal, because it is indistinguishable from — and exactly as safe as — a
# project that has simply never needed a requirements.txt (the pre-existing, long-
# standing default behavior for every caller before this fix).
if [ -f "$PREPARE_BASE_REQUIREMENTS" ]; then
  tr -d '\r' < "$PREPARE_BASE_REQUIREMENTS" | grep -vE '^[[:space:]]*(#|$)' > "$HERE/.deps.txt" || true
  echo "[base] deps source: $PREPARE_BASE_REQUIREMENTS (odoo.sh parity)"
  # Surface drift (do not silently swallow): the build proceeds with requirements.txt
  # as-is, but a manifest dep missing from it WILL break the odoo.sh build. The enforced
  # gate is the standalone `gen-requirements.sh --check` (rc 1); here it is advisory.
  # (This drift check itself still reads the LIVE $PROJECT tree on both sides -- advisory
  # only, never feeds .deps.txt/pip, so it is not part of the AUD-RCE1 fix surface.)
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
  echo "[base] deps source: custom-addons manifests (no requirements.txt at $PREPARE_BASE_REQUIREMENTS)"
fi
echo "[base] python deps: $(paste -sd' ' "$HERE/.deps.txt" 2>/dev/null || echo none)"
# RED-16 fix: mirror .deps.txt into the slug-namespaced build input (see DEPS_FILE_NS
# above) -- same content, different path, so a concurrent different-repo build never
# reads/overwrites this one.
cp "$HERE/.deps.txt" "$DEPS_FILE_NS"
# Supply-chain advisory (never blocking): LOUD warning if the Dockerfile's base image is a
# mutable tag with no @sha256 digest pin. See harness-preflight.sh/Dockerfile header.
harness_check_base_image_pin
dc build odoo >/dev/null
dc up -d db >/dev/null
dc exec -T db sh -c 'until pg_isready -U odoo -q; do sleep 1; done'
dc exec -T db dropdb -U odoo --if-exists "$BASE_DB" >/dev/null 2>&1 || true
echo "[base] installing full set into '$BASE_DB' (one-time, ~10min)..."
# Log-grep backstop (same FAIL_RE pattern + mechanism as validate-warm.sh/
# validate-full.sh's IDENTICAL "-i/-u ... --stop-after-init" invocation): rc can be 0
# even on a failed module load in edge configs (their own measured, documented
# behavior), and until now this was the one caller of that same odoo-bin invocation
# with ZERO backstop -- a silently-broken base could be reported "ready" and every
# downstream validate-warm/validate-full run would then build on a broken foundation.
# Capture the run's combined output to a log; a FAIL_RE hit fails this step LOUD and
# non-zero even when rc==0.
FAIL_RE="ParseError|cannot be located|does not exist|Invalid field|Element .* cannot|Failed to load registry|violates not-null|FAIL|ERROR.*test|[0-9]+ failed|ValidationError|Quants cannot be created|should be set"
LOG="$(mktemp)"
set +e
dc run --rm \
  -e VDB="$BASE_DB" -e LANGCODE="$LANGCODE" -e COMPANY_COUNTRY="$COMPANY_COUNTRY" -e MODS="$MODS" -e DEMO_FLAG="$DEMO_FLAG" \
  odoo bash -c '
set -e
OPTS="-d $VDB --addons-path=/mnt/community/addons,/mnt/enterprise,/mnt/extra-addons --db_host=db --db_user=odoo --db_password=odoo --log-level=warn"
python3 /mnt/community/odoo-bin $OPTS -i base ${LANGCODE:+--load-language=$LANGCODE} --stop-after-init
python3 /mnt/community/odoo-bin shell $OPTS --no-http < /mnt/harness/setup_company.py
python3 /mnt/community/odoo-bin $OPTS -i $MODS $DEMO_FLAG --stop-after-init
' 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
if [ "$rc" -ne 0 ] || grep -qiE "$FAIL_RE" "$LOG"; then
  echo "[base] FAIL (rc=$rc) — install/load error above; '$BASE_DB' NOT ready." >&2
  rm -f "$LOG"
  exit 1
fi
rm -f "$LOG"
# (A) warm-PASS cache invalidation: stamp a base epoch so validate-warm.sh's PASS cache
# (keyed partly on this) is invalidated whenever the base is rebuilt — a new parity pin or
# module set means a prior PASS no longer proves installability. A nanosecond stamp differs
# across rebuilds.
date +%s%N > "${HARNESS_DIR}/.warm-base.${HARNESS_SLUG}.${BASE_DB}.epoch" 2>/dev/null || true
PARITY_POINT_RELEASE="$(printf '%s' "${ODOO_PARITY_POINT_RELEASE:-${ODOO_SH_POINT_RELEASE:-}}" | tr -d '\r\n')"
{
  printf 'point_release=%s\n' "${PARITY_POINT_RELEASE:-unconfirmed}"
  printf 'module_set=%s\n' "$MODS"
  printf 'module_set_sha=%s\n' "$MODULE_SET_SHA"
  printf 'built_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${HARNESS_DIR}/.warm-base.${HARNESS_SLUG}.${BASE_DB}.parity.env.tmp" 2>/dev/null \
  && mv "${HARNESS_DIR}/.warm-base.${HARNESS_SLUG}.${BASE_DB}.parity.env.tmp" "${HARNESS_DIR}/.warm-base.${HARNESS_SLUG}.${BASE_DB}.parity.env" 2>/dev/null || true
if [ -n "$PARITY_POINT_RELEASE" ]; then
  echo "[base] parity stamp: odoo.sh point_release=$PARITY_POINT_RELEASE module_set_sha=${MODULE_SET_SHA:0:12}"
else
  echo "[base] WARNING parity point release not provided; validate-warm will BLOCK until rebuilt with ODOO_SH_POINT_RELEASE=<point-release>."
fi
if [ -x "${HARNESS_DIR}/dump-schema-catalog.sh" ]; then
  "${HARNESS_DIR}/dump-schema-catalog.sh" "$BASE_DB" "${HARNESS_DIR}/.warm-base.${HARNESS_SLUG}.${BASE_DB}.schema-catalog.json" "$MODULE_SET_SHA" \
    || echo "[base] WARNING schema catalog dump failed; check-schema-catalog.py will report NOT screened."
fi
echo "[base] '$BASE_DB' ready. Fast validate: validate-warm.sh \"$PROJECT\" [module ...]"
