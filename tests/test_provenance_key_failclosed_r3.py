"""RED6-1 regression: the in-tree provenance-key-refusal predicate must fail CLOSED
(refuse/treat-as-in-tree) when path resolution itself fails, in every copy of the check.

Background (.ops-game/R2-red6-connectivity.md, finding RED6-1): `scripts/review-gate.sh`'s
`review_provenance_key_in_tree` was hardened so that a `realpath -m` (or its `python3
os.path.realpath` fallback) resolution FAILURE returns 0 (= in-tree = REFUSE), because treating
an unresolvable key path as "definitely not in tree" would let an attacker-plantable key slip
past the out-of-tree-HMAC-key trust boundary. Three other copies of the identical security
predicate were never given the same fix and instead returned 1 (= not in tree = ALLOW) on a
`realpath` failure -- the opposite, fail-OPEN, direction:

  - scripts/ai-principal-runtime.sh  (principal_evidence_key_in_tree)
  - scripts/run-ai-reviews.sh        (byte-identical duplicate of the same function)
  - templates/domain-packs/odoo/hooks/pre-push (odoo_ack_key_in_tree)

This file exercises the REAL function bodies from all three (still-)patched files via
function-boundary extraction + a small bash harness (mirrors tests/test_reviewer_restore_ip3.py's
technique) -- none of these three scripts are safe to `source` directly (ai-principal-runtime.sh
runs `main "$@"` unconditionally at EOF; run-ai-reviews.sh executes a full review run at EOF;
pre-push runs the Odoo validation pipeline unconditionally). Extracting the functions verbatim
means editing the real source changes what these tests execute, with no separate copy to drift.

Revert-proof: reverting `*_key_in_tree`'s two `|| return 0` resolution-failure lines back to
`|| return 1` (the original stale/fail-open form, with the plain `realpath -m -- ... 2>/dev/null`
calls and no `*_abs_path` helper) makes the `*_fails_closed_when_resolution_unavailable` test in
each class below FAIL (observed RC=1/allow instead of the required RC=0/refuse).
"""

import os
import re
import shutil
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AI_PRINCIPAL_RUNTIME = ROOT / "scripts" / "ai-principal-runtime.sh"
RUN_AI_REVIEWS = ROOT / "scripts" / "run-ai-reviews.sh"
ODOO_PRE_PUSH = ROOT / "templates" / "domain-packs" / "odoo" / "hooks" / "pre-push"

BASH = shutil.which("bash") or "/usr/bin/bash"
GIT = shutil.which("git") or "/usr/bin/git"


