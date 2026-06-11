#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME:-}"
PASS_COUNT=0
FIX_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
INSTALL_CODEX_DRIFT_NOTICE=0
INSTALL_CODEX_TMUX_AUTO_ENTRY=0
INSTALL_AI_TMUX_AUTO_ENTRY=0
INSTALL_TMUX_WORKTREE=0

usage() {
  cat <<'USAGE'
Usage: ./scripts/install-global-files.sh [--install-codex-drift-notice] [--install-codex-tmux-auto-entry] [--install-ai-tmux-auto-entry]

Install or repair ai-lab global helper files for this checkout.

This command may create or repair safe helper symlinks under ~/bin:

  ~/bin/AI_AUTO
  ~/bin/ai-auto-init
  ~/bin/ai-home
  ~/bin/aiinit
  ~/bin/ai-register
  ~/bin/ai-auto-template-status
  ~/bin/ai-gstack-contract
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
  ~/bin/feedback-resolve
  ~/bin/knowledge-collect
  ~/bin/workspace-scan
  ~/bin/micro-work
  ~/bin/ai-worktree
  ~/bin/ai-tmux-worktree
  ~/bin/ai-project-profile

It may also add a managed AI_AUTO shell function under ~/.config/ai-lab and a
small source block in ~/.bashrc so typing AI_AUTO with no arguments changes the
current shell directory to this checkout.

Options:
  --install-codex-drift-notice
      Install an opt-in managed shell function that shows an AI_AUTO template
      update notice once per shell session before the first real codex call in
      each AI_AUTO-managed project.
  --install-codex-tmux-auto-entry
      Install the same managed codex shell function with default-on tmux
      auto-entry. Interactive codex calls outside tmux attach to a
      project-scoped tmux session; use AI_AUTO_CODEX_TMUX_AUTO=0 to opt out.
  --install-ai-tmux-auto-entry
      Install managed shell functions with default-on tmux auto-entry for
      interactive codex, claude, and agy calls outside tmux. Use
      AI_AUTO_TMUX_AUTO=0 to opt out globally, or AI_AUTO_<RUNTIME>_TMUX_AUTO=0
      for one runtime.
  --install-tmux-worktree
      Install a managed ~/.tmux.conf hook block so each tmux window in an
      AI_AUTO project gets its own git worktree (auto-created on open, removed
      on close only if clean). On by default once installed; set
      AI_AUTO_TMUX_WORKTREE=0 to opt out and AI_AUTO_TMUX_WORKTREE_KEEP=1 to
      disable auto-removal.
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
    --install-codex-tmux-auto-entry)
      INSTALL_CODEX_TMUX_AUTO_ENTRY=1
      ;;
    --install-ai-tmux-auto-entry)
      INSTALL_AI_TMUX_AUTO_ENTRY=1
      INSTALL_CODEX_TMUX_AUTO_ENTRY=1
      ;;
    --install-tmux-worktree)
      INSTALL_TMUX_WORKTREE=1
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

aiwt() {
  # Enter a per-terminal git worktree so concurrent terminals on one project do not
  # share a working tree or .omx state. Create/list/remove run in the child; only the
  # final cd happens here. \`aiwt --list\` / \`aiwt --remove <name>\` emit no path -> no cd.
  local d
  d="\$(command ai-worktree "\$@")" || return
  [ -n "\$d" ] && cd "\$d"
}

