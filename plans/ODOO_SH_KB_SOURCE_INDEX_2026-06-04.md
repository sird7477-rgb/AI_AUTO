# Odoo.sh KB Source Index

Date: 2026-06-04
Status: Research index for the Odoo.sh KB plan
Primary baseline: Odoo 19.0 official documentation

## Use Rules

- Treat official Odoo documentation as authoritative baseline material.
- Treat schema snapshots and inspected project code as project-specific facts.
- Treat community material as risk discovery only; do not convert it into a hard KB rule without official docs or local evidence.
- When writing KB guide pages, cite the relevant source ID below or label the statement as `Local policy`.

## Official Sources

| ID | Source | KB Use | Notes |
| --- | --- | --- | --- |
| ODOO-ORM-19 | Odoo 19.0 ORM API: https://www.odoo.com/documentation/19.0/developer/reference/backend/orm.html | Field design, computed fields, related fields, indexing, `check_company` | Use for field attributes, stored/related field constraints, and ORM behavior. |
| ODOO-MULTICOMPANY-19 | Odoo 19.0 Multi-company Guidelines: https://www.odoo.com/documentation/19.0/developer/howtos/company.html | `company_dependent`, `@api.depends_context('company')`, multi-company QA | Confirms company-dependent values and current-company-dependent compute behavior. |
| ODOO-SECURITY-19 | Odoo 19.0 Security in Odoo: https://www.odoo.com/documentation/19.0/developer/reference/backend/security.html | ACLs, record rules, field groups, public methods, controller/RPC exposure, `sudo()` review | Confirms empty ACL `group_id` applies to every user, record rules are default-allow, and `company_ids` is available in rule domains. |
| ODOO-VIEWS-19 | Odoo 19.0 View Records: https://www.odoo.com/documentation/19.0/developer/reference/user_interface/view_records.html | View inheritance, XPath, `priority`, `hasclass()` | Confirms inheritance application order, element locators, inheritance positions, and `hasclass()` extension. |
| ODOO-MANIFEST-19 | Odoo 19.0 Module Manifests: https://www.odoo.com/documentation/19.0/developer/reference/backend/module.html | Manifest version, dependencies, data file listing | Confirms `__manifest__.py`, version field, dependency loading, and data/demo lists. |
| ODOO-DATA-19 | Odoo 19.0 Data Files: https://www.odoo.com/documentation/19.0/developer/reference/backend/data.html | XML data lifecycle and `noupdate` | Confirms `noupdate="1"` for data expected to be applied only once. |
| ODOO-PERF-19 | Odoo 19.0 Performance: https://www.odoo.com/documentation/19.0/developer/reference/backend/performance.html | Compute performance, batch operations, indexes | Use for batch compute guidance, `_read_group`, prefetching, complexity reduction, and selective indexing. |
| ODOO-TESTING-19 | Odoo 19.0 Testing Odoo: https://www.odoo.com/documentation/19.0/developer/reference/backend/testing.html | Staging/test checklist and module test expectations | Use for `TransactionCase`, `HttpCase`, test tagging, and test execution notes. |
| ODOO-SH-FIRST-MODULE-19 | Odoo 19.0 Odoo.sh first module: https://www.odoo.com/documentation/19.0/administration/odoo_sh/first_module.html | Odoo.sh development branch and module deployment context | Use only for Odoo.sh operational context, not deep framework rules. |

## Rule-To-Source Mapping

| KB Rule | Source IDs | Confidence |
| --- | --- | --- |
| Schema lookup must precede new model/field proposals. | Local policy + project schema snapshots | High as local AI safety policy; this is not an Odoo framework requirement and needs actual schema files for execution. |
| `company_dependent=True` is for per-company values on the same logical record. | ODOO-MULTICOMPANY-19 | High |
| Use `@api.depends_context('company')` when compute output depends on active company. | ODOO-MULTICOMPANY-19 | High |
| Empty ACL `group_id` grants access broadly and should be avoided unless intentional. | ODOO-SECURITY-19 | High |
| Record rules are default-allow after ACLs if no rule applies. | ODOO-SECURITY-19 | High |
| Multi-company rule domains can use `company_ids`; `company_id` is a model field only when present. | ODOO-SECURITY-19 | High; do not blindly apply the nullable `company_id` pattern to models without that field. |
| Related fields should not chain through `One2many` or `Many2many` paths. | ODOO-ORM-19 | High; use explicit computed fields for aggregation/traversal across x2many records. |
| View inheritance order is controlled by inherited view application and `priority`. | ODOO-VIEWS-19 | High |
| Use `hasclass()` for class matching only where Odoo view/QWeb inheritance supports it. | ODOO-VIEWS-19 | High |
| Use `noupdate="1"` for data expected to be applied only once; keep module-owned security data updateable unless preservation is intentional. | ODOO-DATA-19 | High for lifecycle behavior; security-data update policy is local deployment safety guidance. |
| Manifest `version`, `depends`, `data`, and `demo` should be checked for deployment impact. | ODOO-MANIFEST-19 | High |
| Batch operations and `_read_group`/prefetch patterns should be preferred for compute-heavy logic. | ODOO-PERF-19 | High |
| Index only fields with justified search/domain value. | ODOO-ORM-19 + ODOO-PERF-19 | High |
| Odoo tests should cover model behavior and UI-like form flows where risk exists. | ODOO-TESTING-19 | Medium |
| Odoo 19.0 is the confirmed KB baseline. | ODOO-*-19 official docs + project schema snapshots | High as local safety gate; project-specific implementation still requires the target project's schema snapshot. |
| Large schema files must be queried locally, not pasted wholesale. | Local policy + project schema snapshots | High as local AI context-control policy. |
| Production-like data migration must be checked on staging. | ODOO-SH-FIRST-MODULE-19 + local deployment policy | Medium; especially required fields, constraints, XML data lifecycle, and migration scripts. |
| Controller/RPC exposure must be reviewed for authentication and CSRF choices. | ODOO-SECURITY-19 | Medium; exact route behavior may need target-version docs and project code. |

## Useful Non-Authoritative Risk Notes

| Topic | Source | Use |
| --- | --- | --- |
| Odoo.sh staging and migration threads frequently mention module compatibility and upgrade-order pain. | Reddit/Odoo community discussions found during 2026-06-04 search | Keep as motivation for staging QA and manifest/dependency checks only. |
| View inheritance questions frequently mention XPath fragility and upgrade debt. | Reddit/Odoo community discussions found during 2026-06-04 search | Keep as motivation for stable anchors and staging render checks only. |

## Open Research Items

- Vault target confirmed: `/mnt/c/JSJEON/Obsidian/AI_AUTO_Vault/AI_AUTO/Odoo.sh KB`.
- Locate standard and project schema snapshots when applying the KB to a specific project.
- Confirm whether the project has local Odoo coding conventions that override generic Odoo guidance.
- Final KB uses Korean folders with English technical page titles.
