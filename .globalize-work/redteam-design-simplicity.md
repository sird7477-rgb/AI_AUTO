# RED TEAM — design simplicity & extensibility audit (feat/global-toolize)

Verdict: **SIMPLER** — the design is directionally correct (deletes more than it adds) but
carries 6 concrete over-additions / under-deletions. Ranked, each with file evidence and a
shorter alternative.

Scope read: `.globalize-work/SPEC.md`, `scripts/` (review-gate.sh, verify-machinery.sh,
install-automation-template.sh, install-global-files.sh, doc-budget.sh, automation-doctor.sh),
`tools/` (ai-auto-init, ai-home, ai-auto-template-status, ai-template-refresh, ai-rebuild-plan),
`templates/automation-base/`, `docs/GLOBAL_TOOLS.md`.

---

## R1 (BIGGEST WIN, UNDER-DELETED) — the whole `templates/automation-base/` engine duplicate is dead weight, and the SPEC never names it for deletion

Evidence:
- `templates/automation-base/scripts/` = a SECOND FULL COPY of the engine: **29 files, 860K**
  (`du -sh templates/automation-base/scripts` → 860K; `ls | wc -l` → 29). Plus
  `templates/automation-base/docs/` (the 22 docs), `AGENTS.md`, `hooks/`, `AI_AUTO_TEMPLATE_VERSION`.
- `scripts/install-automation-template.sh` exists ONLY to `cp` this tree into a project:
  26 `cp .../scripts/*` lines + 22 `cp .../docs/*` lines (counted). That is the per-project-copy
  engine. In global mode the engine runs from `$AI_AUTO_HOME/scripts` directly — the entire
  `templates/automation-base/{scripts,docs}` duplicate and ~600-line installer are unreferenced.

Why it matters: SPEC §RETIRED only lists the *drift/version* apparatus. It does NOT list the
duplicate engine tree or `install-automation-template.sh`, which are by far the largest dead
weight (thousands of lines + 860K). "Shortest code" mandate is violated by leaving them.

SHORTER: delete `templates/automation-base/scripts/` and `templates/automation-base/docs/`
wholesale; reduce `templates/automation-base/` to ONLY the project-owned seeds (`verify.sh`
template, `hooks/`, and a minimal AGENTS overlay seed). Gut `install-automation-template.sh` to
near-zero (or delete; `migrate` does `git rm`, not `cp`). Net: −thousands of lines / −860K. This
single deletion dwarfs every line the design adds.

## R2 (UNDER-DELETED) — the `.ai-auto/` per-project bookkeeping (manifest + guidance baseline) is also copy-model-only and is not retired

Evidence:
- `scripts/doc-budget.sh:20` — `GUIDANCE_BASELINE=.ai-auto/guidance-baseline.sha256`.
- `scripts/automation-doctor.sh:442-455` — reads `.ai-auto/template-manifest.json` for managed-file
  checks.
- `tools/ai-template-refresh` rewrites `.ai-auto/template-manifest.json`.

These exist solely to track per-project COPIES and the per-project guidance copy. With guidance
moving to global `~/.claude/CLAUDE.md` and no copies, both the manifest branch and the guidance-
baseline branch are dead. SPEC §RETIRED misses them.

SHORTER: delete the `.ai-auto/template-manifest.json` consumer in automation-doctor and the
`.ai-auto/guidance-baseline.sha256` branch in doc-budget (the doc-budget guidance gate as a whole
likely retires with global guidance). −~120 lines + removes a hidden state file.

## R3 (NEW STATE, UNJUSTIFIED) — drop `$AI_AUTO_PROJECT` entirely

Evidence: `$AI_AUTO_PROJECT` is referenced NOWHERE in the codebase today (grep finds only the
unrelated `AI_AUTO_PROJECT_REGISTRY_FILE`). Every project-root/`.omx` access already resolves via
`git rev-parse --show-toplevel` or relative `.omx/` against `pwd`:
- `review-gate.sh:111` — `workspace="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"`.
- review-gate `.omx/...` paths are all `pwd`-relative (lines 4, 9, 25, 149, 227…).
- 11 scripts use `git rev-parse`/`git -C`; 24 reference `.omx/`.

