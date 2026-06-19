# Plan — KB capture-coverage hardening (격납 catch) 2026-06-19

Source: Obsidian 격납 policy review + 2-agent independent verification panel
(claims verifier + recommendation/security critic). All evidence below was
ground-truth verified against current code, not memory.

## Problem

"저장가치 있는 케이스가 잘 캐치되어 격납되는가?" — No. Capture coverage has a
structural gap: the only automatic capture stores verdict-state noise, while
substantive findings depend on manual `Finding:` trailers + a manually-run
harvester that did not run even this session.

## Verified evidence (panel)

- **Only one auto-trigger.** `scripts/review-gate.sh` (`review_gate_housekeeping`,
  ~L181-186) runs `capture-knowledge-drafts.py --source review-gate --write` on
  every gate exit. No git hook, cron, or other path invokes capture. CONFIRMED.
- **Auto-capture is verdict-state only.** `capture_review_gate`
  (`capture-knowledge-drafts.py:205-236`) emits one generic note
  (`"Review gate ended as <decision>; missing reviewers: …"`, surface=review-gate,
  repeat_key=`review-gate:<decision>`, `sync_class=local_private` hardcoded L138).
  Clean `proceed`+no-missing is skipped. No substantive content extracted. CONFIRMED.
- **Dedup collapses it.** `run_record` skips when `repeat_key` already exists
  (L108-110); review-gate keys are ~4 decision values → **at most ~4 auto-notes per
  project, ever**, regardless of gate-run count. CONFIRMED (panel addition).
- **Substantive harvester is manual-only.** `tools/knowledge-capture` (parses
  `Finding:`/`Finding-Evidence:`/`Finding-Scope:` trailers, mandatory reuse-test gate)
  is referenced only as an installed symlink; no hook/cron invokes it. CONFIRMED.
- **Secret-pattern over-rejects paths (live-tested).** `SECRET_PATTERN` alt
  `/(home|Users|root|mnt)/[^\s]+` (knowledge-notes.py:44, capture-knowledge-drafts.py:21,
  knowledge-capture:54) flags ANY absolute path as secret-like. `/home/odoo/src/…`,
  `/root/…`, `/mnt/z/…` → rejected; relative paths pass; real keys still reject. CONFIRMED.
- **Substantive drafts are batch-mined, not continuous.** corini = 3 drafts, all
  review-gate state, 0 substantive. ai-lab/jw_dev/zurini = 27/28/19 substantive, written
  in a few manual batches (mtimes 2026-06-03/04/12 — "single run" was wrong, multi-batch).
  This session's 3 commits carry **0 `Finding:` trailers** → 0 harvestable learnings. CONFIRMED.
- **Compounding store gap:** every auto-captured note is `local_private` → never reaches
  the vault without manual promotion; capture failures are swallowed (gate warns only).

## Root cause (the real bottleneck)

Coverage is bottlenecked on **trailer authorship** — distilling a reusable rule into
`Finding:`/`Finding-Evidence:`/`Finding-Scope:` at commit time. That is deliberate
author judgment (the reuse-test gate WANTS it). Automating the harvester or fixing the
regex only helps findings that were already trailered. So the highest-leverage change is
making the trailer convention visible/habitual, not the plumbing.

## Fix B (do first) — credential-path secret rule, NOT slash-strip

**The originally-proposed "strip the leading slash" is UNSAFE** (panel security finding):
the bare-path alt is the ONLY body-text guard against credential-by-location
(`/home/u/.ssh/id_rsa`, `.aws/credentials`, `.env`); `validate_source_artifact`'s
`id_rsa`/`.env` checks run only on the `source_artifact` FIELD, not body text. Stripping
the slash disarms that guard.

Replace the bare-path alternative with a **credential-path** alternative that fires on
sensitive path components regardless of leading slash:
```
|(?:\.ssh|\.aws|\.gnupg|\.config/gcloud)/|id_rsa|id_ed25519|id_dsa|id_ecdsa|\.netrc|\.pgpass|credentials\b
```
plus a separately-anchored `.env` sub-check (the existing `(^|[^A-Za-z0-9_])` outer group
interferes with a naive `/\.env` append — verified it slips through). Apply identically to
ALL THREE copies (knowledge-notes.py, capture-knowledge-drafts.py, knowledge-capture).

