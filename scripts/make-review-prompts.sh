#!/usr/bin/env bash
set -euo pipefail

CONTEXT_FILE="${1:-.omx/review-context/latest-review-context.md}"
OUT_DIR="${OUT_DIR:-.omx/review-prompts}"
REVIEW_STATE_DIR="${REVIEW_STATE_DIR:-.omx/reviewer-state}"

mkdir -p "${OUT_DIR}"

if [ ! -f "${CONTEXT_FILE}" ]; then
  echo "Review context file not found: ${CONTEXT_FILE}"
  echo "Run ./scripts/collect-review-context.sh first."
  exit 1
fi

CLAUDE_PROMPT="${OUT_DIR}/claude-review.md"
GEMINI_PROMPT="${OUT_DIR}/gemini-review.md"

reviewer_disabled() {
  [ -f "${REVIEW_STATE_DIR}/$1.disabled" ]
}

disabled_note() {
  local reviewer="$1"
  local file="${REVIEW_STATE_DIR}/${reviewer}.disabled"

  if [ -f "${file}" ]; then
    local reason details disabled_at
    reason="$(sed -n 's/^reason=//p' "${file}")"
    details="$(sed -n 's/^details=//p' "${file}")"
    disabled_at="$(sed -n 's/^disabled_at=//p' "${file}")"
    echo "reason=${reason}; details=${details}; disabled_at=${disabled_at}"
  fi
}

cat > "${CLAUDE_PROMPT}" <<PROMPT
# Claude Review Request

You are reviewing a small Codex-generated change in this repository.

Focus on:

- correctness
- maintainability
- scope control
- hidden risk
- whether the change follows AGENTS.md and docs/WORKFLOW.md
PROMPT

if reviewer_disabled gemini; then
  cat >> "${CLAUDE_PROMPT}" <<PROMPT

Additional coverage because Gemini is disabled:

- missed edge cases
- alternative simpler approaches
- test coverage gaps
- documentation clarity
- future automation friction

Gemini disabled reason: $(disabled_note gemini)
PROMPT
fi

cat >> "${CLAUDE_PROMPT}" <<PROMPT

Do not suggest broad rewrites unless the current diff is unsafe.

Return your review in this format:

## Verdict

Choose one:

- approve
- approve_with_notes
- request_changes

## Findings

List concrete issues only. For each issue include:

- severity: low / medium / high
- file or area
- reason
- suggested fix

## Scope Check

Say whether the change stayed within the requested scope.

## Verification Check

Say whether the reported verification evidence is sufficient.

## Final Recommendation

Give a short final recommendation.

---

$(cat "${CONTEXT_FILE}")
PROMPT

cat > "${GEMINI_PROMPT}" <<PROMPT
# Gemini Review Request

You are reviewing a small Codex-generated change in this repository.

Focus on:

- missed edge cases
- alternative simpler approaches
- test coverage
- documentation clarity
- whether the change creates future automation friction
PROMPT

if reviewer_disabled claude; then
  cat >> "${GEMINI_PROMPT}" <<PROMPT

Additional coverage because Claude is disabled:

- correctness
- maintainability
- scope control
- hidden risk
- AGENTS.md and docs/WORKFLOW.md compliance

Claude disabled reason: $(disabled_note claude)
PROMPT
fi

cat >> "${GEMINI_PROMPT}" <<PROMPT

Do not expand the task beyond the requested scope.

Return your review in this format:

## Verdict

Choose one:

- approve
- approve_with_notes
- request_changes

## Missed Cases

List any missing cases or assumptions.

## Simpler Alternative

Mention a simpler approach only if it is clearly better.

## Test Ideas

Suggest only relevant tests or checks.

## Documentation Clarity

Say whether the documentation is clear enough for the next agent.

## Final Recommendation

Give a short final recommendation.

---

$(cat "${CONTEXT_FILE}")
PROMPT

echo "${CLAUDE_PROMPT}"
echo "${GEMINI_PROMPT}"
