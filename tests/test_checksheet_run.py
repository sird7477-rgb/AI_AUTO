"""Checksheet oracle runner PoC (scripts/checksheet-run.py).

Proves the ponytail-ported design: deterministic oracles execute the produced
artifact against adversarial input, the runner self-validates (catches its own
bad references) before trusting real artifacts, and verdicts are fail-closed
exit codes. Design: plans/AI_AUTO_CHECKSHEET_RUNNER_DESIGN_2026-06-26.md.
"""
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "checksheet-run.py"

GOOD_UPLOADS = (
    "import os\n"
    "def safe_upload_path(base, name):\n"
    "    p = os.path.normpath(os.path.join(base, name))\n"
    "    if os.path.commonpath([os.path.abspath(base), os.path.abspath(p)]) != os.path.abspath(base):\n"
    "        raise ValueError('escape')\n"
    "    return p\n"
)
BAD_UPLOADS = "import os\ndef safe_upload_path(base, name):\n    return os.path.join(base, name)\n"
GOOD_DB = "def get_user(conn, name):\n    return conn.execute('SELECT * FROM users WHERE name = ?', (name,)).fetchall()\n"
BAD_DB = "def get_user(conn, name):\n    return conn.execute(\"SELECT * FROM users WHERE name = '%s'\" % name).fetchall()\n"

SHEET = {
    "expected_items": ["upload-path", "user-lookup"],
    "items": [
        {"id": "upload-path", "oracle": "safe_path", "target": "uploads.py", "implicit": ["no_traversal"]},
        {"id": "user-lookup", "oracle": "sql_param", "target": "db.py", "implicit": ["no_sql_injection"]},
    ]
}


def _run(*args):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, cwd=str(ROOT))


def _write_sheet(d: Path, uploads: str, db: str) -> Path:
    (d / "uploads.py").write_text(uploads)
    (d / "db.py").write_text(db)
    sheet = d / "sheet.json"
    sheet.write_text(json.dumps(SHEET))
    return sheet


def _import_runner():
    spec = importlib.util.spec_from_file_location("checksheet_run", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["checksheet_run"] = mod  # dataclass needs its module registered
    spec.loader.exec_module(mod)
    return mod


def test_selftest_passes_for_real_registry():
    result = _run("--selftest")
    assert result.returncode == 0, result.stderr
    assert "selftest OK" in result.stdout


def test_good_artifacts_pass(tmp_path):
    sheet = _write_sheet(tmp_path, GOOD_UPLOADS, GOOD_DB)
    result = _run(str(sheet))
    assert result.returncode == 0, result.stderr + result.stdout
    assert "PASS" in result.stdout


def test_bad_artifacts_are_caught(tmp_path):
    sheet = _write_sheet(tmp_path, BAD_UPLOADS, BAD_DB)
    result = _run(str(sheet))
    assert result.returncode == 1
    assert "path_traversal_escapes_base" in result.stderr
    assert "sql_injection_leaks_rows" in result.stderr


def test_mixed_one_bad_still_fails(tmp_path):
    sheet = _write_sheet(tmp_path, GOOD_UPLOADS, BAD_DB)  # only db is unsafe
    result = _run(str(sheet))
    assert result.returncode == 1
    assert "sql_injection_leaks_rows" in result.stderr


def test_missing_target_is_a_rejection(tmp_path):
    (tmp_path / "uploads.py").write_text(GOOD_UPLOADS)
    # db.py deliberately absent
    sheet = tmp_path / "sheet.json"
    sheet.write_text(json.dumps(SHEET))
    result = _run(str(sheet))
    assert result.returncode == 1
    assert "target_load_failed" in result.stderr


def test_unknown_oracle_exits_two(tmp_path):
    (tmp_path / "x.py").write_text("y=1\n")
    sheet = tmp_path / "invalid.checksheet.json"
    sheet.write_text(json.dumps({"expected_items": ["x"], "items": [{"id": "x", "oracle": "nope", "target": "x.py"}]}))
    result = _run(str(sheet))
    assert result.returncode == 2
    assert "unknown oracle" in result.stderr


def test_schema_violation_exits_two(tmp_path):
    sheet = tmp_path / "invalid.checksheet.json"
    sheet.write_text(json.dumps({"items": [{"id": "missing-target", "oracle": "safe_path"}]}))
    result = _run(str(sheet))
    assert result.returncode == 2
    assert "schema_invalid" in result.stderr
    assert "target must be a non-empty string" in result.stderr


def test_expected_item_omission_is_rejected_by_id(tmp_path):
    (tmp_path / "uploads.py").write_text(GOOD_UPLOADS)
    sheet = tmp_path / "omission.checksheet.json"
    sheet.write_text(
        json.dumps(
            {
                "expected_items": ["upload-path", "user-lookup"],
                "items": [{"id": "upload-path", "oracle": "safe_path", "target": "uploads.py"}],
            }
        )
    )
    result = _run(str(sheet))
    assert result.returncode == 1
    assert "expected_item_missing: user-lookup" in result.stderr


def test_implicit_true_item_is_an_assertion_not_output_only(tmp_path):
    (tmp_path / "db.py").write_text(BAD_DB)
    sheet = tmp_path / "implicit.checksheet.json"
    sheet.write_text(
        json.dumps(
            {
                "expected_items": ["user-lookup"],
                "items": [{"id": "user-lookup", "oracle": "sql_param", "target": "db.py", "implicit": True}],
            }
        )
    )
    result = _run(str(sheet))
    assert result.returncode == 1
    assert "REJECT sql_injection_leaks_rows implicit=true" in result.stderr


def test_missing_argument_exits_two():
    result = _run()
    assert result.returncode == 2


def test_selftest_catches_a_non_self_validating_oracle():
    # The guard that makes pattern 4 real: an oracle that cannot distinguish its
    # good/bad references must fail selftest, not be silently trusted.
    mod = _import_runner()
    weak = {"fn": lambda m: mod.Verdict(True, "always_ok"), "good": "x=1\n", "bad": "x=1\n"}
    original = dict(mod.ORACLES)
    mod.ORACLES["weak"] = weak
    try:
        ok, failures = mod.selftest()
        assert not ok
        assert any("weak" in f and "bad reference NOT caught" in f for f in failures)
    finally:
        mod.ORACLES.clear()
        mod.ORACLES.update(original)


def test_real_run_aborts_when_an_oracle_fails_selftest(tmp_path, monkeypatch):
    # If selftest fails, a real checksheet run must abort (exit 2) before
    # rendering any verdict -- never a silent pass.
    sheet = _write_sheet(tmp_path, GOOD_UPLOADS, GOOD_DB)
    mod = _import_runner()
    mod.ORACLES["weak"] = {"fn": lambda m: mod.Verdict(True, "always_ok"), "good": "x=1\n", "bad": "x=1\n"}
    rc = mod.main([str(sheet)])
    assert rc == 2
