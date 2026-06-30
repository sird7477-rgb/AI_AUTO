# Obsidian Knowledge Operations

Obsidian is a curated knowledge store for AI_AUTO work. It is not an approval,
verification, review, commit, queue, or runtime control system.

## Authority

AI_AUTO remains authoritative for user approval, verification results,
review-gate verdicts, feedback queue resolution, template patch eligibility,
commits, pushes, and project instructions. A vault note changes no project
behavior until a normal repo edit passes verification and review.

## Capture Rules

Use `scripts/knowledge-notes.py` to create sanitized Markdown notes. `record`
is dry-run by default and writes only with `--write`; pass an explicit
`--output-dir` for the Obsidian vault. Use `--allow-local-draft` only for
temporary `.omx/knowledge` drafts.
The validator supports the flat scalar frontmatter written by this helper; do
not hand-edit notes into nested YAML, lists, or multiline frontmatter values.

Supported types:

- `incident`: blocked or repeated debugging, permission, sandbox, reviewer,
  Docker, WSL, tmux, onboarding, verify, review, commit, push, or setup cases
- `finding`: technical evidence that supports a project decision
- `lesson`: project learning recorded with observable signals, not success
  claims
- `technical-spec`: user-requested, user-supplied, or workflow-required
  reference material
- `promotion-candidate`: repeated sanitized pattern proposed for AI_AUTO docs,
  doctor checks, review gates, `ai-auto setup`, or domain packs

Sync classes:

- `local_repo_index`: tracked schema, guide, or compact index material in an
  AI_AUTO-controlled repository
- `local_private`: local-only drafts or private vault notes; push requires
  `--allow-local-private`
- `external_private_vault`: curated private vault content in an explicit vault
  path, including an external SSD vault
- `shareable_summary`: sanitized content approved for shared storage

Do not store raw prompts, private logs, screenshots with sensitive data,
credentials, tokens, private keys, cookies, credential URLs, absolute private
paths, or raw `.omx` runtime dumps.
Sanitized references to `.omx/feedback/queue.jsonl` are allowed as
`source_artifact`; copying the raw queue body into a note is not.

## Large Reference Baselines

For large technical references such as ERP schema exports, SDK inventories, or
version baselines, split storage into three tiers before writing to a vault:

- `index`: a human-readable Markdown note with frontmatter, source, counts,
  usage order, limitations, and verification evidence
- `slim`: compact JSON or CSV indexes used for routine lookup and coding work
- `full`: source extracts kept as reference evidence and opened only when the
  slim index is insufficient

Run micro-level consistency checks before vault storage: expected files, JSON or
CSV parseability, summary counts, full-to-slim count parity, required lookup
keys, reference integrity, duplicate keys, frontmatter rules, and secret-value
patterns. Treat keyword hits on schema field names as advisory only; fail only
on copied credential values or secret-like payloads.

Do not copy the same full baseline into every project. Store one curated
baseline in the vault and let project repositories reference its baseline ID,
source artifact, and vault path.

Official product documentation baselines may use the same pattern. Keep the
official content and URL set in the project or vault that owns the domain, while
AI_AUTO keeps only the reusable operating rule and validator shape:

- read the project-authored guide or decision note first
- read the official `slim` topic as a navigation-only or heading-only lookup aid
- open the matching official `full`/`raw` topic only when exact semantics are
  needed, and only one topic at a time
- fall back to the version-pinned source URL when the local extract is
  insufficient or freshness matters

End-user manuals can stay `index` tier only when they are rarely used and cheap
to fetch, but a domain baseline should mirror them into `raw` plus `slim` tiers
when operational workflows, UI steps, or repeated business-flow questions are
part of normal work. Keep the index as the routing table, read slim for
navigation, and open one raw manual page at a time for exact user-facing
workflow detail.

For the local Odoo 19 baseline, the curated vault reference is
`Odoo19_Docs_KB` with baseline ID `odoo-19-docs-2026-06`. Validate it with:

```bash
./scripts/validate-odoo-docs-kb.py <vault-path>/AI_AUTO/Odoo19_Docs_KB
```

