# Feedback Queue Promotion Plan - 2026-05-31

## Goal

Promote still-applicable feedback queue items into regular AI_AUTO behavior,
template files, and verification.

## Applicability Decisions

1. `ai-runtime-adapter:agy-prompt-large-placeholder` - applicable; placeholder
   `--prompt` plus stdin can review the wrong content.
2. `obsidian:ssd-vault-migration-runbook` - applicable; SSD operation guidance
   lacks a migration checklist for projects plus the vault.
3. `ui:design-guidance-review` - applicable; UI guidance lacks a reusable design
   quality gate.

## Execution Plan

1. Change the agy/Gemini runtime adapter so oversized prompts fail closed when
   only `--prompt` is available; keep `--prompt-file` as the safe large-prompt
   path.
2. Add verification that the unsafe placeholder path is not executed.
3. Promote the SSD migration runbook into Obsidian integration guidance and the
   template copy.
4. Promote the UI design quality gate into the UI completion pack and template
   copy.
5. Bump the AI_AUTO template version and patch notes.
6. Resolve the feedback queue items after verification and review evidence.

## Completion Criteria

- `./scripts/verify.sh` passes.
- `./scripts/review-gate.sh` returns `proceed` or `proceed_degraded` with any
  degraded state reported.
- Feedback queue items are no longer open.
