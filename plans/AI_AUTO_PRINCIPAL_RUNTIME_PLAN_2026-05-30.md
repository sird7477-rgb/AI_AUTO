# Claude/Gemini 주관자 런타임 전환 계획

## 상태

- State: execution-slice-applied
- Date: 2026-05-30
- Last updated: 2026-05-31
- Execution approval: granted by follow-up user instruction for Ralph execution
- Completion condition: verification plus review gate; unanimous external review
  remains blocked until disabled Claude reviewer is reset
- Applied slice:
  - principal runtime contract helper and docs
  - review-gate reviewer rotation for `codex`, `claude`, and `gemini`
  - fail-closed external-principal evidence marker validation
  - Docker config guard automation for WSL Docker Desktop credential-helper issues
- Requirement correction:
  - 의도는 외부 AI를 격리된 보조 executor로 붙이는 것이 아니다.
  - 의도는 현재 GPT/Codex가 맡는 주관자 슬롯을 Claude 또는 Gemini/agy로
    대체 가능하게 만드는 것이다.
  - 주관자가 바뀌면 나머지 런타임은 reviewer lane으로 배치한다.
- External consultation:
  - Gemini/agy: `approve_with_notes` on 2026-05-30. 최초 계획의 sandbox,
    lock, stale worktree, headless/TTY probe 권고는 delegated executor lane에는
    유효하지만, primary principal 전환의 기본 경로는 아니다.
  - Claude: `approve_with_notes` on 2026-05-30 after retry. 최초 계획의
    step decomposition, execution-mode vocabulary alignment, redaction, path
    containment, egress, gitdir lock, kill-switch 권고는 delegated executor lane에는
    유효하지만, primary principal 전환의 기본 경로는 아니다.

## 문제 정의

현재 AI_AUTO/OMX 구조는 Codex/GPT 주관자 실행을 기본 전제로 한다.

- `AGENTS.md`와 docs는 active leader를 runtime-selected라고 표현하지만, 실제
  CLI 진입, tool 사용, hook/state 해석, 완료 보고는 Codex 세션이 소유한다.
- `scripts/ai-runtime-adapter.sh`는 Claude/Gemini를 `review`, `analyze`,
  `plan` 같은 read-only 용도로만 실행한다.
- `docs/MULTI_AI_COLLABORATION.md`는 Claude/Gemini를 독립 reviewer로 둔다.
- 따라서 현재 구조는 "Claude/Gemini가 리뷰어로 참여"는 가능하지만,
  "Claude/Gemini가 주관자가 되고 Codex/GPT가 리뷰어로 내려가는 운용"은 아니다.

핵심 결함은 권한 부족이 아니라 **주관자 슬롯이 런타임 독립적으로 추상화되어
있지 않다**는 점이다.

## 목표

AI_AUTO/OMX의 주관자 슬롯을 런타임 독립적으로 정의한다.

```text
AI_AUTO principal runtime
  one of: codex | claude | gemini
  owns repo worktree edits, command execution, plan execution, final local report
  receives the same repository authority regardless of provider

reviewer runtime set
  the remaining eligible runtimes
  review the active principal's work through review-gate

OMX state/control plane
  records active principal identity, reviewer assignment, artifacts, gates
  does not silently reduce authority because principal != codex
```

주관자 권한 원칙:

- Codex가 주관자일 때 가능한 repo-local 파일 수정과 검증은 Claude/Gemini
  주관자에게도 같은 수준으로 허용한다.
- 격리 worktree는 주관자 교체의 기본 조건이 아니다.
- worktree/sandbox는 주관자가 다시 하위 executor에게 위험 작업을 위임할 때 쓰는
  선택적 안전장치다.

## 비목표

- provider별로 repo-local 작업 권한을 다르게 주지 않는다.
- Claude/Gemini 주관자에게 더 낮은 권한을 주기 위해 항상 격리 worktree를 강제하지 않는다.
- reviewer와 principal을 같은 작업에서 동시에 같은 역할로 쓰지 않는다.
- commit/push/deploy/credentialed production 작업까지 자동 위임하지 않는다. 이
  영역은 현재 Codex 주관자에게도 사용자 승인과 별도 게이트가 필요하다.
- 기존 review-gate의 독립 reviewer 의미를 흐리지 않는다.

## 원칙

1. 주관자는 provider가 아니라 active principal role이다.
2. repo-local 작업 권한은 active principal에게 동일하게 적용한다.
3. provider 차이는 권한 차이가 아니라 CLI 연결, hook, artifact, prompt protocol
   차이로 다룬다.
