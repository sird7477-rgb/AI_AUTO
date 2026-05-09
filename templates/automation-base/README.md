# Automation Base Template

This template contains the base files for a CLI-based AI development workflow.

## Included

- AGENTS.md: repo-local agent operating rules
- docs/WORKFLOW.md: project workflow documentation
- scripts/automation-doctor.sh: diagnoses automation readiness and suggests safe repairs
- scripts/archive-omx-artifacts.sh: archives old ignored review artifacts while preserving latest evidence
- scripts/verify.example.sh: onboarding placeholder; replace with project-specific verification
- scripts/collect-review-context.sh: collects git diff and workflow context
- scripts/discover-ai-models.sh: discovers local AI CLI model routing capabilities
- scripts/make-review-prompts.sh: generates reviewer prompts
- scripts/record-project-memory.sh: appends sanitized durable memory entries
- scripts/run-ai-reviews.sh: runs available AI reviewers
- scripts/summarize-ai-reviews.sh: summarizes reviewer verdicts
- scripts/test-review-summary.sh: fixture tests for review verdict decisions
- scripts/review-gate.sh: runs verification, reviews, and verdict summary
- scripts/write-session-checkpoint.sh: writes resume checkpoints after review gates

## How to use in a new project

Copy the template into the target repository.

Example:

    cp -r templates/automation-base/* /path/to/target-repo/

Then customize:

    mv scripts/verify.example.sh scripts/verify.sh
    mkdir -p .omx/reviewer-state
    chmod +x scripts/*.sh

Check the automation setup:

    ./scripts/automation-doctor.sh

Template-specific helper link and `~/bin` PATH checks only run when the script detects the ai-lab source tree.

Then ask the AI:

    프로젝트 초기설정 해줘

Equivalent detailed request:

    프로젝트 요구사항을 인터뷰하고, .omx/domain-packs/에 설치된 선택 적용 표준팩 중
    적용할 항목이 있는지 확정한 뒤, AGENTS.md, docs/WORKFLOW.md,
    scripts/verify.sh를 프로젝트에 맞게 설정해줘

The AI should interview the project owner, then update the generated files for the target project:

    AGENTS.md
    docs/WORKFLOW.md
    scripts/verify.sh

The installed `scripts/verify.sh` is intentionally not project-ready. It exits
non-zero until it is replaced with real checks for the target repository.

## Smoke test the template

You can test this template in a temporary repository before applying it to a real project.

Example:

    cd ~/workspace
    rm -rf automation-template-smoke
    mkdir automation-template-smoke
    cd automation-template-smoke
    git init

    cp -r ~/workspace/ai-lab/templates/automation-base/* .

    mv scripts/verify.example.sh scripts/verify.sh
    mkdir -p .omx/reviewer-state
    chmod +x scripts/*.sh

    cat > scripts/verify.sh <<'VERIFY'
    #!/usr/bin/env bash
    set -euo pipefail

    echo "[verify] smoke test for automation template"
    test -f AGENTS.md
    test -f docs/WORKFLOW.md
    test -x scripts/review-gate.sh

    echo "[verify] success"
    VERIFY

    chmod +x scripts/verify.sh

    ./scripts/automation-doctor.sh
    git add .
    git commit -m "test: initialize automation template smoke repo"

    ./scripts/verify.sh
    ./scripts/review-gate.sh

The smoke test should complete with verification success, Claude review if available, Gemini review if available, and a review verdict summary. Set RUN_GEMINI_REVIEW=0 to skip Gemini for a specific run. Large Gemini prompts are sent through stdin to avoid command-line argument length limits. Reviewer-specific timeouts are available as CLAUDE_REVIEW_TIMEOUT_SECONDS and GEMINI_REVIEW_TIMEOUT_SECONDS, with REVIEW_TIMEOUT_KILL_AFTER_SECONDS as the forced-kill grace period. Claude defaults to a longer reviewer timeout because login-based CLI calls can take more than a minute.

Reviewer failures are stateful. Session, weekly, quota, or rate-limit failures disable that reviewer immediately. Other failures retry up to REVIEW_RETRY_LIMIT times before disabling the reviewer. Disabled reviewer state is stored under `.omx/reviewer-state` and is announced on every run until reset with RESET_DISABLED_AI_REVIEWERS=claude, RESET_DISABLED_AI_REVIEWERS=gemini, or RESET_DISABLED_AI_REVIEWERS=all.

Each review run writes a `review-run-*.md` manifest under `.omx/review-results/` linking the context, prompts, outputs, model routing report, fallback artifacts, external runner, and disabled reviewer state for that run.

Before the first AI reviewer invocation in a run, `scripts/discover-ai-models.sh` writes `.omx/model-routing/latest.env` and `.omx/model-routing/latest.md`. The review runner sources that env file and applies model selectors only when the installed CLI supports `--model`.

Model routing is role-first: choose the role/capability first, then resolve it against the current local CLI/runtime/account surface. Provider docs are reference material, not proof that this local CLI can use a model. Use `CLAUDE_REVIEW_ROLE`, `GEMINI_REVIEW_ROLE`, `CODEX_ARCHITECT_REVIEW_ROLE`, `CODEX_TEST_REVIEW_ROLE`, `CLAUDE_REVIEW_MODEL`, `GEMINI_REVIEW_MODEL`, `CODEX_ARCHITECT_REVIEW_MODEL`, `CODEX_TEST_REVIEW_MODEL`, or `CODEX_FALLBACK_MODEL` to override routing without editing scripts. Set `AI_MODEL_DISCOVERY=0` to use provider defaults.

Long-running session operation is described in `docs/SESSION_QUALITY_PLAN.md`.
Use it for model-routing cache policy, working memory capture, checkpoints, and
token/context hygiene.

When a reviewer is disabled, the remaining external reviewer prompt stays focused on its own role. The disabled lane is covered by a separate Codex/GPT fallback review artifact, such as `codex-architect-fallback-*.md` or `codex-test-fallback-*.md`. If both external reviewers are disabled, both fallback reviewers are required and the verdict is reported as degraded coverage such as `codex_only_degraded`; it does not count as independent Claude/Gemini approval. Codex fallback uses `codex exec` when available; set `RUN_CODEX_FALLBACK_REVIEW=0` only for diagnostics.

If the current agent context blocks reviewer network access or runtime writes, use:

    REVIEW_EXECUTION_MODE=external ./scripts/review-gate.sh

Then run the generated `.omx/external-review/run-reviewers-latest.sh` script from an unrestricted interactive terminal. The script resolves the repository root from its own location before running the reviewers, shows reviewer output with `tee`, uses the already-prepared prompts by default, and allows execution-time timeout overrides.

External reviewer preparation reports disabled reviewers before stopping. The generated external runner shares `.omx/reviewer-state/`, so reset a disabled reviewer first if the interactive terminal should retry it.

Review context lists untracked files but omits their content by default. Set `REVIEW_INCLUDE_UNTRACKED_CONTENT=1` for review-gate runs, or `INCLUDE_UNTRACKED_CONTENT=1` when calling `scripts/collect-review-context.sh` directly, to include untracked text files up to `MAX_UNTRACKED_BYTES` bytes after confirming secrets and generated output are covered by `.gitignore`.

`aiinit` adds `.omx/` to the target repository's local `.git/info/exclude` so generated review, model-routing, and reviewer-state artifacts do not become commit candidates by default.

`./scripts/review-gate.sh` and `./scripts/automation-doctor.sh --fix` automatically archive old `.omx/review-results` files when runtime artifacts grow beyond `OMX_REVIEW_ARCHIVE_THRESHOLD` or `OMX_ARTIFACT_WARN_COUNT`. The archive keeps recent/latest evidence active, moves older files under `.omx/review-results/archive/`, and never deletes unless `./scripts/archive-omx-artifacts.sh --delete` is explicitly used.
