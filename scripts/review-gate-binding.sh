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
  git rev-list --parents -n 1 HEAD 2>/dev/null | awk '{ print NF - 1 }'
}

review_binding_committed_payload() {
  printf '\037commit-diff\037\n'
  if [ "$(review_binding_head_parent_count)" -gt 1 ]; then
    review_binding_git diff --no-ext-diff --no-textconv HEAD^1 HEAD 2>/dev/null
  else
    review_binding_git show --format= --no-ext-diff --no-textconv HEAD 2>/dev/null
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
