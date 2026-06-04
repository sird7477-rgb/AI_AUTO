# View Customization Guide

Status: promoted
Sources: [[Source-Index#Official Sources|ODOO-VIEWS-19]]

## Default Approach

Use inherited views for customization. Do not edit upstream/base views directly.

## Required View Spec

| Item | Required |
| --- | --- |
| Target view external ID | yes |
| Inherited view XML ID | yes |
| XPath anchor | yes |
| Position | yes |
| Priority | yes, when ordering matters |
| Staging render evidence | yes |

## XPath Rules

Prefer semantic anchors that are unique in the resolved target view. If a field appears more than once, qualify it with a stable parent, group, page, or other surrounding context instead of relying on a broad `//field[@name='...']` match.

Example anchor:

```xml
<xpath expr="//field[@name='partner_id']" position="after">
    ...
</xpath>
```

Avoid positional-only anchors:

```xml
<!-- Avoid -->
<xpath expr="//form/sheet/group[1]/field[2]" position="after">
    ...
</xpath>
```

Use `hasclass()` only in Odoo view/QWeb inheritance XPath contexts that support Odoo's XPath extension; do not assume it works in generic XML tooling.

```xml
<xpath expr="//div[hasclass('o_row')]" position="inside">
    ...
</xpath>
```

## Failure Handling

If an XPath target is missing in staging:

1. Stop the deployment handoff.
2. Record target view, inherited view, and failing XPath.
3. Re-check upstream view changes.
4. Replace the anchor with a more stable model/view fact.

## Staging Render Checks

| View | User Group | Expected Result | Status |
| --- | --- | --- | --- |
| form |  | renders without traceback | pending |
| list |  | renders without traceback | pending |
| search |  | filters/grouping work | pending |

Status values MUST be one of: `pending`, `pass`, `fail`, `blocked`, `not-applicable`.

Navigation: [[00_Index|Back to index]] | Next: [[Security-Checklist|Security Checklist]]