_ai_auto_project_list_cd() {
  local root="\$1"
  local label="\$2"
  local override_var="\${3:-}"
  local -a projects
  local choice choice_num selected i current

  if [ ! -d "\$root" ]; then
    printf '%s\n' "[AI_AUTO] project root not found for \${label}: \${root}" >&2
    if [ -n "\$override_var" ]; then
      printf '%s\n' "[AI_AUTO] set \${override_var}=/path/to/root if this project group lives elsewhere" >&2
    fi
    return 1
  fi

  current="\$root"
  while true; do
    mapfile -t projects < <(
      find "\$current" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print 2>/dev/null |
        sort -V
    )

    if [ "\${#projects[@]}" -eq 0 ]; then
      cd "\$current" || return
      return
    fi

    printf '%s\n' ""
    printf '%s\n' "\${label}: \${current}"
    printf '[0] 여기로 이동\n'
    i=1
    for selected in "\${projects[@]}"; do
      printf '[%d] %s\n' "\$i" "\$(basename "\$selected")"
      printf '    %s\n' "\$selected"
      i=\$((i + 1))
    done

    printf '번호 입력: '
    IFS= read -r choice || return 1
    case "\$choice" in
      ''|*[!0-9]*)
        printf '%s\n' "[AI_AUTO] invalid selection: \${choice}" >&2
        return 1
        ;;
    esac
    choice_num=\$((10#\$choice))

    if [ "\$choice_num" -eq 0 ]; then
      cd "\$current" || return
      return
    fi

    if [ "\$choice_num" -lt 1 ] || [ "\$choice_num" -gt "\${#projects[@]}" ]; then
      printf '%s\n' "[AI_AUTO] selection out of range: \${choice}" >&2
      return 1
    fi

    selected="\${projects[\$((choice_num - 1))]}"
    if [ -e "\$selected/.git" ] ||
      [ -e "\$selected/AGENTS.md" ] ||
      [ -e "\$selected/package.json" ] ||
      [ -e "\$selected/pyproject.toml" ] ||
      [ -e "\$selected/requirements.txt" ] ||
      [ -e "\$selected/docker-compose.yml" ] ||
      [ -e "\$selected/scripts/verify.sh" ]; then
      cd "\$selected" || return
      return
    fi

    current="\$selected"
  done
}

jwlist() {
  _ai_auto_project_list_cd "\${AI_AUTO_JW_PROJECT_ROOT:-/mnt/z/JSJEON/Project_JW}" "jwlist" "AI_AUTO_JW_PROJECT_ROOT"
}

sirdlist() {
  _ai_auto_project_list_cd "\${AI_AUTO_SIRD_PROJECT_ROOT:-/mnt/z/JSJEON/Project_SirD}" "sirdlist" "AI_AUTO_SIRD_PROJECT_ROOT"
}

tmux() {
  if [ "\$#" -ne 0 ]; then
    command tmux "\$@"
    return
  fi

  local session_name
  session_name=1
  while command tmux has-session -t "\${session_name}" >/dev/null 2>&1; do
    session_name=\$((session_name + 1))
  done

  command tmux new-session -s "\${session_name}"
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

install_codex_wrapper() {
  local bashrc_path="${HOME_DIR}/.bashrc"
  local config_dir="${HOME_DIR}/.config/ai-lab"
  local function_path="${config_dir}/codex-drift-notice.sh"
  local function_tmp_path
  local function_marker="# Managed by AI_AUTO install-global-files.sh codex drift notice"
  local begin_marker="# >>> AI_AUTO codex drift notice integration >>>"
  local end_marker="# <<< AI_AUTO codex drift notice integration <<<"
  local tmp_path
  local begin_count end_count
  local real_codex real_claude="" real_agy="" patch_notes_quoted ai_lab_root_quoted
  local real_codex_quoted real_claude_quoted="" real_agy_quoted=""
  local drift_default tmux_auto_default claude_tmux_auto_default agy_tmux_auto_default
  local include_claude_wrapper=0 include_agy_wrapper=0
  local existing_value resolve_status

  if [ "$INSTALL_CODEX_DRIFT_NOTICE" -ne 1 ] && [ "$INSTALL_CODEX_TMUX_AUTO_ENTRY" -ne 1 ] && [ "$INSTALL_AI_TMUX_AUTO_ENTRY" -ne 1 ]; then
    return
  fi

  if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
    say_fail "HOME is not ready; cannot install codex shell function"
    return
  fi

  extract_generated_function_local() {
    local function_name="$1"
    local local_name="$2"
    local path="$3"

    awk -v fn="${function_name}" -v local_name="${local_name}" '
      $0 == fn "() {" { in_fn=1; next }
      in_fn && $0 == "}" { exit }
      in_fn {
        prefix = "  local " local_name "="
        if (index($0, prefix) == 1) {
          print substr($0, length(prefix) + 1)
          exit
        }
      }
    ' "$path"
  }

  resolve_runtime_command() {
    local runtime_name="$1"
    local resolved resolved_dir resolved_base

    if ! resolved="$(command -v "${runtime_name}" 2>/dev/null)"; then
      return 1
    fi

    case "$resolved" in
      /*)
        ;;
      */*)
        resolved_dir="$(cd -P "$(dirname "$resolved")" 2>/dev/null && pwd)" || return 1
        resolved="${resolved_dir}/$(basename "$resolved")"
        ;;
      *)
        resolved_dir="$(dirname "$(command -v -- "$resolved")")"
        resolved_base="$(basename "$resolved")"
        resolved_dir="$(cd -P "$resolved_dir" 2>/dev/null && pwd)" || return 1
        resolved="${resolved_dir}/${resolved_base}"
        ;;
    esac

    [ -x "$resolved" ] || return 1

    case "$resolved" in
      "${HOME_DIR}/bin/${runtime_name}"|*"${ROOT}/"*)
        return 2
        ;;
    esac

    printf '%s\n' "$resolved"
  }

  real_codex="$(resolve_runtime_command codex)"
  resolve_status=$?
  if [ "$resolve_status" -ne 0 ]; then
    if [ "$resolve_status" -eq 2 ]; then
      say_fail "codex resolves to an AI_AUTO-managed path; refusing shadow install"
    else
      say_fail "codex is not on PATH; cannot install codex shell function"
    fi
    return
  fi

  if [ "$INSTALL_AI_TMUX_AUTO_ENTRY" -eq 1 ]; then
    if real_claude="$(resolve_runtime_command claude)"; then
      include_claude_wrapper=1
    else
      say_warn "claude is not available or resolves to an AI_AUTO-managed path; skipping claude tmux wrapper"
    fi

    if real_agy="$(resolve_runtime_command agy)"; then
      include_agy_wrapper=1
    else
      say_warn "agy is not available or resolves to an AI_AUTO-managed path; skipping agy tmux wrapper"
    fi
  elif [ -f "$function_path" ]; then
    if grep -q '^claude() {' "$function_path"; then
      existing_value="$(extract_generated_function_local claude real_claude "$function_path")"
      if [ -n "$existing_value" ]; then
        real_claude_quoted="$existing_value"
        include_claude_wrapper=1
      fi
    fi
    if grep -q '^agy() {' "$function_path"; then
      existing_value="$(extract_generated_function_local agy real_agy "$function_path")"
      if [ -n "$existing_value" ]; then
        real_agy_quoted="$existing_value"
        include_agy_wrapper=1
      fi
    fi
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
  if [ -n "$real_claude" ] && [ -z "$real_claude_quoted" ]; then
    real_claude_quoted="$(printf '%q' "$real_claude")"
  fi
  if [ -n "$real_agy" ] && [ -z "$real_agy_quoted" ]; then
    real_agy_quoted="$(printf '%q' "$real_agy")"
  fi
  patch_notes_quoted="$(printf '%q' "${ROOT}/templates/automation-base/docs/PATCH_NOTES.md")"
  ai_lab_root_quoted="$(printf '%q' "$ROOT")"
  drift_default="$INSTALL_CODEX_DRIFT_NOTICE"
  if [ "$drift_default" -ne 1 ] &&
    [ -f "$function_path" ] &&
    [ "$(extract_generated_function_local codex drift_notice_default "$function_path")" = "1" ]; then
    drift_default=1
  fi
  tmux_auto_default="${INSTALL_CODEX_TMUX_AUTO_ENTRY:-0}"
  if [ "$tmux_auto_default" -ne 1 ] &&
    [ -f "$function_path" ] &&
    [ "$(extract_generated_function_local codex tmux_auto_default "$function_path")" = "1" ]; then
    tmux_auto_default=1
    say_warn "preserving existing codex tmux auto-entry default; use AI_AUTO_CODEX_TMUX_AUTO=0 or remove the managed shell function to opt out"
  elif [ "$tmux_auto_default" -eq 1 ]; then
    printf '[info] installing codex tmux auto-entry as the default; use AI_AUTO_CODEX_TMUX_AUTO=0 to opt out for a shell\n'
  fi
  claude_tmux_auto_default=0
  agy_tmux_auto_default=0
  if [ "$INSTALL_AI_TMUX_AUTO_ENTRY" -eq 1 ]; then
    claude_tmux_auto_default="$include_claude_wrapper"
    agy_tmux_auto_default="$include_agy_wrapper"
    printf '[info] installing AI tmux auto-entry; use AI_AUTO_TMUX_AUTO=0 to opt out for a shell\n'
  elif [ -f "$function_path" ]; then
    if [ "$include_claude_wrapper" -eq 1 ] &&
      [ "$(extract_generated_function_local claude tmux_auto_default "$function_path")" = "1" ]; then
      claude_tmux_auto_default=1
    fi
    if [ "$include_agy_wrapper" -eq 1 ] &&
      [ "$(extract_generated_function_local agy tmux_auto_default "$function_path")" = "1" ]; then
      agy_tmux_auto_default=1
    fi
  fi

  cat > "$function_tmp_path" <<EOF
