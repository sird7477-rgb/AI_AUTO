# Odoo Build-Error Analysis — Index & Classification (2026-06-10)

Source repos (session logs mined):
- `jw_dev` — `Z:\JSJEON\Project_JW\99. odoo\01. A1\jw_dev`
- `hanseoindustry` — `Z:\JSJEON\Project_JW\99. odoo\00. DEMO\hanseoindustry`

Raw verbatim dataset (one record per occurrence, no omission, duplicates kept):
- `raw/jw_dev-build-errors.jsonl` (25 records)
- `raw/hanseoindustry-build-errors.jsonl` (16 records)
- **Total: 41 build-error occurrences across 36 distinct odoo.sh build IDs.**

This INDEX is the classification/navigation layer; the `raw/*.jsonl` files hold
the verbatim `error_text`. Classification is by **primary root cause** (a case
that broke in a test or demo but whose root is an Odoo 19 rename is filed under
T1, with manifestation noted).

> **Data caveat (not an omission by analysis):** `turns-*.jsonl`
> `input_preview`/`output_preview` are hard-capped at 200 chars by the logger, so
> full verbatim stack traces beyond ~200 chars are not recoverable from these
> logs. Error class is sometimes inferred from the agent's diagnosis line. odoo.sh
> raw build logs were not in the session logs; only what the session captured.

---

## SLIM summary (by type)

| Type | Root cause | Cases | Recur | Repos | Dominant surface |
|---|---|---:|---:|---|---|
| **T1** | Odoo 19 migration drift — renamed/removed field, model, or API used with ≤18 semantics | 15 | 9 | both | code + data + view + test |
| **T2** | View-inheritance selector — xpath/`inherit_id` targets element/field absent from parent combined arch (registry-load, **passes XML parse**) | 8 | 6 | jw_dev | view XML |
| **T3** | XML view RNG/schema — Odoo 19 stricter view validator (search `<group>` wrapper, `<img>` `alt`, filter attrs) | 3 | 2 | hanseo | view XML |
| **T4** | Post-install test fixture/assumption — new/changed test breaks the build (perm fixture, wrong assertion, stale regex/message) | 7 | 1 | jw_dev | tests |
| **T5** | Demo data invalid — bad state value, NOT NULL gap, consumable-product `stock.quant`, zero-qty stock `ValidationError` | 4 | 1 | hanseo | demo XML |
| **T6** | Duplicate field name / label collision — same field on a model from two modules, or two fields sharing a label | 3 | 1 | both | models |
| **T7** | SQL NOT NULL at data load — required column inserted NULL (`binding_type`) | 1 | 0 | jw_dev | data XML |
| | **Total** | **41** | **21** | | |

Highest-leverage observations:
- **T1 (15) is the single biggest root cause** — Odoo 18→19 migration drift. Both repos. Renames: `groups_id→group_ids`, `product_uom→product_uom_id`, `uom_po_id`→removed, `get_module_resource`→removed, UoM `uom.category`/`uom.product_uom_categ_unit`→removed, product `type='product'`→`consu`+`is_storable`, `display_type` product-line test changed, `account.budget.post`/`currency_id` absent.
- **T2 (8) is the ST-P1-51 case, and the worst recurrence cluster**: the same "xpath targets a field/element not in the parent arch" mistake was re-introduced across **5 consecutive jw_dev builds on 2026-06-08** (33224080 → 33229535 → 33238937 → 33243349 → 33246822) plus 33297046/33317998 on 06-09. XML parse passed every time; only registry load caught it. This is the quantified "repeated wrong fix" pattern.
- **21/41 were recurrences** — same root cause re-broke a later build, i.e. the first fix was incomplete or re-introduced.

---

## Full case index (all 41, by type)

### T1 — Odoo 19 migration drift (15; recur 9)
| # | repo | build | recur | module / symbol | one-line |
|---|---|---|---|---|---|
| 04 | jw_dev | 33132504 | – | jw_crm test | `odoo.modules.module.get_module_resource` removed in 19 → registry load fail; switched to `importlib.resources` |
| 05 | jw_dev | 33133584 | – | jw_l10n_kr_defaults test | direct `res.users.groups_id` access vs 19 perm model → `has_group()` |
| 12 | jw_dev | 33221422 | – | jw_account_purchase_bill test | 19 product line is `display_type='product'`; `not line.display_type` filter zeroed totals |
| 16 | jw_dev | 33235962 | ✓ | jw_account_purchase_bill | same `display_type` product-line判定 re-broke |
| 21 | jw_dev | (pre-build) | – | jw_account_sale_invoice data | `uom.product_uom_categ_unit` XMLID absent in 19 |
| 22 | jw_dev | (pre-build) | ✓ | jw_account_sale_invoice data | `uom.category` model removed in 19 (UoM restructure) |
| 23 | jw_dev | 33270662 | ✓ | jw_account_sale_invoice model | `account.move.line` product-line判定 for 19 (`line_section/line_note` exclude) |
| 26 | hanseo | 32232925 | – | s_apparel model | `account.budget.post` model absent in 19 → registry fail; field removed |
| 32 | hanseo | 32236705 | ✓ | s_apparel approval_request | nonexistent `currency_id` used as currency field → registry init fail |
| 36 | hanseo | 32317414 | – | s_apparel purchase code | `product_uom` invalid on `purchase.order.line` → `product_uom_id` |
| 37 | hanseo | (pre-build) | ✓ | s_apparel demo+code | `uom_po_id` removed in 19 (demo + code) → `uom_id` |
| 38 | hanseo | 32329821 | – | s_apparel view | receipt-line field absent in 19 referenced in view → DB init abort |
| 39 | hanseo | 33272484 | ✓ | s_apparel tests | `groups_id→group_ids`, `product_uom→product_uom_id` in tests |
| 40 | hanseo | 33273299 | ✓ | s_apparel tests | test material `consu` → `stock.quant` blocked (storability semantics) |
| 41 | hanseo | 33273682 | ✓ | s_apparel tests | `product.template.type='product'` invalid in 19 → `consu`+`is_storable=True` |

