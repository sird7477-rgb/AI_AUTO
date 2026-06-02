# AI_AUTO Principal Detection Fix Plan (2026-06-02)

Backlog candidate (proposed `ST-P1-23`). Discovered during the ST-P1-22
model-routing Ralph run.

## 1. Problem

`scripts/run-ai-reviews.sh` resolves the active principal only from the
`AI_AUTO_PRINCIPAL` env var and **silently defaults to `codex`** when it is
unset (`normalize_principal_runtime`, via `scripts/ai-principal-runtime.sh`).
The launcher-recorded evidence file
(`.omx/state/principal-runtime/current.env`, e.g. `principal_runtime=claude`) is
only **validated** when `AI_AUTO_PRINCIPAL` is already set to a non-codex value;
it never **drives** the selection.

Consequence (observed): a Claude Code session that ran review-gate without
`AI_AUTO_PRINCIPAL=claude` was treated as principal `codex`, which put Claude in
the reviewer slot and then hit a usage limit — a false "blocker" caused purely
by principal misdetection. The repo cannot independently sense which runtime is
driving it, so a missing declaration must not be silently coerced to codex.

## 2. Fix

- **(a) Evidence can select the principal.** When `AI_AUTO_PRINCIPAL` is unset
  and a valid launcher evidence file exists (`source=ai-auto-principal-launcher`,
  matching `workspace`), adopt its `principal_runtime`. The launcher's
  declaration is then honored without re-passing the env var every invocation.
- **(b) Mismatch fails closed.** When `AI_AUTO_PRINCIPAL` is set but disagrees
  with a valid evidence file, stop with `principal_unavailable` instead of
  proceeding (extends the existing non-codex evidence validation).
- **(c) Visible notice on silent default.** When neither an explicit
  `AI_AUTO_PRINCIPAL` nor valid evidence exists and the principal falls back to
  `codex`, emit a one-line notice: principal defaulted to codex; set
  `AI_AUTO_PRINCIPAL` (or record launcher evidence) if this session is
  claude/gemini.

## 3. Scope of changes

- `scripts/run-ai-reviews.sh` (+ `templates/automation-base/scripts/` copy):
  evidence-driven selection (a), mismatch fail-closed (b), default notice (c).
- `scripts/ai-principal-runtime.sh` (+ template copy) if a shared resolution
  helper is the cleaner home for (a)/(b).
- `tests/test_principal_runtime_contracts.py`: cases for evidence-driven
  selection, env-vs-evidence mismatch fail-closed, and the silent-default
  notice. Keep the existing hermetic-evidence isolation pattern
  (`AI_AUTO_PRINCIPAL_EVIDENCE` → tmp).

## 4. Invariants / non-goals

- Repo-local permissions remain identical across principals (existing contract);
  only reviewer rotation and selection change.
- Evidence is trusted only when launcher-owned and workspace-matched; manual or
  mismatched evidence still fails closed (existing guard preserved).
- No new authority for routing/evidence; selection changes the lane owner, not
  the workflow contract.
- Template parity: both copies byte-identical.

## 5. Verification

- `./scripts/verify.sh` green.
- `./scripts/review-gate.sh` (principal=claude) unanimous.
