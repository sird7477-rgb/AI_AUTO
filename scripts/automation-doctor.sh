#!/usr/bin/env bash
set -euo pipefail

# Framework siblings resolve via our own dir (symlink-followed) so they run from ANY
# cwd; project artifacts/.omx stay relative to $(pwd).
AH="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# R7-F1 STANDALONE hardening: this doctor is a DOCUMENTED standalone entrypoint
# (`./scripts/automation-doctor.sh --project`; install-ubuntu-prereqs.sh, bootstrap-ai-lab.sh).
# Unlike `ai-auto doctor` (whose launcher sources git-scrub.sh), a standalone run had NO
# process-env pin, so its worktree-scanning git calls (`git ls-files --error-unmatch`,
# `git check-ignore`, `git status`) would EXECUTE an untrusted project's in-repo
# `.git/config core.fsmonitor` hook program (RCE). Source the canonical scrub at startup —
# exactly as tools/ai-auto does — so the GIT_CONFIG_* `core.fsmonitor=` env pin (and the
# hostile-GIT_* unset) covers EVERY git call in this process at once. hooks/ is a sibling of
# scripts/ and always present in the engine repo (where this documented entrypoint runs); source
# only when present AND parseable (ai-auto BLAST-H1 idiom) so `set -e` cannot abort the doctor on a
# partial scripts/-only copy (e.g. a test harness that copies scripts/ without hooks/).
# shellcheck source=../hooks/git-scrub.sh
if [ -f "$AH/../hooks/git-scrub.sh" ] && bash -n "$AH/../hooks/git-scrub.sh" 2>/dev/null; then
  . "$AH/../hooks/git-scrub.sh"
fi

FIX=0
SKIP_DIRTY_CHECK="${DOCTOR_SKIP_DIRTY_CHECK:-0}"
OMX_ARTIFACT_WARN_COUNT="${OMX_ARTIFACT_WARN_COUNT:-120}"
OMX_KNOWLEDGE_DRAFT_WARN_COUNT="${OMX_KNOWLEDGE_DRAFT_WARN_COUNT:-50}"

MODE=""  # ""=auto (engine sentinel) | home=engine self-check | project=globalized project

usage() {
  cat <<'USAGE'
Usage: ./scripts/automation-doctor.sh [--home|--project] [--fix]

Diagnose automation readiness. Two modes:
  --home     engine self-check (full framework inventory; default in the engine repo)
  --project  GLOBALIZED project check (zero framework files is correct; confirms hook
             shims + .omx gitignore; WARNS when scripts/verify-project.sh is absent)
  (no mode)  auto-detect: engine sentinel present -> home, else project

Default mode prints status and suggested repair commands without changing files.
With --fix, the doctor may apply safe non-overwriting automation setup fixes.
--fix does not edit shell profile files or other user environment configuration.

Environment:
  DOCTOR_SKIP_DIRTY_CHECK=1  skip the uncommitted-changes check
  OMX_ARTIFACT_WARN_COUNT=N   warn when a .omx artifact directory has more than N files
  OMX_KNOWLEDGE_DRAFT_WARN_COUNT=N
                              warn when .omx/knowledge/drafts has more than N notes
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fix)
      # Fix-mode invariants:
      # - never install external tools
      # - never overwrite existing project files
      # - never run destructive git operations
      # - only repair automation setup files, directories, executable bits, and helper links
      FIX=1
      ;;
    --home)
      MODE=home
      ;;
    --project)
      MODE=project
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

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
FIX_COUNT=0
SKIP_COUNT=0
SUGGESTIONS=()

ROOT="$(pwd)"
IN_AI_LAB=0
HOME_DIR="${HOME:-}"
HOME_READY=0
# Set to 1 iff the existing timeout-bounded git-status probe TIMED OUT (rc=124) -- a slow-FS
# symptom the slow-FS advisory piggybacks on. Never triggers a NEW/unbounded probe.
_slowfs_git_slow=0

if [ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ]; then
  HOME_READY=1
fi

if [ -f "${ROOT}/scripts/review-gate.sh" ] && [ -d "${ROOT}/templates/domain-packs" ] && [ -x "${ROOT}/tools/ai-auto" ] && [ -x "${ROOT}/tools/ai-home" ] && [ -x "${ROOT}/tools/ai-register" ] && [ -x "${ROOT}/tools/ai-gstack-contract" ] && [ -x "${ROOT}/tools/ai-refactor-scan" ] && [ -x "${ROOT}/tools/ai-rebuild-plan" ] && [ -x "${ROOT}/tools/ai-split-plan" ] && [ -x "${ROOT}/tools/ai-split-dry-run" ] && [ -x "${ROOT}/tools/ai-split-apply" ] && [ -x "${ROOT}/tools/ai-plan-status" ] && [ -x "${ROOT}/tools/ai-interview-record" ] && [ -x "${ROOT}/tools/ai-plan-review" ] && [ -x "${ROOT}/tools/ai-plan-export" ] && [ -x "${ROOT}/tools/feedback-collect" ] && [ -x "${ROOT}/tools/feedback-resolve" ] && [ -x "${ROOT}/tools/knowledge-collect" ] && [ -x "${ROOT}/tools/workspace-scan" ] && [ -x "${ROOT}/tools/ai-agent-watchdog" ] && [ -x "${ROOT}/tools/micro-work" ]; then
  IN_AI_LAB=1
fi

# Resolve the two-mode behaviour. Explicit --home/--project win; otherwise the engine
# sentinel decides. --home grades the full engine inventory; --project NEVER requires
# framework files (a globalized project ships zero of them — that is correct).
if [ -z "$MODE" ]; then
  if [ "$IN_AI_LAB" -eq 1 ]; then MODE=home; else MODE=project; fi
fi
if [ "$MODE" = "home" ]; then
  IN_AI_LAB=1
else
  IN_AI_LAB=0
fi

say_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[pass] %s\n' "$1"
}

say_warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '[warn] %s\n' "$1"
}

