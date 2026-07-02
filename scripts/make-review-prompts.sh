#!/usr/bin/env bash
set -euo pipefail

CONTEXT_FILE="${1:-.omx/review-context/latest-review-context.md}"
OUT_DIR="${OUT_DIR:-.omx/review-prompts}"
REVIEW_CONTEXT_MAX_BYTES="${REVIEW_CONTEXT_MAX_BYTES:-300000}"
REVIEW_CONTEXT_SPLIT_LINES="${REVIEW_CONTEXT_SPLIT_LINES:-400}"
REVIEW_CONTEXT_SPLIT_BYTES="${REVIEW_CONTEXT_SPLIT_BYTES:-${REVIEW_CONTEXT_MAX_BYTES}}"
# Denial-of-wallet ceiling: an attacker-controlled oversized diff splits linearly into
# part-NNNN.md, and run-ai-reviews.sh fans out ONE real model call per part per reviewer
# (+retry, +synthesis). Cap the part count; past the ceiling we do NOT fan out — we emit a
# single fail-closed verdict (mirrors the GEMINI_PROMPT_MAX_BYTES fail-closed in
# run-ai-reviews.sh). A few dozen parts is plenty for a legitimately scoped change.
REVIEW_MAX_PARTS="${REVIEW_MAX_PARTS:-40}"
OVERSIZED_CONTEXT_FLAG="${OUT_DIR}/oversized-review-context.flag"
OVERSIZED_CONTEXT=0

mkdir -p "${OUT_DIR}"
rm -f "${OUT_DIR}/split-review-manifest.md"
rm -f "${OVERSIZED_CONTEXT_FLAG}"
rm -rf "${OUT_DIR}/split-review-context"

if [ ! -f "${CONTEXT_FILE}" ]; then
  echo "Review context file not found: ${CONTEXT_FILE}"
  echo "Run ./scripts/collect-review-context.sh first."
  exit 1
fi

