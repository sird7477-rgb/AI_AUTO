# IMPL-PLAN — v3, ordered, file-by-file (blue-team-sized)

Branch feat/global-toolize, worktree `/root/workspace/ai-lab-globalize` ONLY. All counts/anchors
verified against the tree (HEAD 6e90184). Each step = one blue-team unit. Order matters: the DELETE
+ its tests land ATOMICALLY (D1) before the engine self-test can go green.

## STEP 0 — pristine snapshot (enables D3 hash compare)
- For `ai-auto setup`, map {managed framework filename → `$AI_AUTO_HOME` pristine path}; source of
  truth = the live engine tree (`scripts/*`, `docs/*`, base `AGENTS.md`). Compute sha256 on demand;
  no new state file.

## STEP 1 — DELETE copy model + apparatus (atomic with STEP 2)
`git rm -r`: `templates/automation-base/`, `scripts/install-automation-template.sh`,
`scripts/check-template-version.sh`, `scripts/refresh-guidance-baseline.sh`,
`tools/ai-auto-template-status`, `tools/ai-template-refresh`,
`.github/workflows/template-version-gate.yml`.

## STEP 2 — DELETE the apparatus's tests (SAME commit as STEP 1 — resolves D1)
- `tests/test_template_global_contracts.py` — DELETE wholesale.
- `scripts/verify-machinery.sh` — DELETE retired-surface blocks. Verified clusters: `897-902`,
  `1020-1140`, `4070`, `4363-4435`, `5464`, `5522-5549`, `5909-5986`, `6068-6221`, `6615-6739`,
  `6973-6997`, `7132-7144`, `7205-7212`, `7584-7666` (+ header refs `19-20`,`353`). After deletion:
  `git grep -nE 'check-template-version|template_staleness|ai-auto-template-status|AI_AUTO_TEMPLATE_VERSION|guidance-baseline|template-manifest|ai-template-refresh|refresh-guidance-baseline' scripts/verify-machinery.sh` MUST be empty.

## STEP 3 — review-gate.sh: remove staleness gate + FIX fold grep (D1 + F7)
- Delete `check_template_staleness()` + verdict writer + callers. Anchors: `262,277,283,295,
  339-392,385-390,579-580`. Remove `AI_AUTO_TEMPLATE_STALENESS` doc/usage refs (`:295`).
- **F7: change the machinery-fold trigger grep at `:606`** from
  `'^(scripts/|templates/automation-base/scripts/|templates/automation-base/hooks/)'` to
  `'^(scripts/|hooks/)'`.
- Leave the verify call (`:592` `AI_AUTO_VERIFY_SCOPE=product`) and the scrubbed machinery fold
  (`:604-624`, `env -u REVIEW_DECISION_GATE …`) INTACT — C4. Add the §4 self-heal guard at top.

## STEP 4 — PATH sibling resolution + self-heal guard (R2; C5/C7 → D2,F5,F8)
- `scripts/install-global-files.sh`: (a) export `AI_AUTO_HOME` into profile; (b) prepend
  `$AI_AUTO_HOME/scripts` (+ any `templates/domain-packs/*/bin`) to PATH; (c) DROP the `~/bin`
  symlinks for the two deleted tools (`:29-30`, `:1110`, `:1112`); (d) ADD `~/bin/ai-auto` symlink;
  (e) drop `check_source_helper` for the deleted tools (`:1003`,`:1005`); (f) remove the
  `ai-auto-template-status` post-commit-notice block (`:791-818`).
- Mechanical sweep `s|\./scripts/||` across exec call-sites. Verified per-file `./scripts/` counts:
  `verify-machinery.sh` 135 (most inside cd-to-tmp fixtures — PATH resolves; many removed in STEP 2),
  `review-gate.sh` 14, `automation-doctor.sh` 13, `run-ai-reviews.sh` 11, `install-ubuntu-prereqs.sh`
  8, `bootstrap-ai-lab.sh` 7, `ai-principal-runtime.sh` 3, `discover-ai-models.sh` 2,
  `collect-review-context.sh` 2, `ai-runtime-adapter.sh` 2, `verify.sh` 2, plus singletons; `tools/`:
  `ai-home` 2, `ai-rebuild-plan` 1, `ai-auto-init` 1.
