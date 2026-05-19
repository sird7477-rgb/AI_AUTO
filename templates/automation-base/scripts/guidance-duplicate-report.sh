#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${GUIDANCE_DUPLICATE_REPORT_DIR:-.omx/doc-duplicate-report}"
USE_NPX="${GUIDANCE_DUPLICATE_USE_NPX:-0}"
MIN_LINE_LENGTH="${GUIDANCE_DUPLICATE_MIN_LINE_LENGTH:-90}"
TIMESTAMP="$(date +%Y%m%dT%H%M%S%z)"
REPORT_PATH="${OUT_DIR}/guidance-duplicate-report-${TIMESTAMP}.md"

SCOPE=("$@")
if [ "${#SCOPE[@]}" -eq 0 ]; then
  SCOPE=(AGENTS.md docs templates/automation-base)
fi

mkdir -p "${OUT_DIR}"

write_header() {
  {
    echo "# 2단계 지침 중복 리포트"
    echo
    echo "생성 시각: ${TIMESTAMP}"
    echo
    echo "범위:"
    printf -- "- %s\n" "${SCOPE[@]}"
    echo
    echo "목적:"
    echo "- 문서 수정 없이 반복 규칙과 통합 후보를 찾는다."
    echo "- 기존 배포 도구를 우선 사용하고, 없으면 로컬 경량 분석으로 대체한다."
    echo "- 실제 삭제나 통합은 사용자 판단 후 별도 작업으로 진행한다."
    echo
  } > "${REPORT_PATH}"
}

run_jscpd() {
  local runner="$1"
  local runner_label="$2"
  local jscpd_dir="${OUT_DIR}/jscpd-${TIMESTAMP}"
  local console_path="${jscpd_dir}/console.txt"

  mkdir -p "${jscpd_dir}"

  {
    echo "## 기존 도구 분석"
    echo
    echo "사용 도구: ${runner_label}"
    echo
    echo '```text'
  } >> "${REPORT_PATH}"

  set +e
  if [ "${runner}" = "npx" ]; then
    NO_COLOR=1 FORCE_COLOR=0 npx -y jscpd "${SCOPE[@]}" \
      --pattern "**/*.md" \
      --format markdown \
      --reporters console,json \
      --noTips \
      --output "${jscpd_dir}" > "${console_path}" 2>&1
  else
    NO_COLOR=1 FORCE_COLOR=0 "${runner}" "${SCOPE[@]}" \
      --pattern "**/*.md" \
      --format markdown \
      --reporters console,json \
      --noTips \
      --output "${jscpd_dir}" > "${console_path}" 2>&1
  fi
  local status=$?
  set -e

  awk '{ gsub(/\033\[[0-9;]*[A-Za-z]/, ""); print }' "${console_path}" >> "${REPORT_PATH}"
  {
    echo '```'
    echo
    echo "도구 종료 상태: ${status}"
    echo
    echo "상세 산출물: ${jscpd_dir}"
    echo
  } >> "${REPORT_PATH}"

  return 0
}

run_fallback_report() {
  local file_list
  local repeated_lines
  local repeated_headings
  file_list="$(mktemp)"
  repeated_lines="$(mktemp)"
  repeated_headings="$(mktemp)"

  for path in "${SCOPE[@]}"; do
    if [ -f "${path}" ]; then
      printf '%s\0' "${path}" >> "${file_list}"
    elif [ -d "${path}" ]; then
      find "${path}" -type f -name '*.md' -print0 >> "${file_list}"
    fi
  done

  sort -z -u "${file_list}" -o "${file_list}"

  {
    echo "## 로컬 경량 분석"
    echo
    echo "기존 중복 탐지 도구를 실행하지 못해 로컬 분석으로 대체했다."
    echo
    echo "### 반복 긴 문장"
    echo
  } >> "${REPORT_PATH}"

  xargs -0 -r awk -v min_len="${MIN_LINE_LENGTH}" '
    length($0) >= min_len && $0 !~ /^[[:space:]]*#/ {
      count[$0] += 1
      where[$0] = where[$0] FILENAME ":" FNR "; "
    }
    END {
      found = 0
      for (line in count) {
        if (count[line] >= 2) {
          found = 1
          printf "%08d\t%s\t%s\n", count[line], substr(line, 1, 180), where[line]
        }
      }
      if (!found) {
        exit 0
      }
    }
  ' < "${file_list}" | sort -r > "${repeated_lines}"

  if [ -s "${repeated_lines}" ]; then
    awk -F '\t' '{ printf "- %d회: %s\n  위치: %s\n", $1 + 0, $2, $3 }' "${repeated_lines}" >> "${REPORT_PATH}"
  else
    echo "- 같은 긴 문장이 2회 이상 반복된 사례는 찾지 못했다." >> "${REPORT_PATH}"
  fi

  {
    echo
    echo "### 반복 섹션 제목"
    echo
  } >> "${REPORT_PATH}"

  xargs -0 -r awk '
    /^##+[[:space:]]+/ {
      title = $0
      count[title] += 1
      where[title] = where[title] FILENAME ":" FNR "; "
    }
    END {
      found = 0
      for (title in count) {
        if (count[title] >= 2) {
          found = 1
          printf "%08d\t%s\t%s\n", count[title], title, where[title]
        }
      }
      if (!found) {
        exit 0
      }
    }
  ' < "${file_list}" | sort -r > "${repeated_headings}"

  if [ -s "${repeated_headings}" ]; then
    awk -F '\t' '{ printf "- %d회: %s\n  위치: %s\n", $1 + 0, $2, $3 }' "${repeated_headings}" >> "${REPORT_PATH}"
  else
    echo "- 같은 섹션 제목이 2회 이상 반복된 사례는 찾지 못했다." >> "${REPORT_PATH}"
  fi

  {
    echo
    echo "### 판단 기준"
    echo
    echo "- 템플릿 문서와 원본 문서의 반복은 새 프로젝트 복사를 위한 의도된 반복일 수 있다."
    echo "- AGENTS.md에는 짧은 실행 규칙만 두고, 상세 판단 기준은 docs 문서로 모으는 편이 안전하다."
    echo "- 이 리포트는 삭제 지시가 아니라 통합 후보 제안이다."
    echo
  } >> "${REPORT_PATH}"

  rm -f "${file_list}" "${repeated_lines}" "${repeated_headings}"
}

write_header

if command -v jscpd >/dev/null 2>&1; then
  run_jscpd "jscpd" "jscpd"
elif [ "${USE_NPX}" = "1" ] && command -v npx >/dev/null 2>&1; then
  run_jscpd "npx" "npx -y jscpd"
else
  run_fallback_report
fi

echo "[stage2] guidance duplicate report written: ${REPORT_PATH}"