${function_marker}
_ai_auto_tmux_session_name() {
  local base="\$1"
  local hash=""
  local runtime_name=""
  local slug=""

  if [ "\$#" -ge 2 ]; then
    runtime_name="\$1"
    base="\$2"
  fi

  slug="\$(basename "\$base" | tr -cs '[:alnum:]_.-' '-' | sed 's/^-//; s/-\$//')"
  if [ -z "\$slug" ]; then
    slug="workspace"
  fi
  if [ -n "\${runtime_name}" ]; then
    slug="\${runtime_name}-\${slug}"
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    hash="\$(printf '%s' "\${runtime_name}|\${base}" | sha256sum | awk '{print substr(\$1,1,8)}')"
  elif command -v cksum >/dev/null 2>&1; then
    hash="\$(printf '%s' "\${runtime_name}|\${base}" | cksum | awk '{print \$1}')"
  else
    hash="nohash"
  fi

  printf 'ai-%s-%s\n' "\$slug" "\$hash"
}

_ai_auto_shell_quote() {
  local arg=""
  local escaped=""
  local quoted=""

  for arg in "\$@"; do
    escaped="\${arg//\\'/\\'\\\\\\'\\'}"
    quoted="\${quoted} '\${escaped}'"
  done

  printf '%s\n' "\${quoted# }"
}

