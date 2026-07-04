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
    printf '%s/.provenance-key\n' "${AI_AUTO_HOME}"
  else
    printf '%s/.config/ai-auto/provenance.key\n' "${HOME:-/root}"
  fi
}

review_binding_key_in_tree() {
  local keyfile top rp
  keyfile="$(review_binding_key_file)"
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "${top}" ] || return 1
  top="$(realpath -m -- "${top}" 2>/dev/null)" || return 1
  rp="$(realpath -m -- "${keyfile}" 2>/dev/null)" || return 1
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
    printf '\037dirty\037\n'
    printf '\037diff\037\n'; review_binding_git diff --no-ext-diff --no-textconv 2>/dev/null || return 1
    printf '\037cached\037\n'; review_binding_git diff --cached --no-ext-diff --no-textconv 2>/dev/null || return 1
    printf '\037untracked\037\n'
    review_binding_git ls-files --others --exclude-standard -z 2>/dev/null \
      | while IFS= read -r -d '' file; do
          printf '%s\t' "${file}"
          if [ -d "${file}" ] || ! blob="$(git hash-object --no-filters "${file}" 2>/dev/null)" || [ -z "${blob}" ]; then
            printf '\037UNHASHABLE\037%s.%s\n' "${RANDOM}${RANDOM}" "$(date +%s%N 2>/dev/null || printf '%s' "${RANDOM}")"
          else
            printf '%s\n' "${blob}"
          fi
        done
  elif [ "${dirty_status}" -eq 1 ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
    printf '\037latest-commit\037\n'
    git show --format= --no-ext-diff --no-textconv HEAD 2>/dev/null || return 1
  elif [ "${dirty_status}" -eq 1 ]; then
    printf '\037empty\037\n'
  else
    return 1
  fi
}

review_binding_hash() {
  review_binding_change_payload | git hash-object --stdin
}

review_binding_record() {
  local decision="$1" trust="$2" verdict_file="${3:-}" hash ts tmp rec dst
  case "${decision}" in proceed|proceed_degraded) ;; *) return 0 ;; esac
  hash="$(review_binding_hash)" || return 0
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

review_binding_check() {
  local latest latest_decision current recorded decision
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
  current="$(review_binding_hash)" || {
    echo "no binding gate verdict for this change" >&2
    return 1
  }
  recorded="$(review_binding_field binding_hash)"
  if [ -z "${recorded}" ] || [ "${current}" != "${recorded}" ]; then
    echo "no binding gate verdict for this change" >&2
    return 1
  fi
  return 0
}
