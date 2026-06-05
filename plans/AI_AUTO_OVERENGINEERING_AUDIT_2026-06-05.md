# AI_AUTO Over-Engineering / Waste Audit (2026-06-05)

## Language Note

This audit is written in English for continuity with the structural-audit
corpus it analyzes (`AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md` and the structural
audit/execution plans, which carry the same note). Korean remains the default
for new strategy and operational-judgment documents; field names, paths, status
values, and code identifiers stay in English.

Micro-unit review of the AI_AUTO control plane for excess, waste, and
inter-module consistency. The shipped product under this control plane is a
trivial Flask todo app (one blueprint + Postgres). All line counts and caller
counts below are measured from the current tree, not estimated.

## Measured scale

Counting method stated to avoid ambiguity (a reviewer correctly flagged loose
counts in the first draft).

- `scripts/verify.sh`: 6057 lines; 60 `[verify] testing …` machinery self-test
  blocks vs ~13 lines touching the actual app/docker/`/todos`.
- `scripts/run-ai-reviews.sh` 2201, `summarize-ai-reviews.sh` 1177,
  `collect-review-context.sh` 1367, `self_demo_contracts.py` 1334.
- `self_demo_contracts.py`: 41 top-level `def`s = 38 public contract functions +
  3 `_`-prefixed helpers. **None of the 38 public contracts has a runtime
  caller** — every one is reached only from `tests/` (verified by symbol search
  across `scripts/` and `tools/`). This is the headline finding and was not
  disputed in review.
- `collect-review-context.sh`: 9 report-only audit sections, all
  `audit_status: report_only`, all documented as "never blocks the gate".
- 24 test files / 185 test functions; `scripts/` 36 entries (25 `*.sh`);
  `tools/` 27 entries (25 executable); `plans/` 37 `*.md`; 52 canonical
  backlog rows after U1.2/U1.3 relabeling: 27 `complete_contract`, 10
  `operational_clear`, 8 `advisory_contract`, 4 `complete`, 2
  `complete_observe_mode`, and 1 `display_only_complete`.
- Template parity: ~22 scripts mirrored byte-identical root↔template; repeated
  template-owned changes require a version bump plus top patch note
  (`2026.06.05.2` after the U1.2 template status sync).

## Unit findings

### U1. The contract layer enforces nothing (highest-cost finding)

All 38 public `self_demo_contracts.py` policies are advisory: no runtime caller,
and the 9 paired Bash audits are report-only. So ~1334 lines of Python + ~600 lines of
Bash audits + a large share of 185 tests validate evidence *shapes* that no
workflow step consumes to gate anything. Cost is real (write + test + review +
template-sync); enforcement is zero. Either wire the few high-value contracts
into the gate as actual fail-closed checks, or recategorize the layer as
documentation and stop paying enforcement-grade overhead for it.

### U2. Every policy is implemented twice and drifts

Each policy exists as (a) a Python contract and (b) a Bash audit that "mirrors"
it, kept in sync by hand, each with its own test file. This session proved the
drift hazard: the Spec-Code-Alignment Bash audit did not validate row status
while the Python contract did (Codex caught a false `clear`). 9 policies × 2
implementations × ≥2 test files is a standing consistency tax with no
single-source-of-truth. If both are needed, generate the audit from the
contract; otherwise drop one side.

### U3. verify.sh is a 6k-line monolith re-run inside review-gate

verify mixes product verification (~tiny) with 60 machinery self-tests, runs
docker + 185 pytest + dozens of shell fixtures, and is then re-run *again* inside
`review-gate.sh`. Some of those self-tests spawn nested `review-gate`/
`run-ai-reviews` fixtures, which contend with a real concurrent session and
truncated the gate three times this session. Split product-verify from
machinery-self-test; do not re-run the full monolith inside the gate.

### U4. Review-gate weight vs. change size

Every change — including doc-only and backlog-only edits — pays verify (heavy) +
two external LLM reviewers (Gemini via agy + Codex) that are flaky by design (20
retry/timeout/OOM/137/124 handling sites in run-ai-reviews). This session a
handful of small units cost ~10+ external review cycles (untracked-guard false
blocks from a concurrent writer, verify-in-gate truncation, OOM retries). The
diff-scope "lightweight" path exists but still triggers external LLM review.

