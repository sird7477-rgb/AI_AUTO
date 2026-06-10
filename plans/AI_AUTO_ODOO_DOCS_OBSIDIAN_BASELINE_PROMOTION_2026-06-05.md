# Odoo 공식문서 Obsidian 기준선 정규승격 계획

## 범위

2026-06-05에 수집된 `Odoo19_Docs_KB` Obsidian 기준선을 대상으로 한다.
이 계획은 공식문서 raw/slim/index 데이터의 보관 품질, 요약 왜곡 방지,
문서 지침 연결, 검증 도구 연결을 정규 산출물로 승격한다. 2026-06-10
후속 승격에서 사용자 매뉴얼도 index-only가 아니라 `user-manual/raw`와
`user-manual/slim` mirror로 보관하도록 확장했다.

범위 밖:

- 프로젝트별 DB 스키마를 본진 기준선으로 중앙화하지 않는다.
- Obsidian 데이터를 프로젝트 검증, 리뷰, 최신성, 완료 판정의 권위로 만들지 않는다.
- Odoo 사용자 매뉴얼 mirror는 이 baseline index에 명시된 페이지로 제한한다.

## 기준선

- Vault: `/mnt/z/JSJEON/Obsidian/AI_AUTO_Vault/AI_AUTO/Odoo19_Docs_KB`
- Baseline ID: `odoo-19-docs-2026-06`
- Version: `19.0`
- 구조: developer `raw/` 12개 topic, developer `slim/` 12개 topic,
  사용자 매뉴얼 `user-manual/raw`/`user-manual/slim` mirror

## 마이크로 단위

| Unit | 목표 | 완료 조건 | 상태 |
| --- | --- | --- | --- |
| U1 | 기준선 구조 식별 | raw/slim/index/runbook/meta 구조와 오늘 수집 데이터 범위를 확인한다. | complete |
| U2 | 왜곡 위험 검토 | slim 파일이 구현 근거처럼 쓰이는 위험을 식별하고 non-authority 문구를 요구한다. | complete |
| U3 | Obsidian 데이터 보정 | slim, index, runbook에 navigation-only / heading-only 경계와 raw/URL 사용 규칙을 반영한다. | complete |
| U4 | 검증 도구 승격 | `validate-odoo-docs-kb.py`로 구조, 메타데이터, raw/slim parity, user-manual index-only, secret-like payload를 검사한다. | complete |
| U5 | 지침 연결 | `OBSIDIAN_INTEGRATION.md`, README, template patch note에 공식문서 기준선 사용 순서를 연결한다. | complete |
| U6 | 피드백/백로그 정리 | `obsidian:reference-tier-user-manual-index-only` 개선 제안을 resolved로 전환하고 `ST-P1-49`를 complete_contract로 남긴다. | complete |
| U7 | 검증/리뷰 | targeted pytest, vault validator, `./scripts/verify.sh`, `./scripts/review-gate.sh`가 모두 통과한다. | complete |
| U8 | 사용자 매뉴얼 mirror 승격 | 기존 index의 사용자 매뉴얼 링크를 `user-manual/raw`/`user-manual/slim`으로 수집하고 validator가 coverage를 검증한다. | complete |

## 사용 규칙

1. 프로젝트 자작 가이드를 먼저 본다.
2. 공식 `slim` topic은 탐색용 목차와 heading 확인에만 쓴다.
3. 정확한 의미, 코드 예시, 보안 규칙, API 세부는 matching `raw` topic 1건을 연다.
4. freshness가 중요하면 frontmatter의 `source_url`을 공식 원문 확인 경로로 쓴다.
5. 사용자 매뉴얼은 index를 routing table로 쓰고, `user-manual/slim`으로 탐색한 뒤
   필요한 경우 matching `user-manual/raw` 1건만 연다.

## 검증

필수 검증:

```bash
python3 scripts/validate-odoo-docs-kb.py /mnt/z/JSJEON/Obsidian/AI_AUTO_Vault/AI_AUTO/Odoo19_Docs_KB
.venv/bin/python -m pytest -q tests/test_odoo_docs_kb_validator.py tests/test_template_global_contracts.py
AI_AUTO_ODOO_DOCS_KB_PATH=/mnt/z/JSJEON/Obsidian/AI_AUTO_Vault/AI_AUTO/Odoo19_Docs_KB ./scripts/verify.sh
AI_AUTO_ODOO_DOCS_KB_PATH=/mnt/z/JSJEON/Obsidian/AI_AUTO_Vault/AI_AUTO/Odoo19_Docs_KB ./scripts/review-gate.sh
```

만장일치 완료 조건:

- Codex 구현자가 `verify.sh` green을 확인한다.
- Claude/Gemini 또는 정규 대체 reviewer lane 2인이 `proceed`를 낸다.
- degraded 또는 unresolved finding이 있으면 완료로 보고하지 않는다.

최종 증거:

- `AI_AUTO_ODOO_DOCS_KB_PATH=/mnt/z/JSJEON/Obsidian/AI_AUTO_Vault/AI_AUTO/Odoo19_Docs_KB ./scripts/verify.sh`: green, pytest 199개 통과, Odoo docs baseline 12 topic 검증 통과, Docker smoke 통과.
- `AI_AUTO_ODOO_DOCS_KB_PATH=/mnt/z/JSJEON/Obsidian/AI_AUTO_Vault/AI_AUTO/Odoo19_Docs_KB ./scripts/review-gate.sh`: `proceed`, `principal_rotation`, trust `normal`, Gemini `approve_with_notes`, Codex `approve`.
