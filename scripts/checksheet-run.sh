#!/usr/bin/env bash
# Thin wrapper for scripts/checksheet-run.py (pure-core + thin-wrapper pattern,
# cf. self_demo_contracts.py). Args and fail-closed exit codes pass straight
# through: 0=all accepted, 1=a rejection, 2=bad usage/selftest failed.
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/checksheet-run.py" "$@"
