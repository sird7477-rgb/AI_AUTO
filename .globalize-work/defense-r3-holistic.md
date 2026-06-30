# Defense R3 — RED TEAM: HOLISTIC / INTEGRATION (HEAD c3b4781)

Surface: the WHOLE global-mode lifecycle and where pieces interact. Method: full
lifecycle on a throwaway DERIVED project (vendored pristine framework + 1 customized
file + own code) `setup → commit(shim fires) → verify → gate-seam → doctor`; engine
self-host lifecycle; D6 base/overlay vs doc-budget; state-leftover grep; suite.

## SUITE — GREEN, matches claimed baseline
- `bash scripts/verify-machinery.sh`: VMEXIT=0 — 237 passed / 1 skipped (embedded) +
  machinery 101 pass / 0 fail / 6 skip. No NEW failure.
- `.venv/bin/python -m pytest -q`: 237 passed, 1 skipped.

## VERDICT: DEFECTS 1 (highest HIGH)

---

## H1 — HIGH — `ai-auto verify` is BROKEN in every derived project (launcher + verify.sh default scope + engine-only machinery harness compose badly)

One-line: the documented standalone command `ai-auto verify` crashes (exit 127) in any
globalized project and can NEVER go green, because the launcher sets no scope, verify.sh
defaults to `full`, and `full` runs the ENGINE's `verify-machinery.sh` against the
project cwd.

Why it slipped prior rounds: every earlier "verify seam fail-closes" check exercised
verify.sh with the scope set explicitly — the GATE passes `AI_AUTO_VERIFY_SCOPE=product`
(review-gate.sh:493), and R1/R2 repros set product by hand. Nobody ran the actual
launcher subcommand `ai-auto verify` end-to-end in a derived tree. Pure integration gap.

Chain:
- `tools/ai-auto:230` — `verify) exec "$AI_AUTO_HOME/scripts/verify.sh" "$@"` — sets NO
  scope.
- `scripts/verify.sh:7` — `AI_AUTO_VERIFY_SCOPE="${AI_AUTO_VERIFY_SCOPE:-full}"` → default
  `full`.
- `scripts/verify.sh:54-57` — `full` runs `"$AH/verify-machinery.sh"` (the engine's own
  self-test harness) BEFORE `run_product`.
- `scripts/verify-machinery.sh:7` — `.venv/bin/python -m pytest` from `$(pwd)` (the
  derived project) → exit 127 (no `.venv`). Even WITH a venv it proceeds to
  `bash -n scripts/bootstrap-ai-lab.sh` (an engine-only file) → "No such file or
  directory" → 127, and would then `shellcheck scripts/*.sh` on the project's scripts.

Repro (throwaway derived project, fully de-polluted via `ai-auto setup`):
```
ai-auto verify                                  # exit 127 — ".venv/bin/python: No such file"
mkdir -p .venv/bin; ln -s "$(command -v python3)" .venv/bin/python
printf '#!/usr/bin/env bash\necho ok\n' > scripts/verify-project.sh; chmod +x scripts/verify-project.sh
ai-auto verify                                  # exit 127 — "scripts/bootstrap-ai-lab.sh: No such file"
AI_AUTO_VERIFY_SCOPE=product ai-auto verify     # exit 0 — delegates to verify-project.sh  (the path the gate uses)
```

Impact (HIGH — broken-lifecycle + safety property defeated):
1. The fail-closed safety contract ("absent verify-project.sh → exit 1, NOTHING was
   verified", verify.sh:47-50) is UNREACHABLE via the documented command — the run dies
   at the machinery step before `run_product` is ever consulted. A confusing 127 replaces
   the designed loud exit-1.
2. A CORRECTLY set-up project with a PASSING `scripts/verify-project.sh` STILL cannot get
   a green `ai-auto verify`. The verify half of the verify-review loop is dead in global
   mode.
3. Docs actively send users into this: NEW_PROJECT_GUIDE.md:101, :126, :278 and
   CURRENT_STATE.md:279, :461 all instruct a globalized project to run `ai-auto verify`.

Fix (one place — make the default scope engine-aware, mirroring the gate's existing
machinery-fold guard at review-gate.sh:506). In `scripts/verify.sh` replace line 7:
```
if [ -z "${AI_AUTO_VERIFY_SCOPE:-}" ]; then
  if [ -f "$AH/verify-machinery.sh" ] && [ "$(dirname "$AH")" -ef "$(pwd)" ]; then
    AI_AUTO_VERIFY_SCOPE=full      # engine self-host: machinery + product
  else
    AI_AUTO_VERIFY_SCOPE=product   # derived project: project verify only (fail-closed seam)
  fi
fi
```
This makes `ai-auto verify` reach the fail-closed/run_product seam in derived projects
(exit 1 when absent, exit 0 when verify-project.sh passes) while the engine self-host
keeps full machinery scope. Equivalently, the launcher could export
`AI_AUTO_VERIFY_SCOPE=product` for `verify)`, but verify.sh is the better single seam.

---

## LOW — `ai-auto doctor` hardwires `--project`, so engine self-check via the launcher is project-mode
`tools/ai-auto:231` always passes `--project`, so `ai-auto doctor` in the engine repo runs
`check_project_globalization` and WARNS that the engine's own `.git/hooks/{pre,post}-commit`
"hook shim not installed" + suggests `ai-auto setup` — confusing for the engine. Mitigated:
`ai-auto doctor --home` works (MODE ends home, 0 failed, 101 pass), and the launcher is
documented as "diagnose the project". Cosmetic only; not gate-affecting.

---

## CLEAN areas (attacked, held)
- Lifecycle on derived project: `setup` de-pollutes (5 pristine staged for deletion, 1
  customized kept), `commit` fires both shims (pre-commit pytest 1 passed; post-commit
  no-verdict warning), de-polluted tree carries ZERO framework files. No crash/contradiction.
- STATE-LEFTOVER: after setup + commit, the only framework state is `.omx/` and it is
  gitignored via `.git/info/exclude` (`git check-ignore .omx/` → matched). Nothing
  AI_AUTO writes into the project tree is committable. Pollution NOT reintroduced.
- Self-host guard: `ai-auto setup` on the engine ABORTs before any mutation (exit 1).
- `ai-auto doctor --home` on engine: 0 failed. D6 machinery fold still runs in engine.
- D6 interaction: collect-review-context.sh:194 feeds GLOBAL base AGENTS.md + project
  overlay (base-only when project AGENTS absent; `-ef` dedup in self-host); doc-budget.sh
  reads PROJECT-ONLY AGENTS.md (line 132, no AI_AUTO_HOME ref) — the two do NOT both add
  base. Correct, no double-count.
- Gate verify wiring: `ai-auto gate` runs verify.sh with explicit `product` scope
  (review-gate.sh:493) → reaches run_product correctly (proven exit 0 with a passing
  verify-project.sh). The gate path is NOT affected by H1 — only the standalone command is.
- Re-entrancy: pre-commit shim → engine pre-commit runs pytest only (no session-lock at
  commit); gate acquires the lock then nested verify is re-entrant (shared
  AI_AUTO_SESSION_ID). 75 sentinel only from a live foreign holder. No bad composition.
