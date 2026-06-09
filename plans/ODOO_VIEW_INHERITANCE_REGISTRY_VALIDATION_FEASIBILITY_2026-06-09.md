# Odoo View-Inheritance Local Pre-Validation — Feasibility Review (2026-06-09)

Source queue item: `odoo:view-inheritance-registry-validation-required` (high,
failure_pattern, **open**) in `/root/workspace/ai-lab/.omx/feedback/queue.jsonl`.
Origin: JW Odoo purchase-bill build 33238937; commit 372b06c added an invalid
`account.view_in_invoice_tree` `state` selector. Local validation only ran XML
syntax checking, passed, and odoo.sh registry load then failed on the view
inheritance, aborting DB init.

This document is a feasibility review only. No gate is implemented yet; the
follow-up is tracked as a later-gated backlog row (see
`plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md`).

## 1. Root cause: why static XML checking cannot catch this

Odoo view inheritance resolves xpath/field selectors against the **combined
arch** of the parent view (base view + every inheriting module's contribution),
resolved at **registry load** against the model's actual fields. A standalone XML
parser (`ET.parse`) has none of: the parent arch, the model field list, or the
module inheritance order. Selector validity ("does `<field name='state'>` exist
as an anchorable element in the combined parent arch?") is therefore inherently a
registry-time check. This is exactly why Odoo ships the check inside the
framework's registry load, not as a linter — it is a resolution-time problem and
**no static tool can fully substitute. The validator is Odoo itself.**

## 2. Feasibility of the proposed three-tier approach

| Tier | Feasible? | Verdict |
|------|-----------|---------|
| 1. Static checks (label/for vs removed field, ban string selectors, risky-selector denylist) | Yes, but **advisory only** | Catches same-file `position="replace"` + dangling `<label for>`, fragile text/string xpath, denylisted selectors. **Misses cross-module combined-arch dependencies (the actual incident).** Never completion evidence. |
| 2. Registry/module update on a test DB (`-u module --stop-after-init`) | Yes, **the only complete detection** | Already documented in `templates/domain-packs/odoo/verify-patterns.md`. Requires Odoo 19 runtime + addons (enterprise for `account.*`) + Postgres + exact dependency set. |
| 3. View-only smoke (odoo shell / fields_view_get / combined arch) | Partial — **does not remove the runtime dependency** | Combined-arch validation still needs a booted registry with the parent + inheriting modules installed. Effectively Tier 2 scoped to incremental `-u` on a warm DB for speed, not a dependency-free check. |

## 3. The one unavoidable conclusion

Reliable pre-detection requires running the **Odoo standard source as a registry**
(not merely reading the source files). "Reading" the parent arch statically is an
approximation with gaps (combined arch, conditional elements via groups/active,
version drift, other modules). Tier 2 and Tier 3 share the same dependency and
differ only in speed/scope.

### Critical caveat — parity
Even Tier 2/3 only catches what its installed module combination exercises. If
odoo.sh installs enterprise/localization modules the local DB does not, a local
pass can still fail on odoo.sh. Gate reliability == **module-set + point-release
parity with the odoo.sh build.** Without parity, "local green" is false
confidence.

## 4. Can Obsidian KB data infer it? — No (necessary-condition only)

The `Odoo19_Docs_KB` baseline holds **documentation/manual**, not standard view
arch XML. It can confirm the *necessary* layer — model/field existence and type,
version renames/deprecations, documented inheritance patterns — which catches
typos and missing fields. It **cannot** capture the view-anchor / combined-arch
truth, because (a) standard view arch is implementation detail not in the docs,
and (b) combined arch depends on the runtime module set absent from any docs
snapshot. Per `ST-P1-49` the KB is also explicitly **non-authoritative** for
schema/verification, so it must not become a gate. Correct use: upstream
**prevention** (better authoring context so fragile anchors are not written) and
**review-prompt enrichment**, plus an advisory necessary-condition pre-filter —
never a substitute for registry load. Remember: model field existence ≠ view
anchor existence (the exact gap in this incident).

## 5. Where registry load can run (it need not be a local full install)

| Location | How standard source is provided | Local install | Notes |
|----------|--------------------------------|---------------|-------|
| odoo.sh staging/dev branch | already present (incl. enterprise) | none | push → its build does registry load; validation delegated |
| Docker image (`odoo:19` + postgres) | packaged in the image | minimal | the domain-pack compose `-u` pattern; enterprise needs mounted addons |
| CI runner | Docker / source checkout | CI only | automation of the Docker path |
| Local full install | manual clone/setup | full | most control, heaviest |

Minimum requirement is "run `-u module --stop-after-init` once where standard
source + Postgres exist" — that place can be local, container, CI, or odoo.sh.

## 6. Docker image recipe (for the local/CI path)

Base form (community modules) — mount custom addons, no custom Dockerfile:

```yaml
# docker-compose.validate.yml
services:
  db:
    image: postgres:16
    environment: { POSTGRES_DB: postgres, POSTGRES_USER: odoo, POSTGRES_PASSWORD: odoo }
    tmpfs: [/var/lib/postgresql/data]          # disposable DB
  odoo:
    image: odoo:19                              # standard source included
    depends_on: [db]
    environment: { HOST: db, USER: odoo, PASSWORD: odoo }
    volumes:
      - ./custom_addons:/mnt/extra-addons:ro
      # - ./enterprise:/mnt/enterprise:ro       # only if enterprise available
```

```bash
docker compose -f docker-compose.validate.yml run --rm odoo \
  odoo -d val_$(date +%s) \
  --addons-path=/mnt/extra-addons \
  -i your_module --stop-after-init --without-demo=all --log-level=warn
# fail when exit != 0 or logs show ParseError / "Element ... cannot be located" /
# "Field ... does not exist"
```

Custom Dockerfile only when extra pip/system deps are needed:

```dockerfile
FROM odoo:19
USER root
RUN pip3 install --no-cache-dir <deps>
USER odoo
```

Enterprise (this incident's real gate): `account.view_in_invoice_tree` is an
enterprise view, absent from the community image. Obtain enterprise source via an
Odoo **subscription** (`github.com/odoo/enterprise` branch `19.0`, or copy from
odoo.sh), mount it read-only, and add it first on the addons-path:
`--addons-path=/mnt/enterprise,/mnt/extra-addons`. **Never bake enterprise
source/credentials into an image** (license/leak). If enterprise cannot be
obtained locally, delegate validation to an **odoo.sh staging build** (enterprise
already present there).

## 7. Pre-commit alternative evidence (when no registry run is possible)

Alternative evidence reduces risk; it is **not** equivalent to "installable."
Strongest first:

1. Lightweight Docker `-u` with only the standard module that defines the view
   (≈ Tier 2 lite) — if at all possible, use this instead of the below.
2. odoo.sh staging build as the validator before merging to production.
3. (non-runtime) read the parent view source for the exact version + grep all
   inheriting installed modules to confirm the anchor exists in the combined arch.
4. (non-runtime) avoid fragile anchors by construction; anchor on an element
   guaranteed present in the base arch and record why.
5. Static lint pass — advisory only.

With only 3–5, the change must be committed with an explicit marker, e.g.
`odoo-view-registry: NOT validated locally; evidence=parent-arch source check;
risk=build-blocking until staging registry load passes`, and the **merge gate**
remains a passing staging registry load.

## 8. Recommended improvement (feasible, highest ROI first)

1. **Domain-pack rule hardening** (pure guidance; can ship via a normal Ralph):
   in `templates/domain-packs/odoo/verify-patterns.md` and `review-checklist.md`,
   state "view inheritance is registry-validated, not XML-validated; XML parse
   pass ≠ installable", and promote `-u <module> --stop-after-init` to a
   **fail-closed gate** whenever an addon `*.xml` view changed — when no runtime
   is available, mark it **build-blocking risk** (not "skipped/Not-tested") and
   require alternative evidence (section 7). Matches the queue-item resolution.
2. **CI gate before odoo.sh build**: disposable DB, install the odoo.sh-parity
   module set, `-u` changed modules, fail on any view/arch error; minimum scope =
   touched + dependent invoice/payment/move views.
3. **Optional Tier 1 static lint** as a fast advisory pre-filter.

Engineering cost is mostly **environment** (enterprise addons access, odoo.sh
parity, DB), not code: the `-u` pattern already exists in the domain pack; the
work is promoting it to a required fail-closed gate plus the "XML parse ≠
installable" rule.
