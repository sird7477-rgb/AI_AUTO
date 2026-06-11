# Derived odoo:19 image with the project's extra python deps (parity with odoo.sh).
# .deps.txt is the build-context deps bridge: prepare-base-db.sh fills it from the
# project root requirements.txt when present (the SAME file odoo.sh installs), else from
# custom-addons manifests' external_dependencies.python (+ never bakes enterprise
# source — that is mounted). Keep requirements.txt in sync via gen-requirements.sh.
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