Effect: legit `/home/odoo/src/…`, `/mnt/z/…`, relative repo paths PASS; `.ssh/`, `.aws/`,
`id_rsa`, `credentials`, `.netrc`, `.gnupg/`, `.env` still FAIL-closed (even improves: catches
relative `./.ssh/id_ed25519` the old rule missed). Note the two enforcement semantics:
`knowledge-capture` REDACTS matches to `[redacted]` (test asserts this — update
`tests/test_knowledge_capture.py:64-65` to a credential path); `knowledge-notes validate`
(push gate, called by knowledge-collect:234) and `capture-knowledge-drafts.py:105` REJECT/skip.
B stops `[redacted]`-gutted drafts, push-gate rejections, and capture skips for legit paths.

Optional hardening: extend `validate_source_artifact`'s `UNSAFE_SOURCE_PATTERNS` to also
screen body text (defense-in-depth, push gate).

## Fix A (do second) — habit reminder + correct trigger (NOT post-commit)

`tools/knowledge-capture` already IS the harvester: parses trailers, enforces reuse-test,
no-ops when no `Finding:` trailer, dedups by `repeat_key`, dry-run by default. So A is
"wire up an existing tool," in two parts:

- **A1 (highest value): WORKFLOW trailer reminder.** Add a dev-loop step / session-end
  reflexion line: "재사용 가능한 규칙은 `Finding:` + `Finding-Evidence:` + `Finding-Scope:`
  커밋 trailer로 적어라(셋 다 있어야 격납)." Lowest risk, addresses the actual bottleneck.
- **A2: auto-run the harvester off the commit hot path.** `knowledge-capture` default range
  is `@{u}..HEAD` (un-pushed commits), NOT HEAD-only. So **post-commit is the wrong trigger**:
  it would re-scan the whole range on every commit (wasteful) AND inherits the documented
  multi-worktree GIT_* corruption hazard (precommit-hook-corrupts-worktree-git-state) unless
  it replicates the `unset GIT_*` guard. Prefer a **Claude SessionEnd/Stop hook** or a
  **pre-push prompt** — runs once over the same `@{u}..HEAD` window, off the commit path,
  no GIT_* hazard. If post-commit is later insisted on, it MUST `unset GIT_* && cd repo_root`
  (as the existing post-commit does), suppress output, and never block.

## Sequencing

B before A2 (confirmed): without B, A2 would auto-produce `[redacted]`-gutted drafts and
push-gate rejections for any trailered finding that mentions a path. A1 (the reminder) can
land with or before B.

## Risks / mitigations

- B regex anchoring (`.env` via the outer boundary group) → add `.env` as its own
  un-prefixed sub-check; cover with a live has_secret test matrix.
- B weakening secrets → mitigated by switching to credential-component matching (stricter on
  real credentials, looser only on benign location paths); verify both directions live.
- A2 trigger choice → avoid post-commit; if used, GIT_* unset guard is mandatory.

## Verification

- Live `has_secret` matrix (both directions): benign paths PASS, credential paths/keys REJECT
  — for all three copies.
- `verify-machinery` (+ template mirror) assertions: secret-rule matrix; knowledge-capture
  redaction test updated to a credential path; harvester no-op when no trailer; (if a trigger
  is added) it runs once over `@{u}..HEAD` and never blocks.
- Each fix = its own RALPH loop (plan→implement→`REVIEW_DECISION_GATE=1` unanimous→commit).
- scripts/X == templates/automation-base/scripts/X byte parity; template version bump + PATCH_NOTES.

## Out of scope / deferred

- Verdict→finding extraction (knowledge-capture deliberately harvests commit trailers only).
- review-gate state-note demotion to `local_repo_index` (noise cleanup; not a real loss — already local_private). Optional later.
- URL-embedded token with no credential keyword (never caught; low value).

## Outcome (2026-06-19)

- **B DROPPED.** Implementing B (relax the absolute-path secret rule) tripped a
  verify-machinery test (`/home/customer/private-project` must be rejected). The
  absolute-path rejection is DOCUMENTED PRIVACY policy, not an over-broad heuristic:
  `OBSIDIAN_INTEGRATION.md` ("Do not store … absolute private paths"),
  `AUTOMATION_OPERATING_POLICY.md` ("customer data"). The original B premise was also a
  misread: `knowledge-capture` REDACTS a path span and keeps the finding (not a silent
  drop); the push-gate reject is correct policy enforcement (author relativizes the path).
  So B was reverted in full — the local gate caught a privacy regression the AI panel had
  missed (independent cross-verification working).
- **A SHIPPED.** Finding-trailer auto-harvest in `hooks/post-commit` (after GIT_* unset,
  `command -v`-guarded, non-blocking, no-op on untrailered commits) + the WORKFLOW dev-loop
  trailer convention. verify-machinery asserts harvest-on-trailer and no-op-without.
  Template 2026.06.19.1. This is the policy-clean fix for "store-worthy cases get caught."
