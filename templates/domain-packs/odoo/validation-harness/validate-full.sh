#!/usr/bin/env bash
# U-A2 validate-full: the on-demand / pre-PR pass that runs scoped post-install TESTS
# and a DEMO-data pass locally, closing the T4 (post-install tests) + test-T1 + T5
# (demo data) classes the fast push-tier registry-load gate (validate-warm) does not
# catch. Slow (minutes) — run before push/PR, NOT on every push.
#
# Usage: validate-full.sh <project_repo> [module ...]   (no module -> git diff HEAD)
# Scope = changed (or given) custom modules + their reverse-dependents, so a change
# that breaks a dependent's test is caught. Registry coverage stays full-set (the base
# has the full module set installed) so cross-module T6 collisions still surface; the
# reverse-dep scope is for TEST/DEMO selection only.
#
# Env:
#   ODOO_BASE_DB=base             warm no-demo base for the test pass
#   ODOO_DEMO_BASE_DB=base_demo   demo base for the demo pass (ODOO_WITH_DEMO=1 build)
#   ODOO_DEMO_PASS_MODE=update    update (default): -u $SCOPE on a FULL-SET base_demo
#                                 clone — validates the module update against a
#                                 demo-populated registry. Fast and registry-complete.
#   SKIP_TEST_PASS=1 / SKIP_DEMO_PASS=1   opt out of a sub-pass
#   ODOO_DEMO_REBUILD=1           when a demo/ file changed, rebuild base_demo to actually
#                                 validate the changed demo data (full reload). Without
#                                 it a demo/ change fails closed (demo DATA unvalidated).
#
# Demo coverage note (measured U-A0/U-A2): `-u` does NOT reload demo/ files, and a
# fresh `-i $SCOPE` on an empty DB FALSE-FAILS on incomplete module graphs (a field
# whose comodel lives in an unrelated module, e.g. enterprise `documents`). So the demo
# pass runs `-u` on the full base_demo to catch demo-data-present errors; to validate a
# CHANGED demo/ file's data, rebuild base_demo (ODOO_WITH_DEMO=1 prepare-base-db.sh),
# which reloads all demo on the full set.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="$(cd "$HERE/.." && pwd)"
export ODOO_COMMUNITY="${ODOO_COMMUNITY:-$DATA/01. Odoo.19(커뮤니티)}"
export ODOO_ENTERPRISE="${ODOO_ENTERPRISE:-$DATA/02. Odoo.19(enterprise)}"
export HARNESS_DIR="$HERE"
# Fail fast with a clear message if the Docker daemon is down (see harness-preflight.sh).
. "$HERE/harness-preflight.sh"
harness_require_docker || exit 4
PROJECT="${1:?usage: validate-full.sh <project_repo> [module ...]}"; shift || true

