"""Behavior contract for the READ path (Stage 2 worker + Stage 1B hook).

Locks the anti-poisoning guardrails: domain-gated retrieval returns capped slim POINTERS only and
fails GRACEFUL/OPEN on every miss. Both helpers are extensionless executables, exercised as
subprocesses against a self-contained fixture vault (no dependency on the real Obsidian vault).
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
RETRIEVE = REPO_ROOT / "tools" / "knowledge-retrieve"
HOOK = REPO_ROOT / "tools" / "ai-kb-retrieval-hook"


@pytest.fixture()
def vault(tmp_path: Path) -> Path:
    kb = tmp_path / "vault" / "Odoo19_Docs_KB"
    (kb / "slim").mkdir(parents=True)
    (kb / "00_Index.md").write_text(
        "# Index\n\n"
        "| topic | url | slim | raw | status |\n"
        "| --- | --- | --- | --- | --- |\n"
        "| Security (groups/ACL/record rules) | x | slim/security.md | raw/security.md | collected |\n"
        "| ORM reference | x | slim/orm-reference.md | raw/orm-reference.md | collected |\n",
        encoding="utf-8",
    )
    (kb / "slim" / "security.md").write_text("# Security\n## record rules\n## access rights\n", encoding="utf-8")
    (kb / "slim" / "orm-reference.md").write_text("# ORM\n## model\n## fields\n## compute\n", encoding="utf-8")
    return tmp_path / "vault"


def _retrieve(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([str(RETRIEVE), *args], capture_output=True, text=True)


def test_retrieve_matches_topic_by_keyword(vault: Path) -> None:
    r = _retrieve("security", "record", "rule", "--domain", "odoo", "--vault-dir", str(vault), "--limit", "1")
    assert r.returncode == 0
    assert "slim/security.md" in r.stdout
    assert "ADVISORY" in r.stdout  # advisory boundary is always stated
    assert "raw/security.md" not in r.stdout  # never auto-returns raw


def test_retrieve_matches_orm_via_slim_headings(vault: Path) -> None:
    # 'model/field/compute' are absent from the topic name but present in the slim headings.
    r = _retrieve("compute", "field", "model", "--domain", "odoo", "--vault-dir", str(vault), "--limit", "1")
    assert "slim/orm-reference.md" in r.stdout


@pytest.mark.parametrize("args", [
    ("security", "--domain", "odoo", "--vault-dir", "/no/such/vault"),  # missing vault
    ("security", "--domain", "python"),                                 # unknown domain
    ("--domain", "odoo"),                                               # no keywords
])
def test_retrieve_fails_graceful(args: tuple) -> None:
    r = _retrieve(*args)
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def _odoo_project(tmp_path: Path, vault: Path) -> Path:
    proj = tmp_path / "proj"
    (proj / "custom-addons" / "m").mkdir(parents=True)
    (proj / "custom-addons" / "m" / "__manifest__.py").write_text("{'name':'m','version':'19.0.1.0.0'}", encoding="utf-8")
    (proj / ".omx").mkdir()
    (proj / ".omx" / "project-profile.json").write_text(json.dumps({"domain": "odoo"}), encoding="utf-8")
    (proj / ".omx" / "local-config.json").write_text(
        json.dumps({"obsidian": {"ai_auto_vault_dir": str(vault)}}), encoding="utf-8")
    return proj


def _hook(stdin: str) -> subprocess.CompletedProcess:
    return subprocess.run([str(HOOK)], input=stdin, capture_output=True, text=True)


def test_hook_injects_for_domain_prompt(tmp_path: Path, vault: Path) -> None:
    proj = _odoo_project(tmp_path, vault)
    payload = json.dumps({"prompt": "how do I add a record rule and access rights?", "cwd": str(proj)})
    r = _hook(payload)
    assert r.returncode == 0
    assert "slim/security.md" in r.stdout


def test_hook_resolves_profile_from_nested_subdir(tmp_path: Path, vault: Path) -> None:
    # A prompt submitted from a nested subdirectory must still find the repo-root profile.
    proj = _odoo_project(tmp_path, vault)
    sub = proj / "custom-addons" / "m" / "models"
    sub.mkdir(parents=True)
    payload = json.dumps({"prompt": "fix the record rule and access rights", "cwd": str(sub)})
    r = _hook(payload)
    assert r.returncode == 0
    assert "slim/security.md" in r.stdout


def test_hook_silent_on_generic_prompt(tmp_path: Path, vault: Path) -> None:
    proj = _odoo_project(tmp_path, vault)
    r = _hook(json.dumps({"prompt": "lets grab coffee and chat", "cwd": str(proj)}))
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_hook_silent_on_non_domain_project(tmp_path: Path) -> None:
    # No project-profile -> gate 1 fails -> nothing, even with a domain-shaped prompt.
    r = _hook(json.dumps({"prompt": "fix the record rule security", "cwd": str(tmp_path)}))
    assert r.returncode == 0
    assert r.stdout.strip() == ""


@pytest.mark.parametrize("stdin", ["not json {{{", "", "{}"])
def test_hook_fail_open_on_bad_input(stdin: str) -> None:
    r = _hook(stdin)
    assert r.returncode == 0
    assert r.stdout.strip() == ""