To include that optional baseline in `./scripts/verify.sh`, set
`AI_AUTO_ODOO_DOCS_KB_PATH` to the local baseline directory. The template must
not hardcode a user-specific vault path; absent this variable, verification
skips the optional official-docs baseline check.

For Odoo work, consult the local Obsidian baseline when
`AI_AUTO_ODOO_DOCS_KB_PATH` or an explicit vault path is available before giving
implementation-ready framework or user-flow guidance. Use the project-authored
guide first, then the matching official slim page, then one matching raw page,
then the pinned source URL if freshness or exact wording matters. If the local
baseline is unavailable, say so and fall back to official documentation lookup
instead of guessing from memory.

That validator checks the raw/slim/index/runbook structure and metadata only,
including that every `slim` file warns it is not authoritative implementation
text and every indexed user-manual page has matching `user-manual/raw` and
`user-manual/slim` files. It does not make Obsidian authoritative for Odoo
behavior, project schema facts, verification, review, queue resolution, or
upstream documentation freshness.

## Daily Workflow

1. Start from the project index or vault Project Home view.
2. During debugging, record an `incident` only when work was blocked, repeated,
   or likely reusable.
3. After review, record only reusable findings, lessons, prevention decisions,
   or promotion candidates; never import raw review output.
4. During research, record `finding` for decision evidence and `technical-spec`
   only when the user or workflow requires storage.
5. End the day by triaging drafts, merging duplicate `repeat_key` notes, and
   updating `status`, `next_action`, and `updated`.
6. During onboarding, show at most five advisory notes matched by
   `project_type`, `stack`, `domain_pack`, `surface`, or `repeat_key`.

Recommended body sections: Summary, When to care, Evidence pointer, Safe
resolution or decision, Verification/review evidence, Next action, Do not do.

Generated vault layout:

```text
AI_AUTO/
  AI_AUTO_INDEX.md
  Projects/<project--hash>/<note>.md
  Projects/<project--hash>.md
  Surfaces/<surface>.md
  RepeatKeys/<repeat-key>.md
  Promotion/candidates.md
  Views/inbox.md
  Views/open-incidents.md
  Views/recently-updated.md
```

`Projects/<project--hash>` preserves the same collision guard as the old
`Inbox/<project--hash>` layout. The hub pages and each note's `## Links`
section are generated from note frontmatter and can be rebuilt.

Do not treat `AI_AUTO_INDEX.md` as a vault-wide table of contents. It covers the
curated AI_AUTO note lane only: source notes under `Projects/` and `Inbox`, plus
generated hubs under `Surfaces/`, `RepeatKeys/`, `Promotion/`, and `Views/`.
Top-level domain KB folders and large reference baselines keep their own
folder-local indexes and validators.

Two separate index lanes exist, and automated retrieval covers only one of them:

- **Reference-baseline lane** (`Odoo19_Docs_KB` and similar): a `slim` routing
  table (`00_Index.md`) that the domain-gated `knowledge-retrieve` hook searches
  to inject capped pointers. This is the only lane auto-surfaced during work.
- **Curated-findings lane** (`AI_AUTO_INDEX.md` + `Projects/`/`Surfaces/`/
  `RepeatKeys/`): fully rebuilt from note frontmatter on every push (idempotent —
  re-running `knowledge-notes.py index` over the whole note set keeps it
  consistent, so routing a new draft to a different `project:` never requires
  reindexing existing notes). This lane is **browse-only**; the retrieval hook
  does not read it, so a captured `surface: odoo` finding is not auto-retrieved
  even after push. Extending retrieval to the findings lane is a backlog item.

Recommended views: Project Home, Inbox, Open Incidents, Work Review Findings,
Technical Specs, Repeat Keys, Promotion Candidates, Recently Updated.

## Commands

Record a note:

```bash
./scripts/knowledge-notes.py record \
  --type incident \
  --status resolved \
  --title "Docker daemon unreachable during verify" \
  --summary "Docker was installed but the daemon was not reachable." \
  --project ai-lab \
  --surface docker \
  --severity medium \
  --repeat-key docker:daemon-unreachable \
  --source-artifact .omx/feedback/queue.jsonl \
  --source-extract "sanitized queue summary for docker daemon unreachable" \
  --sync-class external_private_vault \
  --confidence medium \
  --output-dir <vault-path>/AI_AUTO/Projects/<project--hash> \
  --write
```

