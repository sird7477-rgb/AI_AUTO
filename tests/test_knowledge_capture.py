"""Behavior contract for the knowledge-capture helper (Stage 1A artifact harvest).

Locks the junk-vault defences the AI council required: the reuse-test gate, secret/path
redaction, sync_class routing, and idempotent dedup. knowledge-capture is an extensionless
executable, so it is exercised as a subprocess against a throwaway git repo.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
TOOL = REPO_ROOT / "tools" / "knowledge-capture"


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True,
                   capture_output=True, text=True)


def _commit(repo: Path, name: str, message: str) -> None:
    (repo / name).write_text(name, encoding="utf-8")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", message)


@pytest.fixture()
def repo(tmp_path: Path) -> Path:
    r = tmp_path / "proj"
    r.mkdir()
    _git(r, "init", "-q")
    _git(r, "config", "user.email", "t@e.com")
    _git(r, "config", "user.name", "t")
    return r


def _harvest(repo: Path) -> subprocess.CompletedProcess:
    return subprocess.run([str(TOOL), "harvest", "--repo", str(repo), "--write"],
                          capture_output=True, text=True)


def _drafts(repo: Path) -> list[Path]:
    d = repo / ".omx" / "knowledge" / "drafts"
    return sorted(d.glob("*.md")) if d.is_dir() else []


def test_complete_finding_is_drafted_and_sanitized(repo: Path) -> None:
    _commit(repo, "a", "fix\n\n"
            "Finding: createdb -T clones do not carry the on-disk filestore so images break\n"
            "Finding-Evidence: validate run + /mnt/z/secret/leak.txt observation\n"
            "Finding-Scope: any harness clone that serves a DB\n"
            "Finding-NotWhen: headless validation\n"
            "Finding-Surface: odoo\n"
            "Finding-Share: shareable")
    _harvest(repo)
    drafts = _drafts(repo)
    assert len(drafts) == 1
    text = drafts[0].read_text(encoding="utf-8")
    # reuse-test content present
    assert "Reusable rule:" in text and "Evidence:" in text and "Scope" in text
    # secret/path span redacted, never written verbatim
    assert "/mnt/z/secret" not in text
    assert "[redacted]" in text
    # explicit shareable routing honoured + sanitized marker set
    assert "sync_class: shareable_summary" in text
    assert "redaction_status: sanitized" in text


def test_reuse_test_gate_drops_incomplete_finding(repo: Path) -> None:
    # Missing Finding-Scope -> must be skipped, no draft (junk-vault defence).
    _commit(repo, "a", "tweak\n\nFinding: a rule\nFinding-Evidence: somewhere")
    result = _harvest(repo)
    assert _drafts(repo) == []
    assert "reuse-test" in (result.stdout + result.stderr)


def test_commit_without_trailer_is_ignored(repo: Path) -> None:
    _commit(repo, "a", "routine change with no finding trailer")
    _harvest(repo)
    assert _drafts(repo) == []


def test_default_share_is_local_private(repo: Path) -> None:
    _commit(repo, "a", "x\n\n"
            "Finding: prefer flock over lockfiles for harness readers\n"
            "Finding-Evidence: concurrency test\n"
            "Finding-Scope: harness reader/writer paths")
    _harvest(repo)
    drafts = _drafts(repo)
    assert len(drafts) == 1
    assert "sync_class: local_private" in drafts[0].read_text(encoding="utf-8")


def test_harvest_is_idempotent_across_multiple_drafts(repo: Path) -> None:
    for i in (1, 2, 3):
        _commit(repo, f"f{i}", f"change {i}\n\n"
                f"Finding: rule {i} about widget handling\n"
                f"Finding-Evidence: test {i}\n"
                f"Finding-Scope: module {i}")
    _harvest(repo)
    assert len(_drafts(repo)) == 3
    # Second run must add nothing (dedup reads every existing repeat_key, not just the first).
    second = _harvest(repo)
    assert len(_drafts(repo)) == 3
    assert "duplicate" in (second.stdout + second.stderr)
