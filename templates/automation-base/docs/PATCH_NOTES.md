# AI_AUTO Patch Notes

This file records template-level changes by AI_AUTO template version. Review it
before patching an existing project, then use `ai-auto-template-status` to check
which files are template-owned, hybrid, or project-owned.

## 2026.05.28.2

- Clarified ambiguity handling for follow-up meta requests so root-cause,
  guidance-update, or recurrence-prevention questions stay anchored to the
  specific failure event the user identified instead of drifting to adjacent
  technical topics.
- Moved the repo-owned default local project and vault paths from
  `/mnt/c/JSJEON/...` to `/mnt/z/JSJEON/...`; users who keep projects on the old
  drive or under the former `Project_JW/99. 개발개발` grouping should override
  `AI_AUTO_JW_PROJECT_ROOT`, `AI_AUTO_SIRD_PROJECT_ROOT`, and local vault paths.
- Made installed Codex tmux auto-entry default on after
  `--install-codex-tmux-auto-entry`; use `AI_AUTO_CODEX_TMUX_AUTO=0 codex` for
  direct execution while scripts, pipes, redirects, and nested tmux sessions
  still bypass tmux. Reverting to direct execution is currently a per-shell
  opt-out or managed shell-function removal.
- Documented the external SSD sandbox boundary so `/mnt/z` sandbox read-only
  evidence is not mistaken for SSD failure without an approved real write probe.
- Added post-Ralph guidance-bloat handling guidance: analyze first, then propose
  a two-stage cleanup plan before editing guidance documents.

## 2026.05.27.2

- Added opt-in `codex` tmux auto-entry support through the managed shell
  wrapper. The feature activates only with `AI_AUTO_CODEX_TMUX_AUTO=1` for
  interactive terminal calls outside tmux, and it preserves direct execution for
  scripts, pipes, redirects, nested tmux sessions, and normal Codex calls.
- Kept the tmux wrapper in the same generated `codex()` chain as the existing
  template drift notice so opt-in shell integrations do not overwrite each
  other.

## 2026.05.27.1

- Added managed shell shortcuts `jwlist` and `sirdlist` for drilling into local
  project folders and entering directories once common project markers are
  found.
- Documented the local project-list shortcuts alongside the existing `AI_AUTO`
  and bare `tmux` shell integration, with verification coverage for generated
  shell functions and override roots.

## 2026.05.25.3

- Hardened Obsidian knowledge vault pushes so invalid explicit projects cannot
  regenerate an empty index, validation rejects symlink note escapes, failed
  review-gate verdicts can still produce local drafts, and same-name projects
  use hash-suffixed vault inbox namespaces.
- Clarified `knowledge-collect` operating docs, sync boundaries, global helper
  lists, Codex drift notice output, and local/private vault push requirements.

## 2026.05.25.2

- Added automatic local knowledge draft capture from sanitized feedback and
  review-gate signals, plus AI_AUTO home `knowledge-collect` for validated
  cross-project inspection and explicit vault push.

## 2026.05.25.1

- Added `docs/OBSIDIAN_INTEGRATION.md` to define Obsidian as a sanitized
  knowledge store under AI_AUTO control, not a review, approval, or runtime
  authority.
- Added `scripts/knowledge-notes.py` for curated incident, finding, lesson,
  technical-spec, and promotion-candidate notes with frontmatter validation,
  dry-run default behavior, explicit write/output controls, local-draft guards,
  secret checks, source hashing, and generated indexes.
- Wired the Obsidian knowledge workflow into template installation, doctor,
  template-status, and verification coverage, including external SSD/vault
  operating guidance. Because the helper is Python-based, doctor now treats
  `python3 >= 3.9` as a required runtime.

## 2026.05.24.5

- Split AI automation trend hardening so the always-loaded control contract
  stays short while recurring trend research lives under `docs/research/`.
- Added template installer, status, and verification coverage for the nested
  trend research guide.

## 2026.05.24.4

- Clarified hybrid/project-owned template patch reporting with
  absorbed/rejected/deferred outcomes.
