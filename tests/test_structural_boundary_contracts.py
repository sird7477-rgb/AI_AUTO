import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _target_snapshot(root: Path) -> dict[str, tuple[str, str]]:
    snapshot: dict[str, tuple[str, str]] = {}
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if relative.parts and relative.parts[0] == ".git":
            continue
        if path.is_file():
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            snapshot[relative.as_posix()] = ("file", digest)
        elif path.is_symlink():
            snapshot[relative.as_posix()] = ("symlink", path.readlink().as_posix())
        elif path.is_dir():
            snapshot[relative.as_posix()] = ("dir", "")
    return snapshot


def test_verify_script_keeps_structural_audit_markers() -> None:
    verify = _read("scripts/verify.sh")

    required_markers = [
        "[verify] testing review summary decisions...",
        "[verify] testing GStack contract helper...",
        "[verify] testing ai-rebuild-plan...",
        "[verify] testing ai-split Python rebuild helpers...",
        "[verify] checking automation template sync...",
    ]

    for marker in required_markers:
        assert marker in verify


def test_rebuild_plan_reports_read_only_boundary_without_modifying_target(tmp_path: Path) -> None:
    target = tmp_path / "target"
    target.mkdir()
    subprocess.run(["git", "init"], cwd=target, check=True, stdout=subprocess.PIPE, text=True)

    for path in [
        "AGENTS.md",
        "docs/WORKFLOW.md",
        "scripts/verify.sh",
        "scripts/review-gate.sh",
    ]:
        file_path = target / path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text("placeholder\n", encoding="utf-8")

    before = _target_snapshot(target)
    proc = subprocess.run(
        [str(ROOT / "tools" / "ai-rebuild-plan"), str(target)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    after = _target_snapshot(target)

    assert after == before
    assert "리빌드 플랜 / rebuild plan: read-only diagnosis and planning only." in proc.stdout
    assert "리빌드 실행 / rebuild run: not started by this command." in proc.stdout
    assert "Do not treat a domain pack as execution approval." in proc.stdout
    assert "Stop here unless the user explicitly asks for 리빌드 실행 / rebuild run." in proc.stdout


def test_split_apply_requires_explicit_flag_and_completed_approval_gate(tmp_path: Path) -> None:
    target = tmp_path / "target"
    subprocess.run(["git", "init", "-q", str(target)], check=True)
    source = target / "src" / "monolith.py"
    source.parent.mkdir(parents=True)
    source.write_text("def helper():\n    return 1\n", encoding="utf-8")

    plan_path = target / ".omx" / "rebuild" / "split-plan.json"
    plan_path.parent.mkdir(parents=True)
    plan_path.write_text(
        json.dumps(
            {
                "version": 1,
                "mode": "python-top-level-symbol-split",
                "source_file": "src/monolith.py",
                "destination_file": "src/split.py",
                "symbols": ["helper"],
                "moves": [],
                "approved_execution_gate": {
                    "approved_by": "",
                    "approved_scope": "",
                    "reviewed_dry_run": False,
                    "rollback_path": "",
                    "post_apply_verification": [],
                },
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    no_flag = subprocess.run(
        [str(ROOT / "tools" / "ai-split-apply"), "--plan", str(plan_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    assert no_flag.returncode != 0
    assert "requires --execute-approved-plan" in no_flag.stderr

    no_gate = subprocess.run(
        [
            str(ROOT / "tools" / "ai-split-apply"),
            "--plan",
            str(plan_path),
            "--execute-approved-plan",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    assert no_gate.returncode != 0
    assert "approved_execution_gate.approved_by" in no_gate.stderr
