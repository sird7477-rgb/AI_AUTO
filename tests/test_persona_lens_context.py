import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _prepare_repo(repo: Path) -> None:
    (repo / "scripts").mkdir(parents=True)
    (repo / "docs").mkdir()
    shutil.copy(ROOT / "scripts" / "collect-review-context.sh", repo / "scripts" / "collect-review-context.sh")
    subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo, check=True)
    subprocess.run(["git", "add", "scripts/collect-review-context.sh"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-m", "baseline"], cwd=repo, check=True, stdout=subprocess.DEVNULL)


def _run_context(repo: Path) -> str:
    env = {**os.environ, "OUT_DIR": str(repo / ".omx" / "review-context")}
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


def test_persona_lens_context_adds_strict_policy_for_review_gate_paths(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)
    (repo / "scripts" / "review-gate.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")

    context = _run_context(repo)

    assert "- active lenses: policy_compliance,review_taxonomy,test_strategy,integrator" in context
    assert "- integrator required: true" in context
    assert "- review gate policy: strict_gate" in context
    assert "scripts/review-gate.sh" in context


def test_persona_lens_context_keeps_docs_only_verify_only(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)
    (repo / "docs" / "note.md").write_text("note\n", encoding="utf-8")

    context = _run_context(repo)

    assert "- active lenses: docs_dx" in context
    assert "- integrator required: false" in context
    assert "- review gate policy: verify_only" in context


def test_persona_lens_context_promotes_ui_files_to_review_gate(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    _prepare_repo(repo)
    (repo / "app.tsx").write_text("export default function App() { return null }\n", encoding="utf-8")

    context = _run_context(repo)

    assert "- active lenses: browser_qa,design,integrator" in context
    assert "- integrator required: true" in context
    assert "- review gate policy: review_gate" in context
