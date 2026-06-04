# Security Checklist

Status: promoted
Sources: [[Source-Index#Official Sources|ODOO-SECURITY-19]]

## Model Access

Every new model needs an ACL decision.

| Check | Status |
| --- | --- |
| `ir.model.access.csv` line exists for new model | pending |
| `group_id` is explicit or public access is justified | pending |
| create/read/write/unlink permissions match user role | pending |

Empty `group_id` means broad access. Use it only when intentional and documented.

## Record Rules

Record rules are required when ACL-level access is too broad for business data.

After ACLs grant access, records are allowed unless an applicable record rule restricts them. If no rule applies to a model/user operation, ACL-level access can expose all records for that operation.

For models with a nullable `company_id`, a common multi-company pattern is:

```python
['|', ('company_id', '=', False), ('company_id', 'in', company_ids)]
```

Do not apply this blindly. If the model has no `company_id`, use the correct company relation path or document why no company record rule is needed. Treat `company_ids` as the rule-domain variable for the user's allowed companies; treat `company_id` here as a model field only when that field exists.

Check:

| Check | Status |
| --- | --- |
| Company domain reviewed | pending |
| Own-record or team scope reviewed | pending |
| Portal/public exposure reviewed | pending |
| Representative users tested | pending |

## Field Groups

Sensitive fields should use field-level groups where appropriate.

Examples of sensitive fields:

- costs and margins
- approval controls
- internal notes
- payroll/accounting-related values
- integration identifiers

## `sudo()` And Public Methods

Treat these as security-sensitive:

- public model methods callable through RPC;
- controller routes using `@http.route`;
- routes with `auth='public'` or `csrf=False`;
- `sudo()` inside business logic;
- writes in onchange/compute paths;
- access checks deferred to the UI only.

Controller/RPC checks:

| Check | Status |
| --- | --- |
| Route authentication mode reviewed | pending |
| CSRF setting justified for write endpoints | pending |
| Public route data exposure reviewed | pending |
| RPC-callable methods validate access server-side | pending |

## Security Evidence Table

| Area | Evidence | Status |
| --- | --- | --- |
| ACL |  | pending |
| Record rule |  | pending |
| Field groups |  | pending |
| Multi-company |  | pending |
| Representative users |  | pending |

Status values MUST be one of: `pending`, `pass`, `fail`, `blocked`, `not-applicable`.

Navigation: [[00_Index|Back to index]] | Next: [[Staging-QA-Checklist|Staging QA Checklist]]