Since the launcher runs the engine with `pwd = project` (SPEC §Mechanism), `pwd` already IS the
project. A `$AI_AUTO_PROJECT` override is a new env var — i.e. new long-session failure surface —
with zero current need. YAGNI.

SHORTER: launcher does NOT `cd` and sets no project var; engine keeps `pwd`-based resolution as-is.
−1 env var, −the branch that reads it.

## R4 (TWO COMMANDS → ONE) — `ai-auto init` and `ai-auto migrate` should be one idempotent command

Evidence: SPEC §Mechanism defines `init` (set core.hooksPath, gitignore `.omx/`, detect domain —
writes no files; idempotent) and `migrate` (`git rm` the managed set MINUS verify.sh, then run
init, one commit, fail-closed on dirty/missing verify.sh). `migrate` ≡ `init` + "if vendored
framework files are present, `git rm` them." The de-vendor step is a no-op on an already-clean
project, so it is safe to fold into init.

SHORTER: a single idempotent `ai-auto init` that, when it detects tracked managed-set files,
removes them in the same commit (gated by the same dirty-tree fail-closed check). −1 subcommand,
−1 entry in the extension table (see R6), −duplicate fail-closed logic.

## R5 (LAUNCHER MAY BE UNNEEDED) — scripts self-resolve `$AI_AUTO_HOME`, so a new `ai-auto` binary adds little over symlinks; and the "self-dir-relative" rewrite has a cheaper form

Evidence — the rewrite is NOT small and is entangled with a test harness:
- Real exec call-sites of `./scripts/X` across the engine: **56** (line-leading/guarded execs),
  per file: verify-machinery **73**, review-gate 6, ai-principal-runtime 3, verify.sh 2,
  run-ai-reviews 2, bootstrap 2, ai-runtime-adapter 2, install-ubuntu-prereqs 1.
- `verify-machinery.sh` is a 361K self-test harness (161 mktemp/cd/assert lines); its 73 calls
  run INSIDE temp fixtures that `cd "$tmp"` and even `cp .../check-template-version.sh scripts/`
  (line 1074). So those tests literally simulate the copy model — they don't take a per-file
  `SCRIPT_DIR` edit; the *fixtures* must be repointed at `$AI_AUTO_HOME` (and many retire with the
  drift tests, R-retire below).

The design implies a per-file `AI_AUTO_HOME="$(cd "$(dirname "$(readlink -f "$0")")"…)"` boilerplate
plus editing each call-site. That is 4+ copies of boilerplate and ~13 engine call-site edits.

SHORTER (minimal edit set):
1. `install-global-files.sh` already symlinks every `tools/*` into `~/bin`. Extend it to symlink
   the ~3 ENTRY engine scripts (`review-gate.sh`, a `verify` wrapper, `automation-doctor.sh`) into
   `~/bin` too — they are then on PATH, no launcher binary needed (`ai-auto gate` == `review-gate.sh`).
2. For inter-script calls, prepend `$AI_AUTO_HOME/scripts` to PATH once (in the entry/launcher) and
   mechanically strip the prefix: `s|\./scripts/||` so `./scripts/X.sh` → `X.sh`, resolved via PATH.
   This removes ALL the per-file `SCRIPT_DIR` boilerplate (1 PATH line vs 4+ readlink blocks).
3. The ONE seam stays explicit: review-gate calls verify as `"$PROJECT/scripts/verify.sh"`
   (project-owned), unaffected by PATH.

If a dispatcher is still wanted for UX, keep it ~30 lines — but it is a convenience, not load-
bearing, since scripts self-resolve. Net: avoids a new binary + ~3 boilerplate blocks.

## R6 (EXTENSIBILITY CHOKEPOINT) — "new pack = launcher subcommand + hook entry" is NOT extensible; it forces a core edit per pack

