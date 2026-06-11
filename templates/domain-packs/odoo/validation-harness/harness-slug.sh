#!/usr/bin/env bash
# Per-PROJECT identity for the validation harness. Two DIFFERENT projects must not share
# the postgres container / volume / base DB, so each derives a stable docker-safe slug
# from its repo path and exports it as COMPOSE_PROJECT_NAME (docker compose then prefixes
# the container, network, AND named volume with it -> full per-project isolation, no
# compose-file edit needed). The slug is also used to make the base-rebuild lock
# per-project. Same project -> same slug across sessions (reuses its own base); different
# projects -> different slug (own stack). Sourced by the harness entry scripts.
harness_proj_slug() {  # <project_repo> -> [a-z0-9-]{<=40}, stable, collision-resistant
  local abs tail hash slug
  abs="$(cd "$1" 2>/dev/null && pwd -P)" || abs="$1"
  # human-readable tail (cosmetic): basename, transliterate/drop non-ascii, -> dashes
  tail="$(printf '%s' "${abs##*/}" \
            | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
            | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9' '-' \
            | sed 's/-\{1,\}/-/g; s/^-//; s/-$//')"
  # cksum (POSIX, decimal — no hex letters) over the absolute path carries the uniqueness
  hash="$(printf '%s' "$abs" | cksum | cut -d' ' -f1)"
  slug="h-${tail:-p}-${hash}"          # leading 'h-' forces a [a-z] first char
  printf '%s' "$slug" | cut -c1-40
}
