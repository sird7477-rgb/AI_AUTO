import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    (repo / "scripts").mkdir(parents=True)
    shutil.copy(ROOT / "scripts" / "collect-review-context.sh", repo / "scripts" / "collect-review-context.sh")
    subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)
    return repo


def _run(repo: Path) -> str:
    env = {
        **os.environ,
        "OUT_DIR": str(repo / ".omx" / "review-context"),
        "REVIEW_CONTEXT_DETAIL": "full",
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


def _write_unit(repo: Path, content: str) -> None:
    (repo / ".omx" / "micro").mkdir(parents=True, exist_ok=True)
    (repo / ".omx" / "micro" / "current.json").write_text(content, encoding="utf-8")


def test_micro_work_audit_reports_ready_and_flags_non_goal_leak(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    (repo / "src").mkdir()
    (repo / "docs").mkdir()
    _write_unit(
        repo,
        '{"id":"u","goal":"g","scope_paths":["src"],"smallest_useful_wedge":"w",'
        '"non_goals":["docs"],"required_evidence":["verify"],"completion_criteria":["done"]}\n',
    )
    (repo / "src" / "a.py").write_text("x\n", encoding="utf-8")
    (repo / "docs" / "leak.md").write_text("y\n", encoding="utf-8")

    out = _run(repo)
    assert "## MicroWork Audit" in out
    assert "audit_status: report_only" in out
    assert "micro_work_status: ready" in out
    # docs/ is an explicit non-goal, so the changed docs file is reported as a leak.
    assert "docs/leak.md" in out
    assert "non_goal_leak:" in out


def test_micro_work_audit_reports_incomplete_and_absent(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    _write_unit(repo, '{"id":"u","goal":"g"}\n')
    incomplete = _run(repo)
    assert "micro_work_status: incomplete_micro_unit" in incomplete
    assert "missing_fields:" in incomplete

    (repo / ".omx" / "micro" / "current.json").unlink()
    absent = _run(repo)
    assert "micro_work_status: no_micro_unit" in absent


def test_micro_work_audit_handles_spaces_and_non_object(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    (repo / "src").mkdir()
    _write_unit(
        repo,
        '{"id":"u","goal":"g","scope_paths":["src"],"smallest_useful_wedge":"w",'
        '"non_goals":["docs"],"required_evidence":["verify"],"completion_criteria":["done"]}\n',
    )
    # A changed path with a space must stay intact (not split) in the audit.
    (repo / "a file.md").write_text("x\n", encoding="utf-8")
    out = _run(repo)
    assert "micro_work_status: ready" in out
    assert "a file.md" in out

    # A non-object micro-unit must not crash review-context generation.
    _write_unit(repo, "[]\n")
    out2 = _run(repo)
    assert "micro_work_status: invalid_micro_unit" in out2
