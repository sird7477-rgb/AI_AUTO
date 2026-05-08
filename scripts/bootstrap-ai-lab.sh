#!/usr/bin/env bash
set -euo pipefail

FIX=0

usage() {
  cat <<'USAGE'
Usage: ./scripts/bootstrap-ai-lab.sh [--fix]

Check first-time ai-lab setup for this checkout.

Default mode diagnoses required tools, helper links, PATH, and automation doctor output.
With --fix, bootstrap may create safe helper symlinks through automation-doctor.

It does not install external tools, edit shell profile files, configure git remotes, or reset reviewer state.
USAGE
}

case "${1:-}" in
  "")
    ;;
  --fix)
    FIX=1
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    echo
    usage
    exit 2
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME:-}"
HOME_READY=0

if [ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ]; then
  HOME_READY=1
fi

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
FIX_COUNT=0
SUGGESTIONS=()

say_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[pass] %s\n' "$1"
}

say_warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '[warn] %s\n' "$1"
}

say_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[fail] %s\n' "$1"
}

say_fix() {
  FIX_COUNT=$((FIX_COUNT + 1))
  printf '[fix] %s\n' "$1"
}

suggest() {
  local suggestion="$1"
  local existing

  if [ "${#SUGGESTIONS[@]}" -gt 0 ]; then
    for existing in "${SUGGESTIONS[@]}"; do
      if [ "$existing" = "$suggestion" ]; then
        return
      fi
    done
  fi

  SUGGESTIONS+=("$suggestion")
}

check_command() {
  local name="$1"
  local severity="$2"

  if command -v "$name" >/dev/null 2>&1; then
    say_pass "command available: ${name}"
  elif [ "$severity" = "fail" ]; then
    say_fail "required command missing: ${name}"
    suggest "install ${name} and ensure it is on PATH"
  else
    say_warn "optional command missing: ${name}"
    suggest "install ${name} if this workflow needs it"
  fi
}

ensure_link() {
  local link_path="$1"
  local target_path="$2"

  if [ -z "$HOME_DIR" ]; then
    say_warn "HOME is not set; cannot check helper link: ${link_path}"
    return
  fi

  if [ "$HOME_READY" -ne 1 ]; then
    say_warn "HOME directory does not exist; cannot check helper link: ${HOME_DIR}"
    suggest "set HOME to an existing user directory"
    return
  fi

  if [ -L "$link_path" ] && [ "$(readlink "$link_path")" = "$target_path" ]; then
    say_pass "helper link ok: ${link_path}"
    return
  fi

  if [ -e "$link_path" ] && [ ! -L "$link_path" ]; then
    say_warn "helper path exists but is not a symlink: ${link_path}"
    suggest "review ${link_path} before replacing it"
    return
  fi

  if [ "$FIX" -eq 1 ]; then
    local link_dir
    link_dir="$(dirname "$link_path")"

    if [ -d "$link_dir" ] && [ ! -w "$link_dir" ]; then
      say_warn "helper directory is not writable; cannot create helper link: ${link_dir}"
      suggest "check permissions for ${link_dir}"
      return
    fi

    if [ ! -d "$link_dir" ] && [ ! -w "$HOME_DIR" ]; then
      say_warn "HOME directory is not writable; cannot create helper directory: ${HOME_DIR}"
      suggest "check permissions for ${HOME_DIR}"
      return
    fi

    mkdir -p "$link_dir"
    ln -sfn "$target_path" "$link_path"
    say_fix "linked ${link_path} -> ${target_path}"
  elif [ -L "$link_path" ]; then
    say_warn "helper link points elsewhere: ${link_path}"
    suggest "./scripts/bootstrap-ai-lab.sh --fix"
  else
    say_warn "helper link missing: ${link_path}"
    suggest "./scripts/bootstrap-ai-lab.sh --fix"
  fi
}

printf '[bootstrap] checking ai-lab checkout in %s\n\n' "$ROOT"

if [ ! -d "${ROOT}/.git" ]; then
  say_fail "ai-lab checkout is not a git repository: ${ROOT}"
  suggest "clone ai-lab with git"
fi

if [ -x "${ROOT}/scripts/automation-doctor.sh" ]; then
  say_pass "automation doctor is executable"
else
  say_fail "automation doctor is missing or not executable"
  suggest "chmod +x ${ROOT}/scripts/*.sh"
fi

if [ -x "${ROOT}/tools/ai-auto-init" ]; then
  say_pass "aiinit source helper is executable"
else
  say_fail "aiinit source helper is missing or not executable"
  suggest "chmod +x ${ROOT}/tools/ai-auto-init"
fi

if [ -x "${ROOT}/tools/workspace-scan" ]; then
  say_pass "workspace-scan source helper is executable"
else
  say_fail "workspace-scan source helper is missing or not executable"
  suggest "chmod +x ${ROOT}/tools/workspace-scan"
fi

echo
echo "[bootstrap] checking commands"

check_command git fail
check_command docker warn
check_command claude warn
check_command gemini warn
check_command omx warn

echo
echo "[bootstrap] checking helper links"

if [ -n "$HOME_DIR" ] && [ "$HOME_READY" -eq 1 ]; then
  ensure_link "${HOME_DIR}/bin/ai-auto-init" "${ROOT}/tools/ai-auto-init"
  ensure_link "${HOME_DIR}/bin/aiinit" "${ROOT}/tools/ai-auto-init"
  ensure_link "${HOME_DIR}/bin/workspace-scan" "${ROOT}/tools/workspace-scan"

  case ":${PATH}:" in
    *":${HOME_DIR}/bin:"*)
      say_pass "global helper directory is on PATH: ${HOME_DIR}/bin"
      ;;
    *)
      say_warn "global helper directory is not on PATH: ${HOME_DIR}/bin"
      suggest 'export PATH="$HOME/bin:$PATH"'
      suggest 'add export PATH="$HOME/bin:$PATH" to your shell profile'
      ;;
  esac
elif [ -n "$HOME_DIR" ]; then
  say_warn "HOME directory does not exist; helper link and PATH checks skipped: ${HOME_DIR}"
  suggest "set HOME to an existing user directory"
else
  say_warn "HOME is not set; helper link and PATH checks skipped"
fi

echo
echo "[bootstrap] running automation doctor"

if [ "$FIX" -eq 1 ]; then
  if (
    cd "$ROOT"
    DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh --fix
  ); then
    say_pass "automation doctor completed"
  else
    say_fail "automation doctor failed"
    suggest "cd ${ROOT} && ./scripts/automation-doctor.sh"
  fi
elif (
  cd "$ROOT"
  DOCTOR_SKIP_DIRTY_CHECK=1 ./scripts/automation-doctor.sh
); then
  say_pass "automation doctor completed"
else
  say_fail "automation doctor failed"
  suggest "cd ${ROOT} && ./scripts/automation-doctor.sh"
fi

echo
printf 'Summary: %s passed, %s warnings, %s failed' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
if [ "$FIX_COUNT" -gt 0 ]; then
  printf ', %s fixed' "$FIX_COUNT"
fi
printf '\n'

if [ "${#SUGGESTIONS[@]}" -gt 0 ]; then
  echo
  echo "Suggested fixes:"
  for suggestion in "${SUGGESTIONS[@]}"; do
    printf '  %s\n' "$suggestion"
  done
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

exit 0
