# Codex Drift Notice Design (removed)

This document described an opt-in `codex` shadowing surface that compared a
project's vendored AI_AUTO files against the AI_AUTO home checkout and printed a
template "update available" notice before Codex started.

That feature was removed in the globalization. AI_AUTO is now a globally-installed
tool that operates on a project directory, and a project repo carries zero
vendored framework files, so there is no per-project template version to drift
against and nothing to compare.

The unrelated Codex startup notice for pending Obsidian/knowledge drafts still
exists. See `docs/GLOBAL_TOOLS.md` (the `OBSIDIAN OUTPUT CHECK` notice) and
`docs/OBSIDIAN_INTEGRATION.md` for that workflow.
