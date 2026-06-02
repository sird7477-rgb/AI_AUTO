import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN_SCRIPT = ROOT / "scripts" / "discover-ai-models.sh"
TEMPLATE_SCRIPT = ROOT / "templates" / "automation-base" / "scripts" / "discover-ai-models.sh"
CONTEXT_SCRIPT = ROOT / "scripts" / "collect-review-context.sh"
TEMPLATE_CONTEXT_SCRIPT = ROOT / "templates" / "automation-base" / "scripts" / "collect-review-context.sh"

# Phase 0 (ST-P1-22) is observe-only: the routing report records the
# lane-to-class contract per principal but must not change routing behavior or
# claim completion authority. These strings are the locked contract.
# Bare identifiers (no backticks): inside the report heredoc the backticks are
# backslash-escaped, so match the rendered identifier substrings instead.
CONTRACT_STRINGS = (
    "## Principal Class Lanes (observe-only)",
    "fast_scan",
    "low_cost_impl",
    "standard_impl",
    "frontier_review",
    "carry no completion authority",
    "gemini -m forbidden",
    "class_unavailable",
)


def test_both_discover_copies_carry_observe_only_lane_contract() -> None:
    main_text = MAIN_SCRIPT.read_text(encoding="utf-8")
    template_text = TEMPLATE_SCRIPT.read_text(encoding="utf-8")
    for needle in CONTRACT_STRINGS:
        assert needle in main_text, f"missing in main script: {needle}"
        assert needle in template_text, f"missing in template script: {needle}"