### T2 — View-inheritance selector / registry-load (8; recur 6) — **ST-P1-51**
| # | repo | build | recur | module / file | one-line |
|---|---|---|---|---|---|
| 08 | jw_dev | 33211441 | – | jw_account_purchase_bill account_move_views.xml:84 | `inherit_id` ref to nonexistent XMLID → DB init fail |
| 13 | jw_dev | 33224080 | – | account_move_views.xml | `@string` used as xpath selector (not allowed in 19) |
| 14 | jw_dev | 33229535 | ✓ | account_move_views.xml | xpath targets `state` field absent from parent arch |
| 17 | jw_dev | 33238937 | ✓ | account_move_views.xml:112 | xpath element not in parent; XML parse passed, registry failed *(queue origin)* |
| 18 | jw_dev | 33243349 | ✓ | account_move_views.xml:116 | re-added xpath to absent element (regression of #14/#17) |
| 19 | jw_dev | 33246822 | ✓ | account_move_views.xml | `position=replace` on field absent from `account.view_in_invoice_tree` |
| 24 | jw_dev | 33297046 | ✓ | jw_account_sale_invoice account_move_views.xml | xpath field absent from parent `account.view_out_invoice_tree` |
| 25 | jw_dev | 33317998 | ✓ | account_payment_views.xml | xpath node absent from parent payment view |

### T3 — XML view RNG/schema (3; recur 2)
| # | repo | build | recur | file | one-line |
|---|---|---|---|---|---|
| 27 | hanseo | 32233022 | – | s_buyer_views / s_sample_request_views | kanban `<img>` missing `alt`; search `<group>` wrapper rejected by 19 RNG |
| 28 | hanseo | 32233153 | ✓ | s_sample_request_views search | `RELAXNG_ERR_NOELEM` — `<group>` wrapper in search view |
| 29 | hanseo | 32233313 | ✓ | s_expense_request_views search | `RELAXNG_ERR_ATTRVALID` — filter definition rejected |

### T4 — Post-install test fixture/assumption (7; recur 1)
| # | repo | build | recur | test | one-line |
|---|---|---|---|---|---|
| 02 | jw_dev | 33128801 | – | jw_board test_post_permission | default-on write perm; fixture created post without group |
| 03 | jw_dev | 33129361 | ✓ | jw_board test_post_permission | perm sync removed user from group on hr.employee create |
| 06 | jw_dev | 33210527 | – | jw_sale test_crm_estimate_sale_link | new defensive test had wrong assumption |
| 07 | jw_dev | 33211182 | ✓ | jw_sale test | cancel-confirm sync wrote `jw_crm_estimate_id=False` (flow/perm error) |
| 11 | jw_dev | 33212870 | – | jw_account_purchase_bill test | refund `abs(amount_residual)` assumption wrong for refund case |
| 15 | jw_dev | 33230459 | – | jw_account_purchase_bill test | VAT 10% expected but tax not applied to bill line |
| 20 | jw_dev | 33264630 | – | jw_account_purchase_bill test | `UserError` message changed; test regex not updated |

### T5 — Demo data invalid (4; recur 1)
| # | repo | build | recur | file | one-line |
|---|---|---|---|---|---|
| 30 | hanseo | 32233470 | – | s_apparel_demo.xml | demo uses stale state `to_approve`; also wrote computed `budget_limit` |
| 33 | hanseo | (demo) | – | s_apparel_demo.xml + models | consumable materials → `Quants cannot be created for consumable products` |
| 35 | hanseo | 32317316 | ✓ | s_apparel stock-setup | stock adjust called on zero-target → `Quantity or Reserved Quantity should be set` |
| 31 | hanseo | 32233470 | – | s_apparel_demo.xml | demo `s.expense.request` missing required `budget_item` (NOT NULL) |

### T6 — Duplicate field name / label collision (3; recur 1)
| # | repo | build | recur | model | one-line |
|---|---|---|---|---|---|
| 09 | jw_dev | 33211903 | – | account.move `jw_site_name` | same field defined by two modules (sale_invoice + purchase_bill) |
| 10 | jw_dev | 33212246 | ✓ | account.move `jw_site_name` | collision not fully resolved → same test re-failed |
| 34 | hanseo | 32316462 | – | s.style.bom.line | two fields share label `소요량` → ir_model warning in failing build |

### T7 — SQL NOT NULL at data load (1)
| # | repo | build | recur | file | one-line |
|---|---|---|---|---|---|
| 01 | jw_dev | 33110876 | – | jw_crm_reports.xml | `ir_act_report_xml.binding_type` inserted NULL → NOT NULL violation |
