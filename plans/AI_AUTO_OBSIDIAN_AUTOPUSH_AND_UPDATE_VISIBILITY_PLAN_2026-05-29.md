# AI_AUTO Obsidian Auto-Push And Update Visibility Plan

## 목적

이 문서는 비활성 TODO `ST-P1-08`과 `ST-P1-09`를 실행 가능한 승인
플랜으로 구체화한다. 두 항목은 모두 "AI 호출 시 사용자가 놓치기 쉬운
운영 상태"를 다루지만, 권한 경계가 다르다.

- `ST-P1-08`: AI_AUTO 본진에서 AI를 호출할 때, AI_AUTO 및 등록 프로젝트의
  검증된 지식 산출물 초안이 Obsidian으로 밀리지 않고 남아 있으면 자동
  푸시 후보로 처리한다.
- `ST-P1-09`: 등록 프로젝트에서 AI를 호출할 때, 해당 프로젝트의 AI_AUTO
  템플릿 업데이트 상태를 사용자가 더 분명하게 인식하게 한다.

두 항목은 2026-05-29 non-active promotion Ralph pass에서
`complete_contract`로 승격되었다. 승격 근거는
`scripts/self_demo_contracts.py`의 `obsidian_autopush_policy` 및
`update_visibility_policy`와 `tests/test_self_demo_contracts.py`의 대응
테스트다. 실제 Obsidian push 실행이나 startup shell wiring은 여전히 이
문서의 권한 경계와 별도 사용자 승인 조건을 따른다.

## 현재 근거

### ST-P1-08

현재 지식격납 표면은 다음 기능을 이미 갖고 있다.

- `tools/knowledge-collect`
  - 현재 repo, 명시 `--project`, `--include-registry`, `--include-workspace`
    기준으로 `.omx/knowledge/drafts/*.md`를 수집한다.
  - `scripts/knowledge-notes.py validate`로 초안을 검증한다.
  - `--vault-dir <vault>/AI_AUTO --push`가 있을 때만 vault에 복사한다.
  - `sync_class`가 `external_private_vault` 또는 `shareable_summary`가 아니면
    푸시를 거절한다.
  - `local_private`는 `--allow-local-private`가 있어야만 허용한다.
  - `.omx` vault, symlink draft/vault escape를 거절한다.
  - 푸시 후 vault validate/index를 수행한다.
- `docs/OBSIDIAN_INTEGRATION.md`
  - Obsidian은 승인, 검증, 리뷰, 커밋, 큐, 런타임 제어 권한이 없다고
    명시한다.
  - vault 경로는 명시 설정이어야 하며 mounted drive 전체 검색은 금지한다.
  - `/mnt/z` 쓰기는 Codex writable-root 또는 승인된 write command가
    필요하다고 명시한다.

따라서 8번의 핵심은 새 저장소/동기화 체계를 만드는 것이 아니라,
기존 `knowledge-collect`를 AI_AUTO 본진 호출 시점에 안전하게 호출할 수
있는 조건, 표시, opt-in, 실패 처리를 정의하는 것이다.

### ST-P1-09

현재 업데이트 가시화 표면은 다음 기능을 이미 갖고 있다.

- `tools/ai-auto-template-status`
  - 프로젝트의 설치 템플릿 버전, 현재 템플릿 버전, managed file 상태,
    ownership, patch policy를 읽기 전용으로 보고한다.
  - `--record-feedback`는 drift가 있을 때만 sanitized feedback을 기록하지만,
    일반 notice에서는 자동 실행 대상이 아니다.
- `scripts/install-global-files.sh --install-codex-drift-notice`
  - `codex` shell function을 opt-in으로 설치해 Codex 시작 전에 읽기 전용
    템플릿 업데이트 notice를 출력한다.
  - drift가 있으면 `AI_AUTO 최신 패치 적용해줘` 키워드를 보여준다.
  - 실제 Codex binary 호출은 계속 통과시킨다.
- `docs/GLOBAL_TOOLS.md`
  - drift notice가 정상 전역 설치에는 포함되지 않는 opt-in임을 명시한다.
  - notice는 패치 적용이 아니라 패치 요청 키워드 안내로 제한된다.

