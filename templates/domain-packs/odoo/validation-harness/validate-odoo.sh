#!/usr/bin/env bash
# Local Odoo 19 registry-load validation gate (ST-P1-51 CI slice).
# Installs changed custom-addons modules on a disposable DB against parity-pinned
# Odoo 19 community+enterprise source; fails on registry/view/field errors that
# static XML parsing cannot catch.
#
# Usage: validate-odoo.sh <project_repo> [module ...]
#   no modules -> auto-detect from `git diff` changed custom-addons/<module>/ paths
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="$(cd "$HERE/.." && pwd)"
export ODOO_COMMUNITY="${ODOO_COMMUNITY:-$DATA/01. Odoo.19(커뮤니티)}"
export ODOO_ENTERPRISE="${ODOO_ENTERPRISE:-$DATA/02. Odoo.19(enterprise)}"
# Locale baseline (Korean projects: ko_KR). Empty -> en_US only. Matches odoo.sh DB.
ODOO_LOAD_LANGUAGE="${ODOO_LOAD_LANGUAGE:-ko_KR}"
# Extra standard modules to pre-install before custom modules (1-full adds l10n_kr).
# 1-lite default: none.
ODOO_BASE_MODULES="${ODOO_BASE_MODULES:-}"
# 1-lite baseline: set company fiscal country (no full chart) so account.tax
# country_id resolves. Stateless: applied fresh per run, nothing persisted.
ODOO_COMPANY_COUNTRY="${ODOO_COMPANY_COUNTRY:-base.kr}"
export HARNESS_DIR="$HERE"

PROJECT="${1:?usage: validate-odoo.sh <project_repo> [module ...]}"; shift || true
export PROJECT_ADDONS="$PROJECT/custom-addons"
[ -d "$PROJECT_ADDONS" ] || { echo "[validate] no custom-addons at $PROJECT_ADDONS" >&2; exit 2; }
# Per-project isolation: namespace this project's compose stack (container/network/volume)
# so a different project never shares the postgres/base. Must precede any docker compose call.
. "$HERE/harness-slug.sh"
COMPOSE_PROJECT_NAME="$(harness_proj_slug "$PROJECT")"
export COMPOSE_PROJECT_NAME

if [ "$#" -gt 0 ]; then
  MODCOMMA="$(echo "$*" | tr ' ' ',')"
else
  # Detect changed custom modules from uncommitted changes AND committed-but-not-
  # yet-pushed changes (after commit the working tree is clean, so `git diff HEAD`
  # alone would miss the commits being pushed).
  up="$(git -C "$PROJECT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  # --attr-source=<empty-tree>: the worktree `--name-only` diff runs the in-repo clean filter to
  # detect changes (RCE vector over an untrusted project), so ignore the project's .gitattributes.
  # The up...HEAD diff is tree-vs-tree (no worktree blob) and needs no attr-source.
  _attr_none="$(git -C "$PROJECT" hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"
  MODCOMMA="$({ git -C "$PROJECT" --attr-source="$_attr_none" diff --name-only HEAD 2>/dev/null;
                [ -n "$up" ] && git -C "$PROJECT" diff --name-only "$up...HEAD" 2>/dev/null; } \
    | sed -n 's#^custom-addons/\([^/]*\)/.*#\1#p' | sort -u | paste -sd, -)"
fi
[ -n "$MODCOMMA" ] || { echo "[validate] no changed custom-addons modules; skip"; exit 0; }
echo "[validate] modules: $MODCOMMA  (Odoo 19.0.0 FINAL, parity-pinned)"

# Collect project python deps (external_dependencies.python) -> .deps.txt, so the
# derived image matches odoo.sh's pip set. Enterprise source is mounted, not baked.
python3 - "$PROJECT_ADDONS" > "$HERE/.deps.txt" <<'PY'
import ast,glob,os,sys
root=sys.argv[1]; deps=set()
for m in glob.glob(os.path.join(root,"*","__manifest__.py")):
    try:
        d=ast.literal_eval(open(m,encoding="utf-8").read())
        for p in (d.get("external_dependencies",{}) or {}).get("python",[]) or []:
            deps.add(p)
    except Exception:
        pass
print("\n".join(sorted(deps)))
PY
echo "[validate] python deps: $(paste -sd' ' "$HERE/.deps.txt" 2>/dev/null || echo none)"
docker compose -f "$HERE/docker-compose.validate.yml" build odoo >/dev/null
# Start Postgres and wait for readiness before running Odoo (the image entrypoint
# is cleared and there is no DB healthcheck, so avoid racing DB startup).
docker compose -f "$HERE/docker-compose.validate.yml" up -d db >/dev/null
docker compose -f "$HERE/docker-compose.validate.yml" exec -T db \
  sh -c 'until pg_isready -U odoo -q; do sleep 1; done'

DB="val_$$_$(date +%s%N)"
LOG="$(mktemp)"
# Disposable contract: drop the validation DB on success or failure so it does not
# accumulate in the compose volume.
cleanup_validate_db() {
  docker compose -f "$HERE/docker-compose.validate.yml" exec -T db \
    dropdb -U odoo --if-exists "$DB" >/dev/null 2>&1 || true
  rm -f "$LOG" 2>/dev/null || true
}
trap cleanup_validate_db EXIT
# 1-lite stateless flow on a fresh disposable DB:
#   1) install base (+ optional base modules) and activate the language
#   2) set company fiscal country (setup_company.py) — no persistent state
#   3) fresh-install the changed custom modules and catch registry/view/field errors
set +e
docker compose -f "$HERE/docker-compose.validate.yml" run --rm \
  -e VDB="$DB" \
  -e LANGCODE="${ODOO_LOAD_LANGUAGE:-}" \
  -e BASEMODS="${ODOO_BASE_MODULES:-}" \
  -e COMPANY_COUNTRY="$ODOO_COMPANY_COUNTRY" \
  -e MODS="$MODCOMMA" \
  odoo bash -c '
set -e
OPTS="-d $VDB --addons-path=/mnt/community/addons,/mnt/enterprise,/mnt/extra-addons --db_host=db --db_user=odoo --db_password=odoo --log-level=warn"
python3 /mnt/community/odoo-bin $OPTS -i base${BASEMODS:+,$BASEMODS} ${LANGCODE:+--load-language=$LANGCODE} --stop-after-init
python3 /mnt/community/odoo-bin shell $OPTS --no-http < /mnt/harness/setup_company.py
python3 /mnt/community/odoo-bin $OPTS -i $MODS --without-demo=all --stop-after-init
' 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

if [ "$rc" -ne 0 ] || grep -qiE "ParseError|cannot be located|does not exist|Invalid field|Element .* cannot|Failed to load registry" "$LOG"; then
  echo "[validate] FAIL (rc=$rc) — registry/view/field error above. NOT installable on odoo.sh as-is."
  rm -f "$LOG"; exit 1
fi
rm -f "$LOG"
echo "[validate] PASS — $MODCOMMA installs/loads on parity-pinned Odoo 19"