def _run_discovery(repo: Path) -> str:
    out_dir = repo / ".omx" / "model-routing"
    env = {
        **os.environ,
        "AI_MODEL_DISCOVERY_DIR": str(out_dir),
        "AI_MODEL_DISCOVERY_REFRESH": "1",
    }
    subprocess.run(
        ["bash", str(MAIN_SCRIPT)],
        cwd=repo,
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    return (out_dir / "latest.md").read_text(encoding="utf-8")


def test_report_renders_lane_block_for_all_three_principals(tmp_path: Path) -> None:
    report = _run_discovery(tmp_path)

    assert "## Principal Class Lanes (observe-only)" in report
    # One observe-only row per principal, regardless of which CLIs are installed.
    lane_section = report.split("## Principal Class Lanes (observe-only)", 1)[1]
    lane_section = lane_section.split("## Tuning Evidence", 1)[0]
    assert "| codex |" in lane_section
    assert "| claude |" in lane_section
    assert "| gemini |" in lane_section
    # Gemini stays honestly class-fixed on the agy-only path.
    assert "class_unavailable" in lane_section
    assert "gemini -m forbidden" in lane_section
    # Observe-only: routing records never carry completion authority.
    assert "carry no completion authority" in report


DOC = ROOT / "docs" / "AI_MODEL_ROUTING.md"
TEMPLATE_DOC = ROOT / "templates" / "automation-base" / "docs" / "AI_MODEL_ROUTING.md"

# Phase 1 (ST-P1-22): the low_cost_impl lane is a separate, guardrail-gated,
# non-authoritative bounded lane. docs/AI_MODEL_ROUTING.md is its source of truth.
LOW_COST_CONTRACT = (
    "### `low_cost_impl` lane contract",
    "separate",
    "downgrade",
    "executor-low.toml",
    "rewrite-rate",
    "completion authority",
    "Gemini has no `low_cost_impl`",
)


def test_low_cost_impl_contract_present_and_synced() -> None:
    main_text = DOC.read_text(encoding="utf-8")
    template_text = TEMPLATE_DOC.read_text(encoding="utf-8")
    for needle in LOW_COST_CONTRACT:
        assert needle in main_text, f"missing in docs/AI_MODEL_ROUTING.md: {needle}"
        assert needle in template_text, f"missing in template doc: {needle}"


RECORDER = ROOT / "scripts" / "record-lane-decision.py"
TEMPLATE_RECORDER = ROOT / "templates" / "automation-base" / "scripts" / "record-lane-decision.py"


def _record(log: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["python3", str(RECORDER), "--log", str(log), *args],
        capture_output=True,
        text=True,
    )


def test_lane_decision_recorder_appends_valid_record(tmp_path: Path) -> None:
    log = tmp_path / "lane-decisions.tsv"
    result = _record(
        log,
        "--principal", "codex",
        "--lane", "low_cost_impl",
        "--role", "executor-low",
        "--requested-class", "fast",
        "--resolved-model", "gpt-5.3-codex-spark",
        "--model-source", "omx-contract",
        "--model-class-applied", "true",
        "--confidence", "medium",
    )
    assert result.returncode == 0, result.stderr
    lines = log.read_text(encoding="utf-8").splitlines()
    assert lines[0].split("\t") == [
        "timestamp", "principal", "lane", "role", "requested_class",
        "resolved_model", "model_source", "model_class_applied", "reason",
        "fallback", "confidence",
    ]
    assert lines[1].split("\t")[1:3] == ["codex", "low_cost_impl"]


def test_lane_decision_requires_reason_when_class_not_applied(tmp_path: Path) -> None:
    result = _record(
        tmp_path / "ld.tsv",
        "--principal", "gemini",
        "--lane", "fast_scan",
        "--requested-class", "fast",
        "--model-class-applied", "false",
        "--confidence", "low",
    )
    assert result.returncode == 2
    assert "reason is required" in result.stderr


def test_lane_decision_rejects_unknown_enum_values(tmp_path: Path) -> None:
    result = _record(
        tmp_path / "ld.tsv",
        "--principal", "openai",
        "--lane", "low_cost_impl",
        "--requested-class", "turbo",
        "--model-class-applied", "true",
        "--confidence", "medium",
    )
    assert result.returncode == 2


def test_lane_decision_recorder_copies_are_identical() -> None:
    assert RECORDER.read_text(encoding="utf-8") == TEMPLATE_RECORDER.read_text(encoding="utf-8")


def _run_review_context(repo: Path, principal: str, shape: str) -> str:
    repo.mkdir(parents=True, exist_ok=True)
    (repo / "scripts").mkdir(parents=True, exist_ok=True)
    (repo / "scripts" / "collect-review-context.sh").write_text(
        CONTEXT_SCRIPT.read_text(encoding="utf-8"), encoding="utf-8"
    )
    subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)
    env = {
        **os.environ,
        "OUT_DIR": str(repo / ".omx" / "review-context"),
        "AI_AUTO_PRINCIPAL": principal,
        "MODEL_ROUTING_INPUT_SHAPE": shape,
    }
    subprocess.run(
        ["bash", "scripts/collect-review-context.sh"],
        cwd=repo,
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    return (repo / ".omx" / "review-context" / "latest-review-context.md").read_text(encoding="utf-8")


def test_routing_audit_is_report_only_and_flags_fast_lane_candidate(tmp_path: Path) -> None:
    context = _run_review_context(tmp_path / "codex", "codex", "lookup")

    assert "## Model Routing Lane Audit" in context
    audit = context.split("## Model Routing Lane Audit", 1)[1].split("## Diff", 1)[0]
    assert "audit_status: report_only" in audit
    assert "active_principal: codex" in audit
    assert "recommended_lane: fast_scan" in audit
    assert "missed_fast_lane_opportunity: candidate" in audit
    # The audit must never claim authority or auto-reroute.
    assert "runtime_lane_added: false" in audit
    assert "routing_authority: none" in audit


def test_routing_audit_reports_gemini_class_fixed_honestly(tmp_path: Path) -> None:
    context = _run_review_context(tmp_path / "gemini", "gemini", "lookup")

    audit = context.split("## Model Routing Lane Audit", 1)[1].split("## Diff", 1)[0]
    assert "active_principal: gemini" in audit
    # Gemini is invoked only via agy and stays class-fixed; no fake opportunity.
    assert "missed_fast_lane_opportunity: fast_lane_unavailable" in audit
    assert "class_unavailable" in audit


def test_routing_audit_normalizes_input_shape_case_and_whitespace(tmp_path: Path) -> None:
    context = _run_review_context(tmp_path / "norm", "codex", " LOOKUP ")

    audit = context.split("## Model Routing Lane Audit", 1)[1].split("## Diff", 1)[0]
    # Uppercase + surrounding whitespace must still map to the fast lane.
    assert "recommended_lane: fast_scan" in audit


def test_review_context_audit_present_in_both_copies() -> None:
    for script in (CONTEXT_SCRIPT, TEMPLATE_CONTEXT_SCRIPT):
        text = script.read_text(encoding="utf-8")
        assert "write_model_routing_lane_audit" in text
        assert "## Model Routing Lane Audit" in text
        assert "routing_authority: none" in text
