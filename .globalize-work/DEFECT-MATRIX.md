# DEFECT MATRIX — v3 (D1–D8, S1–S6, F1–F10 each → resolved-by + residual)

Verified against the tree (branch feat/global-toolize, HEAD 6e90184). "Residual" = honest flag of
anything a locked decision does NOT fully close. SPEC v3 §refs.

## Correctness defects (v1 round: D1–D8)

| # | Sev | Finding | Resolved by | SPEC v3 § | Residual |
|---|-----|---------|-------------|-----------|----------|
| D1 | CRIT | Retiring staleness/version/drift apparatus breaks KEPT `verify-machinery.sh` self-tests + `tests/test_template_global_contracts.py` | atomic delete | §2 | NONE — delete the test blocks + unit test in the SAME commit as the apparatus; replace with a zero-framework-file test. IMPL greps to zero. |
| D2 | HIGH | `verify.sh` is a CLIENT of framework siblings absent in a zero-vendor project | §4+§5 | §4,§5 | NONE — `verify.sh` is GLOBAL; siblings via PATH+self-heal guard; `-f` source guards become `command -v`. |
| D3 | HIGH | blunt `git rm` deletes PROJECT-AUTHORED content | §8 | §8 | LOW — needs reliable pristine path map; relocated/renamed read as "differ" → SAFE side (kept). |
| D4 | HIGH | kept CI `template-version-gate.yml` hard-fails | delete | §2 | NONE — only workflow; no other CI calls engine scripts. |
| D5 | HIGH | `automation-doctor` `REQUIRED_FILES` flags a globalized project broken; `:67` gates on deleted tool | §12 | §12 | NONE. |
| D6 | MED | Engine (not just Claude Code) reads PROJECT `AGENTS.md`; moving base to `~/.claude` degrades reviewer context | §6 (C1 closure, scoped) | §6 | NONE — `collect-review-context.sh:187` now reads global base + overlay (deduped). FULLY closed; see F1 for why doc-budget is deliberately EXCLUDED. |
| D7 | MED | global `core.hooksPath` collides with odoo `pre-push` | §9 | §9 | NONE — shims into resolved hooks dir; pre-commit/post-commit/pre-push are distinct names. RE-AFFIRMED unchanged. |
| D8 | MED | retiring install/refresh orphans doc-budget inherited-baseline | §7 | §7 | NONE — sole consumer doc-budget, sole writer deleted refresh script. |

## Simplicity / extensibility (S1–S6)

| # | Finding | Resolved by | § | Residual |
|---|---------|-------------|---|----------|
| S1 | biggest win under-deleted (`templates/automation-base` 29 files + installer ~600 lines) | §2 wholesale delete | §2 | NONE — dwarfs every added line. |
| S2 | `.ai-auto/` manifest + baseline are copy-model-only | §2/§7/§8/§12 | — | NONE. |
| S3 | `$AI_AUTO_PROJECT` referenced nowhere; YAGNI | §4 dropped | §4 | NONE. |
| S4 | `init`+`migrate` should be ONE idempotent command | §8 `ai-auto setup` | §8 | NONE. |
| S5 | new launcher + per-file `SCRIPT_DIR` heavier than PATH-strip | §4 one PATH line + self-heal guard | §4 | LOW — the `s\|./scripts/\|\|` sweep must be mechanical/complete; IMPL counts call-sites. |
| S6 | "new pack = subcommand + hook entry" forces core edit | §10 documented convention (C6) | §10 | NONE for correctness — extensibility is a documented seam, not built (YAGNI); a pack still needs no core edit to add a global dir. |

## v2 red-team residuals (F1–F10) — each → resolved-by + residual

| # | Sev | Finding | Locked fix | SPEC v3 § | Residual |
|---|-----|---------|------------|-----------|----------|
| F1 | CRIT | D6 full-closure folded into `doc-budget.sh:167` (a 220-line CAP) → self-host 169+169=338>220 → gate RED; derived project counts engine base against own budget | C1 | §6 | NONE — closure scoped to `collect-review-context.sh` ONLY; doc-budget:167 reads PROJECT overlay only. Verified: AGENTS.md=169, cap=220 → overlay-only passes. |
| F2 | CRIT | `ai-auto setup` in `$AI_AUTO_HOME` on clean tree → byte-matches every file → `git rm`s the whole engine | C2 | §8.0 | NONE — hard self-host guard runs FIRST (toplevel==`$AI_AUTO_HOME` OR engine sentinel present → abort); never `git rm` in engine repo. |
| F3 | HIGH | 3 KEPT tools dangle on deleted marker `templates/automation-base/AI_AUTO_TEMPLATE_VERSION` (obsidian silent-death, ai-domain-pack "unknown", ai-tmux-worktree mis-detect) | C3 | §13 | NONE — all three re-pointed to deleted-file-free sentinels; obsidian/ai-tmux use `domain-packs`+`verify-machinery`/`.omx`; ai-domain-pack drops the dead `template_version` field. Refs confirmed live (obsidian:81, ai-domain-pack:122, ai-tmux-worktree:27-28). |
| F4 | HIGH | v2 `verify.sh` dropped `AI_AUTO_VERIFY_SCOPE` → REVIEW_* env-leak regression + double machinery + derived-project green no-op | C4 | §5,§12 | NONE — scope dispatch + scrub + single machinery fold KEPT exactly (verified verify.sh:7,78-93 + review-gate:592,604-624); derived real test = `verify-project.sh`; doctor --project warns loudly when absent. |
| F5 | HIGH | shims/dispatcher depend on profile PATH/`$AI_AUTO_HOME` in git-hook env → unset → blocked commit / command-not-found | C5+C7 | §4,§9 | NONE — install BAKES `readlink -f` absolute engine path into each shim; shim sets PATH before exec; entrypoints carry the §4 self-heal guard. |
| F6 | MED | run-parts failure semantics unspecified (pre-commit fail-closed; post-commit isolate; exit-5) | C6+C7 | §9,§10 | NONE — run-parts DROPPED (C6); the single relocated `pre-commit` body keeps fail-closed + exit-5 handling; `post-commit` always exit 0. |
| F7 | MED | machinery-fold grep `^scripts/` won't fire on relocated top-level `hooks/**` | C7 | §9 | NONE — both grep anchors updated to `^(scripts/\|hooks/)` (review-gate:606 + relocated hooks/pre-commit body); dead `automation-base/*` alternatives removed. |
| F8 | LOW-MED | bare-name siblings have no fallback outside a re-sourced profile | C7 | §4 | NONE — §4 self-heal guard (`readlink -f` + PATH prepend) at every entrypoint makes bare-name resolve in any context. |
| F9 | LOW | D6 closure double-feeds AGENTS.md in self-host (reviewer-context + duplicate-report noise) | C7 | §6 | NONE — dedup: skip global base when `-ef` the project file. |
| F10 | LOW-MED | §10 run-parts + `packs/<verb>` routing is YAGNI (added beyond any defect) | C6 | §10 | NONE — DROPPED entirely; extensibility is a documented convention, restoring the shortest-code mandate. |

## Net verdict (v3)
Every D1–D8, S1–S6, and F1–F10 is resolved by a locked correction with NO residual integrity risk.
D3/S5 carry LOW operational residuals only (both fall to the safe side: kept-not-deleted /
mechanical-sweep-with-counts). No finding remains OPEN after v3.
