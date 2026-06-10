#!/usr/bin/env python3
"""Validate an Obsidian-stored Odoo official docs raw/slim baseline."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REQUIRED_ROOT_FILES = (
    "00_Index.md",
    "01_UserManual_Index.md",
    "02_Retrieval_Runbook.md",
    "_meta/baseline.md",
)
SECRET_VALUE = re.compile(
    r"(password|passwd|pwd|secret|authorization|client[_-]?secret|api[_-]?key|private[_ -]?key)\s*[:=]\s*\S+",
    re.IGNORECASE,
)
TOKEN_VALUE = re.compile(r"\b(token)\s*[:=]\s*(['\"]|bearer|sk-|ghp_|[A-Za-z0-9_./+=-]{24,})", re.IGNORECASE)
SAFE_DOC_VALUES = {
    "click",
    "copy",
    "enable",
    "enter",
    "generate",
    "select",
}
ROW = re.compile(
    r"^\|\s*(?P<topic>[^|]+?)\s*\|\s*(?P<url>[^|]+?)\s*\|\s*(?P<slim>slim/[^|]+?)\s*\|\s*(?P<raw>raw/[^|]+?)\s*\|\s*(?P<status>[^|]+?)\s*\|$"
)
USER_ROW = re.compile(
    r"^\|\s*(?P<group>[^|]+?)\s*\|\s*(?P<topic>[^|]+?)\s*\|\s*(?P<url>https://www\.odoo\.com/documentation/(?P<url_version>[^/]+)/applications/[^|]+?\.html)\s*\|\s*(?P<slim>user-manual/slim/[^|]+?)\s*\|\s*(?P<raw>user-manual/raw/[^|]+?)\s*\|\s*(?P<status>[^|]+?)\s*\|$"
)


def fail(message: str) -> None:
    print(f"[odoo-docs-kb-validate] {message}", file=sys.stderr)
    raise SystemExit(1)


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read {path}: {exc}")


def frontmatter(path: Path) -> dict[str, str]:
    text = read(path)
    match = re.match(r"^---\r?\n(?P<frontmatter>.*?)\r?\n---\r?\n", text, re.DOTALL)
    if not match:
        fail(f"missing or malformed frontmatter: {path}")

    data: dict[str, str] = {}
    for lineno, line in enumerate(match.group("frontmatter").splitlines(), start=2):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("- "):
            continue
        if ":" not in stripped:
            fail(f"malformed frontmatter line in {path}:{lineno}: {line}")
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key in data:
            fail(f"duplicate frontmatter key in {path}:{lineno}: {key}")
        data[key] = value
    return data


def markdown_files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*.md") if path.is_file())


def validate_secret_scan(root: Path) -> None:
    for path in markdown_files(root):
        for line in read(path).splitlines():
            if TOKEN_VALUE.search(line):
                fail(f"secret-like payload found in {path}")
            secret_match = SECRET_VALUE.search(line)
            if secret_match:
                value = secret_match.group(0).split(":", 1)[-1].split("=", 1)[-1].strip().strip("`'\"")
                first_word = re.split(r"\s+", value, maxsplit=1)[0].lower()
                if first_word in SAFE_DOC_VALUES:
                    continue
            if secret_match:
                fail(f"secret-like payload found in {path}")


def validate_required_layout(root: Path) -> None:
    if not root.is_dir():
        fail(f"not a directory: {root}")
    for relative in REQUIRED_ROOT_FILES:
        if not (root / relative).is_file():
            fail(f"missing required file: {relative}")
    for directory in ("raw", "slim"):
        if not (root / directory).is_dir():
            fail(f"missing required directory: {directory}")
    for directory in ("user-manual/raw", "user-manual/slim"):
        if not (root / directory).is_dir():
            fail(f"missing required directory: {directory}")


def topic_files(root: Path, directory: str) -> dict[str, Path]:
    files = {}
    for path in sorted((root / directory).glob("*.md")):
        files[path.stem] = path
    if not files:
        fail(f"no topic files in {directory}/")
    return files


def validate_topic_parity(root: Path) -> tuple[dict[str, Path], dict[str, Path]]:
    raw = topic_files(root, "raw")
    slim = topic_files(root, "slim")
    if set(raw) != set(slim):
        missing_slim = sorted(set(raw) - set(slim))
        missing_raw = sorted(set(slim) - set(raw))
        fail(f"raw/slim topic mismatch: missing_slim={missing_slim} missing_raw={missing_raw}")
    return raw, slim


def validate_metadata(root: Path, raw: dict[str, Path], slim: dict[str, Path]) -> tuple[str, str]:
    baseline = frontmatter(root / "_meta" / "baseline.md")
    baseline_id = baseline.get("baseline_id")
    version = baseline.get("version")
    source_root = baseline.get("source_root")
    if not baseline_id or not version or not source_root:
        fail("_meta/baseline.md must define baseline_id, version, and source_root")

    for topic in sorted(raw):
        raw_meta = frontmatter(raw[topic])
        slim_meta = frontmatter(slim[topic])
        for key in ("baseline_id", "version", "source_url", "fetched_at"):
            if not raw_meta.get(key):
                fail(f"raw/{topic}.md missing frontmatter key: {key}")
            if not slim_meta.get(key):
                fail(f"slim/{topic}.md missing frontmatter key: {key}")
        for key in ("baseline_id", "version", "source_url"):
            if raw_meta[key] != slim_meta[key]:
                fail(f"raw/slim metadata mismatch for {topic}: {key}")
        if raw_meta["baseline_id"] != baseline_id or raw_meta["version"] != version:
            fail(f"topic metadata does not match baseline for {topic}")
        if not raw_meta["source_url"].startswith(source_root):
            fail(f"topic source_url outside source_root for {topic}: {raw_meta['source_url']}")
        slim_text = read(slim[topic])
        if "navigation-only / heading-only slim view" not in slim_text:
            fail(f"slim/{topic}.md must declare navigation-only / heading-only scope")
        if "Do not use" not in slim_text or "authoritative implementation text" not in slim_text:
            fail(f"slim/{topic}.md must declare non-authoritative implementation scope")
    return baseline_id, version


def validate_index(root: Path, raw: dict[str, Path], slim: dict[str, Path], baseline_id: str, version: str) -> None:
    index = root / "00_Index.md"
    index_text = read(index)
    index_meta = frontmatter(index)
    if index_meta.get("baseline_id") != baseline_id or index_meta.get("version") != version:
        fail("00_Index.md metadata must match baseline")
    for required in ("navigation/heading-only", "raw", "원문 URL", "통째 로드 금지"):
        if required not in index_text:
            fail(f"00_Index.md missing usage warning: {required}")

    collected_raw_topics: list[str] = []
    collected_slim_topics: list[str] = []
    for line in index_text.splitlines():
        match = ROW.match(line)
        if not match:
            continue
        status = match.group("status").strip()
        if status != "collected":
            continue
        raw_path = root / match.group("raw").strip()
        slim_path = root / match.group("slim").strip()
        if not raw_path.is_file():
            fail(f"index references missing raw file: {raw_path.relative_to(root)}")
        if not slim_path.is_file():
            fail(f"index references missing slim file: {slim_path.relative_to(root)}")
        collected_raw_topics.append(raw_path.stem)
        collected_slim_topics.append(slim_path.stem)

    expected_topics = set(raw)
    for label, topics in (("raw", collected_raw_topics), ("slim", collected_slim_topics)):
        duplicate_topics = sorted({topic for topic in topics if topics.count(topic) > 1})
        if duplicate_topics:
            fail(f"index contains duplicate {label} topic rows: {duplicate_topics}")
        if set(topics) != expected_topics:
            missing = sorted(expected_topics - set(topics))
            extra = sorted(set(topics) - expected_topics)
            fail(f"index {label} topic coverage mismatch: missing={missing} extra={extra}")


def validate_user_manual(root: Path, baseline_id: str, version: str) -> None:
    manual = root / "01_UserManual_Index.md"
    meta = frontmatter(manual)
    text = read(manual)
    expected = {
        "baseline_id": baseline_id,
        "version": version,
        "tier": "user",
        "view": "index",
    }
    for key, value in expected.items():
        if meta.get(key) != value:
            fail(f"01_UserManual_Index.md must define {key}: {value}")
    if "applications.html" not in meta.get("source_url", ""):
        fail("01_UserManual_Index.md source_url must point at applications.html")
    for forbidden in ("raw 미수집", "raw-on-demand", "URL on-demand fetch", "index-only"):
        if forbidden in text:
            fail(f"01_UserManual_Index.md still describes user manuals as index-only: {forbidden}")
    for required in ("user-manual/raw", "user-manual/slim", "Studio"):
        if required not in text:
            fail(f"01_UserManual_Index.md missing user-manual mirror rule: {required}")

    raw_topics: list[str] = []
    slim_topics: list[str] = []
    source_urls: list[str] = []
    for line in text.splitlines():
        match = USER_ROW.match(line)
        if not match:
            continue
        if match.group("status").strip() != "collected":
            continue
        if match.group("url_version").strip() != version:
            fail(f"user manual index URL version mismatch for {match.group('topic').strip()}: {match.group('url').strip()}")
        raw_path = root / match.group("raw").strip()
        slim_path = root / match.group("slim").strip()
        if not raw_path.is_file():
            fail(f"user manual index references missing raw file: {raw_path.relative_to(root)}")
        if not slim_path.is_file():
            fail(f"user manual index references missing slim file: {slim_path.relative_to(root)}")
        raw_topics.append(raw_path.stem)
        slim_topics.append(slim_path.stem)
        source_urls.append(match.group("url").strip())

    if not raw_topics:
        fail("01_UserManual_Index.md must contain collected user-manual raw/slim rows")
    for label, topics in (("raw", raw_topics), ("slim", slim_topics)):
        duplicate_topics = sorted({topic for topic in topics if topics.count(topic) > 1})
        if duplicate_topics:
            fail(f"user manual index contains duplicate {label} rows: {duplicate_topics}")
    duplicate_urls = sorted({url for url in source_urls if source_urls.count(url) > 1})
    if duplicate_urls:
        fail(f"user manual index contains duplicate source_url rows: {duplicate_urls}")

    raw_files = topic_files(root, "user-manual/raw")
    slim_files = topic_files(root, "user-manual/slim")
    if set(raw_files) != set(slim_files):
        missing_slim = sorted(set(raw_files) - set(slim_files))
        missing_raw = sorted(set(slim_files) - set(raw_files))
        fail(f"user manual raw/slim mismatch: missing_slim={missing_slim} missing_raw={missing_raw}")
    expected_topics = set(raw_topics)
    if set(raw_files) != expected_topics:
        missing = sorted(expected_topics - set(raw_files))
        extra = sorted(set(raw_files) - expected_topics)
        fail(f"user manual file coverage mismatch: missing={missing} extra={extra}")

    for topic in sorted(raw_files):
        raw_meta = frontmatter(raw_files[topic])
        slim_meta = frontmatter(slim_files[topic])
        for key in ("baseline_id", "version", "tier", "view", "source_url", "fetched_at"):
            if not raw_meta.get(key):
                fail(f"user-manual/raw/{topic}.md missing frontmatter key: {key}")
            if not slim_meta.get(key):
                fail(f"user-manual/slim/{topic}.md missing frontmatter key: {key}")
        if raw_meta["baseline_id"] != baseline_id or raw_meta["version"] != version:
            fail(f"user manual raw metadata does not match baseline for {topic}")
        if slim_meta["baseline_id"] != baseline_id or slim_meta["version"] != version:
            fail(f"user manual slim metadata does not match baseline for {topic}")
        if raw_meta["tier"] != "user" or slim_meta["tier"] != "user":
            fail(f"user manual tier metadata must be user for {topic}")
        if raw_meta["view"] != "raw" or slim_meta["view"] != "slim":
            fail(f"user manual view metadata mismatch for {topic}")
        if raw_meta["source_url"] != slim_meta["source_url"]:
            fail(f"user manual raw/slim source_url mismatch for {topic}")
        if raw_meta["source_url"] not in source_urls:
            fail(f"user manual file not referenced by index for {topic}")
        slim_text = read(slim_files[topic])
        if "navigation-only / heading-only user-manual slim view" not in slim_text:
            fail(f"user-manual/slim/{topic}.md must declare navigation-only user-manual scope")
        if "Do not use" not in slim_text or "authoritative implementation text" not in slim_text:
            fail(f"user-manual/slim/{topic}.md must declare non-authoritative implementation scope")


def validate_runbook(root: Path, baseline_id: str, version: str) -> None:
    runbook = root / "02_Retrieval_Runbook.md"
    meta = frontmatter(runbook)
    text = read(runbook)
    if meta.get("baseline_id") != baseline_id or meta.get("version") != version:
        fail("02_Retrieval_Runbook.md metadata must match baseline")
    for required in ("자작 가이드 먼저", "navigation-only / heading-only", "공식 raw", "1건만", "user-manual/raw"):
        if required not in text:
            fail(f"02_Retrieval_Runbook.md missing retrieval rule: {required}")


def validate(root: Path) -> None:
    validate_required_layout(root)
    validate_secret_scan(root)
    raw, slim = validate_topic_parity(root)
    baseline_id, version = validate_metadata(root, raw, slim)
    validate_index(root, raw, slim, baseline_id, version)
    validate_user_manual(root, baseline_id, version)
    validate_runbook(root, baseline_id, version)
    user_manual_count = len(topic_files(root, "user-manual/raw"))
    print(
        f"[odoo-docs-kb-validate] ok: {len(raw)} developer topic(s), "
        f"{user_manual_count} user manual page(s), baseline={baseline_id}, version={version}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Path to Odoo19_Docs_KB")
    args = parser.parse_args()
    validate(args.path.resolve())


if __name__ == "__main__":
    main()