따라서 9번의 핵심은 이미 있는 opt-in notice를 더 식별 가능하고 낮은
노이즈로 만드는 것이며, AI 호출 자체를 막거나 자동 패치를 실행해서는 안
된다.

## 공통 설계 원칙

1. AI_AUTO가 권한의 주체다.
   Obsidian note, drift notice, feedback queue는 근거 또는 알림일 뿐
   승인/검증/완료 권한을 갖지 않는다.

2. 쓰기 동작은 명시 경계 안에서만 한다.
   vault push는 설정된 vault path와 기존 `knowledge-collect` 안전검사를
   통과해야 한다. `/mnt/z` 쓰기 권한 문제는 sandbox 경계로 보고 승인 또는
   writable-root 설정이 필요하다.

3. AI 호출은 막지 않는다.
   자동 푸시 실패, vault 미설정, 업데이트 drift 감지는 기본적으로
   경고/notice이다. 사용자가 명시한 패치, 커밋, 푸시 승인 없이 프로젝트
   파일을 수정하지 않는다.

4. 루틴 작업은 조용해야 한다.
   current 상태, pending 없음, opt-out 상태에서는 한 줄 이하 또는 무출력
   경로를 유지한다. 눈에 띄는 출력은 사용자가 action을 취할 수 있는 경우에만
   사용한다.

5. 테스트 가능한 shell 표면으로 제한한다.
   구현은 shell wrapper와 Python helper의 fixture 테스트로 검증 가능해야
   한다. daemon, background service, Obsidian API, browser/session 자동화는
   도입하지 않는다.

## ST-P1-08 상세 플랜: Obsidian Pending-Output Auto-Push

### 목표 동작

AI_AUTO 본진 checkout에서 AI 호출이 시작될 때 다음 조건을 모두 만족하면
pending 지식 산출물을 자동 푸시 후보로 처리한다.

- 현재 git root가 AI_AUTO 본진이다.
- vault 경로가 명시 설정되어 있다.
- 현재 repo 또는 AI_AUTO registry의 등록 프로젝트에 검증 가능한
  `.omx/knowledge/drafts/*.md`가 있다.
- note의 `sync_class`가 vault push 정책에 맞다.
- 사용자가 기능을 끄지 않았다.

기본 정책은 "자동 감지 + 짧은 요약 + 설정된 경우 푸시"이다. vault 경로가
없거나 쓰기 권한이 없으면 AI 호출을 계속 진행시키고, 사용자가 재현 가능한
명령을 볼 수 있게 한다.

### 활성화 조건

필수 조건:

- `git rev-parse --show-toplevel` 결과가 AI_AUTO 본진 경로와 같다.
- `AI_AUTO_KNOWLEDGE_AUTOPUSH`가 `0`이 아니다.
- vault 경로가 다음 중 하나로 명시되어 있다.
  - `AI_AUTO_OBSIDIAN_VAULT_DIR`
  - `config/ai-auto-local.json`의 vault 설정 필드
  - 기존에 문서화된 local config surface가 있다면 그 surface
- registry scan은 `--include-registry`로만 수행한다.
- detached HEAD, active rebase, linked worktree, 또는 submodule 내부에서는
  git root 판정이 불명확하면 auto-push를 실행하지 않고 warning-only로
  종료한다.

비활성 조건:

- 현재 위치가 일반 프로젝트 checkout이다.
- vault 경로가 없다.
- draft가 없다.
- draft가 있지만 모두 invalid이다.
- draft가 모두 이미 vault에 동일 hash로 존재한다.
- `AI_AUTO_KNOWLEDGE_AUTOPUSH=0`이다.
- 프로젝트 또는 note가 auto-push 제외 대상으로 표시되어 있다.

제외 정책:

- 전역 비활성: `AI_AUTO_KNOWLEDGE_AUTOPUSH=0`
- 프로젝트 단위 제외: repo-local 설정 파일 또는 registry metadata에
  `knowledge_autopush=false` 같은 명시 필드를 둔다. V1에서 별도 metadata
  surface가 없으면 "전역 비활성 + 수동 push"만 허용하고 임의 파일 검색은
  하지 않는다.