ORIGINAL_CONTEXT_FILE="${CONTEXT_FILE}"
SPLIT_MANIFEST_FILE=""
context_bytes="$(wc -c < "${CONTEXT_FILE}")"
if [ "${context_bytes}" -gt "${REVIEW_CONTEXT_MAX_BYTES}" ]; then
  is_positive_integer='^[0-9]+$'
  if ! printf '%s\n' "${REVIEW_CONTEXT_SPLIT_LINES}" | grep -Eq "${is_positive_integer}" || [ "${REVIEW_CONTEXT_SPLIT_LINES}" -lt 1 ]; then
    echo "Invalid REVIEW_CONTEXT_SPLIT_LINES=${REVIEW_CONTEXT_SPLIT_LINES}; expected a positive integer" >&2
    exit 2
  fi
  if ! printf '%s\n' "${REVIEW_CONTEXT_SPLIT_BYTES}" | grep -Eq "${is_positive_integer}" || [ "${REVIEW_CONTEXT_SPLIT_BYTES}" -lt 1 ]; then
    echo "Invalid REVIEW_CONTEXT_SPLIT_BYTES=${REVIEW_CONTEXT_SPLIT_BYTES}; expected a positive integer" >&2
    exit 2
  fi
  if ! printf '%s\n' "${REVIEW_MAX_PARTS}" | grep -Eq "${is_positive_integer}" || [ "${REVIEW_MAX_PARTS}" -lt 1 ]; then
    echo "Invalid REVIEW_MAX_PARTS=${REVIEW_MAX_PARTS}; expected a positive integer" >&2
    exit 2
  fi

  SPLIT_DIR="${OUT_DIR}/split-review-context"
  rm -rf "${SPLIT_DIR}"
  mkdir -p "${SPLIT_DIR}"

  LC_ALL=C awk -v outdir="${SPLIT_DIR}" -v lines="${REVIEW_CONTEXT_SPLIT_LINES}" -v bytes="${REVIEW_CONTEXT_SPLIT_BYTES}" '
    BEGIN { part = 1; line_in_part = 0; part_bytes = 0; file = sprintf("%s/part-%04d.body.md", outdir, part) }
    {
      line_bytes = length($0) + 1
      if (line_in_part > 0 && (line_in_part >= lines || part_bytes + line_bytes > bytes)) {
        close(file)
        part++
        line_in_part = 0
        part_bytes = 0
        file = sprintf("%s/part-%04d.body.md", outdir, part)
      }
      print $0 >> file
      line_in_part++
      part_bytes += line_bytes
    }
  ' "${CONTEXT_FILE}"

  part_count="$(find "${SPLIT_DIR}" -maxdepth 1 -type f -name 'part-*.body.md' | wc -l | tr -d ' ')"
  if [ "${part_count}" -gt "${REVIEW_MAX_PARTS}" ]; then
    # Fail CLOSED: do NOT fan out unbounded per-part reviewer calls. Drop the split
    # artifacts, drop the manifest (so run-ai-reviews.sh does not enter the split loop),
    # and drop an oversized flag that run-ai-reviews.sh reads to short-circuit each
    # reviewer to a single request_changes verdict with NO model call.
    rm -rf "${SPLIT_DIR}"
    OVERSIZED_CONTEXT=1
    {
      echo "Review context split into ${part_count} parts, over REVIEW_MAX_PARTS=${REVIEW_MAX_PARTS}."
      echo "Context too large for bounded external review; narrow scope or split manually."
    } > "${OVERSIZED_CONTEXT_FLAG}"
    echo "Review context too large: ${part_count} parts exceed REVIEW_MAX_PARTS=${REVIEW_MAX_PARTS}; emitting fail-closed request_changes." >&2
  fi
  for body in "${SPLIT_DIR}"/part-*.body.md; do
    [ "${OVERSIZED_CONTEXT}" = "1" ] && break
    [ -f "${body}" ] || continue
    part_name="$(basename "${body}" .body.md)"
    part_number="$(printf '%s\n' "${part_name}" | sed 's/^part-//; s/^0*//')"
    if [ -z "${part_number}" ]; then
      part_number=0
    fi
    part_file="${SPLIT_DIR}/${part_name}.md"
    body_bytes="$(wc -c < "${body}")"
    if [ "${body_bytes}" -gt "${REVIEW_CONTEXT_SPLIT_BYTES}" ]; then
      echo "Split review part ${body} is ${body_bytes} bytes and exceeds REVIEW_CONTEXT_SPLIT_BYTES=${REVIEW_CONTEXT_SPLIT_BYTES}" >&2
      echo "A single context line may be too large to review safely without truncation." >&2
      exit 2
    fi
    {
      echo "# Split Review Context ${part_number}/${part_count}"
      echo
      echo "Original context: ${ORIGINAL_CONTEXT_FILE}"
      echo "Original bytes: ${context_bytes}"
      echo "Part lines limit: ${REVIEW_CONTEXT_SPLIT_LINES}"
      echo "Part body bytes: ${body_bytes}"
      echo "Part body byte limit: ${REVIEW_CONTEXT_SPLIT_BYTES}"
      echo
      echo "Do not issue a final review verdict from this part alone. A final verdict requires all parts or a synthesized review that explicitly lists every part with a non-empty per-part observation."
      echo
      cat "${body}"
    } > "${part_file}"
    rm -f "${body}"
  done

  if [ "${OVERSIZED_CONTEXT}" != "1" ]; then
  SPLIT_MANIFEST_FILE="${OUT_DIR}/split-review-manifest.md"
  {
    echo "# Split Review Manifest"
    echo
    echo "The original review context exceeded the configured reviewer limit and was split instead of silently compressed."
    echo
    echo "- Original context: ${ORIGINAL_CONTEXT_FILE}"
    echo "- Original bytes: ${context_bytes}"
    echo "- REVIEW_CONTEXT_MAX_BYTES: ${REVIEW_CONTEXT_MAX_BYTES}"
    echo "- REVIEW_CONTEXT_SPLIT_LINES: ${REVIEW_CONTEXT_SPLIT_LINES}"
    echo "- REVIEW_CONTEXT_SPLIT_BYTES: ${REVIEW_CONTEXT_SPLIT_BYTES}"
    echo "- Part count: ${part_count}"
    echo
    echo "## Review Protocol"
    echo
    echo "A reviewer must not issue a final verdict from a truncated head/tail excerpt. Process every part in order, then issue one final verdict. If the reviewer surface cannot process ordered parts in one stateful conversation, produce per-part observations first and run a separate synthesis review over those observations. A valid synthesis must include one non-empty observation line for every part."
    echo
    echo "## Parts"
    echo
    find "${SPLIT_DIR}" -maxdepth 1 -type f -name 'part-*.md' | sort | sed 's/^/- /'
  } > "${SPLIT_MANIFEST_FILE}"
  fi
