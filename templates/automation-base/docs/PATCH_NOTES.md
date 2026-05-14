# AI_AUTO Patch Notes

This file records template-level changes by AI_AUTO template version. Review it
before patching an existing project, then use `ai-auto-template-status` to check
which files are template-owned, hybrid, or project-owned.

## 2026.05.15.1

- Added ownership and patch-policy columns to `ai-auto-template-status` output.
- Classified managed files as `template-owned`, `hybrid`, or `project-owned`.
- Marked `AGENTS.md` and `docs/WORKFLOW.md` as `review-merge` so project-specific
  rules are preserved during patch review.
- Marked `scripts/verify.sh` as `inspect-only` because target projects are
  expected to replace the onboarding placeholder with project-specific checks.
- Documented that generated/runtime `.omx/` artifacts are outside the managed
  patch manifest.
- Added this patch-note file so projects can inspect version changes before
  applying template updates.
- Added automatic lightweight AI review context for small tracked diffs. The
  default review context now stays diff-centered for small changes and omits
  planning/reference-file bodies unless `REVIEW_CONTEXT_DETAIL=full` is set.

## 2026.05.14.1

- Initial managed automation template version marker.