_ai_auto_nofile_limit() {
  local target="\${AI_AUTO_NOFILE_LIMIT:-1048576}"

  case "\${target}" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  printf '%s\n' "\${target}"
}

_ai_auto_raise_nofile_limit() {
  local current=""
  local target=""

  target="\$(_ai_auto_nofile_limit)" || return 0
  current="\$(ulimit -n 2>/dev/null || true)"
  case "\${current}" in
    ''|*[!0-9]*)
      ulimit -n "\${target}" >/dev/null 2>&1 || true
      return 0
      ;;
  esac

  if [ "\${current}" -lt "\${target}" ]; then
    ulimit -n "\${target}" >/dev/null 2>&1 || true
  fi
}

_ai_auto_runtime_command() {
  local runtime_binary="\$1"
  local limit=""
  local quoted=""
  shift

  quoted="\$(_ai_auto_shell_quote "\${runtime_binary}" "\$@")"
  limit="\$(_ai_auto_nofile_limit 2>/dev/null || true)"
  if [ -n "\${limit}" ]; then
    printf 'ulimit -n %s >/dev/null 2>&1 || true; %s\n' "\${limit}" "\${quoted}"
  else
    printf '%s\n' "\${quoted}"
  fi
}

_ai_auto_start_tmux_session() {
  local tmux_binary="\$1"
  local tmux_session_base="\$2"
  local tmux_command="\$3"
  local attempt=1
  local max_attempts="\${AI_AUTO_TMUX_SESSION_ATTEMPTS:-50}"
  local tmux_session=""

  case "\${max_attempts}" in
    ''|*[!0-9]*)
      max_attempts=50
      ;;
  esac

  while [ "\${attempt}" -le "\${max_attempts}" ]; do
    if [ "\${attempt}" -eq 1 ]; then
      tmux_session="\${tmux_session_base}"
    else
      tmux_session="\${tmux_session_base}-\${attempt}"
    fi

    command "\${tmux_binary}" new-session -s "\${tmux_session}" -c "\$(pwd)" "\${tmux_command}" && return 0
    attempt=\$((attempt + 1))
  done

  return 1
}

