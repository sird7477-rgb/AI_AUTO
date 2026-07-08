"""BLUE fix (ops-defense2): dump-schema-catalog.sh poisons $OUT too late.

Confirmed defect being closed here:

  templates/domain-packs/odoo/validation-harness/dump-schema-catalog.sh runs
  `set -euo pipefail` (line 4), then `psql_csv="$(mktemp)"` BEFORE the trap
  and BEFORE fail_loud() (the function that actually poisons $OUT) are even
  defined. If that first mktemp call -- or anything else before the
  poisoning machinery is armed -- fails under `set -e`, the script dies
  WITHOUT ever poisoning $OUT. A pre-existing stale `{"schema": 1, ...}`
  catalog at $OUT then survives untouched and is silently reused as fresh by
  check-schema-catalog.py. Confirmed via `TMPDIR=/nonexistent`.

Fix (dump-schema-catalog.sh only; this file's edit boundary):
  $OUT is poisoned to `{"schema": 0, ...}` IMMEDIATELY after it is resolved,
  before the first fallible command (mktemp included), via a synchronous
  write AND an EXIT trap that keeps re-asserting the poison unless
  `out_finalized=1` is set. `out_finalized` is set to 1 only on the two
  deliberate paths that leave $OUT holding a true final value: fail_loud()'s
  own detailed poison, or the real success path's `mv "$tmp" "$OUT"`.

Non-vacuousness: against the pre-fix script (available via `git show
HEAD:templates/domain-packs/odoo/validation-harness/dump-schema-catalog.sh`,
since this edit is uncommitted in this worktree at authoring time), the
early-failure test below leaves the STALE `{"schema": 1}` catalog in place
(the mktemp failure happens before any poisoning code has even run) --
i.e. it reverts to FAIL. See the session's final report for the one-shot
manual revert/rerun proof.
"""
from __future__ import annotations

import json
import os
import stat
import subprocess
from pathlib import Path

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


def _run_dump(script: Path, work_dir: Path, out_path: Path, path_prefix: Path | None = None, extra_env=None):
    env = os.environ.copy()
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}:{env['PATH']}"
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        ["bash", str(script), "basedb", str(out_path), "modsha123"],
        cwd=work_dir,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def _seed_stale_catalog(out_path: Path) -> None:
    stale = {
        "schema": 1,
        "source": "odoo.ir_model_fields",
        "base_db": "basedb",
        "module_set_sha": "modsha123",
        "models": {"res.partner": {"fields": {"name": {"ttype": "char"}}}},
    }
    out_path.write_text(json.dumps(stale), encoding="utf-8")


def test_early_failure_before_fail_loud_still_poisons_stale_catalog(tmp_path):
    """The core regression: force death BEFORE fail_loud()/the original trap
    are even reachable (TMPDIR points nowhere, so the very first `mktemp`
    call fails under `set -e`). A pre-existing stale schema==1 catalog must
    still end up poisoned, not left untouched."""
    work_dir = tmp_path / "work"
    work_dir.mkdir()
    out_path = work_dir / "catalog.json"
    _seed_stale_catalog(out_path)

    nonexistent_tmpdir = tmp_path / "does-not-exist"
    result = _run_dump(SCRIPT, work_dir, out_path, extra_env={"TMPDIR": str(nonexistent_tmpdir)})

    assert result.returncode != 0, (
        "an unwritable TMPDIR must still fail the script, not silently "
        "succeed:\n" + result.stdout
    )
    after = json.loads(out_path.read_text(encoding="utf-8"))
    assert after.get("schema") != 1, (
        "an early pre-fail_loud death (mktemp failing before any poisoning "
        "machinery was armed) left the STALE schema==1 catalog untouched -- "
        "the confirmed too-late-poisoning defect:\n" + result.stdout
    )


def _fake_docker_success(tmp_path: Path) -> Path:
    """A hermetic fake `docker` on PATH: any invocation whose args contain
    'psql' emits one well-formed row and exits 0; everything else no-ops
    successfully. No real Docker daemon or Postgres is touched."""
    bin_dir = tmp_path / "fakebin_success"
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text(
        "#!/usr/bin/env bash\n"
        "for a in \"$@\"; do\n"
        "  if [ \"$a\" = psql ]; then\n"
        "    printf 'res.partner\\tname\\tchar\\t\\t\\tbase\\n'\n"
        "    exit 0\n"
        "  fi\n"
        "done\n"
        "exit 0\n",
        encoding="utf-8",
    )
    _make_executable(docker)
    return bin_dir


def test_success_path_leaves_the_real_catalog_not_poisoned(tmp_path):
    """A normal, successful run must still leave the real catalog
    (schema:1-shape) at $OUT, not a poisoned placeholder -- the early-poison
    fix must not leak into the success path."""
    work_dir = tmp_path / "work"
    work_dir.mkdir()
    out_path = work_dir / "catalog.json"
    out_path.write_text(json.dumps({"schema": 0, "error": "prior run failed"}), encoding="utf-8")

    fake_bin = _fake_docker_success(tmp_path)
    result = _run_dump(SCRIPT, work_dir, out_path, path_prefix=fake_bin)

    assert result.returncode == 0, result.stdout
    after = json.loads(out_path.read_text(encoding="utf-8"))
    assert after.get("schema") == 1, (
        "a successful dump must leave the real catalog (schema:1), not a "
        "poisoned/stale placeholder:\n" + result.stdout
    )
    assert "res.partner" in after.get("models", {}), (
        "successful catalog is missing the expected dumped model:\n" + result.stdout
    )
