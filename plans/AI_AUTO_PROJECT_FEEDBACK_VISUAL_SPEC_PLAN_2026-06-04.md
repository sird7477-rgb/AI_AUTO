# AI_AUTO Project-Feedback Intake Plan: Visual Planning + Spec Alignment (2026-06-04)

## Context

Seven OPEN improvement items surfaced from the downstream `jw_dev` Odoo project
feedback queue (`/mnt/z/JSJEON/Project_JW/99. odoo/01. A1/jw_dev/.omx/feedback/queue.jsonl`).
User decision (2026-06-04): register all seven in the structural backlog with an
honest classification, build one unified implementation plan for the adjacent
items, and implement only after explicit approval. Odoo-specific items stay in
the project runbook / a future Odoo domain pack; only the reusable,
framework-neutral kernel is absorbed into AI_AUTO home guidance.

These are not greenfield: AI_AUTO home already has overlapping infrastructure,
so each item is scoped as *extend existing surface*, *domain-pack kernel only*,
or *already largely covered*.

## Existing home assets to reuse (do not duplicate)

- `docs/PLANNING_VISUALIZATION_GUIDE.md` — Structurizr + Excalidraw + paired
  Markdown spec, source-of-truth rules, `excalidraw-spec-template.md`.
- `scripts/collect-review-context.sh::write_visual_artifact_audit` — report-only
  audit pairing `*.excalidraw` ↔ `*-spec.md` ↔ `*.svg`.
- `scripts/self_demo_contracts.py::visual_artifact_policy` — source-of-truth
  contract over mermaid/structurizr/excalidraw/export artifact types.
- `scripts/doc-budget.sh` — `DOC_BUDGET_EXEMPT_GLOBS` + top-level-only guidance
  scope (ST-P1-24), so nested plan/spec docs are already exempt from the
  guidance-bloat budget.
- Adjacent review contracts: artifact-sync (`SA-P1-03`), `phase_scope_guard`,
  `review_revision_loop` — for spec/alignment work, extend rather than overlap.

## Classification

Generic AI_AUTO-home (new value beyond existing assets):

- `planning:structure-visual-optimizer-gate` — complexity-triggered auto-proposal
  of the structurize → visualize → optimizer step (the guide documents *how*; no
  trigger/checkpoint exists yet).
- `planning:ui-wireframe-required-for-form-heavy-specs` — UI wireframe as a
  distinct artifact from flow diagrams when layout is the core requirement.
- `spec-gate:review-loop-alignment` — spec-row ↔ code-evidence mapping gate
  *inside* the implement/review loop (existing artifact-sync guards final-report
  omission and phase leakage, not in-loop spec alignment).

Odoo domain-pack (absorb framework-neutral kernel only):

- `odoo:wireframe-must-follow-native-ui-structure` — kernel: framework-native
  wireframes should mirror the real view skeleton; Odoo view specifics
  (control panel/statusbar/sheet/oe_title/smart buttons/notebook, dialog modal
  structure, list/kanban) stay in the project runbook.
- `planning:excalidraw-wireframe-guide-promote-to-ai-auto` — kernel: the generic
  wireframe-authoring conventions; the Odoo-specific
  `docs/runbooks/EXCALIDRAW_WIREFRAME_GUIDE.md` stays project-owned.
- `odoo:preserve-standard-business-flow-before-custom-ui` — kernel: do not hide
  or replace a framework's standard business flow behind custom UI without an
  impact map + regression evidence; the Odoo field/flow specifics
  (order_line, payment terms, invoice status, purchase→bill mapping) and any
  review-gate block stay in the Odoo domain pack.

Already largely covered (thin increment only):

- `doc-budget:plan-spec-label-exemption` — ST-P1-24 already provides glob-based
  and nested-scope exemption; the only remainder is a *standardized* plan/spec
  filename-label convention plus a documented default glob.

## Unified design, grouped

### Group 1 — Planning visual-artifact gate (ST-P1-36 + ST-P1-37)

One pure, report-only contract in `self_demo_contracts.py`
(e.g. `planning_visual_gate_policy`) plus a planning/interview checkpoint in
existing guidance. It classifies a spec's complexity signals (entangled state
transitions ≥2, 1:N or bidirectional doc links, many permission/button/alert
conditions, PDF/dashboard/migration scope, explicit tool mention) and the
layout signals (form-structure change, section layout, columns, popup view,
button placement) and *proposes* the missing visualization or wireframe artifact
as a candidate before the final implementation-instruction doc. It is advisory:
it proposes work, it does not hard-block, and the source spec stays
authoritative with visualization subordinate.

### Group 2 — Spec ↔ code alignment gate (ST-P1-38)

A pure contract that, after a medium-or-larger patch and before applying
reviewer-suggested scope changes, requires mapping spec rows to code evidence
and classifying each `aligned | updated | not_applicable | blocked |
needs_user_confirmation`. Report-only classification first; any new blocking
behavior is a separate, explicitly approved step. Extends — does not duplicate —
artifact-sync and `review_revision_loop`.

### Group 3 — Odoo domain kernels (ST-P1-39 / 40 / 41)

Absorb only framework-neutral principles into home guidance
(`PLANNING_VISUALIZATION_GUIDE.md` and/or a generic principle line); keep Odoo
view structure, the Excalidraw runbook, and the standard-flow field specifics in
the project runbook / a future Odoo domain pack. No Odoo-specific enforcement is
added to generic home gates.

### Group 4 — doc-budget plan/spec label convention (ST-P1-42)

Document a plan/spec filename-label convention and ship it as a default
`DOC_BUDGET_EXEMPT_GLOBS` recommendation; report labeled-artifact totals
separately. Mostly realized by ST-P1-24, so this is a small convention/doc
increment, not new accounting logic.

## Sequencing (each a micro-unit Ralph, unanimous review, post-approval)

1. Group 1 (visual gate) — highest repeat signal, extends an existing surface.
2. Group 2 (spec alignment) — adjacent review-loop surface; design alongside
   Group 1 to avoid contract overlap.
3. Group 4 (doc-budget label) — thin; can ride a small commit.
4. Group 3 (Odoo kernels) — last; generic kernel into home, specifics stay
   project-owned. Confirm a domain-pack home before promoting Odoo specifics.

## Boundaries (invariant)

- Report-only / advisory by default. New hard-blocking gates require separate
  explicit approval, not this intake.
- No runtime, scheduler, queue, or completion authority added.
- Domain items absorb only the framework-neutral kernel; Odoo specifics stay
  project-owned (odoo #6 precedent).
- Queue items stay OPEN until each unit is implemented, reviewed, and committed;
  registration is not resolution.