- Added `DOC_BUDGET_TEMPLATE_PATCH=1` for reviewed template-owned guide additions.
- Downgraded missing optional Gemini/agy stabilizing flags to doctor info notes.

## 2026.05.24.3

- Added AI automation trend hardening guidance for agent identity, tool
  permission classes, kill switch/revoke handling, local automation
  observability, and recurring trend research.
- Linked the hardening guide from workflow, runtime adapter, model routing,
  observability, session-quality, and template onboarding docs without granting
  new runtime permissions.
- Added verification coverage so root/template hardening guidance and template
  status entries stay in sync.

## 2026.05.24.2

- Reduced guidance document budget pressure by moving low-cost lane routing
  details into `docs/AI_MODEL_ROUTING.md` while keeping delegation safety
  boundaries in `docs/AUTOMATION_OPERATING_POLICY.md`.
- Shortened template `AGENTS.md` onboarding and rebuild keyword guidance by
  preserving triggers/fail-closed behavior and delegating detailed mechanics to
  linked workflow documents.
- Mirrored the active and template `docs/AUTOMATION_OPERATING_POLICY.md`
  structure so new projects receive the same guidance-budget reduction.
- Added template-sync verification for active/template routing and operating
  policy docs.

## 2026.05.24.1

This version consolidates the runtime-adapter branch changes and records the
template versioning guard added after review.

- Added the AI runtime adapter contract and `scripts/ai-runtime-adapter.sh` so
  Codex, Claude, Gemini, and agy review paths use explicit read-only capability
  checks before execution.
- Routed Claude/Gemini split reviews and Codex fallback review through the
  adapter while preserving command overrides, external runner propagation,
  sandbox/no-edit flags, and failure diagnostics in review artifacts.
- Added `docs/AI_RUNTIME_ADAPTERS.md` and verification coverage for capability
  refusal, relative path handling with `--cd`, external runner adapter
  propagation, adapter diagnostics, and template/root sync.
- Added experimental template source reporting and install guards so non-main
  AI_AUTO branches report disabled template patching unless explicitly
  overridden.
- Tightened completion guidance and verification so template-owned changes must
  bump `AI_AUTO_TEMPLATE_VERSION` and keep the latest patch-note heading in sync.

## 2026.05.21.2

- Added the `AI_AUTO 최신 패치 적용해줘` keyword so projects can request the
  AI_AUTO template patch workflow without retyping the full prompt.
- Updated the optional Codex drift notice to print the short patch keyword when
  template drift is detected.
- Documented that the keyword still preserves project-specific rules, avoids
  generated `.omx/` artifacts, and requires normal verification/review gates.

## 2026.05.21.1

- Documented Codex native goal mode as an optional thread-local completion aid,
  not an AI_AUTO control plane.
- Clarified that AI_AUTO/OMX state, checkpoints, plan artifacts, verification,
  review gates, approvals, and latest user instructions remain separate sources
  of truth.
- Added verification coverage so root and template session-quality guidance keep
  the same native-goal boundary.

## 2026.05.20.2

- Updated the opt-in Codex drift notice so each AI_AUTO-managed project reports
  template drift only once per shell session.
- Added the latest template patch-note heading and patch-note path to the drift
  notice so users can inspect the home checkout review notes before patching.
- Bumped the template version marker to match the latest patch-note version used
  by `ai-auto-template-status`.

## 2026.05.20.1

- Added `scripts/doc-budget.sh` as the Stage 1 guidance document budget check.
- Added `scripts/guidance-duplicate-report.sh` for read-only Stage 2 duplicate
  and consolidation reports when requested after a budget warning.
- Updated verification to run the guidance budget check, exercise budget
  accounting, test duplicate-report fallback behavior, and confirm template
  installation coverage.
- Added workflow policy requiring final code diffs to be compared with
  applicable plan, specification, or design artifacts before completion reports.
- Added completion-report guidance to explain user-facing results in plain
  Korean first, with technical identifiers included only when needed for
  reproduction or user action.
- Updated onboarding and template guidance so new projects decide spec/design
  alignment ownership, Korean-first report language, and guidance document
  budget handling during setup.

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
