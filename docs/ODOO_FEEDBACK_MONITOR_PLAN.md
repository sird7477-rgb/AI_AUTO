# Odoo Feedback Monitor Plan

## Purpose

Collect user feedback, error context, and lightweight field-test evidence from
Odoo staging and production environments, then produce periodic analysis
reports for maintainers. This layer must never modify Odoo code, data, settings,
or workflows without an explicit user request.

## Scope

Target phases:

- `stage`: active user acceptance testing, QA, and controlled pilot use.
- `production`: live operation with stricter privacy, permissions, and
  rate-limit rules.

Primary users:

- end users who can report usability issues or improvement ideas
- operators who see error dialogs or workflow failures
- maintainers who review reports and decide whether to request fixes

## Non-goals

- No automatic code changes.
- No automatic Odoo configuration changes.
- No automatic database repair or data mutation.
- No automatic issue-to-implementation handoff.
- No collection of raw secrets, credentials, tokens, session IDs, or unrelated
  customer data.

## Product Surface

### Global Improvement Button

Add an always-available improvement request entry point to the Odoo web client.

Expected behavior:

- visible from every Odoo screen, subject to group permissions
- opens a compact feedback dialog
- captures category, free-text description, optional attachments, current menu,
  action, model, record id when available, route/hash, user, company, and time
- allows the user to submit without leaving the current workflow

Suggested categories:

- error
- workflow_blocker
- confusing_ui
- missing_feature
- data_quality
- performance
- report_output
- other

### Error Dialog Log Button

Add a "Report with log" action to Odoo error/alert dialogs.

Expected behavior:

- captures the user-facing error message
- captures sanitized technical context when available
- lets the user add a note and attachment
- stores the original screen/action context
- never exposes raw traceback or sensitive values to unauthorized users

## Data Model Draft

### `ai.feedback.ticket`

Fields:

- `name`: generated ticket title
- `category`: selection
- `description`: user-provided text
- `source`: `global_button`, `error_dialog`, `operator_note`, or `imported_log`
- `stage`: `stage` or `production`
- `severity_hint`: `low`, `medium`, `high`, `critical`
- `status`: `new`, `triaged`, `reported`, `ignored`, `resolved`
- `user_id`
- `company_id`
- `menu_id`
- `action_id`
- `model_name`
- `res_id`
- `route`
- `client_context_json`
- `error_message`
- `sanitized_log_excerpt`
- `attachment_ids`
- `created_at`
- `analyzed_at`
- `report_id`

### `ai.feedback.report`

Fields:

- `name`
- `period_start`
- `period_end`
- `generated_at`
- `stage`
- `ticket_count`
- `summary`
- `duplicates`
- `severity_breakdown_json`
- `category_breakdown_json`
- `recommended_actions`
- `blocked_or_unclear_items`
- `source_ticket_ids`

## Collection Cadence

Run a scheduled collection and analysis job every 1 hour.

Recommended implementation:

- Odoo `ir.cron` for simple deployments.
- External worker only when analysis is slow, model-backed, or needs isolation.

The cron job should:

1. find new tickets since the last report
2. redact sensitive values
3. group duplicates and related tickets
4. infer severity and affected workflow
5. generate a maintainer-facing report
6. mark included tickets as `reported`

## Report Contract

Each report should include:

- period covered
- number of new tickets
- top categories
- suspected duplicates
- high-risk items
- reproducibility hints
- affected Odoo models/views/actions
- attachment summary
- recommended next actions
- unresolved questions

Reports are stored in Odoo and can be displayed on demand from a menu action.
The report output is advisory only. It must not include an "apply fix" or
"modify system" button.

## User-Requested Output

When the user asks for the latest feedback report, the AI or maintainer tool may
read the latest `ai.feedback.report` record and print a concise summary.

Allowed:

- summarize collected feedback
- rank severity and urgency
- propose investigation steps
- propose implementation plans
- identify missing reproduction evidence

Not allowed without explicit user request:

- create a code patch
- edit Odoo records or configuration
- change access rules
- mark reports resolved
- deploy changes

## Security And Privacy Rules

- Redact secrets before persistence and before analysis.
- Store only the minimum useful log excerpt.
- Attachments must follow Odoo access rules and record rules.
- Production collection should avoid raw customer data unless the project owner
  explicitly approves a narrow, auditable scope.
- Keep analysis prompts and reports free of credentials, tokens, cookies,
  session IDs, raw authorization headers, and private keys.
- Separate stage and production records in filters, reports, and permissions.

## Permissions

Suggested groups:

- `Feedback User`: can submit tickets and see own tickets.
- `Feedback Maintainer`: can see all tickets, attachments, and reports.
- `Feedback Admin`: can configure categories, retention, and cron settings.

Production defaults should be least-privilege:

- ordinary users submit and view only their own submissions
- maintainers review all submissions
- only admins configure retention and collection settings

## Odoo Implementation Notes

The exact web-client extension depends on the Odoo major version.

- Odoo 14-15: legacy JavaScript widget/service extension patterns.
- Odoo 16-18: OWL web client patch/service extension patterns.

Before implementation, confirm:

- target Odoo version
- custom addon namespace
- deployment method
- whether external AI analysis is allowed in production
- attachment retention policy
- maximum log excerpt length
- report visibility rules

## Integration With AI_AUTO

AI_AUTO should treat this module as an evidence source, not an executor.

Recommended flow:

1. Odoo users submit tickets.
2. Hourly analysis generates `ai.feedback.report`.
3. A maintainer asks AI_AUTO to review the latest report.
4. AI_AUTO summarizes issues and proposes a plan.
5. Code/config changes start only after a new explicit user request.

This fits the Incident Ops boundary: collect evidence, classify risk, report
status, and defer side-effectful action until approval.

## Open Questions

- Which Odoo major version is the target?
- Should reports be generated fully inside Odoo or by an external worker?
- Is production AI analysis allowed, or should production only collect and stage
  perform analysis?
- What attachment size and retention limits are acceptable?
- Which user groups should see production feedback reports?
- Should error dialog reporting capture browser console/network evidence, or
  only Odoo-side exception context?

## Acceptance Criteria

- Users can submit feedback from any Odoo screen.
- Users can report an error dialog with sanitized context.
- Attachments are supported.
- Feedback is stored with category, context, user, and timestamp.
- New items are analyzed every hour.
- Reports are stored and retrievable on demand.
- Reports are advisory and never apply changes.
- Production privacy and record-rule boundaries are documented and enforced.
