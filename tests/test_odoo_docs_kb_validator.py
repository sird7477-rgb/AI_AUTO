import shutil
import subprocess
import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "validate-odoo-docs-kb.py"
COLLECTOR_SCRIPT = ROOT / "scripts" / "collect-odoo-docs-kb.py"
COLLECTOR_SPEC = importlib.util.spec_from_file_location("collect_odoo_docs_kb", COLLECTOR_SCRIPT)
assert COLLECTOR_SPEC is not None
COLLECTOR = importlib.util.module_from_spec(COLLECTOR_SPEC)
assert COLLECTOR_SPEC.loader is not None
COLLECTOR_SPEC.loader.exec_module(COLLECTOR)


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def valid_fixture(root: Path) -> Path:
    kb = root / "Odoo19_Docs_KB"
    write(
        kb / "_meta" / "baseline.md",
        """---
baseline_id: odoo-19-docs-2026-06
version: "19.0"
source_root: https://www.odoo.com/documentation/19.0/
---

# baseline
""",
    )
    write(
        kb / "raw" / "orm-reference.md",
        """---
baseline_id: odoo-19-docs-2026-06
version: "19.0"
source_url: https://www.odoo.com/documentation/19.0/developer/reference/backend/orm.html
fetched_at: 2026-06-05T06:44:27Z
---

# ORM raw
""",
    )
    write(
        kb / "slim" / "orm-reference.md",
        """---
baseline_id: odoo-19-docs-2026-06
version: "19.0"
source_url: https://www.odoo.com/documentation/19.0/developer/reference/backend/orm.html
fetched_at: 2026-06-05T06:44:27Z
---

# ORM slim

> Scope: navigation-only / heading-only slim view. Do not use this file as authoritative implementation text. For exact semantics, code examples, security rules, or API details, open the matching `raw` file or the pinned source URL.
""",
    )
    write(
        kb / "00_Index.md",
        """---
baseline_id: odoo-19-docs-2026-06
version: "19.0"
source_root: https://www.odoo.com/documentation/19.0/
---

# Odoo 19 Docs KB

열람 규칙: slim navigation/heading-only -> 부족 시 raw -> 그래도 부족 시 원문 URL. raw는 통째 로드 금지.

| topic | url | slim | raw | status |
| --- | --- | --- | --- | --- |
| ORM reference | developer/reference/backend/orm.html | slim/orm-reference.md | raw/orm-reference.md | collected |
""",
    )
    write(
        kb / "01_UserManual_Index.md",
        """---
type: technical-spec
baseline_id: odoo-19-docs-2026-06
version: "19.0"
tier: user
view: index
source_url: https://www.odoo.com/documentation/19.0/applications.html
fetched_at: 2026-06-05T07:10:09Z
sync_class: external_private_vault
---

# Odoo 19 User Manual

User manual pages are mirrored as `user-manual/raw` and `user-manual/slim`. Studio excluded.

| group | topic | source_url | slim | raw | status |
| --- | --- | --- | --- | --- | --- |
| essentials | essentials | https://www.odoo.com/documentation/19.0/applications/essentials.html | user-manual/slim/essentials.md | user-manual/raw/essentials.md | collected |
""",
    )
    write(
        kb / "user-manual" / "raw" / "essentials.md",
        """---
baseline_id: odoo-19-docs-2026-06
version: "19.0"
tier: user
view: raw
source_url: https://www.odoo.com/documentation/19.0/applications/essentials.html
fetched_at: 2026-06-10T00:00:00Z
---

# Odoo essentials

Raw user manual page.
""",
    )
    write(
        kb / "user-manual" / "slim" / "essentials.md",
        """---
baseline_id: odoo-19-docs-2026-06
version: "19.0"
tier: user
view: slim
source_url: https://www.odoo.com/documentation/19.0/applications/essentials.html
fetched_at: 2026-06-10T00:00:00Z
---

# Odoo essentials slim

> Scope: navigation-only / heading-only user-manual slim view. Do not use this file as authoritative implementation text. For exact operational semantics, workflow details, or UI steps, open the matching `user-manual/raw` file or the pinned source URL.
""",
    )
    write(
        kb / "02_Retrieval_Runbook.md",
        """---
baseline_id: odoo-19-docs-2026-06
version: "19.0"
---

# Runbook

자작 가이드 먼저, navigation-only / heading-only 공식 slim, 공식 raw 1건만, user-manual/raw 1건만.
""",
    )
    return kb