_ai_auto_enter_tmux_if_needed() {
  local runtime_name="\$1"
  local runtime_binary="\$2"
  local runtime_toggle="\$3"
  local tmux_auto_default="\$4"
  shift 4
  local tmux_binary=""
  local tmux_base=""
  local tmux_command=""
  local tmux_session=""

  if [ "\${AI_AUTO_TMUX_AUTO:-1}" = "0" ]; then
    return 1
  fi

  if [ "\${runtime_toggle:-\${tmux_auto_default}}" != "1" ] ||
    [ -n "\${TMUX:-}" ] ||
    ! [ -t 0 ] ||
    ! [ -t 1 ]; then
    return 1
  fi

  tmux_binary="\$(type -P tmux 2>/dev/null || true)"
  if [ -z "\${tmux_binary}" ]; then
    return 1
  fi

  tmux_base="\${AI_AUTO_TMUX_BASE:-\$(pwd)}"
  tmux_session="\$(_ai_auto_tmux_session_name "\${runtime_name}" "\${tmux_base}")"
  tmux_command="\$(_ai_auto_runtime_command "\${runtime_binary}" "\$@")"
  _ai_auto_start_tmux_session "\${tmux_binary}" "\${tmux_session}" "\${tmux_command}" && return 0
  return 1
}

_ai_auto_codex_tmux_session_name() {
  _ai_auto_tmux_session_name "\$@"
}

_ai_auto_codex_shell_quote() {
  _ai_auto_shell_quote "\$@"
}

codex() {
  local real_codex=${real_codex_quoted}
  local patch_notes=${patch_notes_quoted}
  local ai_lab_root=${ai_lab_root_quoted}
  local drift_notice_default=${drift_default}
  local tmux_auto_default=${tmux_auto_default}
  local repo_root=""
  local status_output=""
  local notice_key=""
  local latest_note=""
  local knowledge_output=""
  local knowledge_timeout=""
  local template_status_timeout=""

  if command -v git >/dev/null 2>&1; then
    repo_root="\$(git rev-parse --show-toplevel 2>/dev/null || true)"
  fi

  if [ "\${AI_AUTO_CODEX_DRIFT_NOTICE:-\${drift_notice_default}}" != "0" ] &&
    [ -n "\${repo_root}" ] &&
    [ -f "\${repo_root}/AI_AUTO_TEMPLATE_VERSION" ] &&
    command -v timeout >/dev/null 2>&1 &&
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
        template_status_timeout="\${AI_AUTO_TEMPLATE_STATUS_NOTICE_TIMEOUT:-1}"
        status_output="\$(timeout "\${template_status_timeout}" ai-auto-template-status "\${repo_root}" 2>/dev/null || true)"
        AI_AUTO_CODEX_DRIFT_NOTICE_SEEN="\${AI_AUTO_CODEX_DRIFT_NOTICE_SEEN:-}|\${notice_key}|"
        if printf '%s\n' "\$status_output" | grep -q '^status: customized_or_outdated'; then
          latest_note="\$(awk '/^## / {print; exit}' "\${patch_notes}" 2>/dev/null || true)"
          printf '%s\n' "[AI_AUTO] ===== AI_AUTO UPDATE CHECK =====" >&2
          printf '%s\n' "[AI_AUTO] state: update_available" >&2
          printf '%s\n' "[AI_AUTO] project: \${repo_root}" >&2
          printf '%s\n' "\$status_output" | awk '/^(installed_version|current_version|status): / {print "[AI_AUTO] " \$0}' >&2
          if [ -n "\${latest_note}" ]; then
            printf '%s\n' "[AI_AUTO] latest patch note: \${latest_note#\#\# }" >&2
          fi
          printf '%s\n' "[AI_AUTO] review notes: \${patch_notes}" >&2
          printf '%s\n' "[AI_AUTO] inspect: ai-auto-template-status \${repo_root}" >&2
          printf '%s\n' "[AI_AUTO] action: AI_AUTO 최신 패치 적용해줘" >&2
          printf '%s\n' "[AI_AUTO] ================================" >&2
        fi
        ;;
    esac
    fi

  if [ "\${AI_AUTO_KNOWLEDGE_AUTOPUSH_NOTICE:-1}" != "0" ] &&
    [ -n "\${repo_root}" ] &&
    [ "\${repo_root}" = "\${ai_lab_root}" ] &&
    command -v timeout >/dev/null 2>&1 &&
    command -v knowledge-collect >/dev/null 2>&1; then
    knowledge_timeout="\${AI_AUTO_KNOWLEDGE_NOTICE_TIMEOUT:-3}"
    knowledge_output="\$(timeout "\${knowledge_timeout}" knowledge-collect --include-registry --project "\${repo_root}" 2>/dev/null || true)"
    if printf '%s\n' "\${knowledge_output}" | awk 'NR > 1 && NF {found=1} END {exit found ? 0 : 1}'; then
      printf '%s\n' "[AI_AUTO] ===== OBSIDIAN OUTPUT CHECK =====" >&2
      printf '%s\n' "[AI_AUTO] state: pending_knowledge_drafts" >&2
      printf '%s\n' "[AI_AUTO] scope: AI_AUTO home plus registered projects" >&2
	      printf '%s\n' "\${knowledge_output}" | awk 'NR == 1 {next} NF {print "[AI_AUTO] pending: " \$0; count++} count >= 10 {exit}' >&2
	      printf '%s\n' "[AI_AUTO] inspect: knowledge-collect --include-registry --project \${repo_root}" >&2
	      printf '%s\n' "[AI_AUTO] register moved/missing project: ai-register --prune; ai-register /path/to/repo" >&2
	      printf '%s\n' "[AI_AUTO] push after approval: knowledge-collect --project <repo> --push --vault-dir <vault-dir>" >&2
	      printf '%s\n' "[AI_AUTO] publish shareable drafts: scripts/obsidian-autopush.sh" >&2
	      printf '%s\n' "[AI_AUTO] ================================" >&2
    fi
  fi

  if AI_AUTO_TMUX_BASE="\${repo_root:-\$(pwd)}" _ai_auto_enter_tmux_if_needed \
    codex "\${real_codex}" "\${AI_AUTO_CODEX_TMUX_AUTO:-}" "\${tmux_auto_default}" "\$@"; then
    return
  fi

  _ai_auto_raise_nofile_limit
  "\$real_codex" "\$@"
}
EOF

  if [ "$include_claude_wrapper" -eq 1 ]; then
    cat >> "$function_tmp_path" <<EOF