say_info() {
  printf '[info] %s\n' "$1"
}

say_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[fail] %s\n' "$1"
}

say_fix() {
  FIX_COUNT=$((FIX_COUNT + 1))
  printf '[fix] %s\n' "$1"
}

say_skip() {
  SKIP_COUNT=$((SKIP_COUNT + 1))
  printf '[skip] %s\n' "$1"
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

case "${OMX_ARTIFACT_WARN_COUNT}" in
  ''|*[!0-9]*)
    say_warn "invalid OMX_ARTIFACT_WARN_COUNT='${OMX_ARTIFACT_WARN_COUNT}'; using 120"
    OMX_ARTIFACT_WARN_COUNT=120
    ;;
esac

case "${OMX_KNOWLEDGE_DRAFT_WARN_COUNT}" in
  ''|*[!0-9]*)
    say_warn "invalid OMX_KNOWLEDGE_DRAFT_WARN_COUNT='${OMX_KNOWLEDGE_DRAFT_WARN_COUNT}'; using 50"
    OMX_KNOWLEDGE_DRAFT_WARN_COUNT=50
    ;;
esac

ensure_dir() {
  local path="$1"

  if [ -d "$path" ]; then
    say_pass "directory exists: ${path}"
    return
  fi

  if [ "$FIX" -eq 1 ]; then
    mkdir -p "$path"
    say_fix "created directory: ${path}"
  else
    say_warn "directory missing: ${path}"
    suggest "./scripts/automation-doctor.sh --fix"
  fi
}

check_required_file() {
  local path="$1"

  if [ -f "$path" ]; then
    say_pass "required file exists: ${path}"
    return
  fi

  say_fail "required file missing: ${path}"
  if [ "${IN_AI_LAB:-0}" -eq 1 ]; then
    suggest "./scripts/automation-doctor.sh --fix"
  else
    suggest "ai-auto setup"
  fi
}

