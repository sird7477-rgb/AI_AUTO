# Automation Base Template

This template contains the base files for a CLI-based AI development workflow.

## Included

- AGENTS.md: repo-local agent operating rules
- docs/WORKFLOW.md: project workflow documentation
- scripts/verify.example.sh: example verification script; customize per project
- scripts/collect-review-context.sh: collects git diff and workflow context
- scripts/make-review-prompts.sh: generates reviewer prompts
- scripts/run-ai-reviews.sh: runs available AI reviewers
- scripts/summarize-ai-reviews.sh: summarizes reviewer verdicts
- scripts/review-gate.sh: runs verification, reviews, and verdict summary

## How to use in a new project

Copy the template into the target repository.

Example:

    cp -r templates/automation-base/* /path/to/target-repo/

Then customize:

    mv scripts/verify.example.sh scripts/verify.sh
    chmod +x scripts/*.sh

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

    git add .
    git commit -m "test: initialize automation template smoke repo"

    ./scripts/verify.sh
    ./scripts/review-gate.sh

The smoke test should complete with verification success, Claude review if available, Gemini skipped by default, and a review verdict summary.
