# Defense R1 — RED TEAM: Engine correctness in global mode

Worktree: feat/global-toolize @ aa8d028. Surface: engine correctness when AI_AUTO is a
global tool operating on a derived (zero-framework-file) project. Read-only on source;
all repros built in throwaway temp projects.

## Verdict
No HIGH defect. The load-bearing seams are sound:
- SELF-DIR `$AH` resolution (`readlink -f "$0"`) holds under symlink, bare-name PATH,
  `bash script`, and engine paths with spaces+unicode (all tested green).
- verify seam fail-closes: a derived project with no `scripts/verify-project.sh` exits 1
  (NOTHING verified), never a silent green. verify always runs BEFORE the docs-only /
  provenance skip paths, so no skip can ride an untested tree.
- D6/C1/C7: base+overlay feed and `-ef` dedup behave correctly (base-only when project
  AGENTS.md absent; single feed in self-host; both fed in a derived project).
- Deletion set is clean: zero dangling refs to install-automation-template,
  check-template-version, refresh-guidance-baseline, ai-auto-template-status,
  ai-template-refresh, automation-base, template-manifest, guidance-baseline, or
  template-version-gate.yml in any kept .sh/.py/.yml. §13 ripple fixes (obsidian-autopush,
  ai-domain-pack manifest, ai-tmux-worktree) all applied. No `./scripts/` sibling-call
  survivors in live code (only usage strings / heredoc-generated runners).
- doctor: dead hook shim → fail; non-git → fail; --home outside engine → fail; all loud,
  no crash. ai-auto setup de-vendors pristine files + bakes hook shims + gitignores .omx
  correctly; unknown launcher verb errors with usage (exit 2).

## Ranked findings

### 1. MED — external-review runner hardcodes `./scripts/...`; broken in global mode
`scripts/run-ai-reviews.sh:358-361,439,441`. The generated external runner
(`.omx/external-review/run-reviewers-*.sh`, emitted when `REVIEW_EXECUTION_MODE=external`)
probes `${script_dir}/../../scripts/run-ai-reviews.sh` (= repo_root/scripts/...). In a
globalized zero-framework project that path does not exist, so it falls to
`repo_root="$(pwd)"` and then runs `./scripts/run-ai-reviews.sh` (:439) and
`./scripts/summarize-ai-reviews.sh` (:441) — both pwd-relative, both ABSENT in a derived
project. The runner dies with "No such file or directory".
- Repro: in a globalized project (no scripts/), `REVIEW_EXECUTION_MODE=external` gate →
  generated runner references `./scripts/run-ai-reviews.sh` which is not present.
- Severity: MED — opt-in path (used when AI CLIs hang), fails loudly (not silent/green),
  but the external-review feature is unusable in global mode, contradicting the §11/§14
  "gate runs from global, zero framework files in project" contract.
- Fix: resolve the engine via the baked/`$AI_AUTO_HOME` path (or `command -v
  run-ai-reviews.sh` on the §4-prepended PATH) when generating the runner, instead of
  `./scripts/...`. Bake `AI_AUTO_HOME` into the runner and call
  `"$AI_AUTO_HOME/scripts/run-ai-reviews.sh"` / `summarize-ai-reviews.sh`.

### 2. LOW — machinery-fold trigger keyed on pwd, executed from engine (asymmetry)
`scripts/review-gate.sh:505` and `hooks/pre-commit:49` gate the machinery fold on the
pwd-relative `[ -f scripts/verify-machinery.sh ]`, but EXECUTE the engine harness
(`"$AH/verify-machinery.sh"` / bare-name `verify-machinery.sh` on PATH). In the source
repo pwd==engine so both agree. In a derived project they diverge: a project that
coincidentally ships its own `scripts/verify-machinery.sh` AND changes `scripts/` would
trigger the ENGINE harness to run against the wrong tree.
- Severity: LOW — requires the exact coincidental filename in a derived project; harmless
  in practice (harness would just fail). The guard intent ("source repo only") holds for
  all realistic projects.
- Fix: gate on the engine copy too, e.g. `[ -f "$AH/verify-machinery.sh" ] && [ -f
  scripts/verify-machinery.sh ]`, or detect self-host by sentinel rather than a
  project-local filename.

### 3. LOW — `ai-auto setup` removes pristine AGENTS.md but seeds no thin overlay stub
`tools/ai-auto:14,74-83` treat `AGENTS.md` as a normal FRAMEWORK_PATH and `git rm` it when
byte-pristine, with no replacement stub. SPEC §8 step 2 / §6 specify "remove base, seed a
thin overlay stub (§6 read target)". After setup a globalized project has NO `AGENTS.md`
at all.
- Severity: LOW — `collect-review-context.sh` degrades to base-only with no crash (verified:
  full-context run in a stub-less project feeds the global base AGENTS.md exactly once), so
  the gate is unaffected. Arguably defensible under the "delete > add" mandate, but it is a
  literal deviation from the spec and leaves the project with no local guidance file.
- Fix: either seed a one-line overlay stub on pristine-removal (per §8.2) or amend the spec
  to document base-only as the intended global-mode behavior.

### 4. LOW — `template_parity_boundary` contract is residue of the retired template model
`scripts/self_demo_contracts.py:767-774` (+ test `tests/test_self_demo_contracts.py:540`)
still enforces `template_version_updated` / `patch_notes_updated` / `template_sync_check`
for a `template_owned_change` record — the AI_AUTO_TEMPLATE_VERSION/template-PATCH_NOTES
concept SPEC §2 deletes. Gated on `template_owned_change`, so it is inert (no live caller
sets it) and does not dangle at runtime, but it is surviving reference to the deleted
template-version concept in kept code, kept green only by its own unit test.
- Severity: LOW — no runtime dangle/crash; stale dead contract.
- Fix: drop `template_parity_boundary` and its test as part of the §2 delete set.

### 5. LOW — doctor `--project` warns on absent engine dirs (noise)
`scripts/automation-doctor.sh:519-523` runs `ensure_dir docs`, `docs/research`, `scripts`,
`.omx/reviewer-state` unconditionally; in a zero-framework globalized project these warn
"directory missing", contradicting the §12 "zero framework files is correct" intent.
- Severity: LOW — WARN only; doctor still exits 0, so "project PASSES" holds. Cosmetic.
- Fix: scope the framework-dir ensures to `MODE=home`; in project mode only ensure `.omx`.
