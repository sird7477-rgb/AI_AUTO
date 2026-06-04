# Staging QA Checklist

Status: promoted
Sources: [[Source-Index#Official Sources|ODOO-MANIFEST-19]], [[Source-Index#Official Sources|ODOO-DATA-19]], [[Source-Index#Official Sources|ODOO-TESTING-19]], [[Source-Index#Official Sources|ODOO-SH-FIRST-MODULE-19]]

## Deployment Metadata

| Check | Evidence | Status |
| --- | --- | --- |
| `__manifest__.py` version reviewed |  | pending |
| Dependencies listed |  | pending |
| XML/CSV data files listed |  | pending |
| Demo/test data separated |  | pending |

## Data Lifecycle

Use `noupdate="1"` for data intended to be created once and not overwritten on module update. Use updateable data for UI/action/view records that must receive future changes.

| Data Type | Suggested Lifecycle |
| --- | --- |
| Core default configuration | consider `noupdate="1"` |
| Security records | keep updateable unless there is an explicit preservation reason |
| Views/actions/menus | usually updateable |
| Demo data | demo-only |

Keep module-owned ACLs, record rules, groups, and menus updateable unless there is an explicit reason to preserve administrator-edited records. If security data is placed under `noupdate="1"`, document the future migration/manual-update path for fixes.

## Data Migration QA

Odoo.sh staging should prove that the change works against a production-like database copy, not only a clean install.

| Migration Risk | Required Check | Status |
| --- | --- | --- |
| New `required=True` field | Existing records have default/backfill path before constraint applies | pending |
| Changed selection/domain constraint | Existing values are mapped or migration is documented | pending |
| New relation constraint | Existing records satisfy relation/company consistency | pending |
| Data XML update | `noupdate` behavior and manual migration path reviewed | pending |
| Migration script needed | Script name, command, and staging result recorded | pending |

## Staging Checks

| Check | Representative Evidence | Status |
| --- | --- | --- |
| Module installs or updates | Odoo.sh build/update result | pending |
| Form/list/search views render | record route/view/user and observed result | pending |
| ACL and record rules behave correctly | representative users tested | pending |
| Multi-company behavior works | active company switch tested | pending |
| Compute/search performance acceptable | sample volume or query evidence | pending |
| Data lifecycle correct after update | repeated module update checked | pending |
| Production-like data migration | staging database copy validates existing data path | pending |
| Automated Odoo tests | `TransactionCase` for model/security behavior; `HttpCase` or equivalent UI-path test when controller/web flow risk exists; tags/command recorded | pending |

## Stop Conditions

Stop production handoff when:

- module update fails;
- view inheritance fails;
- permissions are broader than intended;
- schema lookup was incomplete;
- staging result is unknown.

## Final QA Summary

```text
Staging status:
Blocking issues:
Non-blocking notes:
Production handoff:
```

Status values MUST be one of: `pending`, `pass`, `fail`, `blocked`, `not-applicable`.

Navigation: [[00_Index|Back to index]] | Source: [[Source-Index|Source Index]]