4. 주관자가 `codex`이면 Claude/Gemini가 reviewer가 된다.
5. 주관자가 `claude`이면 Gemini와 Codex가 reviewer가 된다.
6. 주관자가 `gemini`이면 Claude와 Codex가 reviewer가 된다.
7. 완료 판정은 항상 active principal의 자기 주장만으로 끝나지 않고, reviewer
   coverage와 Ralph unanimous audit를 통과해야 한다.

## RALPLAN-DR 요약

### Principles

- 주관자 슬롯과 reviewer 슬롯을 분리한다.
- 런타임별 권한 차이를 만들지 않는다.
- 기성 CLI는 주관자 adapter로 연결하되, AI_AUTO/OMX의 state와 gate는 유지한다.
- worktree broker는 delegated executor 선택지로 보존하되 primary principal
  전환의 기본 설계에서 제외한다.

### Decision Drivers

- 사용자의 원 요구는 "GPT 자리에 Claude/Gemini를 대체 투입"이다.
- 주관자가 바뀌면 나머지 AI가 reviewer가 되어야 한다.
- AI_AUTO는 분산된 별도 프로젝트마다 다른 권한 모델을 갖지 않아야 한다.
- 기존 verify/review-gate/Ralph 완료 조건은 유지해야 한다.

### Viable Options

| Option | 설명 | 장점 | 단점 |
| --- | --- | --- | --- |
| A. wrapper-only | `AI_AUTO_PRINCIPAL=claude|gemini|codex`가 선택한 CLI를 직접 실행한다. | 가장 단순하다. | hooks/state/review assignment가 약하다. |
| B. principal runtime adapter | 공통 principal contract를 만들고 Codex/Claude/Gemini CLI를 그 뒤에 연결한다. | 권한 parity와 audit가 명확하다. | adapter 설계와 테스트가 필요하다. |
| C. worktree executor broker | 외부 AI를 격리 executor로 실행하고 diff만 회수한다. | 위임 작업 안전성은 높다. | 사용자의 주관자 교체 요구와 다르다. |

선호안: **B**. `principal runtime adapter`를 만들고, worktree broker는 주관자가
선택적으로 하위 executor를 격리할 때만 사용한다.

## 마이크로 계획

### M0. 요구 정정 기록

- 파일:
  - `plans/AI_AUTO_PRINCIPAL_RUNTIME_PLAN_2026-05-30.md`
  - `docs/AI_RUNTIME_ADAPTERS.md`
  - `docs/AI_MODEL_ROUTING.md`
  - `docs/MULTI_AI_COLLABORATION.md`
- 작업:
  - "external executor"가 아니라 "active principal runtime" 요구였음을 명시한다.
  - 기존 worktree broker 해석을 delegated executor option으로 낮춘다.
- 검증:
  - 문서에서 주관자 교체와 reviewer 배치가 별도 개념으로 드러난다.

### M1. Principal runtime contract 정의

- 새 문서 후보: `docs/AI_PRINCIPAL_RUNTIMES.md`
- 필수 필드:
  - `principal_runtime`: `codex | claude | gemini`
  - `principal_command`
  - `repo_root`
  - `instruction_sources`
  - `allowed_repo_actions`
  - `requires_user_approval_for`
  - `reviewer_runtimes`
  - `artifact_dir`
  - `handoff_protocol`
- 권한 원칙:
  - repo-local edit/test/verify 권한은 주관자 런타임 간 동일하다.
  - commit/push/deploy/credential 작업은 provider와 무관하게 기존 승인 게이트를 따른다.
- 검증:
  - `codex`, `claude`, `gemini` profile이 같은 권한 matrix를 공유한다.

### M2. Active principal 선택 표면 설계

- 후보:
  - `AI_AUTO_PRINCIPAL=codex|claude|gemini`
  - `aiinit --principal claude`
  - `AI_AUTO --principal gemini`
- 작업:
  - 기본값은 `codex`.
  - 프로젝트 전용 지침은 주관자와 무관하게 동일하게 로드한다.
  - 지원하지 않는 runtime이면 fail-closed.
- 검증:
  - 선택된 principal이 `.omx/state/` 또는 실행 manifest에 기록된다.
  - 주관자가 바뀌어도 AGENTS/docs/project rules 로딩 순서가 변하지 않는다.

### M3. Reviewer rotation rule

- 규칙:
  - principal `codex` -> reviewers: `claude`, `gemini`
  - principal `claude` -> reviewers: `gemini`, `codex`
  - principal `gemini` -> reviewers: `claude`, `codex`
- 작업:
  - review-gate가 active principal을 reviewer pool에서 제외한다.
  - 남은 reviewer 중 unavailable runtime은 active principal의 subagent
    substitute가 정규 대체 lane으로 담당한다.
  - substitute가 usable verdict와 direct file inspection을 만들지 못하면
    degraded/pending으로 보고한다.
  - Codex가 reviewer일 때는 Codex fallback이 아니라 독립 reviewer lane으로 명명한다.
