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

ROOT_CAUSE_SHEET = {
    "expected_items": ["root-cause"],
    "items": [
        {
            "id": "root-cause",
            "oracle": "root_cause_fidelity",
            "target": "root-cause.json",
            "implicit": ["observed_symptom_reproduced_before_confirming_cause"],
        }
    ],
}


def _run(*args):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, cwd=str(ROOT))


def _write_sheet(d: Path, uploads: str, db: str) -> Path:
    (d / "uploads.py").write_text(uploads)
    (d / "db.py").write_text(db)
    sheet = d / "sheet.json"
    sheet.write_text(json.dumps(SHEET))
    return sheet


def _write_root_cause_sheet(d: Path, artifact: dict) -> Path:
    (d / "root-cause.json").write_text(json.dumps(artifact))
    sheet = d / "root-cause.checksheet.json"
    sheet.write_text(json.dumps(ROOT_CAUSE_SHEET))
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


def test_root_cause_claim_requires_observed_reproduction_fidelity(tmp_path):
    sheet = _write_root_cause_sheet(tmp_path, {"conclusion": "root cause confirmed"})
    result = _run(str(sheet))
    assert result.returncode == 1
    assert "root_cause_fields_missing" in result.stderr
    assert "observed_symptom" in result.stderr
    assert "reproduction" in result.stderr
    assert "fidelity" in result.stderr


def test_root_cause_fidelity_no_blocks_confirmed_language(tmp_path):
    sheet = _write_root_cause_sheet(
        tmp_path,
        {
            "observed_symptom": "user saw the client button stay disabled",
            "reproduction": "server-side proxy test only",
            "fidelity": "no",
            "conclusion": "root cause confirmed from proxy evidence",
        },
    )
    result = _run(str(sheet))
    assert result.returncode == 1
    assert "root_cause_confirmed_without_fidelity" in result.stderr


def test_root_cause_fidelity_yes_allows_confirmed_language(tmp_path):
    sheet = _write_root_cause_sheet(
        tmp_path,
        {
            "observed_symptom": "user saw the client button stay disabled",
            "reproduction": "same browser workflow reproduced the disabled button",
            "fidelity": "yes",
            "conclusion": "root cause confirmed from matching reproduction",
        },
    )
    result = _run(str(sheet))
    assert result.returncode == 0, result.stderr + result.stdout
    assert "PASS root_cause_fidelity_declared" in result.stdout


def test_root_cause_fidelity_no_allows_hypothesis_language(tmp_path):
    sheet = _write_root_cause_sheet(
        tmp_path,
        {
            "observed_symptom": "user saw the client button stay disabled",
            "reproduction": "server-side proxy test only",
            "fidelity": "no",
            "conclusion": "hypothesis only; 미확정 가설",
        },
    )
    result = _run(str(sheet))
    assert result.returncode == 0, result.stderr + result.stdout
    assert "PASS root_cause_fidelity_declared" in result.stdout


def test_real_run_aborts_when_an_oracle_fails_selftest(tmp_path, monkeypatch):
    # If selftest fails, a real checksheet run must abort (exit 2) before
    # rendering any verdict -- never a silent pass.
    sheet = _write_sheet(tmp_path, GOOD_UPLOADS, GOOD_DB)
    mod = _import_runner()
    mod.ORACLES["weak"] = {"fn": lambda m: mod.Verdict(True, "always_ok"), "good": "x=1\n", "bad": "x=1\n"}
    rc = mod.main([str(sheet)])
    assert rc == 2


def _write_registry(path: Path, items: list[dict], expected: list[str] | None = None) -> Path:
    registry = path / "closed.registry.json"
    registry.write_text(
        json.dumps(
            {
                "version": 1,
                "kind": "closed_defect_regression_registry",
                "expected_items": expected or [item["id"] for item in items],
                "items": items,
            }
        )
    )
    return registry


def _command_item(item_id: str, predicate: dict | None, non_vacuity: dict | None = None, enforcement: str = "mechanized") -> dict:
    item = {
        "id": item_id,
        "source": "test",
        "severity": "medium" if enforcement == "author_asserted" else "high",
        "protects": "test guard",
        "closed_at": "2026-07-05",
        "enforcement": enforcement,
    }
    if predicate is not None:
        item["predicate"] = predicate
    if non_vacuity is not None:
        item["non_vacuity"] = non_vacuity
    return item


def test_regression_registry_accepts_mechanized_and_author_asserted_items(tmp_path):
    good = {"argv": [sys.executable, "-c", "print('ok')"], "expect_exit": 0, "stdout_contains": "ok"}
    adversarial = {"argv": [sys.executable, "-c", "import sys; print('blocked', file=sys.stderr); sys.exit(3)"], "expect_exit": 3, "stderr_contains": "blocked"}
    registry = _write_registry(
        tmp_path,
        [
            _command_item("mechanized", good, adversarial),
            _command_item("author", good, None, enforcement="author_asserted"),
        ],
    )
    result = _run("--regression-registry", str(registry))
    assert result.returncode == 0, result.stderr + result.stdout
    assert "mechanized" in result.stdout
    assert "author_asserted" in result.stdout


def test_regression_registry_missing_predicate_fails_completeness(tmp_path):
    registry = _write_registry(tmp_path, [_command_item("missing", None, None, enforcement="author_asserted")])
    result = _run("--regression-registry", str(registry))
    assert result.returncode == 1
    assert "predicate_missing" in result.stderr


def test_regression_registry_high_author_asserted_is_rejected(tmp_path):
    good = {"argv": [sys.executable, "-c", "print('marker only')"], "expect_exit": 0, "stdout_contains": "marker"}
    item = _command_item("marker-only", good, None, enforcement="author_asserted")
    item["severity"] = "critical"
    registry = _write_registry(tmp_path, [item])
    result = _run("--regression-registry", str(registry))
    assert result.returncode == 1
    assert "author_asserted_high_severity" in result.stderr


def test_regression_registry_vacuous_mechanized_item_is_rejected(tmp_path):
    good = {"argv": [sys.executable, "-c", "print('ok')"], "expect_exit": 0}
    stub = {"argv": [sys.executable, "-c", "print('stub green')"], "expect_exit": 7}
    registry = _write_registry(tmp_path, [_command_item("vacuous", good, stub)])
    result = _run("--regression-registry", str(registry))
    assert result.returncode == 1
    assert "non_vacuity_exit_mismatch" in result.stderr


def test_regression_registry_expected_item_omission_blocks(tmp_path):
    good = {"argv": [sys.executable, "-c", "print('ok')"], "expect_exit": 0}
    registry = _write_registry(tmp_path, [_command_item("present", good, None, enforcement="author_asserted")], expected=["present", "missing"])
    result = _run("--regression-registry", str(registry))
    assert result.returncode == 1
    assert "expected_item_missing: missing" in result.stderr


def test_shipped_closed_defect_regression_registry_passes():
    registry = ROOT / "checksheets" / "closed-defect-regression.registry.json"
    result = _run("--regression-registry", str(registry))
    assert result.returncode == 0, result.stderr + result.stdout
    assert "AUD-GATE-CHECKSHEET-OMISSION" in result.stdout
    assert "AUD-GATE-CHECKSHEET-ADVERSARIAL-SQL" in result.stdout
    assert "author_asserted" not in result.stdout
