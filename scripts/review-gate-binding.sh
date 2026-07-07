#!/usr/bin/env bash

# Shared review-gate binding helper. Source from review-gate/pre-push; do not execute directly.

review_binding_dir() {
  printf '%s\n' "${REVIEW_STATE_DIR:-.omx/reviewer-state}"
}

review_binding_env() {
  printf '%s/binding-verdict.env\n' "$(review_binding_dir)"
}

review_binding_log() {
  printf '%s/binding-verdict.log\n' "$(review_binding_dir)"
}

review_binding_key_file() {
  if command -v review_provenance_key_file >/dev/null 2>&1; then
    review_provenance_key_file
  elif [ -n "${AI_AUTO_PROVENANCE_KEY_FILE:-}" ]; then
    printf '%s\n' "${AI_AUTO_PROVENANCE_KEY_FILE}"
  elif [ -n "${AI_AUTO_HOME:-}" ]; then
    local candidate home_key top rp
    candidate="${AI_AUTO_HOME}/.provenance-key"
    home_key="${HOME:-/root}/.config/ai-auto/provenance.key"
    if top="$(git rev-parse --show-toplevel 2>/dev/null)" \
      && rp="$(realpath -m -- "${candidate}" 2>/dev/null)" \
      && top="$(realpath -m -- "${top}" 2>/dev/null)"; then
      # Refuse attacker-readable keys that resolve inside the reviewed worktree.
      case "${rp}/" in
        "${top}/"*) ;;
        *) printf '%s\n' "${candidate}"; return ;;
      esac
    else
      printf '%s\n' "${home_key}"
      return
    fi
    printf '%s\n' "${home_key}"
  else
    printf '%s/.config/ai-auto/provenance.key\n' "${HOME:-/root}"
  fi
}

review_binding_abs_path() {
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m -- "${path}" 2>/dev/null && return 0
  fi
  AI_AUTO_ABS_PATH="${path}" python3 - <<'PY' 2>/dev/null
import os
print(os.path.realpath(os.environ["AI_AUTO_ABS_PATH"]))
PY
}

review_binding_key_in_tree() {
  local keyfile top rp
  keyfile="$(review_binding_key_file)"
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "${top}" ] || return 1
  top="$(review_binding_abs_path "${top}")" || return 0
  rp="$(review_binding_abs_path "${keyfile}")" || return 0
  case "${rp}/" in "${top}/"*) return 0 ;; esac
  return 1
}

review_binding_ensure_key() {
  if command -v review_provenance_ensure_key >/dev/null 2>&1; then
    review_provenance_ensure_key
    return
  fi
  local keyfile dir tmp
  review_binding_key_in_tree && return 1
  keyfile="$(review_binding_key_file)"
  [ -s "${keyfile}" ] && return 0
  dir="$(dirname "${keyfile}")"
  mkdir -p "${dir}" 2>/dev/null || return 1
  tmp="$(mktemp "${dir}/.provkey.XXXXXX" 2>/dev/null)" || return 1
  if ( umask 077; openssl rand -hex 32 > "${tmp}" ) 2>/dev/null && [ -s "${tmp}" ]; then
    chmod 0600 "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${keyfile}" 2>/dev/null && return 0
  fi
  rm -f "${tmp}" 2>/dev/null
  return 1
}

review_binding_hmac() {
  if command -v review_provenance_hmac >/dev/null 2>&1; then
    review_provenance_hmac
    return
  fi
  local keyfile mode
  keyfile="$(review_binding_key_file)"
  review_binding_key_in_tree && return 0
  [ -s "${keyfile}" ] || return 0
  [ -O "${keyfile}" ] || return 0
  mode="$(stat -c '%a' "${keyfile}" 2>/dev/null || echo 777)"
  [ $(( 0${mode} & 077 )) -eq 0 ] || return 0
  AI_AUTO_PROV_KEYFILE="${keyfile}" python3 -c 'import hmac,hashlib,os,sys; k=open(os.environ["AI_AUTO_PROV_KEYFILE"],"rb").read(); sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())' 2>/dev/null
}

