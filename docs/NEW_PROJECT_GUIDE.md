# New Project Automation Guide

This guide explains how to initialize the automation workflow in a new repository.

## Manual setup

From inside the target git repository:

    aiinit

Or from another directory:

    aiinit /path/to/target-repo

`aiinit` installs the automation template, creates `.omx/reviewer-state`, adds
`.omx/` to the target repository's local `.git/info/exclude`, registers the
project in the local AI_AUTO project registry, and then runs the installed
automation doctor with the install-time dirty-tree check skipped. It also
installs `AI_AUTO_TEMPLATE_VERSION`, a lightweight marker used by
`ai-auto-template-status` to compare the project with the current AI_AUTO
template.

After `aiinit`, ask the AI:

    프로젝트 초기설정 해줘

Equivalent detailed request:

    프로젝트 요구사항을 인터뷰하고, docs/*_COMPLETION.md 완료팩과
    .omx/domain-packs/에 설치된 도메인팩 중 적용할 항목이 있는지 확정한 뒤,
    리뷰 강도, 실패 패턴 기록, 승인 마찰 관리, 서브에이전트 사용 기준을 정하고
    작업 중 플랜/인터뷰 강도와 Incident Ops 감시/장애대응 기준까지 정한 뒤,
    AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 프로젝트에 맞게 설정해줘

This should start the `docs/INTERVIEW_PLAN_LAYER.md` onboarding interview before
real work begins. Keep questions narrow, inspect local evidence first, map each
answer into the project baseline, and track ambiguity instead of hiding
assumptions. Capture:

- project purpose and non-goals
- users, final deliverable, and assumptions that could not be confirmed from
  local files
- review intensity: `lightweight`, `standard`, or `strict`
- whether sanitized failure patterns and improvement ideas may be recorded in
  `.omx/feedback/queue.jsonl`
- recurring approval/permission friction to handle with narrow approved command
  prefixes or repo helpers, without bypassing destructive or credentialed
  approvals
- native subagent usage boundaries for lookup, implementation slices, testing,
  UX review, dependency research, and critique; final integration remains with
  the leader
- resource-aware parallelism expectations: inspect local CPU, memory, disk, and
  load first; then ask about shutdown history, concurrent heavy sessions,
  thermal limits, and maximum acceptable parallelism
- planning/interview intensity expectations for future work: `none`, `light`,
  `standard`, or `deep`
- operational readiness rules: required inputs, fail-closed blockers,
  accepted operating artifacts, read-only/auth/network preflight, and
  sandbox-vs-real-network evidence, and analysis-only fallback boundaries
- Incident Ops rules: dry-run/field-test monitoring, automatic action classes,
  incident log fields, UI field-test evidence, and heartbeat/quiet/active
  incident reporting intervals from `docs/INCIDENT_OPS.md`
- plan management rules: current plan index, TODO reconciliation, checkpoint
  update expectations, and where detailed runbooks or long checklists should live
- spec/design alignment rules: which plan, specification, or design artifacts
  code edits must be compared against before completion
- user-facing report language: plain Korean outcome summaries first, without
  leading with internal variable names unless they are needed for reproduction
  or user action
- guidance context budget: what belongs in `AGENTS.md` versus linked docs
- selected and rejected completion packs from `docs/*_COMPLETION.md`
- whether a domain pack applies, such as the Odoo pack for Odoo projects
- stack and runtime commands
- allowed and forbidden change types
- required verification commands
- smoke checks that prove the final result works
- completion checks from selected completion packs
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
    4. 기존 README/docs/package/script를 먼저 읽고, 프로젝트 목적, 사용자, 최종 산출물, non-goal, 스택, 완료 기준, 금지 범위를 인터뷰해.
    5. 리뷰 강도를 lightweight/standard/strict 중에서 확정해. 기본 추천은 standard야.
    6. 민감정보를 제외한 실패 패턴/개선사항을 .omx/feedback/queue.jsonl에 기록할지 확인해.
    7. 반복되는 비파괴 명령의 승인 마찰을 줄일 approved prefix/helper 기준을 정해. 단 destructive/credential/production 작업은 승인 대상으로 유지해.
    8. 서브에이전트 사용 기준을 정해. repo 탐색, 분리 가능한 구현, 테스트/UX/의존성 검토, critique는 위임 가능하지만 최종 통합과 완료 주장은 leader 책임으로 둬.
    9. CPU/메모리/디스크/로드를 가능한 범위에서 직접 확인한 뒤, 우분투/WSL 강제 종료 이력, 동시에 돌아가는 무거운 세션, 발열 한계, 최대 병렬 작업 수를 인터뷰해서 resource-aware parallelism 기준을 정해.
    10. 작업 중 플랜/인터뷰 강도 기준을 docs/INTERVIEW_PLAN_LAYER.md에 맞춰 정해. 작은 작업은 즉시 실행, 방향이 갈리는 작업은 좁은 질문, 장기 정책/아키텍처/검증 체계는 plan-first interview를 기본으로 해.
    11. 운영 준비 규칙을 정해. 필수 입력이 missing/stale/incomplete/degraded이면 fail-closed로 막고, partial success는 진단으로만 남기며 accepted operating artifact로 저장하지 않게 해.
    12. operational dry-run/deployment 전에 read-only/auth/network 권한, DB, token, cooldown, output path, API budget, side-effect boundary preflight 기준을 정해. sandboxed external API probe 실패와 승인된 real-network path 결과를 구분해.
    13. Incident Ops 기준을 정해. dry-run/field-test 감시, 자동 조치 class, incident log 필드, UI field-test evidence, heartbeat/quiet/active-incident 보고 주기를 docs/INCIDENT_OPS.md 기준으로 프로젝트에 맞게 확정해.
    14. plan index와 TODO reconciliation 기준을 정해. 코드 수정 후 어떤 기획서/사양서/설계자료와 diff를 대조할지도 정해.
    15. 사용자에게 보고할 때 변수명이나 내부 식별자를 앞세우지 않고 쉬운 한국어로 먼저 설명하는 기준을 정해.
    16. 긴 runbook/checklist는 AGENTS.md에 계속 붙이지 말고 linked docs로 분리해.
    17. docs/*_COMPLETION.md 완료팩 중 UI, 배포, 보안, 데이터, 성능, 관측성 중 무엇이 필요한지 확인해. 필요한 팩은 완료/검증 조건을 잡고, 필요 없는 팩은 non-goal로 기록한 뒤 프로젝트 문서에 불필요하면 삭제해.
    18. .omx/domain-packs/에 설치된 선택 적용 도메인팩을 확인하고, 이 프로젝트에 적용할 팩과 제외할 팩을 인터뷰로 확정해.
    19. 적용하기로 확정한 완료팩/도메인팩이 있으면 필요한 항목만 반영해.
    20. 생성된 AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 프로젝트에 맞게 수정해.
    21. ./scripts/automation-doctor.sh를 실행해.
    22. ./scripts/verify.sh를 실행해.
    23. 확정한 리뷰 강도에 맞춰 ./scripts/review-gate.sh를 실행해.
    24. 커밋은 하지 말고 결과만 보고해.

    완료 보고에는 아래를 포함해:
    - 변경 파일
    - automation-doctor 결과
    - 인터뷰에서 확정한 운영 지침
    - 리뷰 강도와 승인 마찰 관리 기준
    - 실패 패턴/개선사항 기록 여부
    - 서브에이전트 사용 기준
    - docs/INTERVIEW_PLAN_LAYER.md 기준의 플랜/인터뷰 강도와 질문 범위 최소화 기준
    - 운영 준비 fail-closed 기준
    - Incident Ops 감시/장애대응/주기보고 기준
    - plan index/TODO reconciliation 기준
    - spec/design alignment 기준
    - 사용자 보고를 쉬운 한국어로 먼저 작성하는 기준
    - AGENTS.md와 linked docs 분리 기준
    - 선택/제외한 완료팩과 선택한 팩의 완료/검증 기준
    - verify.sh에 넣은 검증 기준
    - verify 결과
    - review-gate 결과
    - Claude 리뷰 요약
    - Gemini skip 여부
    - 남은 warning 또는 제한사항
    - 커밋하지 않았다는 확인

## Short request

    현재 프로젝트에 aiinit으로 자동화 템플릿을 설치해줘. aiinit 이후 기존 파일을 먼저 읽고 프로젝트 목적, 사용자, 최종 산출물, non-goal, 스택, 완료 기준, 금지 범위, 리뷰 강도(lightweight/standard/strict), 실패 패턴/개선사항 기록 여부, 승인 마찰 관리 기준, 서브에이전트 사용 기준, 플랜/인터뷰 강도 기준(none/light/standard/deep), 운영 준비 fail-closed 기준, sandbox-vs-real-network evidence 기준, Incident Ops 감시/장애대응/주기보고 기준, plan index/TODO reconciliation 기준, spec/design alignment 기준, 사용자 보고를 쉬운 한국어로 먼저 작성하는 기준, AGENTS.md와 linked docs 분리 기준, 필요한 완료팩(UI/배포/보안/데이터/성능/관측성), 적용할 도메인팩을 인터뷰해서 AGENTS.md, docs/WORKFLOW.md, scripts/verify.sh를 이 프로젝트에 맞게 설정해줘. ./scripts/automation-doctor.sh, ./scripts/verify.sh, 확정한 리뷰 강도에 따른 ./scripts/review-gate.sh까지 통과시켜줘. 커밋은 하지 말고 결과만 보고해.

## Post-aiinit request

Use this after `aiinit` has already installed the template:

    프로젝트 초기설정 해줘

## Project Registry

## Finding AI_AUTO Again

If you are in another Ubuntu/WSL terminal and do not remember where AI_AUTO was
cloned, use the global helper:

    AI_AUTO
    AI_AUTO --status

`./scripts/install-global-files.sh` installs an `AI_AUTO` shell function through
`~/.config/ai-lab/AI_AUTO.sh` and sources it from `~/.bashrc`. After reloading
the shell, typing `AI_AUTO` with no arguments moves the current terminal to the
AI_AUTO checkout. Use `AI_AUTO --path` when you only need the path, or
`AI_AUTO --status` to inspect the checkout status.

## Project Registry

New `aiinit` runs register the target repository in:

    ~/.local/state/ai-auto/projects.tsv

Override the registry path with:

    AI_AUTO_PROJECT_REGISTRY_FILE=/path/to/projects.tsv

Projects initialized before registry support can be registered later:

    ai-register
    ai-register /path/to/existing-repo

Remove registry entries for repositories that were deleted or moved:

    ai-register --prune

Use `workspace-scan` from the AI_AUTO checkout or any shell with the helper on
`PATH` to see repositories under `~/workspace` plus registered repositories.
The `INIT` column marks repositories present in the registry. Normal
repositories and linked worktrees are both recognized.

Registry writes use a local lock. On Linux/WSL, `flock` releases the lock when
the process exits, so stale lock deletion is not needed. The default wait is 10
seconds; override with `AI_AUTO_PROJECT_REGISTRY_LOCK_TIMEOUT_SECONDS` only when
needed.

## Template Status Comparison

Use this when checking whether a project has drifted from the current reusable
AI_AUTO template:

    ai-auto-template-status /path/to/project

First review `docs/PATCH_NOTES.md` in the AI_AUTO template or installed project
to understand what changed in each template version.

The command reports the installed template version, current template version,
overall status, per-managed-file states, ownership, and patch policy. It is
status-only and never auto-merges. Generated/runtime files such as `.omx/`
review artifacts are outside the managed-file manifest. Treat `different` as
"customized or outdated" until a human or AI reviews the file in context.
Patch policies mean:

- `update`: template-owned file; a newer template can normally replace or patch
  it after review.
- `review-merge`: hybrid file; preserve project-specific rules and merge only
  applicable template guidance.
- `inspect-only`: project-owned file; report drift, but do not overwrite it.

When the drift should become a queued follow-up for that project, record it
explicitly:

    ai-auto-template-status --record-feedback /path/to/project

This appends a sanitized feedback item with repeat key
`automation-template:update-available` only when drift exists. The helper writes
through AI_AUTO's trusted feedback recorder rather than executing scripts from
the inspected project.

When Codex starts in a project with the optional drift notice installed, it may
print `patch keyword: AI_AUTO 최신 패치 적용해줘`. Typing that keyword in the
project is the short form for the full AI_AUTO template patch workflow: inspect
template status and patch notes, merge only applicable managed-file changes,
preserve project-specific rules, run verification and the review gate, and stop
before commit/push unless explicitly asked.

## Domain Packs

Domain packs are optional reference packs for project-specific onboarding.
`aiinit` copies them into the target repository only as ignored runtime
references under `.omx/domain-packs/`. It does not merge them into project
instructions automatically.

Use `docs/DOMAIN_PACKS.md` for the domain-pack lifecycle, selection, rejection,
and application rules. Generic projects do not need a generic domain pack;
continue with `automation-base` and any applicable completion packs when no
installed domain pack matches.

Use `docs/DOMAIN_PACK_AUTHORING_GUIDE.md` only when creating or changing a
reusable source pack. Project onboarding should normally select, reject, defer,
or apply installed packs rather than authoring new packs.

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
4. Run `ai-auto-template-status` to collect version and per-file status.
5. Propose a small merge plan before editing.
6. Copy only missing automation scripts or docs that do not overwrite project
   rules.
7. Preserve project-specific instructions as the source of truth when they are
   stricter than the reusable template.
8. Run `./scripts/automation-doctor.sh`, the project verification command, and
   `./scripts/review-gate.sh`.

## Notes

- `aiinit` must be run inside a git repository.
- `aiinit /path/to/repo` may be used from outside the target repository.
- `aiinit` runs the installed `./scripts/automation-doctor.sh` after template installation.
- `ai-register` can register older already-initialized projects without
  reinstalling or overwriting automation files.
- `./scripts/automation-doctor.sh` diagnoses automation readiness and suggests repair commands.
- `./scripts/automation-doctor.sh --fix` may apply only safe non-overwriting setup fixes.
- Optional `docs/*_COMPLETION.md` files are onboarding references. Delete the
  packs rejected as non-goals if they would clutter the target project.
- Project-specific agent instructions belong in `AGENTS.md`.
- Project-specific workflow notes belong in `docs/WORKFLOW.md`.
- Project-specific checks belong in `scripts/verify.sh`.
- Do not keep the placeholder `scripts/verify.sh` as a real project gate.
- Commit only after reviewing the generated files and verification results.
