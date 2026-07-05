#!/usr/bin/env python3
"""Deterministic checksheet oracle runner (PoC).

Ports the ponytail agentic-benchmark discipline (github DietrichGebert/ponytail,
benchmarks/agentic/) into a generic acceptance-oracle runner. Design note:
plans/AI_AUTO_CHECKSHEET_RUNNER_DESIGN_2026-06-26.md.

Patterns realized here:
  1. Deterministic oracle  -- each checksheet item runs the produced artifact
     against a fixed/adversarial input and decides accepted/rejected by code,
     never by an LLM (tasks.py score_* in ponytail).
  3. Isolation            -- each produced module loads under a unique name in a
     fresh namespace; oracles build their own fixtures (tmp dir, in-memory db) so
     the runner cannot accidentally pass an artifact via shared state.
  4. Runner self-test     -- `--selftest` proves every oracle CATCHES its own
     known-bad reference and PASSES its known-good reference before any real
     artifact is trusted; a non-self-validating oracle aborts the run (exit 2).
     This is the structural answer to the echo-$? masking false-pass class
     (memory: verify-machinery-result-via-vmexit-value).

  2 (implicit-requirement / omission forcing) is carried as the checksheet item's
  `implicit` field -- the safety axes the change spec did not state, asserted
  regardless -- and reported per item. 5 (LLM judge for non-deterministic axes)
  is out of this PoC's scope (deterministic oracles only).

Exit codes (fail-closed, matching scripts/self_demo_contracts.py CLI):
  0 = all items accepted
  1 = at least one item rejected (or a target failed to load)
  2 = bad usage / selftest failed / unknown oracle  (never a silent pass)
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable


@dataclass(frozen=True)
class Verdict:
    accepted: bool
    reason: str
    data: dict[str, Any] = field(default_factory=dict)


class ChecksheetSchemaError(ValueError):
    """Raised when a checksheet cannot be trusted as a machine-readable contract."""


class RegressionRegistryError(ValueError):
    """Raised when a closed-defect regression registry is malformed."""


ROOT_CAUSE_REQUIRED_FIELDS = ("observed_symptom", "reproduction", "fidelity")
ROOT_CAUSE_HIGH_CONFIDENCE_RE = re.compile(
    r"(원인\s*확정|확인\s*완료|결정적|\broot\s+cause\s+confirmed\b|\bconfirmed\b|\bdefinitive\b)",
    re.IGNORECASE,
)


# --- isolated artifact loading (pattern 3) ---------------------------------
_load_n = 0


def _load_module(pyfile: Path):
    """Import a produced .py under a unique module name (no sys.modules reuse)."""
    global _load_n
    _load_n += 1
    spec = importlib.util.spec_from_file_location(f"_artifact_{_load_n}", str(pyfile))
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {pyfile}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _find(mod, names: list[str]) -> Callable | None:
    for nm in names:
        fn = getattr(mod, nm, None)
        if callable(fn):
            return fn
    return None


def _contained(base: str, target: str) -> bool:
    base, target = os.path.abspath(base), os.path.abspath(target)
    try:
        return os.path.commonpath([base, target]) == base
    except ValueError:
        return False


# --- oracles (pattern 1: deterministic, execute against adversarial input) ---
def oracle_safe_path(mod) -> Verdict:
    fn = _find(mod, ["safe_upload_path", "safe_path", "build_upload_path"])
    if fn is None:
        return Verdict(False, "no_target_function", {"looked_for": "safe_upload_path"})
    with tempfile.TemporaryDirectory() as base:
        try:
            ok_path = os.path.normpath(fn(base, "photo.png"))
        except Exception as exc:  # noqa: BLE001 -- correctness path must not raise
            return Verdict(False, "correctness_raised", {"error": repr(exc)})
        if not (ok_path.endswith("photo.png") and _contained(base, ok_path)):
            return Verdict(False, "correctness_failed", {"got": ok_path})
        adversarial = os.path.join("..", "..", "..", "etc", "passwd")
        try:
            escaped = fn(base, adversarial)
        except Exception:
            return Verdict(True, "safe_rejected_traversal_by_raising", {})
        if _contained(base, os.path.normpath(escaped)):
            return Verdict(True, "safe_contained", {})
        return Verdict(False, "path_traversal_escapes_base", {"got": os.path.normpath(escaped)})


def _seed_users_db() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, secret TEXT)")
    conn.executemany(
        "INSERT INTO users (name, secret) VALUES (?, ?)",
        [("alice", "a-token"), ("bob", "b-token")],
    )
    conn.commit()
    return conn


def oracle_sql_param(mod) -> Verdict:
    fn = _find(mod, ["get_user", "find_user", "lookup_user"])
    if fn is None:
        return Verdict(False, "no_target_function", {"looked_for": "get_user"})
    conn = _seed_users_db()
    try:
        try:
            rows = fn(conn, "alice")
        except Exception as exc:  # noqa: BLE001
            return Verdict(False, "correctness_raised", {"error": repr(exc)})
        if len(list(rows)) != 1:
            return Verdict(False, "correctness_failed", {"rows_for_alice": len(list(rows))})
        injection = "' OR '1'='1"
        try:
            leaked = fn(conn, injection)
        except Exception:
            return Verdict(True, "safe_rejected_injection_by_raising", {})
        if len(list(leaked)) == 0:
            return Verdict(True, "safe_parameterized", {})
        return Verdict(False, "sql_injection_leaks_rows", {"leaked": len(list(leaked))})
    finally:
        conn.close()


def oracle_root_cause_fidelity(path: Path) -> Verdict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return Verdict(False, "root_cause_artifact_invalid", {"error": repr(exc)})
    if not isinstance(data, dict):
        return Verdict(False, "root_cause_artifact_invalid", {"error": "root must be an object"})
    missing = [
        field_name
        for field_name in ROOT_CAUSE_REQUIRED_FIELDS
        if not isinstance(data.get(field_name), str) or not data[field_name].strip()
    ]
    if missing:
        return Verdict(False, f"root_cause_fields_missing:{','.join(missing)}", {"missing": missing})
    fidelity = data["fidelity"].strip().lower()
    if fidelity not in ("yes", "no"):
        return Verdict(False, "root_cause_fidelity_invalid", {"expected": "yes|no", "got": data["fidelity"]})
    # Scan every string value of the artifact EXCEPT the three required contract fields
    # (observed_symptom, reproduction, fidelity): high-confidence "확정/confirmed/definitive" language
    # in ANY other field (notes, analysis, conclusion, an ad-hoc key, ...) with fidelity=no is the same
    # contradiction and must not evade the check by living outside a fixed allowlist. But
    # observed_symptom and reproduction legitimately DESCRIBE the user's observation, so benign
    # "confirmed" language there (e.g. "user confirmed the button stays disabled") must NOT
    # false-reject an honest fidelity=no hypothesis artifact.
    claim_text = "\n".join(
        str(value)
        for key, value in data.items()
        if key not in ROOT_CAUSE_REQUIRED_FIELDS and isinstance(value, str)
    )
    if fidelity == "no" and ROOT_CAUSE_HIGH_CONFIDENCE_RE.search(claim_text):
        return Verdict(False, "root_cause_confirmed_without_fidelity", {"fidelity": fidelity})
    return Verdict(True, "root_cause_fidelity_declared", {"fidelity": fidelity})


# Each oracle ships a known-good (must accept) and known-bad (must be caught)
# reference -- the lazy-but-plausible version correct on the happy path, unsafe on
# the adversarial input. --selftest proves the oracle distinguishes them.
ORACLES: dict[str, dict[str, Any]] = {
    "safe_path": {
        "fn": oracle_safe_path,
        "good": (
            "import os\n"
            "def safe_upload_path(base, name):\n"
            "    p = os.path.normpath(os.path.join(base, name))\n"
            "    if os.path.commonpath([os.path.abspath(base), os.path.abspath(p)]) != os.path.abspath(base):\n"
            "        raise ValueError('path escapes base')\n"
            "    return p\n"
        ),
        "bad": (
            "import os\n"
            "def safe_upload_path(base, name):\n"
            "    return os.path.join(base, name)  # happy-path only, no traversal guard\n"
        ),
    },
    "sql_param": {
        "fn": oracle_sql_param,
        "good": (
            "def get_user(conn, name):\n"
            "    return conn.execute('SELECT * FROM users WHERE name = ?', (name,)).fetchall()\n"
        ),
        "bad": (
            "def get_user(conn, name):\n"
            "    return conn.execute(\"SELECT * FROM users WHERE name = '%s'\" % name).fetchall()\n"
        ),
    },
    "root_cause_fidelity": {
        "mode": "file",
        "fn": oracle_root_cause_fidelity,
        "good": json.dumps(
            {
                "observed_symptom": "user saw the browser button stay disabled",
                "reproduction": "same browser workflow reproduced the disabled button",
                "fidelity": "yes",
                "conclusion": "root cause confirmed in the matching browser repro",
            }
        ),
        "bad": json.dumps(
            {
                "observed_symptom": "user saw the browser button stay disabled",
                "reproduction": "server-only proxy check did not run the browser workflow",
                "fidelity": "no",
                "conclusion": "root cause confirmed from proxy evidence",
            }
        ),
    },
}


def _run_oracle_on_source(spec: dict[str, Any], source: str) -> Verdict:
    with tempfile.TemporaryDirectory() as d:
        if spec.get("mode") == "file":
            ref = Path(d) / "ref.json"
            ref.write_text(source, encoding="utf-8")
            return spec["fn"](ref)
        ref = Path(d) / "ref.py"
        ref.write_text(source, encoding="utf-8")
        return spec["fn"](_load_module(ref))


def selftest() -> tuple[bool, list[str]]:
    """Every oracle must accept its good ref and reject its bad ref (pattern 4)."""
    failures: list[str] = []
    for name, spec in ORACLES.items():
        good = _run_oracle_on_source(spec, spec["good"])
        if not good.accepted:
            failures.append(f"{name}: good reference rejected ({good.reason})")
        bad = _run_oracle_on_source(spec, spec["bad"])
        if bad.accepted:
            failures.append(f"{name}: bad reference NOT caught (accepted as {bad.reason})")
    return (not failures, failures)


def _require_string(value: Any, field_name: str, item_id: str | None = None) -> str:
    if isinstance(value, str) and value:
        return value
    prefix = f"item {item_id}: " if item_id else ""
    raise ChecksheetSchemaError(f"{prefix}{field_name} must be a non-empty string")


def _validate_implicit(value: Any, item_id: str) -> bool | list[str]:
    if value is None:
        return False
    if isinstance(value, bool):
        return value
    if isinstance(value, list) and all(isinstance(v, str) and v for v in value):
        return value
    raise ChecksheetSchemaError(f"item {item_id}: implicit must be true/false or a list of strings")


def _validate_checksheet(data: Any) -> tuple[list[dict[str, Any]], list[str] | None]:
    if not isinstance(data, dict):
        raise ChecksheetSchemaError("checksheet root must be an object")
    items = data.get("items")
    if not isinstance(items, list) or not items:
        raise ChecksheetSchemaError("items must be a non-empty list")

    seen: set[str] = set()
    normalized: list[dict[str, Any]] = []
    for raw in items:
        if not isinstance(raw, dict):
            raise ChecksheetSchemaError("each item must be an object")
        item_id = _require_string(raw.get("id"), "id")
        if item_id in seen:
            raise ChecksheetSchemaError(f"duplicate item id {item_id!r}")
        seen.add(item_id)
        normalized.append(
            {
                "id": item_id,
                "oracle": _require_string(raw.get("oracle"), "oracle", item_id),
                "target": _require_string(raw.get("target"), "target", item_id),
                "implicit": _validate_implicit(raw.get("implicit"), item_id),
            }
        )

    expected_raw = data.get("expected_items")
    if expected_raw is None:
        return normalized, None
    if not isinstance(expected_raw, list) or not all(isinstance(v, str) and v for v in expected_raw):
        raise ChecksheetSchemaError("expected_items must be a list of non-empty strings")
    if len(set(expected_raw)) != len(expected_raw):
        raise ChecksheetSchemaError("expected_items must not contain duplicate ids")
    return normalized, expected_raw


def _repo_root_for(path: Path) -> Path:
    try:
        out = subprocess.check_output(
            ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return Path(out.strip()).resolve()
    except (OSError, subprocess.CalledProcessError):
        return path.resolve()


def _validate_command(value: Any, item_id: str, field_name: str) -> dict[str, Any] | None:
    if value is None:
        return None
    if not isinstance(value, dict):
        raise RegressionRegistryError(f"item {item_id}: {field_name} must be an object")
    argv = value.get("argv")
    if not isinstance(argv, list) or not argv or not all(isinstance(v, str) and v for v in argv):
        raise RegressionRegistryError(f"item {item_id}: {field_name}.argv must be a non-empty string list")
    expect_exit = value.get("expect_exit", 0)
    if not isinstance(expect_exit, int) or expect_exit < 0 or expect_exit > 255:
        raise RegressionRegistryError(f"item {item_id}: {field_name}.expect_exit must be an integer 0..255")
    timeout = value.get("timeout_seconds", 30)
    if not isinstance(timeout, int) or timeout <= 0 or timeout > 300:
        raise RegressionRegistryError(f"item {item_id}: {field_name}.timeout_seconds must be 1..300")
    cwd = value.get("cwd", ".")
    if not isinstance(cwd, str) or not cwd:
        raise RegressionRegistryError(f"item {item_id}: {field_name}.cwd must be a non-empty string")
    stdout_contains = value.get("stdout_contains")
    stderr_contains = value.get("stderr_contains")
    if stdout_contains is not None and not isinstance(stdout_contains, str):
        raise RegressionRegistryError(f"item {item_id}: {field_name}.stdout_contains must be a string")
    if stderr_contains is not None and not isinstance(stderr_contains, str):
        raise RegressionRegistryError(f"item {item_id}: {field_name}.stderr_contains must be a string")
    return {
        "argv": argv,
        "expect_exit": expect_exit,
        "timeout_seconds": timeout,
        "cwd": cwd,
        "stdout_contains": stdout_contains,
        "stderr_contains": stderr_contains,
    }


def _validate_regression_registry(data: Any) -> tuple[list[dict[str, Any]], list[str]]:
    if not isinstance(data, dict):
        raise RegressionRegistryError("registry root must be an object")
    if data.get("kind") != "closed_defect_regression_registry":
        raise RegressionRegistryError("kind must be closed_defect_regression_registry")
    if data.get("version") != 1:
        raise RegressionRegistryError("version must be 1")
    expected_raw = data.get("expected_items")
    if not isinstance(expected_raw, list) or not expected_raw or not all(isinstance(v, str) and v for v in expected_raw):
        raise RegressionRegistryError("expected_items must be a non-empty string list")
    if len(set(expected_raw)) != len(expected_raw):
        raise RegressionRegistryError("expected_items must not contain duplicate ids")
    raw_items = data.get("items")
    if not isinstance(raw_items, list) or not raw_items:
        raise RegressionRegistryError("items must be a non-empty list")
    seen: set[str] = set()
    items: list[dict[str, Any]] = []
    for raw in raw_items:
        if not isinstance(raw, dict):
            raise RegressionRegistryError("each item must be an object")
        item_id = _require_string(raw.get("id"), "id")
        if item_id in seen:
            raise RegressionRegistryError(f"duplicate item id {item_id!r}")
        seen.add(item_id)
        enforcement = raw.get("enforcement", "author_asserted")
        if enforcement not in ("mechanized", "author_asserted"):
            raise RegressionRegistryError(f"item {item_id}: enforcement must be mechanized or author_asserted")
        predicate = _validate_command(raw.get("predicate"), item_id, "predicate")
        non_vacuity = _validate_command(raw.get("non_vacuity"), item_id, "non_vacuity")
        if enforcement == "mechanized" and non_vacuity is None:
            raise RegressionRegistryError(f"item {item_id}: mechanized entries require non_vacuity")
        items.append(
            {
                "id": item_id,
                "source": _require_string(raw.get("source"), "source", item_id),
                "severity": _require_string(raw.get("severity"), "severity", item_id),
                "protects": _require_string(raw.get("protects"), "protects", item_id),
                "closed_at": _require_string(raw.get("closed_at"), "closed_at", item_id),
                "enforcement": enforcement,
                "predicate": predicate,
                "non_vacuity": non_vacuity,
            }
        )
    return items, expected_raw


def _implicit_label(value: bool | list[str]) -> str:
    if value is True:
        return " implicit=true"
    if isinstance(value, list) and value:
        return f" implicit={','.join(value)}"
    return ""


# --- checksheet run --------------------------------------------------------
def run_checksheet(path: Path) -> int:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        items, expected_items = _validate_checksheet(data)
    except (OSError, json.JSONDecodeError, ChecksheetSchemaError) as exc:
        print(f"[checksheet] ERROR schema_invalid: {exc}", file=sys.stderr)
        return 2

    actual_ids = [item["id"] for item in items]
    if expected_items is not None:
        missing = sorted(set(expected_items) - set(actual_ids))
        unexpected = sorted(set(actual_ids) - set(expected_items))
        if missing or unexpected:
            if missing:
                print(f"[checksheet] ERROR expected_item_missing: {','.join(missing)}", file=sys.stderr)
            if unexpected:
                print(f"[checksheet] ERROR unexpected_item: {','.join(unexpected)}", file=sys.stderr)
            return 1

    base = path.parent
    rejected = 0
    for item in items:
        item_id = item.get("id", "<no-id>")
        oracle_name = item["oracle"]
        spec = ORACLES.get(oracle_name)
        if spec is None:
            print(f"[checksheet] {item_id}: ERROR unknown oracle {oracle_name!r}", file=sys.stderr)
            return 2
        target = (base / item["target"]).resolve()
        if spec.get("mode") == "file":
            v = spec["fn"](target)
        else:
            try:
                mod = _load_module(target)
            except Exception as exc:  # noqa: BLE001 -- a missing/broken artifact is a rejection
                print(f"[checksheet] {item_id} ({oracle_name}): REJECT target_load_failed: {exc}", file=sys.stderr)
                rejected += 1
                continue
            v = spec["fn"](mod)
        tag = "PASS" if v.accepted else "REJECT"
        impl = _implicit_label(item["implicit"])
        line = f"[checksheet] {item_id} ({oracle_name}): {tag} {v.reason}{impl}"
        print(line if v.accepted else line, file=sys.stderr if not v.accepted else sys.stdout)
        if not v.accepted:
            rejected += 1
    return 1 if rejected else 0


def _run_registry_command(repo: Path, command: dict[str, Any]) -> Verdict:
    cwd = (repo / command["cwd"]).resolve()
    try:
        result = subprocess.run(
            command["argv"],
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=command["timeout_seconds"],
        )
    except subprocess.TimeoutExpired:
        return Verdict(False, "timeout", {"argv": command["argv"], "timeout_seconds": command["timeout_seconds"]})
    except OSError as exc:
        return Verdict(False, "exec_failed", {"argv": command["argv"], "error": repr(exc)})
    if result.returncode != command["expect_exit"]:
        return Verdict(
            False,
            "exit_mismatch",
            {"argv": command["argv"], "expected": command["expect_exit"], "got": result.returncode},
        )
    stdout_contains = command.get("stdout_contains")
    if stdout_contains and stdout_contains not in result.stdout:
        return Verdict(False, "stdout_missing", {"needle": stdout_contains})
    stderr_contains = command.get("stderr_contains")
    if stderr_contains and stderr_contains not in result.stderr:
        return Verdict(False, "stderr_missing", {"needle": stderr_contains})
    return Verdict(True, "command_matched", {"argv": command["argv"], "exit": result.returncode})


def run_regression_registry(path: Path) -> int:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        items, expected_items = _validate_regression_registry(data)
    except (OSError, json.JSONDecodeError, RegressionRegistryError) as exc:
        print(f"[regression-registry] ERROR schema_invalid: {exc}", file=sys.stderr)
        return 2

    actual_ids = [item["id"] for item in items]
    missing = sorted(set(expected_items) - set(actual_ids))
    unexpected = sorted(set(actual_ids) - set(expected_items))
    if missing or unexpected:
        if missing:
            print(f"[regression-registry] ERROR expected_item_missing: {','.join(missing)}", file=sys.stderr)
        if unexpected:
            print(f"[regression-registry] ERROR unexpected_item: {','.join(unexpected)}", file=sys.stderr)
        return 1

    repo = _repo_root_for(path.parent)
    rejected = 0
    for item in items:
        item_id = item["id"]
        if item["enforcement"] == "author_asserted" and item["severity"] in ("high", "critical"):
            print(f"[regression-registry] {item_id}: REJECT author_asserted_high_severity", file=sys.stderr)
            rejected += 1
            continue
        predicate = item["predicate"]
        if predicate is None:
            print(f"[regression-registry] {item_id}: REJECT predicate_missing", file=sys.stderr)
            rejected += 1
            continue
        verdict = _run_registry_command(repo, predicate)
        if not verdict.accepted:
            print(f"[regression-registry] {item_id}: REJECT predicate_{verdict.reason} {verdict.data}", file=sys.stderr)
            rejected += 1
            continue
        non_vacuity = item["non_vacuity"]
        if non_vacuity is not None:
            nv = _run_registry_command(repo, non_vacuity)
            if not nv.accepted:
                print(f"[regression-registry] {item_id}: REJECT non_vacuity_{nv.reason} {nv.data}", file=sys.stderr)
                rejected += 1
                continue
            print(f"[regression-registry] {item_id}: PASS mechanized {item['protects']}")
        else:
            print(f"[regression-registry] {item_id}: PASS author_asserted {item['protects']}")
    return 1 if rejected else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Deterministic checksheet oracle runner.")
    parser.add_argument("checksheet", nargs="?", help="path to a checksheet JSON file")
    parser.add_argument("--selftest", action="store_true", help="validate every oracle on its good/bad references and exit")
    parser.add_argument("--regression-registry", action="store_true", help="run a closed-defect regression registry JSON file")
    args = parser.parse_args(argv)

    if args.selftest:
        ok, failures = selftest()
        if ok:
            print(f"[checksheet] selftest OK ({len(ORACLES)} oracles)")
            return 0
        for f in failures:
            print(f"[checksheet] selftest FAIL: {f}", file=sys.stderr)
        return 2

    if not args.checksheet:
        parser.print_usage(sys.stderr)
        return 2

    if args.regression_registry:
        return run_regression_registry(Path(args.checksheet))

    # Always self-validate before trusting real artifacts (pattern 4): a runner
    # that cannot catch its own bad references must not render a verdict.
    ok, failures = selftest()
    if not ok:
        for f in failures:
            print(f"[checksheet] selftest FAIL (aborting before real run): {f}", file=sys.stderr)
        return 2

    return run_checksheet(Path(args.checksheet))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