- note 단위 제외: frontmatter `autopush: false`를 후보로 둔다. 단,
  `sync_class: local_private`는 이미 더 강한 차단 조건이므로 기본 제외로
  취급한다.
- malformed frontmatter는 parser crash로 이어지면 안 된다. auto-push
  preflight에서는 해당 note를 skipped/warning으로 처리하고 주 AI 호출은
  계속한다.
- 제외된 note/project는 skipped count와 이유에 포함하지만 failure로 보지
  않는다.

### 출력 정책

무출력 또는 1줄 출력:

- pending 없음
- vault 미설정
- opt-out

눈에 띄는 summary 출력:

- push 후보가 1개 이상 있다.
- push가 실행되어 `created` 또는 `updated`가 발생했다.
- invalid note 또는 sync_class 차단이 발생했다.
- vault write 권한 실패가 발생했다.

권장 출력 필드:

- 프로젝트 수
- note 수
- created/updated/unchanged/skipped count
- 차단 이유 상위 3개
- vault 경로 basename 또는 안전하게 축약된 경로
- 다음 조치 명령

### 구현 단계

1. `knowledge-collect`에 machine-readable dry-run summary를 추가한다.
   - 예: `--summary-json`
   - 반환 필드: `repo_count`, `valid_count`, `invalid_count`,
     `pushable_count`, `blocked_sync_class_count`, `unchanged_count`,
     `would_create_count`, `would_update_count`
   - `--push` 없이도 vault와 비교해 `would_create/update/unchanged`를
     계산할 수 있어야 한다.

2. AI_AUTO 본진용 auto-push wrapper를 추가한다.
   - 후보 이름: `tools/ai-auto-knowledge-autopush`
   - 역할: 환경/설정 확인, `knowledge-collect --include-registry` dry-run,
     조건 충족 시 push 실행, 결과 summary 출력
   - vault 미설정 또는 권한 실패 시 exit 0 경고로 끝낸다.

3. AI 호출 전 hook surface를 좁게 연결한다.
   - 기존 `codex` drift notice function 또는 AI_AUTO shell integration에
     "AI_AUTO 본진일 때만" 호출하는 preflight를 붙인다.
   - 프로젝트 checkout에서는 8번 auto-push를 실행하지 않는다.
   - 장기 실행 daemon이나 background push는 만들지 않는다.

4. 설정/문서를 갱신한다.
   - `docs/OBSIDIAN_INTEGRATION.md`: auto-push 조건, opt-out, vault 설정,
     failure mode, 권한 경계를 추가한다.
   - `docs/GLOBAL_TOOLS.md`: 전역 shell integration이 어떤 경우
     knowledge preflight를 실행하는지 추가한다.

5. 필요 시 template surface를 갱신한다.
   - `templates/automation-base/`에 영향을 주면 반드시
     `AI_AUTO_TEMPLATE_VERSION`과 `docs/PATCH_NOTES.md`를 갱신한다.

### 주변 모듈 관계

| Module | Relationship | Coupling Risk | Plan Boundary |
| --- | --- | --- | --- |
| `tools/knowledge-collect` | 기존 수집, 검증, push, vault index 경로. | auto-push 요구가 수동 push semantics를 깨뜨릴 수 있다. | 기존 수동 `--push` 동작을 유지하고 summary/dry-run만 확장한다. |
| `scripts/knowledge-notes.py` | note validate/index의 권위 있는 helper. | auto-push가 validator를 우회하면 vault 품질이 깨진다. | 모든 push 후보는 이 helper validate를 통과해야 한다. |
| `scripts/capture-knowledge-drafts.py` | review-gate 산출물을 local draft로 만드는 경로. | capture와 push가 같은 호출에서 섞이면 원인 추적이 어려워진다. | capture는 별도 단계로 유지하고 auto-push는 existing draft만 처리한다. |
| `tools/ai-register` / registry file | 등록 프로젝트 discovery. | workspace crawl이 느려지거나 범위를 넓힐 수 있다. | auto-push는 registry와 현재 repo만 사용하고 `--include-workspace`는 쓰지 않는다. |
| `scripts/install-global-files.sh` | shell integration 설치 표면. | preflight가 모든 Codex 호출에 무거운 비용을 만들 수 있다. | AI_AUTO 본진에서만 knowledge preflight를 붙이고 timeout을 둔다. |
| `docs/OBSIDIAN_INTEGRATION.md` | 권한/보안/운영 기준. | vault note가 승인/검증 권한처럼 오해될 수 있다. | 문서에 non-authority와 failure mode를 반복 명시한다. |
| `/mnt/z` vault path | 실제 외부 SSD vault 가능 경로. | sandbox write boundary와 실제 디스크 장애를 혼동할 수 있다. | 승인된 write command 또는 writable-root 설정 없이는 write 실패를 warning으로 처리한다. |

