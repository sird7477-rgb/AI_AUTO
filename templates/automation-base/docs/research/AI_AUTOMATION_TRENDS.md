# AI Automation Trend Research

This is the lower-frequency reference for recurring AI automation trend reports.
It does not change runtime defaults by itself. Runtime behavior changes still
require the normal AI_AUTO patch, verification, and review gates.

## Report Location

Use dated reports such as `docs/research/ai-automation-trends-YYYY-MM.md`.

## Cadence

For AI_AUTO itself, collect a report monthly or before major template, runtime,
reviewer, or tool-permission changes.

For ordinary projects, collect a report only when AI automation architecture,
external reviewer trust, provider capability, or tool-governance decisions are
material to the requested work.

## Required Fields

Each report should include:

- collection date
- source links and source type
- trend summary
- evidence versus inference
- AI_AUTO relevance
- action, defer, reject, or monitor decision
- affected docs, scripts, templates, or runtime surfaces
- verification and review requirements for any proposed patch

Prefer official documentation, release notes, standards work, vendor security
guidance, and local runtime evidence. Treat commentary and secondary analysis as
context, not authority.

## Authority Boundary

Provider announcements and public documents are reference material. Local
runtime capability evidence and normal verification/review gates control what
AI_AUTO may claim or execute in the current environment.
