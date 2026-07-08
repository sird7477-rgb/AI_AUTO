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
# Fail fast with a clear message if the Docker daemon is down (see harness-preflight.sh).
. "$HERE/harness-preflight.sh"
harness_require_docker || exit 4

PROJECT="${1:?usage: validate-odoo.sh <project_repo> [module ...]}"; shift || true

# RED17b-2 fix (sibling of validate-warm.sh/validate-full.sh's fix): mount an
# IMMUTABLE SNAPSHOT of the target commit's custom-addons, never the live
# (mutable) working directory. A bind-mount of $PROJECT/custom-addons tracks
# whatever is on disk at whatever moment the container's odoo-bin -i actually
# reads each file, so a same-UID or merely concurrent (non-adversarial) edit
# to custom-addons/ WHILE this runs makes the container test different bytes
# than the commit under test, silently certifying content that was never the
# validated tree. See validate-warm.sh's harness_materialize_tree for the full
# rationale and .ops-game/R8-red17b-final-convergence.md RED17b-2. Default
# HEAD gives a direct/manual invocation the same immutable-commit ground
# truth; a caller may override HARNESS_VALIDATE_REF to check a specific ref.
# (serve.sh is INTENTIONALLY a live mount for hands-on dev -- left untouched.)
HARNESS_VALIDATE_REF="${HARNESS_VALIDATE_REF:-HEAD}"
HARNESS_SNAPSHOT_DIR="$(mktemp -d "${HARNESS_DIR}/.odoo-harness-snap.XXXXXX")"
# Early cleanup for any exit before `trap cleanup_validate_db EXIT` (below) is
# installed. cleanup_validate_db additionally removes this same directory
# once it is installed, so every exit path stays covered.
trap 'rm -rf "$HARNESS_SNAPSHOT_DIR" 2>/dev/null || true' EXIT
# RED18 fix (.ops-game/R9-red18-verify-toctou-fix.md point 5): `git archive
# <ref>` is NOT filter-immune -- it DOES run the archived tree's OWN
# (committed, attacker-controlled) .gitattributes clean/smudge/textconv/filter
# conversions and has no --attr-source flag to suppress it, unlike this
# file's other worktree `git diff` calls. Since $HARNESS_VALIDATE_REF is
# exactly the untrusted pushed tree, that would be a net-new git-exec RCE.
# Materialize with `git ls-tree` + `git cat-file blob` instead: both are pure
# object-database reads that never consult .gitattributes, never run
# clean/smudge/textconv/filter drivers, and never refresh the index (so no
# fsmonitor-hook exec either). See validate-warm.sh's harness_materialize_tree
# for the full rationale; duplicated here (each script is standalone).
harness_materialize_tree() {  # <project_repo> <ref> <dest_root> ; writes dest_root/custom-addons/**
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
        echo "[validate] NOTE: skipping submodule entry '$path' at $ref (not materialized)" >&2
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
        echo "[validate] NOTE: skipping symlink entry '$path' at $ref (symlinks are not materialized; not a valid addon source file)" >&2
        continue ;;
    esac
    [ "$type" = "blob" ] || { echo "[validate] NOTE: skipping non-blob entry '$path' (type=$type) at $ref" >&2; continue; }
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
        echo "[validate] REJECT: absolute path '$path' at $ref -- aborting materialization" >&2
        return 1 ;;
    esac
    case "$path" in
      ..|../*|*/../*|*/..)
        echo "[validate] REJECT: '..' path component in '$path' at $ref -- aborting materialization" >&2
        return 1 ;;
    esac
    case "$path" in
      custom-addons/*) : ;;
      *)
        echo "[validate] REJECT: entry '$path' at $ref is outside custom-addons/ -- aborting materialization" >&2
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
        echo "[validate] REJECT: resolved path for '$path' escapes the snapshot dir ($parentreal not under $destreal) -- aborting materialization" >&2
        return 1 ;;
    esac
    # RAW stored bytes, zero conversion -- this is the filter-immune read.
    git -C "$proj" cat-file blob "$oid" > "$outpath" || return 1
    [ "$mode" = "100755" ] && chmod +x "$outpath"
    n=$((n+1))
  done < <(git -C "$proj" ls-tree -r -z "$ref" -- custom-addons 2>/dev/null)
  [ "$n" -gt 0 ] || return 1   # no custom-addons/ (or only unmaterializable entries) at that ref -> fail closed
  return 0
}
if ! harness_materialize_tree "$PROJECT" "$HARNESS_VALIDATE_REF" "$HARNESS_SNAPSHOT_DIR"; then
  echo "[validate] cannot materialize '$HARNESS_VALIDATE_REF':custom-addons (bad ref, no custom-addons/ at that commit, or object read error)" >&2
  exit 2
fi
export PROJECT_ADDONS="$HARNESS_SNAPSHOT_DIR/custom-addons"
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
  # -c core.fsmonitor= kills the SEPARATE in-repo `.git/config` fsmonitor HOOK-PROGRAM exec vector
  # (--attr-source does NOT reach it) that fires as the worktree diff refreshes the index; this
  # standalone validator pins both inline (it does not source hooks/git-scrub.sh).
  # The up...HEAD diff is tree-vs-tree (no worktree blob) and needs neither.
  _attr_none="$(git -C "$PROJECT" hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"
  MODCOMMA="$({ git -C "$PROJECT" --attr-source="$_attr_none" -c core.fsmonitor= diff --name-only HEAD 2>/dev/null;
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
  # RED17b-2: also drop the materialized commit snapshot (this replaces the
  # earlier, simpler EXIT trap installed right after materialization above).
  rm -rf "$HARNESS_SNAPSHOT_DIR" 2>/dev/null || true
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
