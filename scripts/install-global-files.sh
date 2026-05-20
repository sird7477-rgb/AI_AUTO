#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME:-}"
PASS_COUNT=0
FIX_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
INSTALL_CODEX_DRIFT_NOTICE=0

usage() {
  cat <<'USAGE'
Usage: ./scripts/install-global-files.sh [--install-codex-drift-notice]

Install or repair ai-lab global helper files for this checkout.

This command may create or repair safe helper symlinks under ~/bin:

  ~/bin/AI_AUTO
  ~/bin/ai-auto-init
  ~/bin/ai-home
  ~/bin/aiinit
  ~/bin/ai-register
  ~/bin/ai-auto-template-status
  ~/bin/ai-refactor-scan
  ~/bin/ai-rebuild-plan
  ~/bin/ai-split-plan
  ~/bin/ai-split-dry-run
  ~/bin/ai-split-apply
  ~/bin/ai-plan-status
  ~/bin/ai-interview-record
  ~/bin/ai-plan-review
  ~/bin/ai-plan-export
  ~/bin/feedback-collect
  ~/bin/workspace-scan

It may also add a managed AI_AUTO shell function under ~/.config/ai-lab and a
small source block in ~/.bashrc so typing AI_AUTO with no arguments changes the
current shell directory to this checkout.

Options:
  --install-codex-drift-notice
      Install an opt-in managed shell function that shows an AI_AUTO template
      update notice once per shell session before the first real codex call in
      each AI_AUTO-managed project.
  -h, --help
      Show this help.

It does not install external programs, configure credentials, run
automation-doctor --fix, or overwrite non-symlink files.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-codex-drift-notice)
      INSTALL_CODEX_DRIFT_NOTICE=1
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
  shift
done

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

install_shell_function() {
  local bashrc_path="${HOME_DIR}/.bashrc"
  local config_dir="${HOME_DIR}/.config/ai-lab"
  local function_path="${config_dir}/AI_AUTO.sh"
  local function_tmp_path
  local function_marker="# Managed by AI_AUTO install-global-files.sh"
  local begin_marker="# >>> AI_AUTO shell integration >>>"
  local end_marker="# <<< AI_AUTO shell integration <<<"
  local tmp_path
  local begin_count end_count

  if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
    say_fail "HOME is not ready; cannot install AI_AUTO shell function"
    return
  fi

  if [ -e "$bashrc_path" ] && [ ! -f "$bashrc_path" ]; then
    say_fail "shell profile path exists but is not a file: ${bashrc_path}"
    return
  fi

  if [ -e "$bashrc_path" ] && [ ! -w "$bashrc_path" ]; then
    say_fail "shell profile is not writable: ${bashrc_path}"
    return
  fi

  if [ ! -e "$bashrc_path" ] && [ ! -w "$HOME_DIR" ]; then
    say_fail "HOME directory is not writable; cannot create shell profile: ${HOME_DIR}"
    return
  fi

  tmp_path="${bashrc_path}.ai-auto.$$"

  begin_count=0
  end_count=0
  if [ -f "$bashrc_path" ]; then
    begin_count="$(grep -cFx "$begin_marker" "$bashrc_path" || true)"
    end_count="$(grep -cFx "$end_marker" "$bashrc_path" || true)"
  fi

  if [ "$begin_count" -ne "$end_count" ]; then
    say_fail "shell integration markers are unbalanced in ${bashrc_path}; not editing profile"
    rm -f "$tmp_path"
    return
  fi

  if [ -e "$function_path" ] && [ ! -f "$function_path" ]; then
    say_fail "AI_AUTO shell function path exists but is not a file: ${function_path}"
    rm -f "$tmp_path"
    return
  fi

  if [ -f "$function_path" ] &&
    ! grep -qFx "$function_marker" "$function_path" &&
    ! { grep -q 'AI_AUTO()' "$function_path" && grep -q 'command AI_AUTO --path' "$function_path"; }; then
    say_fail "AI_AUTO shell function file exists but is not managed: ${function_path}"
    rm -f "$tmp_path"
    return
  fi

  mkdir -p "$config_dir"
  function_tmp_path="${function_path}.tmp.$$"
  cat > "$function_tmp_path" <<EOF
${function_marker}
AI_AUTO() {
  if [ "\$#" -eq 0 ]; then
    cd "\$(command AI_AUTO --path)" || return
  else
    command AI_AUTO "\$@"
  fi
}
EOF

  if [ -f "$bashrc_path" ]; then
    awk -v begin="$begin_marker" -v end="$end_marker" '
      $0 == begin {skip=1; next}
      $0 == end {skip=0; next}
      !skip {print}
    ' "$bashrc_path" > "$tmp_path"
  else
    : > "$tmp_path"
  fi

  cat >> "$tmp_path" <<'EOF'
# >>> AI_AUTO shell integration >>>
[ -f "$HOME/.config/ai-lab/AI_AUTO.sh" ] && . "$HOME/.config/ai-lab/AI_AUTO.sh"
# <<< AI_AUTO shell integration <<<
EOF

  if [ -f "$bashrc_path" ] && cmp -s "$tmp_path" "$bashrc_path"; then
    rm -f "$tmp_path"
    say_pass "AI_AUTO shell source block already installed in ${bashrc_path}"
  else
    mv "$tmp_path" "$bashrc_path"
    say_fix "installed AI_AUTO shell source block in ${bashrc_path}"
  fi

  if [ -f "$function_path" ] && cmp -s "$function_tmp_path" "$function_path"; then
    rm -f "$function_tmp_path"
    say_pass "AI_AUTO shell function file already installed: ${function_path}"
    return
  fi

  mv "$function_tmp_path" "$function_path"
  say_fix "installed AI_AUTO shell function file: ${function_path}"
}

