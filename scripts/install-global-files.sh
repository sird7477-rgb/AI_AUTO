#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME:-}"
PASS_COUNT=0
FIX_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

usage() {
  cat <<'USAGE'
Usage: ./scripts/install-global-files.sh

Install or repair ai-lab global helper files for this checkout.

This command may create or repair safe helper symlinks under ~/bin:

  ~/bin/ai-auto-init
  ~/bin/aiinit
  ~/bin/workspace-scan

It does not install external programs, edit shell profiles, configure credentials,
run automation-doctor --fix, or overwrite non-symlink files.
USAGE
}

case "${1:-}" in
  "")
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

say_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[pass] %s\n' "$1"
}

say_fix() {
  FIX_COUNT=$((FIX_COUNT + 1))
  printf '[fix] %s\n' "$1"
}

say_warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '[warn] %s\n' "$1"
}

say_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[fail] %s\n' "$1"
}

print_summary() {
  echo
  printf 'Summary: %s passed, %s fixed, %s warnings, %s failed\n' \
    "$PASS_COUNT" "$FIX_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
}

check_source_helper() {
  local path="$1"

  if [ -x "$path" ]; then
    say_pass "source helper is executable: ${path}"
  else
    say_fail "source helper is missing or not executable: ${path}"
  fi
}

install_link() {
  local link_path="$1"
  local target_path="$2"
  local link_dir

  if [ -L "$link_path" ] && [ "$(readlink "$link_path")" = "$target_path" ]; then
    say_pass "global helper link ok: ${link_path}"
    return
  fi

  if [ -e "$link_path" ] && [ ! -L "$link_path" ]; then
    say_fail "global helper path exists but is not a symlink: ${link_path}"
    return
  fi

  link_dir="$(dirname "$link_path")"

  if [ -d "$link_dir" ] && [ ! -w "$link_dir" ]; then
    say_fail "global helper directory is not writable: ${link_dir}"
    return
  fi

  if [ -e "$link_dir" ] && [ ! -d "$link_dir" ]; then
    say_fail "global helper parent path exists but is not a directory: ${link_dir}"
    return
  fi

  if [ ! -d "$link_dir" ] && [ ! -w "$HOME_DIR" ]; then
    say_fail "HOME directory is not writable; cannot create helper directory: ${HOME_DIR}"
    return
  fi

  mkdir -p "$link_dir"

  if [ -L "$link_path" ]; then
    rm -f "$link_path"
  fi

  ln -s "$target_path" "$link_path"
  say_fix "linked ${link_path} -> ${target_path}"
}

echo "[global-files] installing ai-lab global helper files"
echo "[global-files] checkout: ${ROOT}"
echo

check_source_helper "${ROOT}/tools/ai-auto-init"
check_source_helper "${ROOT}/tools/workspace-scan"

if [ "$FAIL_COUNT" -gt 0 ]; then
  print_summary
  echo
  echo "[global-files] not complete; source helpers must be executable before links are changed"
  exit 1
fi

if [ -z "$HOME_DIR" ]; then
  say_fail "HOME is not set; cannot install global helper links"
elif [ ! -d "$HOME_DIR" ]; then
  say_fail "HOME directory does not exist: ${HOME_DIR}"
else
  install_link "${HOME_DIR}/bin/ai-auto-init" "${ROOT}/tools/ai-auto-init"
  install_link "${HOME_DIR}/bin/aiinit" "${ROOT}/tools/ai-auto-init"
  install_link "${HOME_DIR}/bin/workspace-scan" "${ROOT}/tools/workspace-scan"

  case ":${PATH}:" in
    *":${HOME_DIR}/bin:"*)
      say_pass "global helper directory is on PATH: ${HOME_DIR}/bin"
      ;;
    *)
      say_warn "global helper directory is not on PATH: ${HOME_DIR}/bin"
      echo '[hint] temporary PATH fix: export PATH="$HOME/bin:$PATH"'
      ;;
  esac
fi

print_summary

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "[global-files] not complete; resolve failed items and rerun this command"
  exit 1
fi

echo
echo "[global-files] done"