def _extract_bash_functions(script_path: Path, names: set) -> str:
    """Pull top-level `name() { ... }` bodies verbatim out of a bash script (same technique as
    tests/test_reviewer_restore_ip3.py's `_extract_bash_functions`)."""
    out = []
    capturing = False
    found = set()
    for line in script_path.read_text().splitlines():
        if not capturing:
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{", line)
            if m and m.group(1) in names:
                capturing = True
                found.add(m.group(1))
                out.append(line)
            continue
        out.append(line)
        if line == "}":
            capturing = False
    missing = names - found
    assert not missing, f"function(s) not found in {script_path}: {missing}"
    return "\n".join(out) + "\n"


def _run_harness(tmp_path: Path, preamble: str, functions_src: str, body: str, *, cwd: Path, env: dict) -> subprocess.CompletedProcess:
    script = tmp_path / "harness.sh"
    script.write_text(
        "#!/usr/bin/env bash\nset -euo pipefail\n"
        + preamble + "\n"
        + functions_src + "\n"
        + body + "\n"
    )
    script.chmod(0o755)
    return subprocess.run(
        [BASH, str(script)],
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=30,
    )


def _restricted_path_env(tmp_path: Path, *, with_git: bool) -> dict:
    """A PATH containing NEITHER `realpath` NOR `python3` (simulating both resolution paths
    failing -- e.g. a minimal container image, or `realpath` genuinely absent), optionally with
    only `git` present (needed by the two functions that call `git rev-parse` themselves)."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    if with_git:
        git_link = bin_dir / "git"
        if not git_link.exists():
            git_link.symlink_to(GIT)
    return {"PATH": str(bin_dir), "HOME": str(tmp_path)}


# ---------------------------------------------------------------------------
# ai-principal-runtime.sh / run-ai-reviews.sh: principal_evidence_key_in_tree
# ---------------------------------------------------------------------------

_PRINCIPAL_EVIDENCE_FUNCS = {
    "principal_evidence_key_file",
    "principal_evidence_abs_path",
    "principal_evidence_key_in_tree",
}

_KEY_IN_TREE_BODY = (
    'principal_evidence_key_in_tree && echo "RC=0" || echo "RC=$?"'
)


def _principal_evidence_case(script_path: Path, tmp_path: Path, *, fail_resolution: bool) -> str:
    repo_dir = tmp_path / "repo"
    repo_dir.mkdir(exist_ok=True)
    subprocess.run([GIT, "init", "-q", str(repo_dir)], check=True)
    outside_dir = tmp_path / "outside"
    outside_dir.mkdir(exist_ok=True)
    key_file = outside_dir / "provenance.key"
    key_file.write_bytes(b"x" * 32)
    key_file.chmod(0o600)

    functions_src = _extract_bash_functions(script_path, _PRINCIPAL_EVIDENCE_FUNCS)

    if fail_resolution:
        env = os.environ.copy()
        env.update(_restricted_path_env(tmp_path, with_git=True))
    else:
        env = os.environ.copy()

    env["AI_AUTO_PROVENANCE_KEY_FILE"] = str(key_file)

    result = _run_harness(
        tmp_path,
        preamble="",
        functions_src=functions_src,
        body=_KEY_IN_TREE_BODY,
        cwd=repo_dir,
        env=env,
    )
    assert result.returncode == 0, f"harness itself failed:\n{result.stdout}"
    return result.stdout.strip().splitlines()[-1]


def test_ai_principal_runtime_fails_closed_when_resolution_unavailable(tmp_path):
    """RED6-1: with realpath AND python3 both absent from PATH, `principal_evidence_key_in_tree`
    in scripts/ai-principal-runtime.sh must REFUSE (RC=0) a genuinely out-of-tree key rather
    than ALLOW it (RC=1) -- resolution failure must fail closed, not open.

    Revert-proof: with the stale `|| return 1` (no `*_abs_path` helper) this prints RC=1."""
    assert _principal_evidence_case(AI_PRINCIPAL_RUNTIME, tmp_path, fail_resolution=True) == "RC=0"


def test_ai_principal_runtime_allows_legitimate_out_of_tree_key(tmp_path):
    """Sanity/non-vacuousness counterpart: with realpath available (normal environment), a truly
    out-of-tree key is still ALLOWED (RC=1) -- the fail-closed fix must not have turned into a
    blanket refusal."""
    assert _principal_evidence_case(AI_PRINCIPAL_RUNTIME, tmp_path, fail_resolution=False) == "RC=1"


def test_run_ai_reviews_fails_closed_when_resolution_unavailable(tmp_path):
    """Same as above for the byte-identical duplicate in scripts/run-ai-reviews.sh (RED6-1 notes
    this copy is separate from ai-principal-runtime.sh's and must be independently patched/tested)."""
    assert _principal_evidence_case(RUN_AI_REVIEWS, tmp_path, fail_resolution=True) == "RC=0"


def test_run_ai_reviews_allows_legitimate_out_of_tree_key(tmp_path):
    assert _principal_evidence_case(RUN_AI_REVIEWS, tmp_path, fail_resolution=False) == "RC=1"


# ---------------------------------------------------------------------------
# templates/domain-packs/odoo/hooks/pre-push: odoo_ack_key_in_tree
# ---------------------------------------------------------------------------

_ODOO_ACK_FUNCS = {
    "odoo_ack_key_file",
    "odoo_ack_abs_path",
    "odoo_ack_key_in_tree",
}

_ODOO_KEY_IN_TREE_BODY = 'odoo_ack_key_in_tree && echo "RC=0" || echo "RC=$?"'


def test_odoo_pre_push_fails_closed_when_resolution_unavailable(tmp_path):
    """RED6-1: odoo_ack_key_in_tree (templates/domain-packs/odoo/hooks/pre-push) takes PROJECT
    as a plain variable (no internal git call), so no git needed in PATH here -- only realpath
    and python3 must be hidden to force a resolution failure.

    Revert-proof: with the stale plain `realpath -m -- ... || return 1` this prints RC=1."""
    project_dir = tmp_path / "repo"
    project_dir.mkdir()
    outside_dir = tmp_path / "outside"
    outside_dir.mkdir()
    key_file = outside_dir / "provenance.key"
    key_file.write_bytes(b"x" * 32)
    key_file.chmod(0o600)

    functions_src = _extract_bash_functions(ODOO_PRE_PUSH, _ODOO_ACK_FUNCS)
    env = os.environ.copy()
    env.update(_restricted_path_env(tmp_path, with_git=False))
    env["AI_AUTO_PROVENANCE_KEY_FILE"] = str(key_file)

    result = _run_harness(
        tmp_path,
        preamble=f'PROJECT={project_dir}\n',
        functions_src=functions_src,
        body=_ODOO_KEY_IN_TREE_BODY,
        cwd=project_dir,
        env=env,
    )
    assert result.returncode == 0, f"harness itself failed:\n{result.stdout}"
    assert result.stdout.strip().splitlines()[-1] == "RC=0"


def test_odoo_pre_push_allows_legitimate_out_of_tree_key(tmp_path):
    project_dir = tmp_path / "repo"
    project_dir.mkdir()
    outside_dir = tmp_path / "outside"
    outside_dir.mkdir()
    key_file = outside_dir / "provenance.key"
    key_file.write_bytes(b"x" * 32)
    key_file.chmod(0o600)

    functions_src = _extract_bash_functions(ODOO_PRE_PUSH, _ODOO_ACK_FUNCS)
    env = os.environ.copy()
    env["AI_AUTO_PROVENANCE_KEY_FILE"] = str(key_file)

    result = _run_harness(
        tmp_path,
        preamble=f'PROJECT={project_dir}\n',
        functions_src=functions_src,
        body=_ODOO_KEY_IN_TREE_BODY,
        cwd=project_dir,
        env=env,
    )
    assert result.returncode == 0, f"harness itself failed:\n{result.stdout}"
    assert result.stdout.strip().splitlines()[-1] == "RC=1"
