# Odoo Build-Error Prevention Review (2026-06-10)

Per-type prevention for the 41 occurrences classified in `INDEX.md`. Each measure
is tagged by where it lands: **[pack]** odoo domain pack guidance (mainline,
promotable via verify/review-gate like ST-P1-51), **[mainline-tool]** a new
AI_AUTO helper/lint, **[project]** project-side discipline/`verify.sh`,
**[behavior]** agent workflow rule.

## The one cross-cutting lever (covers ~35/41)

T1, T2, T3, T7 — and the load-time half of T4/T5 — share a single complete
detector: **run `-i/-u <changed module> --stop-after-init` on a disposable
Odoo 19 DB (with `--test-enable` for test-touching changes, and demo install for
demo changes) BEFORE the odoo.sh push.** Static XML parse caught none of the T2
registry errors; the registry load caught all of them. This is exactly the
ST-P1-51 fail-closed gate — the 41-case evidence (esp. the 5-build T2 recurrence
cluster) **materially strengthens the case to promote the later-gated CI/Docker
registry-load harness** (disposable DB + odoo.sh module-set/point-release parity).
Until that exists, ST-P1-51's "build-blocking risk + alternative evidence" marker
is the interim control.

Second cross-cutting lever — **[behavior] stop-and-diagnose**: 21/41 were
recurrences; T2 re-broke 5 consecutive builds with the *same* xpath mistake. After
the 2nd same-type build failure, force a root-cause/parent-arch analysis before a
3rd attempt (ST-P1-17/28 bound cycles; this data is the evidence to apply it to
build-fix loops, not just review loops).

---

## T1 — Odoo 19 migration drift (15 cases, biggest)

Root: code/data/view/test written against Odoo ≤18 semantics for a field, model,
or API that was **renamed or removed** in 19. Observed set:

| Removed / renamed | Use instead |
|---|---|
| `res.users.groups_id` (write/read direct) | `group_ids`; `has_group()` |
| `purchase.order.line.product_uom` | `product_uom_id` |
| `*.uom_po_id` | `uom_id` |
| `uom.category` model, `uom.product_uom_categ_unit` xmlid | module-owned UoM category / 19 `uom.uom` shape |
| `odoo.modules.module.get_module_resource` | `importlib.resources` |
| `product.template.type='product'` | `type='consu'` + `is_storable=True` |
| product-line判定 `not line.display_type` | exclude `display_type in ('line_section','line_note')` / check `=='product'` |
| `account.budget.post`, ad-hoc `currency_id` field | confirm model/field exists in 19 first |
| `_sql_constraints` (deprecated warn) | model-level constraint API |

Prevention:
- **[pack]** Add an "Odoo 19 rename/removal cheat-sheet" (above) to
  `templates/domain-packs/odoo/review-checklist.md`, and state in
  `verify-patterns.md`: **field/model/API existence is registry-validated, not
  memory-validated** — a name that worked in an older project may be gone in 19.
  This is the direct sibling of ST-P1-51 and the highest-value new promotion
  (15 cases). Ties to the open `odoo:schema-catalog-validation` queue item and the
  `Odoo19_Docs_KB` (necessary-condition pre-filter, non-authoritative per ST-P1-49).
- **[project]** the cross-cutting `-u --stop-after-init` gate surfaces these as
  `Invalid field X on model Y` / `Model Z does not exist` before push.

## T2 — View-inheritance selector (8 cases) — **already shipped: ST-P1-51**

Root: xpath/`inherit_id` targets an element/field absent from the parent combined
arch; XML parse passes, registry load fails.
- **[pack] DONE** — ST-P1-51 promoted the "registry-validated, not XML-validated"
  rule + fail-closed `-u` gate + build-blocking-risk marker (committed
  `347f884`). This exact class (incl. the 5-build recurrence cluster and the
  `@string`-as-selector and `position=replace`-absent-field variants) is what it
  targets.
- **[mainline-tool, later-gated]** the CI/Docker registry-load harness — now
  strongly justified; see the cross-cutting lever.
- **[behavior]** stop-and-diagnose (the 5× recurrence is the worst offender).

## T3 — XML view RNG/schema (3 cases)

