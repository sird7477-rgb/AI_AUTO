# New Project Automation Guide

AI_AUTO is a globally-installed tool that operates ON a project directory. A
project repo carries ZERO committed framework files. This guide explains how a
project adopts the global workflow.

## Setup

From inside the target git repository:

    ai-auto setup

Or against another directory:

    ai-auto setup /path/to/target-repo

`ai-auto setup` is one idempotent command. It:

- installs thin `pre-commit`/`post-commit` hook shims with the engine path baked
  in, so commits run the gate from the global engine;
- adds `.omx/` to the target repository's local `.git/info/exclude`;
- detects the project domain (advisory, via `ai-project-profile`);
- de-pollutes any framework files left from the old copy model: a tracked file
  byte-identical to the global pristine is `git rm`'d (staged, not committed);
  a retired vendored file the engine no longer ships (e.g. `docs/PATCH_NOTES.md`,
  `AI_AUTO_TEMPLATE_VERSION`) is recognized by its content marker and also `git rm`'d;
  a modified or symlinked one is LEFT and REPORTED.

It never vendors framework files, never auto-commits, and aborts without changes
if run against the engine repo itself or on a tree with staged non-deletions.
A pristine `scripts/verify.sh` is removed; a customized one is kept and should be
converted by hand into `scripts/verify-project.sh` (the optional project test
hook the gate runs).

After `ai-auto setup`, ask the AI:

    프로젝트 초기설정 해줘

This starts the `docs/INTERVIEW_PLAN_LAYER.md` onboarding interview before real
work begins. Keep questions narrow, inspect local evidence first, map each answer
into the project baseline, and track ambiguity instead of hiding assumptions.
Capture:

- project purpose and non-goals
- users, final deliverable, and assumptions that could not be confirmed from
  local files
- review intensity: `lightweight`, `standard`, or `strict`
- whether sanitized failure patterns and improvement ideas may be recorded in
  `.omx/feedback/queue.jsonl`
- recurring approval/permission friction to handle with narrow approved command
  prefixes or repo helpers, without bypassing destructive or credentialed
  approvals
- whether warm Claude/Gemini advisory sessions may be used for local iteration;
  they are advisory only and never replace stateless `review-gate` for commit
  candidates
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
- guidance context budget: what belongs in the project `AGENTS.md` overlay
  versus linked docs
- AI automation hardening: use `docs/AI_AUTOMATION_TREND_HARDENING.md` when
  agent identity, tool permissions, revocation, local automation observability,
  or recurring trend research are in scope
- selected and rejected completion packs from `docs/*_COMPLETION.md`
- whether a domain pack applies, such as the Odoo pack for Odoo projects
- stack and runtime commands
- allowed and forbidden change types
- required verification commands
- smoke checks that prove the final result works
- completion checks from selected completion packs
- project-specific docs or domain constraints

Project-owned files are limited to OPTIONAL overlays:

    AGENTS.md                 # thin project overlay; the engine reads the
                              # global base alongside it (no overlay = base only)
    scripts/verify-project.sh # optional real project tests the gate runs

The engine's `docs/*`, `scripts/*`, and base `AGENTS.md` live in the global
checkout and are never copied into the project.

Run the gate from the global engine (or let the installed hooks run it):

    ai-auto doctor    # automation-doctor.sh --project
    ai-auto verify    # verify.sh
    ai-auto gate      # review-gate.sh

## Codex setup request

