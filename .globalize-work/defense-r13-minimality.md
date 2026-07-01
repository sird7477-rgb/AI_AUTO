# Defense R13 — MINIMALITY + GOAL lens (RED TEAM, final gauntlet #3, HEAD 26d96db)

Read-only. Suite GREEN: **237 passed, 1 skipped** via `.venv` (98s).

## Verdict: CLEAN. GOAL = **FULLY MET (Y)**.

R12-1 (the AI_AUTO_TEMPLATE_VERSION retired-file gap) is CLOSED at HEAD 26d96db. The whole
deliverable is done: goal met + minimal + no dead code + docs truthful + suite green.

---

## GOAL §13/§14 DEFINITIVE e2e — 7/7 + both retired + customized + app + zero framework files
Throwaway already-patched project: committed pristine framework (AGENTS.md, docs/WORKFLOW.md,
review-gate.sh, verify.sh) + BOTH retired files (docs/PATCH_NOTES.md `# AI_AUTO Patch Notes`
marker AND AI_AUTO_TEMPLATE_VERSION `2026.06.30.6`) + customized docs/DOMAIN_PACKS.md + app
files (src/app.py, README.md) → `ai-auto setup` → commit:
- 4 pristine REMOVED ✓; **both retired files REMOVED** (PATCH_NOTES + AI_AUTO_TEMPLATE_VERSION) ✓
- customized DOMAIN_PACKS.md KEPT with content intact ✓; app files untouched ✓
- `.omx/` gitignored via info/exclude ✓; baked-path pre/post-commit shims installed ✓
- idempotent re-run = "Nothing to remove" no-op ✓
- After adoption commit: `git ls-files` shows **ZERO AI_AUTO framework files** ✓
ORIGINAL user goal (project repo no longer polluted by AI_AUTO framework files / version-bump
churn) — **FULLY met, Y**. Every old-copy-model project's committed AI_AUTO_TEMPLATE_VERSION is
now de-polluted (the last vendored-file class R12 flagged).

Mechanism (tools/ai-auto): AI_AUTO_TEMPLATE_VERSION in FRAMEWORK_PATHS:51 + is_retired_framework_file:80
case with version-string first-line guard (`^[0-9]{4}\.[0-9]{2}\.[0-9]{2}`); de-polluted in the
same atomic review_git `git rm` as PATCH_NOTES via the existing retired[]/rmset[] merge. No new
code path — the R11-1 mechanism was simply extended to the sibling. Minimal shape.

## DEAD CODE — CLEAN
git-grep tree-wide for every P1-R12 deletion (install-automation-template, ai-auto-init,
ai-template-refresh, ai-auto-template-status, check-template-version, refresh-guidance-baseline,
template-version-gate, AI_AUTO_TEMPLATE_STALENESS). In the LIVE kept tree (docs/ tools/ scripts/
hooks/ templates/ AGENTS.md README.md): ZERO dangling refs. Hits only in (a) `plans/*` — pre-existing
archival design docs UNTOUCHED by the diff (`git diff 6e90184..HEAD -- plans/` empty), and (b)
`.globalize-work/*` audit notes that intentionally describe the deletions. Neither is a live ref.

## MINIMALITY — no actionable defect
- R12 guard subcommand expansion: SUBS list (verify-machinery:7375 `diff|show|log|blame|status|
  checkout|restore|reset|stash|apply|archive|cat-file`) covers the full clean-filter set incl.
  status; 67 sites hardened; no drift vs launcher/tool usage. Correct, not reducible.
- Inline `--attr-source="$_et"` empty-tree pattern (7 standalone tools: automation-doctor,
  micro-check, write-session-checkpoint, ai-home, ai-rebuild-plan, ai-tmux-worktree, workspace-scan):
  the `hash-object -t tree /dev/null || echo 4b825dc…` is load-bearing (SHA-256 repos need the
  computed hash; a bare constant reopens the RCE on SHA-256) and each tool is intentionally
  dependency-free (does not source git-harden.sh). Cannot PROVE a shorter correct form without
  coupling standalone tools to a sourced helper (which adds its own line + coupling). Not actionable.
- retired[]/rmset[]/is_retired_framework_file merge (ai-auto) is the minimal retired-de-pollution
  shape; single-sourced git-scrub.sh/git-harden.sh (no copy drift). No dead helper/var/stale comment.

## DOCS / SPEC.v3 / AGENTS — truthful + in sync
- Onboarding commands in docs match launcher dispatch verbatim: `ai-auto setup|gate|verify|doctor`.
- NEW_PROJECT_GUIDE.md:23-26 now explicitly names BOTH retired files (`docs/PATCH_NOTES.md`,
  `AI_AUTO_TEMPLATE_VERSION`) as content-marker-recognized `git rm` targets — the R12-1 secondary
  doc knock-on ("any framework files" over-claim) is CLOSED; the claim is now literally true.
- No doc references any deleted tool/flow/file (grep clean over docs/ AGENTS.md README.md).

## SUITE — GREEN 237 passed / 1 skipped via .venv.
