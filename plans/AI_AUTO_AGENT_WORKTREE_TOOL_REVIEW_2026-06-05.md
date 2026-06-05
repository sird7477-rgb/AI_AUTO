# AI Agent Worktree Tool Review (2026-06-05)

## 요약

여러 AI 에이전트가 같은 repository를 동시에 만질 때 `git status`, untracked
artifact, review context, branch ownership이 섞이는 문제가 반복된다. 이미 수동으로
worktree를 쓰고 있다면 새 대형 런타임을 도입하기보다, 현재 운영을 표준화하는 얇은
registry/status 도구가 현실적이다.

권장 방향:

- 새 IDE/desktop 앱 도입보다 repo-native CLI 래퍼 우선.
- 자동 merge는 1차 범위에서 제외.
- `status/start/finish/cleanup`과 명명 규칙, stale worktree 보고, merge 전
  `verify.sh`/`review-gate.sh` checklist까지만 검토한다.
- 기존 `git worktree`, branch, tmux/OMX 운영을 대체하지 않고 관찰/정리 계층으로
  둔다.

## 참고 도구

| Tool | Type | 참고점 | URL |
| --- | --- | --- | --- |
| workmux | CLI + tmux + worktree | task마다 worktree와 tmux window를 붙이는 패턴이 AI_AUTO/OMX 운영과 가장 가깝다. | https://workmux.raine.dev/ |
| Hive | CLI/TUI | isolated/manageable-by-default worktree workspace 표면. | https://hive.cretu.dev/ |
| Rift | CLI | agent별 isolated worktree + branch 생성 흐름 참고. | https://rift.priyashpatil.com/ |
| git-stint | OSS CLI | Claude Code hook 기반 branch/worktree 자동 생성 아이디어 참고. | https://github.com/rchaz/git-stint |
| Etz | general worktree CLI | AI 전용은 아니지만 scriptable worktree lifecycle 관리 참고. | https://www.etz.dev/ |
| Orca | worktree IDE | Codex/Claude/OpenCode 병렬 pane UI 참고. 직접 도입보다는 UX 참고. | https://www.orcabuild.ai/ |
| Arborist | desktop app | local worktree + CLI process restore/organization 참고. | https://arborist.tools/ |
| Cuttlefish | macOS app | agent별 worktree 가시화 패턴 참고. | https://cuttlefish.build/ |
| Verun | native workspace | bring-your-own-agent + worktree 격리 workspace 참고. | https://www.verun.dev/ |

## AI_AUTO 후보 범위

후보 이름: `ai-worktree` 또는 `ai-agent-worktree`.

초기 명령 후보:

```bash
ai-worktree status
ai-worktree start <agent> <task>
ai-worktree finish <name>
ai-worktree cleanup
```

최소 기능 후보:

- repo root와 linked worktree 목록 출력.
- agent/task/branch/worktree path 명명 규칙 제안.
- main worktree dirty/untracked 상태와 agent worktree dirty 상태 분리 표시.
- 오래된 worktree cleanup 후보를 dry-run으로만 표시.
- finish 시 changed files, branch, last commit, recommended verification command 출력.
- merge/push/삭제는 기본 dry-run 또는 명시 승인 후로 제한.

## 제외 범위

- 자동 merge.
- 자동 branch delete.
- AI agent 실행/권한 부여 런타임.
- queue/scheduler/dashboard.
- `verify.sh` 또는 `review-gate.sh`를 대체하는 완료 권한.
- project-owned 파일을 자동 판정해 수정하는 기능.

## 채택 조건

다음 조건 중 하나가 반복되면 별도 실행계획으로 승격한다.

- 같은 repo에서 2개 이상 AI 세션이 동시에 쓰기 작업을 자주 수행한다.
- review-gate가 무관 untracked artifact나 tree churn으로 반복 흔들린다.
- worktree/branch 소유자가 불명확해 통합자가 수동 확인에 시간을 쓴다.
- 실패한 agent 작업을 안전하게 폐기/보존하는 표준 절차가 필요하다.

승격 시 최소 검증:

- fixture repo에서 `git worktree list --porcelain` 파싱 테스트.
- dirty main / dirty agent / stale worktree / missing branch / detached HEAD 케이스.
- dry-run cleanup이 파일을 삭제하지 않는다는 테스트.
- `./scripts/verify.sh`와 review-gate 만장일치.
