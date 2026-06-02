#!/usr/bin/env python3
"""Append one validated model-routing lane decision to the lane-decisions log.

Phase 1 of the cross-runtime model-routing plan (ST-P1-22). This is the per-unit
observability recorder: a runtime that routes a unit of work onto a model class
calls this to log the decision. The record is evidence only and carries NO
completion authority. Records go to a dedicated log, separate from the
reviewer-lane observations.tsv, to avoid a schema collision.
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_LOG = Path(".omx/model-routing/lane-decisions.tsv")
MAX_ROWS = 1000
HEADER = [
    "timestamp",
    "principal",
    "lane",
    "role",
    "requested_class",
    "resolved_model",
    "model_source",
    "model_class_applied",
    "reason",
    "fallback",
    "confidence",
]

PRINCIPALS = {"codex", "claude", "gemini"}
LANES = {"fast_scan", "low_cost_impl", "standard_impl", "frontier_review"}
CLASSES = {"fast", "standard", "frontier"}
APPLIED = {"true", "false"}
CONFIDENCE = {"high", "medium", "low"}


def validate(args: argparse.Namespace) -> list[str]:
    errors: list[str] = []
    if args.principal not in PRINCIPALS:
        errors.append(f"principal must be one of {sorted(PRINCIPALS)}")
    if args.lane not in LANES:
        errors.append(f"lane must be one of {sorted(LANES)}")
    if args.requested_class not in CLASSES:
        errors.append(f"requested-class must be one of {sorted(CLASSES)}")
    if args.model_class_applied not in APPLIED:
        errors.append("model-class-applied must be 'true' or 'false'")
    if args.confidence not in CONFIDENCE:
        errors.append(f"confidence must be one of {sorted(CONFIDENCE)}")
    # When the requested class was not applied, the reason must explain why so a
    # routing record can never silently hide a class_unavailable/override/escalation.
    if args.model_class_applied == "false" and not args.reason.strip():
        errors.append("reason is required when model-class-applied=false")
    # Tab/newline would corrupt the TSV row.
    for name, value in (
        ("reason", args.reason),
        ("resolved_model", args.resolved_model),
        ("model_source", args.model_source),
        ("fallback", args.fallback),
        ("role", args.role),
    ):
        if "\t" in value or "\n" in value:
            errors.append(f"{name} must not contain tab or newline")
    return errors


def append_record(log_path: Path, row: list[str]) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    existing: list[str] = []
    if log_path.exists():
        existing = log_path.read_text(encoding="utf-8").splitlines()
    if not existing or existing[0] != "\t".join(HEADER):
        existing = ["\t".join(HEADER)]
    existing.append("\t".join(row))
    # Cap to header + most recent MAX_ROWS data rows.
    body = existing[1:]
    if len(body) > MAX_ROWS:
        body = body[-MAX_ROWS:]
    log_path.write_text("\n".join([existing[0], *body]) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--principal", required=True)
    parser.add_argument("--lane", required=True)
    parser.add_argument("--role", default="")
    parser.add_argument("--requested-class", required=True, dest="requested_class")
    parser.add_argument("--resolved-model", default="", dest="resolved_model")
    parser.add_argument("--model-source", default="", dest="model_source")
    parser.add_argument("--model-class-applied", required=True, dest="model_class_applied")
    parser.add_argument("--reason", default="")
    parser.add_argument("--fallback", default="")
    parser.add_argument("--confidence", required=True)
    parser.add_argument("--log", default=str(DEFAULT_LOG), type=Path)
    args = parser.parse_args(argv)

    errors = validate(args)
    if errors:
        for error in errors:
            print(f"[lane-decision] invalid: {error}", file=sys.stderr)
        return 2

    row = [
        datetime.now(timezone.utc).isoformat(),
        args.principal,
        args.lane,
        args.role,
        args.requested_class,
        args.resolved_model,
        args.model_source,
        args.model_class_applied,
        args.reason,
        args.fallback,
        args.confidence,
    ]
    append_record(args.log, row)
    print(str(args.log))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
