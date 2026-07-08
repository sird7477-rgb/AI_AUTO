# Derived odoo:19 image with the project's extra python deps (parity with odoo.sh).
# .deps.txt is the build-context deps bridge: prepare-base-db.sh fills it from the
# project root requirements.txt when present (the SAME file odoo.sh installs), else from
# custom-addons manifests' external_dependencies.python (+ never bakes enterprise
# source — that is mounted). Keep requirements.txt in sync via gen-requirements.sh.
#
# SUPPLY CHAIN: the FROM tag below is intentionally left as a MUTABLE tag right now (no
# `@sha256:` digest pin) -- harness-preflight.sh's harness_check_base_image_pin() prints a
# LOUD, non-blocking SUPPLY-CHAIN WARNING on every build until this is pinned, because a
# registry-side tag swap of `odoo:19` would otherwise silently change what every push
# validates against. To pin it deliberately (and stop the warning):
#   1) docker pull odoo:19
#   2) docker inspect --format='{{index .RepoDigests 0}}' odoo:19   # -> odoo:19@sha256:<64hex>
#   3) Replace the line below with: FROM odoo:19@sha256:<that digest>
#   Bump the digest deliberately (repeat the two steps above) whenever you intend to move
#   to a newer odoo:19 build -- never let it silently drift.
FROM odoo:19
USER root
COPY .deps.txt /tmp/.deps.txt
# `-s` skips pip entirely when .deps.txt is empty (e.g. a comments-only / blank
# requirements.txt reduces to no deps), so the build never fails on an empty dep list.
RUN if [ -s /tmp/.deps.txt ]; then \
      pip3 install --no-cache-dir -r /tmp/.deps.txt \
      || pip3 install --no-cache-dir --break-system-packages -r /tmp/.deps.txt ; \
    fi
USER odoo