### Micro Work Units

| Unit | Target | Change | Surrounding Checks | Tests | Rollback |
| --- | --- | --- | --- | --- | --- |
| 8.1 | `knowledge-collect` summary | Add `--summary-json` or equivalent dry-run machine summary. | Must use existing validation and repo discovery. | Valid/invalid/blocked/unchanged counts. | Remove summary flag; manual table output remains. |
| 8.2 | vault comparison | Compute `would_create`, `would_update`, and `unchanged` without copying. | Must reuse note hash behavior. | Same-hash unchanged, changed target requires force/policy. | Disable vault comparison in dry-run. |
| 8.3 | registry scope | Limit auto-push discovery to current repo plus `--include-registry`. | Avoid `--include-workspace` and mounted-drive scans. | Registered project fixture included; workspace-only repo excluded. | Fall back to current repo only. |
| 8.4 | complex git state | Skip safely on detached HEAD, active rebase, linked worktree ambiguity, or submodule root ambiguity. | Must not false-match AI_AUTO home path. | Detached/submodule fixtures warn and skip. | Only allow exact normal git root. |
| 8.5 | latency budget | Add preflight timeout target. Recommended dry-run budget: 2 seconds; hard timeout: 5 seconds. | Timeout must not kill user AI call. | Slow helper fixture returns warning and exit 0. | Disable preflight on timeout. |
| 8.6 | wrapper | Add narrow AI_AUTO-home auto-push wrapper. | Must detect AI_AUTO home checkout and vault config. | Home repo runs; project repo skips. | Remove shell integration call. |
| 8.7 | write idempotency | Ensure failed push leaves no lock/temp artifacts and manual push still works. | Prefer direct copy semantics already used by `knowledge-collect`. | Simulated write failure followed by manual push fixture. | Keep auto-push dry-run only. |
| 8.8 | sync class guard | Preserve `local_private` and disallowed `sync_class` blocking. | No new broad allow-list. | `local_private` blocked without allow flag. | Reuse existing push guard only. |
| 8.9 | exclusion policy | Support explicit global, project, and note-level exclusion without broad discovery. | Must not create a hidden allow/deny authority outside config/frontmatter. | Project excluded, `autopush: false`, malformed frontmatter, and `local_private` skipped fixtures. | Keep only global opt-out. |
| 8.10 | post-push evidence | Run validate/index after successful push and summarize counts. | Do not claim Obsidian as completion authority. | Validate/index called once after created/updated. | Report push only, no auto-index. |
| 8.11 | docs | Document opt-out, vault config, timeout, warning-only failure. | Avoid expanding Obsidian authority. | Doc references and verify. | Revert docs. |

### 테스트 계획

fixture 기반 테스트:

- vault 미설정이면 push를 하지 않고 AI 호출을 막지 않는다.
- `AI_AUTO_KNOWLEDGE_AUTOPUSH=0`이면 검사/푸시를 건너뛴다.
- 현재 repo가 AI_AUTO 본진이 아니면 auto-push를 실행하지 않는다.
- registry에 등록된 프로젝트의 valid draft가 summary에 포함된다.
- 명시 제외된 프로젝트와 `autopush: false` note는 skipped로 집계되고 push되지
  않는다.
- invalid draft는 skipped로 집계되고 push되지 않는다.
- `local_private` note는 `--allow-local-private` 없이는 차단된다.
- `.omx` vault path는 차단된다.
- symlink draft/vault escape는 차단된다.
- 동일 hash note는 `unchanged`로 보고되고 중복 생성하지 않는다.
- vault write 실패는 warning으로 보고하고 AI 호출은 계속된다.
- push 후 validate/index가 실행된다.
- dry-run scan이 latency budget을 넘으면 warning 후 AI 호출을 계속한다.
- write failure 뒤에 lock/temp artifact 없이 수동 `knowledge-collect --push`가
  재시도 가능하다.
