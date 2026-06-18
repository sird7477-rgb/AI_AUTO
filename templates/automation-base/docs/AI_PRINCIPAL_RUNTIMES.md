# AI Principal Runtimes

AI_AUTO uses one active principal runtime for execution and assigns the other
eligible runtimes as reviewers. The principal can be `codex`, `claude`, or
`gemini`.

## Contract

All principals share the same repo-local authority: read instructions, edit
repository files, run local verification, write `.omx/*` artifacts, and prepare
the completion report. Commit, push, deploy, production, destructive, and
credentialed work still require the same user approval for every principal.

Provider differences are CLI/protocol differences, not permission differences.
If a runtime cannot satisfy the contract, AI_AUTO reports
`principal_unavailable` instead of silently reducing its authority.

External principals require launcher-owned evidence. `AI_AUTO_PRINCIPAL=claude`
or `AI_AUTO_PRINCIPAL=gemini` is only a selection request; the launcher must
write `.omx/state/principal-runtime/current.env` with the runtime, principal
execution mode, `source=ai-auto-principal-launcher`, and current workspace path.
Missing, manual, or mismatched evidence makes review-gate fail closed.

## Reviewer Rotation

The active principal cannot self-review.

```text
principal codex  -> reviewers claude, gemini
principal claude -> reviewers gemini, codex
principal gemini -> reviewers claude, codex
```

Codex reviewer coverage during `claude` or `gemini` principal runs is normal
principal rotation, not degraded fallback coverage.

## Principal Subagent Substitute

If an expected reviewer is unavailable, the active principal's subagent covers
that reviewer lane as a degraded substitute reviewer for the run (reported as
proceed_degraded with degraded trust, not independent external review):

```text
codex + unavailable claude/gemini -> codex principal-subagent review
claude + unavailable gemini       -> claude substitute review plus codex reviewer
gemini + unavailable claude       -> gemini substitute review plus codex reviewer
```

Substitute coverage is always degraded, not independent external review. With a
usable verdict and a `Direct File Inspection` section it is reported as
proceed_degraded with degraded trust; otherwise the gate reports blocked coverage.

## Artifact Invariance

Changing the principal must not change artifact roots: `.omx/state/`,
`.omx/plans/`, `.omx/review-context/`, `.omx/review-prompts/`,
`.omx/review-results/`, and `.omx/logs/`. Review manifests and verdict summaries
record the active principal for handoff reconstruction.

## Selection

The default principal is `codex`.

```bash
AI_AUTO_PRINCIPAL=claude ./scripts/review-gate.sh
AI_AUTO_PRINCIPAL=gemini ./scripts/review-gate.sh
```

Worktree isolation is not the default principal path. It remains a delegated
executor safety option, not a way to give Claude or Gemini less repo-local
authority than Codex.
