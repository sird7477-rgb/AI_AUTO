# Patch Notes: Review Context Budget

Date: 2026-05-15

## Changes

- Reduced the default review context cap from 750000 bytes to 300000 bytes.
- Reduced the focused diff cap from 300000 bytes to 120000 bytes.
- Reduced the default Gemini prompt cap from 750000 bytes to 300000 bytes.
- Added explicit guidance that Gemini recovery must stay on the configured local CLI path, without switching to API-key mode or weakening review-gate criteria.
- Updated the Odoo verification pattern to compile Python source in memory instead of using `compileall` or `py_compile` so onboarding static checks do not create `__pycache__` churn.

## Queue Items Covered

- `review-gate:gemini-context-split-no-key`
- `verify:compileall-pycache`

## Notes

This is a bounded budget hardening pass, not a full multi-slice reviewer orchestration system. File or topic based review slicing remains a later design task.