For local private drafts, add both:

```bash
--output-dir .omx/knowledge/drafts --allow-local-draft
```

For automatic local draft capture, run
`./scripts/capture-knowledge-drafts.py --source all --write`. `review-gate`
captures review-gate drafts by default; set `OMX_AUTO_KNOWLEDGE_DRAFTS=0` to
disable that run.

If the optional Codex startup notice is installed from the AI_AUTO home checkout,
AI_AUTO startup also performs a bounded read-only pending-draft check across the
home checkout plus registered projects. When drafts are waiting, it prints an
`OBSIDIAN OUTPUT CHECK` block with a compact pending list, an inspect command,
and an approval-only push handoff:

```bash
knowledge-collect --project <repo> --push --vault-dir <vault-dir>
```

The startup notice never pushes automatically and never writes to the vault.

To publish on demand, run `./scripts/obsidian-autopush.sh` from the home
checkout. It pushes only shareable drafts (`sync_class: shareable_summary` /
`external_private_vault`) that pass a secret/redaction preflight, reads the vault
path from `obsidian.ai_auto_vault_dir` in `.omx/local-config.json`, fails closed
if a shareable note contains secret-like content, and never pushes
`local_private` drafts (they stay local until promoted).

After an approved push, `knowledge-collect` marks the local draft and vault copy
with `sync_state: pushed_to_obsidian` and an `obsidian_pushed_hash`, so normal
pending checks stop reporting that note until the local draft changes. Use
`knowledge-collect --include-pushed ...` when auditing already mirrored drafts.
The startup notice does not scan mounted project folders. If an individual
project is missing from the pending list, run `ai-register --prune` and then
`ai-register /path/to/repo` from the current project location.
Disable it for one shell command with:

```bash
AI_AUTO_KNOWLEDGE_AUTOPUSH_NOTICE=0 codex
```

Validate and index notes:

```bash
./scripts/knowledge-notes.py validate <vault-path>/AI_AUTO
./scripts/knowledge-notes.py index \
  --notes-dir <vault-path>/AI_AUTO \
  --output <vault-path>/AI_AUTO/AI_AUTO_INDEX.md
```

For reviewed plain-guide folders that are not `knowledge-notes.py` frontmatter
notes, use a scoped validator for that folder before copying it into the vault.
Example:

```bash
./scripts/validate-<guide-folder>.py
rsync -a --delete "knowledge/<guide-folder>/" "<vault-path>/AI_AUTO/<guide-folder>/"
```

The generic `knowledge-notes.py validate` / `index` commands ignore top-level
plain-guide folders because those files do not use the helper's frontmatter
schema. Validate the folder itself with its scoped validator before copying.

Use these lanes when checking whether Obsidian material is properly connected:

- `AI_AUTO curated notes`: `Projects/`, `Inbox/`, generated hubs, and
  `AI_AUTO_INDEX.md`; relationships come from helper frontmatter and generated
  `## Links`
- `domain KB folders`: folder-local indexes such as `00_Index.md` plus a scoped
  validator
- `large reference baselines`: baseline indexes, `slim`/`raw` tiers, runbook
  metadata, and parity validators

The Obsidian graph view can make domain KB pages or reference-baseline pages
look like standalone notes. That is not a defect by itself. Treat missing
folder-local indexes, failed scoped validators, missing generated links in
curated notes, or stale `Inbox` conflicts as defects.

Before cleaning up perceived standalone notes, run the read-only vault audit:

```bash
./scripts/audit-obsidian-vault.py <vault-path>/AI_AUTO
```

Use the report to separate exact duplicate Inbox notes, same-source conflicts,
same-repeat-key conflicts, and distinct evidence that needs manual merge or a
unique Projects filename. The audit command is evidence only; it must not be
used as deletion approval.

Promote an older flat inbox vault after review and backup:

```bash
./scripts/knowledge-notes.py migrate-vault <vault-path>/AI_AUTO --dry-run
./scripts/knowledge-notes.py migrate-vault <vault-path>/AI_AUTO
```

