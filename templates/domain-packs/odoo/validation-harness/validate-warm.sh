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
# Fail fast with a clear message if the Docker daemon is down (see harness-preflight.sh).
. "$HERE/harness-preflight.sh"
harness_require_docker || exit 4
PROJECT="${1:?usage: validate-warm.sh <project_repo> [module ...]}"; shift || true
BASE_DB="${ODOO_BASE_DB:-base}"

# RED17b-2 fix: mount an IMMUTABLE SNAPSHOT of the target commit's custom-addons,
# never the live (mutable) working directory. A bind-mount of $PROJECT/custom-addons
# tracks whatever is on disk at whatever moment the container's odoo-bin -u actually
# reads each file -- tens of seconds to ~2 minutes after this script starts (see the
# "quiet is normal" note below) -- so a same-UID or merely concurrent (non-adversarial)
# edit to custom-addons/ WHILE this runs makes the container test different bytes than
# the commit `git push` actually transmits, silently certifying content that was never
# the pushed tree. See .ops-game/R8-red17b-final-convergence.md RED17b-2.
# hooks/pre-push sets HARNESS_VALIDATE_REF to the exact pushed local sha so a push
# validates precisely what it transmits; default HEAD gives the same immutable-commit
# ground truth to a direct/manual invocation. (serve.sh, by contrast, is INTENTIONALLY
# a live mount -- that is dev-time convenience, not validation, and is deliberately
# left untouched by this fix.)
HARNESS_VALIDATE_REF="${HARNESS_VALIDATE_REF:-HEAD}"
HARNESS_SNAPSHOT_DIR="$(mktemp -d "${HARNESS_DIR}/.odoo-harness-snap.XXXXXX")"
# Early cleanup for any exit before `trap cleanup_warm EXIT` (below) is installed --
# e.g. the early "no changed modules" skips further down. cleanup_warm additionally
# removes this same directory once it is installed, so every exit path stays covered.
trap 'rm -rf "$HARNESS_SNAPSHOT_DIR" 2>/dev/null || true' EXIT
# RED18 fix (.ops-game/R9-red18-verify-toctou-fix.md point 5): `git archive
# <ref>` is NOT filter-immune -- it DOES run the archived tree's OWN
# (committed, attacker-controlled) .gitattributes clean/smudge/textconv/filter
# conversions (empirically reproduced: a committed `* filter=evil` +
# `filter.evil.smudge=<cmd>` config execs <cmd> during `git archive`), and
# `git archive` has NO --attr-source flag to suppress it -- the escape hatch
# every other worktree-touching git call in this file relies on does not exist
# for archive. Since $HARNESS_VALIDATE_REF is exactly the untrusted pushed
# tree, that is a net-new git-exec RCE. Materialize with `git ls-tree` +
# `git cat-file blob` instead: both are PURE OBJECT-DATABASE reads that never
# consult .gitattributes, never run clean/smudge/textconv/filter drivers, and
# never refresh the index (so no fsmonitor-hook exec either) -- that machinery
# only exists for worktree-checkout/archive operations, which these two
# plumbing commands do not implement. Immune by construction, not by an
# extra flag that has to be remembered on every call.
harness_materialize_tree() {  # <project_repo> <ref> <dest_root> ; writes dest_root/custom-addons/** and dest_root/requirements.txt (if present at ref)
  local proj="$1" ref="$2" dest="$3" n=0 line meta path mode type oid outpath parentdir destreal parentreal
  # Fail closed on an unresolvable ref up front -- do not let ls-tree's silent
  # empty output on a bad ref masquerade as "zero files, still a valid pass".
  git -C "$proj" rev-parse --verify -q "${ref}^{tree}" >/dev/null 2>&1 || return 1
  destreal="$(cd "$dest" && pwd -P)" || return 1
  while IFS= read -r -d '' line; do
    # ls-tree -z entry: "<mode> <type> <oid>\t<path>" (NUL-terminated, -z also
    # disables C-style path quoting, so this split is safe for any byte in path).
    meta="${line%%$'\t'*}"; path="${line#*$'\t'}"
    mode="${meta%% *}"
    type="${meta#* }"; type="${type%% *}"
    oid="${meta##* }"
    case "$mode" in
      160000)  # submodule/gitlink -- not a blob in THIS repo; do not follow it.
        echo "[warm] NOTE: skipping submodule entry '$path' at $ref (not materialized)" >&2
        continue ;;
      120000)
        # RED18b fix (.ops-game/R9-red18b-verify-hardened.md point 3, CRITICAL):
        # a committed symlink's target text is fully attacker-controlled (e.g.
        # -> /root/.ssh/id_rsa, or -> ../../..) and this snapshot dir gets
        # bind-mounted into the odoo container -- recreating it here would land
        # a live, unvalidated symlink inside $PROJECT_ADDONS. Odoo addon
        # modules never need an in-tree symlink, so reject it outright, same
        # as a submodule entry above. This also removes the "write through an
        # earlier-created symlink" ordering escape (point 2's variant b) by
        # construction: no symlink is EVER created anywhere in $dest.
        echo "[warm] NOTE: skipping symlink entry '$path' at $ref (symlinks are not materialized; not a valid addon source file)" >&2
        continue ;;
    esac
    [ "$type" = "blob" ] || { echo "[warm] NOTE: skipping non-blob entry '$path' (type=$type) at $ref" >&2; continue; }
    # RED18b fix (.ops-game/R9-red18b-verify-hardened.md point 2, CRITICAL): a
    # hand-crafted tree (via `git mktree`, then pushed) can contain an entry
    # whose PATH COMPONENT is literally ".." -- `git ls-tree -r` emits it
    # verbatim (e.g. "custom-addons/../../PWNED-harness-preflight.sh"), and an
    # unsanitized "$dest/$path" then writes OUTSIDE $dest. Since $dest is a
    # sibling of this harness's own scripts (mktemp -d "$HARNESS_DIR/..."),
    # just two ".." components land an attacker-controlled executable next to
    # the real harness scripts -- a self-propagating backdoor. Reject (fail
    # CLOSED) any path that is absolute, has a ".." path component anywhere,
    # or does not sit under custom-addons/ -- BEFORE outpath is ever
    # computed/used, and name the offending path in the error.
    case "$path" in
      /*)
        echo "[warm] REJECT: absolute path '$path' at $ref -- aborting materialization" >&2
        return 1 ;;
    esac
    case "$path" in
      ..|../*|*/../*|*/..)
        echo "[warm] REJECT: '..' path component in '$path' at $ref -- aborting materialization" >&2
        return 1 ;;
    esac
    case "$path" in
      custom-addons/*) : ;;
      # AUD-RCE1 fix: requirements.txt is the one non-custom-addons file that feeds
      # `pip3 install -r` (prepare-base-db.sh's .deps.txt). Materialize it from the
      # REVIEWED ref via this same filter-immune cat-file path, never the live
      # $PROJECT/requirements.txt -- same class of fix as custom-addons/* above, one
      # field over. Exact top-level match only (not e.g. custom-addons/requirements.txt).
      requirements.txt) : ;;
      *)
        echo "[warm] REJECT: entry '$path' at $ref is outside custom-addons/ (and is not requirements.txt) -- aborting materialization" >&2
        return 1 ;;
    esac
    outpath="$dest/$path"
    parentdir="$(dirname "$outpath")"
    mkdir -p "$parentdir" || return 1
    # Belt-and-suspenders: canonicalize the just-created parent dir and assert
    # it is still strictly inside $dest. The lexical ".." rejection above
    # already makes an escape impossible for a well-formed path; this
    # independent, structural check is the second line of defense the fix
    # calls for, and it can never be defeated by a through-symlink write since
    # no symlink is ever created in $dest (see the 120000 case above).
    parentreal="$(cd "$parentdir" && pwd -P)" || return 1
    case "$parentreal" in
      "$destreal"|"$destreal"/*) : ;;
      *)
        echo "[warm] REJECT: resolved path for '$path' escapes the snapshot dir ($parentreal not under $destreal) -- aborting materialization" >&2
        return 1 ;;
    esac
    # RAW stored bytes, zero conversion -- this is the filter-immune read.
    git -C "$proj" cat-file blob "$oid" > "$outpath" || return 1
    [ "$mode" = "100755" ] && chmod +x "$outpath"
    # Only custom-addons/* entries count toward the fail-closed gate below --
    # requirements.txt is OPTIONAL at the ref (a ref genuinely without one is a valid
    # state; the deps-consuming caller fails closed on ITS OWN absence check, not on
    # this function's return value), so its presence must never mask an otherwise-empty
    # custom-addons/ at the ref.
    case "$path" in custom-addons/*) n=$((n+1)) ;; esac
  done < <(git -C "$proj" ls-tree -r -z "$ref" -- custom-addons requirements.txt 2>/dev/null)
  [ "$n" -gt 0 ] || return 1   # no custom-addons/ (or only unmaterializable entries) at that ref -> fail closed
  return 0
}
if ! harness_materialize_tree "$PROJECT" "$HARNESS_VALIDATE_REF" "$HARNESS_SNAPSHOT_DIR"; then
  echo "[warm] cannot materialize '$HARNESS_VALIDATE_REF':custom-addons (bad ref, no custom-addons/ at that commit, or object read error)" >&2
  exit 2
fi
export PROJECT_ADDONS="$HARNESS_SNAPSHOT_DIR/custom-addons"
# Empty-tree OID (in $PROJECT's hash algo) for `git --attr-source=`: makes every WORKTREE-touching
# git diff over the (untrusted) project IGNORE its in-repo .gitattributes, so an attacker's
# attribute-driven clean/smudge/textconv/diff driver cannot exec. NOTE: git runs the clean filter
# to detect a content change even on a `--name-only` worktree diff, so name-only is NOT exempt from
# the clean-filter RCE vector — every worktree `git diff` below carries --attr-source. Each worktree
# diff ALSO carries `-c core.fsmonitor=` to kill the SEPARATE in-repo `.git/config` fsmonitor
# HOOK-PROGRAM exec vector (config, not attribute — --attr-source does NOT reach it) that fires as
# the diff refreshes the index; this standalone validator does not source hooks/git-scrub.sh. The
# up...HEAD diffs are tree-vs-tree (no worktree scan) so they need neither.
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
  MODCOMMA="$({ git -C "$PROJECT" --attr-source="$PROJ_ATTR_NONE" -c core.fsmonitor= diff --name-only HEAD 2>/dev/null;
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
  d="$( { git -C "$PROJECT" --attr-source="$PROJ_ATTR_NONE" -c core.fsmonitor= diff --no-ext-diff --no-textconv HEAD -- "$f" 2>/dev/null;
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
  ca="$({ git -C "$PROJECT" --attr-source="$PROJ_ATTR_NONE" -c core.fsmonitor= diff --name-only HEAD 2>/dev/null;
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
  # Hashes $PROJECT_ADDONS (the materialized snapshot, RED17b-2), not the live
  # $PROJECT/custom-addons -- so the cache key reflects exactly the bytes the
  # container actually validated, not whatever the live tree held at hash time.
  # The sed strips the (per-run, random) snapshot dir prefix so the key stays
  # stable/relative across runs instead of embedding a throwaway tmpdir name.
  local m
  { for m in $(printf '%s' "$1" | tr ',' ' '); do
      find "$PROJECT_ADDONS/$m" -type f -not -path '*/__pycache__/*' -not -name '*.pyc' -print0 2>/dev/null
    done | LC_ALL=C sort -z | xargs -0 -r sha256sum 2>/dev/null | sed "s#${PROJECT_ADDONS}/##g" | sha256sum | cut -d' ' -f1; } 2>/dev/null || true
}
WARM_CACHE_DIR="${HARNESS_DIR}/.warm-pass-cache.${HARNESS_SLUG}"
WARM_CACHE_KEY=""
if [ "${WARM_NO_CACHE:-0}" != "1" ]; then
  _modset="$(printf '%s' "$MODCOMMA" | tr ',' '\n' | sed '/^$/d' | sort -u | paste -sd, -)"
  _eligible=1
  for _m in $(printf '%s' "$_modset" | tr ',' ' '); do
    [ -d "$PROJECT_ADDONS/$_m" ] || _eligible=0   # a deleted/missing module dir -> never cache
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
# PROVENANCE (bypass fix, LIVE/CRITICAL): a cache marker is only ever a valid stand-in
# for a real docker-backed load if IT was itself written by a real docker-backed load.
# WARM_CACHE_PRIME below writes a marker WITHOUT ever invoking docker (by design, for
# offline test/CI fixturing) -- so the two write sites must stamp DISTINCT, non-forgeable
# content, and the reuse path here must refuse anything that is not stamped "genuine".
# Without this, a marker planted out-of-band (a stray WARM_CACHE_PRIME=1 test/CI run, or
# a hostile shell) durably poisons this key: a LATER, ordinary (non-primed) invocation --
# e.g. a real `git push` -- would read the file, see it exists, and print a cached PASS
# for a module that never actually loaded in Odoo. An ambient/leaked WARM_CACHE_PRIME=1
# on the real push itself is the same bypass by a second route; hooks/pre-push now unsets
# it at the chokepoint (defense in depth), but that alone does not protect against a
# marker planted earlier by a DIFFERENT (test/CI/hostile) process and merely read back
# here, which is why the provenance stamp -- not just the env scrub -- is the fix.
WARM_MARK_GENUINE='provenance=genuine'
WARM_MARK_PRIMED='provenance=primed'
warm_marker_provenance() {  # $1=path ; prints the marker's first line, or nothing
  head -n 1 -- "$1" 2>/dev/null || true
}
if [ -n "$WARM_CACHE_KEY" ] && [ -f "${WARM_CACHE_DIR}/${WARM_CACHE_KEY}" ]; then
  _warm_prov="$(warm_marker_provenance "${WARM_CACHE_DIR}/${WARM_CACHE_KEY}")"
  if [ "$_warm_prov" = "$WARM_MARK_GENUINE" ] \
     || { [ "$_warm_prov" = "$WARM_MARK_PRIMED" ] && [ "${WARM_CACHE_PRIME:-0}" = "1" ]; }; then
    [ "${WARM_CLASSIFY_ONLY:-0}" = "1" ] && { echo "[warm] CLASSIFY: cached"; exit 0; }
    "$HERE/check-parity.sh" "$PROJECT" "$BASE_DB"
    echo "[warm] PASS (cached, no-op): '$MODCOMMA' content already validated on this warm base (key ${WARM_CACHE_KEY:0:12}); -u not re-run. (override: WARM_NO_CACHE=1)"
    exit 0
  fi
  # Marker present but NOT genuine-provenance (a primed/test marker, or an unrecognized/
  # legacy-empty one) read by a plain (non-primed) invocation -> a cache MISS, never a
  # PASS. Fall through to real validation (or, further below, re-priming if THIS
  # invocation also sets WARM_CACHE_PRIME=1 -- an equally-primed/test context).
  echo "[warm] NOTE: cached marker at key ${WARM_CACHE_KEY:0:12} has non-genuine provenance ('${_warm_prov:-<empty>}') for this invocation -- treating as a cache MISS and re-validating." >&2
fi
# Test/CI hook: prime the cache for the current key WITHOUT a docker run, so the cache path
# is fixturable offline. Never set in normal use. The marker is stamped "primed" (never
# "genuine") so it can only ever satisfy a LATER cache-hit that is itself WARM_CACHE_PRIME=1
# (see the reuse check above) -- a plain production invocation can never read this marker
# back as a PASS, closing the durable-out-of-band-plant bypass.
if [ "${WARM_CACHE_PRIME:-0}" = "1" ] && [ -n "$WARM_CACHE_KEY" ]; then
  "$HERE/check-parity.sh" "$PROJECT" "$BASE_DB"
  mkdir -p "$WARM_CACHE_DIR" 2>/dev/null && printf '%s\n' "$WARM_MARK_PRIMED" > "${WARM_CACHE_DIR}/${WARM_CACHE_KEY}" 2>/dev/null || true
  echo "[warm] CACHE PRIMED ${WARM_CACHE_KEY:0:12}"; exit 0
fi
[ "${WARM_CLASSIFY_ONLY:-0}" = "1" ] && { echo "[warm] CLASSIFY: validate"; exit 0; }

"$HERE/check-parity.sh" "$PROJECT" "$BASE_DB"

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
  # RED17b-2: also drop the materialized commit snapshot (this replaces the earlier,
  # simpler EXIT trap installed right after materialization above).
  rm -rf "$HARNESS_SNAPSHOT_DIR" 2>/dev/null || true
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
# Stamped "genuine" (this is the one and only site that ran an actual `docker compose run`
# odoo-bin -u load) -- the reuse check above accepts ONLY this provenance unconditionally.
if [ -n "${WARM_CACHE_KEY:-}" ]; then
  mkdir -p "$WARM_CACHE_DIR" 2>/dev/null && printf '%s\n' "$WARM_MARK_GENUINE" > "${WARM_CACHE_DIR}/${WARM_CACHE_KEY}" 2>/dev/null || true
fi
echo "[warm] PASS — $MODCOMMA updates cleanly on warm base (parity-pinned Odoo 19)"
