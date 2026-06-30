import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _run(args: list[str], *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        args,
        cwd=ROOT,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def _write_review(path: Path, verdict: str, extra: str = "") -> None:
    path.write_text(
        f"""# Review

## Verdict

{verdict}

## Findings

No blocking findings.

## Direct File Inspection

- docs/AI_PRINCIPAL_RUNTIMES.md

{extra}
""",
        encoding="utf-8",
    )


def _write_review_manifest(
    out_dir: Path,
    tmp_path: Path,
    claude: Path,
    gemini: Path,
    codex: Path,
    codex_test: Path,
    codex_summary: Path,
) -> None:
    summary = out_dir / "review-summary-20260531T000000.md"
    summary.write_text(
        f"""# AI Review Summary

## Inputs

- Context: {tmp_path / "missing-context.md"}
- Claude result: {claude}
- Gemini result: {gemini}
- Codex architect fallback: {codex}
- Codex test fallback: {codex_test}
- Codex fallback summary: {codex_summary}
- Split context manifest: none
""",
        encoding="utf-8",
    )


def test_principal_profiles_share_repo_local_permissions() -> None:
    profiles = {}
    for principal in ("codex", "claude", "gemini", "agy"):
        result = _run(["./scripts/ai-principal-runtime.sh", "profile", principal])
        assert result.returncode == 0, result.stderr
        profile = dict(line.split("=", 1) for line in result.stdout.strip().splitlines())
        profiles[principal] = profile

    baseline = profiles["codex"]
    for principal in ("claude", "gemini", "agy"):
        assert profiles[principal]["repo_local_allowed_actions"] == baseline["repo_local_allowed_actions"]
        assert profiles[principal]["requires_user_approval_for"] == baseline["requires_user_approval_for"]
        assert profiles[principal]["artifact_roots"] == baseline["artifact_roots"]

    assert profiles["agy"]["principal_runtime"] == "gemini"


def test_principal_reviewer_rotation_contract() -> None:
    expected = {
        "codex": ["claude", "gemini"],
        "claude": ["gemini", "codex"],
        "gemini": ["claude", "codex"],
        "agy": ["claude", "codex"],
    }
    for principal, reviewers in expected.items():
        result = _run(["./scripts/ai-principal-runtime.sh", "reviewers", principal])
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip().splitlines() == reviewers

    result = _run(["./scripts/ai-principal-runtime.sh", "normalize", "unknown"])
    assert result.returncode == 2
    assert "unsupported principal runtime" in result.stderr


def test_principal_runtime_records_launcher_execution_evidence(tmp_path: Path) -> None:
    evidence_file = tmp_path / "principal.env"

    result = _run(
        ["./scripts/ai-principal-runtime.sh", "record-launch", "agy"],
        env={
            "AI_AUTO_PRINCIPAL_EVIDENCE": str(evidence_file),
            "AI_AUTO_PRINCIPAL_LAUNCHER": "1",
        },
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == str(evidence_file)
    text = evidence_file.read_text(encoding="utf-8")
    assert "principal_runtime=gemini" in text
    assert "execution_mode=principal" in text
    assert "source=ai-auto-principal-launcher" in text
    assert f"workspace={ROOT}" in text


def test_launcher_records_repo_root_workspace_from_subdirectory(tmp_path: Path) -> None:
    # Recording from a subdirectory must anchor workspace to the repo root so the
    # runner (which derives the root via git) accepts the evidence as matched.
    evidence_file = tmp_path / "principal.env"
    subdir = ROOT / "scripts"
    merged_env = os.environ.copy()
    merged_env.update(
        {
            "AI_AUTO_PRINCIPAL_EVIDENCE": str(evidence_file),
            "AI_AUTO_PRINCIPAL_LAUNCHER": "1",
        }
    )
    result = subprocess.run(
        [str(ROOT / "scripts" / "ai-principal-runtime.sh"), "record-launch", "claude"],
        cwd=subdir,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    text = evidence_file.read_text(encoding="utf-8")
    assert f"workspace={ROOT}" in text
    assert f"workspace={subdir}" not in text


def test_principal_runtime_rejects_manual_execution_evidence(tmp_path: Path) -> None:
    result = _run(
        ["./scripts/ai-principal-runtime.sh", "record-launch", "claude"],
        env={"AI_AUTO_PRINCIPAL_EVIDENCE": str(tmp_path / "principal.env")},
    )

    assert result.returncode == 2
    assert "principal evidence can only be recorded" in result.stderr


def test_review_summary_accepts_claude_principal_rotation(tmp_path: Path) -> None:
    out_dir = tmp_path / "review-results"
    out_dir.mkdir()

    claude = out_dir / "claude-review.md"
    gemini = out_dir / "gemini-review.md"
    codex = out_dir / "codex-architect-fallback.md"
    codex_test = out_dir / "codex-test-fallback.md"
    codex_summary = out_dir / "codex-fallback-summary.md"

    claude.write_text("# Claude Review\n\nSkipped: Claude is the active principal runtime.\n", encoding="utf-8")
    _write_review(gemini, "approve_with_notes")
    _write_review(codex, "approve_with_notes", "## Reviewer Boundary\n\nCodex reviewer coverage for active principal claude.\n")
    codex_test.write_text("# Codex Test\n\n## Verdict\n\nmissing\n", encoding="utf-8")
    codex_summary.write_text("# Codex Principal-Rotation Review\n\n## Status\n\nprincipal_rotation\n", encoding="utf-8")

    summary = out_dir / "review-summary-20260531T000000.md"
    summary.write_text(
        f"""# AI Review Summary

## Inputs

- Context: {tmp_path / "missing-context.md"}
- Claude result: {claude}
- Gemini result: {gemini}
- Codex architect fallback: {codex}
- Codex test fallback: {codex_test}
- Codex fallback summary: {codex_summary}
- Split context manifest: none
""",
        encoding="utf-8",
    )

    result = _run(
        ["./scripts/summarize-ai-reviews.sh"],
        env={
            "AI_AUTO_PRINCIPAL": "claude",
            "RESULT_DIR": str(out_dir),
            "OUT_DIR": str(out_dir),
        },
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "- decision: proceed" in result.stdout
    assert "- reason: principal_rotation_approval" in result.stdout
    assert "- coverage: principal_rotation" in result.stdout
    assert "- active_principal: claude" in result.stdout
    assert "missing_or_unusable_reviewers: none" in result.stdout


def test_review_summary_accepts_gemini_principal_rotation(tmp_path: Path) -> None:
    out_dir = tmp_path / "review-results"
    out_dir.mkdir()

    claude = out_dir / "claude-review.md"
    gemini = out_dir / "gemini-review.md"
    codex = out_dir / "codex-architect-fallback.md"
    codex_test = out_dir / "codex-test-fallback.md"
    codex_summary = out_dir / "codex-fallback-summary.md"

    _write_review(claude, "approve_with_notes")
    gemini.write_text("# Gemini Review\n\nSkipped: Gemini is the active principal runtime.\n", encoding="utf-8")
    _write_review(codex, "approve_with_notes", "## Reviewer Boundary\n\nCodex reviewer coverage for active principal gemini.\n")
    codex_test.write_text("# Codex Test\n\n## Verdict\n\nmissing\n", encoding="utf-8")
    codex_summary.write_text("# Codex Principal-Rotation Review\n\n## Status\n\nprincipal_rotation\n", encoding="utf-8")

    summary = out_dir / "review-summary-20260531T000000.md"
    summary.write_text(
        f"""# AI Review Summary

## Inputs

- Context: {tmp_path / "missing-context.md"}
- Claude result: {claude}
- Gemini result: {gemini}
- Codex architect fallback: {codex}
- Codex test fallback: {codex_test}
- Codex fallback summary: {codex_summary}
- Split context manifest: none
""",
        encoding="utf-8",
    )

    result = _run(
        ["./scripts/summarize-ai-reviews.sh"],
        env={
            "AI_AUTO_PRINCIPAL": "gemini",
            "RESULT_DIR": str(out_dir),
            "OUT_DIR": str(out_dir),
        },
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "- decision: proceed" in result.stdout
    assert "- reason: principal_rotation_approval" in result.stdout
    assert "- coverage: principal_rotation" in result.stdout
    assert "- active_principal: gemini" in result.stdout
    assert "missing_or_unusable_reviewers: none" in result.stdout


def test_principal_rotation_request_changes_blocks_before_degraded(tmp_path: Path) -> None:
    out_dir = tmp_path / "review-results"
    out_dir.mkdir()

    claude = out_dir / "claude-review.md"
    gemini = out_dir / "gemini-review.md"
    codex = out_dir / "codex-architect-fallback.md"
    codex_test = out_dir / "codex-test-fallback.md"
    codex_summary = out_dir / "codex-fallback-summary.md"

    claude.write_text("# Claude Review\n\nSkipped: Claude is the active principal runtime.\n", encoding="utf-8")
    _write_review(gemini, "request_changes")
    _write_review(codex, "approve_with_notes", "## Reviewer Boundary\n\nCodex reviewer coverage for active principal claude.\n")
    codex_test.write_text("# Codex Test\n\n## Verdict\n\nmissing\n", encoding="utf-8")
    codex_summary.write_text("# Codex Principal-Rotation Review\n\n## Status\n\nprincipal_rotation\n", encoding="utf-8")

    summary = out_dir / "review-summary-20260531T000000.md"
    summary.write_text(
        f"""# AI Review Summary

## Inputs

- Context: {tmp_path / "missing-context.md"}
- Claude result: {claude}
- Gemini result: {gemini}
- Codex architect fallback: {codex}
- Codex test fallback: {codex_test}
- Codex fallback summary: {codex_summary}
- Split context manifest: none
""",
        encoding="utf-8",
    )

    result = _run(
        ["./scripts/summarize-ai-reviews.sh"],
        env={
            "AI_AUTO_PRINCIPAL": "claude",
            "RESULT_DIR": str(out_dir),
            "OUT_DIR": str(out_dir),
        },
    )

    assert result.returncode == 1
    assert "- decision: revise" in result.stdout
    assert "- reason: reviewer_requested_changes" in result.stdout
    assert "- coverage: principal_rotation" in result.stdout


def test_codex_principal_subagent_substitute_is_degraded_coverage(tmp_path: Path) -> None:
    out_dir = tmp_path / "review-results"
    out_dir.mkdir()

    claude = out_dir / "claude-review.md"
    gemini = out_dir / "gemini-review.md"
    codex = out_dir / "codex-architect-fallback.md"
    codex_test = out_dir / "codex-test-fallback.md"
    codex_summary = out_dir / "codex-fallback-summary.md"

    claude.write_text("# Claude Review\n\nSkipped: Claude usage limit.\n", encoding="utf-8")
    _write_review(gemini, "approve_with_notes")
    _write_review(codex, "approve_with_notes", "## Principal Subagent Substitute Boundary\n\nCodex principal-subagent substitute coverage for Claude.\n")
    codex_test.write_text("# Codex Test\n\n## Verdict\n\nmissing\n", encoding="utf-8")
    codex_summary.write_text("# Principal Subagent Substitute Review\n\n## Status\n\nprincipal_subagent_substitute\n", encoding="utf-8")
    _write_review_manifest(out_dir, tmp_path, claude, gemini, codex, codex_test, codex_summary)

    result = _run(
        ["./scripts/summarize-ai-reviews.sh"],
        env={"RESULT_DIR": str(out_dir), "OUT_DIR": str(out_dir)},
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "- decision: proceed_degraded" in result.stdout
    assert "- reason: principal_subagent_substitute_approval" in result.stdout
    assert "- coverage: principal_subagent_substitute" in result.stdout
    assert "- trust: degraded" in result.stdout
    assert "missing_or_unusable_reviewers: none" in result.stdout


def test_codex_principal_two_substitutes_are_degraded_coverage(tmp_path: Path) -> None:
    out_dir = tmp_path / "review-results"
    out_dir.mkdir()

    claude = out_dir / "claude-review.md"
    gemini = out_dir / "gemini-review.md"
    codex = out_dir / "codex-architect-fallback.md"
    codex_test = out_dir / "codex-test-fallback.md"
    codex_summary = out_dir / "codex-fallback-summary.md"

    claude.write_text("# Claude Review\n\nSkipped: Claude usage limit.\n", encoding="utf-8")
    gemini.write_text("# Gemini Review\n\nSkipped: Gemini unavailable.\n", encoding="utf-8")
    _write_review(codex, "approve_with_notes", "## Principal Subagent Substitute Boundary\n\nCodex substitute coverage for Claude.\n")
    _write_review(codex_test, "approve", "## Principal Subagent Substitute Boundary\n\nCodex substitute coverage for Gemini.\n")
    codex_summary.write_text("# Principal Subagent Substitute Review\n\n## Status\n\nprincipal_subagent_substitute\n", encoding="utf-8")
    _write_review_manifest(out_dir, tmp_path, claude, gemini, codex, codex_test, codex_summary)

    result = _run(
        ["./scripts/summarize-ai-reviews.sh"],
        env={"RESULT_DIR": str(out_dir), "OUT_DIR": str(out_dir)},
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "- decision: proceed_degraded" in result.stdout
    assert "- coverage: principal_subagent_substitute" in result.stdout
    assert "- trust: degraded" in result.stdout
    assert "missing_or_unusable_reviewers: none" in result.stdout


def test_claude_principal_substitute_rotation_is_degraded(tmp_path: Path) -> None:
    out_dir = tmp_path / "review-results"
    out_dir.mkdir()

    claude = out_dir / "claude-review.md"
    gemini = out_dir / "gemini-review.md"
    codex = out_dir / "codex-architect-fallback.md"
    codex_test = out_dir / "codex-test-fallback.md"
    codex_summary = out_dir / "codex-fallback-summary.md"

    claude.write_text("# Claude Review\n\nSkipped: Claude is active principal.\n", encoding="utf-8")
    gemini.write_text("# Gemini Review\n\nSkipped: Gemini unavailable.\n", encoding="utf-8")
    _write_review(codex, "approve_with_notes", "## Reviewer Boundary\n\nCodex reviewer coverage for active principal claude.\n")
    _write_review(codex_test, "approve", "## Principal Subagent Substitute Boundary\n\nClaude principal-subagent substitute coverage for Gemini.\n")
    codex_summary.write_text("# Principal Subagent Substitute Review\n\n## Status\n\nprincipal_subagent_substitute\n", encoding="utf-8")
    _write_review_manifest(out_dir, tmp_path, claude, gemini, codex, codex_test, codex_summary)

    result = _run(
        ["./scripts/summarize-ai-reviews.sh"],
        env={"AI_AUTO_PRINCIPAL": "claude", "RESULT_DIR": str(out_dir), "OUT_DIR": str(out_dir)},
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "- decision: proceed_degraded" in result.stdout
    assert "- reason: principal_rotation_with_substitute_approval" in result.stdout
    assert "- coverage: principal_rotation_with_substitute" in result.stdout
    assert "- trust: degraded" in result.stdout
    assert "missing_or_unusable_reviewers: none" in result.stdout


def test_gemini_principal_substitute_keeps_architect_lane_distinct(tmp_path: Path) -> None:
    out_dir = tmp_path / "review-results"
    out_dir.mkdir()

    claude = out_dir / "claude-review.md"
    gemini = out_dir / "gemini-review.md"
    codex = out_dir / "codex-architect-fallback.md"
    codex_test = out_dir / "codex-test-fallback.md"
    codex_summary = out_dir / "codex-fallback-summary.md"

    claude.write_text("# Claude Review\n\nSkipped: Claude unavailable.\n", encoding="utf-8")
    gemini.write_text("# Gemini Review\n\nSkipped: Gemini is active principal.\n", encoding="utf-8")
    _write_review(codex, "approve", "## Principal Subagent Substitute Boundary\n\nGemini principal-subagent substitute coverage for Claude.\n")
    _write_review(codex_test, "approve_with_notes", "## Reviewer Boundary\n\nCodex reviewer coverage for active principal gemini.\n")
    codex_summary.write_text("# Principal Subagent Substitute Review\n\n## Status\n\nprincipal_subagent_substitute\n", encoding="utf-8")
    _write_review_manifest(out_dir, tmp_path, claude, gemini, codex, codex_test, codex_summary)

    result = _run(
        ["./scripts/summarize-ai-reviews.sh"],
        env={"AI_AUTO_PRINCIPAL": "gemini", "RESULT_DIR": str(out_dir), "OUT_DIR": str(out_dir)},
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "- decision: proceed_degraded" in result.stdout
    assert "- reason: principal_rotation_with_substitute_approval" in result.stdout
    assert "- coverage: principal_rotation_with_substitute" in result.stdout
    assert "- trust: degraded" in result.stdout
    assert "missing_or_unusable_reviewers: none" in result.stdout


def test_principal_substitute_request_changes_blocks(tmp_path: Path) -> None:
    out_dir = tmp_path / "review-results"
    out_dir.mkdir()

    claude = out_dir / "claude-review.md"
    gemini = out_dir / "gemini-review.md"
    codex = out_dir / "codex-architect-fallback.md"
    codex_test = out_dir / "codex-test-fallback.md"
    codex_summary = out_dir / "codex-fallback-summary.md"

    claude.write_text("# Claude Review\n\nSkipped: Claude usage limit.\n", encoding="utf-8")
    _write_review(gemini, "approve")
    _write_review(codex, "request_changes", "## Principal Subagent Substitute Boundary\n\nCodex substitute coverage for Claude.\n")
    codex_test.write_text("# Codex Test\n\n## Verdict\n\nmissing\n", encoding="utf-8")
    codex_summary.write_text("# Principal Subagent Substitute Review\n\n## Status\n\nprincipal_subagent_substitute\n", encoding="utf-8")
    _write_review_manifest(out_dir, tmp_path, claude, gemini, codex, codex_test, codex_summary)

    result = _run(
        ["./scripts/summarize-ai-reviews.sh"],
        env={"RESULT_DIR": str(out_dir), "OUT_DIR": str(out_dir)},
    )

    assert result.returncode == 1
    assert "- decision: review_manually" in result.stdout
    assert "- reason: principal_subagent_substitute_requested_changes" in result.stdout


def test_review_runner_exercises_claude_principal_rotation(tmp_path: Path) -> None:
    fake_adapter = tmp_path / "fake-adapter.sh"
    fake_adapter.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [ -z "${output}" ]; then
  exit 2
fi
cat > "${output}" <<'REVIEW'
# Codex Principal Review

## Verdict

approve_with_notes

## Findings

No blocking findings.

## Direct File Inspection

- scripts/run-ai-reviews.sh

## Reviewer Boundary

Codex reviewer coverage for active principal claude.
REVIEW
""",
        encoding="utf-8",
    )
    fake_adapter.chmod(0o755)

    out_dir = tmp_path / "review-results"
    evidence_file = tmp_path / "principal.env"
    evidence_file.write_text(
        f"principal_runtime=claude\nexecution_mode=principal\nsource=ai-auto-principal-launcher\nworkspace={ROOT}\n",
        encoding="utf-8",
    )
    result = _run(
        ["./scripts/run-ai-reviews.sh"],
        env={
            "AI_AUTO_PRINCIPAL": "claude",
            "AI_AUTO_PRINCIPAL_EVIDENCE": str(evidence_file),
            "AI_MODEL_DISCOVERY": "0",
            "CONTEXT_DIR": str(tmp_path / "review-context"),
            "OUT_DIR": str(out_dir),
            "PROMPT_DIR": str(tmp_path / "review-prompts"),
            "REVIEW_STATE_DIR": str(tmp_path / "reviewer-state"),
            "EXTERNAL_REVIEW_DIR": str(tmp_path / "external-review"),
            "RUNTIME_ADAPTER_SCRIPT": str(fake_adapter),
            "RUN_GEMINI_REVIEW": "0",
        },
    )

    assert result.returncode == 0, result.stdout + result.stderr
    codex_reviews = sorted(out_dir.glob("codex-architect-fallback-*.md"))
    assert codex_reviews, result.stdout
    text = codex_reviews[-1].read_text(encoding="utf-8")
    assert "Codex reviewer coverage for active principal claude" in text


def _write_fake_adapter(tmp_path: Path) -> Path:
    fake_adapter = tmp_path / "fake-adapter.sh"
    fake_adapter.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "${output}" ] || exit 2
cat > "${output}" <<'REVIEW'
# Codex Principal Review

## Verdict

approve_with_notes

## Findings

No blocking findings.

## Direct File Inspection

- scripts/run-ai-reviews.sh
REVIEW
""",
        encoding="utf-8",
    )
    fake_adapter.chmod(0o755)
    return fake_adapter


def _principal_run_env(tmp_path: Path, **overrides: str) -> dict[str, str]:
    env = {
        "AI_MODEL_DISCOVERY": "0",
        "CONTEXT_DIR": str(tmp_path / "review-context"),
        "OUT_DIR": str(tmp_path / "review-results"),
        "PROMPT_DIR": str(tmp_path / "review-prompts"),
        "REVIEW_STATE_DIR": str(tmp_path / "reviewer-state"),
        "EXTERNAL_REVIEW_DIR": str(tmp_path / "external-review"),
        "RUNTIME_ADAPTER_SCRIPT": str(_write_fake_adapter(tmp_path)),
        "RUN_GEMINI_REVIEW": "0",
    }
    env.update(overrides)
    return env


def test_valid_launcher_evidence_selects_principal_when_env_unset(tmp_path: Path) -> None:
    evidence_file = tmp_path / "principal.env"
    evidence_file.write_text(
        f"principal_runtime=claude\nexecution_mode=principal\nsource=ai-auto-principal-launcher\nworkspace={ROOT}\n",
        encoding="utf-8",
    )
    result = _run(
        ["./scripts/run-ai-reviews.sh"],
        env=_principal_run_env(
            tmp_path,
            AI_AUTO_PRINCIPAL="",  # unset/empty: evidence must drive selection
            AI_AUTO_PRINCIPAL_EVIDENCE=str(evidence_file),
        ),
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "selected from launcher evidence" in result.stdout
    # Claude principal => Claude self-review skipped, codex covers the lane.
    assert "active principal cannot self-review" in result.stdout


def test_explicit_principal_contradicting_evidence_fails_closed(tmp_path: Path) -> None:
    evidence_file = tmp_path / "principal.env"
    evidence_file.write_text(
        f"principal_runtime=claude\nexecution_mode=principal\nsource=ai-auto-principal-launcher\nworkspace={ROOT}\n",
        encoding="utf-8",
    )
    result = _run(
        ["./scripts/run-ai-reviews.sh"],
        env=_principal_run_env(
            tmp_path,
            AI_AUTO_PRINCIPAL="codex",
            AI_AUTO_PRINCIPAL_EVIDENCE=str(evidence_file),
        ),
    )
    assert result.returncode == 2
    assert "contradicts launcher evidence" in result.stderr


def test_default_to_codex_without_declaration_emits_visible_notice(tmp_path: Path) -> None:
    result = _run(
        ["./scripts/run-ai-reviews.sh"],
        env=_principal_run_env(
            tmp_path,
            AI_AUTO_PRINCIPAL="",
            AI_AUTO_PRINCIPAL_EVIDENCE=str(tmp_path / "missing-principal.env"),
            RUN_CLAUDE_REVIEW="0",
        ),
    )
    assert "defaulted to codex" in result.stdout


def test_review_runner_requires_external_principal_evidence(tmp_path: Path) -> None:
    result = _run(
        ["./scripts/run-ai-reviews.sh"],
        env={
            "AI_AUTO_PRINCIPAL": "claude",
            # Isolate to a tmp path that is never created so the "missing
            # evidence" case is hermetic and does not depend on a developer's
            # local .omx/state/principal-runtime/current.env.
            "AI_AUTO_PRINCIPAL_EVIDENCE": str(tmp_path / "missing-principal.env"),
            "AI_MODEL_DISCOVERY": "0",
            "CONTEXT_DIR": str(tmp_path / "review-context"),
            "OUT_DIR": str(tmp_path / "review-results"),
            "PROMPT_DIR": str(tmp_path / "review-prompts"),
            "REVIEW_STATE_DIR": str(tmp_path / "reviewer-state"),
            "EXTERNAL_REVIEW_DIR": str(tmp_path / "external-review"),
        },
    )

    assert result.returncode == 2
    assert "principal_unavailable" in result.stderr
    assert "principal evidence file is missing" in result.stderr


def test_review_runner_rejects_manual_principal_evidence(tmp_path: Path) -> None:
    evidence_file = tmp_path / "principal.env"
    evidence_file.write_text("principal_runtime=claude\nexecution_mode=principal\n", encoding="utf-8")

    result = _run(
        ["./scripts/run-ai-reviews.sh"],
        env={
            "AI_AUTO_PRINCIPAL": "claude",
            "AI_AUTO_PRINCIPAL_EVIDENCE": str(evidence_file),
            "AI_MODEL_DISCOVERY": "0",
            "CONTEXT_DIR": str(tmp_path / "review-context"),
            "OUT_DIR": str(tmp_path / "review-results"),
            "PROMPT_DIR": str(tmp_path / "review-prompts"),
            "REVIEW_STATE_DIR": str(tmp_path / "reviewer-state"),
            "EXTERNAL_REVIEW_DIR": str(tmp_path / "external-review"),
        },
    )

    assert result.returncode == 2
    assert "evidence file is not launcher-owned" in result.stderr


def test_review_runner_records_principal_and_self_review_guards() -> None:
    text = (ROOT / "scripts" / "run-ai-reviews.sh").read_text(encoding="utf-8")

    assert "Active principal: ${ACTIVE_PRINCIPAL}" in text
    assert "Reviewer runtimes: ${PRINCIPAL_REVIEWERS}" in text
    assert 'if ! ACTIVE_PRINCIPAL="$(normalize_principal_runtime)"; then' in text
    assert "principal_unavailable" in text
    # E (global mode): the generated external runner invokes the engine scripts by ABSOLUTE
    # engine path (baked from ${RUN_AI_REVIEWS_SCRIPT_DIR}), never pwd-relative ./scripts/...
    # which is absent in a globalized zero-framework project.
    assert 'AI_AUTO_PRINCIPAL="\\${AI_AUTO_PRINCIPAL}" RESULT_DIR="\\${OUT_DIR}" OUT_DIR="\\${OUT_DIR}" "${RUN_AI_REVIEWS_SCRIPT_DIR}/summarize-ai-reviews.sh"' in text
    assert '"${RUN_AI_REVIEWS_SCRIPT_DIR}/run-ai-reviews.sh"' in text
    assert 'if [ "${ACTIVE_PRINCIPAL}" = "claude" ]; then' in text
    assert 'if [ "${ACTIVE_PRINCIPAL}" = "gemini" ]; then' in text
    assert "principal_rotation" in text