install_codex_drift_notice() {
  local bashrc_path="${HOME_DIR}/.bashrc"
  local config_dir="${HOME_DIR}/.config/ai-lab"
  local function_path="${config_dir}/codex-drift-notice.sh"
  local function_tmp_path
  local function_marker="# Managed by AI_AUTO install-global-files.sh codex drift notice"
  local begin_marker="# >>> AI_AUTO codex drift notice integration >>>"
  local end_marker="# <<< AI_AUTO codex drift notice integration <<<"
  local tmp_path
  local begin_count end_count
  local real_codex real_codex_dir real_codex_base real_codex_quoted patch_notes_quoted

  if [ "$INSTALL_CODEX_DRIFT_NOTICE" -ne 1 ]; then
    return
  fi

  if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
    say_fail "HOME is not ready; cannot install codex drift notice shell function"
    return
  fi

  if ! real_codex="$(command -v codex 2>/dev/null)"; then
    say_fail "codex is not on PATH; cannot install codex drift notice"
    return
  fi

  case "$real_codex" in
    /*)
      ;;
    */*)
      real_codex_dir="$(cd -P "$(dirname "$real_codex")" 2>/dev/null && pwd)" || {
        say_fail "could not resolve codex directory: ${real_codex}"
        return
      }
      real_codex="${real_codex_dir}/$(basename "$real_codex")"
      ;;
    *)
      real_codex_dir="$(dirname "$(command -v -- "$real_codex")")"
      real_codex_base="$(basename "$real_codex")"
      real_codex_dir="$(cd -P "$real_codex_dir" 2>/dev/null && pwd)" || {
        say_fail "could not resolve codex directory: ${real_codex}"
        return
      }
      real_codex="${real_codex_dir}/${real_codex_base}"
      ;;
  esac

  if [ ! -x "$real_codex" ]; then
    say_fail "resolved codex is not executable: ${real_codex}"
    return
  fi

  case "$real_codex" in
    "${HOME_DIR}/bin/codex"|*"${ROOT}/"*)
      say_fail "resolved codex path looks AI_AUTO-managed; refusing shadow install: ${real_codex}"
      return
      ;;
  esac

  if [ -e "$bashrc_path" ] && [ ! -f "$bashrc_path" ]; then
    say_fail "shell profile path exists but is not a file: ${bashrc_path}"
    return
  fi

  if [ -e "$bashrc_path" ] && [ ! -w "$bashrc_path" ]; then
    say_fail "shell profile is not writable: ${bashrc_path}"
    return
  fi

  if [ ! -e "$bashrc_path" ] && [ ! -w "$HOME_DIR" ]; then
    say_fail "HOME directory is not writable; cannot create shell profile: ${HOME_DIR}"
    return
  fi

  if [ -e "$function_path" ] && [ ! -f "$function_path" ]; then
    say_fail "codex drift notice path exists but is not a file: ${function_path}"
    return
  fi

  if [ -f "$function_path" ] && ! grep -qFx "$function_marker" "$function_path"; then
    say_fail "codex drift notice file exists but is not managed: ${function_path}"
    return
  fi

  tmp_path="${bashrc_path}.ai-auto-codex.$$"
  begin_count=0
  end_count=0
  if [ -f "$bashrc_path" ]; then
    begin_count="$(grep -cFx "$begin_marker" "$bashrc_path" || true)"
    end_count="$(grep -cFx "$end_marker" "$bashrc_path" || true)"
  fi

  if [ "$begin_count" -ne "$end_count" ]; then
    say_fail "codex drift notice markers are unbalanced in ${bashrc_path}; not editing profile"
    rm -f "$tmp_path"
    return
  fi

  mkdir -p "$config_dir"
  function_tmp_path="${function_path}.tmp.$$"
  real_codex_quoted="$(printf '%q' "$real_codex")"
  patch_notes_quoted="$(printf '%q' "${ROOT}/templates/automation-base/docs/PATCH_NOTES.md")"

  cat > "$function_tmp_path" <<EOF
