#!/usr/bin/env bash
# Docker preflight for the harness entry scripts. Sourced (not executed) by
# validate-warm/validate-full/serve/prepare-base-db/validate-odoo right after
# HARNESS_DIR is set. The whole Lane-2 harness runs on `docker compose`, so if the
# Docker daemon is down every script otherwise dies deep inside `dc up` with a raw,
# confusing docker error. This turns that into one clear, actionable message.
#
# Common trigger: `wsl --shutdown` tears down the /mnt/wsl/docker-desktop mount and it
# only returns when Docker Desktop is (re)started — until then the /usr/bin/docker
# symlink dangles and the daemon socket is gone.

harness_require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    {
      echo "[harness] docker CLI를 찾을 수 없습니다 — Docker Desktop이 꺼져 있거나 WSL integration이 비활성입니다."
      echo "[harness]   1) Windows에서 Docker Desktop을 실행하세요 (트레이 아이콘이 완전히 \"Running\"이 될 때까지)."
      echo "[harness]   2) Docker Desktop → Settings → Resources → WSL Integration에서 이 distro를 켜세요."
      echo "[harness]   3) 'docker version' 이 Server까지 응답하면 다시 실행하세요."
    } >&2
    return 1
  fi
  if ! docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
    {
      echo "[harness] docker 데몬에 연결할 수 없습니다 — Docker Desktop이 꺼져 있거나 아직 기동 중입니다."
      echo "[harness]   Windows에서 Docker Desktop을 실행하고 완전히 \"Running\"이 된 뒤 다시 실행하세요."
      echo "[harness]   (wsl --shutdown 직후라면 /mnt/wsl/docker-desktop 마운트가 복구될 때까지 기다려야 합니다.)"
    } >&2
    return 1
  fi
}
