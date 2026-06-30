# RED TEAM — design-correctness audit of the global-tool-ization SPEC

Target: `.globalize-work/SPEC.md` (feat/global-toolize). Verdict: **DEFECTS: 8 (highest: CRITICAL)**.
The design's two load-bearing moves — (a) "only `verify.sh` is project-owned / pwd-relative,
everything else resolves from `$AI_AUTO_HOME`" and (b) "RETIRE the whole staleness/version/drift
apparatus" — both have unhandled couplings that break the engine or the kept self-test suite, and
`migrate`'s blunt `git rm` can delete project-authored content. Ranked below.

---

## D1 — CRITICAL — Retiring the staleness/version/drift apparatus breaks the KEPT `verify-machinery.sh` self-test suite (and a unit test)

SPEC §RETIRED deletes `check-template-version`, `ai-template-refresh`, `ai-auto-template-status`
3-way drift, off-manifest detection, and the `check_template_staleness` gate in `review-gate.sh`.
But `scripts/verify-machinery.sh` — which the SPEC explicitly KEEPS (source-repo-only harness) — is
the test harness that asserts on exactly those surfaces:

- `scripts/verify-machinery.sh:1074-1140` — full bump-on-change gate test of `check-template-version.sh`
  (base/no-bump/bumped/pack/inconsistent cases).
- `scripts/verify-machinery.sh:4363-4436` — "review-gate downstream template-staleness gate" test:
  asserts `block` → `exit 6` + a `template_staleness` verdict, `warn` surfaces, `off` is silent,
  unreachable home fails open. All of this dies when `check_template_staleness` is removed from
  `review-gate.sh:339-392`.
- `scripts/verify-machinery.sh:897, 4070, 6068-7666` — dozens of `ai-auto-template-status` drift /
  ownership / record-feedback / promotion tests.
- `tests/test_template_global_contracts.py:107` reads `templates/automation-base/scripts/verify-machinery.sh`
  and asserts it references `AI_AUTO_TEMPLATE_VERSION`; lines 69/100/102 assert template-status emits
  `AI_AUTO_TEMPLATE_VERSION` rows.

Failure scenario: the gate runs ON ai-lab itself (the self-host case, axis 2). `verify.sh`
(`AI_AUTO_VERIFY_SCOPE=full`) → `./scripts/verify-machinery.sh:80` → the staleness/bump tests call
now-deleted scripts → non-zero → the whole suite is RED. SPEC §DONE requires "all engine self-tests …
green," so the design as written can never reach DONE. The SPEC's "delete the apparatus" bullet does
not acknowledge that the apparatus's own regression tests live in the file it keeps.

Fix: treat `verify-machinery.sh`'s template-version/staleness/drift test blocks AND
`tests/test_template_global_contracts.py`'s template-status assertions as part of the retired surface —
delete/rewrite them in the SAME change that removes the machinery. Audit `git grep -n
'check-template-version\|template-staleness\|ai-auto-template-status\|AI_AUTO_TEMPLATE_VERSION'` and
zero it out atomically.

## D2 — HIGH — `verify.sh` is declared the only project-owned engine file, but it is a CLIENT of framework siblings the design deletes from the project

SPEC §Boundary: "PROJECT-OWNED: `scripts/verify.sh` ONLY … all other `scripts/*` … in `$AI_AUTO_HOME`."
But `verify.sh` has hard pwd-relative dependencies on framework siblings:

- `scripts/verify.sh:9-12` sources `${repo_root}/scripts/docker-config-guard.sh` (`repo_root=$(pwd)`).
- `scripts/verify.sh:17-20` sources `${repo_root}/scripts/session-lock.sh`.
- `scripts/verify.sh:80,88` runs `./scripts/verify-machinery.sh`.
- The INSTALLED placeholder `templates/automation-base/scripts/verify.example.sh:28-41` calls
  `./scripts/test-review-summary.sh`, `./scripts/doc-budget.sh`, `./scripts/automation-doctor.sh`, and
  install step 11 (`install-automation-template.sh:397`) tells every project to keep calling
  `doc-budget.sh` / `guidance-duplicate-report.sh` from verify.sh.

Failure scenario: in globalized mode `pwd`=project (zero framework files). The project's
`scripts/verify.sh` runs `./scripts/verify-machinery.sh` → file not found → `set -e` crash (or, for
the `-f`-guarded sources of session-lock/docker-config-guard, a SILENT skip that drops the
concurrency lock and docker-config guard — the very session-lock re-entrancy review-gate relies on).
The boundary split has no defined path for a PROJECT-owned `verify.sh` to reach `$AI_AUTO_HOME/scripts`.