- detached HEAD, active rebase, linked worktree, submodule 내부, malformed
  frontmatter가 auto-push를 crash시키지 않는다.

검증 명령:

- `python3 scripts/todo-report.py --fail-on-active`
- `./scripts/verify.sh`
- commit 후보 제시 전 `./scripts/review-gate.sh`

### 롤백

- shell integration에서 auto-push wrapper 호출을 제거하거나
  `AI_AUTO_KNOWLEDGE_AUTOPUSH=0`으로 끈다.
- `knowledge-collect`의 기존 수동 `--push` 경로는 유지한다.
- vault에 이미 복사된 note는 Obsidian 쪽 수동 정리 대상으로 두고, AI_AUTO가
  자동 삭제하지 않는다.

## ST-P1-09 상세 플랜: Project AI_AUTO Update Visibility

### 목표 동작

등록 프로젝트에서 AI 호출이 시작될 때 해당 프로젝트의 AI_AUTO 템플릿 상태가
업데이트 필요, drift, patch disabled, status error처럼 사용자가 알아야 하는
상태라면 더 분명한 notice를 보여준다.

notice는 다음을 하지 않는다.

- AI 호출 차단
- 자동 패치 적용
- 자동 commit/push
- 자동 `--record-feedback`
- 프로젝트 파일 수정

### 활성화 조건

필수 조건:

- 현재 위치가 git repo이다.
- repo가 AI_AUTO 본진이 아니거나, 본진이어도 일반 프로젝트 drift notice로
  오해될 상황이 아니다.
- `ai-auto-template-status`가 실행 가능하다.
- `AI_AUTO_CODEX_DRIFT_NOTICE`가 `0`이 아니다.
- 사용자가 `--install-codex-drift-notice`를 opt-in 설치했다.

눈에 띄는 notice 조건:

- installed template version이 current template version보다 낮다.
- managed file drift가 있다.
- patch policy가 `review-merge` 또는 `inspect-only`라서 사용자가 수동 검토를
  알아야 한다.
- template patch가 disabled라서 자동 업데이트가 불가능하다.
- status command가 실패했지만 repo가 AI_AUTO template 설치 repo로 보인다.

조용한 조건:

- current 상태이다.
- repo가 AI_AUTO template 대상이 아니다.
- 같은 shell/session에서 같은 repo에 이미 동일 notice를 보여줬다.
- opt-out이다.

### 출력 정책

notice는 stderr에 출력하고, compact와 prominent 두 수준을 둔다.

compact:

```text
[AI_AUTO] update available: installed 0.x < current 0.y. Ask: AI_AUTO 최신 패치 적용해줘
```

prominent:

```text
=== AI_AUTO update notice ===
Project: <repo-name>
Status: update available / drift / manual review needed
Action: AI_AUTO 최신 패치 적용해줘
Check:  ai-auto-template-status
=============================
```

기본은 compact로 시작하되, drift 또는 patch disabled처럼 사용자가 놓치면
실수 가능성이 큰 상태는 prominent를 허용한다.

환경 변수:

- `AI_AUTO_CODEX_DRIFT_NOTICE=0`: 완전 비활성
- `AI_AUTO_CODEX_DRIFT_NOTICE_STYLE=compact|prominent`: 표시 수준
- `AI_AUTO_CODEX_DRIFT_NOTICE_ALWAYS=1`: throttle 무시

### 구현 단계

1. 현재 drift notice parser를 구조화한다.
   - `ai-auto-template-status` 출력에서 status/version/drift/policy를 안정적으로
     읽는 helper를 둔다.
   - 가능하면 status 도구에 `--summary-json`을 추가하고 notice는 JSON을
     소비한다.

2. notice severity를 도입한다.
   - `none`: 출력 없음
   - `info`: compact 1줄
   - `attention`: prominent notice
   - `warning`: command 실패 또는 patch disabled, 하지만 AI 호출은 계속

