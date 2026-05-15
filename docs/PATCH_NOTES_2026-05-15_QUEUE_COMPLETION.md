# Patch Notes: Queue Completion

Date: 2026-05-15

## Changes

- Added automation-doctor warnings for legacy AI instruction pointer files that
  reference missing or untracked `AGENTS.md`, `docs/WORKFLOW.md`, or
  `scripts/verify.sh` targets.
- Added review verdict wording that distinguishes intentional reviewer opt-outs
  from persisted reviewer failures while keeping both as degraded coverage.
- Added reusable Odoo onboarding prompts for Odoo 19 on odoo.sh, project-local
  SSH/access runbooks, temporary admin password handling, and Playwright
  environment variables.

## Queue Items Covered

- `automation-template:promote-project-safety-drift`
- `onboarding:pointer-files-untracked-target`
- `review:disabled-reviewer-intentional-degraded`
- `onboarding:odoo19-ssh-playwright-guideline`