### U5. Tooling sprawl + operator discoverability (corrected after review)

27 tools + 36 scripts. A resolver already exists: `scripts/resolve-feedback.sh`
(repeat-key, flock concurrency safety) plus a `tools/feedback-resolve` global
helper, and `docs/GLOBAL_TOOLS.md` documents `feedback-collect` and
`feedback-resolve` as a pair. Backlog `ST-P1-43` is already `complete_contract`.

The first draft of this audit claimed the resolver was missing and that
ST-P1-43 should be built — both stale. Codex review caught it. The accurate,
weaker finding: this operator hand-edited the queue and proposed rebuilding an
existing, documented tool — i.e. with 25 tools, even the docs were not consulted
before acting. Real residual gap: the *read* tool's runtime output does not
inline the resolve command (only the docs pair them), so the next operator can
repeat the miss. This is discoverability polish, not a missing capability.

### U5b. Concurrent multi-agent churn makes analysis (and reviews) go stale

`tools/feedback-resolve` and the ST-P1-43 `complete_contract` flip were produced
by another agent **while this audit was being written** (the same concurrent
session that kept adding `ODOO_SH_KB_*` and `knowledge/` untracked files into the
repo, and that forced `REVIEW_UNTRACKED_ALLOWLIST` scoping on every review this
session). Multiple agents writing the same tree simultaneously is itself a
source of waste: stale analysis, false untracked-guard blocks, reviewer
contention, and duplicated/abandoned work. Worth an explicit single-writer or
worktree-isolation convention.

### U6. Backlog status inflation

The first audit draft counted 44 `complete_contract` rows and mixed historical
completion states. After U1.2/U1.3 relabeling, 8 policy rows are explicitly
`advisory_contract`: report-only audit, CLI output, documentation, or test-only
contract exists, but no fail-closed runtime caller owns the rule. This removes
the worst status inflation without claiming those policies are enforced.

## Inter-module consistency issues

- contract ↔ audit: hand-mirrored, already drifted (U2).
- read-tool ↔ write-tool: `feedback-collect` ↔ `resolve-feedback.sh` not linked
  (U5).
- backlog ↔ downstream queue: resolution is manual and the existing resolver was
  missed (U5).
- principal selection: `AI_AUTO_PRINCIPAL` env export leaks into verify's pytest
  and breaks codex-default tests; launcher-evidence is the only safe path — an
  undocumented cross-module coupling that cost debugging time.
- review-gate ↔ verify ↔ nested review fixtures: re-entrancy + concurrent-session
  contention (U3).
- root ↔ template: ~22 byte-identical mirrors; every touch needs version bump +
  patch note + parity test (6 bumps/session).

## Candidate direction (for discussion, not yet approved)

1. Decide the contract layer's purpose: enforce (wire a few into the gate) or
   document (collapse Python+Bash to one, stop the 4-artifact-per-policy
   pattern). This is the biggest lever.
2. Split verify.sh; stop re-running the full monolith inside review-gate.
3. Make review weight proportional to diff scope (skip external LLM review for
   doc/backlog-only changes; keep verify).
4. Discoverability polish: have `feedback-collect` runtime output point at
   `feedback-resolve` (the docs already pair them; ST-P1-43 is already done).
5. Reserve `complete_contract` for items with a real caller; add a status for
   "advisory contract, no runtime caller" so U1/U6 stop being hidden.
6. Adopt a single-writer or per-agent worktree convention so concurrent agents
   stop churning the same tree (U5b).

Concrete "how" for the top lever (U1), since review asked for it: pick ~3 highest-
value contracts (e.g. `review_gate_short_summary`, `template_parity_boundary`,
`completion_acceptance_scope`), call them from the actual gate/verify path as
fail-closed checks, and demote the rest to a clearly-labeled advisory module —
rather than maintaining 38 contracts + 9 audits + ~2 tests each at
enforcement-grade cost for zero runtime effect.

None of this is implemented; this audit only records findings and evidence.
