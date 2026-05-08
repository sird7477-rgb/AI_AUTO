# Automation Base Template

This template contains the base files for a CLI-based AI development workflow.

## Included

- AGENTS.md: repo-local agent operating rules
- docs/WORKFLOW.md: project workflow documentation
- scripts/automation-doctor.sh: diagnoses automation readiness and suggests safe repairs
- scripts/verify.example.sh: example verification script; customize per project
- scripts/collect-review-context.sh: collects git diff and workflow context
- scripts/make-review-prompts.sh: generates reviewer prompts
- scripts/run-ai-reviews.sh: runs available AI reviewers
- scripts/summarize-ai-reviews.sh: summarizes reviewer verdicts
- scripts/test-review-summary.sh: fixture tests for review verdict decisions
- scripts/review-gate.sh: runs verification, reviews, and verdict summary

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

Update scripts/verify.sh for the target project.

Do not keep ai-lab-specific checks in a real project unless they are relevant.

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

When a reviewer is disabled, the remaining external reviewer prompt stays focused on its own role. The disabled lane is covered by a separate Codex/GPT fallback review artifact, such as `codex-architect-fallback-*.md` or `codex-test-fallback-*.md`. If both external reviewers are disabled, both fallback reviewers are required and the verdict is reported as degraded coverage such as `codex_only_degraded`; it does not count as independent Claude/Gemini approval. Codex fallback uses `codex exec` when available; set `RUN_CODEX_FALLBACK_REVIEW=0` only for diagnostics.

If the current agent context blocks reviewer network access or runtime writes, use:

    REVIEW_EXECUTION_MODE=external ./scripts/review-gate.sh

Then run the generated `.omx/external-review/run-reviewers-latest.sh` script from an unrestricted interactive terminal. The script resolves the repository root from its own location before running the reviewers, shows reviewer output with `tee`, uses the already-prepared prompts by default, and allows execution-time timeout overrides.

Review context lists untracked files but omits their content by default. Set `INCLUDE_UNTRACKED_CONTENT=1` to include untracked text files up to `MAX_UNTRACKED_BYTES` bytes after confirming secrets and generated output are covered by `.gitignore`.
