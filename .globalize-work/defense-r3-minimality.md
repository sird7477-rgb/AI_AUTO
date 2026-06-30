# Defense game ROUND 3 — RED TEAM (minimality / docs / §13 goal)

Worktree: /root/workspace/ai-lab-globalize  branch feat/global-toolize  HEAD c3b4781
Scope: BLOAT from R1/R2 fixes, DEAD CODE / orphans, DOCS truthfulness by execution,
§13 e2e on HEAD, SPEC↔CODE drift, full suite.

## Verdict: CLEAN (no HIGH/MED). 2 LOW only.

## Suite — GREEN
- `.venv/bin/python -m pytest -q` → 237 passed, 1 skipped.
- `bash scripts/verify-machinery.sh` → pytest 237/1 + all bash machinery tests PASS (VMEXIT 0).
  (Note: a bare `python3 -m pytest` fails on tests/test_app.py — flask missing — because the
  suite is designed to run via `.venv/bin/python`; not a regression, pre-existing harness fact.)

## §13 GOAL e2e on HEAD — PROVEN
Throwaway already-patched project (vendored WORKFLOW/INCIDENT_OPS/review-gate.sh/verify.sh/AGENTS.md
byte-identical + one customized doc + main.py) → `ai-auto setup`:
- 5 pristine vendored copies STAGED for `git rm`; customized doc KEPT+reported; verify.sh removed
  (pristine); baked-path pre/post-commit shims installed in `.git/hooks`; `.omx/` excluded.
- After commit: `git ls-files` = ONLY `docs/SECURITY_COMPLETION.md` (customized) + `main.py`.
  ZERO committed framework files. ✅
- `ai-auto gate`/`verify`/`doctor` exec the global engine (review-gate.sh / verify.sh /
  automation-doctor.sh --project) against $PWD. ✅
- post-commit advisory fired on the `--no-verify` commit (gate-bypass non-silent). ✅
- Idempotent re-run: 0 removed, hooks+exclude re-asserted, exit 0. ✅
- Self-host guard: `ai-auto setup .` inside engine ABORTS, no mutation. ✅

## DEAD CODE / orphans — NONE
- Grep of whole tree (code+tests) for every deleted identifier (automation-base,
  AI_AUTO_TEMPLATE_VERSION, ai-auto-template-status, ai-template-refresh, check-template-version,
  install-automation-template, refresh-guidance-baseline, check_offmanifest_shadows,
  template_parity_boundary, guidance-baseline, template-manifest, check_template_staleness,
  template-version-gate) → no live references in KEPT code.
- verify-machinery.sh:5842/6319/6375 `tools/ai-auto-init` = DELIBERATE stale-link fixtures
  (simulate an old checkout, then assert install/bootstrap/doctor REPOINT `aiinit` → `tools/ai-auto`).
  Not dead code; the asserts pass.
- §13 ripple fixes all landed: obsidian-autopush.sh:81-83 (verify-machinery+domain-packs sentinel),
  ai-domain-pack (template_version field dropped — grep zero), ai-tmux-worktree:27
  (`[ -d domain-packs ] || [ -d .omx ]`), collect-review-context.sh:187-194 (C1 base+overlay with
  `-ef` dedup). doc-budget reads project AGENTS.md only.
- install-global-files.sh codex-wrapper drift-notice block fully removed; no orphan vars
  (patch_notes/drift_default/status_output/notice_key/template_status_timeout/latest_note → grep zero).

## DOCS truthfulness by execution — CONSISTENT
- `ai-auto setup` / `gate` / `verify` / `doctor` all exist and behave as documented in
  NEW_PROJECT_GUIDE.md, GLOBAL_TOOLS.md, README.md.
- verify.sh→verify-project.sh marker is consistent everywhere (install-global cd-detector,
  GLOBAL_TOOLS, doctor warn-loud). No verify.sh/verify-project.sh contradiction survives.
- `aiinit` legacy symlink → tools/ai-auto; GLOBAL_TOOLS.md:25 documents it as legacy "prefer
  ai-auto setup"; no-arg `ai-auto` prints usage (exit 1). Matches doc.
- README "full = machinery + product smoke": engine ships scripts/verify-project.sh
  (run_product_pytest+run_product_smoke) so the claim holds in-repo.
- Grep of docs/*.md + README for every deleted concept → ZERO stale instructions.

## BLOAT / minimality — each R1/R2 mechanism is minimal & SPEC-mandated
flock (advisory lock, graceful degrade), atomic single `git rm` of pre-validated set,
git-config-scrub (`for _gcv in "${!GIT_CONFIG_KEY_@}" ...`), shim dir-guard
(`! [ -f ] || ! [ -x ]`) — all in tightest defensible form; nothing a shorter idiom replaces.
Self-heal §4 guard repeated across entrypoints is by design (each entrypoint reachable
un-sourced), not duplication-to-remove.

---

## FINDINGS

### LOW-1 — SPEC.v3.md line anchors stale vs HEAD (spec/code drift)
.globalize-work/SPEC.v3.md §5/§9/§13 cite review-gate.sh:592 / :604-624 / :606 and
collect-review-context.sh:187 / doc-budget.sh:167 etc. Actual post-R1/R2 lines:
review-gate.sh scope=product at :493, machinery FOLD :505-526, fold-trigger grep `^(scripts/|hooks/)`
at :508. SPEC explicitly pins anchors to base "HEAD 6e90184" (design-time predictions), and the
BEHAVIOR matches in every case, so this is informational drift in an internal design doc, not a
user-facing stale instruction. Fix (optional): re-anchor SPEC line numbers to c3b4781 or drop the
exact line cites.

### LOW-2 — tools/ai-auto:12-13 provenance comments name deleted files
The FRAMEWORK_PATHS comment references the deleted `install-automation-template.sh` and the retired
`AI_AUTO_TEMPLATE_VERSION` marker to explain where the list came from. Harmless (explanatory only,
no code path), but mentions dead identifiers. Fix (optional): shorten to "managed framework files
the old copy model vendored" without naming the deleted file.

(Observation, not a finding: FRAMEWORK_PATHS is a 43-entry hardcoded allowlist re-deriving the old
MANAGED_PATHS. It is the minimal SAFE way to identify managed files — a heuristic would risk
git-rm'ing legitimately-named project files — so it is kept by design, not bloat.)
