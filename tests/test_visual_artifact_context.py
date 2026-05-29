import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _prepare_repo(repo: Path) -> None:
    (repo / "scripts").mkdir(parents=True)
    (repo / "docs" / "plans" / "demo").mkdir(parents=True)
    shutil.copy(ROOT / "scripts" / "collect-review-context.sh", repo / "scripts" / "collect-review-context.sh")
    subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)


def _run_context(repo: Path, reviewed_specs: str = "", ambiguous: str = "0") -> str:
    env = {
        **os.environ,
        "OUT_DIR": str(repo / ".omx" / "review-context"),
        "VISUAL_HUMAN_REVIEWED_SPECS": reviewed_specs,
        "VISUAL_AMBIGUOUS_SOURCE": ambiguous,
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


def test_visual_artifact_audit_reports_excalidraw_spec_states(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)
    drawing = repo / "docs" / "plans" / "demo" / "overview.excalidraw"
    drawing.write_text('{"type":"excalidraw"}\n', encoding="utf-8")

    explanatory = _run_context(repo)
    assert "## Visual Artifact Audit" in explanatory
    assert "visual_warning:explanatory_only docs/plans/demo/overview.excalidraw" in explanatory

    spec = repo / "docs" / "plans" / "demo" / "overview-spec.md"
    spec.write_text("# Overview Spec\n", encoding="utf-8")
    unreviewed = _run_context(repo)
    assert "visual_warning:unreviewed_spec docs/plans/demo/overview.excalidraw -> docs/plans/demo/overview-spec.md" in unreviewed

    reviewed = _run_context(repo, "docs/plans/demo/overview-spec.md")
    assert "visual_ok:implementation_facing_spec docs/plans/demo/overview.excalidraw -> docs/plans/demo/overview-spec.md" in reviewed


def test_visual_artifact_audit_reports_stale_export_and_ambiguous_source(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)
    drawing = repo / "docs" / "plans" / "demo" / "overview.excalidraw"
    export = repo / "docs" / "plans" / "demo" / "overview.svg"
    export.write_text("<svg />\n", encoding="utf-8")
    drawing.write_text('{"type":"excalidraw","updated":true}\n', encoding="utf-8")
    os.utime(export, (1, 1))
    os.utime(drawing, (2, 2))

    context = _run_context(repo, ambiguous="1")

    assert "visual_warning:stale_export docs/plans/demo/overview.svg" in context
    assert "visual_warning:ambiguous_source_of_truth" in context
    assert "runtime_tool_install_required: false" in context
