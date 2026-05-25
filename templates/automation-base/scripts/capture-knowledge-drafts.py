#!/usr/bin/env python3
"""Capture sanitized operational signals as local knowledge-note drafts."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


SECRET_PATTERN = re.compile(
    r"(^|[^A-Za-z0-9_])("
    r"(password|passwd|pwd|token|secret|authorization|client[_-]?secret|api[_-]?key|apikey|access[_-]?key|private[_ -]?key)\s*[:=]"
    r"|bearer\s+|ssh-rsa|ssh-ed25519|begin\s+[^ \t\r\n]*\s*private\s+key"
    r"|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9_]{20,}"
    r"|cookie\s*[:=]|set-cookie\s*:"
    r"|https?://[^/\s:@]+:[^/\s@]+@"
    r"|/(home|Users|root|mnt)/[^\s]+"
    r"|\b(system|developer|user)\s+prompt\s*:"
    r"|screenshot\s*[:=]"
    r")",
    re.IGNORECASE,
)


def fail(message: str) -> None:
    raise SystemExit(f"[capture] {message}")


def has_secret(value: str) -> bool:
    return bool(SECRET_PATTERN.search(value or ""))


def slugify(value: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._:-]+", "-", value.strip().lower()).strip("-")
    slug = re.sub(r"-{2,}", "-", slug)
    return slug[:80] or "item"


def project_name() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        return Path(result.stdout.strip()).name
    except (subprocess.CalledProcessError, FileNotFoundError):
        return Path.cwd().name


def latest_file(directory: Path, pattern: str) -> Path | None:
    if not directory.exists():
        return None
    files = sorted(directory.glob(pattern), key=lambda path: path.stat().st_mtime, reverse=True)
    return files[0] if files else None


def artifact_ref(path: Path) -> str:
    try:
        return str(path.resolve(strict=False).relative_to(Path.cwd().resolve()))
    except ValueError:
        return str(path)


def parse_verdict(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    current_heading = ""
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line.startswith("## "):
            current_heading = line[3:].strip()
            continue
        if not line or line.startswith("|") or line.startswith("-"):
            continue
        if current_heading and current_heading not in data:
            data[current_heading] = line
    return data


def existing_repeat_keys(output_dir: Path) -> set[str]:
    keys: set[str] = set()
    if not output_dir.exists():
        return keys
    for path in output_dir.glob("*.md"):
        try:
            for raw_line in path.read_text(encoding="utf-8").splitlines():
                if raw_line.startswith("repeat_key:"):
                    value = raw_line.split(":", 1)[1].strip().strip('"')
                    if value:
                        keys.add(value)
                    break
        except OSError:
            continue
    return keys


def run_record(args: argparse.Namespace, fields: dict[str, str]) -> bool:
    values = [str(value) for value in fields.values()]
    if any(has_secret(value) for value in values):
        print(f"[capture] skipped secret-like item: {fields.get('repeat_key', 'unknown')}", file=sys.stderr)
        return False
    if args.write and fields["repeat_key"] in existing_repeat_keys(args.output_dir):
        print(f"[capture] skipped existing draft: {fields['repeat_key']}")
        return False

    command = [
        str(args.knowledge_helper),
        "record",
        "--type",
        fields["type"],
        "--status",
        fields.get("status", "draft"),
        "--title",
        fields["title"],
        "--summary",
        fields["summary"],
        "--project",
        args.project,
        "--surface",
        fields["surface"],
        "--severity",
        fields.get("severity", "medium"),
        "--repeat-key",
        fields["repeat_key"],
        "--source-artifact",
        fields["source_artifact"],
        "--source-extract",
        fields["source_extract"],
        "--confidence",
        fields.get("confidence", "medium"),
        "--sync-class",
        "local_private",
        "--output-dir",
        str(args.output_dir),
        "--allow-local-draft",
    ]
    if fields.get("promotion_state"):
        command.extend(["--promotion-state", fields["promotion_state"]])
    if fields.get("evidence_count"):
        command.extend(["--evidence-count", fields["evidence_count"]])
    if fields.get("review_evidence"):
        command.extend(["--review-evidence", fields["review_evidence"]])
    if fields.get("body"):
        command.extend(["--body", fields["body"]])
    if args.write:
        command.append("--write")

    subprocess.run(command, check=True)
    return True


def capture_feedback(args: argparse.Namespace) -> int:
    path = args.feedback_file
    if not path.exists():
        print(f"[capture] feedback queue missing: {path}")
        return 0

    count = 0
    with path.open(encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError as exc:
                print(f"[capture] skipped invalid feedback JSON line {lineno}: {exc}", file=sys.stderr)
                continue
            if entry.get("status", "open") != "open":
                continue

            entry_type = entry.get("type", "failure_pattern")
            note_type = "incident" if entry_type == "failure_pattern" else "finding"
            surface = entry.get("surface") or "feedback"
            repeat_key = entry.get("repeat_key") or f"{surface}:feedback-{lineno}"
            summary = entry.get("summary") or "Sanitized feedback item captured for review."
            title = summary[:80]
            source_extract = f"{entry_type}:{repeat_key}:{summary}"
            body = entry.get("resolution") or "Captured automatically from the sanitized project feedback queue."

            if run_record(
                args,
                {
                    "type": note_type,
                    "status": "draft",
                    "title": title,
                    "summary": summary,
                    "surface": surface,
                    "severity": entry.get("severity", "medium"),
                    "repeat_key": repeat_key,
                    "source_artifact": artifact_ref(path),
                    "source_extract": source_extract,
                    "body": body,
                },
            ):
                count += 1
    return count


def capture_review_gate(args: argparse.Namespace) -> int:
    verdict = args.review_verdict or latest_file(Path(".omx/review-results"), "review-verdict-*.md")
    if verdict is None or not verdict.exists():
        print("[capture] review verdict missing")
        return 0

    data = parse_verdict(verdict)
    decision = data.get("Final Decision", "unknown")
    missing = data.get("Missing Or Unusable Reviewers", "none")
    if decision == "proceed" and missing == "none" and not args.include_success:
        print("[capture] skipped clean review-gate success")
        return 0

    severity = "medium" if decision in {"proceed_degraded", "review_manually"} else "high"
    summary = f"Review gate ended as {decision}; missing reviewers: {missing}."
    return int(
        run_record(
            args,
            {
                "type": "finding",
                "status": "draft",
                "title": f"Review gate {decision}",
                "summary": summary,
                "surface": "review-gate",
                "severity": severity,
                "repeat_key": f"review-gate:{slugify(decision)}",
                "source_artifact": artifact_ref(verdict),
                "source_extract": summary,
                "body": "Captured automatically from the review-gate verdict. Treat as a local draft until reviewed.",
            },
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Capture sanitized local knowledge drafts from AI_AUTO runtime signals.")
    parser.add_argument("--source", choices=["all", "feedback", "review-gate"], default="all")
    parser.add_argument("--feedback-file", type=Path, default=Path(".omx/feedback/queue.jsonl"))
    parser.add_argument("--review-verdict", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path(".omx/knowledge/drafts"))
    parser.add_argument("--knowledge-helper", type=Path, default=Path("scripts/knowledge-notes.py"))
    parser.add_argument("--project", default=project_name())
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--include-success", action="store_true")
    args = parser.parse_args()

    total = 0
    if args.source in {"all", "feedback"}:
        total += capture_feedback(args)
    if args.source in {"all", "review-gate"}:
        total += capture_review_gate(args)
    print(f"[capture] captured {total} draft candidate(s)")


if __name__ == "__main__":
    main()