The real migration creates `<vault-path>/AI_AUTO.backup-YYYYMMDDTHHMMSSZ`
before changing files, moves validated source notes from `Inbox/<project--hash>`
to `Projects/<project--hash>`, refreshes note links, rebuilds hub pages, and
validates the result. It refuses existing backup paths, symlink escape targets,
and target overwrites.

If dry-run reports an existing `Projects/` target, stop and audit the pair
before running the real migration. Classify each conflict as an exact duplicate,
a newer or more complete version to merge, or distinct evidence that needs a
unique Projects filename. Do not bypass the overwrite guard merely to make the
graph view look cleaner.

## External SSD Operation

Project repositories and the Obsidian vault may live on an external SSD. Keep
the AI_AUTO checkout, `~/bin`, `~/.config/ai-lab`, and
`~/.local/state/ai-auto` on the internal Ubuntu/WSL filesystem.

For the local `Z:` SSD, the expected WSL paths are
`/mnt/z/JSJEON/Project_JW`, `/mnt/z/JSJEON/Project_SirD`, and
`/mnt/z/JSJEON/Obsidian/AI_AUTO_Vault`. If a Codex sandboxed command reports
`/mnt/z` as read-only, treat it first as a sandbox writable-root boundary, not
as SSD failure. Use one approved real write probe for the target path before
diagnosing Windows disk state, WSL remounting, or drive health.

Do not use legacy `C:\JSJEON\Obsidian\AI_AUTO_Vault` or
`/mnt/c/JSJEON/Obsidian/AI_AUTO_Vault` paths for new Obsidian writes. Treat
those paths as stale migration sources only, and prefer `config/ai-auto-local.json`,
`AI_AUTO_OBSIDIAN_VAULT_DIR`, or an explicit current vault path before writing
or validating Obsidian material.

Agent-run `ai-auto setup`, AI_AUTO engine updates, and Obsidian vault pushes under
`/mnt/z` require either an approved write command for that target path or a Codex
session configured with the target project/vault as a writable root. Human-run
commands in a normal WSL shell can write to the SSD directly when the real probe
passes.

After moving a project, run `ai-register --prune`, register the new project
path, then run the project doctor and verification.

The vault path must be configured explicitly. Do not scan mounted drives to
discover projects or vaults.

The AI_AUTO home checkout uses `knowledge-collect --include-registry` for broad review; vault writes require
`--project <repo> --vault-dir <vault-path>/AI_AUTO --push`, plus `--allow-local-private` only for a local/private vault.

## External SSD Migration Runbook

1. Record source and target project/vault paths, active branch, and
   `git status --short` for each project.
2. Run one approved real write probe for the target project parent and vault
   parent before diagnosing disk, remount, or drive-health issues.
3. Copy projects and vaults with metadata-preserving tooling after a dry-run
   when available. Keep `.git`, tracked files, and project-owned ignored
   runtime directories together.
4. Do not copy `.omx` wholesale between projects or into the vault. Export only
   curated sanitized notes, feedback summaries, promotion candidates, or handoff
   reports.
5. From each moved project, run `ai-register`, then `ai-register --prune`.
6. Validate the vault with `scripts/knowledge-notes.py validate <vault>/AI_AUTO`
   and rebuild the index when the vault layout changed.
7. Run the project doctor if present, then `./scripts/verify.sh` and
   `./scripts/review-gate.sh` before normal AI_AUTO work resumes.
8. Keep the original source tree untouched until the moved path passes
   verification and review; otherwise re-register the original path and record a
   sanitized incident or feedback item.

## Backup And Promotion

Do not commit `.omx/` wholesale. `.omx/knowledge` is local draft storage only,
not a durable backup or cross-project knowledge base. Durable knowledge lives in
an explicit Obsidian vault path or in tracked docs after reviewed promotion.

Before syncing notes, confirm redaction, destination `sync_class`, reference-only
sources, and no secrets, raw prompts, private paths, or copied logs.

Promotion into AI_AUTO guidance requires normal repo edits plus
`./scripts/verify.sh` and `./scripts/review-gate.sh`. Repeat count alone is not
enough; promotion needs sanitized evidence, stable repeat keys, confidence,
source references, and no unresolved contradictory evidence.
