import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKS = ("DATA", "DEPLOYMENT", "OBSERVABILITY", "PERFORMANCE", "SECURITY", "UI")


def _prepare_repo(repo: Path) -> None:
    (repo / "scripts").mkdir(parents=True)
    (repo / "docs").mkdir()
    shutil.copy(ROOT / "scripts" / "collect-review-context.sh", repo / "scripts" / "collect-review-context.sh")
    for pack in PACKS:
        (repo / "docs" / f"{pack}_COMPLETION.md").write_text(f"# {pack.title()} Completion Pack\n", encoding="utf-8")
    subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)


def _run_context(repo: Path, input_shape: str = "") -> str:
    env = {
        **os.environ,
        "OUT_DIR": str(repo / ".omx" / "review-context"),
        "COMPLETION_PACK_INPUT_SHAPE": input_shape,
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


def test_completion_pack_routing_audit_reports_inventory_and_triggers(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)
    (repo / "docs" / "DEPLOYMENT_COMPLETION.md").write_text("# Deployment Completion Pack\nupdate\n", encoding="utf-8")

    context = _run_context(repo, "security_review")

    assert "## Completion Pack Routing Audit" in context
    assert "audit_status: report_only" in context
    assert "packs_present: data,deployment,observability,performance,security,ui" in context
    assert "explicit_trigger: security_completion" in context
    assert "- deployment_completion: docs/DEPLOYMENT_COMPLETION.md" in context
    assert "runtime_lane_added: false" in context


def test_completion_pack_docs_generation_is_reference_lens_only(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)

    context = _run_context(repo, "docs_generation_lens")

    assert "explicit_trigger: reference_lens:not_completion_pack" in context
    assert "runtime_lane_added: false" in context