claude() {
  local real_claude=${real_claude_quoted}
  local tmux_auto_default=${claude_tmux_auto_default}
  local repo_root=""

  if command -v git >/dev/null 2>&1; then
    repo_root="\$(git rev-parse --show-toplevel 2>/dev/null || true)"
  fi

  if AI_AUTO_TMUX_BASE="\${repo_root:-\$(pwd)}" _ai_auto_enter_tmux_if_needed \
    claude "\${real_claude}" "\${AI_AUTO_CLAUDE_TMUX_AUTO:-}" "\${tmux_auto_default}" "\$@"; then
    return
  fi

  _ai_auto_raise_nofile_limit
  "\$real_claude" "\$@"
}
EOF
  fi

  if [ "$include_agy_wrapper" -eq 1 ]; then
    cat >> "$function_tmp_path" <<EOF

agy() {
  local real_agy=${real_agy_quoted}
  local tmux_auto_default=${agy_tmux_auto_default}
  local repo_root=""

  if command -v git >/dev/null 2>&1; then
    repo_root="\$(git rev-parse --show-toplevel 2>/dev/null || true)"
  fi

  if AI_AUTO_TMUX_BASE="\${repo_root:-\$(pwd)}" _ai_auto_enter_tmux_if_needed \
    agy "\${real_agy}" "\${AI_AUTO_AGY_TMUX_AUTO:-}" "\${tmux_auto_default}" "\$@"; then
    return
  fi

  _ai_auto_raise_nofile_limit
  "\$real_agy" "\$@"
}
EOF
  fi

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
    say_pass "codex shell source block already installed in ${bashrc_path}"
  else
    mv "$tmp_path" "$bashrc_path"
    say_fix "installed codex shell source block in ${bashrc_path}"
  fi

  if [ -f "$function_path" ] && cmp -s "$function_tmp_path" "$function_path"; then
    rm -f "$function_tmp_path"
    say_pass "codex shell function already installed: ${function_path}"
    return
  fi

  mv "$function_tmp_path" "$function_path"
  say_fix "installed codex shell function file: ${function_path}"
}

echo "[global-files] installing ai-lab global helper files"
echo "[global-files] checkout: ${ROOT}"
echo

