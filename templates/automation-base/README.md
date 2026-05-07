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