fi

CLAUDE_PROMPT="${OUT_DIR}/claude-review.md"
GEMINI_PROMPT="${OUT_DIR}/gemini-review.md"

cat > "${CLAUDE_PROMPT}" <<PROMPT
# Claude Review Request

You are reviewing a small Codex-generated change in this repository.

Use only the review context embedded in this prompt. Do not run shell commands,
inspect repository files, invoke tools, or start a fresh verification run. If the
embedded context is insufficient for a confident review, return request_changes
and name the missing context.

Focus on:

- correctness
- maintainability
- scope control
- hidden risk
- whether the change follows AGENTS.md and docs/WORKFLOW.md
PROMPT

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
PROMPT

if [ "${OVERSIZED_CONTEXT}" = "1" ]; then
  cat "${OVERSIZED_CONTEXT_FLAG}" >> "${CLAUDE_PROMPT}"
elif [ -n "${SPLIT_MANIFEST_FILE}" ]; then
  cat >> "${CLAUDE_PROMPT}" <<PROMPT
# Review Context Overflow

The full review context is too large for a single bounded external-review prompt.
It has been split into ordered parts. Do not approve from a head/tail truncation.
Return request_changes unless all split parts are processed in order or a
synthesis review explicitly lists every part with a non-empty per-part
observation.

PROMPT
  cat "${SPLIT_MANIFEST_FILE}" >> "${CLAUDE_PROMPT}"
else
  cat "${CONTEXT_FILE}" >> "${CLAUDE_PROMPT}"
fi

cat > "${GEMINI_PROMPT}" <<PROMPT
# Gemini Review Request

You are reviewing a small Codex-generated change in this repository.

Use only the review context embedded in this prompt. Do not run shell commands,
inspect repository files, invoke tools, or start a fresh verification run. If the
embedded context is insufficient for a confident review, return request_changes
and name the missing context.

Focus on:

- missed edge cases
- alternative simpler approaches
- test coverage
- documentation clarity
- whether the change creates future automation friction
PROMPT

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
PROMPT

if [ "${OVERSIZED_CONTEXT}" = "1" ]; then
  cat "${OVERSIZED_CONTEXT_FLAG}" >> "${GEMINI_PROMPT}"
elif [ -n "${SPLIT_MANIFEST_FILE}" ]; then
  cat >> "${GEMINI_PROMPT}" <<PROMPT
# Review Context Overflow

The full review context is too large for a single bounded external-review prompt.
It has been split into ordered parts. Do not approve from a head/tail truncation.
Return request_changes unless all split parts are processed in order or a
synthesis review explicitly lists every part with a non-empty per-part
observation.

PROMPT
  cat "${SPLIT_MANIFEST_FILE}" >> "${GEMINI_PROMPT}"
else
  cat "${CONTEXT_FILE}" >> "${GEMINI_PROMPT}"
fi

echo "${CLAUDE_PROMPT}"
echo "${GEMINI_PROMPT}"