Use this request when asking Codex to onboard a project:

    이 프로젝트를 전역 AI_AUTO 워크플로에 연결해줘.

    절차:
    1. 현재 경로와 git 상태를 확인해.
    2. ai-auto setup을 실행해 (훅 심 설치 + .omx ignore + 잔존 프레임워크 파일 정리).
    3. 기존 README/docs/package/script를 먼저 읽고, 프로젝트 목적, 사용자, 최종 산출물,
       non-goal, 스택, 완료 기준, 금지 범위를 인터뷰해.
    4. 리뷰 강도(lightweight/standard/strict, 기본 standard), 실패 패턴 기록 여부,
       승인 마찰 관리, 서브에이전트 사용 기준, resource-aware parallelism, 플랜/인터뷰
       강도(none/light/standard/deep), 운영 준비 fail-closed 기준,
       sandbox-vs-real-network evidence, Incident Ops 감시/보고 기준,
       plan index/TODO reconciliation, spec/design alignment, 쉬운 한국어 보고 기준,
       AGENTS.md 오버레이와 linked docs 분리 기준을 확정해.
    5. docs/*_COMPLETION.md 중 필요한 완료팩(UI/배포/보안/데이터/성능/관측성)과
       적용할 도메인팩(ai-domain-pack)을 확정해.
    6. 인터뷰 결과를 프로젝트 소유 파일에만 반영해: 필요하면 AGENTS.md 오버레이와
       scripts/verify-project.sh를 작성/수정해. (docs/*·scripts/*·기반 AGENTS.md는
       전역 엔진 소유라 프로젝트에 복사하지 않아.)
    7. ai-auto doctor, ai-auto verify, 확정한 리뷰 강도에 맞춘 ai-auto gate를 실행해.
    8. 커밋은 하지 말고 결과만 보고해.

    완료 보고에는 변경 파일, ai-auto setup 결과(정리/유지 파일), 인터뷰에서 확정한
    운영 지침, verify-project.sh에 넣은 검증 기준, verify/gate 결과, Claude 리뷰 요약,
    Gemini skip 여부, 남은 warning, 커밋하지 않았다는 확인을 포함해.

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

The managed shell integration also adds two local project-list shortcuts:
`jwlist` lists project folders directly under
`/mnt/z/JSJEON/Project_JW`, and `sirdlist` lists project folders
directly under `/mnt/z/JSJEON/Project_SirD`. If your JW projects live under
an extra grouping folder such as `Project_JW/99. odoo`, set
`AI_AUTO_JW_PROJECT_ROOT` to that folder. The folders do not need to be git
repositories or AI_AUTO-adopted projects. Each command prompts for a number:
choose `0` to enter the currently displayed folder, or choose a subfolder to
drill down through grouped project folders. When a selected folder contains
common project markers such as `.git`, `AGENTS.md`, `package.json`,
`pyproject.toml`, `requirements.txt`, `docker-compose.yml`, or
`scripts/verify-project.sh`, the command enters that folder instead of drilling
into internal directories. Override the roots with `AI_AUTO_JW_PROJECT_ROOT` or
`AI_AUTO_SIRD_PROJECT_ROOT` only for a different local machine layout.

Bare `tmux` is convenient too: typing `tmux` with no arguments creates a new
session named with the first available number, starting from `1`. Normal tmux
commands such as `tmux ls` and `tmux attach -t 1` still pass through unchanged.

For long interactive Codex work, AI_AUTO can also install an opt-in tmux
auto-entry wrapper:

    ./scripts/install-global-files.sh --install-codex-tmux-auto-entry

After that, normal interactive `codex` calls outside tmux attach to a stable
project-scoped tmux session. The wrapper stays out of the way for scripts,
pipes, redirects, and calls already inside tmux. Use
`AI_AUTO_CODEX_TMUX_AUTO=0 codex` when direct execution is needed. For the
multi-runtime wrapper installed with `--install-ai-tmux-auto-entry`, use
`AI_AUTO_TMUX_AUTO=0` to bypass all managed AI wrappers or
`AI_AUTO_CLAUDE_TMUX_AUTO=0` / `AI_AUTO_AGY_TMUX_AUTO=0` for one runtime. The
wrapper also best-effort raises the runtime `nofile` soft limit; override the
target with `AI_AUTO_NOFILE_LIMIT` if a local shell needs a different value.
Re-running the same runtime command for a project with an existing tmux session
starts the next numbered session instead of attaching to the already-open one.
Different runtimes in the same project also use separate session names, so
`claude` does not attach to a `codex` session.

## Project Registry

`ai-auto setup` does not register the project. Registration is a separate,
optional convenience for discovery and feedback collection. Register a project
in:

    ~/.local/state/ai-auto/projects.tsv

with:

    ai-register
    ai-register /path/to/existing-repo

Override the registry path with:

    AI_AUTO_PROJECT_REGISTRY_FILE=/path/to/projects.tsv

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

## Domain Packs

Domain packs are optional reference packs for project-specific onboarding. They
are NOT auto-copied at setup. Install or update a pack into the project's ignored
runtime references under `.omx/domain-packs/` with:

    ai-domain-pack status            # read-only state
    ai-domain-pack refresh --apply   # install/update clean managed copies only

`ai-domain-pack` never merges pack text into project files. Use
`docs/DOMAIN_PACKS.md` for the domain-pack lifecycle, selection, rejection, and
application rules. Generic projects do not need a generic domain pack; continue
with the AI_AUTO baseline and any applicable completion packs when no installed
domain pack matches.

Use `docs/DOMAIN_PACK_AUTHORING_GUIDE.md` only when creating or changing a
reusable source pack. Project onboarding should normally select, reject, defer,
or apply installed packs rather than authoring new packs.

Source packs in this repository:

    templates/domain-packs/browser-macro/
    templates/domain-packs/odoo/

During onboarding, the AI should ask whether the project matches an available
pack. In the target repository, read the installed copy from `.omx/domain-packs/`.
If a pack applies, use it as source material for an `AGENTS.md` overlay and
`scripts/verify-project.sh`. Apply only the parts that match the actual project.
Keep unrelated domain guidance out of generic projects.

The onboarding interview should explicitly record:

- selected domain pack names
- rejected domain pack names
- project-specific rules that must stay outside the reusable domain pack

## Existing Project Adoption

`ai-auto setup` is conservative: it never overwrites or deletes customized work.
A modified framework file is left in place and reported, never removed. Run it on
an existing project to install the hook shims, ignore `.omx/`, and clear out only
byte-identical leftover copies from the old vendoring model.

For an existing or already-advanced project, ask the AI:

    기존 프로젝트에 전역 AI_AUTO 워크플로를 도입해줘.
    기존 AGENTS.md, docs, 검증 스크립트는 덮어쓰지 말고 먼저 분석한 뒤
    필요한 오버레이와 지침만 제안/반영해줘.

The AI should preserve existing project instructions and verification behavior,
then add only the missing overlay or guidance needed for the workflow.

Recommended adoption flow:

1. Run `ai-auto setup` and review the removed/kept report.
2. Read the existing project instructions and verification scripts.
3. List what the project already covers and compare against the AI_AUTO baseline.
4. Propose a small plan before editing.
5. Add only a thin `AGENTS.md` overlay and/or `scripts/verify-project.sh` as
   needed; do not re-vendor engine docs or scripts.
6. Preserve project-specific instructions as the source of truth when they are
   stricter than the AI_AUTO baseline.
7. Run `ai-auto doctor`, `ai-auto verify`, and `ai-auto gate`.

## Notes

- `ai-auto setup` must be run inside a git repository.
- `ai-auto setup /path/to/repo` may be used from outside the target repository.
- `ai-auto setup` is idempotent; re-running re-asserts the hook shims and
  `.omx/` ignore.
- `ai-register` can register already-adopted projects for discovery without
  touching project files.
- `ai-auto doctor` (automation-doctor.sh --project) diagnoses the project and
  warns loudly when `scripts/verify-project.sh` is absent, so a missing real
  test is visible, never a silent green.
- Optional `docs/*_COMPLETION.md` files are global onboarding references; do not
  copy them into the project.
- Project-specific agent instructions belong in the optional `AGENTS.md` overlay.
- Project-specific checks belong in `scripts/verify-project.sh`.
- Commit only after reviewing the staged changes and verification results.
</content>
</invoke>