install_tmux_hooks() {
  local conf="${HOME_DIR}/.tmux.conf"
  local begin="# >>> AI_AUTO tmux worktree integration >>>"
  local end="# <<< AI_AUTO tmux worktree integration <<<"
  local tmp begin_count end_count

  if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
    say_fail "HOME is not ready; cannot install tmux worktree hooks"
    return
  fi
  if [ -e "$conf" ] && [ ! -f "$conf" ]; then
    say_fail "tmux config path exists but is not a file: ${conf}"
    return
  fi
  if [ -e "$conf" ] && [ ! -w "$conf" ]; then
    say_fail "tmux config is not writable: ${conf}"
    return
  fi
  if [ ! -e "$conf" ] && [ ! -w "$HOME_DIR" ]; then
    say_fail "HOME directory is not writable; cannot create tmux config: ${conf}"
    return
  fi

  begin_count=0
  end_count=0
  if [ -f "$conf" ]; then
    begin_count="$(grep -cFx "$begin" "$conf" || true)"
    end_count="$(grep -cFx "$end" "$conf" || true)"
  fi
  if [ "$begin_count" -ne "$end_count" ]; then
    say_fail "tmux worktree markers are unbalanced in ${conf}; not editing tmux config"
    return
  fi

  tmp="${conf}.ai-auto.$$"
  {
    if [ -f "$conf" ]; then
      awk -v b="$begin" -v e="$end" '
        $0==b {skip=1; next}
        $0==e {skip=0; next}
        skip!=1 {print}
      ' "$conf"
    fi
    printf '%s\n' "$begin"
    printf '%s\n' "set-hook -g after-new-session 'run-shell \"ai-tmux-worktree create #{window_id} #{pane_id} #{pane_current_path}\"'"
    printf '%s\n' "set-hook -g after-new-window 'run-shell \"ai-tmux-worktree create #{window_id} #{pane_id} #{pane_current_path}\"'"
    printf '%s\n' "set-hook -g window-unlinked 'run-shell \"ai-tmux-worktree remove #{hook_window}\"'"
    printf '%s\n' "set-hook -g session-closed 'run-shell \"ai-tmux-worktree gc\"'"
    printf '%s\n' "$end"
  } > "$tmp"

  if [ -f "$conf" ] && cmp -s "$tmp" "$conf"; then
    rm -f "$tmp"
    say_pass "tmux worktree hooks already installed: ${conf}"
  else
    mv -f "$tmp" "$conf"
    say_fix "installed tmux worktree hooks in ${conf} (on by default; reload a running server with: tmux source-file ~/.tmux.conf; AI_AUTO_TMUX_WORKTREE=0 to disable)"
  fi
}

check_source_helper "${ROOT}/tools/ai-auto-init"
check_source_helper "${ROOT}/tools/ai-home"
check_source_helper "${ROOT}/tools/ai-register"
check_source_helper "${ROOT}/tools/ai-auto-template-status"
check_source_helper "${ROOT}/tools/ai-domain-pack"
check_source_helper "${ROOT}/tools/ai-gstack-contract"
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
check_source_helper "${ROOT}/tools/feedback-resolve"
check_source_helper "${ROOT}/tools/knowledge-collect"
check_source_helper "${ROOT}/tools/workspace-scan"
check_source_helper "${ROOT}/tools/micro-work"
check_source_helper "${ROOT}/tools/ai-worktree"
check_source_helper "${ROOT}/tools/ai-tmux-worktree"
check_source_helper "${ROOT}/tools/ai-project-profile"

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
  install_link "${HOME_DIR}/bin/ai-domain-pack" "${ROOT}/tools/ai-domain-pack"
  install_link "${HOME_DIR}/bin/ai-gstack-contract" "${ROOT}/tools/ai-gstack-contract"
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
  install_link "${HOME_DIR}/bin/feedback-resolve" "${ROOT}/tools/feedback-resolve"
  install_link "${HOME_DIR}/bin/knowledge-collect" "${ROOT}/tools/knowledge-collect"
  install_link "${HOME_DIR}/bin/workspace-scan" "${ROOT}/tools/workspace-scan"
  install_link "${HOME_DIR}/bin/micro-work" "${ROOT}/tools/micro-work"
  install_link "${HOME_DIR}/bin/ai-worktree" "${ROOT}/tools/ai-worktree"
  install_link "${HOME_DIR}/bin/ai-tmux-worktree" "${ROOT}/tools/ai-tmux-worktree"
  install_link "${HOME_DIR}/bin/ai-project-profile" "${ROOT}/tools/ai-project-profile"
  install_shell_function
  if [ "$INSTALL_TMUX_WORKTREE" = "1" ]; then
    install_tmux_hooks
  fi
  install_codex_wrapper

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