3. throttle을 명확히 한다.
   - repo root + status fingerprint 기준으로 같은 shell/session 내 중복 출력
     억제
   - fingerprint가 바뀌면 다시 출력
   - `AI_AUTO_CODEX_DRIFT_NOTICE_ALWAYS=1`이면 매번 출력

4. 사용자의 다음 행동을 한 줄로 고정한다.
   - 검사: `ai-auto-template-status`
   - 적용 요청: `AI_AUTO 최신 패치 적용해줘`
   - opt-out: `AI_AUTO_CODEX_DRIFT_NOTICE=0 codex`

5. 문서를 갱신한다.
   - `docs/GLOBAL_TOOLS.md`: notice style, throttle, opt-out, non-blocking
     boundary를 추가한다.
   - `docs/NEW_PROJECT_GUIDE.md` 또는 관련 onboarding 문서가 이 notice를
     언급하고 있다면 최신 문구로 맞춘다.

6. template 영향 여부를 판정한다.
   - `scripts/install-global-files.sh`만 바뀌어도 template copy가 있으면 parity
     테스트에 맞춰 template 파일과 patch note를 갱신해야 할 수 있다.

Latency rule:

- project update visibility runs on ordinary AI startup, so it needs a stricter
  responsiveness target than vault auto-push
- target timeout: 0.5 seconds for the status preflight
- hard timeout: 1 second, after which the notice reports a compact warning or
  stays silent according to current policy, but the AI command must continue

### 주변 모듈 관계

| Module | Relationship | Coupling Risk | Plan Boundary |
| --- | --- | --- | --- |
| `tools/ai-auto-template-status` | update/drift/source-of-truth status provider. | Shell notice parser can drift from status output. | Prefer `--summary-json`; otherwise centralize parser fixture. |
| `scripts/install-global-files.sh` | opt-in `codex` wrapper installation surface. | Wrapper can shadow or break real Codex invocation. | Notice runs before call and always passes through to real Codex. |
| `docs/GLOBAL_TOOLS.md` | User-facing install/opt-out docs. | Notice behavior may be invisible or surprising. | Document opt-in, style, throttle, and non-blocking boundary. |
| `docs/NEW_PROJECT_GUIDE.md` | New project onboarding surface. | Users may not know why notice appears. | Mention only if current guide already covers template status/update workflow. |
| `tools/ai-register` / registry | Defines registered project context. | Notice should not scan unrelated folders. | Use current git repo; registry is optional context, not scan input for every call. |
| `templates/automation-base/*` | Downstream shell/docs propagation. | Template parity failures if global helper behavior is copied. | Update template version/patch notes only when template-owned files change. |

### Micro Work Units

| Unit | Target | Change | Surrounding Checks | Tests | Rollback |
| --- | --- | --- | --- | --- | --- |
| 9.1 | status summary | Add or consume structured `ai-auto-template-status` summary. | Must remain read-only and avoid `--record-feedback`. | Current/outdated/drift/error fixtures. | Fall back to existing text notice. |
| 9.2 | latency timeout | Enforce 0.5 second target and 1 second hard timeout for startup status checks. | Must never delay the real AI command materially. | Slow status fixture exits early and passes through. | Disable status preflight on slow paths. |
| 9.3 | severity map | Map status to `none`, `info`, `attention`, `warning`. | Broken status command is warning, not drift. | Failure fixture says check installation. | Collapse to current update notice. |
| 9.4 | notice renderer | Implement compact/prominent stderr output. | Must include action and check command. | Output snapshot fixtures. | Restore current one-line notice. |
| 9.5 | throttle | Use shell/session-scoped fingerprint. | Must not persist across reboot or leak between repos. | Same repo/status suppressed; changed status prints. | Disable throttle with current behavior. |
| 9.6 | pass-through | Prove real Codex command still runs with original args. | No blocking on status failure. | Fake codex receives args after notice failure. | Remove wrapper notice call. |
| 9.7 | opt-out/style env | Support `AI_AUTO_CODEX_DRIFT_NOTICE=0`, style, always flags. | Existing opt-out remains compatible. | Env fixture coverage. | Keep only existing opt-out. |
| 9.8 | docs/template alignment | Update global docs and template only if touched. | Patch notes/version required for template changes. | Template sync and doc budget. | Revert propagation docs. |