Evidence: SPEC §Extensibility says each QC/design pack adds "(optional) a launcher subcommand +
global hook entry," yet also claims "domain packs are already pluggable." Those contradict: if a
pack must edit the launcher's subcommand table and the hook body, every pack touches core — a
chokepoint, the opposite of the existing domain-pack model, which is **directory-discovered**
(`ai-domain-pack`, `.omx/domain-packs/`, sidecar manifests — GLOBAL_TOOLS.md §ai-domain-pack).

Current hook reality is already dir-capable: `install-automation-template.sh:334-336` sets
`core.hooksPath=.githooks`; hooks live in `templates/automation-base/hooks/`. Nothing forces a
monolithic hook.

SHORTER (register-by-dropping-a-file, zero core edits):
- Hooks: global `hooks/pre-commit` iterates `"$AI_AUTO_HOME/hooks/pre-commit.d/"*` (run-parts
  style). A pack registers by dropping one file there.
- Launcher: dispatch unknown subcommands to `"$AI_AUTO_HOME/packs/<name>/cmd"` (or just PATH).
  A pack registers a verb by shipping an executable; no table edit.
This makes the seam compose like the existing domain-pack discovery instead of a hand-edited table.

---

## RETIREMENT ripple — correct to delete, but the SPEC under-counts the call-sites that must change

The retired apparatus (`ai-auto-template-status`, `ai-template-refresh`, `check-template-version.sh`,
staleness gate, off-manifest) has wide inbound references that must ALL be edited/removed, else
fail-open dead calls remain:
- `ai-auto-template-status` callers: review-gate (staleness gate, lines 283/295/340/383-390/579),
  bootstrap-ai-lab.sh, install-automation-template.sh, install-global-files.sh (lines 793-818
  codex-drift notice + 1003/1110 symlink), `tools/ai-home` (help text), **`tools/ai-rebuild-plan:134-137`**
  (rebuild preflight — breaks if status tool deleted), plus ~6 docs.
- `ai-template-refresh` callers: automation-doctor, bootstrap, install-global-files,
  ai-auto-template-status, review-gate, verify-machinery.
- `check-template-version.sh`: 11 references, all inside verify-machinery self-tests (retire with it).

Conflict to FLAG (do NOT over-delete): `ai-auto-template-status` ALSO reports `domain_packs` drift
(GLOBAL_TOOLS.md:30), and **domain packs STAY** (they are the extensibility model). Deleting the
tool wholesale silently drops domain-pack drift reporting. Fix cheaply by redirecting that to the
already-existing `ai-domain-pack status` (GLOBAL_TOOLS.md:38) and then delete
`ai-auto-template-status` entirely. Likewise `ai-rebuild-plan` must drop its template-status call,
not inherit a dead one.

## Hidden state / moving-part count (axis 5)

New/affected moving parts and disposition:
- `$AI_AUTO_HOME` env export — KEEP, but partly redundant: every script can self-resolve it from
  `readlink -f "$0"` (SPEC says so), so the profile export is only needed by the launcher+hooks.
- `$AI_AUTO_PROJECT` — DROP (R3).
- `.ai-auto/` manifest + guidance baseline files — DELETE (R2).
- `.ai-auto` *marker* file — NOT NEEDED: SPEC never actually specifies one; init idempotency keys
  off `git config core.hooksPath`. If blue team adds a marker, reject it.
- `core.hooksPath` — REUSE existing mechanism (install-automation-template.sh:334), not new.

Net moving-parts delta after the above: roughly **+1 kept (`$AI_AUTO_HOME`)**, with `$AI_AUTO_PROJECT`,
the `.ai-auto/` state, and any marker eliminated.

---

## Net-lines assessment

Direction is right (strongly net-negative). But the design as written:
- UNDER-deletes: `templates/automation-base/{scripts,docs}` (29 files/860K) + `install-automation-template.sh`
  (~600 lines) + `.ai-auto/` manifest/baseline machinery (R1, R2) — thousands of lines left on the floor.
- OVER-adds: `$AI_AUTO_PROJECT` (R3), a second subcommand (R4), a launcher binary + per-file
  `SCRIPT_DIR` boilerplate (R5), a per-pack core edit (R6).

Apply R1–R6 and the change becomes meaningfully shorter AND more extensible than the current spec.
