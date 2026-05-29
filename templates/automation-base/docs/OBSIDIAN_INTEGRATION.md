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
  templates, doctor checks, review gates, `aiinit`, or domain packs

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
  --output-dir <vault-path>/AI_AUTO/Inbox \
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

Agent-written `aiinit`, AI_AUTO template patches, and Obsidian vault pushes under
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
