# Plan — Template distribution / version-management redesign (#2) 2026-06-20

Source: jw_dev silent-drift incident (a downstream project ran an old, since-refactored
`test-knowledge-notes.sh` + older `verify-machinery` and never re-synced; its gate failed
on infra the home no longer has). Two-agent AI council (current-state cartographer +
proposed-model critic) — all claims ground-truth verified against current code at
origin/main `b6f8df5`.

## Headline finding (reframes the brief)

**The user's 5-part model is largely ALREADY BUILT.** The one genuinely missing,
jw_dev-killing piece is a **blocking downstream version-staleness gate + a one-command
re-sync**. Everything else is either already shipped (domain packs), already true (single
source of truth), or needs only convention (upstream queue). Do not rebuild what exists.

## Current state (verified) — what exists vs what's missing

Already present and correct (REUSE):
- **Single source of truth** — global `~/bin` tools all resolve to the one home checkout.
- **Pinned install snapshot** — `install-automation-template.sh` `cp`s a fixed manifest +
  stamps `AI_AUTO_TEMPLATE_VERSION`; aiinit refuses to re-run (not an update path).
- **Drift DETECTION (report-only)** — `ai-auto-template-status`: per-file sha256 + version
  compare; 3-tier ownership (`template-owned|update`, `hybrid|review-merge` = AGENTS.md +
  WORKFLOW.md, `project-owned|inspect-only` = verify.sh).
- **Publisher gate** — `check-template-version.sh` (consistency + bump-on-change forcing a
  patch note); SOURCE-repo only (self-disables in installed projects).
- **Domain packs = the target model, fully built** — `ai-domain-pack`: pinned
  `.omx/domain-packs/` + per-pack manifest (`template_version` + `source_root_hash` +
  per-file sha map) + conflict-aware state machine + `refresh --apply` that mutates ONLY
  inside `.omx/domain-packs/`, fails closed on local edits / experimental source.
- **Upstream transport** — `record-feedback` → project-local `.omx/feedback/queue.jsonl`;
  `feedback-collect` aggregates every registered project's queue to the home. Triage loop
  is already exercised (regular-promotion plan). Only a naming convention is missing.
- **Fleet substrate** — `~/.local/state/ai-auto/projects.tsv` + `ai-register` +
  `workspace-scan` (needs a version column).

Missing (the GAP a redesign must add):
1. **No downstream version-staleness GATE.** A project's own `review-gate.sh` / `verify.sh`
   / `automation-doctor.sh` never assert "installed == published"; stale projects pass green.
