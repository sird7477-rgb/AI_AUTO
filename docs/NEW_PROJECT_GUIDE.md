# New Project Automation Guide

This guide explains how to initialize the automation workflow in a new repository.

## Manual setup

From inside the target git repository:

    aiinit

Or from another directory:

    aiinit /path/to/target-repo

`aiinit` installs the automation template, creates `.omx/reviewer-state`, adds `.omx/` to the target repository's local `.git/info/exclude`, and then runs the installed automation doctor with the install-time dirty-tree check skipped.

After `aiinit`, ask the AI:

    프로젝트 초기설정 해줘

Equivalent detailed request:

    프로젝트 요구사항을 인터뷰하고, .omx/domain-packs/에 설치된 선택 적용 표준팩 중
    적용할 항목이 있는지 확정한 뒤, AGENTS.md, docs/WORKFLOW.md,
    scripts/verify.sh를 프로젝트에 맞게 설정해줘

This should start a short onboarding interview before real work begins. Capture:

- project purpose and non-goals
- whether a domain pack applies, such as the Odoo pack for Odoo projects
- stack and runtime commands
- allowed and forbidden change types
- required verification commands
- smoke checks that prove the final result works
- project-specific docs or domain constraints

Then customize:

    AGENTS.md
    docs/WORKFLOW.md
    scripts/verify.sh

The generated `scripts/verify.sh` is a placeholder and exits non-zero until it is replaced with project-specific checks.

Run the gate:

    ./scripts/automation-doctor.sh
    ./scripts/verify.sh
    ./scripts/review-gate.sh

## Codex setup request

Use this request when asking Codex to initialize a new project:

    이 프로젝트에 자동화 기반을 초기화해줘.

    절차:
    1. 현재 경로와 git 상태를 확인해.
    2. aiinit을 실행해.
    3. aiinit이 출력한 automation-doctor 결과를 확인해.
    4. 프로젝트 목적, 스택, 완료 기준, 금지 범위를 인터뷰해.
    5. .omx/domain-packs/에 설치된 선택 적용 표준팩을 확인하고, 이 프로젝트에 적용할 팩과 제외할 팩을 인터뷰로 확정해.
    6. 적용하기로 확정한 표준팩이 있으면 필요한 항목만 반영해.
    7. 생성된 AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 프로젝트에 맞게 수정해.
    8. ./scripts/automation-doctor.sh를 실행해.
    9. ./scripts/verify.sh를 실행해.
    10. ./scripts/review-gate.sh를 실행해.
    11. 커밋은 하지 말고 결과만 보고해.

    완료 보고에는 아래를 포함해:
    - 변경 파일
    - automation-doctor 결과
    - 인터뷰에서 확정한 운영 지침
    - verify.sh에 넣은 검증 기준
    - verify 결과
    - review-gate 결과
    - Claude 리뷰 요약
    - Gemini skip 여부
    - 남은 warning 또는 제한사항
    - 커밋하지 않았다는 확인

## Short request

    현재 프로젝트에 aiinit으로 자동화 템플릿을 설치해줘. aiinit 이후 프로젝트 목적, 스택, 완료 기준, 금지 범위를 인터뷰해서 AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 이 프로젝트에 맞게 설정하고, ./scripts/automation-doctor.sh, ./scripts/verify.sh, ./scripts/review-gate.sh까지 통과시켜줘. 커밋은 하지 말고 결과만 보고해.

## Post-aiinit request

Use this after `aiinit` has already installed the template:

    프로젝트 초기설정 해줘

## Domain Packs

Domain packs are optional reference packs for project-specific onboarding.
`aiinit` copies them into the target repository only as ignored runtime
references under `.omx/domain-packs/`. It does not merge them into project
instructions automatically.

Source packs in this repository:

    templates/domain-packs/odoo/

During onboarding, the AI should ask whether the project matches an available
pack. In the target repository, read the installed copy from `.omx/domain-packs/`.
If a pack applies, use it as source material for `AGENTS.md`,
`docs/WORKFLOW.md`, and `scripts/verify.sh`. Apply only the parts that match the
actual project. Keep unrelated domain guidance out of generic projects.

The onboarding interview should explicitly record:

- selected domain pack names
- rejected domain pack names
- project-specific rules that must stay outside the reusable domain pack

## Existing Project Adoption

`aiinit` is intentionally conservative. If an existing project already has files
such as `AGENTS.md`, `docs/WORKFLOW.md`, or `scripts/verify.sh`, it stops instead
of overwriting them.

For an existing or already-advanced project, ask the AI:

    기존 프로젝트에 자동화 기반을 병합 도입해줘.
    기존 AGENTS.md, docs, scripts/verify.sh는 덮어쓰지 말고 먼저 분석한 뒤
    필요한 자동화 파일과 지침만 제안/반영해줘.

The AI should preserve existing project instructions and verification behavior,
then add only the missing automation files or guidance needed for the Codex/OMX
workflow.

Recommended adoption flow:

1. Read the existing `AGENTS.md`, workflow docs, and verification scripts.
2. List what the existing project already covers.
3. Compare against the current automation template.
4. Propose a small merge plan before editing.
5. Copy only missing automation scripts or docs that do not overwrite project
   rules.
6. Preserve project-specific instructions as the source of truth when they are
   stricter than the reusable template.
7. Run `./scripts/automation-doctor.sh`, the project verification command, and
   `./scripts/review-gate.sh`.

## Notes

- `aiinit` must be run inside a git repository.
- `aiinit /path/to/repo` may be used from outside the target repository.
- `aiinit` runs the installed `./scripts/automation-doctor.sh` after template installation.
- `./scripts/automation-doctor.sh` diagnoses automation readiness and suggests repair commands.
- `./scripts/automation-doctor.sh --fix` may apply only safe non-overwriting setup fixes.
- Project-specific agent instructions belong in `AGENTS.md`.
- Project-specific workflow notes belong in `docs/WORKFLOW.md`.
- Project-specific checks belong in `scripts/verify.sh`.
- Do not keep the placeholder `scripts/verify.sh` as a real project gate.
- Commit only after reviewing the generated files and verification results.
