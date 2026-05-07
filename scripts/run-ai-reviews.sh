#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-.omx/review-results}"
PROMPT_DIR="${PROMPT_DIR:-.omx/review-prompts}"
REVIEW_TIMEOUT_SECONDS="${REVIEW_TIMEOUT_SECONDS:-180}"

mkdir -p "${OUT_DIR}"

echo "[review] collecting review context..."
CONTEXT_FILE="$(./scripts/collect-review-context.sh)"

echo "[review] generating review prompts..."
./scripts/make-review-prompts.sh "${CONTEXT_FILE}" >/dev/null

CLAUDE_PROMPT="${PROMPT_DIR}/claude-review.md"
GEMINI_PROMPT="${PROMPT_DIR}/gemini-review.md"

TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
CLAUDE_OUT="${OUT_DIR}/claude-review-${TIMESTAMP}.md"
GEMINI_OUT="${OUT_DIR}/gemini-review-${TIMESTAMP}.md"
SUMMARY_OUT="${OUT_DIR}/review-summary-${TIMESTAMP}.md"

run_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "[review] claude command not found; skipping Claude review"
    cat > "${CLAUDE_OUT}" <<MSG
# Claude Review

Skipped: claude command not found.
MSG
    return 0
  fi

  echo "[review] running Claude review..."

  set +e
  if claude --help 2>/dev/null | grep -q -- '--print'; then
    timeout "${REVIEW_TIMEOUT_SECONDS}" claude --print "$(cat "${CLAUDE_PROMPT}")" > "${CLAUDE_OUT}" 2>&1
  else
    timeout "${REVIEW_TIMEOUT_SECONDS}" claude < "${CLAUDE_PROMPT}" > "${CLAUDE_OUT}" 2>&1
  fi
  status=$?
  set -e

  if [ "${status}" -ne 0 ]; then
    {
      echo
      echo "---"
      echo
      echo "Claude review failed or timed out."
      echo "Exit status: ${status}"
    } >> "${CLAUDE_OUT}"
    echo "[review] Claude review failed; result captured: ${CLAUDE_OUT}"
    return 0
  fi

  echo "[review] Claude result: ${CLAUDE_OUT}"
}

run_gemini() {
  if [ "${RUN_GEMINI_REVIEW:-0}" != "1" ]; then
    echo "[review] Gemini review disabled by default; set RUN_GEMINI_REVIEW=1 to enable"
    cat > "${GEMINI_OUT}" <<MSG
# Gemini Review

Skipped: Gemini review is disabled by default.

Reason:
- Gemini CLI may enter interactive or agent mode.
- Previous runs hung or failed with capacity/tool errors.
- Enable explicitly with RUN_GEMINI_REVIEW=1 after confirming a non-interactive invocation mode.
MSG
    return 0
  fi

  if ! command -v gemini >/dev/null 2>&1; then
    echo "[review] gemini command not found; skipping Gemini review"
    cat > "${GEMINI_OUT}" <<MSG
# Gemini Review

Skipped: gemini command not found.
MSG
    return 0
  fi

  echo "[review] running Gemini review..."

  set +e
  if gemini --help 2>/dev/null | grep -q -- '--prompt'; then
    timeout "${REVIEW_TIMEOUT_SECONDS}" gemini --prompt "$(cat "${GEMINI_PROMPT}")" > "${GEMINI_OUT}" 2>&1
  else
    timeout "${REVIEW_TIMEOUT_SECONDS}" gemini < "${GEMINI_PROMPT}" > "${GEMINI_OUT}" 2>&1
  fi
  status=$?
  set -e

  if [ "${status}" -ne 0 ]; then
    {
      echo
      echo "---"
      echo
      echo "Gemini review failed or timed out."
      echo "Exit status: ${status}"
      echo
      echo "Known possible causes:"
      echo "- Gemini model capacity exhausted"
      echo "- CLI tool permissions differ from this repository workflow"
      echo "- Gemini CLI entered an agent/tool mode instead of plain review mode"
    } >> "${GEMINI_OUT}"
    echo "[review] Gemini review failed; result captured: ${GEMINI_OUT}"
    return 0
  fi

  echo "[review] Gemini result: ${GEMINI_OUT}"
}

run_claude
run_gemini

cat > "${SUMMARY_OUT}" <<SUMMARY
# AI Review Summary

Generated at: $(date -Iseconds)

## Inputs

- Context: ${CONTEXT_FILE}
- Claude prompt: ${CLAUDE_PROMPT}
- Gemini prompt: ${GEMINI_PROMPT}

## Outputs

- Claude result: ${CLAUDE_OUT}
- Gemini result: ${GEMINI_OUT}

## Notes

A reviewer failure does not fail this script. Failures are captured in the corresponding result file.
SUMMARY

echo "[review] summary: ${SUMMARY_OUT}"
echo "[review] done"
