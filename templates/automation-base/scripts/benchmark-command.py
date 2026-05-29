#!/usr/bin/env python3
"""Optional benchmark evidence capture for AI_AUTO workflows."""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from shlex import join as shell_join


SCHEMA_VERSION = "ai_auto_benchmark_v1"


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def git_commit() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return "unknown"
    return result.stdout.strip() or "unknown"


def tool_version(tool_path: str) -> str:
    try:
        result = subprocess.run(
            [tool_path, "--version"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except OSError:
        return "unknown"
    return (result.stdout.splitlines() or ["unknown"])[0].strip()


def environment_record() -> dict[str, object]:
    return {
        "platform": platform.platform(),
        "python": platform.python_version(),
        "cwd": os.getcwd(),
        "git_commit": git_commit(),
    }


def write_outputs(record: dict[str, object], out_dir: Path, name: str, stamp: str) -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / f"{stamp}-{name}.json"
    md_path = out_dir / f"{stamp}-{name}.md"
    json_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    md_path.write_text(markdown(record), encoding="utf-8")
    return json_path, md_path


def markdown(record: dict[str, object]) -> str:
    tool = record["tool"]
    env = record["environment"]
    lines = [
        f"# Benchmark Evidence - {record['name']}",
        "",
        f"- status: `{record['benchmark_run_status']}`",
        f"- verdict: `{record['verdict']}`",
        f"- command: `{record['command']}`",
        f"- captured_at: `{record['captured_at']}`",
        f"- tool: `{tool['name']}` available=`{tool['available']}` version=`{tool['version']}`",
        f"- git_commit: `{env['git_commit']}`",
    ]
    if record.get("metric"):
        lines.extend(
            [
                f"- metric: `{record['metric']}`",
                f"- sample_count: `{record['sample_count']}`",
                f"- measured_ms: `{record['measured_ms']}`",
            ]
        )
    if record.get("raw_output_json"):
        lines.append(f"- raw_output_json: `{record['raw_output_json']}`")
    if record.get("reason"):
        lines.append(f"- reason: {record['reason']}")
    lines.extend(
        [
            "",
            "This evidence is observational. It does not replace `./scripts/verify.sh` or `./scripts/review-gate.sh`.",
            "",
        ]
    )
    return "\n".join(lines)


def unavailable_record(args: argparse.Namespace, command: str, stamp: str) -> dict[str, object]:
    return {
        "schema_version": SCHEMA_VERSION,
        "name": args.name,
        "command": command,
        "captured_at": stamp,
        "benchmark_run_status": "unavailable",
        "verdict": "unavailable",
        "reason": "hyperfine_not_installed",
        "sample_count": 0,
        "environment": environment_record(),
        "tool": {"name": "hyperfine", "available": False, "version": None},
        "claims_readiness": False,
        "replaces_verify": False,
        "replaces_review_gate": False,
    }


def run_hyperfine(args: argparse.Namespace, command: str, stamp: str, hyperfine_path: str) -> dict[str, object]:
    out_dir = Path(args.out_dir)
    raw_path = out_dir / f"{stamp}-{args.name}.hyperfine.json"
    raw_path.parent.mkdir(parents=True, exist_ok=True)
    run = subprocess.run(
        [
            hyperfine_path,
            "--warmup",
            str(args.warmup),
            "--runs",
            str(args.runs),
            "--export-json",
            str(raw_path),
            command,
        ],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    base = {
        "schema_version": SCHEMA_VERSION,
        "name": args.name,
        "command": command,
        "captured_at": stamp,
        "environment": environment_record(),
        "tool": {"name": "hyperfine", "available": True, "version": tool_version(hyperfine_path)},
        "claims_readiness": False,
        "replaces_verify": False,
        "replaces_review_gate": False,
        "raw_output_json": str(raw_path),
        "hyperfine_stdout": run.stdout[-4000:],
    }
    if run.returncode != 0:
        return {
            **base,
            "benchmark_run_status": "fail",
            "verdict": "fail",
            "reason": "hyperfine_failed",
            "sample_count": 0,
        }

    try:
        raw = json.loads(raw_path.read_text(encoding="utf-8"))
        first = raw.get("results", [{}])[0]
        mean_seconds = float(first.get("mean", 0))
    except (OSError, ValueError, TypeError, IndexError) as exc:
        return {
            **base,
            "benchmark_run_status": "error",
            "verdict": "error",
            "reason": f"invalid_hyperfine_json:{exc.__class__.__name__}",
            "sample_count": 0,
        }
    measured_ms = round(mean_seconds * 1000, 3)
    return {
        **base,
        "benchmark_run_status": "pass",
        "verdict": "observed",
        "metric": "runtime_ms",
        "sample_count": int(first.get("runs") or args.runs),
        "measured_ms": measured_ms,
        "stddev_ms": round(float(first.get("stddev", 0)) * 1000, 3),
        "min_ms": round(float(first.get("min", 0)) * 1000, 3) if "min" in first else None,
        "max_ms": round(float(first.get("max", 0)) * 1000, 3) if "max" in first else None,
        "threshold_stage": "observe",
        "reason": "measurement_recorded_without_readiness_claim",
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Capture optional AI_AUTO benchmark evidence.")
    parser.add_argument("--name", required=True, help="Stable benchmark scenario name.")
    parser.add_argument("--out-dir", default="plans/benchmarks", help="Directory for JSON and Markdown evidence.")
    parser.add_argument("--runs", type=int, default=10, help="Hyperfine run count.")
    parser.add_argument("--warmup", type=int, default=1, help="Hyperfine warmup count.")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Command after --.")
    args = parser.parse_args(argv)
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("command is required after --")
    if args.runs < 1:
        parser.error("--runs must be >= 1")
    if args.warmup < 0:
        parser.error("--warmup must be >= 0")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    stamp = utc_stamp()
    name = "".join(ch if ch.isalnum() or ch in "-_" else "-" for ch in args.name).strip("-_")
    args.name = name or "benchmark"
    command = shell_join(args.command)
    hyperfine_path = shutil.which("hyperfine")
    if hyperfine_path is None:
        record = unavailable_record(args, command, stamp)
    else:
        record = run_hyperfine(args, command, stamp, hyperfine_path)
    json_path, md_path = write_outputs(record, Path(args.out_dir), args.name, stamp)
    print(json_path)
    print(md_path)
    return 0 if record["benchmark_run_status"] in {"pass", "unavailable"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
