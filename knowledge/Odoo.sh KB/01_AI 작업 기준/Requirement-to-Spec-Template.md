# Requirement To Spec Template

Status: promoted
Use when an Odoo customization request needs a concrete spec or implementation plan.

## 1. Business Goal And User Scenario

- Goal:
- Users:
- Current pain:
- Desired result:

## 2. Confirmed Inputs And Missing Inputs

| Input | Status | Evidence |
| --- | --- | --- |
| Odoo version | missing |  |
| Standard schema snapshot | missing |  |
| Project schema snapshot | missing |  |
| Target module | missing |  |
| Target users/groups | missing |  |

## 3. Source-Backed Rules Used

| Rule | Source |
| --- | --- |
| Schema-first design | Local policy + schema snapshots |
| Security review for new model/field | [[Source-Index#Rule-To-Source Mapping]] |

## 4. Schema Lookup Table

| Candidate | Type | Standard Snapshot | Project Snapshot | Decision |
| --- | --- | --- | --- | --- |
|  |  | not checked | not checked | defer |

If a required project snapshot lookup is not complete, final status MUST be `schema-pending`; do not produce implementation-ready code.

## 5. Model And Field Reuse Analysis

- Existing model candidates:
- Existing field candidates:
- Reuse decision:
- Why reuse is insufficient, if creating new schema:

## 6. New Field Or Model Design

| Item | Value |
| --- | --- |
| Technical name |  |
| Field/model type |  |
| Relation target |  |
| Required/index/store |  |
| Multi-company behavior |  |
| Compute dependencies |  |
| Security groups |  |

## 7. View Customization Details

| Item | Value |
| --- | --- |
| Target view external ID |  |
| Inherited view XML ID |  |
| XPath anchor |  |
| Position |  |
| Priority |  |
| Staging render check |  |

## 8. Security Details

- ACL:
- Record rule:
- Field groups:
- `sudo()` or public method risk:
- Representative users to test:

## 9. Deployment Impact

- Manifest dependency changes:
- Manifest version change:
- Data files:
- `noupdate` decision:
- Upgrade/install command or Odoo.sh action:

## 10. Performance And Multi-Company Impact

- Compute/query risk:
- Batch/prefetch approach:
- Multi-company scenarios:
- Index justification:

## 11. Staging QA Checklist

| Check | Evidence | Status |
| --- | --- | --- |
| Module installs/updates |  | pending |
| View renders |  | pending |
| ACL/rules behave correctly |  | pending |
| Multi-company behavior verified |  | pending |
| Data lifecycle verified |  | pending |
| Automated Odoo tests |  | pending |

## 12. Execution Trace Table

| Step | Evidence | Status |
| --- | --- | --- |
| Requirement parsed |  | pending |
| Schema checked |  | pending |
| Reuse evaluated |  | pending |
| View checked |  | pending |
| Security checked |  | pending |
| Deployment checked |  | pending |
| Staging checked |  | pending |

## 13. Final Status

- Status: ready / schema-pending / security-pending / staging-pending / blocked
- Blockers:
- Next action:

Evidence table status values MUST be one of: `pending`, `pass`, `fail`, `blocked`, `not-applicable`. Empty evidence with `pass` or `ready` is invalid.

Navigation: [[00_Index|Back to index]] | Use after: [[Schema-Usage-Guide|Schema Usage Guide]]
