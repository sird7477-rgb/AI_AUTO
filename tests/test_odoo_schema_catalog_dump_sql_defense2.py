"""BLUE fix (ops-defense2, smallest-verifiable-change round).

Confirmed defect being closed here:

  During warm-base prep, dump-schema-catalog.sh ran a psql query selecting
  `COALESCE(f.modules, '')` against `ir_model_fields`. `modules` is not a real
  column on that table in this Odoo/Postgres version -- it errors:
      ERROR: column f.modules does not exist
      HINT: Perhaps you meant to reference the column "f.model"
  (the hint is a red herring: `f.model` is just the model name string, already
  selected separately via `m.model` -- following it verbatim would silently
  produce wrong data, not fix anything). The dump therefore ALWAYS failed, and
  because dump-schema-catalog.sh ran under `set -euo pipefail` with no error
  handling, a failure at the psql step aborted the script BEFORE it reached
  `mv "$tmp" "$OUT"` -- so any catalog already at $OUT from a PRIOR successful
  run was left completely untouched. check-schema-catalog.py would then load
  that stale-but-structurally-valid ("schema": 1, module_set_sha unchanged)
  catalog and report "OK: screened N module(s)" as if the screen had actually
  run against current data. The only visible symptom was a single WARNING line
  in prepare-base-db.sh's build log ("schema catalog dump failed; ...  will
  report NOT screened") -- which was itself not even accurate once a stale
  catalog was already in place, and which nothing downstream gated on.

Fix (dump-schema-catalog.sh only; this file's edit boundary):
  (a) SQL: derive `modules` via `ir_model_data` (model='ir.model.fields',
      res_id=f.id), the same mechanism Odoo itself uses to track which module
      owns any given model record for uninstall/cleanup. This table has
      existed since Odoo's earliest versions -- version-safe, unlike a
      column/attribute that may or may not exist depending on version.
  (b) Loudness / fail-closed: both the psql step and the python post-
      processing step now run under `|| fail_loud "..."`. fail_loud prints an
      un-missable "NOT-VALIDATED (dump failed): ..." banner to stderr AND
      POISONS $OUT (overwrites it with `{"schema": 0, ...}`) before exiting
      non-zero -- so a stale prior-success catalog can never again be silently
      reused as fresh. check-schema-catalog.py's existing load_catalog()
      already treats schema != 1 as "catalog unavailable, NOT screened", and
      hooks/pre-push already always invokes it with --strict, which turns that
      into a hard block (see tests/test_odoo_harness_honesty_r2.py and
      scripts/verify-machinery.sh's own schema-catalog fixture block for that
      existing --strict fail-closed contract) -- untouched by this change,
      just now actually reachable instead of being masked by a stale file.

Non-vacuousness: every assertion below targets behavior only true of the FIXED
script. Restoring the pre-fix content (available via `git show
HEAD:templates/domain-packs/odoo/validation-harness/dump-schema-catalog.sh`,
since this edit is uncommitted in this worktree at authoring time) makes the
corresponding assertions fail -- see the session's final report for the
one-shot manual revert/rerun proof.
"""
from __future__ import annotations

import json
import re
import stat
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (
    ROOT
    / "templates"
    / "domain-packs"
    / "odoo"
    / "validation-harness"
    / "dump-schema-catalog.sh"
)


def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _extract_sql(script_text: str) -> str:
    """Pull the psql -c "<SQL>" body out of the script text."""
    m = re.search(
        r"-c\s+\"(.*?)\"\s*>\s*\"\$psql_csv\"", script_text, re.DOTALL
    )
    assert m, "could not locate the psql -c \"...\" SQL block in the script"
    return m.group(1)


