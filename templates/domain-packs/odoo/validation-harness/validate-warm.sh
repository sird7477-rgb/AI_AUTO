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
# Empty-tree OID (in $PROJECT's hash algo) for `git --attr-source=`: makes every WORKTREE-touching
# git diff over the (untrusted) project IGNORE its in-repo .gitattributes, so an attacker's
# attribute-driven clean/smudge/textconv/diff driver cannot exec. NOTE: git runs the clean filter
# to detect a content change even on a `--name-only` worktree diff, so name-only is NOT exempt from
# the clean-filter RCE vector — every worktree `git diff` below carries --attr-source.
PROJ_ATTR_NONE="$(git -C "$PROJECT" hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"
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
  MODCOMMA="$({ git -C "$PROJECT" --attr-source="$PROJ_ATTR_NONE" diff --name-only HEAD 2>/dev/null;
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
  # Harden BOTH diffs against the project's in-repo git-exec vectors: --no-ext-diff/--no-textconv
  # close the .git/config diff.external + textconv vectors; --attr-source=$PROJ_ATTR_NONE makes the
  # worktree-vs-HEAD diff IGNORE the in-repo .gitattributes so an attacker's attribute-driven
  # clean/smudge/textconv/diff driver cannot exec on the worktree blob (a bare `git diff HEAD -- f`
  # is worktree-vs-tree and STILL runs the clean filter even with --no-ext-diff --no-textconv).
  # The up...HEAD diff is tree-vs-tree (committed blobs, no worktree-blob conversion) so the flags
  # alone suffice there.
  d="$( { git -C "$PROJECT" --attr-source="$PROJ_ATTR_NONE" diff --no-ext-diff --no-textconv HEAD -- "$f" 2>/dev/null;
          [ -n "${up:-}" ] && git -C "$PROJECT" diff --no-ext-diff --no-textconv "${up}...HEAD" -- "$f" 2>/dev/null; } \
        | grep -E '^[+-]' | grep -Ev '^(\+\+\+|---)' || true )"
  [ -n "$d" ] || return 1   # no detectable content change -> be safe, validate
  # The whole changed line must be the version key AND NOTHING ELSE (key, quoted value,
  # optional trailing comma, EOL). A compact line that merely STARTS with 'version' but
  # also carries e.g. 'depends'/'installable' is install-relevant and must NOT be skipped.
  printf '%s\n' "$d" | grep -vqE "^[+-][[:space:]]*[\"']version[\"'][[:space:]]*:[[:space:]]*[\"'][^\"']*[\"'][[:space:]]*,?[[:space:]]*$" && return 1
  return 0
}
asset_only_noop() {
  [ "${WARM_NO_ASSET_SKIP:-0}" = "1" ] && return 1
  [ "${EXPLICIT_MODS:-0}" = "1" ] && return 1
  local ca f
  ca="$({ git -C "$PROJECT" --attr-source="$PROJ_ATTR_NONE" diff --name-only HEAD 2>/dev/null;
          [ -n "${up:-}" ] && git -C "$PROJECT" diff --name-only "${up}...HEAD" 2>/dev/null; } \
        | sort -u | sed -n 's#^custom-addons/.*#&#p' || true)"
  [ -n "$ca" ] || return 1   # nothing under custom-addons -> let the normal flow run
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      custom-addons/*/static/*.xml|custom-addons/*/static/*.csv) return 1 ;;  # data/QWeb loadable even under static/ -> validate
      custom-addons/*/static/*) : ;;                                          # true static asset (js/css/img/...) -> irrelevant
      custom-addons/*/__manifest__.py) manifest_version_only_change "$f" || return 1 ;;
      *) return 1 ;;                                                          # anything else -> relevant
    esac
  done <<< "$ca"
  return 0
}
if asset_only_noop; then
  [ "${WARM_CLASSIFY_ONLY:-0}" = "1" ] && { echo "[warm] CLASSIFY: skip"; exit 0; }
  echo "[warm] SKIP (no-op): changed custom-addons files are static assets and/or a __manifest__.py version-line bump only; the -u registry/install load cannot change and is not run. Installable as-is. (override: WARM_NO_ASSET_SKIP=1)"
  exit 0
