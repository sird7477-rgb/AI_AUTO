# New Project Automation Guide

This guide explains how to initialize the automation workflow in a new repository.

## Manual setup

From inside the target git repository:

    aiinit

Or from another directory:

    aiinit /path/to/target-repo

`aiinit` installs the automation template, creates `.omx/reviewer-state`, and then runs the installed automation doctor with the install-time dirty-tree check skipped.

Then customize:

    scripts/verify.sh

Run the gate:

    ./scripts/verify.sh
    ./scripts/review-gate.sh

## Codex setup request

Use this request when asking Codex to initialize a new project:

    이 프로젝트에 자동화 기반을 초기화해줘.

    절차:
    1. 현재 경로와 git 상태를 확인해.
    2. aiinit을 실행해.
    3. aiinit이 출력한 automation-doctor 결과를 확인해.
    4. 생성된 AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 확인해.
    5. scripts/verify.sh를 이 프로젝트에 맞게 수정해.
    6. ./scripts/verify.sh를 실행해.
    7. ./scripts/review-gate.sh를 실행해.
    8. 커밋은 하지 말고 결과만 보고해.

    완료 보고에는 아래를 포함해:
    - 변경 파일
    - automation-doctor 결과
    - verify.sh에 넣은 검증 기준
    - verify 결과
    - review-gate 결과
    - Claude 리뷰 요약
    - Gemini skip 여부
    - 남은 warning 또는 제한사항
    - 커밋하지 않았다는 확인

## Short request

    현재 프로젝트에 aiinit으로 자동화 템플릿을 설치하고, aiinit이 출력한 automation-doctor 결과를 확인한 뒤, 이 프로젝트에 맞게 scripts/verify.sh를 수정하고 ./scripts/review-gate.sh까지 통과시켜줘. 커밋은 하지 말고 결과만 보고해.

## Notes

- `aiinit` must be run inside a git repository.
- `aiinit /path/to/repo` may be used from outside the target repository.
- `aiinit` runs the installed `./scripts/automation-doctor.sh` after template installation.
- `./scripts/automation-doctor.sh` diagnoses automation readiness and suggests repair commands.
- `./scripts/automation-doctor.sh --fix` may apply only safe non-overwriting setup fixes.
- Project-specific checks belong in `scripts/verify.sh`.
- Do not blindly reuse ai-lab Flask checks in other projects.
- Commit only after reviewing the generated files and verification results.
