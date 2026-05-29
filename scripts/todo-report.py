#!/usr/bin/env python3
"""Report active AI_AUTO TODOs from the canonical backlog."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path


DEFAULT_BACKLOG = Path("plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md")
ACTIVE_STATUSES = {"open", "planned_not_run", "insufficiently_run", "contract_started"}
ATTENTION_STATUSES = {"blocked", "approval_needed", "deferred"}
COMPLETE_STATUSES = {
    "complete",
    "complete_contract",
    "complete_observe_mode",
    "display_only_complete",
    "installed_required",
}
NON_ACTIVE_STATUSES = {"excluded", "reference_only", "later_gated"}
KNOWN_STATUSES = ACTIVE_STATUSES | ATTENTION_STATUSES | COMPLETE_STATUSES | NON_ACTIVE_STATUSES


@dataclass(frozen=True)
class TodoItem:
    category: str
    item_id: str
    item: str
    status: str
    note: str


def _cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def _is_table_separator(line: str) -> bool:
    cells = _cells(line)
    return bool(cells) and all(set(cell.replace(" ", "")) <= {"-", ":"} for cell in cells)


def _slug(header: str) -> str:
    return header.strip().lower().replace(" ", "_")


def parse_backlog(text: str) -> list[TodoItem]:
    items: list[TodoItem] = []
    category = ""
    headers: list[str] | None = None

    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("## "):
            category = line.removeprefix("## ").strip()
            headers = None
            continue
        if not line.startswith("|"):
            headers = None
            continue
        if _is_table_separator(line):
            continue

        cells = _cells(line)
        if headers is None:
            headers = [_slug(cell) for cell in cells]
            continue
        if len(cells) != len(headers):
            continue

        row = dict(zip(headers, cells))
        status = row.get("status")
        if status not in KNOWN_STATUSES:
            continue
        item_id = row.get("id", "")
        item = row.get("item") or row.get("slice") or row.get("area") or ""
        note = row.get("next_gate") or row.get("boundary_note") or row.get("reason") or row.get("status") or ""
        items.append(TodoItem(category=category, item_id=item_id, item=item, status=status, note=note))

    return items


def format_report(items: list[TodoItem]) -> str:
    active = [item for item in items if item.status in ACTIVE_STATUSES]
    attention = [item for item in items if item.status in ATTENTION_STATUSES]
    complete = [item for item in items if item.status in COMPLETE_STATUSES]
    non_active = [item for item in items if item.status in NON_ACTIVE_STATUSES]

    lines = [
        "# AI_AUTO TODO Report",
        "",
        f"- active_count: {len(active)}",
        f"- attention_count: {len(attention)}",
        f"- complete_count: {len(complete)}",
        f"- non_active_count: {len(non_active)}",
        "",
        "## Active TODOs",
        "",
    ]
    if active:
        lines.extend(["| ID | Category | Item | Status | Note |", "| --- | --- | --- | --- | --- |"])
        for item in active:
            lines.append(f"| {item.item_id} | {item.category} | {item.item} | {item.status} | {item.note} |")
    else:
        lines.append("None.")

    lines.extend(["", "## Policy Attention", ""])
    if attention:
        lines.extend(["| ID | Category | Item | Status | Note |", "| --- | --- | --- | --- | --- |"])
        for item in attention:
            lines.append(f"| {item.item_id} | {item.category} | {item.item} | {item.status} | {item.note} |")
    else:
        lines.append("None.")

    lines.extend(["", "## Complete / Closed", ""])
    if complete:
        lines.extend(["| ID | Category | Item | Status |", "| --- | --- | --- | --- |"])
        for item in complete:
            lines.append(f"| {item.item_id} | {item.category} | {item.item} | {item.status} |")
    else:
        lines.append("None.")

    lines.extend(["", "## Non-Active Boundaries", ""])
    if non_active:
        lines.extend(["| ID | Category | Item | Status |", "| --- | --- | --- | --- |"])
        for item in non_active:
            lines.append(f"| {item.item_id} | {item.category} | {item.item} | {item.status} |")
    else:
        lines.append("None.")

    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Report active AI_AUTO TODOs from the canonical backlog.")
    parser.add_argument("--backlog", default=str(DEFAULT_BACKLOG), help="Backlog markdown file to parse.")
    parser.add_argument("--fail-on-active", action="store_true", help="Exit nonzero when active TODOs remain.")
    args = parser.parse_args(argv)

    backlog = Path(args.backlog)
    try:
        text = backlog.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"todo-report: cannot read {backlog}: {exc}", file=sys.stderr)
        return 2

    items = parse_backlog(text)
    active_count = sum(1 for item in items if item.status in ACTIVE_STATUSES)
    attention_count = sum(1 for item in items if item.status in ATTENTION_STATUSES)
    print(format_report(items), end="")
    if args.fail_on_active and (active_count or attention_count):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
