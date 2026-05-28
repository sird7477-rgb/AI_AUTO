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
