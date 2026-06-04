#!/usr/bin/env python3
"""Validate the scoped Odoo.sh KB markdown bundle before vault publishing."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB_ROOT = ROOT / "knowledge" / "Odoo.sh KB"
PLAN_GLOB = "ODOO_SH_KB_*.md"
STATUS_VALUES = {"promoted", "ready", "schema-pending", "security-pending", "staging-pending", "blocked"}
EVIDENCE_VALUES = {"pending", "pass", "fail", "blocked", "not-applicable"}
WIKILINK = re.compile(r"\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]")


def fail(message: str) -> None:
    print(f"[odoo-kb-validate] {message}", file=sys.stderr)
    raise SystemExit(1)


def markdown_files() -> list[Path]:
    files = sorted(KB_ROOT.rglob("*.md"))
    files.extend(sorted((ROOT / "plans").glob(PLAN_GLOB)))
    if not files:
        fail("no Odoo KB markdown files found")
    return files


def validate_links(files: list[Path]) -> None:
    targets = {
        path.stem
        for path in files
        if path.is_relative_to(KB_ROOT)
    }
    targets.update(
        str(path.relative_to(KB_ROOT).with_suffix(""))
        for path in files
        if path.is_relative_to(KB_ROOT)
    )
    for path in files:
        if not path.is_relative_to(KB_ROOT):
            continue
        text = path.read_text(encoding="utf-8")
        for target in WIKILINK.findall(text):
            if target not in targets:
                fail(f"missing wikilink target in {path}: {target}")


def validate_status_vocabulary(files: list[Path]) -> None:
    joined = "\n".join(path.read_text(encoding="utf-8") for path in files)
    for value in STATUS_VALUES | EVIDENCE_VALUES:
        if value not in joined:
            fail(f"status vocabulary not documented: {value}")
    for path in files:
        if not path.is_relative_to(KB_ROOT):
            continue
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if not line.startswith("Status:"):
                continue
            status = line.split(":", 1)[1].strip()
            if status not in STATUS_VALUES:
                fail(f"unknown status in {path}:{lineno}: {status}")


def validate_source_index(files: list[Path]) -> None:
    source = KB_ROOT / "99_자료" / "Source-Index.md"
    if source not in files:
        fail("missing KB Source-Index.md")
    text = source.read_text(encoding="utf-8")
    for key in (
        "ODOO-ORM-19",
        "ODOO-MULTICOMPANY-19",
        "ODOO-SECURITY-19",
        "ODOO-VIEWS-19",
        "ODOO-SH-FIRST-MODULE-19",
    ):
        if key not in text:
            fail(f"source index missing required source key: {key}")


def validate_leakage(files: list[Path]) -> None:
    secret_like = re.compile(
        r"(password|passwd|pwd|token|secret|authorization|client[_-]?secret|api[_-]?key|private[_ -]?key)\s*[:=]",
        re.IGNORECASE,
    )
    for path in files:
        text = path.read_text(encoding="utf-8")
        if secret_like.search(text):
            fail(f"secret-like content found in {path}")


def main() -> None:
    files = markdown_files()
    validate_links(files)
    validate_status_vocabulary(files)
    validate_source_index(files)
    validate_leakage(files)
    print(f"[odoo-kb-validate] ok: {len(files)} file(s)")


if __name__ == "__main__":
    main()
