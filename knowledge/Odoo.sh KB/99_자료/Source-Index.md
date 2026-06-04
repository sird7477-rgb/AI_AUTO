# Source Index

Status: promoted
Primary baseline: Odoo 19.0 official documentation.
Generated from: `plans/ODOO_SH_KB_SOURCE_INDEX_2026-06-04.md`

## Official Sources

| ID | Source | Use |
| --- | --- | --- |
| ODOO-ORM-19 | [Odoo 19.0 ORM API](https://www.odoo.com/documentation/19.0/developer/reference/backend/orm.html) | ORM fields, computed fields, related fields, indexes, `check_company` |
| ODOO-MULTICOMPANY-19 | [Odoo 19.0 Multi-company Guidelines](https://www.odoo.com/documentation/19.0/developer/howtos/company.html) | `company_dependent`, `@api.depends_context('company')`, multi-company behavior |
| ODOO-SECURITY-19 | [Odoo 19.0 Security in Odoo](https://www.odoo.com/documentation/19.0/developer/reference/backend/security.html) | ACL, record rules, field groups, public methods, `sudo()`, controller/RPC risk |
| ODOO-VIEWS-19 | [Odoo 19.0 View Records](https://www.odoo.com/documentation/19.0/developer/reference/user_interface/view_records.html) | View inheritance, XPath, priority, `hasclass()` |
| ODOO-MANIFEST-19 | [Odoo 19.0 Module Manifests](https://www.odoo.com/documentation/19.0/developer/reference/backend/module.html) | Manifest metadata, dependencies, data/demo files |
| ODOO-DATA-19 | [Odoo 19.0 Data Files](https://www.odoo.com/documentation/19.0/developer/reference/backend/data.html) | XML/CSV data files and `noupdate` |
| ODOO-PERF-19 | [Odoo 19.0 Performance](https://www.odoo.com/documentation/19.0/developer/reference/backend/performance.html) | Batch operations, prefetching, `_read_group`, performance checks |
| ODOO-TESTING-19 | [Odoo 19.0 Testing Odoo](https://www.odoo.com/documentation/19.0/developer/reference/backend/testing.html) | Odoo tests and test tagging |
| ODOO-SH-FIRST-MODULE-19 | [Odoo 19.0 Odoo.sh first module](https://www.odoo.com/documentation/19.0/administration/odoo_sh/first_module.html) | Odoo.sh module development context |

## Rule-To-Source Mapping

| Rule | Source | Note |
| --- | --- | --- |
| Schema-first lookup before implementation-ready output | Local policy + project schema snapshot | Project safety gate, not an Odoo framework requirement. |
| Per-company values use `company_dependent=True` when appropriate | ODOO-MULTICOMPANY-19 | Applies when one logical record needs different values per company. |
| Company-sensitive computes use `@api.depends_context('company')` | ODOO-MULTICOMPANY-19 | Applies when output changes by active company. |
| Empty ACL `group_id` is broad access and must be justified | ODOO-SECURITY-19 | Treat as security-sensitive. |
| Record rules are default-allow after ACLs if no rule applies | ODOO-SECURITY-19 | Explicit scoping is required when ACL-level access is broader than the business rule. |
| Multi-company rule domains may use `company_ids` | ODOO-SECURITY-19 | `company_ids` is a rule-domain variable; `company_id` is a model field only when present. |
| Related fields must not chain through x2many paths | ODOO-ORM-19 | Use computed fields for aggregation/traversal across x2many records. |
| Stable XPath anchors and `hasclass()` are preferred | ODOO-VIEWS-19 | `hasclass()` applies only where Odoo XPath extensions are supported. |
| Manifest/data/noupdate decisions affect deployment | ODOO-MANIFEST-19, ODOO-DATA-19 | Keep security data updateable unless preserving admin edits is intentional. |
| Batch/prefetch patterns matter for compute-heavy work | ODOO-PERF-19 | Use as performance design evidence. |
| Odoo tests should cover risky model/security/UI flows | ODOO-TESTING-19 | Use `TransactionCase`/`HttpCase` or equivalent when risk warrants it. |
| Odoo 19.0 is the confirmed KB baseline | ODOO-*-19 official docs + project schema snapshots | Project-specific implementation still requires the target project's schema snapshot. |
| Large schema files must be queried locally, not pasted wholesale | Local policy + schema snapshot | Record command/query and relevant rows. |
| Production-like data migration must be checked on staging | ODOO-SH-FIRST-MODULE-19 + local deployment policy | Especially for required fields, constraints, and XML data lifecycle. |
| Controller/RPC exposure must be reviewed for authentication and CSRF choices | ODOO-SECURITY-19 | Treat public routes and RPC-callable methods as security-sensitive. |

## Useful Non-Authoritative Risk Notes

| Topic | Source | Use |
| --- | --- | --- |
| Odoo.sh staging and migration threads frequently mention module compatibility and upgrade-order pain. | Reddit/Odoo community discussions found during 2026-06-04 search | Keep as motivation for staging QA and manifest/dependency checks only. |
| View inheritance questions frequently mention XPath fragility and upgrade debt. | Reddit/Odoo community discussions found during 2026-06-04 search | Keep as motivation for stable anchors and staging render checks only. |

## Open Items

- Vault target confirmed: `/mnt/c/JSJEON/Obsidian/AI_AUTO_Vault/AI_AUTO/Odoo.sh KB`.
- Attach standard and project schema snapshots when applying the KB to a specific project.
- Confirm local project conventions.

Navigation: [[00_Index|Back to index]]