- **C7 self-heal guard** prepended to each ENTRYPOINT (`verify.sh`, `review-gate.sh`,
  `hooks/pre-commit`, `hooks/post-commit`, `tools/ai-auto`):
  `: "${AI_AUTO_HOME:=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)}"; case ":$PATH:" in *":$AI_AUTO_HOME/scripts:"*) ;; *) PATH="$AI_AUTO_HOME/scripts:$PATH";; esac`
- Do NOT add `$AI_AUTO_PROJECT`; launcher does not `cd`; keep `pwd`-based `.omx`/git.

## STEP 5 — verify seam, KEEP scope + scrub (R3; C4 → D2,F4)
- `scripts/verify.sh`: KEEP the `AI_AUTO_VERIFY_SCOPE` case (`:7,:78-95`) — do NOT make machinery
  unconditional. Convert the `-f "${repo_root}/scripts/docker-config-guard.sh"` / `session-lock.sh`
  source guards (`:9-23`) to `command -v` bare-name on PATH (never silently skip the lock). Branch
  bodies: `full` → `verify-machinery.sh` + `verify-project.sh`(if present+exec); `product` →
  `verify-project.sh`(if present); `machinery` → `verify-machinery.sh`. Add §4 guard at top.
- CREATE `scripts/verify-project.sh`: migrate ai-lab's `run_product_pytest`/`run_product_smoke`/
  `API_PORT` logic out of `verify.sh:39-48` into it (self-host project verification).

## STEP 6 — doc-budget (R7; C1 → D8, NOT F1-folded)
- `scripts/doc-budget.sh`: remove the `GUIDANCE_BASELINE` branch (`:20`) + all
  `templates/automation-base/*` budget branches (`:33,72-74,171-180,210-213,237-239,255-261,
  335-339`). `:167` `budget_primary_file "AGENTS.md lines" AGENTS.md 150 220` stays measuring the
  PROJECT overlay ONLY — DO NOT add the global base (C1; would push self-host to 338>220). Caps
  unchanged.

## STEP 7 — automation-doctor (R9 → D4/D5; F4 warn)
- `scripts/automation-doctor.sh`: add `--project`(default-in-project)/`--home` modes.
  - `--project`: check ONLY `scripts/verify-project.sh` (**warn LOUDLY if absent** — F4), hook
    shims, `.omx/` gitignored. Replace monolithic `REQUIRED_FILES` (`:525-564`).
  - `--home`: engine inventory; drop `ai-auto-template-status` from the `:67` source-repo gate;
    remove `.ai-auto/template-manifest.json` reads (`:442-455`) and `ai-template-refresh`/
    `ai-auto-template-status` helper-link checks (`:732,:734`).

## STEP 8 — hooks: thin baked-path shims, NO run-parts (R5; C5/C6/C7 → D7,F5,F6,F7)
- CREATE global `hooks/pre-commit` + `hooks/post-commit` = the framework bodies DIRECTLY (relocate
  the worktree-safe commit-test bodies from the deleted `templates/automation-base/hooks/`). NO
  `.d/` dirs, NO dispatcher (C6). Each starts with the §4 guard.
  - `pre-commit`: fail-CLOSED; PRESERVE the existing exit-5/no-runner handling; **update its
    internal fold grep** (was `templates/automation-base/hooks/pre-commit:54`) to `^(scripts/|hooks/)`
    (F7).
  - `post-commit`: advisory — isolate failures, always `exit 0` (F6).
- `ai-auto setup` installs shims into `git rev-parse --git-path hooks` (worktree/common-dir aware):
  `unset GIT_*; AI_AUTO_HOME="<baked readlink -f path>"; PATH="$AI_AUTO_HOME/scripts:$PATH"; exec
  "$AI_AUTO_HOME/hooks/<hook>" "$@"` (C5). Do NOT set `core.hooksPath`. odoo `pre-push` coexists.

