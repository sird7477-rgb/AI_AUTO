from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from scripts.self_demo_contracts import benchmark_capture_record


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "benchmark-command.py"


def run_benchmark(tmp_path: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--name",
            "verify smoke",
            "--out-dir",
            str(tmp_path),
            "--runs",
            "3",
            "--warmup",
            "0",
            "--",
            sys.executable,
            "-c",
            "print('ok')",
        ],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


def json_output_path(result: subprocess.CompletedProcess[str]) -> Path:
    return Path(result.stdout.splitlines()[0])


def test_benchmark_command_records_unavailable_when_hyperfine_missing(tmp_path: Path) -> None:
    env = {**os.environ, "PATH": str(tmp_path / "empty-bin")}
    (tmp_path / "empty-bin").mkdir()

    result = run_benchmark(tmp_path, env)

    assert result.returncode == 0, result.stderr
    record = json.loads(json_output_path(result).read_text(encoding="utf-8"))
    assert record["schema_version"] == "ai_auto_benchmark_v1"
    assert record["benchmark_run_status"] == "unavailable"
    assert record["verdict"] == "unavailable"
    assert record["tool"] == {"name": "hyperfine", "available": False, "version": None}
    assert record["sample_count"] == 0
    assert record["claims_readiness"] is False
    assert record["replaces_verify"] is False
    assert record["replaces_review_gate"] is False
    assert benchmark_capture_record(record).reason == "benchmark_capture_unavailable_recorded"


def test_benchmark_command_uses_hyperfine_when_available(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    fake = bin_dir / "hyperfine"
    fake.write_text(
        """#!/usr/bin/env python3
import json
import sys

if "--version" in sys.argv:
    print("hyperfine 1.0.0-test")
    raise SystemExit(0)

out = sys.argv[sys.argv.index("--export-json") + 1]
with open(out, "w", encoding="utf-8") as fh:
    json.dump({"results": [{"mean": 0.123, "stddev": 0.004, "min": 0.12, "max": 0.13, "runs": 3}]}, fh)
print("Benchmark 1: fixture")
""",
        encoding="utf-8",
    )
    fake.chmod(0o755)
    assert os.access(fake, os.X_OK)
    env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}"}

    result = run_benchmark(tmp_path, env)

    assert result.returncode == 0, result.stderr
    record = json.loads(json_output_path(result).read_text(encoding="utf-8"))
    assert record["benchmark_run_status"] == "pass"
    assert record["verdict"] == "observed"
    assert record["tool"]["available"] is True
    assert record["tool"]["version"] == "hyperfine 1.0.0-test"
    assert record["sample_count"] == 3
    assert record["measured_ms"] == 123.0
    assert record["threshold_stage"] == "observe"
    assert Path(record["raw_output_json"]).exists()
    assert benchmark_capture_record(record).reason == "benchmark_capture_pass"
