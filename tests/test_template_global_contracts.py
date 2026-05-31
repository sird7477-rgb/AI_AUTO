import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _script_links(path: str, function_name: str) -> dict[str, str]:
    pattern = re.compile(
        rf'{function_name} "\$\{{HOME_DIR\}}/bin/([^"]+)" "\$\{{ROOT\}}/tools/([^"]+)"'
    )
    return dict(pattern.findall(_read(path)))


def test_global_helper_link_surfaces_stay_in_sync() -> None:
    docs_links = dict(
        re.findall(
            r"~/bin/([^\s]+) -> ~/workspace/ai-lab/tools/([^\s]+)",
            _read("docs/GLOBAL_TOOLS.md"),
        )
    )
    install_links = _script_links("scripts/install-global-files.sh", "install_link")
    doctor_links = _script_links("scripts/automation-doctor.sh", "check_helper_link")
    bootstrap_links = _script_links("scripts/bootstrap-ai-lab.sh", "ensure_link")

    assert docs_links
    assert docs_links == install_links == doctor_links == bootstrap_links


def test_template_status_manifest_paths_exist_and_are_unique() -> None:
    manifest = re.search(
        r"managed_files\(\) \{\n  cat <<'FILES'\n(?P<body>.*?)\nFILES\n\}",
        _read("tools/ai-auto-template-status"),
        re.DOTALL,
    )
    assert manifest is not None

    rows = [line.split("|") for line in manifest.group("body").strip().splitlines()]
    assert all(len(row) == 4 for row in rows)

    managed_paths = [row[0] for row in rows]
    template_paths = [row[1] for row in rows]
    ownership_values = [row[2] for row in rows]
    patch_policy_values = [row[3] for row in rows]
    assert len(managed_paths) == len(set(managed_paths))
    assert len(template_paths) == len(set(template_paths))
    assert set(ownership_values) <= {"template-owned", "hybrid", "project-owned"}
    assert set(patch_policy_values) <= {"update", "review-merge", "inspect-only"}

    missing_template_paths = [
        path for path in template_paths if not (ROOT / "templates" / "automation-base" / path).exists()
    ]
    assert missing_template_paths == []

    invalid_managed_paths = [
        path
        for path in managed_paths
        if Path(path).is_absolute() or ".." in Path(path).parts or path.startswith(".omx/")
    ]
    assert invalid_managed_paths == []

    source_checkout_missing = {
        # The ai-lab source checkout intentionally omits install-target template
        # markers that downstream projects receive from templates/automation-base.
        "AI_AUTO_TEMPLATE_VERSION",
        "docs/PATCH_NOTES.md",
    }
    missing_managed_paths = [
        path for path in managed_paths if path not in source_checkout_missing and not (ROOT / path).exists()
    ]
    assert missing_managed_paths == []

    unexpected_policies = [
        row for row in rows if (row[2], row[3]) not in {
            ("template-owned", "update"),
            ("hybrid", "review-merge"),
            ("project-owned", "inspect-only"),
        }
    ]
    assert unexpected_policies == []


def test_template_status_reports_source_checkout_without_install_marker_noise() -> None:
    import subprocess

    result = subprocess.run(
        ["tools/ai-auto-template-status", "."],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )

    assert "status: source_checkout" in result.stdout
    assert "installed_version: missing" not in result.stdout
    assert "missing\tAI_AUTO_TEMPLATE_VERSION" not in result.stdout
    assert "missing\tdocs/PATCH_NOTES.md" not in result.stdout
    assert "source-only\tAI_AUTO_TEMPLATE_VERSION" in result.stdout
    assert "source-only\tdocs/PATCH_NOTES.md" in result.stdout


def test_tool_adoption_status_surfaces_are_explicit() -> None:
    for path in (
        "scripts/automation-doctor.sh",
        "templates/automation-base/scripts/automation-doctor.sh",
        "scripts/bootstrap-ai-lab.sh",
    ):
        text = _read(path)
        assert "check_tool_adoption" in text
        assert "tool adoption: ${name} state=${adoption_state} next=${next_gate}" in text
        assert "shellcheck required_gate" in text
        assert "hyperfine optional" in text


def test_codex_startup_notices_are_explicit_and_bounded() -> None:
    text = _read("scripts/install-global-files.sh")

    assert "===== AI_AUTO UPDATE CHECK =====" in text
    assert "AI_AUTO_TEMPLATE_STATUS_NOTICE_TIMEOUT" in text
    assert 'template_status_timeout="\\${AI_AUTO_TEMPLATE_STATUS_NOTICE_TIMEOUT:-1}"' in text
    assert "timeout \"\\${template_status_timeout}\" ai-auto-template-status" in text
    assert "state: update_available" in text
    assert "action: AI_AUTO 최신 패치 적용해줘" in text

    assert "AI_AUTO_KNOWLEDGE_AUTOPUSH_NOTICE" in text
    assert "AI_AUTO_KNOWLEDGE_NOTICE_TIMEOUT" in text
    assert "command -v timeout >/dev/null 2>&1" in text
    assert 'timeout "\\${knowledge_timeout}" knowledge-collect' in text
    assert 'knowledge-collect --include-registry --project "\\${repo_root}"' in text
    assert "state: pending_knowledge_drafts" in text
    assert "push after approval: knowledge-collect --project <repo> --push --vault-dir <vault-dir>" in text