${function_marker}
codex() {
  local real_codex=${real_codex_quoted}
  local patch_notes=${patch_notes_quoted}
  local repo_root=""
  local status_output=""
  local notice_key=""
  local latest_note=""

  if [ "\${AI_AUTO_CODEX_DRIFT_NOTICE:-1}" != "0" ] &&
    command -v git >/dev/null 2>&1 &&
    repo_root="\$(git rev-parse --show-toplevel 2>/dev/null)" &&
    [ -f "\${repo_root}/AI_AUTO_TEMPLATE_VERSION" ] &&
    command -v ai-auto-template-status >/dev/null 2>&1; then
    if command -v sha256sum >/dev/null 2>&1; then
      notice_key="\$(printf '%s' "\${repo_root}" | sha256sum | awk '{print \$1}')"
    elif command -v cksum >/dev/null 2>&1; then
      notice_key="\$(printf '%s' "\${repo_root}" | cksum | awk '{print \$1 "-" \$2}')"
    else
      notice_key="\$(printf '%s' "\${repo_root}" | sed 's/|/%7C/g')"
    fi
    case "\${AI_AUTO_CODEX_DRIFT_NOTICE_SEEN:-}" in
      *"|"\${notice_key}"|"*)
        ;;
      *)
        status_output="\$(ai-auto-template-status "\${repo_root}" 2>/dev/null || true)"
        AI_AUTO_CODEX_DRIFT_NOTICE_SEEN="\${AI_AUTO_CODEX_DRIFT_NOTICE_SEEN:-}|\${notice_key}|"
        if printf '%s\n' "\$status_output" | grep -q '^status: customized_or_outdated'; then
          latest_note="\$(awk '/^## / {print; exit}' "\${patch_notes}" 2>/dev/null || true)"
          printf '%s\n' "[AI_AUTO] automation template update recommended for \${repo_root}" >&2
          printf '%s\n' "\$status_output" | awk '/^(installed_version|current_version|status): / {print "[AI_AUTO] " \$0}' >&2
          if [ -n "\${latest_note}" ]; then
            printf '%s\n' "[AI_AUTO] latest patch note: \${latest_note#\#\# }" >&2
          fi
          printf '%s\n' "[AI_AUTO] review notes: \${patch_notes}" >&2
          printf '%s\n' "[AI_AUTO] inspect: ai-auto-template-status \${repo_root}" >&2
        fi
        ;;
    esac
    fi

  "\$real_codex" "\$@"
}
EOF

  if [ -f "$bashrc_path" ]; then
    awk -v begin="$begin_marker" -v end="$end_marker" '
      $0 == begin {skip=1; next}
      $0 == end {skip=0; next}
      !skip {print}
    ' "$bashrc_path" > "$tmp_path"
  else
    : > "$tmp_path"
  fi

  cat >> "$tmp_path" <<'EOF'
