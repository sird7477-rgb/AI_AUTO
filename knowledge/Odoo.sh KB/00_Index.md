# Odoo.sh KB

Status: promoted
Baseline: Odoo 19.0 official documentation.

## Purpose

This KB is the working rulebook for AI-assisted Odoo.sh customization:

1. Read the requirement.
2. Check the schema snapshot.
3. Reuse existing models and fields when possible.
4. Design only the missing parts.
5. Check view inheritance, security, deployment, and staging evidence.
6. Return a traceable spec instead of a speculative implementation.

## Language Convention

Use Korean folder names for Obsidian navigation and English technical page titles for searchability. Add Korean aliases later only when the final vault convention requires them.

## Guides

- [[01_AI 작업 기준/AI-Working-Principles|AI Working Principles]]
- [[01_AI 작업 기준/Requirement-to-Spec-Template|Requirement to Spec Template]]
- [[02_스키마 활용/Schema-Usage-Guide|Schema Usage Guide]]
- [[03_개발 표준/Field-Design-Guide|Field Design Guide]]
- [[03_개발 표준/View-Customization-Guide|View Customization Guide]]
- [[03_개발 표준/Security-Checklist|Security Checklist]]
- [[04_Odoo.sh 운영/Staging-QA-Checklist|Staging QA Checklist]]
- [[99_자료/Source-Index|Source Index]]

## Hard Gates

| Gate | Rule |
| --- | --- |
| Schema | No implementation-ready answer before the schema lookup table is complete. |
| Security | New model or sensitive field work must include ACL, record rule, and field group review. |
| View | Inherited views must name target view, XPath anchor, position, and staging render check. |
| Deployment | Manifest, data files, and `noupdate` behavior must be reviewed. |
| Staging | Production handoff requires staging evidence or an explicit blocker. |

## Status And Evidence Rules

Final output status MUST be one of: `ready`, `schema-pending`, `security-pending`, `staging-pending`, `blocked`.

Evidence table status MUST be one of: `pending`, `pass`, `fail`, `blocked`, `not-applicable`.

Evidence with `pass` or `ready` is invalid unless it names the file/snapshot, lookup query, command/action, user/group where relevant, and observed result.

## Current Open Inputs

- Vault target: `/mnt/c/JSJEON/Obsidian/AI_AUTO_Vault/AI_AUTO/Odoo.sh KB`.
- Add or run the scoped KB validator before promotion.
- For each real project task, locate that project's standard/project schema snapshots before producing implementation-ready output.
