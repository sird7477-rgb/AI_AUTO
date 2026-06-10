from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "scripts" / "audit-obsidian-vault.py"


def write_note(
    path: Path,
    *,
    source_hash: str,
    repeat_key: str,
    body: str = "body",
    project: str = "ai-lab",
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\n".join(
            [
                "---",
                "type: incident",
                "status: resolved",
                "title: Test note",
                "summary: Test summary",
                f"project: {project}",
                "surface: obsidian",
                "severity: medium",
                f"repeat_key: {repeat_key}",
                "source_artifact: docs/OBSIDIAN_INTEGRATION.md",
                f"source_hash: {source_hash}",
                "sync_class: external_private_vault",
                "redaction_status: sanitized",
                "evidence_count: 1",
                "confidence: medium",
                "promotion_state: not_candidate",
                "created: 2026-06-10",
                "updated: 2026-06-10",
                "---",
                "",
                "# Test note",
                "",
                body,
                "",
                "## Links",
                "",
                "- Vault index: [[AI_AUTO_INDEX]]",
                "",
            ]
        ),
        encoding="utf-8",
    )


def run_audit(path: Path) -> dict[str, object]:
    result = subprocess.run(
        [sys.executable, str(AUDIT), str(path), "--json"],
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


def test_audit_classifies_inbox_project_conflicts(tmp_path: Path) -> None:
    vault = tmp_path / "AI_AUTO"
    source_hash = "sha256:" + ("a" * 64)
    write_note(
        vault / "Inbox" / "ai-lab--abc" / "2026-06-10--obsidian--same-source.md",
        source_hash=source_hash,
        repeat_key="obsidian:same-source",
        body="inbox body",
    )
    write_note(
        vault / "Projects" / "ai-lab--abc" / "2026-06-10--obsidian--same-source.md",
        source_hash=source_hash,
        repeat_key="obsidian:same-source",
        body="project body",
    )
    write_note(
        vault / "Projects" / "ai-lab--abc" / "2026-06-10--obsidian--ok.md",
        source_hash="sha256:" + ("b" * 64),
        repeat_key="obsidian:ok",
    )
    (vault / "AI_AUTO_INDEX.md").write_text("# AI_AUTO Knowledge Index\n", encoding="utf-8")
    old_time = min(path.stat().st_mtime for path in vault.rglob("*.md")) - 10
    os.utime(vault / "AI_AUTO_INDEX.md", (old_time, old_time))
    (vault / "Odoo19_Docs_KB").mkdir(parents=True)
    (vault / "Odoo19_Docs_KB" / "00_Index.md").write_text("# Odoo\n", encoding="utf-8")

    report = run_audit(vault)

    assert report["curated_notes"] == 3
    assert report["project_notes"] == 2
    assert report["inbox_notes"] == 1
    assert report["inbox_project_conflicts"] == 1
    assert report["conflict_counts"] == {"same_source_hash": 1}
    assert report["top_level_domain_or_reference_folders"] == {"Odoo19_Docs_KB": 1}
    assert report["ai_auto_index_exists"] is True
    assert report["ai_auto_index_likely_stale"] is True


def test_audit_reports_exact_duplicate_and_missing_links(tmp_path: Path) -> None:
    vault = tmp_path / "AI_AUTO"
    path = vault / "Inbox" / "ai-lab--abc" / "2026-06-10--obsidian--duplicate.md"
    target = vault / "Projects" / "ai-lab--abc" / path.name
    write_note(
        path,
        source_hash="sha256:" + ("c" * 64),
        repeat_key="obsidian:duplicate",
    )
    target.parent.mkdir(parents=True)
    target.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    no_links = vault / "Projects" / "ai-lab--abc" / "2026-06-10--obsidian--no-links.md"
    write_note(
        no_links,
        source_hash="sha256:" + ("d" * 64),
        repeat_key="obsidian:no-links",
    )
    no_links.write_text(no_links.read_text(encoding="utf-8").replace("\n## Links\n", "\n## Not Links\n"), encoding="utf-8")

    report = run_audit(vault)

    assert report["conflict_counts"] == {"exact_duplicate": 1}
    assert report["curated_notes_missing_links"] == [
        "Projects/ai-lab--abc/2026-06-10--obsidian--no-links.md"
    ]


def test_audit_is_read_only(tmp_path: Path) -> None:
    vault = tmp_path / "AI_AUTO"
    note = vault / "Inbox" / "ai-lab--abc" / "2026-06-10--obsidian--readonly.md"
    write_note(
        note,
        source_hash="sha256:" + ("e" * 64),
        repeat_key="obsidian:readonly",
    )
    before = {path: path.read_bytes() for path in vault.rglob("*") if path.is_file()}

    run_audit(vault)

    after = {path: path.read_bytes() for path in vault.rglob("*") if path.is_file()}
    assert after == before


def test_audit_includes_flat_inbox_notes_and_tolerates_invalid_utf8(tmp_path: Path) -> None:
    vault = tmp_path / "AI_AUTO"
    flat = vault / "Inbox" / "flat-note.md"
    write_note(
        flat,
        source_hash="sha256:" + ("f" * 64),
        repeat_key="obsidian:flat",
    )
    target = vault / "Projects" / "ai-lab" / "flat-note.md"
    write_note(
        target,
        source_hash="sha256:" + ("0" * 64),
        repeat_key="obsidian:other",
    )
    bad = vault / "Inbox" / "bad-utf8.md"
    bad.parent.mkdir(parents=True, exist_ok=True)
    bad.write_bytes(b"---\ntype: incident\nproject: ai-lab\n---\n\xff\xfe")

    report = run_audit(vault)

    assert report["inbox_notes"] == 2
    assert report["inbox_project_conflicts"] == 1
    assert report["conflict_counts"] == {"manual_review": 1}


def test_audit_uses_slugged_project_target_for_flat_inbox_notes(tmp_path: Path) -> None:
    vault = tmp_path / "AI_AUTO"
    flat = vault / "Inbox" / "slugged-note.md"
    write_note(
        flat,
        project="Project JW",
        source_hash="sha256:" + ("2" * 64),
        repeat_key="obsidian:slugged-flat",
    )
    target = vault / "Projects" / "Project-JW" / "slugged-note.md"
    write_note(
        target,
        project="Project JW",
        source_hash="sha256:" + ("3" * 64),
        repeat_key="obsidian:slugged-target",
    )

    report = run_audit(vault)

    assert report["inbox_project_conflicts"] == 1
    assert report["conflict_counts"] == {"manual_review": 1}


def test_audit_reports_current_index_as_not_stale(tmp_path: Path) -> None:
    vault = tmp_path / "AI_AUTO"
    note = vault / "Projects" / "ai-lab--abc" / "2026-06-10--obsidian--current.md"
    write_note(
        note,
        source_hash="sha256:" + ("1" * 64),
        repeat_key="obsidian:current",
    )
    index = vault / "AI_AUTO_INDEX.md"
    index.write_text("# AI_AUTO Knowledge Index\n", encoding="utf-8")
    future_time = note.stat().st_mtime + 10
    os.utime(index, (future_time, future_time))

    report = run_audit(vault)

    assert report["ai_auto_index_exists"] is True
    assert report["ai_auto_index_likely_stale"] is False
