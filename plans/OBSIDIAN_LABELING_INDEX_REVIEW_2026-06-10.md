# Obsidian Labeling And Index Review Plan

Date: 2026-06-10
Status: regular-promotion execution

## Target Result

Make the Obsidian vault readable as a deliberate knowledge system instead of a
set of disconnected notes, without weakening the rule that Obsidian is advisory
and non-authoritative.

## Current Evidence

- Current vault: `/mnt/z/JSJEON/Obsidian/AI_AUTO_Vault`.
- Regular AI_AUTO curated notes validate through `scripts/knowledge-notes.py`.
- The Z vault contains both generated AI_AUTO note hubs and separate domain KB
  folders such as `Odoo19_Docs_KB` and `Odoo.sh KB`.
- `scripts/knowledge-notes.py validate <vault>/AI_AUTO` validated the curated
  note set, while skipping generated pages and top-level plain-guide folders.
- `scripts/knowledge-notes.py migrate-vault <vault>/AI_AUTO --dry-run` refused
  at least one Inbox-to-Projects overwrite, proving that remaining Inbox notes
  need conflict review before migration.

## Classification

Use three lanes instead of forcing one index model onto every vault folder.

1. AI_AUTO curated notes
   - Layout: `Projects/`, `Inbox/`, generated `Surfaces/`, `RepeatKeys/`,
     `Promotion/`, `Views/`, and `AI_AUTO_INDEX.md`.
   - Source of relationships: helper frontmatter plus generated `## Links`.
   - Tooling: `scripts/knowledge-notes.py validate`, `index`, and
     `migrate-vault`.

2. Domain KB folders
   - Example: `Odoo.sh KB`.
   - Source of relationships: folder-local `00_Index.md`, source index, and
     scoped validator.
   - Tooling: folder-specific validator such as `scripts/validate-odoo-kb.py`.

3. Large reference baselines
   - Example: `Odoo19_Docs_KB`.
   - Source of relationships: baseline index, slim/raw tiers, runbook metadata,
     and validator parity checks.
   - Tooling: `scripts/validate-odoo-docs-kb.py`.

## Required Review Before Cleanup

1. Audit remaining `Inbox/**/*.md` notes against their `Projects/` targets.
2. Classify each collision:
   - exact duplicate: remove the Inbox copy only after backup or explicit
     cleanup approval
   - same `repeat_key` with newer data: merge into the Projects note
   - distinct evidence: promote under Projects with a unique filename
3. Regenerate AI_AUTO hubs only after conflict resolution:
   - `scripts/knowledge-notes.py migrate-vault <vault>/AI_AUTO`
   - `scripts/knowledge-notes.py index --notes-dir <vault>/AI_AUTO --output <vault>/AI_AUTO/AI_AUTO_INDEX.md`
4. Validate each lane with its own validator.

## Read-Only Audit Command

Add a repo-native audit helper before any destructive cleanup. The helper must
read a vault root and report:

- curated notes under `Projects/` and `Inbox/`
- generated hub pages
- top-level domain KB/reference folders ignored by `knowledge-notes.py`
- Inbox files whose target filename already exists under `Projects/`
- whether each Inbox/Projects conflict is an exact file duplicate, has the same
  `source_hash`, has the same `repeat_key`, or needs manual review
- likely stale generated index presence

The audit helper must not modify vault files. Real cleanup remains a later step
that starts from the audit report.

## Guidance Checkpoints

- State clearly that `AI_AUTO_INDEX.md` covers curated AI_AUTO notes only, not
  top-level domain KB or large reference baseline folders.
- Require Inbox/Projects collision audit before migration.
- Keep domain KB and reference baseline indexes folder-local unless a reviewed
  promotion explicitly adds a cross-link.
- Do not delete, merge, or overwrite vault notes merely because they look
  disconnected in Obsidian graph view.

## Stop Condition

The plan is complete when the guidance distinguishes the three lanes, warns
against blind Inbox migration on conflicts, a read-only audit helper exists, and
future cleanup can start from an audit report instead of manual graph-view
inspection.