review_binding_git() {
  if command -v review_git >/dev/null 2>&1; then
    review_git "$@"
  else
    git "$@"
  fi
}

review_binding_dirty() {
  local rc
  review_binding_git diff --quiet --exit-code --no-ext-diff --no-textconv >/dev/null 2>&1 || rc=$?
  case "${rc:-0}" in 1) return 0 ;; 0) ;; *) return 2 ;; esac
  rc=0
  review_binding_git diff --cached --quiet --exit-code --no-ext-diff --no-textconv >/dev/null 2>&1 || rc=$?
  case "${rc}" in 1) return 0 ;; 0) ;; *) return 2 ;; esac
  [ -z "$(review_binding_git ls-files --others --exclude-standard 2>/dev/null || printf x)" ] || return 0
  return 1
}

review_binding_change_payload() {
  local dirty_status
  dirty_status=0
  review_binding_dirty || dirty_status=$?
  if [ "${dirty_status}" -eq 0 ]; then
    review_binding_prospective_commit_payload
  elif [ "${dirty_status}" -eq 1 ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
    review_binding_committed_payload
  elif [ "${dirty_status}" -eq 1 ]; then
    printf '\037empty\037\n'
  else
    return 1
  fi
}

review_binding_head_parent_count() {
  git rev-list --parents -n 1 "${1:-HEAD}" 2>/dev/null | awk '{ print NF - 1 }'
}

review_binding_empty_tree() {
  review_binding_git hash-object -t tree /dev/null 2>/dev/null
}

# RED7-1 fix: neither of the two prior "base" sources ever fires on the ordinary case of a
# brand-new local branch before its first push -- hooks/pre-push has no <remote sha> to diff
# against (a genuinely new remote ref reports the all-zero sha on stdin) and `@{u}` is unset
# (no upstream configured yet), so review_binding_committed_payload fell all the way back to
# "just the tip commit", making any earlier unreviewed commit (e.g. one adding
# GRANT_ADMIN=true) invisible to both the reviewer and the push-time hash even though it
# rides out on the very next `git push`. Never let the range silently collapse to tip-only;
# always resolve an explicit, safe, OVER-approximated base instead.
#
# RED11-1 fix (CRITICAL, .ops-game/R5-red11-reattack.md): this function used to resolve the
# octopus merge-base of $1 against EVERY ref under refs/remotes/* (a glob, via the now-removed
# review_binding_remote_tracking_refs). refs/remotes/* is populated by `git fetch`, but each
# ref under it is still just an ordinary LOCAL ref -- any same-UID actor (the exact actor this
# binding mechanism exists to defend against) can create one directly with `git update-ref
# refs/remotes/origin/decoy <sha>`, no network or push required. Planting a decoy ref that is
# a DESCENDANT of the commit being pushed collapses merge-base(target, decoy) back to target
# itself, so base==target, the range-diff section becomes an empty no-op, and the payload
# silently collapses to tip-only again -- reproducing the exact RED7-1 defect this function
# exists to close, via ref fabrication instead of "no upstream". PoC'd end-to-end in
# R5-red11-reattack.md (RED11-1). Never trust a glob over refs/remotes/* again.
#
# The only AUTHENTIC base for a push is the pre-push stdin remote_sha (what the remote
# actually reports its current tip to be, from the real push negotiation) -- hooks/pre-push
# already uses that directly and never reaches this function when it is non-zero. This
# function is only reached when there is NO authentic base to work from (a genuinely new
# remote ref, or an ambient/standalone caller with no stdin at all). Fallback order:
#   1. the CURRENT branch's own specific `@{u}` upstream, IF it resolves -- a single,
#      specifically-configured ref (not a glob over every ref this repo has ever heard of),
#      best-effort. NOTE (documented residual, not a closed hole): the ref `@{u}` points at is
#      itself an ordinary local ref and exactly as same-UID-forgeable as refs/remotes/* was
#      (`git branch --set-upstream-to`/a raw `update-ref` can point it at a decoy just as
#      easily) -- narrowing the glob to one specifically-configured ref shrinks the attack
#      surface (a decoy must now match the ref the developer actually configured, rather than
#      merely being new) but does not eliminate same-UID ref forgery. The out-of-band durable
#      verdict log + external auditor (RED8/R5) is the accepted backstop against a same-UID
#      attacker forging ANY local ref, including this one -- this function's job is only to
#      never UNDER-approximate the range, not to authenticate refs it does not control.
#   2. else the empty tree -- the ultimate over-approximation: a full diff of $1's entire
#      reachable content, never narrower than "just the tip".
review_binding_safe_base_fallback() {
  local target="${1:-HEAD}" upstream base
  upstream="$(review_binding_git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [ -n "${upstream}" ]; then
    base="$(review_binding_git merge-base "${target}" "${upstream}" 2>/dev/null || true)"
    if [ -n "${base}" ]; then
      printf '%s\n' "${base}"
      return 0
    fi
  fi
  review_binding_empty_tree
}

# RED3-1 fix: the tip-commit diff alone is invisible to earlier commits that are already
# made but not yet pushed -- e.g. an unreviewed commit A ("add GRANT_ADMIN=true") followed by
# a reviewed trivial commit B rides through unseen, because `git show HEAD` / `HEAD^1..HEAD`
# only ever covers B. Union in the full range since the upstream/base ref so the payload (and
# therefore the hash) covers EVERY unpushed commit, mirroring the validation harness's own
# `@{u}...HEAD` fix for the identical "commits since upstream" scope gap
# (templates/domain-packs/odoo/validation-harness/validate-warm.sh / validate-full.sh --
# `up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}')"`, unioned with the tip
# diff). $1=target commit-ish (default HEAD), $2=explicit base commit-ish (default: resolve
# target's own @{u} tracking ref, only meaningful when target=HEAD -- an explicit base is
# required for any other target, e.g. a pushed sha that is not the ambient checked-out
# branch; see review_binding_check_ref / hooks/pre-push).
#
# RED7-1 fix: when NEITHER an explicit $2 NOR (for target=HEAD) `@{u}` resolves, do not fall
# through to tip-only -- resolve review_binding_safe_base_fallback instead, for ANY target
# (not just HEAD), since hooks/pre-push calls this with an explicit pushed sha as $1 that is
# never literally the string "HEAD". A fallback-resolved base may be the empty tree (a tree
# object, not a commit), which `...` (triple-dot, merge-base-based) diff syntax cannot
# resolve against -- use a direct two-dot diff whenever the base is the empty tree.
review_binding_committed_payload() {
  local target="${1:-HEAD}" base="${2:-}"
  printf '\037commit-diff\037\n'
  if [ "$(review_binding_head_parent_count "${target}")" -gt 1 ]; then
    review_binding_git diff --no-ext-diff --no-textconv "${target}^1" "${target}" 2>/dev/null
  else
    review_binding_git show --format= --no-ext-diff --no-textconv "${target}" 2>/dev/null
  fi
  if [ -z "${base}" ] && [ "${target}" = "HEAD" ]; then
    base="$(review_binding_git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  fi
  if [ -z "${base}" ]; then
    base="$(review_binding_safe_base_fallback "${target}")"
  fi
  if [ -n "${base}" ]; then
    printf '\037range-diff\037\n'
    if [ "${base}" = "$(review_binding_empty_tree)" ]; then
      review_binding_git diff --no-ext-diff --no-textconv "${base}" "${target}" 2>/dev/null
    else
      review_binding_git diff --no-ext-diff --no-textconv "${base}...${target}" 2>/dev/null
    fi
  fi
}

review_binding_prospective_commit_payload() {
  local tmp_dir tmp_index real_index
  tmp_dir="$(mktemp -d)" || return 1
  tmp_index="${tmp_dir}/index"
  real_index="$(git rev-parse --git-path index 2>/dev/null)" || { rm -rf "${tmp_dir}"; return 1; }
  if [ -f "${real_index}" ]; then
    cp "${real_index}" "${tmp_index}" || { rm -rf "${tmp_dir}"; return 1; }
  fi
  if ! GIT_INDEX_FILE="${tmp_index}" review_binding_git add -A -- . >/dev/null 2>&1; then
    rm -rf "${tmp_dir}"
    return 1
  fi
  printf '\037commit-diff\037\n'
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    GIT_INDEX_FILE="${tmp_index}" review_binding_git diff --cached --no-ext-diff --no-textconv HEAD 2>/dev/null
  else
    GIT_INDEX_FILE="${tmp_index}" review_binding_git diff --cached --no-ext-diff --no-textconv --root 2>/dev/null
  fi
  local rc=$?
  rm -rf "${tmp_dir}"
  return "${rc}"
}

review_binding_hash() {
  # RED1-1 fix: an explicit $1 (target commit-ish) bypasses the ambient dirty/HEAD path
  # entirely -- a pre-push-supplied local sha being pushed is always a real commit object,
  # never "the pusher's uncommitted working tree", so it always goes straight to
  # review_binding_committed_payload for THAT sha rather than review_binding_change_payload's
  # ambient-HEAD-derived dirty check. See review_binding_check_ref / hooks/pre-push.
  if [ -n "${1:-}" ]; then
    review_binding_committed_payload "$1" "${2:-}" | git hash-object --stdin
  else
    review_binding_change_payload | git hash-object --stdin
  fi
}

review_binding_record() {
  local decision="$1" trust="$2" verdict_file="${3:-}" pinned_target="${4:-}" hash ts tmp rec dst current_head
  case "${decision}" in proceed|proceed_degraded) ;; *) return 0 ;; esac
  # RED14-1 fix (CRITICAL, .ops-game/R6-red14-convergence.md): review_binding_hash with no
  # target recomputes the hash from AMBIENT HEAD at THIS call -- for review-gate.sh's full-
  # review call site that is AFTER the multi-minute AI-panel round-trip, with no git-level
  # lock preventing an ordinary `git commit --amend`/new commit in a second terminal from
  # moving HEAD in between. Callers that captured the sha actually reviewed BEFORE that
  # window (review-gate.sh's review_reviewed_head_sha, mirroring the machinery_tested_hash
  # H1 pattern a few hundred lines below in review-gate.sh) pass it here as $4. When present,
  # require ambient HEAD to still equal it: a match means nothing moved during the window, so
  # it is safe to hash that exact target (bypassing review_binding_hash's ambient dirty/HEAD
  # re-read entirely -- same "explicit target" routing RED1-1 already relies on for pre-push's
  # pushed-sha call shape). A MISMATCH means HEAD drifted mid-review -- refuse to bind at all
  # (no marker written, non-zero return) rather than silently re-deriving the hash from a HEAD
  # the reviewer never saw; the caller must treat this as a failed/blocked gate run, not a
  # quiet no-op, so an approval can never attach to unreviewed content.
  if [ -n "${pinned_target}" ]; then
    current_head="$(review_binding_git rev-parse HEAD 2>/dev/null || true)"
    if [ -z "${current_head}" ] || [ "${current_head}" != "${pinned_target}" ]; then
      echo "[review-binding] HEAD drifted during the review window (reviewed ${pinned_target}, now ${current_head:-<none>}) -- refusing to bind an approval to unreviewed content; rerun the gate." >&2
      return 1
    fi
    hash="$(review_binding_hash "${pinned_target}")" || return 0
  else
    hash="$(review_binding_hash)" || return 0
  fi
  ts="$(date -Iseconds)"
  review_binding_ensure_key || return 0
  mkdir -p "$(review_binding_dir)"
  dst="$(review_binding_env)"
  tmp="$(mktemp "$(review_binding_dir)/.binding-verdict.XXXXXX")" || return 0
  rec="$(printf 'marker_type=review_gate_binding\nbinding_hash=%s\nbinding_decision=%s\nbinding_trust=%s\nbinding_verdict=%s\nbinding_at=%s\n' \
    "${hash}" "${decision}" "${trust:-unknown}" "${verdict_file:-unknown}" "${ts}")"
  {
    printf '%s\n' "${rec}"
    printf 'binding_hmac=%s\n' "$(printf '%s' "${rec}" | review_binding_hmac)"
  } > "${tmp}"
  mv -f "${tmp}" "${dst}"
  printf '%s\t%s\t%s\t%s\n' "${ts}" "${decision}" "${hash}" "${verdict_file:-unknown}" >> "$(review_binding_log)"
}

