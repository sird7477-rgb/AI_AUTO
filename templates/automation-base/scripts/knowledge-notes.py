#!/usr/bin/env python3
"""Create and validate curated AI_AUTO knowledge notes.

This helper intentionally writes only sanitized Markdown notes. It does not
mirror raw .omx artifacts, resolve feedback queues, or promote guidance.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from datetime import date
from pathlib import Path


TYPES = {"incident", "finding", "lesson", "technical-spec", "promotion-candidate"}
STATUSES = {"draft", "open", "resolved", "deferred", "rejected"}
SEVERITIES = {"low", "medium", "high", "critical"}
SYNC_CLASSES = {"local_repo_index", "local_private", "external_private_vault", "shareable_summary"}
REDACTION_STATUSES = {"sanitized", "redacted"}
CONFIDENCE = {"low", "medium", "high"}
PROMOTION_STATES = {
    "not_candidate",
    "repeated_pattern",
    "guideline_candidate",
    "accepted_change",
    "rejected",
    "deferred",
}
STORAGE_SIGNALS = {"user-request", "user-supplied", "workflow-required"}

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
UNSAFE_SOURCE_PATTERNS = (
    ".omx/logs/",
    ".omx/review-prompts/",
    ".omx/review-context/",
    ".omx/external-review/",
    ".omx/state/",
    ".env",
    "id_rsa",
    "id_ed25519",
)
GENERATED_INDEX_NAMES = {"AI_AUTO_INDEX.md"}


def fail(message: str) -> None:
    raise SystemExit(f"[knowledge] {message}")


def has_secret(value: str) -> bool:
    return bool(SECRET_PATTERN.search(value or ""))


def validate_text(label: str, value: str) -> None:
    if has_secret(value):
        fail(f"refusing secret-like content in {label}")


def validate_frontmatter_scalar(label: str, value: object) -> None:
    text = str(value)
    if "\n" in text or "\r" in text:
        fail(f"frontmatter field must be single-line: {label}")


def normalized_parts(value: str) -> list[str]:
    return [part for part in value.replace("\\", "/").split("/") if part not in ("", ".")]


def validate_source_artifact(value: str, path: str = "<input>") -> None:
    validate_text(f"{path}:source_artifact", value)
    normalized = value.replace("\\", "/")
    parts = normalized_parts(normalized)
    if Path(normalized).is_absolute() or re.match(r"^[A-Za-z]:/", normalized):
        fail(f"{path}: source_artifact must be a project-relative reference")
    if ".." in parts:
        fail(f"{path}: source_artifact must not contain path traversal")
    if any(pattern in normalized for pattern in UNSAFE_SOURCE_PATTERNS):
        fail(f"{path}: unsafe source_artifact: {value}")


def has_symlink_component(path: Path) -> bool:
    current = Path(path.anchor) if path.is_absolute() else Path(".")
    for part in path.parts:
        if part in ("", ".") or part == path.anchor:
            continue
        current = current / part
        if current.is_symlink():
            return True
    return False


def validate_output_dir(path: Path, allow_local_draft: bool) -> None:
    parts = normalized_parts(str(path))
    resolved_parts = list(path.resolve(strict=False).parts)
    if path.is_absolute():
        try:
            parts = list(path.resolve(strict=False).relative_to(Path.cwd().resolve()).parts)
        except ValueError:
            parts = list(path.parts)
    if (any(part == ".omx" for part in parts) or any(part == ".omx" for part in resolved_parts)) and not allow_local_draft:
        fail("output under .omx requires --allow-local-draft and must not be treated as durable vault storage")
    if has_symlink_component(path):
        fail(f"refusing output directory with symlink component: {path}")


def slugify(value: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._:-]+", "-", value.strip().lower()).strip("-")
    slug = re.sub(r"-{2,}", "-", slug)
    return slug[:80] or "note"


def yaml_quote(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    text = str(value)
    if text == "" or re.search(r"[:#\[\]{}&*!|>'\"%@`\n\r\t]", text) or text.strip() != text:
        return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return text


def parse_frontmatter(path: Path) -> dict[str, str]:
    # Supports only the flat scalar frontmatter written by this helper.
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    if not text.startswith("---\n"):
        fail(f"missing YAML frontmatter: {path}")
    end = text.find("\n---\n", 4)
    if end < 0:
        fail(f"unterminated YAML frontmatter: {path}")
    data: dict[str, str] = {}
    for lineno, line in enumerate(text[4:end].splitlines(), start=2):
        if not line.strip():
            continue
        if ":" not in line:
            fail(f"invalid frontmatter line {path}:{lineno}")
        key, raw = line.split(":", 1)
        key = key.strip()
        if key in data:
            fail(f"duplicate frontmatter key {path}:{lineno}: {key}")
        value = raw.strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        data[key] = value
    return data


def note_body(path: Path) -> str:
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    end = text.find("\n---\n", 4)
    if end < 0:
        return ""
    return text[end + len("\n---\n") :]


def validation_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def validate_note_data(data: dict[str, str], path: str = "<input>") -> None:
    for field, value in data.items():
        validate_frontmatter_scalar(f"{path}:{field}", value)
        validate_text(f"{path}:{field}", value)

    required = [
        "type",
        "status",
        "title",
        "summary",
        "project",
        "surface",
        "severity",
        "repeat_key",
        "source_artifact",
        "source_hash",
        "sync_class",
        "redaction_status",
        "evidence_count",
        "confidence",
        "promotion_state",
        "created",
        "updated",
    ]
    missing = [field for field in required if not data.get(field)]
    if missing:
        fail(f"{path}: missing required fields: {', '.join(missing)}")

    enum_checks = {
        "type": TYPES,
        "status": STATUSES,
        "severity": SEVERITIES,
        "sync_class": SYNC_CLASSES,
        "redaction_status": REDACTION_STATUSES,
        "confidence": CONFIDENCE,
        "promotion_state": PROMOTION_STATES,
    }
    for field, allowed in enum_checks.items():
        if data[field] not in allowed:
            fail(f"{path}: unsupported {field}: {data[field]}")

    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", data["created"]):
        fail(f"{path}: created must use YYYY-MM-DD")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", data["updated"]):
        fail(f"{path}: updated must use YYYY-MM-DD")
    if ":" not in data["repeat_key"]:
        fail(f"{path}: repeat_key must use <surface>:<short-slug>")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", data["source_hash"]):
        fail(f"{path}: source_hash must use sha256:<64 lowercase hex chars>")
    try:
        evidence_count = int(data["evidence_count"])
    except ValueError as exc:
        raise SystemExit(f"[knowledge] {path}: evidence_count must be an integer") from exc
    if evidence_count < 1:
        fail(f"{path}: evidence_count must be >= 1")
    promote_to_guideline = str(data.get("promote_to_guideline")).lower() == "true"
    if data["promotion_state"] == "repeated_pattern" and evidence_count < 2:
        fail(f"{path}: repeated_pattern requires evidence_count >= 2")
    reviewed_change_states = {"guideline_candidate", "accepted_change"}
    if data["promotion_state"] in reviewed_change_states or promote_to_guideline:
        high_severity_exception = data["severity"] in {"high", "critical"} and bool(data.get("review_evidence"))
        if evidence_count < 2 and not high_severity_exception:
            fail(f"{path}: reviewed promotion state requires repeated evidence or high-severity review evidence")
        if not data.get("review_evidence"):
            fail(f"{path}: reviewed promotion state requires review_evidence")
    if data["type"] == "technical-spec" and data.get("storage_signal") not in STORAGE_SIGNALS:
        fail(f"{path}: technical-spec requires storage_signal")
    if data["type"] == "lesson" and data.get("outcome") == "positive":
        signals = [
            data.get("observed_benefit"),
            data.get("target_completed"),
            data.get("blocker_removed"),
            data.get("prevention_added"),
            data.get("reuse_observed"),
            data.get("cost_reduction_observed"),
        ]
        if not any(value and value != "false" for value in signals):
            fail(f"{path}: positive lesson requires an observable signal")
    validate_source_artifact(data["source_artifact"], path)


def write_note(args: argparse.Namespace) -> None:
    created = args.created or date.today().isoformat()
    updated = args.updated or created
    source_extract = args.source_extract
    for label, value in (
        ("title", args.title),
        ("summary", args.summary),
        ("source_artifact", args.source_artifact),
        ("source_extract", source_extract),
        ("body", args.body or ""),
    ):
        validate_text(label, value)

    data: dict[str, object] = {
        "type": args.type,
        "status": args.status,
        "title": args.title,
        "summary": args.summary,
        "project": args.project,
        "surface": args.surface,
        "severity": args.severity,
        "repeat_key": args.repeat_key,
        "source_artifact": args.source_artifact,
        "source_hash": "sha256:" + hashlib.sha256(source_extract.encode("utf-8")).hexdigest(),
        "sync_class": args.sync_class,
        "redaction_status": args.redaction_status,
        "evidence_count": args.evidence_count,
        "confidence": args.confidence,
        "promotion_state": args.promotion_state,
        "created": created,
        "updated": updated,
    }
    optional_fields = [
        "project_type",
        "stack",
        "domain_pack",
        "source_repo",
        "candidate_kind",
        "next_action",
        "last_verified",
        "review_evidence",
        "outcome",
        "observed_benefit",
        "uncertainty",
        "storage_signal",
    ]
    for field in optional_fields:
        value = getattr(args, field)
        if value:
            data[field] = value
    for field in (
        "promote_to_guideline",
        "target_completed",
        "blocker_removed",
        "prevention_added",
        "reuse_observed",
        "cost_reduction_observed",
    ):
        value = getattr(args, field)
        if value is not None:
            data[field] = value
    if args.reused_count is not None:
        data["reused_count"] = args.reused_count

    for key, value in data.items():
        validate_text(key, str(value))
        validate_frontmatter_scalar(key, value)
    validate_note_data({key: validation_value(value) for key, value in data.items()})

    output_dir = Path(args.output_dir)
    validate_output_dir(output_dir, args.allow_local_draft)
    filename = f"{created}--{slugify(args.repeat_key)}--{slugify(args.title)}.md"
    output_path = output_dir / filename
    if not args.write:
        print(f"[knowledge] dry-run would write {output_path}")
        return

    output_dir.mkdir(parents=True, exist_ok=True)
    if output_path.exists() and not args.force:
        fail(f"refusing to overwrite existing note: {output_path}")

    lines = ["---"]
    for key in sorted(data):
        lines.append(f"{key}: {yaml_quote(data[key])}")
    lines.extend(
        [
            "---",
            "",
            f"# {args.title}",
            "",
            "## Summary",
            "",
            args.summary,
            "",
            "## Details",
            "",
            args.body or "Draft note. Add sanitized details before relying on this as curated knowledge.",
            "",
            "## Source",
            "",
            f"- artifact: `{args.source_artifact}`",
            f"- source_hash: `{data['source_hash']}`",
        ]
    )
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[knowledge] wrote {output_path}")


def validate_directory(args: argparse.Namespace) -> None:
    root = Path(args.path)
    if not root.exists():
        fail(f"path does not exist: {root}")
    if has_symlink_component(root):
        fail(f"refusing validation path with symlink component: {root}")
    files = sorted(root.rglob("*.md")) if root.is_dir() else [root]
    validation_root = root.resolve(strict=False) if root.is_dir() else root.parent.resolve(strict=False)
    checked = 0
    for path in files:
        if path.name in GENERATED_INDEX_NAMES:
            continue
        resolved_path = path.resolve(strict=False)
        if not resolved_path.is_relative_to(validation_root):
            fail(f"{path}: validated notes must stay under the validation root")
        data = parse_frontmatter(path)
        validate_note_data(data, str(path))
        validate_text(f"{path}:body", note_body(path))
        checked += 1
    print(f"[knowledge] validated {checked} note(s)")


def write_index(args: argparse.Namespace) -> None:
    notes_dir = Path(args.notes_dir)
    output = Path(args.output)
    validate_output_dir(output.parent, args.allow_local_draft)
    output_parent = output.parent.resolve(strict=False)
    output_resolved = output.resolve(strict=False)
    files = sorted(notes_dir.rglob("*.md")) if notes_dir.exists() else []
    rows: list[tuple[dict[str, str], Path]] = []
    for path in files:
        resolved_path = path.resolve(strict=False)
        if resolved_path == output_resolved or path.name in GENERATED_INDEX_NAMES:
            continue
        if not resolved_path.is_relative_to(output_parent):
            fail(f"{path}: indexed notes must be under the index output directory")
        data = parse_frontmatter(path)
        validate_note_data(data, str(path))
        validate_text(f"{path}:body", note_body(path))
        rows.append((data, resolved_path))

    output.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# AI_AUTO Knowledge Index",
        "",
        "This index is generated from curated knowledge notes. It is advisory only.",
        "",
        "## Notes",
        "",
        "| Type | Status | Surface | Repeat Key | Title | Updated |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for data, path in rows:
        rel = path.relative_to(output_parent).as_posix()
        lines.append(
            f"| {data['type']} | {data['status']} | {data['surface']} | "
            f"{data['repeat_key']} | [{data['title']}]({rel}) | {data['updated']} |"
        )
    lines.extend(
        [
            "",
            "## Views",
            "",
            "- Inbox: `status = draft`",
            "- Open Incidents: `type = incident` and `status != resolved`",
            "- Repeat Keys: group by `repeat_key`",
            "- Promotion Candidates: `type = promotion-candidate` or `promote_to_guideline = true`",
            "- Project Onboarding: filter by `project_type`, `stack`, `domain_pack`, and `surface`",
            "- Recently Updated: sort by `updated desc`",
        ]
    )
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[knowledge] indexed {len(rows)} note(s) in {output}")


def add_common_record_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--type", required=True, choices=sorted(TYPES))
    parser.add_argument("--status", default="draft", choices=sorted(STATUSES))
    parser.add_argument("--title", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--surface", required=True)
    parser.add_argument("--severity", default="medium", choices=sorted(SEVERITIES))
    parser.add_argument("--repeat-key", required=True)
    parser.add_argument("--source-artifact", required=True)
    parser.add_argument("--source-extract", required=True, help="sanitized exact source extract used for source_hash")
    parser.add_argument("--sync-class", default="local_private", choices=sorted(SYNC_CLASSES))
    parser.add_argument("--redaction-status", default="sanitized", choices=sorted(REDACTION_STATUSES))
    parser.add_argument("--evidence-count", type=int, default=1)
    parser.add_argument("--confidence", default="low", choices=sorted(CONFIDENCE))
    parser.add_argument("--promotion-state", default="not_candidate", choices=sorted(PROMOTION_STATES))
    parser.add_argument("--created")
    parser.add_argument("--updated")
    parser.add_argument("--project-type")
    parser.add_argument("--stack")
    parser.add_argument("--domain-pack")
    parser.add_argument("--source-repo")
    parser.add_argument("--candidate-kind")
    parser.add_argument("--next-action")
    parser.add_argument("--last-verified")
    parser.add_argument("--review-evidence")
    parser.add_argument("--promote-to-guideline", action=argparse.BooleanOptionalAction)
    parser.add_argument("--outcome")
    parser.add_argument("--observed-benefit")
    parser.add_argument("--target-completed", action=argparse.BooleanOptionalAction)
    parser.add_argument("--blocker-removed", action=argparse.BooleanOptionalAction)
    parser.add_argument("--prevention-added", action=argparse.BooleanOptionalAction)
    parser.add_argument("--reuse-observed", action=argparse.BooleanOptionalAction)
    parser.add_argument("--reused-count", type=int)
    parser.add_argument("--cost-reduction-observed", action=argparse.BooleanOptionalAction)
    parser.add_argument("--uncertainty")
    parser.add_argument("--storage-signal", choices=sorted(STORAGE_SIGNALS))
    parser.add_argument("--body")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--allow-local-draft", action="store_true")
    parser.add_argument("--write", action="store_true", help="write the note; default is dry-run validation only")
    parser.add_argument("--force", action="store_true")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Create and validate AI_AUTO knowledge notes.")
    sub = parser.add_subparsers(dest="command", required=True)

    record = sub.add_parser("record", help="write one curated Markdown knowledge note")
    add_common_record_args(record)
    record.set_defaults(func=write_note)

    validate = sub.add_parser("validate", help="validate a note file or directory")
    validate.add_argument("path", nargs="?", default=".omx/knowledge")
    validate.set_defaults(func=validate_directory)

    index = sub.add_parser("index", help="generate an advisory Markdown index")
    index.add_argument("--notes-dir", default=".omx/knowledge")
    index.add_argument("--output", required=True)
    index.add_argument("--allow-local-draft", action="store_true")
    index.set_defaults(func=write_index)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