def run_validator(path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(SCRIPT), str(path)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def test_valid_fixture_passes(tmp_path: Path) -> None:
    result = run_validator(valid_fixture(tmp_path))
    assert result.returncode == 0
    assert "ok: 1 developer topic(s), 1 user manual page(s)" in result.stdout


def test_missing_raw_slim_parity_fails(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    (kb / "slim" / "orm-reference.md").unlink()
    result = run_validator(kb)
    assert result.returncode != 0
    assert "slim" in result.stderr


def test_index_missing_file_reference_fails(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    index = kb / "00_Index.md"
    index.write_text(index.read_text(encoding="utf-8").replace("raw/orm-reference.md", "raw/missing.md"), encoding="utf-8")
    result = run_validator(kb)
    assert result.returncode != 0
    assert "index references missing raw file" in result.stderr


def test_index_duplicate_rows_cannot_hide_missing_topic(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    raw = kb / "raw" / "actions.md"
    slim = kb / "slim" / "actions.md"
    raw.write_text((kb / "raw" / "orm-reference.md").read_text(encoding="utf-8"), encoding="utf-8")
    slim.write_text((kb / "slim" / "orm-reference.md").read_text(encoding="utf-8"), encoding="utf-8")

    index = kb / "00_Index.md"
    index.write_text(
        index.read_text(encoding="utf-8")
        + "| ORM duplicate | developer/reference/backend/orm.html | slim/orm-reference.md | raw/orm-reference.md | collected |\n",
        encoding="utf-8",
    )

    result = run_validator(kb)
    assert result.returncode != 0
    assert "duplicate raw topic rows" in result.stderr


def test_raw_slim_metadata_mismatch_fails(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    slim = kb / "slim" / "orm-reference.md"
    slim.write_text(slim.read_text(encoding="utf-8").replace('version: "19.0"', 'version: "18.0"'), encoding="utf-8")
    result = run_validator(kb)
    assert result.returncode != 0
    assert "raw/slim metadata mismatch" in result.stderr


def test_slim_scope_warning_is_required(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    slim = kb / "slim" / "orm-reference.md"
    slim.write_text(
        slim.read_text(encoding="utf-8").replace(
            "> Scope: navigation-only / heading-only slim view. Do not use this file as authoritative implementation text. For exact semantics, code examples, security rules, or API details, open the matching `raw` file or the pinned source URL.\n",
            "",
        ),
        encoding="utf-8",
    )
    result = run_validator(kb)
    assert result.returncode != 0
    assert "navigation-only / heading-only scope" in result.stderr


def test_slim_non_authoritative_warning_is_required(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    slim = kb / "slim" / "orm-reference.md"
    slim.write_text(
        slim.read_text(encoding="utf-8").replace("authoritative implementation text", "the main text"),
        encoding="utf-8",
    )
    result = run_validator(kb)
    assert result.returncode != 0
    assert "non-authoritative implementation scope" in result.stderr


def test_frontmatter_allows_comments_lists_and_crlf(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    raw = kb / "raw" / "orm-reference.md"
    raw.write_text(
        raw.read_text(encoding="utf-8").replace(
            "baseline_id: odoo-19-docs-2026-06\n",
            "# comment accepted by the frontmatter reader\n"
            "tags:\n"
            "- odoo\n"
            "baseline_id: odoo-19-docs-2026-06\n",
        ).replace("\n", "\r\n"),
        encoding="utf-8",
    )
    result = run_validator(kb)
    assert result.returncode == 0, result.stderr


def test_user_manual_mirror_rows_are_required(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    manual = kb / "01_UserManual_Index.md"
    manual.write_text(manual.read_text(encoding="utf-8").replace("user-manual/raw/essentials.md", "user-manual/raw/missing.md"), encoding="utf-8")
    result = run_validator(kb)
    assert result.returncode != 0
    assert "user manual index references missing raw file" in result.stderr


def test_user_manual_index_only_wording_fails(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    manual = kb / "01_UserManual_Index.md"
    manual.write_text(manual.read_text(encoding="utf-8") + "\nraw 미수집. URL on-demand fetch.\n", encoding="utf-8")
    result = run_validator(kb)
    assert result.returncode != 0
    assert "still describes user manuals as index-only" in result.stderr


def test_user_manual_slim_metadata_mismatch_fails(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    slim = kb / "user-manual" / "slim" / "essentials.md"
    slim.write_text(slim.read_text(encoding="utf-8").replace("view: slim", "view: raw"), encoding="utf-8")
    result = run_validator(kb)
    assert result.returncode != 0
    assert "user manual view metadata mismatch" in result.stderr


def test_user_manual_slim_non_authority_warning_required(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    slim = kb / "user-manual" / "slim" / "essentials.md"
    slim.write_text(slim.read_text(encoding="utf-8").replace("authoritative implementation text", "main text"), encoding="utf-8")
    result = run_validator(kb)
    assert result.returncode != 0
    assert "non-authoritative implementation scope" in result.stderr


def test_safe_doc_secret_phrase_does_not_bypass_token_scan(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    raw = kb / "user-manual" / "raw" / "essentials.md"
    raw.write_text(raw.read_text(encoding="utf-8") + "\nsecret: enter the value and token = ghp_abcdefghijklmnopqrstuvwxyz\n", encoding="utf-8")
    result = run_validator(kb)
    assert result.returncode != 0
    assert "secret-like payload" in result.stderr


def test_collector_reads_rewritten_user_manual_table(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    links = COLLECTOR.read_index_links(kb / "01_UserManual_Index.md")
    assert links == [
        (
            "essentials",
            "essentials",
            "https://www.odoo.com/documentation/19.0/applications/essentials.html",
        )
    ]


def test_collector_rewrites_index_with_cli_metadata(tmp_path: Path) -> None:
    index = tmp_path / "01_UserManual_Index.md"
    links = [
        (
            "sales",
            "Sales",
            "https://www.odoo.com/documentation/20.0/applications/sales/sales.html",
        )
    ]
    COLLECTOR.rewrite_user_manual_index(
        index,
        links,
        "2026-06-10T00:00:00Z",
        baseline_id="odoo-20-docs-2026-06",
        version="20.0",
    )
    text = index.read_text(encoding="utf-8")
    assert "baseline_id: odoo-20-docs-2026-06" in text
    assert 'version: "20.0"' in text
    assert "source_url: https://www.odoo.com/documentation/20.0/applications.html" in text
    assert "user-manual/slim/sales__sales.md" in text
    assert COLLECTOR.read_index_links(index) == links


def test_secret_like_payload_fails(tmp_path: Path) -> None:
    kb = valid_fixture(tmp_path)
    raw = kb / "raw" / "orm-reference.md"
    raw.write_text(raw.read_text(encoding="utf-8") + "\napi_key=abc123\n", encoding="utf-8")
    result = run_validator(kb)
    assert result.returncode != 0
    assert "secret-like payload" in result.stderr


def test_current_vault_fixture_passes_when_present(tmp_path: Path) -> None:
    vault = Path("/mnt/z/JSJEON/Obsidian/AI_AUTO_Vault/AI_AUTO/Odoo19_Docs_KB")
    if not vault.exists():
        return
    local_copy = tmp_path / "Odoo19_Docs_KB"
    shutil.copytree(vault, local_copy)
    result = run_validator(local_copy)
    assert result.returncode == 0, result.stderr