### 테스트 계획

fixture 기반 테스트:

- current 상태는 조용하거나 compact current message만 허용한다.
- outdated version은 update notice와 patch keyword를 출력한다.
- managed file drift는 prominent 또는 attention severity로 출력한다.
- `review-merge`/`inspect-only` 파일 변경은 "수동 검토 필요"로 표시한다.
- template patch disabled는 자동 패치 가능처럼 표시하지 않는다.
- `ai-auto-template-status` 실패는 warning으로 표시하고 Codex 호출은 계속한다.
- status 실패 warning은 drift가 아니라 설치/상태 점검 필요로 안내한다.
- `AI_AUTO_CODEX_DRIFT_NOTICE=0`이면 완전 무출력이다.
- 같은 shell/session에서 같은 fingerprint는 반복 출력하지 않는다.
- `AI_AUTO_CODEX_DRIFT_NOTICE_ALWAYS=1`은 반복 출력한다.
- status preflight가 0.5초 target 또는 1초 hard timeout을 넘으면 AI 호출은
  지연 없이 계속된다.
- AI_AUTO 본진 checkout에서 8번 knowledge preflight와 9번 project update notice가
  서로 중복/충돌하지 않는다.

검증 명령:

- `python3 scripts/todo-report.py --fail-on-active`
- `./scripts/verify.sh`
- commit 후보 제시 전 `./scripts/review-gate.sh`

### 롤백

- `--install-codex-drift-notice` opt-in wrapper를 재설치하지 않거나 shell
  function에서 notice 호출을 제거한다.
- 사용자 단위로 `AI_AUTO_CODEX_DRIFT_NOTICE=0`을 사용한다.
- `ai-auto-template-status`의 read-only 동작은 유지한다.

## Ralph Work Groups And Review Loop

Ralph execution for `ST-P1-08` and `ST-P1-09` must stay micro-unit based. Review
cadence is grouped by risk and blast radius:

| Group | Units | Review Requirement |
| --- | --- | --- |
| Small | 9.1, 9.2, 9.3, 9.4, 9.5, 8.1, 8.2, 8.3, 8.9 | Run a targeted fixture/static check after each unit. Claude reviewer participates when available. If Claude is disabled due quota or usage limit, a GPT architect reviewer may count as Claude-equivalent only when degraded trust is explicitly reported. |
| Medium | 9.6, 9.7, 9.8, 8.4, 8.5, 8.6, 8.7, 8.8, 8.10 | Run targeted checks plus `python3 scripts/todo-report.py --fail-on-active` after each unit, and run `./scripts/verify.sh` after each coherent pair or sooner if shell integration, vault writes, or template parity are touched. Claude-or-GPT-equivalent review is required. |
| Large | 8.11 plus any cross-template propagation, broad shell preflight framework, or docs/policy rewrite | Run full `./scripts/verify.sh` and `./scripts/review-gate.sh`. Do not claim completion without review consensus or an explicitly reported degraded substitute. |

Loop rule:

1. implement exactly one micro unit or one coherent small pair
2. inspect diff and classify alignment with this plan
3. run the unit's targeted test
4. run `python3 scripts/todo-report.py --fail-on-active`
5. run `./scripts/verify.sh` for medium/large groups or before any user-facing
   completion claim
6. run review-gate for medium/large groups and for any commit-candidate report
7. if full review-gate context truncates large untracked plans, run narrower
   per-file or per-unit AI council reviews and report the monolithic gate limit
   instead of treating omitted context as approval
8. revise and repeat until every available reviewer approves, or until the
   approved GPT substitute covers a Claude quota/usage-limit gap with degraded
   trust stated plainly

Updated user rule on 2026-05-29: small-or-larger grouped work should include a
Claude reviewer when available. If Claude is inactive because of quota or usage
limit, GPT reviewer output is accepted as equivalent for the unanimity check,
but the final report must label the review state as degraded.

## 실행 순서

1. `ST-P1-09`를 먼저 구현한다.
   - 이미 opt-in drift notice surface가 있으므로 변경 범위가 작다.
   - 사용자가 "AI 호출 시 업데이트 체크를 더 확실히 인식"하는 효과를 먼저
     확인할 수 있다.

