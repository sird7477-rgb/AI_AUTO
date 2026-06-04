# AI_AUTO Domain-Pack Refresh Plan - 2026-06-05

## Goal

Make AI_AUTO domain-pack updates deterministic across projects without
project-by-project manual copy work.

## Consensus Inputs

- Claude artifact:
  `.omx/artifacts/claude-ai-auto-domain-pack-refresh-design-review-context-root-works-2026-06-04T18-32-42-627Z.md`
- Gemini artifact:
  `.omx/artifacts/gemini-ai-auto-domain-pack-refresh-design-review-context-root-works-2026-06-04T18-31-43-264Z.md`

Gemini approved the direction. Claude approved the direction only after two
required changes: legacy no-manifest copies must be report-only unless
provably adoptable, and deliberately removed packs must not be resurrected.
Those requirements are promoted into the implementation contract below.

## Implementation Contract

1. Source packs remain under `templates/domain-packs/<name>/`.
2. Installed references remain ignored runtime files under
   `.omx/domain-packs/<name>/`.
3. New installs write sidecar manifests under `.omx/domain-packs/.manifest/`.
4. Status uses a three-way comparison:
   - current source
   - current installed copy
   - install-time manifest baseline
5. `ai-domain-pack status` is read-only.
6. `ai-domain-pack refresh` is dry-run by default.
7. `ai-domain-pack refresh --apply` may write only inside `.omx/domain-packs/`.
8. Clean managed copies may be refreshed mechanically.
9. Exact-match legacy copies may be adopted by writing a manifest.
10. Dirty legacy copies, local modifications, missing tracked files, local extra
    files, unreadable manifests, and experimental source branches fail closed.
11. A pack with a manifest but no installed directory is treated as deliberately
    removed and is not reinstalled.
12. Refresh never edits project `AGENTS.md`, `docs/WORKFLOW.md`, or
    `scripts/verify.sh`.

## Micro Work Units

- Add `tools/ai-domain-pack` with `status` and `refresh` subcommands.
- Seed manifests from `scripts/install-automation-template.sh` for newly copied
  packs while preserving existing installed pack directories.
- Wire the helper into global installer, bootstrap, doctor, and rebuild
  preflight surfaces.
- Add `verify.sh` cases for current, dry-run, clean update, idempotence, local
  modification refusal, exact-match legacy adoption, dirty legacy refusal,
  deliberately removed pack preservation, and experimental branch write guard.
- Update lifecycle docs, global-tool docs, template README, patch notes, and
  template version.

## Completion Evidence

Required evidence before claiming completion:

- `python3 -m py_compile tools/ai-domain-pack`
- targeted domain-pack refresh fixture in `./scripts/verify.sh`
- full `./scripts/verify.sh`
- Claude-enabled `./scripts/review-gate.sh`

## Status

Implemented in the 2026.06.05.1 template promotion.