Fix: the design must specify that the launcher exports `$AI_AUTO_HOME` into verify.sh's environment and
the template verify.sh references helpers as `"$AI_AUTO_HOME/scripts/doc-budget.sh"` etc. (or ships a
tiny `ai-auto helper <name>` shim). Update `verify.example.sh` and AGENTS.md step-11 guidance in lockstep.

## D3 — HIGH — `migrate`'s `git rm` (managed set MINUS verify.sh) deletes PROJECT-AUTHORED content

SPEC §migrate: "`git rm` the vendored framework files (managed set MINUS verify.sh) + AGENTS.md/docs +
version file … Fail-closed: refuse if verify.sh is missing or the tree is dirty." This assumes verify.sh
is the ONLY file projects customize. It is not:

- Install steps explicitly tell projects to CUSTOMIZE `AGENTS.md` and `docs/WORKFLOW.md`
  (`install-automation-template.sh:396, 416`).
- `ai-auto-template-status` ownership classes are `template-owned | hybrid | project-owned`
  (`tests/test_template_global_contracts.py` ownership assertion) — hybrid/project-owned managed files
  are MEANT to diverge per project. Drift states include `locally_edited` / `conflict`
  (`review-gate.sh:364-366`).

Failure scenario: a real project that wrote its own AGENTS.md guidance overlay INTO the managed
`AGENTS.md`, or customized `docs/WORKFLOW.md`, runs `ai-auto migrate`. The blunt `git rm AGENTS.md
docs/…` deletes that authored content in "one commit." The dirty-tree guard doesn't catch it — the
edits are committed, not dirty. This is silent data loss of project-owned content. Bitter irony: the
3-way drift detector that could classify "this managed file is locally_edited → preserve" is the very
thing SPEC §RETIRED deletes.

Fix: migrate must run an ownership/drift check (keep a minimal classifier even if the gate is retired)
and refuse-or-preserve any managed file whose content differs from the template baseline, not just
verify.sh. The SPEC's "AGENTS.md addendum" overlay model needs migrate to SPLIT the file, not `rm` it.

## D4 — HIGH — The kept CI workflow `template-version-gate.yml` hard-fails once `check-template-version.sh` is retired

`.github/workflows/template-version-gate.yml` runs, on every push/PR, `./scripts/check-template-version.sh`
and `shellcheck … templates/automation-base/scripts/*.sh`. SPEC §RETIRED deletes
`check-template-version.sh` but never mentions this workflow (it is recent — commit 56812b7).

Failure scenario: after retirement, every push to the ai-lab source repo fails the `template-version-gate`
job with "No such file or directory: ./scripts/check-template-version.sh". A server-side gate that
"cannot be skipped with --no-verify" (its own header) now blocks all merges.

Fix: delete or rewrite `template-version-gate.yml` in the same change as the script removal.

## D5 — HIGH — `automation-doctor.sh`, relocated to `ai-auto doctor`, reports a correctly-globalized project as broken

SPEC §migrate DONE wants "no framework files committed." But `automation-doctor.sh` (kept as the global
doctor) hard-fails on exactly that state: `REQUIRED_FILES` (`scripts/automation-doctor.sh:533-564`)
lists `AGENTS.md` and every `scripts/*.sh|*.py` managed file plus `scripts/verify.sh`, and
`check_required_file:181` emits `say_fail "required file missing"` for each absent one. A globalized
project has none of them except verify.sh.

Failure scenario: `ai-auto doctor` on a freshly-migrated project prints ~30 "required file missing"
failures and a non-zero exit — the inverse of the intended success signal — and `verify.example.sh:39`
still invokes it inside verify.sh, so `ai-auto verify` inherits the noise. Line 67 also gates the whole
"source repo" branch on `${ROOT}/tools/*` existing, so `ROOT` must be `$AI_AUTO_HOME`, not `$(pwd)`.

Fix: doctor needs an explicit project-mode that checks ONLY `verify.sh` + hooksPath + `.omx` gitignore,
and a separate home-mode for the engine inventory. Relocation alone is insufficient; the required-file
contract must be rewritten.

## D6 — MEDIUM — Moving base `AGENTS.md` fully to global `~/.claude/CLAUDE.md` silently shrinks review coverage, because the ENGINE (not just Claude Code) reads `AGENTS.md` at runtime

SPEC §Guidance claims "Claude Code already layers global + project," implying project AGENTS.md is
redundant. That is true for the Claude RUNTIME but false for the engine's own reads:

- `collect-review-context.sh:187` injects `AGENTS.md` into the reviewer context file; `:209/:295/:439`
  drive scope-classification and persona-lens selection off the `AGENTS.md` path.