2. `ST-P1-08`을 두 번째로 구현한다.
   - vault write, registry project, `/mnt/z` 권한, sync_class 정책이 얽혀 있어
     더 큰 테스트와 실패 처리가 필요하다.
   - 9번에서 정리한 preflight/throttle/notice 구조를 재사용한다.

3. 두 항목을 하나의 preflight framework로 묶는 것은 마지막에 판단한다.
   - 중복 shell 코드가 실제로 커졌을 때만 공통화한다.
   - 처음부터 별도 framework를 만들지 않는다.

## AI Meeting Refinements

Gemini advisor artifact:
`.omx/artifacts/gemini-review-the-ai-auto-later-gated-planning-artifacts-for-st-p1--2026-05-29T10-40-50-229Z.md`.

Accepted refinements:

- `ST-P1-08` dry-run scan needs a latency budget; recommended target is 2
  seconds, with a hard timeout around 5 seconds and warning-only failure
- registry discovery must use existing registry surfaces and must not become an
  expensive workspace or mounted-drive crawl
- failed vault writes must be idempotent and must not leave lock/temp artifacts
  that break a later manual push
- project-level and note-level exclusions should be explicit, testable, and
  reported as skipped rather than failures
- `ST-P1-09` throttle state must be session-scoped or ephemeral, not durable
  cross-project state
- `ai-auto-template-status` failure must map to an installation/status warning,
  not an update/drift claim
- startup update notice needs a stricter latency budget than Obsidian auto-push:
  target 0.5 seconds, hard timeout 1 second
- detached git states, submodules, and malformed note frontmatter must skip or
  warn without interrupting the primary AI command

Claude advisor was attempted in this Ralph branch but did not return before
manual termination. The current unanimity claim therefore cannot rely on Claude
participation; it must rely on Gemini plus review-gate evidence unless Claude is
later re-enabled.

## Ralph Unanimity Conditions

For this planning branch, unanimity means every available reviewer or gate that
successfully inspects the actual plan contents agrees on these points:

- keep `ST-P1-07`, `ST-P1-08`, and `ST-P1-09` as `complete_contract`
  after contract promotion
- no implementation, daemon, browser/session bridge, memory authority, auto
  patch, auto commit, or auto push to git is introduced by this branch
- the implementation path is split into micro units with tests and rollback
  boundaries
- Obsidian push failure and update notice failure remain non-blocking for the
  primary AI invocation
- untracked plan contents are included in review context before claiming review
  closure

If Claude remains unavailable, report unanimity as degraded: Gemini plus Codex
fallback/review-gate may approve the plan, but full two-external-reviewer
unanimity is not established.

## 완료 기준

8번 완료 기준:

- AI_AUTO 본진 호출에서만 pending knowledge summary 또는 push가 동작한다.
- 등록 프로젝트 draft가 포함된다.
- vault 경로, sync_class, symlink, `.omx` 금지, write failure가 테스트된다.
- push 후 validate/index evidence가 남는다.
- AI 호출을 막지 않는 failure mode가 테스트된다.

9번 완료 기준:

- 등록 프로젝트 AI 호출 전 update/drift 상태가 더 분명하게 표시된다.
- current 상태와 반복 호출은 낮은 노이즈를 유지한다.
- opt-out/throttle이 테스트된다.
- 자동 patch/commit/push가 없다는 boundary가 테스트된다.

공통 완료 기준:

- 해당 구현 diff와 이 플랜의 alignment가 보고된다.
- `python3 scripts/todo-report.py --fail-on-active` 통과
- `./scripts/verify.sh` 통과
- commit 후보를 제시할 경우 `./scripts/review-gate.sh` 결과가
  `proceed` 또는 `proceed_degraded`

## 현재 판정

`ST-P1-08`과 `ST-P1-09`는 효과가 있을 가능성이 높다. 다만 지금 당장 활성
TODO로 승격하지 않는다. 9번은 기존 notice 개선으로 낮은 위험에서 시작할 수
있고, 8번은 write boundary가 있으므로 vault 설정, 권한, sync_class 차단,
post-push 검증까지 포함한 별도 구현 승인 후 진행하는 것이 맞다.
