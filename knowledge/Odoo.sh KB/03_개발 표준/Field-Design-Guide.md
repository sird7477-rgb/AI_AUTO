# Field Design Guide

Status: promoted
Sources: [[Source-Index#Official Sources|ODOO-ORM-19]], [[Source-Index#Official Sources|ODOO-MULTICOMPANY-19]], [[Source-Index#Official Sources|ODOO-PERF-19]]

## Naming

| Field Type | Naming Rule |
| --- | --- |
| `Many2one` | End with `_id`. |
| `One2many` | End with `_ids`. |
| `Many2many` | End with `_ids`. |

## Type Selection

| Need | Prefer | Avoid |
| --- | --- | --- |
| Short fixed status list | `fields.Selection` | New config model |
| User-editable list | `Many2one` config model | Hard-coded `Selection` |
| Per-company value on same record | `company_dependent=True` | Duplicate company-specific records without reason |
| Cross-company relation safety | `check_company=True` where applicable | Blind relation to company-owned records |

## Compute Fields

- Declare dependencies for fields read by the compute method.
- Use `@api.depends_context('company')` when active company changes the computed value.
- Prefer batch computation patterns over per-record searches.
- Avoid stored computed fields over deep/high-cardinality relationships unless the performance tradeoff is justified.

## Related Fields

- Confirm the source relation exists in the project schema.
- Confirm the related value should be visible at the target model level.
- Avoid using related fields as a workaround for unclear ownership.
- Do not chain related fields through `One2many` or `Many2many` paths. If the value requires aggregation or traversal across x2many records, use an explicit computed field and document dependencies, store/search behavior, and performance impact.

## Indexes

Add an index only when the field is used in meaningful domains, search views, joins, or reporting paths. Do not index every new field by default.

## Field Design Checklist

| Check | Status |
| --- | --- |
| Existing field reuse evaluated | pending |
| Field type justified | pending |
| Relation target checked | pending |
| Compute dependencies listed | pending |
| Multi-company behavior decided | pending |
| Security groups reviewed | pending |
| Search/index need justified | pending |

Status values MUST be one of: `pending`, `pass`, `fail`, `blocked`, `not-applicable`.

Navigation: [[00_Index|Back to index]] | Next: [[View-Customization-Guide|View Customization Guide]]
