# Defense R5 — HOLISTIC / INTEGRATION lens (red)

Target: feat/global-toolize @ 775a081. Read-only. Full global-mode lifecycle exercised on
real temp git projects.

## Verdict: DEFECTS 2 (highest LOW). Core lifecycle CLEAN — no new HIGH/MED.

The full DERIVED lifecycle and ENGINE self-host run end-to-end with no crash, no wrong
verdict, no silent skip, no pollution. Both findings below are minor truthfulness/
consistency gaps that are fail-loud / disclosed-by-design, not broken lifecycle.

---

## GREEN gate (required)
- `.venv/bin/python -m pytest -q` → **237 passed, 1 skipped**. (System `python3` lacks
  flask — the suite's canonical runner is `.venv`; not a defect.)
- `bash scripts/verify-machinery.sh` → **VMEXIT=0**, embedded pytest 237/1, no real
  failures (failure-pattern grep empty; all "fail" hits are "0 failed"/test names).
- Engine self-host NOT regressed.

## Lifecycle exercised GREEN (real temp repos)
- DERIVED setup → de-pollutes 3 pristine framework files (staged), installs pre/post
  shims, gitignores .omx. Shim body byte-correct (scrub + F1 guard + baked path).
- pre-commit shim → engine hook → **fail-closed on a real failing test** (exit 1, commit
  blocked); passes on green; warns-not-blocks when no runner.
- post-commit advisory fires on bypass; **goes silent when a recent proceed verdict
  exists** (post-commit ↔ gate handshake OK).
- `ai-auto verify`: **fail-closed** (exit 1, "NOTHING was verified") with no
  verify-project.sh; **delegates** to verify-project.sh when present (exit 0). Gate uses
  the same verify.sh (product scope) — no analog of the R3 verify crash.
- collect-review-context **D6**: in a de-polluted derived project the **GLOBAL
  AGENTS.md is pulled into full-detail context** (`### /root/workspace/ai-lab-globalize/
  AGENTS.md`); lightweight default omits it as designed.
- `ai-auto doctor` (project) + `doctor --home` (engine, 101 pass) clean.
- **Legacy upgrade path**: full-body copy-model hook (markers `AI_AUTO worktree-safe
  hook`/`post-commit guard`) is **upgraded to the scrubbing shim** by setup AND the
  upgraded shim **fires** (engine pytest runs on next commit).
- Self-host guard aborts `ai-auto setup` on the engine; F3 dirty-index guard aborts on
  staged non-deletions.
- **Odoo coexistence + real `git push`** to a local bare remote: framework pre-commit
  shim + odoo pre-push live together; clean manifest pushes; a manifest referencing a
  missing data file is **BLOCKED by the odoo pre-push manifest screen** (exit 1) while
  the framework pre-commit still gates the commit. Git state stays sane.
- **Canonical git-exec-env denylist byte-identical** across all 4 copies (launcher,
  hooks/pre-commit, hooks/post-commit, baked shim) — no drift.

---

## DEFECTS

### D1 (LOW) — odoo pre-push claims "auto-installed by aiinit"; nothing wires it in global mode
- One-line: The odoo pre-push hook header says it is "auto-installed into Odoo projects by
  aiinit", but in global mode no lifecycle step ever wires it into `.git/hooks/pre-push` —
  so an adopter's Odoo registry-load gate is a dormant file that never fires until
  manually wired.
- Repro: `ai-domain-pack refresh --apply` copies the pack only into
  `.omx/domain-packs/odoo/` (gitignored); `ai-auto setup` only manages pre-commit/
  post-commit. `aiinit` is now a bare symlink to `tools/ai-auto` (commands:
  setup/gate/verify/doctor) — it has NO pack-install behavior. The comment was true under
  the deleted copy-model installer; globalization made it false.
- Severity: LOW (stale comment + silent non-activation; the hook itself "skips loudly /
  NOT VALIDATED" once wired, and README labels the pack an "ignored reference").
- File: templates/domain-packs/odoo/hooks/pre-push:2-3 (and the parallel `aiinit`
  framing).
- Fix: change the header to "installed as a reference by `ai-domain-pack refresh
  --apply`; wire it into `.git/hooks/pre-push` (or core.hooksPath) yourself" — drop the
  `aiinit` auto-install claim. Optionally have doctor warn when an odoo project has the
  pack staged but no pre-push wired.

### D2 (LOW) — pre-commit gates via pytest only, bypassing the verify-project.sh seam
- One-line: The engine pre-commit hook hardcodes a pytest run and never invokes the
  project's own `scripts/verify-project.sh`, so in a NON-pytest derived project (Node/Go/
  docker-smoke) the commit gate is a no-op even though the project HAS real verification.
- Repro: a derived project whose real checks live in verify-project.sh and which has no
  collectible pytest → pre-commit prints "no pytest available … not blocking" (or "exit 5
  … not blocking") and the commit proceeds with zero verification. verify.sh treats
  verify-project.sh as "the project's own real verification" (fail-closed), but
  pre-commit does not consult it.
- Severity: LOW (disclosed: the hook's own warning + the post-commit "run ai-auto gate +
  verify before pushing" nag; by-design fast-gate vs full-gate split).
- File: hooks/pre-commit:33-66 (pre_commit_run_pytest + dispatch).
- Fix (optional): when no pytest is collectible AND `scripts/verify-project.sh` is
  present+executable, run it as the commit gate; else keep the warn-and-defer. Or document
  the pytest-only commit gate explicitly so non-Python projects know commit-time gating is
  deferred to the gate.

## Non-defects confirmed
- scripts/ dir vanishing after de-pollution (only held framework files) — cosmetic;
  user re-creates it for verify-project.sh. Not a code defect.
- `ai-auto verify` from a repo SUBDIR fails-closed (./scripts/verify-project.sh is
  cwd-relative) — pre-existing, fail-closed (never false-green), operators run from root.
- Single pre-commit slot (framework shim vs an odoo version-bump pre-commit) — inherent
  git limitation; setup conservatively warns+keeps a custom hook; git-tier README already
  tells the user to author a combined hook.