- 검증:
  - 같은 runtime이 principal과 reviewer를 동시에 맡지 않는다.
  - reviewer coverage summary가 principal identity를 표시한다.
  - `principal_subagent_substitute`와 `principal_rotation_with_substitute`는
    정상 trust로 통과하고, substitute request_changes는 차단된다.

### M3.5. Ralph completion promotion rule

- 규칙:
  - Ralph 실행 중 요청 범위 안에서 발견한 plan-only, 미승격 규칙,
    문서/도구 괴리, 누락 tool wiring은 같은 루프에서 정규 산출물로
    승격한다.
  - 외부 quota, credential, 명시 권한처럼 즉시 해결 불가능한 hard blocker만
    증거와 함께 남긴다.
- 적용:
  - `AGENTS.md`, template `AGENTS.md`, `docs/WORKFLOW.md`, template
    `docs/WORKFLOW.md`에 정규 규칙으로 승격했다.
- 검증:
  - completion discipline은 review-gate와 verify 완료 전 diff/spec alignment
    확인 대상에 포함한다.

### M4. CLI principal adapter 설계

- Codex:
  - 현재 Codex/OMX 실행 경로를 baseline principal로 기록한다.
- Claude:
  - non-interactive 실행 가능 여부와 interactive/TTY 필요 여부를 probe한다.
  - project root에서 직접 파일 수정 가능한 principal mode를 확인한다.
- Gemini/agy:
  - `agy --prompt` 기반 non-interactive principal 가능 여부를 probe한다.
  - agent/edit mode와 tool approval behavior를 확인한다.
- 검증:
  - 세 runtime 모두 같은 principal contract field를 채운다.
  - CLI가 필요한 기능을 지원하지 않으면 "권한 축소"가 아니라
    `principal_unavailable`로 실패한다.

### M5. OMX state/control plane 연결

- 작업:
  - active principal identity를 session checkpoint, review manifest, completion
    report에 남긴다.
  - OMX skill/hook/state는 principal-neutral하게 동작해야 한다.
  - principal이 Codex가 아니어도 `.omx/state`, `.omx/review-results`,
    `.omx/plans` artifact contract는 동일하다.
- 검증:
  - principal별 dry-run manifest가 같은 schema를 사용한다.
  - hook/state가 Codex-only 문구로 완료 주장을 만들지 않는다.

### M6. 권한 parity 테스트

- 테스트 후보:
  - `tests/test_principal_runtime_contracts.py`
  - `tests/test_review_rotation.py`
- 테스트:
  - `codex`, `claude`, `gemini` principal profile의 repo-local 권한 matrix가 같다.
  - commit/push/deploy/credential 작업은 세 principal 모두 승인 필요로 표시된다.
  - project rules loading은 principal에 따라 달라지지 않는다.
  - unsupported CLI는 principal 권한 축소가 아니라 unavailable로 처리된다.
- 검증:
  - `./scripts/verify.sh`

### M7. 주관자 실행 dry-run

- 작업:
  - 각 principal에 같은 read/edit/test shaped fixture를 제공한다.
  - 실제 repo 파괴 없이 fixture repo에서 파일 수정, test 실행, artifact 작성까지 확인한다.
  - 이 단계의 fixture repo는 테스트용이며, 실제 사용자 repo 작업을 worktree로 강제한다는 뜻이 아니다.
- 검증:
  - principal별 output artifact가 동일 schema를 만족한다.
  - 실패/timeout/auth prompt가 명확한 failure class로 남는다.

### M8. Review-gate 통합

- 작업:
  - review prompt에 active principal identity를 포함한다.
  - reviewer가 active principal의 diff/artifact를 검토하도록 한다.
  - principal runtime의 자기 리뷰는 coverage에 포함하지 않는다.
- 검증:
  - principal `claude`에서 Claude reviewer가 제외된다.
  - principal `gemini`에서 Gemini reviewer가 제외된다.
  - principal `codex`에서 기존 Claude/Gemini reviewer 경로가 유지된다.

### M9. AI_AUTO/aiinit 사용자 표면

- 작업:
  - 신규 프로젝트 등록 또는 AI_AUTO 실행 시 principal 선택 방법을 문서화한다.
  - 기본값은 기존 동작 보존을 위해 Codex.
  - 사용자가 Claude/Gemini 주관자를 선택하면 reviewer rotation도 함께 설명한다.
- 검증:
  - 기존 프로젝트는 설정이 없으면 동작이 바뀌지 않는다.
  - 설정이 있으면 manifest에 principal/reviewer assignment가 표시된다.

### M10. Worktree broker 재분류

- 작업:
  - worktree broker는 primary principal 전환 필수요건에서 제거한다.
  - delegated executor, risky experiment, multi-lane scratch 작업에만 선택적으로 둔다.
