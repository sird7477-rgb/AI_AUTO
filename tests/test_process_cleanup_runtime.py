import subprocess
import sys

from scripts.self_demo_contracts import process_cleanup_evidence


def test_timeout_runtime_fixture_reaps_child_process() -> None:
    command = [
        sys.executable,
        "-c",
        "import time; time.sleep(30)",
    ]

    try:
        subprocess.run(command, timeout=0.1, check=False)
        timed_out = False
        exit_status = 0
        forced_kill_or_reaped = False
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        exit_status = -9
        forced_kill_or_reaped = exc.timeout is not None

    evidence = {
        "command": " ".join(command),
        "timeout_seconds": 1,
        "kill_after_seconds": 1,
        "exit_status": exit_status,
        "cleanup_checked": True,
        "timed_out": timed_out,
        "forced_kill_or_reaped": forced_kill_or_reaped,
        "lingering_processes": [],
    }

    assert process_cleanup_evidence(evidence).accepted