# >>> AI_AUTO codex drift notice integration >>>
[ -f "$HOME/.config/ai-lab/codex-drift-notice.sh" ] && . "$HOME/.config/ai-lab/codex-drift-notice.sh"
# <<< AI_AUTO codex drift notice integration <<<
EOF

  if [ -f "$bashrc_path" ] && cmp -s "$tmp_path" "$bashrc_path"; then
    rm -f "$tmp_path"
    say_pass "codex drift notice source block already installed in ${bashrc_path}"
  else
    mv "$tmp_path" "$bashrc_path"
    say_fix "installed codex drift notice source block in ${bashrc_path}"
  fi

  if [ -f "$function_path" ] && cmp -s "$function_tmp_path" "$function_path"; then
    rm -f "$function_tmp_path"
    say_pass "codex drift notice shell function already installed: ${function_path}"
    return
  fi

  mv "$function_tmp_path" "$function_path"
  say_fix "installed codex drift notice shell function file: ${function_path}"
}

echo "[global-files] installing ai-lab global helper files"
echo "[global-files] checkout: ${ROOT}"
echo

check_source_helper "${ROOT}/tools/ai-auto-init"
check_source_helper "${ROOT}/tools/ai-home"
check_source_helper "${ROOT}/tools/ai-register"
check_source_helper "${ROOT}/tools/ai-auto-template-status"
check_source_helper "${ROOT}/tools/ai-refactor-scan"
check_source_helper "${ROOT}/tools/ai-rebuild-plan"
check_source_helper "${ROOT}/tools/ai-split-plan"
check_source_helper "${ROOT}/tools/ai-split-dry-run"
check_source_helper "${ROOT}/tools/ai-split-apply"
check_source_helper "${ROOT}/tools/ai-plan-status"
check_source_helper "${ROOT}/tools/ai-interview-record"
check_source_helper "${ROOT}/tools/ai-plan-review"
check_source_helper "${ROOT}/tools/ai-plan-export"
check_source_helper "${ROOT}/tools/feedback-collect"
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
  install_link "${HOME_DIR}/bin/AI_AUTO" "${ROOT}/tools/ai-home"
  install_link "${HOME_DIR}/bin/ai-auto-init" "${ROOT}/tools/ai-auto-init"
  install_link "${HOME_DIR}/bin/ai-home" "${ROOT}/tools/ai-home"
  install_link "${HOME_DIR}/bin/aiinit" "${ROOT}/tools/ai-auto-init"
  install_link "${HOME_DIR}/bin/ai-register" "${ROOT}/tools/ai-register"
  install_link "${HOME_DIR}/bin/ai-auto-template-status" "${ROOT}/tools/ai-auto-template-status"
  install_link "${HOME_DIR}/bin/ai-refactor-scan" "${ROOT}/tools/ai-refactor-scan"
  install_link "${HOME_DIR}/bin/ai-rebuild-plan" "${ROOT}/tools/ai-rebuild-plan"
  install_link "${HOME_DIR}/bin/ai-split-plan" "${ROOT}/tools/ai-split-plan"
  install_link "${HOME_DIR}/bin/ai-split-dry-run" "${ROOT}/tools/ai-split-dry-run"
  install_link "${HOME_DIR}/bin/ai-split-apply" "${ROOT}/tools/ai-split-apply"
  install_link "${HOME_DIR}/bin/ai-plan-status" "${ROOT}/tools/ai-plan-status"
  install_link "${HOME_DIR}/bin/ai-interview-record" "${ROOT}/tools/ai-interview-record"
  install_link "${HOME_DIR}/bin/ai-plan-review" "${ROOT}/tools/ai-plan-review"
  install_link "${HOME_DIR}/bin/ai-plan-export" "${ROOT}/tools/ai-plan-export"
  install_link "${HOME_DIR}/bin/feedback-collect" "${ROOT}/tools/feedback-collect"
  install_link "${HOME_DIR}/bin/workspace-scan" "${ROOT}/tools/workspace-scan"
  install_shell_function
  install_codex_drift_notice

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
echo "[global-files] reload your shell or run: source ~/.bashrc"
