#!/usr/bin/env bash
# Per-REPO identity for the validation harness. Two DIFFERENT projects must not share the
# postgres container / volume / base DB, so each derives a stable docker-safe slug from
# its repo IDENTITY and exports it as COMPOSE_PROJECT_NAME (docker compose then prefixes
# the container, network, AND named volume with it -> full per-project isolation, no
# compose-file edit needed). The slug is also used to make the base-rebuild lock
# per-project. Same repo -> same slug (reuses its base) EVEN across different `git
# worktree` checkouts of that repo (RED3-4: keying on the worktree's own absolute path
# made every new `aiwt` worktree of the SAME repo pay its own ~10min warm-base rebuild,
# for a byte-identical base a sibling worktree had already built); different repos ->
# different slug (own stack), because they never share a git common-dir. Sourced by the
# harness entry scripts.
harness_proj_slug() {  # <project_repo> -> [a-z0-9-]{<=40}, stable, collision-resistant
  local abs identity gcd tail_src tail hash slug
  abs="$(cd "$1" 2>/dev/null && pwd -P)" || abs="$1"
  # Repo IDENTITY, not the worktree's own path: `git --git-common-dir` resolves to the
  # ONE shared .git directory for every worktree of a clone (that is exactly what `git
  # worktree add` is for), so hashing THAT instead of $abs lets sibling worktrees of the
  # same repo share one warm base. Falls back to the path itself when $1 is not a git
  # repo (or git is unavailable) so isolation still degrades safely to the old behavior.
  gcd="$(git -C "$abs" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -n "$gcd" ]; then
    identity="$(cd "$gcd" 2>/dev/null && pwd -P)" || identity="$gcd"
  else
    identity="$abs"
  fi
  # human-readable tail (cosmetic): derived from the IDENTITY, not the worktree's own
  # basename (worktrees of one repo each have their own directory name) -- otherwise two
  # worktrees of the same repo would still get different slugs despite the same hash.
  case "$identity" in
    */.git) tail_src="${identity%/.git}" ;;
    *)      tail_src="$identity" ;;
  esac
  tail="$(printf '%s' "${tail_src##*/}" \
            | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
            | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9' '-' \
            | sed 's/-\{1,\}/-/g; s/^-//; s/-$//')"
  # cksum (POSIX, decimal — no hex letters) over the repo identity carries the uniqueness
  hash="$(printf '%s' "$identity" | cksum | cut -d' ' -f1)"
  slug="h-${tail:-p}-${hash}"          # leading 'h-' forces a [a-z] first char
  printf '%s' "$slug" | cut -c1-40
}
