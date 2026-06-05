#!/usr/bin/env python3
"""Report active AI_AUTO TODOs from the canonical backlog."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
import re


DEFAULT_BACKLOG = Path("plans/AI_AUTO_STRUCTURAL_WEAKNESS_BACKLOG.md")
ACTIVE_STATUSES = {"open", "planned_not_run", "insufficiently_run", "contract_started"}
ATTENTION_STATUSES = {"blocked", "approval_needed", "deferred"}
COMPLETE_STATUSES = {
    "complete",
    "complete_contract",
    "complete_observe_mode",
    "display_only_complete",
    "installed_required",
    "operational_clear",
}
NON_ACTIVE_STATUSES = {"advisory_contract", "excluded", "reference_only", "later_gated"}
KNOWN_STATUSES = ACTIVE_STATUSES | ATTENTION_STATUSES | COMPLETE_STATUSES | NON_ACTIVE_STATUSES
OBSERVE_BOUNDARY_PATTERN = re.compile(r"\bnot active\b(?!\s+TODO)", re.IGNORECASE)
MISLEADING_COMPLETION_PATTERNS = (
    re.compile(r"\bcontract[- ]only\b", re.IGNORECASE),
    re.compile(r"\bcontract[- ](cleared|covered|done|met)\b", re.IGNORECASE),
    re.compile(r"\bcontract coverage only\b", re.IGNORECASE),
    re.compile(r"\bno runtime caller\b", re.IGNORECASE),
    re.compile(r"\bno caller\b", re.IGNORECASE),
    re.compile(r"\bruntime\b.*\bnot active\b", re.IGNORECASE),
    re.compile(r"\bruntime\b.*\bmissing\b", re.IGNORECASE),
    re.compile(r"\b(runtime|wiring|caller|call path|operating surface|tooling|gate policy|parity|sync|version)\b.*\b(pending|not implemented|not wired|not synced|missing|absent|unimplemented|mismatch)\b", re.IGNORECASE),
    re.compile(r"\b(pending|missing|absent|unimplemented|not synced|mismatch)\b.*\b(runtime|wiring|caller|call path|operating surface|tooling|gate policy|parity|sync|version)\b", re.IGNORECASE),
    re.compile(r"\b(remains?|remaining)\s+TODO\b", re.IGNORECASE),
    OBSERVE_BOUNDARY_PATTERN,
    re.compile(r"\bparity drift\b", re.IGNORECASE),
    re.compile(r"\bversion mismatch\b", re.IGNORECASE),
    re.compile(r"\bnot synced\b", re.IGNORECASE),
    re.compile(r"\bstill requires?\b", re.IGNORECASE),
    re.compile(r"\bstill needs?\b", re.IGNORECASE),
    re.compile(r"\bstill active TODO\b", re.IGNORECASE),
    re.compile(r"\bnot currently clear\b", re.IGNORECASE),
    re.compile(r"\bseparate execution\b", re.IGNORECASE),
    re.compile(r"\bseparate\s+(future\s+|later\s+)?work\b", re.IGNORECASE),
    re.compile(r"\blater explicit execution\b", re.IGNORECASE),
)


@dataclass(frozen=True)
class TodoItem:
    category: str
    item_id: str
    item: str
    status: str
    note: str


@dataclass(frozen=True)
class TodoBuckets:
    active: list[TodoItem]
    attention: list[TodoItem]
    complete: list[TodoItem]
    non_active: list[TodoItem]


def _cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def _is_table_separator(line: str) -> bool:
    cells = _cells(line)
    return bool(cells) and all(set(cell.replace(" ", "")) <= {"-", ":"} for cell in cells)


def _slug(header: str) -> str:
    return header.strip().lower().replace(" ", "_")


def completion_status_conflict(item: TodoItem) -> str | None:
    if item.status not in COMPLETE_STATUSES:
        return None
    text = item.note.strip()
    if not text:
        return None
    for pattern in MISLEADING_COMPLETION_PATTERNS:
        if pattern.search(text):
            if item.status in {"complete_observe_mode", "display_only_complete"} and pattern is OBSERVE_BOUNDARY_PATTERN:
                continue
            return "complete_status_mentions_unfinished_operating_surface"
    return None


def bucket_items(items: list[TodoItem]) -> TodoBuckets:
    active = [item for item in items if item.status in ACTIVE_STATUSES]
    attention = [item for item in items if item.status in ATTENTION_STATUSES]
    complete: list[TodoItem] = []
    non_active = [item for item in items if item.status in NON_ACTIVE_STATUSES]

    for item in items:
        if item.status not in COMPLETE_STATUSES:
            continue
        if completion_status_conflict(item):
            attention.append(item)
        else:
            complete.append(item)

    return TodoBuckets(active=active, attention=attention, complete=complete, non_active=non_active)


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
    buckets = bucket_items(items)

    lines = [
        "# AI_AUTO TODO Report",
        "",
        f"- active_count: {len(buckets.active)}",
        f"- attention_count: {len(buckets.attention)}",
        f"- complete_count: {len(buckets.complete)}",
        f"- non_active_count: {len(buckets.non_active)}",
        "",
        "## Active TODOs",
        "",
    ]
    if buckets.active:
        lines.extend(["| ID | Category | Item | Status | Note |", "| --- | --- | --- | --- | --- |"])
        for item in buckets.active:
            lines.append(f"| {item.item_id} | {item.category} | {item.item} | {item.status} | {item.note} |")
    else:
        lines.append("None.")

    lines.extend(["", "## Policy Attention", ""])
    if buckets.attention:
        lines.extend(["| ID | Category | Item | Status | Reason | Note |", "| --- | --- | --- | --- | --- | --- |"])
        for item in buckets.attention:
            reason = completion_status_conflict(item) or "policy_attention"
            lines.append(f"| {item.item_id} | {item.category} | {item.item} | {item.status} | {reason} | {item.note} |")
    else:
        lines.append("None.")

    lines.extend(["", "## Complete / Closed", ""])
    if buckets.complete:
        lines.extend(["| ID | Category | Item | Status |", "| --- | --- | --- | --- |"])
        for item in buckets.complete:
            lines.append(f"| {item.item_id} | {item.category} | {item.item} | {item.status} |")
    else:
        lines.append("None.")

    lines.extend(["", "## Non-Active Boundaries", ""])
    if buckets.non_active:
        lines.extend(["| ID | Category | Item | Status |", "| --- | --- | --- | --- |"])
        for item in buckets.non_active:
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
    buckets = bucket_items(items)
    print(format_report(items), end="")
    if args.fail_on_active and (buckets.active or buckets.attention):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
