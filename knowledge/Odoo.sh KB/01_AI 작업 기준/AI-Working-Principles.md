# AI Working Principles

Status: promoted
Source: [[Source-Index]]

## Non-Negotiable Rules

1. Separate facts, assumptions, and missing inputs.
2. Check the current project schema before proposing new models or fields.
3. Reuse existing Odoo/project fields before creating custom fields.
4. Do not produce implementation-ready guidance when schema evidence is missing.
5. Treat security, deployment, and staging checks as part of the same requirement, not as later cleanup.

## Output Status Labels

| Status | Meaning |
| --- | --- |
| `ready` | Schema, security, deployment, and staging checks are complete enough to implement. |
| `schema-pending` | Requirement can be analyzed or drafted, but schema evidence is missing; implementation-ready code MUST NOT be produced. |
| `security-pending` | Schema/design exists, but ACL/rule/field group evidence is incomplete. |
| `staging-pending` | Spec may be implementation-ready, but production handoff is blocked until staging evidence is complete. |
| `blocked` | A required input, approval, or non-schema decision is missing and prevents even a safe draft/spec answer. |

Evidence table status values MUST be one of: `pending`, `pass`, `fail`, `blocked`, `not-applicable`.

## Fact And Assumption Format

Use this block in every non-trivial Odoo customization answer:

```text
Confirmed:
- ...

Assumed:
- ...

Missing:
- ...

Final status:
- ready / schema-pending / security-pending / staging-pending / blocked
```

## Schema Lookup Is Mandatory

Every customization spec must include this table before new code is proposed:

| Candidate | Type | Standard Snapshot | Project Snapshot | Decision |
| --- | --- | --- | --- | --- |
| `model.field_name` | field/model/view | found/missing/not checked | found/missing/not checked | reuse/new/defer |

If any required item is `not checked`, final status MUST be `schema-pending` and implementation-ready code MUST NOT be produced.

Use `blocked` only when a missing approval or non-schema input prevents even a useful draft. Do not use `blocked` as a substitute for missing schema evidence.

## Execution Trace Table

When the request moves from advice to specification or implementation, include:

| Step | Evidence | Status |
| --- | --- | --- |
| Requirement parsed | Business goal and users identified | pending |
| Schema checked | Standard/project snapshots queried | pending |
| Reuse evaluated | Existing field/model decision recorded | pending |
| View checked | Target view and XPath recorded | pending |
| Security checked | ACL/rules/field groups reviewed | pending |
| Deployment checked | Manifest/data/noupdate reviewed | pending |
| Staging checked | Install/render/permission checks recorded | pending |

Each `pass` evidence entry must name the file/snapshot, lookup query, command/action, user/group where relevant, and observed result. Empty evidence with `pass` or `ready` is invalid.

## Workflow States

1. Raw evidence collected.
2. KB draft written.
3. Schema-gated sample run completed.
4. Staging-gated sample run completed.
5. Unanimous review passed.
6. AI_AUTO integration on hold.

## Source Discipline

- Use official Odoo documentation for framework rules.
- Use schema snapshots and inspected project code for project facts.
- Label local conventions as `Local policy`.
- Keep community notes as risk signals only.

Navigation: [[00_Index|Back to index]] | Next: [[Schema-Usage-Guide|Schema Usage Guide]]