def _select_columns(sql: str) -> list[str]:
    """Split the SELECT ... FROM column list on TOP-LEVEL commas (ignoring
    commas nested inside parens, e.g. inside COALESCE(...)/string_agg(...))."""
    m = re.search(r"SELECT\s+(.*?)\s+FROM\b", sql, re.DOTALL | re.IGNORECASE)
    assert m, "no SELECT ... FROM clause found"
    body = m.group(1)
    cols: list[str] = []
    depth = 0
    current = ""
    for ch in body:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            cols.append(current.strip())
            current = ""
        else:
            current += ch
    if current.strip():
        cols.append(current.strip())
    return cols


# ==========================================================================
# (a) SQL fix: no more `f.modules`, correct version-safe module derivation
# ==========================================================================
def test_sql_no_longer_references_the_nonexistent_modules_column():
    sql = _extract_sql(SCRIPT.read_text(encoding="utf-8"))
    assert "f.modules" not in sql, (
        "SQL still references ir_model_fields.modules, which does not exist "
        "on this Odoo/Postgres version (the confirmed defect)"
    )
    # Guard against the misleading psql HINT being followed verbatim: f.model
    # is just the model name string (already selected via m.model) and is NOT
    # a stand-in for "which module(s) own this field".
    assert not re.search(r"COALESCE\(\s*f\.model\s*,", sql), (
        "SQL must not naively swap f.modules -> f.model per the psql HINT; "
        "that column means something unrelated (the model name)"
    )


def test_sql_derives_modules_via_ir_model_data_join():
    sql = _extract_sql(SCRIPT.read_text(encoding="utf-8"))
    assert "ir_model_data" in sql, (
        "expected the module derivation to join ir_model_data (the "
        "version-safe source Odoo itself uses to track which module owns a "
        "given ir.model.fields record)"
    )
    assert re.search(r"d\.model\s*=\s*'ir\.model\.fields'", sql), (
        "ir_model_data join must be scoped to model='ir.model.fields' rows"
    )
    assert re.search(r"d\.res_id\s*=\s*f\.id", sql), (
        "ir_model_data join must match on res_id = the field's own id"
    )
    assert "string_agg" in sql and "DISTINCT" in sql, (
        "modules should be aggregated (comma-joined, de-duplicated) to match "
        "check-schema-catalog.py's comma-split parsing of the 6th column"
    )


def test_sql_still_produces_the_6_columns_check_schema_catalog_expects():
    """check-schema-catalog.py's dump-schema-catalog.sh Python post-processor
    (embedded in the same script) parses each row as exactly:
        model, name, ttype, relation, related, modules
    Assert the SQL's SELECT list has exactly that shape/order after the fix,
    so the two halves of the pipeline still agree."""
    text = SCRIPT.read_text(encoding="utf-8")
    sql = _extract_sql(text)
    cols = _select_columns(sql)
    assert len(cols) == 6, f"expected 6 SELECT columns, got {len(cols)}: {cols}"
    assert cols[0] == "m.model"
    assert cols[1] == "f.name"
    assert "f.ttype" in cols[2]
    assert "f.relation" in cols[3]
    assert "f.related" in cols[4]
    assert "string_agg" in cols[5] and "d.module" in cols[5]

    # Cross-check against the embedded python post-processor's own unpacking
    # order, so a future drift between the SQL and the parser is caught here.
    py_unpack = re.search(
        r"model, name, ttype, relation, related, modules = ", text
    )
    assert py_unpack, "python post-processor's row-unpack line moved/changed"


# ==========================================================================
# (b) Loudness / fail-closed: a dump failure must not silently keep a stale
#     catalog looking valid.
# ==========================================================================
def _fake_docker_that_fails_at_psql(tmp_path: Path) -> Path:
    """A hermetic fake `docker` on PATH: any invocation whose args contain
    'psql' fails (simulating the confirmed SQL failure, or any other dump-time
    breakage) with a realistic error on stderr; everything else no-ops
    successfully. No real Docker daemon or Postgres is touched."""
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text(
        "#!/usr/bin/env bash\n"
        "for a in \"$@\"; do\n"
        "  if [ \"$a\" = psql ]; then\n"
        "    echo 'ERROR: simulated dump-time failure for test' >&2\n"
        "    exit 1\n"
        "  fi\n"
        "done\n"
        "exit 0\n",
        encoding="utf-8",
    )
    _make_executable(docker)
    return bin_dir


