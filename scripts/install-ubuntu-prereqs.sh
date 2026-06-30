#!/usr/bin/env bash
set -euo pipefail

INSTALL_AI_CLI=0
SKIP_SYSTEM=0

usage() {
  cat <<'USAGE'
Usage: ./scripts/install-ubuntu-prereqs.sh [--install-ai-cli] [--skip-system]

Install the basic Ubuntu prerequisites for this checkout, then prepare the
repository virtual environment and global helper links.

Default mode installs only OS/repo prerequisites:
  - git, curl, ca-certificates, bash
  - python3, python3-venv, python3-pip
  - nodejs, npm
  - docker.io, plus the available Docker Compose plugin package
  - shellcheck and hyperfine for required shell lint and benchmark capture
  - Python packages from requirements.txt
  - repo helper links through ./scripts/install-global-files.sh

With --install-ai-cli, it also attempts npm global installs for:
  - @openai/codex
  - @anthropic-ai/claude-code

Antigravity CLI (`agy`) is the default Gemini review command, but it is not
installed by this npm-based helper. Install or update it through the
Antigravity-managed installer, then verify it with `agy --version`.

This script does not configure credentials, create API keys, log into AI
services, create SSH keys, or configure GitHub tokens.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-ai-cli)
      INSTALL_AI_CLI=1
      ;;
    --skip-system)
      SKIP_SYSTEM=1
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

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUDO=""
USER_NAME="${SUDO_USER:-${USER:-}}"

if [ -z "$USER_NAME" ]; then
  USER_NAME="$(id -un)"
fi

if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "[fail] sudo is required when not running as root"
    exit 1
  fi
  SUDO="sudo"
fi

run_system_install() {
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "[fail] apt-get was not found; this script targets Ubuntu/Debian systems"
    exit 1
  fi

  echo "[install] updating apt package index"
  $SUDO apt-get update

  echo "[install] installing Ubuntu prerequisites"
  $SUDO apt-get install -y \
    git curl ca-certificates bash \
    python3 python3-venv python3-pip \
    nodejs npm \
    docker.io \
    shellcheck hyperfine

  install_docker_compose_plugin

  if command -v docker >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
    if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx docker; then
      echo "[pass] user is already in the docker group"
    else
      echo "[install] adding ${USER_NAME} to the docker group"
      $SUDO usermod -aG docker "$USER_NAME"
      echo "[warn] Docker group membership requires logging out and back in"
    fi
  fi
}

install_docker_compose_plugin() {
  echo "[install] installing Docker Compose plugin"

  if $SUDO apt-get install -y docker-compose-v2; then
    return 0
  fi

  echo "[warn] docker-compose-v2 package was unavailable; trying docker-compose-plugin"
  if $SUDO apt-get install -y docker-compose-plugin; then
    return 0
  fi

  echo "[warn] no Docker Compose v2 apt package was available from the enabled repositories"
  echo "       Install a Docker Compose v2 plugin manually before running ./scripts/verify.sh."
  echo "       Expected check after installation: docker compose version"
}

check_node_version_for_ai_cli() {
  if ! command -v node >/dev/null 2>&1; then
    echo "[fail] node is required for npm-based AI CLI installs"
    exit 1
  fi

  local node_major
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  case "$node_major" in
    ''|*[!0-9]*)
      node_major=0
      ;;
  esac

  if [ "$node_major" -lt 18 ]; then
    echo "[fail] Node.js 18+ is required for the AI CLI tools; found: $(node --version)"
    echo "Install a current Node.js LTS release, then rerun:"
    echo "  ./scripts/install-ubuntu-prereqs.sh --skip-system --install-ai-cli"
    exit 1
  fi
}

install_ai_cli_tools() {
  check_node_version_for_ai_cli

  if ! command -v npm >/dev/null 2>&1; then
    echo "[fail] npm is required for AI CLI installs"
    exit 1
  fi

  echo "[install] installing AI CLI packages with npm"
  echo "[install] selected npm packages: @openai/codex @anthropic-ai/claude-code"
  $SUDO npm install -g \
    @openai/codex \
    @anthropic-ai/claude-code
}

cd "$ROOT"

if [ "$SKIP_SYSTEM" -eq 0 ]; then
  run_system_install
else
  echo "[skip] system package installation skipped"
fi

echo "[install] preparing Python virtual environment"
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt

echo "[install] installing repo global helper links"
"${ROOT}/scripts/install-global-files.sh"

if [ "$INSTALL_AI_CLI" -eq 1 ]; then
  install_ai_cli_tools
else
  echo "[skip] AI CLI package installation skipped"
  echo "       Rerun with --install-ai-cli after confirming Node.js 18+ is available."
fi

echo
echo "[done] Ubuntu prerequisites and repository setup completed."
echo "Next checks:"
echo "  ./scripts/bootstrap-ai-lab.sh"
echo "  ./scripts/automation-doctor.sh"
echo "  ./scripts/verify.sh"
echo
echo "Manual credential steps still required for AI tools:"
echo "  codex login"
echo "  claude login"
echo "  agy"
echo "  (install agy separately with the Antigravity-managed installer if missing)"