check_executable() {
  local path="$1"

  if [ ! -f "$path" ]; then
    return
  fi

  if [ -x "$path" ]; then
    say_pass "script is executable: ${path}"
    return
  fi

  if [ "$FIX" -eq 1 ]; then
    chmod +x "$path"
    say_fix "made script executable: ${path}"
  else
    say_fail "script is not executable: ${path}"
    suggest "./scripts/automation-doctor.sh --fix"
    suggest "chmod +x scripts/*.sh"
  fi
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

check_tool_adoption() {
  local name="$1"
  local adoption_state="$2"
  local severity="$3"
  local next_gate="$4"

  if command -v "$name" >/dev/null 2>&1; then
    say_pass "tool adoption: ${name} state=${adoption_state} next=${next_gate}"
  elif [ "$severity" = "fail" ]; then
    say_fail "tool adoption missing: ${name} state=${adoption_state} next=${next_gate}"
    suggest "install ${name} and ensure it is on PATH"
  else
    say_warn "tool adoption optional missing: ${name} state=${adoption_state} next=${next_gate}"
    suggest "install ${name} if this workflow needs it"
  fi
}

check_python3_version() {
  if ! command -v python3 >/dev/null 2>&1; then
    return
  fi

  if python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
    say_pass "python3 version is >= 3.9"
  else
    say_fail "python3 version must be >= 3.9 for scripts/knowledge-notes.py"
    suggest "install Python 3.9 or newer"
  fi
}

command_help_supports() {
  local help_text="$1"
  local flag="$2"

  printf '%s\n' "$help_text" | grep -Eq "(^|[^[:alnum:]_-])${flag}($|[^[:alnum:]_-])"
}

command_help_text() {
  local command_name="$1"
  local output=""

  if command -v timeout >/dev/null 2>&1; then
    output="$(timeout 10 "$command_name" --help 2>&1 || true)"
    if [ -n "$output" ]; then
      printf '%s\n' "$output"
      return
    fi
    output="$(timeout 10 "$command_name" help 2>&1 || true)"
    if [ -n "$output" ]; then
      printf '%s\n' "$output"
      return
    fi
    output="$(timeout 10 "$command_name" -h 2>&1 || true)"
    printf '%s\n' "$output"
    return
  fi

  output="$("$command_name" --help 2>&1 || true)"
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
    return
  fi
  output="$("$command_name" help 2>&1 || true)"
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
    return
  fi
  "$command_name" -h 2>&1 || true
}

check_gemini_cli_capabilities() {
  local gemini_command gemini_help prompt_mode_supported=0

  gemini_command="${GEMINI_REVIEW_COMMAND:-agy}"

  if ! command -v "$gemini_command" >/dev/null 2>&1; then
    return
  fi

  gemini_help="$(command_help_text "$gemini_command")"
  if [ -z "$gemini_help" ]; then
    say_warn "Gemini help output unavailable; non-interactive review mode could not be inspected"
    suggest "run ${gemini_command} --help in an interactive terminal"
    return
  fi

  if command_help_supports "$gemini_help" "--prompt"; then
    say_pass "Gemini supports non-interactive prompt mode (--prompt)"
    prompt_mode_supported=1
  else
    say_warn "Gemini --prompt support not detected; review may fall back to stdin and can be affected by auth prompts"
    suggest "check Gemini CLI version or use REVIEW_EXECUTION_MODE=external when Gemini hangs"
  fi

  if command_help_supports "$gemini_help" "--approval-mode"; then
    say_pass "Gemini supports approval mode control"
  elif [ "$prompt_mode_supported" -eq 1 ]; then
    say_info "Gemini optional approval mode flag not detected; review can still run, but interactive approvals may require external mode"
  else
    say_warn "Gemini approval mode flag not detected; CLI may request interactive approvals"
  fi

  if command_help_supports "$gemini_help" "--skip-trust"; then
    say_pass "Gemini supports skip-trust flag"
  elif [ "$prompt_mode_supported" -eq 1 ]; then
    say_info "Gemini optional skip-trust flag not detected; workspace trust prompts may require external mode"
  else
    say_warn "Gemini skip-trust flag not detected; workspace trust prompts may appear"
  fi

  if command_help_supports "$gemini_help" "--output-format"; then
    say_pass "Gemini supports text output format control"
  elif [ "$prompt_mode_supported" -eq 1 ]; then
    say_info "Gemini optional output format flag not detected; review parsing remains artifact-checked"
  else
    say_warn "Gemini output format flag not detected; review parsing may be less predictable"
  fi

  if command_help_supports "$gemini_help" "--model"; then
    say_pass "Gemini supports explicit model selection"
  elif [ "$prompt_mode_supported" -eq 1 ]; then
    say_info "Gemini optional --model flag not detected; provider default model will be used"
  else
    say_warn "Gemini --model flag not detected; provider default model will be used"
  fi

  printf '[doctor] Gemini review timeout default: %s seconds\n' "${GEMINI_REVIEW_TIMEOUT_SECONDS:-${REVIEW_TIMEOUT_SECONDS:-300}}"
  printf '[doctor] Gemini review command: %s\n' "${gemini_command}"
  printf '[doctor] Gemini prompt argument threshold: %s bytes\n' "${GEMINI_PROMPT_ARG_MAX_BYTES:-100000}"
}

check_legacy_pointer_targets() {
  local pointer target found_pointer=0
  local pointer_files=(
    "CLAUDE.md"
    "Claude.md"
    "claude.md"
    "GEMINI.md"
    "Gemini.md"
    "gemini.md"
  )
  local target_files=(
    "AGENTS.md"
    "docs/WORKFLOW.md"
    "scripts/verify.sh"
  )

  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return
  fi

  for pointer in "${pointer_files[@]}"; do
    [ -f "$pointer" ] || continue
    if ! grep -Eq 'AGENTS\.md|docs/WORKFLOW\.md|scripts/verify\.sh' "$pointer"; then
      continue
    fi

    found_pointer=1
    for target in "${target_files[@]}"; do
      if ! grep -qF "$target" "$pointer"; then
        continue
      fi
      if [ ! -e "$target" ]; then
        say_warn "legacy pointer ${pointer} references missing target: ${target}"
        suggest "create ${target} before committing ${pointer}"
      elif ! git ls-files --error-unmatch "$target" >/dev/null 2>&1; then
        say_warn "legacy pointer ${pointer} references untracked target: ${target}"
        suggest "git add ${pointer} ${target}"
      fi
    done
  done

  if [ "$found_pointer" -eq 0 ]; then
    say_pass "no legacy AI instruction pointer files detected"
  fi
}

check_helper_link() {
  local link_path="$1"
  local target_path="$2"

  if [ "${IN_AI_LAB:-0}" -ne 1 ]; then
    return
  fi

  if [ -L "$link_path" ] && [ "$(readlink "$link_path")" = "$target_path" ]; then
    say_pass "global helper link ok: ${link_path}"
    return
  fi

  if [ -e "$link_path" ] && [ ! -L "$link_path" ]; then
    say_warn "global helper path exists but is not a symlink: ${link_path}"
    suggest "review ${link_path} before replacing it"
    return
  fi

  if [ "$FIX" -eq 1 ]; then
    mkdir -p "$(dirname "$link_path")"
    ln -sfn "$target_path" "$link_path"
    say_fix "linked ${link_path} -> ${target_path}"
  elif [ -L "$link_path" ]; then
    say_warn "global helper link points elsewhere: ${link_path}"
    suggest "./scripts/automation-doctor.sh --fix"
  else
    say_warn "global helper link missing or points elsewhere: ${link_path}"
    suggest "./scripts/automation-doctor.sh --fix"
  fi
}

check_project_globalization() {
  # --project: a globalized project carries ZERO framework files. Confirm the baked
  # hook shims are installed and point at a valid engine path, and that .omx/ is
  # gitignored. Everything here is WARN-not-fail (an un-migrated dir is not "broken").
  local hooks_dir hook shim baked
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    hooks_dir="$(git rev-parse --git-path hooks 2>/dev/null || true)"
    case "$hooks_dir" in /*) : ;; *) hooks_dir="${ROOT}/${hooks_dir}" ;; esac
    for hook in pre-commit post-commit pre-push; do
      shim="${hooks_dir}/${hook}"
      if [ ! -f "$shim" ] || ! grep -q 'AI_AUTO shim' "$shim" 2>/dev/null; then
        say_warn "AI_AUTO ${hook} hook shim not installed: ${shim}"
        suggest "ai-auto setup"
        continue
      fi
      baked="$(sed -n 's/^AI_AUTO_HOME="\(.*\)"$/\1/p' "$shim" | head -n 1)"
      if [ -n "$baked" ] && [ -x "${baked}/hooks/${hook}" ]; then
        say_pass "AI_AUTO ${hook} hook shim points at a valid engine: ${baked}"
      else
        say_fail "AI_AUTO ${hook} hook shim points at an invalid engine path: ${baked:-<unset>}"
        suggest "ai-auto setup"
      fi
    done

    if git check-ignore -q .omx/ 2>/dev/null; then
      say_pass ".omx/ is gitignored"
    else
      say_warn ".omx/ is not gitignored"
      suggest "ai-auto setup"
    fi
  else
    say_warn "not a git repository; cannot verify hook shims or .omx gitignore"
  fi
}

printf '[doctor] checking automation readiness in %s\n\n' "$ROOT"

check_command git fail

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  say_pass "git repository detected"

  git_root="$(git rev-parse --show-toplevel)"
  if [ "$ROOT" = "$git_root" ]; then
    say_pass "running from git repository root"
  else
    say_fail "not running from git repository root: ${git_root}"
    suggest "cd ${git_root}"
    echo
    printf 'Summary: %s passed, %s warnings, %s failed' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
    if [ "$SKIP_COUNT" -gt 0 ]; then
      printf ', %s skipped' "$SKIP_COUNT"
    fi
    printf '\n'
    echo
    echo "Suggested fixes:"
    echo "  cd ${git_root}"
    exit 1
  fi

  # --attr-source=<empty-tree> disarms an in-repo .gitattributes+`.git/config` clean-filter driver
  # that `git status` would otherwise run on a stat-dirty tracked blob (RCE). Precomputed into a
  # var (not inline `$(...)`) so it is self-contained AND visible to the R9-DRIFT status guard.
  _et="$(git hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"
  if [ "$SKIP_DIRTY_CHECK" = "1" ]; then
    say_skip "working tree dirty check skipped (DOCTOR_SKIP_DIRTY_CHECK=1)"
  else
    # Fail-closed: capture git's exit code separately from its output. Under
    # concurrent multi-session load `git status` can transiently fail; swallowing
    # its exit code would leave empty output and misreport a dirty/unknown tree
    # as "clean". On any non-zero exit we WARN (never a false "clean").
    # `|| _dirty_rc=$?` keeps the failing substitution from tripping `set -e`
    # before we can inspect it (a bare assignment would abort the script).
    # --attr-source=<empty-tree> ($_et) disarms an in-repo .gitattributes clean-filter
    # RCE that `git status` would otherwise run on a stat-dirty tracked blob.
    # timeout so the probe cannot HANG on the very slow FS it is meant to diagnose (a /mnt
    # drvfs mount under load). A timeout returns 124 -> handled by the nonzero branch below
    # (warn, never a false "clean"). `command -v timeout` guard keeps it portable.
    _dirty_rc=0
    if command -v timeout >/dev/null 2>&1; then
      _dirty_out="$(timeout "${DOCTOR_GIT_STATUS_TIMEOUT:-30}" git --attr-source="$_et" status --short 2>/dev/null)" || _dirty_rc=$?
    else
      _dirty_out="$(git --attr-source="$_et" status --short 2>/dev/null)" || _dirty_rc=$?
    fi
    if [ "$_dirty_rc" -ne 0 ]; then
      # rc=124 is a timeout on the EXISTING (already-bounded) git-status probe -> a real slow-FS
      # symptom. Record it (no NEW probe) so the slow-FS advisory below can piggyback the signal.
      [ "$_dirty_rc" -eq 124 ] && _slowfs_git_slow=1
      say_warn "unable to determine working tree state, so not reporting clean; the git status probe exited ${_dirty_rc}"
      suggest "inspect with: git status --short   (re-run when load subsides; DOCTOR_SKIP_DIRTY_CHECK=1 to skip)"
    elif [ -n "$_dirty_out" ]; then
      say_warn "working tree has uncommitted changes"
      # doctor hardens its own check with --attr-source; a plain `git status --short`
      # may differ if benign clean/EOL filters are configured. Set DOCTOR_SKIP_DIRTY_CHECK=1
      # to skip benign filter churn.
      suggest "inspect with: git status --short   (DOCTOR_SKIP_DIRTY_CHECK=1 to skip benign filter churn)"
    else
      say_pass "working tree is clean"
    fi
    unset _dirty_out _dirty_rc
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    say_pass "git remote origin is configured"
  else
    say_warn "git remote origin is not configured"
    suggest "git remote add origin <repo-url>"
  fi
else
  # Distinguish "git ABSENT" from "git PRESENT but every call FAILING". The old code always
  # said "not a git repository -> git init"; under a broken sandbox (codex >=0.142.4 panics
  # exit 101; a corrupt env exits >=128) every `git rev-parse` fails, the panic is discarded by
  # 2>/dev/null, and the operator is told to `git init` an already-fine repo -- the exact class
  # that made a broken-sandbox incident look like the agent ignoring guidelines. Capture the rc
  # and stderr and say so LOUDLY instead.
  if command -v git >/dev/null 2>&1; then
    _grp_rc=0
    _grp_err="$(git rev-parse --is-inside-work-tree 2>&1 >/dev/null)" || _grp_rc=$?
    # Disambiguate a BROKEN sandbox from a legit NON-repo. `git rev-parse` returns 128 for BOTH a
    # plain non-git directory AND a corrupt/broken repo, so the exit code alone cannot tell them
    # apart -- the old `-ge 100` branch wrongly fired the "sandbox PANIC / do NOT git init" advice
    # on a plain non-repo (rc 128 >= 100). Only claim "broken repo" when a repo actually EXISTS:
    # either a `.git` is present RIGHT HERE, or git itself can still resolve --git-dir. We do NOT
    # walk ancestors with a bare `[ -e .git ]` -- a stray/invalid `.git` in a parent (e.g. a leftover
    # /tmp/.git that real git already REJECTS) would be a false positive. A Rust/codex PANIC (exit
    # 101 and other non-128 crash codes) is a broken sandbox regardless of repo presence; git's own
    # fatal 128 with NO repo present is simply "not a git repository".
    _repo_present=0
    if [ -e "${ROOT}/.git" ] || git rev-parse --git-dir >/dev/null 2>&1; then
      _repo_present=1
    fi
    if [ "$_grp_rc" -eq 0 ]; then
      # TOCTOU: is-inside-work-tree failed at the outer guard but now succeeds. Treat as no repo.
      say_fail "current directory is not a git repository"
      suggest "git init"
    elif [ "$_repo_present" -eq 1 ]; then
      say_fail "git is PRESENT but FAILING with exit ${_grp_rc} in a repo that EXISTS (.git found) -- a broken repo/sandbox, NOT a missing repo: ${_grp_err}"
      suggest "your sandbox/environment is broken -- fix it (do NOT run 'git init'); e.g. remove a socket like docker.sock from codex writable_roots"
    elif [ "$_grp_rc" -eq 128 ]; then
      # git's own fatal AND no repo present -> a clean missing repository, handled normally.
      say_fail "current directory is not a git repository"
      suggest "git init"
    elif [ "$_grp_rc" -ge 100 ]; then
      # A non-128 crash code (101 panic, 134 abort, 139 segv, ...) with no repo -> broken sandbox.
      say_fail "git is PRESENT but FAILING with exit ${_grp_rc} -- a tool/sandbox PANIC, NOT a missing repo: ${_grp_err}"
      suggest "your sandbox/environment is broken -- fix it (do NOT run 'git init'); e.g. remove a socket like docker.sock from codex writable_roots"
    else
      say_fail "git is PRESENT but FAILING with exit ${_grp_rc} -- an environment error, not a clean missing repo: ${_grp_err}"
      suggest "fix the environment then re-run; inspect with: git rev-parse --is-inside-work-tree   ('git init' only if there is truly no repo here)"
    fi
    unset _grp_rc _grp_err _repo_present
  else
    say_fail "git is not installed"
    suggest "install git"
  fi
fi

echo
echo "[doctor] checking automation files"

ensure_dir ".omx"
ensure_dir ".omx/reviewer-state"
ensure_dir "docs"
ensure_dir "docs/research"
ensure_dir "scripts"

REQUIRED_FILES=(
  "AGENTS.md"
  "docs/CHROME_CDP_ACCESS.md"
  "docs/AI_AUTOMATION_TREND_HARDENING.md"
  "docs/research/AI_AUTOMATION_TRENDS.md"
  "docs/AI_RUNTIME_ADAPTERS.md"
  "docs/AI_MODEL_ROUTING.md"
  "docs/AUTOMATION_OPERATING_POLICY.md"
  "docs/DOMAIN_PACK_AUTHORING_GUIDE.md"
  "docs/INTERVIEW_PLAN_LAYER.md"
  "docs/OBSIDIAN_INTEGRATION.md"
  "docs/SESSION_QUALITY_PLAN.md"
  "docs/WORKFLOW.md"
  "scripts/archive-omx-artifacts.sh"
  "scripts/ai-runtime-adapter.sh"
  "scripts/audit-obsidian-vault.py"
  "scripts/benchmark-command.py"
  "scripts/todo-report.py"
  "scripts/review-gate.sh"
  "scripts/collect-review-context.sh"
  "scripts/capture-knowledge-drafts.py"
  "scripts/doc-budget.sh"
  "scripts/guidance-duplicate-report.sh"
  "scripts/discover-ai-models.sh"
  "scripts/knowledge-notes.py"
  "scripts/make-review-prompts.sh"
  "scripts/record-feedback.sh"
  "scripts/record-project-memory.sh"
  "scripts/resolve-feedback.sh"
  "scripts/validate-odoo-docs-kb.py"
  "scripts/run-ai-reviews.sh"
  "scripts/summarize-ai-reviews.sh"
  "scripts/test-review-summary.sh"
  "scripts/write-session-checkpoint.sh"
)

# Framework files live in the engine home, not in a globalized project. Only the
# engine checkout carries (and is graded on) the full engine inventory; a derived
# project ships ZERO framework files and must not be flagged for their absence.
if [ "${IN_AI_LAB:-0}" -eq 1 ]; then
  for path in "${REQUIRED_FILES[@]}"; do
    check_required_file "$path"
  done
  check_required_file "docs/AI_ROLES.md"
fi

if [ "$MODE" = "project" ]; then
  # A globalized project owns NO framework verify.sh (it is global now). Its OPTIONAL
  # real test is scripts/verify-project.sh; absence is a loud WARN (C4/F4), never a fail.
  if [ -f "scripts/verify-project.sh" ]; then
    say_pass "project verification present: scripts/verify-project.sh"
  else
    say_warn "scripts/verify-project.sh absent: project defines no verification"
    suggest "add scripts/verify-project.sh so the gate runs real project tests"
  fi
elif [ -f "scripts/verify.sh" ]; then
  say_pass "required file exists: scripts/verify.sh"
  if grep -q "VERIFY_TEMPLATE_UNCONFIGURED=1" "scripts/verify.sh"; then
    say_warn "scripts/verify.sh is still the generic onboarding placeholder"
    suggest "interview the project requirements and replace scripts/verify.sh with project-specific checks"
  fi
elif [ -f "scripts/verify.example.sh" ]; then
  say_warn "scripts/verify.sh is missing; template example exists"
  suggest "mv scripts/verify.example.sh scripts/verify.sh && chmod +x scripts/verify.sh"
else
  check_required_file "scripts/verify.sh"
fi

for path in scripts/*.sh scripts/*.py; do
  [ -e "$path" ] || continue
  check_executable "$path"
done

check_legacy_pointer_targets

if [ "$MODE" = "project" ]; then
  echo
  echo "[doctor] checking globalized project (hook shims + .omx gitignore)"
  check_project_globalization
fi

echo
echo "[doctor] checking optional runtime tools"

check_command python3 fail
check_python3_version
check_command docker warn
if [ "${IN_AI_LAB:-0}" -eq 1 ]; then
  check_tool_adoption shellcheck required_gate fail verify
else
  check_tool_adoption shellcheck optional warn verify
fi
check_tool_adoption hyperfine optional warn benchmark_capture

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    say_pass "Docker daemon is reachable"
  else
    say_warn "Docker command exists but daemon is not reachable"
    suggest "start Docker or check Docker socket permissions"
  fi
fi

check_command claude warn
check_command "${GEMINI_REVIEW_COMMAND:-agy}" warn

check_gemini_cli_capabilities

echo
echo "[doctor] checking reviewer state"

if [ -d ".omx/reviewer-state" ]; then
  disabled_count=0
  for marker in .omx/reviewer-state/*.disabled; do
    [ -e "$marker" ] || continue
    disabled_count=$((disabled_count + 1))
    reviewer="$(basename "$marker" .disabled)"
    reason="$(sed -n 's/^reason=//p' "$marker" 2>/dev/null | head -n 1)"
    details="$(sed -n 's/^details=//p' "$marker" 2>/dev/null | head -n 1)"
    disabled_at="$(sed -n 's/^disabled_at=//p' "$marker" 2>/dev/null | head -n 1)"
    source_run_id="$(sed -n 's/^source_run_id=//p' "$marker" 2>/dev/null | head -n 1)"
    next_action="$(sed -n 's/^next_action=//p' "$marker" 2>/dev/null | head -n 1)"
    reset_hint="$(sed -n 's/^reset_hint=//p' "$marker" 2>/dev/null | head -n 1)"
    if [ -n "$reason" ]; then
      say_warn "reviewer disabled: ${reviewer} (${reason})"
    else
      say_warn "reviewer disabled: ${reviewer}"
    fi
    [ -n "$details" ] && printf '       details: %s\n' "$details"
    [ -n "$disabled_at" ] && printf '       disabled_at: %s\n' "$disabled_at"
    [ -n "$source_run_id" ] && printf '       source_run_id: %s\n' "$source_run_id"
    [ -n "$next_action" ] && printf '       next_action: %s\n' "$next_action"
    if [ -n "$reset_hint" ]; then
      printf '       reset_hint: %s\n' "$reset_hint"
      suggest "$reset_hint"
    fi
  done

  if [ "$disabled_count" -eq 0 ]; then
    say_pass "no disabled reviewers recorded"
  else
    suggest "RESET_DISABLED_AI_REVIEWERS=all ./scripts/review-gate.sh"
  fi
else
  say_warn "reviewer state directory is missing"
  suggest "./scripts/automation-doctor.sh --fix"
fi

echo
echo "[doctor] checking .omx session artifacts"

if [ -d ".omx" ]; then
  for artifact_dir in \
    ".omx/review-results" \
    ".omx/review-context" \
    ".omx/review-prompts" \
    ".omx/model-routing" \
    ".omx/external-review"
  do
    if [ ! -d "$artifact_dir" ]; then
      say_skip "session artifact directory missing: ${artifact_dir}"
      continue
    fi

    artifact_count="$(find "$artifact_dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$artifact_count" -gt "$OMX_ARTIFACT_WARN_COUNT" ]; then
      if [ "$FIX" -eq 1 ] && [ "$artifact_dir" = ".omx/review-results" ] && [ -x "$AH/archive-omx-artifacts.sh" ]; then
        if OMX_REVIEW_ARCHIVE_THRESHOLD="$OMX_ARTIFACT_WARN_COUNT" "$AH/archive-omx-artifacts.sh"; then
          say_fix "archived old review artifacts from ${artifact_dir}"
        else
          say_warn "review artifact archive failed for ${artifact_dir}"
          suggest "OMX_REVIEW_ARCHIVE_THRESHOLD=${OMX_ARTIFACT_WARN_COUNT} ./scripts/archive-omx-artifacts.sh --dry-run"
        fi
      else
        say_warn "session artifact directory has ${artifact_count} files: ${artifact_dir}"
        suggest "./scripts/archive-omx-artifacts.sh --dry-run"
        suggest "./scripts/automation-doctor.sh --fix"
      fi
    else
      say_pass "session artifact directory size ok: ${artifact_dir} (${artifact_count} files)"
    fi
  done

  knowledge_drafts_dir=".omx/knowledge/drafts"
  if [ -d "$knowledge_drafts_dir" ]; then
    knowledge_draft_count="$(find "$knowledge_drafts_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$knowledge_draft_count" -gt "$OMX_KNOWLEDGE_DRAFT_WARN_COUNT" ]; then
      say_warn "knowledge draft directory has ${knowledge_draft_count} notes: ${knowledge_drafts_dir}"
      suggest "knowledge-collect --project \"$(pwd)\""
      suggest "triage duplicate repeat_key notes before vault push"
    else
      say_pass "knowledge draft directory size ok: ${knowledge_drafts_dir} (${knowledge_draft_count} notes)"
    fi
  else
    say_skip "knowledge draft directory missing: ${knowledge_drafts_dir}"
  fi

  latest_manifest="$(ls -t .omx/review-results/review-run-*.md 2>/dev/null | head -n 1 || true)"
  if [ -n "$latest_manifest" ]; then
    say_pass "latest review run manifest: ${latest_manifest}"
  else
    say_skip "no review run manifest recorded yet"
  fi
else
  say_warn ".omx directory is missing"
  suggest "./scripts/automation-doctor.sh --fix"
fi

echo
echo "[doctor] checking ai-lab helper links"

if [ "${IN_AI_LAB:-0}" -eq 1 ] && [ -n "$HOME_DIR" ] && [ "$HOME_READY" -eq 1 ]; then
  check_helper_link "${HOME_DIR}/bin/AI_AUTO" "${ROOT}/tools/ai-home"
  check_helper_link "${HOME_DIR}/bin/ai-auto" "${ROOT}/tools/ai-auto"
  check_helper_link "${HOME_DIR}/bin/ai-home" "${ROOT}/tools/ai-home"
  check_helper_link "${HOME_DIR}/bin/aiinit" "${ROOT}/tools/ai-auto"
  check_helper_link "${HOME_DIR}/bin/ai-register" "${ROOT}/tools/ai-register"
  check_helper_link "${HOME_DIR}/bin/ai-domain-pack" "${ROOT}/tools/ai-domain-pack"
  check_helper_link "${HOME_DIR}/bin/ai-gstack-contract" "${ROOT}/tools/ai-gstack-contract"
  check_helper_link "${HOME_DIR}/bin/ai-refactor-scan" "${ROOT}/tools/ai-refactor-scan"
  check_helper_link "${HOME_DIR}/bin/ai-rebuild-plan" "${ROOT}/tools/ai-rebuild-plan"
  check_helper_link "${HOME_DIR}/bin/ai-split-plan" "${ROOT}/tools/ai-split-plan"
  check_helper_link "${HOME_DIR}/bin/ai-split-dry-run" "${ROOT}/tools/ai-split-dry-run"
  check_helper_link "${HOME_DIR}/bin/ai-split-apply" "${ROOT}/tools/ai-split-apply"
  check_helper_link "${HOME_DIR}/bin/ai-plan-status" "${ROOT}/tools/ai-plan-status"
  check_helper_link "${HOME_DIR}/bin/ai-interview-record" "${ROOT}/tools/ai-interview-record"
  check_helper_link "${HOME_DIR}/bin/ai-plan-review" "${ROOT}/tools/ai-plan-review"
  check_helper_link "${HOME_DIR}/bin/ai-plan-export" "${ROOT}/tools/ai-plan-export"
  check_helper_link "${HOME_DIR}/bin/feedback-collect" "${ROOT}/tools/feedback-collect"
  check_helper_link "${HOME_DIR}/bin/feedback-resolve" "${ROOT}/tools/feedback-resolve"
  check_helper_link "${HOME_DIR}/bin/knowledge-collect" "${ROOT}/tools/knowledge-collect"
  check_helper_link "${HOME_DIR}/bin/workspace-scan" "${ROOT}/tools/workspace-scan"
  check_helper_link "${HOME_DIR}/bin/ai-agent-watchdog" "${ROOT}/tools/ai-agent-watchdog"
  check_helper_link "${HOME_DIR}/bin/micro-work" "${ROOT}/tools/micro-work"
  check_helper_link "${HOME_DIR}/bin/ai-worktree" "${ROOT}/tools/ai-worktree"
  check_helper_link "${HOME_DIR}/bin/ai-tmux-worktree" "${ROOT}/tools/ai-tmux-worktree"
  check_helper_link "${HOME_DIR}/bin/ai-project-profile" "${ROOT}/tools/ai-project-profile"
  check_helper_link "${HOME_DIR}/bin/knowledge-capture" "${ROOT}/tools/knowledge-capture"
  check_helper_link "${HOME_DIR}/bin/knowledge-retrieve" "${ROOT}/tools/knowledge-retrieve"
  check_helper_link "${HOME_DIR}/bin/ai-kb-retrieval-hook" "${ROOT}/tools/ai-kb-retrieval-hook"
  case ":${PATH}:" in
    *":${HOME_DIR}/bin:"*)
      say_pass "global helper directory is on PATH: ${HOME_DIR}/bin"
      ;;
    *)
      say_warn "global helper directory is not on PATH: ${HOME_DIR}/bin"
      suggest 'export PATH="$HOME/bin:$PATH"'
      ;;
  esac
elif [ "${IN_AI_LAB:-0}" -eq 1 ] && [ -n "$HOME_DIR" ]; then
  say_warn "HOME directory does not exist; ai-lab helper link checks skipped: ${HOME_DIR}"
  suggest "set HOME to an existing user directory"
elif [ "${IN_AI_LAB:-0}" -eq 1 ]; then
  say_warn "HOME is not set; ai-lab helper link checks skipped"
else
  say_pass "not running inside ai-lab source checkout; helper link checks skipped"
fi

echo
echo "[doctor] checking cross-CLI operational hygiene (advisory; read-only; warn-only)"

# (a) codex profile sanity: a NON-directory (e.g. a docker.sock socket) listed as a
# sandbox_workspace_write writable_root PANICS codex >=0.142.4 (the exact incident class). Purely
# read-only; skip silently when the config is absent. awk captures a single- OR multi-line
# writable_roots array; each quoted path that EXISTS but is not a directory is flagged.
check_codex_writable_roots() {
  local cfg="$1" p prog
  # `-f` (follows symlinks; true only for REGULAR files) rejects a FIFO/device/symlink-to-device,
  # so `head` below can never block reading a non-regular path.
  [ -f "$cfg" ] || return 0
  # DoS bound (the sibling sqlite check already uses `timeout 5`; this parse had NONE): cap the
  # bytes and lines fed to awk (a symlink-to-huge or a 120 MB config reads at most the cap), cap
  # the number of elements (awk exits after MAXEL), and wrap the parse in `timeout` so an
  # unterminated/pathological config cannot hang the doctor. On timeout (rc 124) `|| true`
  # yields empty output -> no findings, never a hang.
  local t="${DOCTOR_CODEX_PARSE_TIMEOUT:-5}"
  local bytes="${DOCTOR_CODEX_PARSE_BYTES:-262144}"
  local lines="${DOCTOR_CODEX_PARSE_LINES:-4000}"
  local elems="${DOCTOR_CODEX_PARSE_ELEMS:-256}"
  # TOML-aware element extraction: anchors on the REAL `writable_roots =` key (a leading `#`
  # comment line or a suffixed/prefixed name never matches), tracks single AND double quotes,
  # treats a `#` outside quotes as a comment to end-of-line, and ends the array only on an
  # UNQUOTED `]` -- so a `]` or `#` INSIDE a quoted value neither truncates the scan nor is
  # mistaken for a comment. Elements are the quoted strings between the opening/closing brackets.
  prog='
    BEGIN { q=""; inarr=0; started=0; depth=0; ntok=0; tok="" }
    {
      line = $0
      if (!started && !inarr) {
        if (line ~ /^[ \t]*writable_roots[ \t]*=/) {
          started = 1
          sub(/^[ \t]*writable_roots[ \t]*=/, "", line)
        } else {
          next
        }
      }
      n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1)
        if (q != "") {
          if (c == q) { if (inarr) { print tok; ntok++; if (ntok >= MAXEL) exit } q = "" }
          else { tok = tok c }
          i++; continue
        }
        if (c == "#") { break }
        if (c == "\"" || c == "\047") { q = c; tok = ""; i++; continue }
        if (c == "[") { depth++; inarr = 1; i++; continue }
        if (c == "]") { depth--; if (inarr && depth <= 0) exit; i++; continue }
        i++
      }
    }'
  {
    if command -v timeout >/dev/null 2>&1; then
      timeout "$t" awk -v MAXEL="$elems" "$prog" \
        < <(head -c "$bytes" "$cfg" 2>/dev/null | head -n "$lines") || true
    else
      awk -v MAXEL="$elems" "$prog" \
        < <(head -c "$bytes" "$cfg" 2>/dev/null | head -n "$lines") || true
    fi
  } | while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -e "$p" ] && [ ! -d "$p" ]; then
          printf 'BADROOT\t%s\n' "$p"
        fi
      done
}
if [ -n "$HOME_DIR" ] && [ -d "${HOME_DIR}/.codex" ]; then
  _codex_cfgs=()
  [ -f "${HOME_DIR}/.codex/config.toml" ] && _codex_cfgs+=("${HOME_DIR}/.codex/config.toml")
  while IFS= read -r _cfg; do [ -n "$_cfg" ] && _codex_cfgs+=("$_cfg"); done \
    < <(find "${HOME_DIR}/.codex" -maxdepth 1 -type f -name '*.config.toml' 2>/dev/null)
  for _cfg in "${_codex_cfgs[@]}"; do
    while IFS=$'\t' read -r _tag _bad; do
      [ "$_tag" = "BADROOT" ] || continue
      say_warn "codex profile ${_cfg}: writable_root '${_bad}' is not a directory (e.g. a socket) -- will PANIC codex >=0.142.4"
      suggest "in ${_cfg}, use the parent DIRECTORY (e.g. /run) as the writable_root instead of ${_bad}"
    done < <(check_codex_writable_roots "$_cfg")
  done
  unset _codex_cfgs _cfg _tag _bad

  # (b) codex log-store bloat: a large logs_2.sqlite with a high free-page ratio wastes space.
  # Guarded (needs sqlite3 + the file) and timeout-bounded; VACUUM is the reclaim.
  _codex_db="${HOME_DIR}/.codex/logs_2.sqlite"
  if [ -f "$_codex_db" ] && command -v sqlite3 >/dev/null 2>&1; then
    # `stat -L` follows a symlink so a symlinked logs_2.sqlite is sized by its TARGET (not the
    # ~30-byte link). `sqlite3 -readonly` opens read-only so the doctor never RW-opens (and never
    # creates a -wal/-shm on) the user's live db.
    _db_sz="$(stat -L -c%s "$_codex_db" 2>/dev/null || echo 0)"
    if [ "${_db_sz:-0}" -ge "${DOCTOR_CODEX_LOG_BYTES:-52428800}" ]; then
      _db_free="$(timeout 5 sqlite3 -readonly "$_codex_db" 'PRAGMA freelist_count;' 2>/dev/null || echo 0)"
      _db_total="$(timeout 5 sqlite3 -readonly "$_codex_db" 'PRAGMA page_count;' 2>/dev/null || echo 0)"
      case "${_db_free}${_db_total}" in *[!0-9]*|'') _db_free=0; _db_total=0 ;; esac
      if [ "${_db_total:-0}" -gt 0 ]; then
        _db_ratio=$(( _db_free * 100 / _db_total ))
        if [ "$_db_ratio" -ge "${DOCTOR_CODEX_LOG_FREE_PCT:-25}" ]; then
          say_warn "codex log store ${_codex_db} is $((_db_sz / 1048576))MB with ${_db_ratio}% free pages; run VACUUM to reclaim space"
          suggest "sqlite3 ${_codex_db} 'VACUUM;'"
        fi
      fi
    fi
    unset _db_sz _db_free _db_total _db_ratio
  fi
  unset _codex_db
else
  say_skip "no ~/.codex directory; codex profile/log hygiene checks skipped"
fi

# (c) slow-FS project location: a repo under a Windows/drvfs mount (/mnt/<letter>/...) makes git
# operations SLOW. The cost is the SERIAL lstat of TRACKED files (preload-index), NOT an untracked
# scan -- so gitignoring runtime dirs is only a minor, lower-priority note. This environment is
# PRESERVED UNCONDITIONALLY: never advise relocating the repo. Emit the adversarially-verified
# levers instead. The classifier is an O(1) path match (no FS I/O); /mnt/wsl is Linux-native tmpfs
# (fast, NOT drvfs) so it is EXCLUDED -- matching it would be a false positive.
case "$ROOT" in
  /mnt/wsl|/mnt/wsl/*|/mnt/wslg|/mnt/wslg/*)
    : ;;  # Linux-native tmpfs under WSL -- fast; not a Windows/drvfs mount.
  /mnt/*)
    _slowfs_msg="project is on a Windows/drvfs mount (${ROOT}); git operations will be SLOW"
    # Piggyback the EXISTING timeout-bounded git-status probe (rc=124 above) as a confirming
    # symptom -- no new/unbounded probe is run here.
    if [ "${_slowfs_git_slow:-0}" -eq 1 ]; then
      _slowfs_msg="${_slowfs_msg} (the timeout-bounded git-status probe above TIMED OUT, confirming the slow FS)"
    fi
    say_warn "$_slowfs_msg"
    unset _slowfs_msg
    # Correct, verified levers -- and NOTE: this drive path stays as-is; do NOT change it off the drive.
    suggest "git config core.untrackedCache true   (caches untracked-dir stat results; minor but real)"
    suggest "check whether this /mnt drive is a MAPPED / NETWORK (SMB) drive -- that latency is the likely cause; prefer a local (non-network) drive"
    suggest "add a Windows Defender real-time-scan EXCLUSION for the repo path AND the WSL distro (Settings > Virus & threat protection > Exclusions)"
    suggest "do NOT rely on fsmonitor here (unsupported on this WSL git build); the drive path is preserved -- keep the repo in place"
    suggest "(lower priority) ensure large runtime dirs are gitignored so they are not walked"
    ;;
esac

echo
printf 'Summary: %s passed, %s warnings, %s failed' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
if [ "$FIX_COUNT" -gt 0 ]; then
  printf ', %s fixed' "$FIX_COUNT"
fi
if [ "$SKIP_COUNT" -gt 0 ]; then
  printf ', %s skipped' "$SKIP_COUNT"
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
