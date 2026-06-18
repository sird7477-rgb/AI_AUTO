# AI_AUTO Session Log Audit - 2026-06-17

## Scope

- Audit window: 2026-06-10 through 2026-06-17.
- Target surface: AI_AUTO registered projects plus workspace scan results visible from this host.
- Runtime focus: Codex and Claude sessions, with special attention to Claude review-gate behavior.
- Method: read-only inspection of `.omx/logs`, `.omx/review-results`, `.omx/reviewer-state`, project registry, and workspace scan output.

## Project Coverage

| Project | Status | Window evidence |
| --- | --- | --- |
| `/mnt/z/JSJEON/Project_JW/99. odoo/01. A1/jw_dev` | Covered | Dated `omx`, `turns`, `tmux-hook`, `notify-hook`, review-result, and reviewer-state files in the window. |
| `/root/workspace/ai-lab` | Covered | Dated `omx`, `turns`, and `tmux-hook` logs for 2026-06-10, 06-11, 06-12, and 06-15. |
| `/root/workspace/ai-lab-tmux-w0` | Covered | Dated `omx`, `turns`, and `tmux-hook` logs for 2026-06-17. |
| `/mnt/z/JSJEON/Project_SirD/01. Project_zurini/NEW` | No window session logs | `.omx/logs/session-history.jsonl` exists, but no dated window logs were found. |
| `/mnt/z/JSJEON/Project_SirD/01-1. Project_corini` | No window session logs | `.omx/logs` contains 2026-06-06 logs only. |
| Three `/mnt/c/...` registry entries | Inaccessible | Registered paths were not present from this host. |

## Findings

1. AI_AUTO is active, but not cleanly healthy across the whole surface.
   - Codex sessions show principal-subagent review activity, request-change outcomes, approvals with notes, and review artifacts.
   - Claude principal sessions in `ai-lab` triggered Codex principal-review rotation, including real `request_changes` findings against review-gate behavior.
   - Hook-level automation frequently skipped because sessions were unmanaged, target panes were missing, or panes already had active tasks.

2. Claude review-gate coverage is degraded in `jw_dev`.
   - `.omx/reviewer-state/claude.disabled` records `retry_exhausted` with `ConnectionRefused` on 2026-06-15.
   - `.omx/reviewer-state/gemini.disabled` also records retry exhaustion.
   - Later review-gate runs used principal-subagent substitute coverage instead of full external Claude/Gemini reviewer coverage.
   - This is not equivalent to clean independent Claude review participation.

3. Review-gate did block or defer risky states.
   - `review-verdict-20260615T165521.md` reports `blocked` with reason `all_reviewers_failed`.
   - `review-verdict-20260617T173906.md` reports `review_manually` with reason `material_untracked_artifacts_require_manual_review`.
   - `jw_dev` turn logs also show review comments requesting changes when required Docker smoke evidence was missing.
   - Therefore the gate is not merely rubber-stamping approvals.

4. The audit trail is insufficient for full per-commit reconstruction.
   - Some `turns` entries contain user-facing summaries rather than raw command transcripts.
   - Several sessions mention verification or review-gate results without enough structured command evidence to prove every command, exit code, trust level, and reviewer state.
   - Review artifacts are stronger evidence than turn summaries, but they are not consistently tied to every commit/push action in the logs.

5. Domain validation escaped at least one meaningful issue in `jw_dev`.
   - Logs show post-push Odoo build failures such as manifest/missing-file style errors despite pre-push validation claims.
   - This points to a validation coverage gap rather than proof that review-gate falsely approved the change.

6. Autonomy control showed one behavioral concern.
   - A `jw_dev` session includes the user correction "수정하라고 안했자나".
   - The assistant reported that the attempted patch failed and no file change landed, but the attempted action still indicates an autonomy-boundary issue.

## Verdict

AI_AUTO should be considered partially functioning with degraded reviewer trust.

- Codex path: functioning, with visible review-loop activity and request-change behavior.
- Claude path: CLI was broken on 2026-06-17 and then repaired; earlier Claude-principal rotation existed, but Claude-as-reviewer was disabled in `jw_dev` after retry exhaustion.
- Review-gate: mechanically active and capable of blocking, but not consistently backed by clean Claude/Gemini external reviewer coverage or complete command-level audit evidence.

The best current label is `partial_normal_with_reviewer_degradation`, not `healthy`.

## Recommended Follow-ups

1. Reset and smoke-test disabled reviewers after confirming the repaired Claude CLI:
   - `RESET_DISABLED_AI_REVIEWERS=claude ./scripts/review-gate.sh`
   - Repeat for Gemini only after its filesystem/logging issue is fixed.

2. Add structured audit records for verification and review-gate execution:
   - command
   - working directory
   - exit code
   - final decision
   - trust level
   - reviewer list
   - disabled/skipped reviewer state
   - artifact paths

3. Make degraded reviewer coverage impossible to miss in final reports.
   - If Claude/Gemini are skipped, failed, or substituted, the final response should say so explicitly.
   - Treat substitute-only coverage as degraded unless the policy intentionally defines it as regular trust.

4. Investigate frequent hook skips:
   - `unmanaged_session`
   - `target_not_found`
   - `pane_has_active_task`
   - `mode_not_allowed`

5. Strengthen Odoo domain validation for manifest and missing-file checks before commit/push.

## Evidence Pointers

- `/mnt/z/JSJEON/Project_JW/99. odoo/01. A1/jw_dev/.omx/reviewer-state/claude.disabled`
- `/mnt/z/JSJEON/Project_JW/99. odoo/01. A1/jw_dev/.omx/reviewer-state/gemini.disabled`
- `/mnt/z/JSJEON/Project_JW/99. odoo/01. A1/jw_dev/.omx/review-results/review-verdict-20260615T165521.md`
- `/mnt/z/JSJEON/Project_JW/99. odoo/01. A1/jw_dev/.omx/review-results/review-verdict-20260617T173906.md`
- `/mnt/z/JSJEON/Project_JW/99. odoo/01. A1/jw_dev/.omx/logs/turns-2026-06-12.jsonl`
- `/mnt/z/JSJEON/Project_JW/99. odoo/01. A1/jw_dev/.omx/logs/turns-2026-06-15.jsonl`
- `/root/workspace/ai-lab/.omx/logs/turns-2026-06-10.jsonl`
- `/root/workspace/ai-lab/.omx/logs/turns-2026-06-11.jsonl`
- `/root/workspace/ai-lab-tmux-w0/.omx/logs/turns-2026-06-17.jsonl`
