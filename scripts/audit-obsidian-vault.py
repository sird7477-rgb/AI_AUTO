#!/usr/bin/env python3
"""Read-only audit for AI_AUTO Obsidian vault labeling and index lanes."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path


GENERATED_INDEX_NAMES = {"AI_AUTO_INDEX.md"}
GENERATED_ROOT_DIRS = {"Surfaces", "RepeatKeys", "Promotion", "Views"}
NOTE_ROOT_DIRS = {"Projects", "Inbox"}


def path_slug(value: str, preserve_case: bool = False) -> str:
    text = value.strip() if preserve_case else value.strip().lower()
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", text).strip("-")
    slug = re.sub(r"-{2,}", "-", slug)
    return slug[:80] or "item"


def project_slug(value: str) -> str:
    return path_slug(value, preserve_case=True)


def parse_frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end < 0:
        return {}
    data: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if not line.strip() or ":" not in line:
            continue
        key, raw = line.split(":", 1)
        value = raw.strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        data[key.strip()] = value
    return data


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def generated_page(path: Path, root: Path) -> bool:
    if path.name in GENERATED_INDEX_NAMES:
        return True
    try:
        rel = path.relative_to(root)
    except ValueError:
        return False
    if not rel.parts:
        return False
    if rel.parts[0] in GENERATED_ROOT_DIRS:
        return True
    return rel.parts[0] == "Projects" and len(rel.parts) == 2 and path.suffix == ".md"


def note_file(path: Path, root: Path) -> bool:
    try:
        rel = path.relative_to(root)
    except ValueError:
        return False
    if path.suffix != ".md" or not rel.parts:
        return False
    if rel.parts[0] == "Inbox":
        return len(rel.parts) >= 2
    if rel.parts[0] == "Projects":
        return len(rel.parts) >= 3
    return False


def target_project_path(root: Path, inbox_path: Path, data: dict[str, str]) -> Path:
    try:
        rel = inbox_path.relative_to(root)
    except ValueError:
        return root / "Projects" / data.get("project", "unknown") / inbox_path.name
    if len(rel.parts) >= 3:
        project_dir = rel.parts[1]
    else:
        project_dir = project_slug(data.get("project", "unknown"))
    return root / "Projects" / project_dir / inbox_path.name


def classify_conflict(source: Path, target: Path) -> dict[str, object]:
    source_data = parse_frontmatter(source)
    target_data = parse_frontmatter(target)
    exact_duplicate = sha256_file(source) == sha256_file(target)
    same_source_hash = bool(source_data.get("source_hash")) and source_data.get("source_hash") == target_data.get("source_hash")
    same_repeat_key = bool(source_data.get("repeat_key")) and source_data.get("repeat_key") == target_data.get("repeat_key")
    if exact_duplicate:
        classification = "exact_duplicate"
    elif same_source_hash:
        classification = "same_source_hash"
    elif same_repeat_key:
        classification = "same_repeat_key"
    else:
        classification = "manual_review"
    return {
        "source": source.as_posix(),
        "target": target.as_posix(),
        "classification": classification,
        "exact_duplicate": exact_duplicate,
        "same_source_hash": same_source_hash,
        "same_repeat_key": same_repeat_key,
        "source_updated": source_data.get("updated", ""),
        "target_updated": target_data.get("updated", ""),
        "repeat_key": source_data.get("repeat_key", ""),
    }


def top_level_markdown_count(path: Path) -> int:
    if not path.is_dir():
        return 0
    return sum(1 for item in path.rglob("*.md") if item.is_file())


def audit(root: Path) -> dict[str, object]:
    if not root.exists() or not root.is_dir():
        raise SystemExit(f"[obsidian-audit] path does not exist or is not a directory: {root}")

    markdown_files = sorted(path for path in root.rglob("*.md") if path.is_file())
    curated_notes = [path for path in markdown_files if note_file(path, root)]
    generated_pages = [path for path in markdown_files if generated_page(path, root)]
    inbox_notes = [path for path in curated_notes if path.relative_to(root).parts[0] == "Inbox"]
    project_notes = [path for path in curated_notes if path.relative_to(root).parts[0] == "Projects"]

    top_level_folders: dict[str, int] = {}
    for child in sorted(root.iterdir()):
        if child.is_dir() and child.name not in NOTE_ROOT_DIRS and child.name not in GENERATED_ROOT_DIRS:
            count = top_level_markdown_count(child)
            if count:
                top_level_folders[child.name] = count

    conflicts = []
    for inbox_path in inbox_notes:
        data = parse_frontmatter(inbox_path)
        target = target_project_path(root, inbox_path, data)
        if target.exists() and target.resolve(strict=False) != inbox_path.resolve(strict=False):
            conflicts.append(classify_conflict(inbox_path, target))

    conflict_counts = Counter(item["classification"] for item in conflicts)
    index_path = root / "AI_AUTO_INDEX.md"
    ai_auto_index_exists = index_path.exists()
    index_mtime = index_path.stat().st_mtime if ai_auto_index_exists else None
    latest_curated_note_mtime = max((path.stat().st_mtime for path in curated_notes), default=None)
    ai_auto_index_likely_stale = (
        not ai_auto_index_exists
        or (
            latest_curated_note_mtime is not None
            and index_mtime is not None
            and latest_curated_note_mtime > index_mtime
        )
    )
    missing_links = []
    links_pattern = re.compile(r"(?:^|\n)## Links\n", re.MULTILINE)
    for path in curated_notes:
        if not links_pattern.search(path.read_text(encoding="utf-8", errors="replace")):
            missing_links.append(path.relative_to(root).as_posix())

    return {
        "root": root.as_posix(),
        "markdown_files": len(markdown_files),
        "curated_notes": len(curated_notes),
        "project_notes": len(project_notes),
        "inbox_notes": len(inbox_notes),
        "generated_pages": len(generated_pages),
        "top_level_domain_or_reference_folders": top_level_folders,
        "inbox_project_conflicts": len(conflicts),
        "conflict_counts": dict(sorted(conflict_counts.items())),
        "conflicts": conflicts,
        "curated_notes_missing_links": missing_links,
        "ai_auto_index_exists": ai_auto_index_exists,
        "ai_auto_index_likely_stale": ai_auto_index_likely_stale,
    }


def print_text(report: dict[str, object]) -> None:
    print(f"[obsidian-audit] root: {report['root']}")
    print(f"[obsidian-audit] markdown_files: {report['markdown_files']}")
    print(f"[obsidian-audit] curated_notes: {report['curated_notes']}")
    print(f"[obsidian-audit] project_notes: {report['project_notes']}")
    print(f"[obsidian-audit] inbox_notes: {report['inbox_notes']}")
    print(f"[obsidian-audit] generated_pages: {report['generated_pages']}")
    print(f"[obsidian-audit] ai_auto_index_exists: {str(report['ai_auto_index_exists']).lower()}")
    print(f"[obsidian-audit] ai_auto_index_likely_stale: {str(report['ai_auto_index_likely_stale']).lower()}")
    folders = report["top_level_domain_or_reference_folders"]
    if isinstance(folders, dict) and folders:
        print("[obsidian-audit] top_level_domain_or_reference_folders:")
        for name, count in folders.items():
            print(f"[obsidian-audit]   - {name}: {count} markdown file(s)")
    print(f"[obsidian-audit] inbox_project_conflicts: {report['inbox_project_conflicts']}")
    counts = report["conflict_counts"]
    if isinstance(counts, dict) and counts:
        for name, count in counts.items():
            print(f"[obsidian-audit]   {name}: {count}")
    for conflict in report["conflicts"]:
        if isinstance(conflict, dict):
            print(
                "[obsidian-audit] conflict "
                f"{conflict['classification']}: {conflict['source']} -> {conflict['target']}"
            )
    missing_links = report["curated_notes_missing_links"]
    if isinstance(missing_links, list) and missing_links:
        print(f"[obsidian-audit] curated_notes_missing_links: {len(missing_links)}")
        for path in missing_links:
            print(f"[obsidian-audit]   - {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Read-only audit for an AI_AUTO Obsidian vault.")
    parser.add_argument("path", type=Path, help="Path to the AI_AUTO vault root")
    parser.add_argument("--json", action="store_true", help="write machine-readable JSON")
    args = parser.parse_args()

    report = audit(args.path)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print_text(report)


if __name__ == "__main__":
    main()