Root: Odoo 19's stricter view validator rejects structures older versions allowed.
Observed: `<group>` wrapper inside a **search** view (`RELAXNG_ERR_NOELEM`),
filter attr invalid (`RELAXNG_ERR_ATTRVALID`), kanban `<img>` missing `alt`.
Prevention:
- **[pack]** Add to `review-checklist.md` an Odoo-19 view-structure note: search
  views use flat `field`/`filter`/`separator` (no `<group>` wrapper); filters need
  an explicit `name`; `<img>` needs `alt`.
- **[project]** the `-u --stop-after-init` gate catches all three at load.

## T4 — Post-install test fixture/assumption (7 cases)

Root: a new or changed test (perm fixture, assertion, stale `UserError` regex/
message, tax expectation) fails during odoo.sh's post-install test run and aborts
the build.
Prevention:
- **[project]** run the module's tests locally before push:
  `-u <module> --test-enable --test-tags=/<module> --stop-after-init`. The pack's
  "Odoo Tests" pattern already documents this; make it expected for any
  test-touching or behavior/message change.
- **[behavior]** when changing a model's behavior or a user-facing message, update
  its fixtures/assertions/regex in the *same* change (3 of 7 were stale-test drift).

## T5 — Demo data invalid (4 cases)

Root: demo XML violates current constraints — stale `selection` value
(`to_approve`), missing NOT NULL field (`budget_item`), consumable product
`stock.quant` creation, zero-qty stock `ValidationError`, writing a computed field.
Prevention:
- **[pack]** Add a demo-data rule to `verify-patterns.md`: validate demo with
  `-i <module> --stop-after-init` **with demo enabled** on a disposable DB (the
  `--without-demo=all` path hides these); demo records must satisfy current
  selection values, required (NOT NULL) fields, product storability
  (consumable ≠ stockable), and must not set computed fields.
- **[project]** demo-on install in the gate.

## T6 — Duplicate field name / label collision (3 cases)

Root: same field defined on a model by two modules (`account.move.jw_site_name`
from both sale-invoice and purchase-bill), or two fields sharing a label
(`소요량`).
Prevention:
- **[mainline-tool]** This class is **statically detectable** (unlike T2): a
  Tier-1 advisory lint that scans the addon set for (a) the same field name
  defined on the same model by >1 custom module, and (b) duplicate `string=`
  labels on one model. Good candidate for the optional Tier-1 static-lint slice
  noted in the ST-P1-51 feasibility plan — advisory, no runtime needed.
- **[pack]** review-checklist note: when extending a standard model, search the
  addon set for an existing field of that name before adding.

## T7 — SQL NOT NULL at data load (1 case)

Root: a data XML inserts a required column as NULL (`ir_act_report_xml.binding_type`).
Prevention:
- **[project]** caught by the `-i --stop-after-init` load gate.
- **[pack]** review-checklist note: data records for standard models must supply
  required (NOT NULL) columns; verify against the model's field definitions.

---

## Mainline-promotable follow-ups (verify + review-gate, like ST-P1-51)

Ranked by evidence weight:

1. **[HIGH] T1 Odoo-19 rename/removal cheat-sheet + "existence is registry-
   validated" pack rule** — 15 cases; direct sibling of ST-P1-51. New ST row,
   `advisory_contract`, domain-pack guidance. Ties to open
   `odoo:schema-catalog-validation`.
2. **[HIGH, env-cost] Promote the registry-load CI/Docker harness** (currently
   later-gated under ST-P1-51) — single gate covers ~35/41. Cost is environment
   (Odoo 19 + Postgres + enterprise addons + odoo.sh parity), not code.
3. **[MEDIUM] T6 cross-module field-name + label collision static lint** —
   statically detectable, advisory, no runtime. The Tier-1 lint slice from the
   ST-P1-51 plan.
4. **[LOW-MED] T3 search-view RNG + T5 demo-data + T7 required-field pack notes** —
   small review-checklist/verify-patterns additions.
5. **[behavior] stop-and-diagnose on the 2nd same-type build failure** — apply the
   ST-P1-17/28 cycle bound to build-fix loops; 21/41 recurrences are the evidence.

Note: all pack/lint items land in AI_AUTO mainline and can be gated like ST-P1-51;
the registry-load harness's blocker is environment access, not review. Project-side
measures (run the load/test/demo gate before push) are the immediate control the
two repos can adopt today.
