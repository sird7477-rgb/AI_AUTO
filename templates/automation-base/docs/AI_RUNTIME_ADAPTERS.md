# AI 런타임 어댑터

AI_AUTO의 런타임 어댑터는 Codex/GPT 중심으로 작성된 자동화 계약을
Claude, Gemini/agy 같은 다른 AI CLI에도 같은 맥락으로 적용하기 위한
얇은 호환 계층이다. 목표는 런타임별 차이를 숨기되, 권한과 검증 경계를
흐리지 않는 것이다.

## 원칙

- 코드가 없는 해결이 가장 우선이다. 새 어댑터는 실제 반복 비용이나
  운영 리스크를 줄일 때만 추가한다.
- 기본 실행 범위는 `review`, `analyze`, `plan` 같은 read-only 의도 작업이다.
  Codex는 `--sandbox read-only`를 사용한다. Claude와 agy/Gemini은 가능한
  no-edit/plan 플래그를 사용하지만, 이를 파일시스템 sandbox로 간주하지
  않는다.
- `edit_files`, `commit` 같은 쓰기/배포 성격 작업은 별도 실행 계약과
  리뷰 게이트가 승인되기 전까지 어댑터 실행 대상이 아니다.
- 실험 브랜치의 AI_AUTO 템플릿은 프로젝트에 패치 소스로 쓰지 않는다.
  `ai-auto-template-status`가 `template_patch_enabled: no`를 보고하면
  패치 적용을 중단하고 원인을 보고한다.
- 리뷰 컨텍스트가 분할되거나 축약된 경우, 각 part를 실제로 읽었다는
  합성 증거 없이 승인 verdict를 신뢰하지 않는다.
- Runtime adapter의 capability 결과는 권한 증거이지 권한 부여가 아니다.
  agent identity, tool permission class, kill switch/revoke, trend report
  경계는 `docs/AI_AUTOMATION_TREND_HARDENING.md`를 따른다.

## 단계 상태

1. 브랜치/패치 가드: `ai-auto-template-status`가 템플릿 소스 브랜치와
   패치 가능 여부를 보고한다. `main`만 stable 패치 소스다.
2. capability model: 런타임별 capability와 execution mode는
   `scripts/ai-runtime-adapter.sh capability`로 조회한다.
3. adapter contract: 공통 입력은 prompt file, 공통 출력은 output file이다.
4. read-only adapters: Codex, Claude, agy/Gemini은 read-only 작업만
   실행할 수 있다.
5. split context commonization: 런타임별 CLI 차이는 prompt file 기반
   adapter 호출로 흡수한다. split context의 신뢰성은 review gate가 검증한다.
6. execution modes: `readonly_sandbox`, `logical_readonly`, `executor`, `git`을
   구분하고, 현재 스크립트는 read-only 계열만 실행한다.
7. verification gates: `./scripts/verify.sh`가 capability, fake CLI 호출,
   write capability 거부, 템플릿 상태 가드를 검증한다.
8. main merge condition: stable 패치 소스, verify 통과, review gate 통과,
   AI reviewer와 서브에이전트 리뷰의 blocker 해소가 필요하다.

## 사용 예

```bash
./scripts/ai-runtime-adapter.sh capability claude review
./scripts/ai-runtime-adapter.sh capability gemini edit_files
./scripts/ai-runtime-adapter.sh run-readonly \
  --runtime agy \
  --capability review \
  --prompt-file .omx/review-prompts/gemini-review.md \
  --output .omx/review-results/gemini-review.md
```

`run-readonly`는 성공 시 `adapter_status`, `artifact_path`,
`execution_mode`를 표준 출력에 남기고, 실제 리뷰 본문은 `--output`
파일에 저장한다. `capability` 조회가 `supported: no`를 반환하거나 실행이
`capability_refused`로 종료되면, 해당 런타임에 작업을 우회시키지 말고
상위 게이트에 degraded/blocked 상태로 보고한다.

쓰기 가능한 adapter, credentialed adapter, git/publish adapter, MCP/tool
connector adapter는 현재 계약 밖이다. 추가하려면 tool permission registry,
revocation path, redaction boundary, rollback/verification path를 먼저
문서화하고 별도 리뷰 게이트를 통과해야 한다.