## STEP 9 — NEW `tools/ai-auto` launcher (R4; C6 thin)
- Subcommands: `setup`(STEP 10), `gate`→`review-gate.sh`, `verify`→`verify.sh`,
  `doctor`→`automation-doctor.sh --project`. Unknown verb → usage error (NO `packs/<verb>` routing —
  C6). Self-resolve `AI_AUTO_HOME` via the §4 guard.

## STEP 10 — `ai-auto setup` (R4; C2 → D3,F2) — folds ai-auto-init
- **C2 self-host guard FIRST:** abort if `git rev-parse --show-toplevel` == `$AI_AUTO_HOME` OR the
  tree has the engine sentinel (`scripts/review-gate.sh` AND `templates/domain-packs/`). Before any
  hashing.
- Content-aware de-vendor: each tracked managed file sha256 vs pristine (STEP 0): match→`git rm`;
  differ→keep+report. AGENTS.md: pristine→remove+seed thin overlay stub; customized→keep. Ensure
  `.omx/` gitignored. Detect domain (`ai-project-profile`). Install hook shims (STEP 8). Idempotent
  (no marker). Fail-closed on risky dirty tree.
- Retire `tools/ai-auto-init`'s pointer at the deleted `install-automation-template.sh` (`:1`): fold
  into `ai-auto setup` or make a thin alias.

## STEP 11 — version-sentinel RIPPLE + name-ref scrub (C3 → F3)
Marker-FILE consumers (KEPT tools — verified live):
- `scripts/obsidian-autopush.sh:81` — replace `[ ! -f "${HOME_ROOT}/templates/automation-base/AI_AUTO_TEMPLATE_VERSION" ]`
  with `! { [ -f "${HOME_ROOT}/scripts/verify-machinery.sh" ] && [ -d "${HOME_ROOT}/templates/domain-packs" ]; }`.
- `tools/ai-domain-pack:121-122` — drop `version_path`/`template_version`; remove the
  `template_version` field from the written manifest.
- `tools/ai-tmux-worktree:27-28` — replace the two marker tests with
  `[ -d "$top/templates/domain-packs" ] || [ -d "$top/.omx" ]`.
Name-ref scrub (dead fail-open calls): `tools/ai-rebuild-plan:134-137` (drop the
`ai-auto-template-status` preflight); `tools/ai-home` (template-status/refresh help, 1 ea);
`scripts/bootstrap-ai-lab.sh:209-213,223-227,355,357` (source-helper checks + symlinks);
`scripts/review-gate.sh:342,346,385` (residual after STEP 3); README.md (1), AGENTS.md (3),
`docs/*` (GLOBAL_TOOLS.md ~10, NEW_PROJECT_GUIDE.md ~5, CURRENT_STATE.md ~4) — scrub refs; redirect
`domain_packs` drift → `ai-domain-pack status`. `plans/*` historical; leave unless a test breaks.

## STEP 12 — new tests (replace deleted coverage)
- ADD `tests/test_global_mode_contracts.py`: zero-framework-file repo passes
  `automation-doctor.sh --project`; `ai-auto setup` on a byte-pristine vendored file `git rm`s it; a
  customized one is KEPT+reported; **`ai-auto setup` in the engine home ABORTS (C2/F2)**; `verify.sh`
  honors `AI_AUTO_VERIFY_SCOPE` and runs `verify-project.sh` when present (C4); shim resolves the
  engine with `AI_AUTO_HOME`/PATH UNSET (C5/F5).
- Assert `git grep -nE '<retired-apparatus regex>'` empty across `scripts/ tools/ tests/ .github/`,
  AND no surviving ref to `templates/automation-base/AI_AUTO_TEMPLATE_VERSION` (F3).

## STEP 13 — end-to-end DONE proof
- Self-host: `verify.sh` (full) green (F1 regression check: doc-budget self-host PASS). Throwaway
  project: `ai-auto setup` → no framework files committed → `ai-auto gate` runs from global →
  `ai-auto doctor` green. Defense game: 2 dry red rounds.