- `doc-budget.sh:167` budgets `AGENTS.md`; `guidance-duplicate-report.sh` is run as
  `guidance-duplicate-report.sh AGENTS.md docs` (`verify-machinery.sh:1156`).

None of these read `~/.claude/CLAUDE.md`. Failure scenario: after migrate removes project `AGENTS.md`,
the AI review panel's context no longer contains the operating guidance the reviewers are told to
enforce (`collect_review_reference_files` just skips the missing file — fail-soft), and the
budget/duplicate checks see only the thin overlay. Reviews still run but on degraded guidance — a
coverage regression that no test catches.

Fix: either keep a project-side AGENTS.md (overlay is fine, but it must be the file the engine reads),
or repoint `collect-review-context.sh`/`doc-budget.sh` at the global guidance path. Decide explicitly;
do not rely on Claude Code layering for engine reads.

## D7 — MEDIUM — Global `core.hooksPath` collides with the existing per-project Odoo hooksPath consumer

SPEC §Hooks: `ai-auto init` sets `git config core.hooksPath "$AI_AUTO_HOME/hooks"`. But
`install-automation-template.sh:333-339` already sets `core.hooksPath=.githooks` for Odoo projects
(custom-addons present) and explicitly PRESERVES a pre-existing hooksPath. `core.hooksPath` is a single
value — it cannot point at both the global gate dir and the project's `.githooks` Odoo pre-push gate.

Failure scenarios: (a) `ai-auto init` on an Odoo project overwrites `.githooks` → the Odoo
manifest/validation pre-push gate silently stops running; (b) init respects the existing `.githooks` →
the global gate never runs. Either way one gate is silently disabled. The SPEC also doesn't say how the
global hook re-applies the existing worktree-safe `GIT_*`-unset logic (`install-automation-template.sh:155-181`)
for LINKED worktrees, where `git rev-parse --git-path hooks` resolves to the shared common dir.

Fix: the global hook entrypoint must DISPATCH to a project `.githooks/<hook>` when present (chain, not
replace), and init must detect+merge an existing hooksPath rather than clobber it.

## D8 — MEDIUM — Retiring the install/refresh path orphans `doc-budget.sh`'s inherited-baseline, changing budget behavior

`doc-budget.sh:20` reads `.ai-auto/guidance-baseline.sha256` to EXCLUDE inherited-unchanged guidance
from the absolute budget (the documented purpose, `:14-19`). That file (and `.ai-auto/template-manifest.json`)
is written only by `refresh-guidance-baseline.sh` at install time
(`install-automation-template.sh:235-240, 359-378`). SPEC retires the per-project install/copy flow, so
neither `init` nor `migrate` produces a baseline.

Failure scenario: with no baseline, `doc-budget.sh` falls to "full budget" (`:19`) and measures ALL
guidance — but in globalized mode the project no longer holds the inherited docs anyway, so the
AGENTS.md 150/220 caps (`:167`) now measure only the project overlay. The net effect is undefined-by-design
budget semantics, and `verify-machinery.sh:1026-1041` baseline tests assume the install-time baseline
exists. Couples back into D1 (those tests) and D6 (which file is canonical).

Fix: decide where the inherited baseline lives in global mode (compute it from `$AI_AUTO_HOME` at
runtime), and update doc-budget + its tests together.

---

## Axis notes / what is NOT broken

- **Self-host collapse (axis 2): OK.** In the source repo `$AI_AUTO_HOME == $(pwd) == project`, so
  `./scripts/verify.sh` and `$AI_AUTO_HOME/scripts/...` are the same files; `scripts/verify-machinery.sh`
  exists, so the machinery fold (`review-gate.sh:604`) still fires. Self-host does not break from the
  boundary split itself — but it is precisely the case that EXPOSES D1 and D4 (the harness + the CI
  workflow live in the source repo).
- **Framework scripts reading pwd-relative project data (axis 1): mostly fine.** `collect-review-context.sh`,
  `run-ai-reviews.sh`, `summarize`, `session-lock.sh` resolve framework SIBLINGS via `$BASH_SOURCE`/`dirname`
  (e.g. `run-ai-reviews.sh:72`) yet read/write `.omx/`, git, `AGENTS.md` pwd-relative — correct as long as
  the launcher sets `pwd`=project. The real exceptions are verify.sh (D2) and AGENTS.md as engine-read
  guidance (D6).
- The `review-gate.sh` `./scripts/<sibling>` calls (`:695, 737, 750, 171, 176, 183`) DO require the
  globalization rewrite the SPEC mandates (resolve from `$AI_AUTO_HOME`); that is acknowledged work, not a
  defect — flagged only as a reminder that it must be exhaustive (any missed `./scripts/` call breaks a
  zero-vendored-file project).
