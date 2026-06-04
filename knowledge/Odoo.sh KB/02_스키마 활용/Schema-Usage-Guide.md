# Schema Usage Guide

Status: promoted
Primary local policy: project schema snapshot is build-blocking evidence for AI-generated implementation-ready specs. This is a project safety gate, not an Odoo framework requirement.

## Version Rule

Use Odoo 19.0 as the confirmed KB baseline. If a future project uses another major version, re-check that version's official docs and schema snapshots before producing implementation-ready guidance for that project.

## Snapshot Inventory

Record every schema file before using it:

| Snapshot | Purpose | Version | Generated At | Status |
| --- | --- | --- | --- | --- |
| standard schema | baseline | unknown | unknown | missing |
| project schema | project runtime evidence | unknown | unknown | missing |

Snapshot evidence format:

| Field | Example |
| --- | --- |
| File | `odoo19-standard-fields.json` or project-specific snapshot file name |
| Generated at | `YYYY-MM-DD` or `unknown` |
| Odoo version | `19.0` or confirmed project version |
| Lookup query | model/field/view search term used |
| Result | found/missing/not checked plus relevant model/field names |

## Snapshot File Shape

Preferred JSON shape for schema snapshots:

```json
{
  "odoo_version": "19.0",
  "generated_at": "YYYY-MM-DD",
  "source": "standard-or-project-label",
  "models": {
    "res.partner": {
      "name": "Contact",
      "fields": {
        "company_id": {
          "type": "many2one",
          "relation": "res.company",
          "store": true,
          "compute": false,
          "related": false,
          "company_dependent": false,
          "check_company": true,
          "groups": []
        }
      }
    }
  }
}
```

If the snapshot uses CSV or another JSON shape, record the column/key mapping before using it.

## Large Snapshot Lookup

Do not paste a large schema file into an AI prompt. Query it locally and paste only the relevant rows plus the command used.

Example commands:

```bash
rg -n '"res.partner"|"company_id"' path/to/project-schema.json
jq '.models["res.partner"].fields | keys' path/to/project-schema.json
jq '.models["res.partner"].fields["company_id"]' path/to/project-schema.json
```

## Lookup Order

1. Identify business nouns and verbs from the requirement.
2. Translate them into candidate Odoo models, fields, relations, and views.
3. Search the standard schema snapshot.
4. Search the project schema snapshot.
5. Decide reuse, extend, create, or defer.

## Candidate Discovery

Check these properties where the snapshot includes them:

- model technical name
- display name
- `_rec_name`
- field technical name
- field type
- relation target
- `compute`
- `store`
- `related`
- `company_dependent`
- `check_company`
- `groups`

## Reuse Decision

| Result | Action |
| --- | --- |
| Existing field matches the need | Reuse it and explain why. |
| Existing relation can represent the need | Reuse relation before adding a duplicate link. |
| Similar field exists but semantics differ | Explain why reuse is unsafe. |
| No project snapshot is available | Stop at `schema-pending`. |
| No existing field/model fits | Propose new schema with justification. |

## Relationship Checks

- `Many2one`: confirm the target model and company consistency.
- `One2many`: confirm the inverse field exists.
- `Many2many`: confirm whether a relation already models the same business link.

## Blocking Conditions

Stop before implementation-ready output when:

- project schema snapshot is missing;
- candidate model lookup was not performed;
- candidate field lookup was not performed;
- proposed relation target is unknown;
- proposed field duplicates a standard/project field without a written reason.

## Minimal Evidence Table

| Candidate | Lookup Query | Result | Decision |
| --- | --- | --- | --- |
|  |  |  |  |

Status values for related evidence tables MUST be one of: `pending`, `pass`, `fail`, `blocked`, `not-applicable`.

Navigation: [[00_Index|Back to index]] | Next: [[Field-Design-Guide|Field Design Guide]]