review_binding_field() {
  local key="$1" env_file
  env_file="$(review_binding_env)"
  [ -f "${env_file}" ] || return 0
  sed -n "s/^${key}=//p" "${env_file}" | head -1
}

review_binding_authentic() {
  local stored rec expected
  review_binding_key_in_tree && return 1
  [ -s "$(review_binding_key_file)" ] || return 1
  stored="$(review_binding_field binding_hmac)"
  [ -n "${stored}" ] || return 1
  rec="$(printf 'marker_type=review_gate_binding\nbinding_hash=%s\nbinding_decision=%s\nbinding_trust=%s\nbinding_verdict=%s\nbinding_at=%s\n' \
    "$(review_binding_field binding_hash)" \
    "$(review_binding_field binding_decision)" \
    "$(review_binding_field binding_trust)" \
    "$(review_binding_field binding_verdict)" \
    "$(review_binding_field binding_at)")"
  expected="$(printf '%s' "${rec}" | review_binding_hmac)"
  [ -n "${expected}" ] && [ "${expected}" = "${stored}" ]
}

review_binding_latest_verdict() {
  { find .omx/review-results -maxdepth 1 -type f -name 'review-verdict-*.md' -printf '%T@ %p\n' 2>/dev/null || true; } \
    | sort -nr | awk 'NR==1 {print $2}'
}

