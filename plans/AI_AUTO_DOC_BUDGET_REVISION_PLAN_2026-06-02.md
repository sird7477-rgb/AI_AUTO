# AI_AUTO doc-budget Revision Plan (2026-06-02)

Backlog candidate (proposed `ST-P1-24`). Re-review of `scripts/doc-budget.sh`
anti-bloat logic, requested by the user after writing Odoo customization spec
tables repeatedly tripped the budget.

## 1. Problem

`scripts/doc-budget.sh` (and its template copy) guards guidance-document bloat,
but it conflates **AI guidance prose** (AGENTS.md, WORKFLOW, operating policy —
should stay lean) with **project content/spec docs** (e.g. Odoo customization
spec tables — legitimately large). Writing a large spec doc trips the budget.

Verified behavior (2026-06-02):

- The net-added measure uses git pathspec `docs/*.md`, which **matches nested
  paths** (`docs/specs/nested.md` is counted).
- The totals measure uses `find docs -maxdepth 1 -name '*.md'`, which **excludes
  nested paths**.
- So the two measures have **inconsistent scope**, and a spec doc trips the
  net-added warn/fail (150/300) regardless of where it lives; a top-level one
  also pushes the primary total toward 6500.
- The net-added measure only counts the **uncommitted** diff (working tree +
  staged + untracked), so it resets to 0 on every commit; a multi-commit guide
  is never bounded cumulatively (observed: 86 → 36 net lines after a commit).

## 2. Decisions (user, 2026-06-02)

- **D1 — measurement scope: branch-cumulative.** Measure net-added against the
  branch merge-base (vs `main`) instead of only the uncommitted diff, so
  commit-splitting cannot evade the budget. Fall back to the current
  uncommitted-diff behavior when there is no usable base (e.g. on `main` itself
  or no merge-base).
- **D2 — guidance vs content: scope + exempt (confirmed, approach A).**
  Do not raise thresholds. Limit the budget to genuine guidance and exempt
  content/spec docs, applied **consistently to both net-added and totals**:
  - exempt a designated content area (default `docs/specs/**` and
    `docs/reference/**`) plus a configurable `DOC_BUDGET_EXEMPT_GLOBS`;
  - fix the net-added vs totals scope inconsistency so both use the same
    guidance set;
  - keep the current thresholds for guidance.
- **D3 — low-cost hardening: adopt both.**
  - Include `templates/automation-base/docs` in the duplicate-line detection
    (currently root docs only).
  - Require a reason string when `DOC_BUDGET_TEMPLATE_PATCH=1` is used (logged),
    so the escape hatch is not silent self-attestation.

## 3. Scope of changes

- `scripts/doc-budget.sh` (+ `templates/automation-base/scripts/doc-budget.sh`,
  byte-identical per the verify sync list):
  - branch-cumulative net-added with merge-base + safe fallback (D1);
  - a single shared "guidance file set" used by both net-added and totals, with
    the exempt globs subtracted (D2);
  - duplicate detection over root + template docs (D3);
  - reason-required escape hatch with the reason echoed into output (D3).
- Tests (extend existing doc-budget verify coverage in `scripts/verify.sh`, which
  already exercises budget pass/space/mixed/refactor/template-patch/missing
  cases): add exempt-path, cumulative-vs-base, scope-consistency, template
  duplicate, and escape-hatch-reason cases.
- Docs: a short note in the relevant guide on where spec/content docs live
  (exempt area) vs guidance docs.

## 4. Invariants / non-goals

- Warnings stay non-blocking; only `FAIL_COUNT>0` or `DOC_BUDGET_STRICT=1` fails.
- Do not weaken guidance bloat control: guidance thresholds are unchanged.
- Exemption is path/glob scoped and explicit; it never silently exempts the core
  guidance files (AGENTS.md, WORKFLOW.md, AUTOMATION_OPERATING_POLICY.md).
- Template parity: both copies stay byte-identical.

## 5. Verification

- `./scripts/verify.sh` green (includes the doc-budget self-tests).
- `./scripts/review-gate.sh` (principal=claude) unanimous.

## 6. Decisions settled

All three decisions are settled (D1 branch-cumulative, D2 scope+exempt approach
A, D3 both hardenings). Ready to implement once sequenced after `ST-P1-23`.