# RED17b-2 fix: mount an IMMUTABLE SNAPSHOT of the target commit's custom-addons,
# never the live (mutable) working directory -- same fix and rationale as
# validate-warm.sh (see that file's comment block and
# .ops-game/R8-red17b-final-convergence.md RED17b-2). Default HEAD; an on-demand
# pre-PR run can override HARNESS_VALIDATE_REF to check a specific commit.
# (serve.sh is INTENTIONALLY a live mount for hands-on dev -- left untouched.)
HARNESS_VALIDATE_REF="${HARNESS_VALIDATE_REF:-HEAD}"
HARNESS_SNAPSHOT_DIR="$(mktemp -d "${HARNESS_DIR}/.odoo-harness-snap.XXXXXX")"
trap 'rm -rf "$HARNESS_SNAPSHOT_DIR" 2>/dev/null || true' EXIT
# RED18 fix (.ops-game/R9-red18-verify-toctou-fix.md point 5): `git archive`
# is NOT filter-immune -- it runs the archived tree's OWN (attacker-controlled)
# .gitattributes clean/smudge/textconv/filter conversions and has no
# --attr-source escape hatch, unlike this file's other worktree `git diff`
# calls. Since $HARNESS_VALIDATE_REF is the untrusted pushed tree, that is a
# net-new git-exec RCE. Materialize via `git ls-tree` + `git cat-file blob`
# instead -- pure object-database reads, no .gitattributes/filter/fsmonitor
# machinery ever fires for either. See validate-warm.sh's harness_materialize_tree
# for the full rationale; duplicated here (each script is standalone).
harness_materialize_tree() {  # <project_repo> <ref> <dest_root> ; writes dest_root/custom-addons/**
  local proj="$1" ref="$2" dest="$3" n=0 line meta path mode type oid outpath parentdir destreal parentreal
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
        echo "[full] NOTE: skipping submodule entry '$path' at $ref (not materialized)" >&2
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
        echo "[full] NOTE: skipping symlink entry '$path' at $ref (symlinks are not materialized; not a valid addon source file)" >&2
        continue ;;
    esac
    [ "$type" = "blob" ] || { echo "[full] NOTE: skipping non-blob entry '$path' (type=$type) at $ref" >&2; continue; }
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
        echo "[full] REJECT: absolute path '$path' at $ref -- aborting materialization" >&2
        return 1 ;;
    esac
    case "$path" in
      ..|../*|*/../*|*/..)
        echo "[full] REJECT: '..' path component in '$path' at $ref -- aborting materialization" >&2
        return 1 ;;
    esac
    case "$path" in
      custom-addons/*) : ;;
      *)
        echo "[full] REJECT: entry '$path' at $ref is outside custom-addons/ -- aborting materialization" >&2
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
        echo "[full] REJECT: resolved path for '$path' escapes the snapshot dir ($parentreal not under $destreal) -- aborting materialization" >&2
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
  echo "[full] cannot materialize '$HARNESS_VALIDATE_REF':custom-addons (bad ref, no custom-addons/ at that commit, or object read error)" >&2
  exit 2
fi
export PROJECT_ADDONS="$HARNESS_SNAPSHOT_DIR/custom-addons"
[ -d "$PROJECT_ADDONS" ] || { echo "[full] no custom-addons at $PROJECT_ADDONS" >&2; exit 2; }
BASE_DB="${ODOO_BASE_DB:-base}"
DEMO_BASE_DB="${ODOO_DEMO_BASE_DB:-base_demo}"
DEMO_MODE="${ODOO_DEMO_PASS_MODE:-update}"   # update = -u on full-set base_demo (registry-complete); fresh empty-DB -i false-fails on partial graphs (U-A2)
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

# U-A3 sub-routing: with explicit modules we cannot classify file types, so run both
# passes. In git-diff mode, run the test pass only when code/test/data files changed and
# the demo pass only when a demo/ file changed — keeps the common view-only change cheap.
WANT_TEST=1; WANT_DEMO=1
# DEMO_FILES_CHANGED: "1" when a demo/ file changed (git-diff mode), "unknown" with
# explicit modules. Used to flag that the `-u` demo pass does NOT reload changed demo
# records (U-A0), so it must not claim those records were validated.
DEMO_FILES_CHANGED=unknown
if [ "$#" -gt 0 ]; then
  CHANGED="$(printf '%s\n' "$@")"
else
  # Upstream-aware: union of uncommitted (diff HEAD) AND committed-but-not-yet-pushed
  # (@{u}...HEAD) changes, so an on-demand pre-PR run after a clean commit does not
  # silently "skip" the very commits being pushed (the gap the README warns about).
  # --attr-source=<empty-tree>: the worktree `--name-only` diff over the (untrusted) project runs
  # the in-repo clean filter to detect changes, so it is an RCE vector; ignore .gitattributes here.
  # -c core.fsmonitor= kills the SEPARATE in-repo `.git/config` fsmonitor HOOK-PROGRAM exec vector
  # (config, not attribute — --attr-source does NOT reach it) that fires as the worktree diff
  # refreshes the index. This standalone validator does not source hooks/git-scrub.sh, so it pins
  # both defenses inline. (The @{u}...HEAD diff below is tree-vs-tree — no worktree scan — so needs neither.)
  _attr_none="$(git -C "$PROJECT" hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"
  RANGE_FILES="$(git -C "$PROJECT" --attr-source="$_attr_none" -c core.fsmonitor= diff --name-only HEAD 2>/dev/null)"
  if git -C "$PROJECT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    RANGE_FILES="$RANGE_FILES
$(git -C "$PROJECT" diff --name-only '@{u}...HEAD' 2>/dev/null)"
  fi
  FILES="$(printf '%s\n' "$RANGE_FILES" | sed -n 's#^custom-addons/.*#&#p' | sort -u)"
  CHANGED="$(printf '%s\n' "$FILES" | sed -n 's#^custom-addons/\([^/]*\)/.*#\1#p' | sort -u)"
  if printf '%s\n' "$FILES" | grep -qE '/demo/|/demo\.xml$'; then WANT_DEMO=1; DEMO_FILES_CHANGED=1; else WANT_DEMO=0; DEMO_FILES_CHANGED=0; fi
  # View-only changes are registry-validated by the push-tier warm gate; the test pass
  # triggers on code/test/data only (views excluded) so a view-only change stays warm.
  printf '%s\n' "$FILES" | grep -qE '\.(py|csv)$|/(models|tests|data|security|wizard)/' && WANT_TEST=1 || WANT_TEST=0
  [ "$WANT_DEMO" = "1" ] && WANT_TEST=1   # a demo change still re-validates module load
fi
[ -n "$CHANGED" ] || { echo "[full] no changed custom modules; skip"; exit 0; }

# Reverse-dependency closure over custom modules only (a dependent's test must catch a
# break in a module it depends on).
SCOPE="$(CHANGED_IN="$CHANGED" python3 - "$PROJECT_ADDONS" <<'PY'
import ast,glob,os
root=os.sys.argv[1]
changed=set(os.environ.get("CHANGED_IN","").split())
deps={}
for m in glob.glob(os.path.join(root,"*","__manifest__.py")):
    name=os.path.basename(os.path.dirname(m))
    try:
        d=ast.literal_eval(open(m,encoding="utf-8").read())
        deps[name]=set(d.get("depends",[]) or [])
    except Exception:
        deps[name]=set()
custom=set(deps)
rev={}
for n,ds in deps.items():
    for dep in ds:
        if dep in custom:
            rev.setdefault(dep,set()).add(n)
closure=set(c for c in changed if c in custom)
stack=list(closure)
while stack:
    n=stack.pop()
    for r in rev.get(n,()):
        if r not in closure:
            closure.add(r); stack.append(r)
print(",".join(sorted(closure)))
PY
)"
[ -n "$SCOPE" ] || { echo "[full] changed modules not in custom-addons; skip" >&2; exit 0; }
echo "[full] changed: $(echo $CHANGED | tr '\n' ' ') -> scope (with reverse-deps): $SCOPE  [test=$WANT_TEST demo=$WANT_DEMO]"

# Cap reverse-dep explosion: a change to a widely-depended-on base module pulls a large
# closure; warn so this stays an on-demand pass and is not wired onto a fast push tier.
SCOPE_N=$(printf '%s' "$SCOPE" | tr ',' '\n' | grep -c .)
if [ "$SCOPE_N" -gt "${MAX_FULL_SCOPE:-12}" ]; then
  echo "[full] WARNING wide blast radius: $SCOPE_N modules in scope (> ${MAX_FULL_SCOPE:-12}). Keep validate-full on-demand/pre-PR, not on the push hot path."
fi

# T4 / test-T1 / T5 failure signatures (rc may be 0 in edge configs -> log-grep backstop).
FAIL_RE="ParseError|cannot be located|does not exist|Invalid field|Element .* cannot|Failed to load registry|violates not-null|FAIL|ERROR.*test|[0-9]+ failed|ValidationError|Quants cannot be created|should be set"

dc up -d db >/dev/null
dc exec -T db sh -c 'until pg_isready -U odoo -q; do sleep 1; done'

ensure_base() {  # <db> <hint>
  dc exec -T db psql -U odoo -lqt | cut -d'|' -f1 | tr -d ' ' | grep -qx "$1" \
    || { echo "[full] base DB '$1' missing — run prepare-base-db.sh${2:+ ($2)} first" >&2; return 3; }
}

run_pass() {  # <label> <source_db> <clone> <odoo args as one string>
  local label="$1" src="$2" clone="$3" args="$4" log rc
  dc exec -T db createdb -U odoo -T "$src" "$clone"
  log="$(mktemp)"
  set +e
  dc run --rm -e VDB="$clone" -e OARGS="$args" odoo bash -c '
set -e
python3 /mnt/community/odoo-bin -d "$VDB" \
  --addons-path=/mnt/community/addons,/mnt/enterprise,/mnt/extra-addons \
  --db_host=db --db_user=odoo --db_password=odoo --log-level=warn \
  $OARGS --stop-after-init
' 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  set -e
  dc exec -T db dropdb -U odoo --if-exists "$clone" >/dev/null 2>&1 || true
  if [ "$rc" -ne 0 ] || grep -qiE "$FAIL_RE" "$log"; then
    echo "[full] $label FAIL (rc=$rc)"; rm -f "$log"; return 1
  fi
  rm -f "$log"; echo "[full] $label PASS"; return 0
}

overall=0

if [ "${SKIP_TEST_PASS:-0}" != "1" ] && [ "$WANT_TEST" = "1" ]; then
  ensure_base "$BASE_DB" || exit 3
  TAGS="/$(echo "$SCOPE" | sed 's/,/,\//g')"   # mod1,mod2 -> /mod1,/mod2 (only these modules' tests)
  run_pass "test-pass" "$BASE_DB" "valt_$$_$(date +%s%N)" \
    "-u $SCOPE --test-enable --test-tags=$TAGS" || overall=1
fi

if [ "${SKIP_DEMO_PASS:-0}" != "1" ] && [ "$WANT_DEMO" = "1" ]; then
  ensure_base "$DEMO_BASE_DB" "ODOO_WITH_DEMO=1" || exit 3
  if [ "$DEMO_MODE" = "fresh" ]; then
    # A true fresh demo load needs the FULL module set (a partial -i false-fails on
    # cross-module field comodels), so it is a base_demo rebuild, not a per-run pass.
    echo "[full] demo-pass(fresh) requested: rebuild base_demo to reload all demo on the"
    echo "[full]   full set -> ODOO_WITH_DEMO=1 ./prepare-base-db.sh \"$PROJECT\""
    echo "[full]   (then re-run with the default update mode). Skipping fresh here."
  fi
  if [ "$DEMO_FILES_CHANGED" != "0" ] && [ "${ODOO_DEMO_REBUILD:-0}" = "1" ]; then
    # demo/ changed and rebuild opted in: a base_demo rebuild reloads ALL demo on the
    # full set, which is the only thing that actually validates the changed demo data
    # (U-A0: -u does not reload demo). Its success IS the demo-data validation.
    echo "[full] demo/ changed -> rebuilding base_demo to validate changed demo data (full reload)..."
    harness_unlock   # release our READ lock so the child prepare-base can take the WRITE lock (no self-deadlock)
    # Fix (same class as RED17b-2/18/18b): pass the ALREADY-MATERIALIZED, immutable
    # snapshot's custom-addons ($PROJECT_ADDONS, set above from $HARNESS_SNAPSHOT_DIR)
    # via PREPARE_BASE_ADDONS_DIR, NOT the raw/live $PROJECT path -- prepare-base-db.sh
    # would otherwise unconditionally re-derive "$PROJECT/custom-addons" and rebuild the
    # base from the live, mutable working dir instead of the reviewed $HARNESS_VALIDATE_REF,
    # silently reintroducing the "validate the live dir, not the reviewed ref" TOCTOU class.
    if ODOO_WITH_DEMO=1 PREPARE_BASE_ADDONS_DIR="$PROJECT_ADDONS" ./prepare-base-db.sh "$PROJECT"; then
      echo "[full] demo-pass(rebuild) PASS — changed demo data loads cleanly on the full set"
    else
      echo "[full] demo-pass(rebuild) FAIL — changed demo data did not load"; overall=1
    fi
  else
    # update: -u scope on the full-set demo base — registry-complete, validates the
    # module update against demo-populated tables.
    run_pass "demo-pass(update)" "$DEMO_BASE_DB" "vald_$$_$(date +%s%N)" "-u $SCOPE" || overall=1
    # U-A0: -u does NOT reload changed demo/ records. When a demo/ file changed, this
    # pass validated module load with demo PRESENT but NOT the changed demo data — so we
    # fail closed (incomplete field evidence must not read as a clean pass).
    if [ "$DEMO_FILES_CHANGED" != "0" ]; then
      DEMO_DATA_UNVALIDATED=1
    fi
  fi
fi

if [ "$overall" -ne 0 ]; then
  echo "[full] FAIL — see the failing pass above; NOT clean on odoo.sh as-is"
  exit 1
elif [ "${DEMO_DATA_UNVALIDATED:-0}" = "1" ]; then
  echo "[full] FAIL (incomplete) — code/registry + demo-present load clean, but changed demo"
  echo "[full]   DATA was NOT validated (-u does not reload demo). Re-run with ODOO_DEMO_REBUILD=1"
  echo "[full]   to rebuild base_demo and validate the changed demo records."
  exit 1
else
  # RED2-7: the closing message must reflect what actually ran, not what the script is
  # capable of running. A views-only change (WANT_TEST=0/WANT_DEMO=0) or an explicit
  # SKIP_*_PASS never executes a sub-pass at all -- say so instead of unconditionally
  # claiming "tests + demo load clean".
  test_part="tests SKIPPED (no code/test/data change in scope)"
  if [ "${SKIP_TEST_PASS:-0}" = "1" ]; then
    test_part="tests SKIPPED (SKIP_TEST_PASS=1)"
  elif [ "$WANT_TEST" = "1" ]; then
    test_part="tests PASS"
  fi
  demo_part="demo SKIPPED (no demo/ change in scope)"
  if [ "${SKIP_DEMO_PASS:-0}" = "1" ]; then
    demo_part="demo SKIPPED (SKIP_DEMO_PASS=1)"
  elif [ "$WANT_DEMO" = "1" ]; then
    demo_part="demo PASS"
  fi
  echo "[full] PASS — ${test_part}; ${demo_part} (parity-pinned Odoo 19)"
fi
exit 0