2. **No one-command re-sync.** Install is frozen; aiinit refuses re-run; only manual copy /
   hand-patch exists. (Domain packs DO have `refresh --apply` — base files don't.)
3. **`verify-machinery.sh` and `tools/*` are OFF the managed manifest.** The very infra that
   runs in the gate is neither installed nor tracked nor drift-checked. jw_dev's stale
   machinery was a hand-copied, OFF-MANIFEST file — a manifest-version gate alone would not
   have caught it.
4. **No base-file install-time manifest** (domain packs have one; base files don't), so the
   status tool cannot do a 3-way diff ("you edited it" vs "home moved on").
5. **No no-local-edit enforcement** (edits to template-owned files are reported, never
   blocked) and **registry stores no version** (no fleet staleness view).

## Design — phased

**Dependency chain (corrected by plan review): manifest → gate/refresh → off-manifest.**
The base-file install manifest is the load-bearing prerequisite for everything else: a
conflict-aware re-sync and a gate that blocks only on GENUINE upstream drift (not on a
project's legitimate edit) are structurally impossible on today's 2-way
`ai-auto-template-status` diff (source-vs-installed only — it cannot tell "project edited
it" from "home moved on"; both collapse to `different`). The domain-pack contract this plan
reuses (`ai-domain-pack`) derives its only safe-to-overwrite state (`outdated_clean`) from a
3-way diff against its per-pack manifest; without an equivalent base manifest, base refresh
returns `unmanaged` and refuses everything (or blind-overwrites and destroys local edits).
So the manifest comes FIRST.

### Phase 0 — base-file install manifest + machine-readable status (the prerequisite)
- At install, write `.ai-auto/template-manifest.json`: `template_version` + per-file sha of
  every managed file (lift the domain-pack `.omx/domain-packs/.manifest/<pack>.json` model;
  today only AGENTS.md + docs/*.md have a partial baseline via
  `.ai-auto/guidance-baseline.sha256` — scripts, the jw_dev surface, have none). This enables
  the 3-way diff (source / installed / install-baseline) that distinguishes a project edit
  from an upstream change, fixing the `customized_or_outdated` two-axes conflation.
- Add `--json` to `ai-auto-template-status` (mirror `ai-domain-pack --json`): emit per-file
  `{path, state, ownership, patch_policy}` + installed/current version, so the gate consumes
  structured state, not scraped tab-table text.
- Bring the gate-relevant but currently UNMANAGED infra onto the manifest: `verify-machinery.sh`
  is not installed and not in `managed_files` today — the literal jw_dev surface. Decide its
  managed status here (install it as template-owned, or explicitly track-and-warn) so later
  phases can see it.

### Phase 1 — one-command re-sync + downstream staleness GATE (the jw_dev fix)
- **Re-sync first (ship before flipping the gate to blocking):** `ai-template-refresh`,
  cloning the `ai-domain-pack refresh --apply` CONTRACT now that the base manifest (Phase 0)
  exists: 3-way classify, mechanical overwrite ONLY for `template-owned` files that are
  `outdated_clean` (home moved on, no local edit); `hybrid` (AGENTS.md/WORKFLOW.md) →
  review-merge prompt (never blind overwrite — AGENTS.md is hand-merged at install and is
  `different` on essentially every real project); `project-owned` (verify.sh) → untouched.
  `main`-channel gated, dry-run default, re-stamps the version + runs
  `refresh-guidance-baseline.sh`.
- **Then the gate — hosted in `review-gate.sh` (NOT verify.sh).** `verify.sh` is installed
  from `verify.example.sh` and is `project-owned` (projects rewrite it; a template change to
  it never reaches installed projects). `review-gate.sh` is template-owned + installed and
  has a clean seam: insert the check just before its `echo "[gate] running verification..."`
  / `./scripts/verify.sh` call (~review-gate.sh:435-445). The check shells out to the global
  `ai-auto-template-status --json` and:
  - **blocks** only on `ownership==template-owned` `different`/`missing`, or a
    template-owned-affecting `installed_version != current_version`;
  - **warns only** on `hybrid` / `project-owned` drift (AGENTS.md hybrid is `different` on
    every real project — must NOT red-gate);
  - **fails OPEN with a loud warning** when the home is unreachable, with PRECISE detection:
    `ai-auto-template-status` is a symlink into the home; an unmounted home leaves a dangling
    symlink (exit 127/126), which must be treated as "unreachable → warn + exit 0", NOT a
    block. Detect via `command -v` + a probe run + readlink-target existence; reserve a
    blocking nonzero only for a CLEAN run that reports template-owned drift.
- Migration ordering is mandatory: ship `ai-template-refresh` first, let projects converge,
  THEN flip the gate to blocking — otherwise every legacy project (jw_dev) red-gates at once.

### Phase 2 — off-manifest-copy detection (the LITERAL jw_dev trigger)
jw_dev broke on a project-PRIVATE, OFF-MANIFEST script copy (`verify-machinery.sh` /
`test-knowledge-notes.sh`) that no manifest tracked — so the Phase-1 version gate, scoped to
managed files, does NOT catch it. Add a WARN for project-local files whose names shadow home
template/tool names but are absent from the manifest. CRITICAL: the shadow-name list is NOT
knowable downstream (a derived project has no `templates/`/`tools/`; `automation-doctor`'s
tool enumeration is gated on `IN_AI_LAB`). The list MUST be sourced from the home via the
global tool (`ai-auto-template-status` exposing managed-file + tools basenames) — which is
why Phase 0 must also bring `tools/*` + `verify-machinery.sh` onto a tracked manifest.

### Phase 3 (defer) — formalized upstream proposal convention
Reserve a `record-feedback` key prefix (e.g. `template-proposal:*`) + a `feedback-collect`
filter so project→home template-improvement proposals are first-class and triageable. Low
urgency: transport (`record-feedback` + `feedback-collect`) already works; this is convention
+ a filter.

### Honest scope of the jw_dev fix
Phase 1 kills the version-STALENESS class (silently behind). The literal jw_dev instance (an
off-manifest stale script) needs Phase 2, which needs Phase 0's manifest. So Phase 1 is NOT
a standalone jw_dev fix — the full chain (Phase 0 → 1 → 2) is.

## Hard questions — resolved (panel)

- **Version discovery:** no network — the home is a local-FS path the global tools already
  read; `ai-auto-template-status` reads both versions in one process. The gate consumes its
  signal. Home unreachable → fail open + warn.
- **No-edit vs legitimate override:** enforce "no drift" on `template-owned` ONLY; `hybrid` =
  warn/review-merge; `project-owned` = untouched. The ownership tier IS the exception
  mechanism (already in the manifest).
- **Proposal transport:** same machine / shared FS; reuse `record-feedback` +
  `feedback-collect`; add only a naming convention. Do not build new transport.
- **Re-snapshot trigger:** the downstream gate makes drift a hard stop; re-sync itself stays
  review-mediated (no safe blind overwrite of hybrid). Open sub-decision (user): hard-block
  vs warn-with-grace-window. Recommend hard-block on major template-OWNED script drift,
  warn on docs.

## Risks / mitigations

1. Flip-to-blocking without shipped remediation red-gates every legacy project → ship
   `ai-template-refresh` FIRST, gate SECOND.
2. Ignoring ownership tiers turns every legit AGENTS.md/verify.sh edit into a false drift
   failure → gate keys on `template-owned` only from day one.
3. Fail-closed on unreachable home blocks offline/cross-machine work → fail open + warn.
4. Manifest-scoped gate misses off-manifest legacy copies (the literal jw_dev trigger) →
   pair the version gate with Phase 2 off-manifest detection.
5. Auto-apply overwriting hybrid files destroys project intent → re-sync mechanical only for
   `template-owned`; hybrid/project-owned review-mediated (the domain-pack refresh boundary).

## Verification

- Each phase = its own RALPH loop (plan→implement→`REVIEW_DECISION_GATE=1` unanimous→commit),
  scripts/X == templates mirror byte parity, template version bump + PATCH_NOTES where a
  template file changes.
- verify-machinery (or pytest) assertions per phase: Phase 0 — install writes the per-file
  manifest, `--json` emits structured per-file ownership/state, the 3-way diff distinguishes
  "edited" from "behind"; Phase 1 — a stale fixture project red-gates (template-owned only),
  `ai-template-refresh` clears it, hybrid/project-owned edits do NOT block, unreachable-home
  fails open (dangling-symlink path); Phase 2 — an off-manifest shadow script warns.
- Dogfood on jw_dev: after Phase 1, jw_dev red-gates on template-owned drift →
  `ai-template-refresh` → green; Phase 2 then flags its off-manifest stale machinery copy.

## Out of scope / deferred

- Cross-machine / networked sync (all projects are local-FS — rejected).
- Rebuilding domain packs (already the model — reused, not redone).
- Registry version column (Phase 1 adjunct; nice-to-have for a fleet staleness view).
- Auto-applying re-sync without review (rejected for hybrid/project-owned).

## Validation trail

- **AI council (validity):** 2-agent panel — current-state cartographer (mapped every
  mechanism + a GAP LIST) + proposed-model critic (per-piece verdict: most already built;
  the missing piece = blocking gate + re-sync; hard questions resolved; phased architecture).
- **AI plan review:** verdict **GO-WITH-CHANGES (rework the phasing)**. Most important
  correction APPLIED: **inverted Phase 0/1** — the base-file install manifest is the
  load-bearing prerequisite (no safe conflict-aware re-sync or genuine-drift gate exists on
  the current 2-way diff), so it is now Phase 0; the gate+refresh move to Phase 1. Other
  applied changes: gate hosted in `review-gate.sh` (not project-owned `verify.sh`), inserted
  before its `verify.sh` call; `--json` added to `ai-auto-template-status` as a gate
  prerequisite (block on `ownership==template-owned` only); precise fail-open detection
  (dangling-symlink / exit-127); Phase 2 shadow-name list sourced from the home + `tools/*` /
  `verify-machinery.sh` brought onto a tracked manifest; corrected dependency chain
  (manifest → gate/refresh → off-manifest) and dropped the "Phase 0 = standalone jw_dev fix"
  framing.
- **Status:** plan ready to implement as phased RALPH loops on user go (start Phase 0:
  base-file manifest + `--json`). Highest-risk item: not shipping `ai-template-refresh`
  before flipping the gate to blocking (would red-gate all legacy projects at once).