fi
# (A) warm-PASS cache: the warm base is fixed and `-u <changed> --stop-after-init` installs
# the changed modules' ON-DISK content onto it, so the outcome depends only on (changed
# module set, that content, the base identity) — NOT on git history. A rebase that reshuffles
# unrelated commits but leaves the changed modules' content identical yields the same result,
# so a prior PASS is carried instead of re-running the multi-minute build. SAFE BY
# CONSTRUCTION: the key is sha256(sorted modset | on-disk content hash | base epoch), so ANY
# content difference (or a base rebuild, which bumps the epoch) misses and re-validates; only
# a sha256 collision could false-hit. PASS-only; a FAIL is never cached. Opt out: WARM_NO_CACHE=1.
warm_content_hash() {  # $1=comma modset ; prints a content hash, or nothing on any error
  local m
  { for m in $(printf '%s' "$1" | tr ',' ' '); do
      find "$PROJECT/custom-addons/$m" -type f -not -path '*/__pycache__/*' -not -name '*.pyc' -print0 2>/dev/null
    done | LC_ALL=C sort -z | xargs -0 -r sha256sum 2>/dev/null | sed "s#${PROJECT}/##g" | sha256sum | cut -d' ' -f1; } 2>/dev/null || true
}
WARM_CACHE_DIR="${HARNESS_DIR}/.warm-pass-cache.${HARNESS_SLUG}"
WARM_CACHE_KEY=""
if [ "${WARM_NO_CACHE:-0}" != "1" ]; then
  _modset="$(printf '%s' "$MODCOMMA" | tr ',' '\n' | sed '/^$/d' | sort -u | paste -sd, -)"
  _eligible=1
  for _m in $(printf '%s' "$_modset" | tr ',' ' '); do
    [ -d "$PROJECT/custom-addons/$_m" ] || _eligible=0   # a deleted/missing module dir -> never cache
  done
  if [ "$_eligible" = "1" ]; then
    _chash="$(warm_content_hash "$_modset")"
    # An ABSENT base epoch means we cannot prove which base the prior PASS was on, so a base
    # change (new parity / module set) could not invalidate the key. Refuse to cache rather
    # than substitute a constant — caching stays inert until prepare-base-db.sh stamps an epoch.
    _epoch="$(cat "${HARNESS_DIR}/.warm-base.${HARNESS_SLUG}.${BASE_DB}.epoch" 2>/dev/null || true)"
    if [ -n "$_chash" ] && [ -n "$_epoch" ]; then
      WARM_CACHE_KEY="$(printf '%s|%s|%s' "$_modset" "$_chash" "$_epoch" | sha256sum | cut -d' ' -f1)"
    fi
  fi
fi
if [ -n "$WARM_CACHE_KEY" ] && [ -f "${WARM_CACHE_DIR}/${WARM_CACHE_KEY}" ]; then
  [ "${WARM_CLASSIFY_ONLY:-0}" = "1" ] && { echo "[warm] CLASSIFY: cached"; exit 0; }
  echo "[warm] PASS (cached, no-op): '$MODCOMMA' content already validated on this warm base (key ${WARM_CACHE_KEY:0:12}); -u not re-run. (override: WARM_NO_CACHE=1)"
  exit 0
fi
# Test/CI hook: prime the cache for the current key WITHOUT a docker run, so the cache path
# is fixturable offline. Never set in normal use.
if [ "${WARM_CACHE_PRIME:-0}" = "1" ] && [ -n "$WARM_CACHE_KEY" ]; then
  mkdir -p "$WARM_CACHE_DIR" 2>/dev/null && : > "${WARM_CACHE_DIR}/${WARM_CACHE_KEY}" 2>/dev/null || true
  echo "[warm] CACHE PRIMED ${WARM_CACHE_KEY:0:12}"; exit 0
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
# lock. The run container is removed by EXACT name (`docker rm -f "$RUNC"`), never via a
# `--filter name=` substring — a substring match would catch a sibling whose pid is a
# digit-prefix of ours (`...-warmrun-123` matching `...-warmrun-1234`) and force-kill its
# LIVE validation. Idempotent — safe on the normal path (where --rm/explicit drops already ran).
cleanup_warm() {
  docker rm -f "$RUNC" >/dev/null 2>&1 || true
  dc exec -T db dropdb -U odoo --if-exists "$CLONE" >/dev/null 2>&1 || true
  [ -n "${LOG:-}" ] && rm -f "$LOG" 2>/dev/null || true
}
trap cleanup_warm EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
docker rm -f "$RUNC" >/dev/null 2>&1 || true  # clear a stale same-EXACT-name run container (pid reuse); never a substring match
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
# Record this PASS so an identical (modset, on-disk content, base epoch) skips the -u re-run.
# Only ever written on a real PASS; a FAIL above already exited without reaching here.
if [ -n "${WARM_CACHE_KEY:-}" ]; then
  mkdir -p "$WARM_CACHE_DIR" 2>/dev/null && : > "${WARM_CACHE_DIR}/${WARM_CACHE_KEY}" 2>/dev/null || true
fi
echo "[warm] PASS — $MODCOMMA updates cleanly on warm base (parity-pinned Odoo 19)"
