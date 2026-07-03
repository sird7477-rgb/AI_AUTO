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
import sqlite3
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
}


def _run_oracle_on_source(oracle_fn: Callable, source: str) -> Verdict:
    with tempfile.TemporaryDirectory() as d:
        ref = Path(d) / "ref.py"
        ref.write_text(source, encoding="utf-8")
        return oracle_fn(_load_module(ref))


def selftest() -> tuple[bool, list[str]]:
    """Every oracle must accept its good ref and reject its bad ref (pattern 4)."""
    failures: list[str] = []
    for name, spec in ORACLES.items():
        good = _run_oracle_on_source(spec["fn"], spec["good"])
        if not good.accepted:
            failures.append(f"{name}: good reference rejected ({good.reason})")
        bad = _run_oracle_on_source(spec["fn"], spec["bad"])
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


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Deterministic checksheet oracle runner.")
    parser.add_argument("checksheet", nargs="?", help="path to a checksheet JSON file")
    parser.add_argument("--selftest", action="store_true", help="validate every oracle on its good/bad references and exit")
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
