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

# SUPPLY-CHAIN advisory (LATENT residual, ops-defense game #2): the harness Dockerfile's
# base image (`FROM odoo:19`) is a MUTABLE registry tag with no `@sha256:` digest pin and
# no content-trust check anywhere -- a registry-side tag swap would silently change what
# `dc build odoo` (and every downstream validate-warm/validate-full run reusing that image)
# actually validates. Deliberately NOT a Dockerfile ARG/build-arg for the image ref (that
# would reintroduce an image-ref injection surface this harness currently has none of) and
# NOT a hardcoded, unverifiable digest guess -- instead, make the gap LOUD and advisory,
# mirroring dump-schema-catalog.sh's NOT-VALIDATED idiom: never block the build, but never
# stay silent either. Called by each entry script right before it triggers `docker compose
# build` (prepare-base-db.sh, serve.sh, validate-odoo.sh); reads the Dockerfile AS SHIPPED
# on disk, so it cannot see a build triggered against a runtime-overridden image ref.
harness_check_base_image_pin() {
  local dockerfile="${1:-${HARNESS_DIR:-.}/Dockerfile}"
  [ -f "$dockerfile" ] || return 0
  local from_line image
  while IFS= read -r from_line; do
    image="$(printf '%s\n' "$from_line" | sed -E 's/^[[:space:]]*FROM[[:space:]]+//; s/[[:space:]]+[Aa][Ss][[:space:]]+.*$//')"
    if printf '%s' "$image" | grep -qE '@sha256:[0-9a-fA-F]{64}$'; then
      continue   # digest-pinned -- recognized, no warning
    fi
    echo "[harness] SUPPLY-CHAIN WARNING: base image '${image}' is a mutable tag, not digest-pinned -- a registry-side tag swap changes what validates. Pin via FROM ${image}@sha256:<digest> (see Dockerfile header) to close this." >&2
  done < <(grep -E '^[[:space:]]*FROM[[:space:]]+' "$dockerfile" 2>/dev/null)
  return 0
}