def _run_dump(script: Path, work_dir: Path, out_path: Path, path_prefix: Path):
    import os

    env = os.environ.copy()
    env["PATH"] = f"{path_prefix}:{env['PATH']}"
    return subprocess.run(
        ["bash", str(script), "basedb", str(out_path), "modsha123"],
        cwd=work_dir,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def test_dump_failure_is_loud_and_poisons_a_stale_catalog_not_silent_pass(
    tmp_path,
):
    work_dir = tmp_path / "work"
    work_dir.mkdir()
    out_path = work_dir / "catalog.json"

    # Seed a STALE-but-structurally-VALID catalog, exactly what would be left
    # behind by a prior successful run before the dump started failing.
    stale = {
        "schema": 1,
        "source": "odoo.ir_model_fields",
        "base_db": "basedb",
        "module_set_sha": "modsha123",
        "models": {"res.partner": {"fields": {"name": {"ttype": "char"}}}},
    }
    out_path.write_text(json.dumps(stale), encoding="utf-8")

    fake_bin = _fake_docker_that_fails_at_psql(tmp_path)
    result = _run_dump(SCRIPT, work_dir, out_path, fake_bin)

    assert result.returncode != 0, (
        "a dump failure must exit non-zero, not silently succeed:\n"
        + result.stdout
    )
    assert "NOT-VALIDATED" in result.stdout, (
        "failure must be LOUD (un-missable NOT-VALIDATED marker), not a quiet "
        "WARNING a green verdict can hide:\n" + result.stdout
    )

    # The critical fail-closed assertion: the catalog must be POISONED, not
    # left as the stale-but-valid version that would silently pass downstream.
    after = json.loads(out_path.read_text(encoding="utf-8"))
    assert after.get("schema") != 1, (
        "a failed dump left a schema==1 (looks-valid) catalog in place -- "
        "this is the exact silent-stale-pass regression:\n" + result.stdout
    )


def test_dump_failure_poison_marker_downstream_reads_as_not_screened(tmp_path):
    """Confirm the poisoned catalog actually trips check-schema-catalog.py's
    own fail-closed path (no changes needed there -- it already treats
    schema != 1 as unavailable/NOT screened, and --strict turns that into a
    hard failure; this proves the two files still compose correctly)."""
    work_dir = tmp_path / "work"
    work_dir.mkdir()
    out_path = work_dir / "catalog.json"
    out_path.write_text(
        json.dumps({"schema": 1, "models": {"x": {"fields": {}}}}),
        encoding="utf-8",
    )
    fake_bin = _fake_docker_that_fails_at_psql(tmp_path)
    _run_dump(SCRIPT, work_dir, out_path, fake_bin)

    checker = (
        ROOT
        / "templates"
        / "domain-packs"
        / "odoo"
        / "validation-harness"
        / "check-schema-catalog.py"
    )
    (work_dir / "custom-addons" / "mod1").mkdir(parents=True)
    (work_dir / "custom-addons" / "mod1" / "__manifest__.py").write_text(
        "{'name': 'mod1'}\n", encoding="utf-8"
    )
    result = subprocess.run(
        [
            "python3",
            str(checker),
            "--catalog",
            str(out_path),
            "--root",
            "custom-addons",
            "--modules",
            "mod1",
            "--strict",
        ],
        cwd=work_dir,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    assert result.returncode != 0, (
        "check-schema-catalog.py --strict must fail closed against a "
        "poisoned catalog:\n" + result.stdout
    )
    assert "NOT screened" in result.stdout, result.stdout
