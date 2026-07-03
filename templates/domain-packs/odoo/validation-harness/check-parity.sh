#!/usr/bin/env bash
# Fail-closed parity guard for the warm Odoo registry-load base.
# Usage: check-parity.sh <project_repo> [base_db]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${1:?usage: check-parity.sh <project_repo> [base_db]}"
BASE_DB="${2:-${ODOO_BASE_DB:-base}}"
PROJECT_ADDONS="$PROJECT/custom-addons"
[ -d "$PROJECT_ADDONS" ] || { echo "[parity] BLOCKED (parity unconfirmed): no custom-addons at $PROJECT_ADDONS" >&2; exit 4; }

. "$HERE/harness-slug.sh"
HARNESS_SLUG="$(harness_proj_slug "$PROJECT")"
STAMP="${HARNESS_DIR:-$HERE}/.warm-base.${HARNESS_SLUG}.${BASE_DB}.parity.env"

module_set() {
  python3 - "$PROJECT_ADDONS" <<'PY'
import ast
import glob
import os
import sys

root = sys.argv[1]
mods = []
for manifest in sorted(glob.glob(os.path.join(root, "*", "__manifest__.py"))):
    name = os.path.basename(os.path.dirname(manifest))
    try:
        with open(manifest, encoding="utf-8") as fh:
            data = ast.literal_eval(fh.read())
    except Exception:
        continue
    if data.get("installable", True):
        mods.append(name)
print(",".join(sorted(mods)))
PY
}

stamp_value() {
  local key="$1"
  sed -n "s/^${key}=//p" "$STAMP" 2>/dev/null | head -n 1
}

blocked() {
  echo "[parity] BLOCKED (parity unconfirmed): $*" >&2
  exit 4
}

[ -f "$STAMP" ] || blocked "missing warm-base parity stamp: $STAMP"

current_modules="$(module_set)"
[ -n "$current_modules" ] || blocked "no installable custom modules"
current_sha="$(printf '%s' "$current_modules" | sha256sum | cut -d' ' -f1)"

point_release="$(stamp_value point_release)"
stamped_modules="$(stamp_value module_set)"
stamped_sha="$(stamp_value module_set_sha)"

[ -n "$point_release" ] && [ "$point_release" != "unconfirmed" ] \
  || blocked "missing odoo.sh point release in $STAMP; rebuild with ODOO_SH_POINT_RELEASE=<point-release> prepare-base-db.sh"
[ -n "$stamped_sha" ] || blocked "missing module_set_sha in $STAMP"
[ "$stamped_sha" = "$current_sha" ] \
  || blocked "module-set drift: stamp=${stamped_sha} current=${current_sha}; rebuild warm base from the odoo.sh module set"
if [ -n "$stamped_modules" ] && [ "$stamped_modules" != "$current_modules" ]; then
  blocked "module-set changed: stamp=${stamped_modules} current=${current_modules}; rebuild warm base"
fi

echo "[parity] PASS — odoo.sh point_release=${point_release} module_set_sha=${current_sha:0:12}"