review_binding_verdict_decision() {
  local file="$1"
  [ -n "${file}" ] && [ -f "${file}" ] || return 0
  sed -n 's/^- decision: //p' "${file}" | head -1
}

# RED1-1 fix: the actual check, parameterized by the commit-ish ACTUALLY being pushed ($1)
# and its base ($2, typically the remote's current sha for that ref before the push). With
# no arguments this reduces to the original ambient-HEAD behavior (review_binding_check
# below), preserved for review-gate.sh's own interactive/dry-run callers. hooks/pre-push
# calls this once per stdin ref-update line with the real pushed local sha and remote sha,
# so a push whose local ref differs from the pusher's checked-out HEAD (e.g. `git push
# origin evilbranch:main` while sitting on main) is bound to evilbranch's own content, not
# main's -- closing the "binding checks ambient HEAD, never the pushed ref/sha" gap.
review_binding_check_ref() {
  local target="${1:-}" base="${2:-}" latest latest_decision current recorded decision
  latest="$(review_binding_latest_verdict)"
  latest_decision="$(review_binding_verdict_decision "${latest}")"
  case "${latest_decision}" in
    blocked|revise|review_manually)
      echo "review-gate latest verdict is ${latest_decision}; push is blocked" >&2
      return 1
      ;;
  esac
  if ! review_binding_authentic; then
    echo "no binding gate verdict for this change" >&2
    return 1
  fi
  decision="$(review_binding_field binding_decision)"
  case "${decision}" in proceed|proceed_degraded) ;; *)
    echo "no binding gate verdict for this change" >&2
    return 1
    ;;
  esac
  if [ -n "${target}" ]; then
    current="$(review_binding_hash "${target}" "${base}")" || {
      echo "no binding gate verdict for this change" >&2
      return 1
    }
  else
    current="$(review_binding_hash)" || {
      echo "no binding gate verdict for this change" >&2
      return 1
    }
  fi
  recorded="$(review_binding_field binding_hash)"
  if [ -z "${recorded}" ] || [ "${current}" != "${recorded}" ]; then
    echo "no binding gate verdict for this change" >&2
    return 1
  fi
  return 0
}

review_binding_check() {
  review_binding_check_ref
}