- 검증:
  - principal `claude` 또는 `gemini`가 원본 repo-local 작업 권한을 갖는다는 문구와 충돌하지 않는다.
  - worktree 사용 여부는 task policy이지 provider 권한 차이가 아니다.

### M11. External consensus replay

- 작업:
  - 수정된 "principal runtime 전환" 계획을 Claude와 Gemini에 다시 검토시킨다.
  - 질문은 "GPT/Codex 자리에 Claude/Gemini를 대체 투입하는 요구를 만족하는가"로 고정한다.
- 검증:
  - 두 reviewer 모두 `approve` 또는 `approve_with_notes`.
  - notes는 applied/rejected/deferred로 분류한다.

## Ralph unanimous 완료조건

이 계획의 구현은 일반 `proceed_degraded`로 완료 처리하지 않는다. 완료는 아래가
모두 충족될 때만 가능하다.

- Ralph implementation lane: principal runtime contract와 reviewer rotation이 구현됨.
- Ralph verifier lane: `./scripts/verify.sh` 통과.
- Ralph review-gate lane: active principal을 제외한 reviewer들이 검토하고
  `proceed`를 반환.
- Ralph external-consensus lane: Claude와 Gemini/agy가 수정된 요구 해석을 검토하고
  `approve` 또는 `approve_with_notes`를 반환.
- Ralph architect lane: 주관자 권한 parity와 OMX state/control plane 연결 approve.
- Ralph critic lane: "GPT 자리를 Claude/Gemini로 대체" 요구가 acceptance criterion으로
  테스트된다고 approve.
- Ralph integration lane: principal과 reviewer role이 섞이지 않는다고 approve.

만장일치 정의:

```text
approve = implementation + verifier + review-gate + architect + critic + integration
no request_changes
no blocked
no degraded completion claim
no principal/reviewer role collision
```

## ADR

### Decision

AI_AUTO/OMX는 Claude/Gemini를 격리된 보조 executor로만 붙이는 구조가 아니라,
`codex | claude | gemini` 중 하나를 active principal runtime으로 선택할 수 있는
principal runtime contract를 설계한다.

### Drivers

- 원 요구사항 복원: GPT/Codex 주관자 자리를 Claude/Gemini로 대체 가능해야 한다.
- 권한 parity: repo-local 작업 권한은 주관자 runtime과 무관하게 같아야 한다.
- 검증성: 주관자가 바뀌면 나머지 runtime이 reviewer로 배치되어야 한다.
- 호환성: 기존 Codex 기본 경로와 review-gate는 깨지지 않아야 한다.

### Alternatives considered

- worktree executor broker를 기본 경로로 사용: 사용자의 주관자 대체 요구와 다르고,
  provider별 권한 차이를 만들어 보류.
- Claude/Gemini를 reviewer로만 유지: 원 요구를 충족하지 못해 보류.
- 단순 wrapper-only: 빠르지만 OMX state/review assignment가 약해 보류.

### Why chosen

principal runtime contract는 주관자 권한을 provider별로 낮추지 않으면서도,
OMX artifact, review-gate, Ralph 완료조건을 그대로 유지할 수 있다.

### Consequences

- 구현은 단순 reviewer adapter 확장보다 크다.
- Claude/Gemini CLI의 실제 principal mode 지원 여부를 probe해야 한다.
- Codex-only hook/state 문구를 principal-neutral하게 정리해야 한다.
- delegated executor 격리 설계는 별도 선택지로 남는다.

### Follow-ups

- `docs/AI_PRINCIPAL_RUNTIMES.md` PRD 작성.
- principal runtime profile schema 작성.
- Claude/Gemini/Codex principal probe fixture 작성.
- reviewer rotation test 작성.
- AI_AUTO/aiinit principal 선택 표면 설계.
- 수정된 계획으로 Claude/Gemini consensus replay.

## 실행 게이트와 중단 조건

- Claude/Gemini CLI가 repo root에서 principal로 실행될 수 없다는 local evidence가 나오면 해당 runtime은 `principal_unavailable`로 둔다.
- principal 전환이 provider별 권한 축소를 요구하면 설계를 중단하고 다시 검토한다.
- active principal과 reviewer가 같은 runtime으로 중복 배치되면 실패로 처리한다.
- `AI_AUTO_PRINCIPAL=claude|gemini`만으로는 self-review를 스킵하지 않는다.
  실제 principal launcher가 `.omx/state/principal-runtime/current.env`에
  `principal_runtime=<runtime>`와 `execution_mode=principal` marker를 남긴
  경우에만 reviewer rotation을 허용한다.
- 추가 AI_AUTO/aiinit 진입점 자동화는 별도 PRD와 test spec으로 확장한다.
