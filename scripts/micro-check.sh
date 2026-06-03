#!/usr/bin/env bash
set -euo pipefail

# Thin repo wrapper around `tools/micro-work validate`. Read-only: it validates a
# micro-unit JSON (default .omx/micro/current.json) and prints the report-only
# scope audit against the current changed paths. No execution, no mutation.

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "${REPO_ROOT}" ] || REPO_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
MICRO_WORK="${REPO_ROOT}/tools/micro-work"

FILE="${MICRO_WORK_FILE:-.omx/micro/current.json}"

usage() {
  cat <<'USAGE'
Usage: ./scripts/micro-check.sh [--file PATH]

Validate a MicroWork unit JSON (default: .omx/micro/current.json or MICRO_WORK_FILE)
and report scope drift against the current git changes. Read-only.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --file)
      FILE="${2:-}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[micro-check] unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

if [ ! -f "${FILE}" ]; then
  echo "[micro-check] no micro-unit file at ${FILE} (set MICRO_WORK_FILE or pass --file); nothing to check"
  exit 0
fi

changed_args=()
# Parse porcelain robustly: strip the 2-char XY status + space, take the
# post-rename path ("old -> new" -> new), and keep spaces in filenames.
while IFS= read -r line; do
  [ "${#line}" -ge 4 ] || continue
  status="${line:0:2}"
  path="${line:3}"
  # Only rename/copy entries use "old -> new"; keep the destination path.
  case "${status}" in
    *[RC]*) case "${path}" in *" -> "*) path="${path##* -> }" ;; esac ;;
  esac
  path="${path%\"}"; path="${path#\"}"
  [ -n "${path}" ] || continue
  changed_args+=(--changed "${path}")
done < <(git -C "${REPO_ROOT}" -c core.quotepath=false status --porcelain 2>/dev/null)

exec python3 "${MICRO_WORK}" validate "${FILE}" "${changed_args[@]}"
