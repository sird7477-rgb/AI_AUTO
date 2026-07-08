"""RED-16 BLUE fix (ops-defense game #2, final open finding): namespace the
validation-harness's built Docker IMAGE tag and its `.deps.txt` build input by
HARNESS_SLUG/COMPOSE_PROJECT_NAME, the same way the container/network/volume
already are.

Confirmed defect (MEDIUM/LATENT, see .ops-game2/R12-red16-certification.md finding
#1): `docker-compose.validate.yml`'s `odoo` service pinned an explicit, GLOBAL image
tag (`image: odoo19-validate:local`) and `prepare-base-db.sh`/`validate-odoo.sh` wrote
their pip build input to a fixed, un-namespaced path (`$HERE/.deps.txt`, `$HERE` being
the harness script directory -- shared by every project pointed at the same
ODOO_HARNESS_DIR). Docker Compose auto-prefixes containers/networks/unnamed volumes
with COMPOSE_PROJECT_NAME, but does NOT auto-prefix an explicit `image:` -- so two
DIFFERENT repos sharing one ODOO_HARNESS_DIR, both hitting the missing-base/rebuild
path at overlapping times, could have one project's `.deps.txt` write and `dc build`
"win" the shared `odoo19-validate:local` tag, silently validating the OTHER project
against unreviewed dependencies (false-negative validation, not RCE -- containers run
:ro, no docker.sock, non-privileged).

Fix (PREFERRED, not the fallback-warning path): thread COMPOSE_PROJECT_NAME into (a)
the compose `image:` field -- `odoo19-validate:${COMPOSE_PROJECT_NAME:-local}` -- and
(b) a build ARG `DEPS_FILE` (default `.deps.txt`, for a raw `docker build .` with no
compose args) that the Dockerfile now COPYs from instead of a literal `.deps.txt`;
`prepare-base-db.sh`/`validate-odoo.sh` now `cp` their computed deps content into
`$HERE/.deps.${COMPOSE_PROJECT_NAME}.txt` -- the file the build ARG actually
resolves to -- in ADDITION to the legacy `$HERE/.deps.txt` (kept, unchanged, as a
human-readable "last run" artifact so the existing, already-shipped test suite that
asserts on `.deps.txt` content keeps passing unchanged).

These tests are hermetic:
  - The compose-file namespacing tests do NOT invoke a real `docker`/`docker compose`
    binary at all -- they read the REAL, shipped `docker-compose.validate.yml` off
    disk and apply a small, self-contained reimplementation of Docker Compose's
    `${VAR:-default}` string-interpolation syntax (verified by hand against a real
    `docker compose -f docker-compose.validate.yml config --images` run during
    authoring -- both agree byte-for-byte for every case exercised here). No build,
    no daemon, no network.
  - The end-to-end script test uses the SAME scripted fake `docker` binary pattern as
    tests/test_odoo_prepare_base_db_defense2.py (logs invocations, answers
    version/info/build/up/exec/run with canned success) -- never a real image build.

Non-vacuousness (PROJECT RULE: pin pre-fix behavior as an embedded literal, never
`git show HEAD` at test time): OLD_COMPOSE_IMAGE_LINE below is the exact, literal
pre-fix `image:` line (`odoo19-validate:local`, no `${...}` interpolation at all) --
applying the same two-slug interpolation to it shows both slugs collapse to the
IDENTICAL tag, which is exactly the cross-repo-contamination precondition RED-16
describes. OLD_PREPARE_BASE_DB_DEPS_WRITE_SH is the exact pre-fix deps-write shape
(writes ONLY the unnamespaced `$HERE/.deps.txt`) -- driven through the same
two-different-projects-one-harness-dir scenario used against the real, fixed
prepare-base-db.sh below, and shown to let project B's write clobber project A's.
"""
from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ODOO_PACK = ROOT / "templates" / "domain-packs" / "odoo"
HARNESS_SRC = ODOO_PACK / "validation-harness"
COMPOSE_FILE = HARNESS_SRC / "docker-compose.validate.yml"
DOCKERFILE = HARNESS_SRC / "Dockerfile"

_HARNESS_FILES = [
    "prepare-base-db.sh",
    "validate-odoo.sh",
    "validate-full.sh",
    "validate-warm.sh",
    "harness-preflight.sh",
    "harness-slug.sh",
    "harness-lock.sh",
    "docker-compose.validate.yml",
    "Dockerfile",
    "setup_company.py",
]


# --------------------------------------------------------------------------
# shared fixture helpers (small, local copies -- mirrors the pattern already
# used by the sibling defense2 test files rather than importing across them)
# --------------------------------------------------------------------------
def _git(args: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=cwd, text=True, capture_output=True, check=check)


def _init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    _git(["init", "-q"], path)
    _git(["config", "user.email", "t@example.invalid"], path)
    _git(["config", "user.name", "T"], path)


def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _copy_harness(tmp_path: Path, name: str = "harness") -> Path:
    harness = tmp_path / name
    harness.mkdir()
    for fname in _HARNESS_FILES:
        dst = harness / fname
        shutil.copy2(HARNESS_SRC / fname, dst)
        if fname.endswith(".sh"):
            _make_executable(dst)
    return harness


def _make_module(root: Path, name: str, py_deps: list[str] | None = None) -> None:
    mod = root / name
    mod.mkdir(parents=True, exist_ok=True)
    deps_repr = repr(py_deps or [])
    (mod / "__manifest__.py").write_text(
        "{'name': '%s', 'depends': [], 'installable': True, "
        "'external_dependencies': {'python': %s}}\n" % (name, deps_repr),
        encoding="utf-8",
    )


# A small, SCRIPTED fake `docker`: logs every invocation, answers preflight
# (version/info) and the compose subcommands (build/up/exec/run) with canned
# success -- never a real image build. Matches
# tests/test_odoo_prepare_base_db_defense2.py's established pattern.
_FAKE_DOCKER_SH = """#!/usr/bin/env bash
set -u
: "${DOCKER_CALL_LOG:?DOCKER_CALL_LOG not set}"
printf '%s\\n' "$*" >> "$DOCKER_CALL_LOG"

case "${1:-}" in
  version) echo "24.0.0"; exit 0 ;;
  info) exit 0 ;;
  rm) exit 0 ;;
esac

if [ "${1:-}" = "compose" ]; then
  shift
  if [ "${1:-}" = "-f" ]; then shift 2; fi
  verb="${1:-}"
  case "$verb" in
    build) exit 0 ;;
    up) exit 0 ;;
    exec)
      rest="$*"
      case "$rest" in
        *psql*) printf 'base                                                            | odoo     | UTF8     |\\n'; exit 0 ;;
        *) exit 0 ;;
      esac
      ;;
    run)
      exit "${FAKE_DOCKER_RUN_EXIT:-0}"
      ;;
    *) exit 0 ;;
  esac
fi
exit 0
"""


def _fake_docker_bin(tmp_path: Path, log_path: Path) -> Path:
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text(_FAKE_DOCKER_SH, encoding="utf-8")
    _make_executable(docker)
    log_path.write_text("", encoding="utf-8")
    return bin_dir


def _base_env(fake_bin: Path, docker_log: Path, extra: dict | None = None) -> dict:
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
    env["DOCKER_CALL_LOG"] = str(docker_log)
    for k in (
        "FAKE_DOCKER_RUN_EXIT", "PREPARE_BASE_ADDONS_DIR", "PREPARE_BASE_REQUIREMENTS",
        "COMPOSE_PROJECT_NAME", "HARNESS_SLUG", "HARNESS_LOCK_FILE",
    ):
        env.pop(k, None)
    if extra:
        env.update(extra)
    return env


def _harness_proj_slug(harness: Path, project: Path) -> str:
    """Drive the REAL harness-slug.sh (not a reimplementation) to get the exact
    slug the harness scripts will compute for `project` -- used only to predict
    the expected filename, mirroring tests/test_slug_and_scope_r4.py's pattern."""
    cmd = f'. "{harness / "harness-slug.sh"}"; harness_proj_slug "{project}"'
    result = subprocess.run(["bash", "-c", cmd], text=True, capture_output=True, check=True)
    return result.stdout.strip()


# ==========================================================================
# Compose-file interpolation semantics: a small, self-contained reimplementation
# of Docker Compose's `${VAR:-default}` / `${VAR}` substitution, applied to the
# REAL, shipped docker-compose.validate.yml (read off disk, never rewritten).
# Verified by hand against `docker compose -f docker-compose.validate.yml config
# --images` (with ODOO_COMMUNITY/ODOO_ENTERPRISE/PROJECT_ADDONS stubbed and
# DOCKER_HOST pointed at a nonexistent socket, proving no daemon contact is
# needed) during authoring: both agree for every case exercised below.
# ==========================================================================
_VAR_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]*))?\}")


def _compose_interp(template: str, env: dict) -> str:
    def repl(m: re.Match) -> str:
        name, _, default = m.group(1), m.group(2), m.group(3)
        if name in env and env[name] != "":
            return env[name]
        return default if default is not None else ""
    return _VAR_RE.sub(repl, template)


def _real_compose_text() -> str:
    return COMPOSE_FILE.read_text(encoding="utf-8")


def _real_image_template() -> str:
    """Extract the `odoo` service's `image:` value line via a targeted regex (no
    yaml dependency available in this venv) -- disambiguated from the `db`
    service's `image: postgres:16` by requiring the `odoo19-validate` prefix."""
    text = _real_compose_text()
    m = re.search(r"^\s*image:\s*(odoo19-validate:\S+)\s*$", text, re.MULTILINE)
    assert m, f"no `image: odoo19-validate:...` line found in {COMPOSE_FILE}:\n{text}"
    return m.group(1)


def _real_deps_file_template() -> str:
    text = _real_compose_text()
    m = re.search(r"^\s*DEPS_FILE:\s*(\S+)\s*$", text, re.MULTILINE)
    assert m, f"no `DEPS_FILE: ...` build arg line found in {COMPOSE_FILE}:\n{text}"
    return m.group(1)


def test_shipped_compose_image_and_deps_are_parameterized_by_compose_project_name():
    """Structural precondition: the REAL, shipped compose file's `image:` and
    `build.args.DEPS_FILE` must reference COMPOSE_PROJECT_NAME (not be bare
    literals) -- otherwise every test below would be vacuously testing dead code."""
    image_tmpl = _real_image_template()
    deps_tmpl = _real_deps_file_template()
    assert "${COMPOSE_PROJECT_NAME" in image_tmpl, image_tmpl
    assert "${COMPOSE_PROJECT_NAME" in deps_tmpl, deps_tmpl


def test_image_tag_differs_between_two_distinct_slugs():
    image_tmpl = _real_image_template()
    tag_a = _compose_interp(image_tmpl, {"COMPOSE_PROJECT_NAME": "h-slug-a"})
    tag_b = _compose_interp(image_tmpl, {"COMPOSE_PROJECT_NAME": "h-slug-b"})
    assert tag_a != tag_b, (
        f"two DIFFERENT slugs produced the SAME image tag ({tag_a!r}) -- this is "
        "exactly the RED-16 cross-repo-contamination precondition"
    )
    assert tag_a == "odoo19-validate:h-slug-a"
    assert tag_b == "odoo19-validate:h-slug-b"


def test_deps_file_path_differs_between_two_distinct_slugs():
    deps_tmpl = _real_deps_file_template()
    deps_a = _compose_interp(deps_tmpl, {"COMPOSE_PROJECT_NAME": "h-slug-a"})
    deps_b = _compose_interp(deps_tmpl, {"COMPOSE_PROJECT_NAME": "h-slug-b"})
    assert deps_a != deps_b, (
        f"two DIFFERENT slugs produced the SAME .deps.txt build-context path "
        f"({deps_a!r}) -- two repos could clobber one shared build input"
    )
    assert deps_a == ".deps.h-slug-a.txt"
    assert deps_b == ".deps.h-slug-b.txt"


def test_image_tag_and_deps_path_are_stable_for_the_same_slug():
    """Same slug -> same/reused tag and deps path (not a fresh name every run --
    a project must keep reusing/rebuilding its OWN image, matching the existing
    per-project base/volume caching model)."""
    image_tmpl = _real_image_template()
    deps_tmpl = _real_deps_file_template()
    env = {"COMPOSE_PROJECT_NAME": "h-repeat-me"}
    assert _compose_interp(image_tmpl, env) == _compose_interp(image_tmpl, env)
    assert _compose_interp(deps_tmpl, env) == _compose_interp(deps_tmpl, env)
    # And explicitly identical across two independent calls (not e.g. time-seeded):
    tag1 = _compose_interp(image_tmpl, {"COMPOSE_PROJECT_NAME": "h-repeat-me"})
    tag2 = _compose_interp(image_tmpl, {"COMPOSE_PROJECT_NAME": "h-repeat-me"})
    assert tag1 == tag2 == "odoo19-validate:h-repeat-me"


def test_default_unset_slug_falls_back_to_today_name():
    """Default/standalone behavior: if COMPOSE_PROJECT_NAME is genuinely unset
    (bypassing every wrapper script, e.g. a raw `docker compose` invocation), the
    image tag and deps path fall back to TODAY's exact, pre-fix literals -- no
    breakage for the common single-repo case."""
    image_tmpl = _real_image_template()
    deps_tmpl = _real_deps_file_template()
    assert _compose_interp(image_tmpl, {}) == "odoo19-validate:local"
    assert _compose_interp(deps_tmpl, {}) == ".deps.local.txt"


# Non-vacuousness control: the exact pre-fix `image:` line, embedded literally
# (never fetched from git history) -- a bare tag with NO `${...}` interpolation.
OLD_COMPOSE_IMAGE_LINE = "odoo19-validate:local"


def test_old_bare_image_tag_would_have_collapsed_both_slugs_to_one_tag():
    """Proves the defect was real: applying the identical two-slug interpolation
    to the OLD, un-namespaced literal produces the SAME tag for both slugs (there
    is nothing to interpolate) -- the exact cross-repo-contamination precondition
    RED-16 describes."""
    tag_a = _compose_interp(OLD_COMPOSE_IMAGE_LINE, {"COMPOSE_PROJECT_NAME": "h-slug-a"})
    tag_b = _compose_interp(OLD_COMPOSE_IMAGE_LINE, {"COMPOSE_PROJECT_NAME": "h-slug-b"})
    assert tag_a == tag_b == "odoo19-validate:local", (
        "the embedded pre-fix image line no longer collapses both slugs to one tag "
        "-- this control is no longer discriminating"
    )


# ==========================================================================
# Dockerfile: structural check that the shipped Dockerfile actually threads the
# ARG through (the compose-side namespacing above is inert if the Dockerfile
# still hardcodes `COPY .deps.txt`).
# ==========================================================================
def test_dockerfile_copies_from_the_deps_file_arg_not_a_hardcoded_literal():
    text = DOCKERFILE.read_text(encoding="utf-8")
    assert re.search(r"^ARG\s+DEPS_FILE=\.deps\.txt\s*$", text, re.MULTILINE), (
        f"Dockerfile has no `ARG DEPS_FILE=.deps.txt` fallback declaration:\n{text}"
    )
    assert re.search(r"^COPY\s+\$\{DEPS_FILE\}\s+/tmp/\.deps\.txt\s*$", text, re.MULTILINE), (
        f"Dockerfile's COPY does not source ${{DEPS_FILE}} -- the build ARG is dead:\n{text}"
    )
    # Regression guard: no OTHER hardcoded `COPY .deps.txt` (the pre-fix line) survives.
    assert "COPY .deps.txt /tmp/.deps.txt" not in text, (
        "Dockerfile still has the old hardcoded COPY alongside/instead of the ARG'd one"
    )


# ==========================================================================
# Regression: no reference site was missed. Every literal mention of the image
# tag / .deps.txt build input across the WHOLE harness dir must be consistent
# with the namespaced scheme -- a stray hardcoded `odoo19-validate:local` (e.g.
# in a script doing `docker image inspect`/`rmi`) would mean that reference
# can't find the per-slug image the build step actually produced.
# ==========================================================================
def test_no_stray_hardcoded_image_tag_outside_the_compose_file():
    offenders = []
    for path in sorted(HARNESS_SRC.iterdir()):
        if not path.is_file() or path == COMPOSE_FILE:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        if "odoo19-validate" in text:
            offenders.append(path.name)
    assert not offenders, (
        f"found a hardcoded 'odoo19-validate' image-tag reference outside "
        f"docker-compose.validate.yml in: {offenders} -- this reference would not "
        f"resolve to the per-slug image the build step produces"
    )


def test_deps_write_sites_all_namespace_by_compose_project_name():
    """Regression: every script that WRITES the build-context deps file must also
    mirror it into the COMPOSE_PROJECT_NAME-namespaced path the Dockerfile ARG
    actually consumes -- a script that only writes the legacy `.deps.txt` would
    silently keep contributing to the shared/clobberable file."""
    writers = {
        "prepare-base-db.sh": HARNESS_SRC / "prepare-base-db.sh",
        "validate-odoo.sh": HARNESS_SRC / "validate-odoo.sh",
    }
    for name, path in writers.items():
        text = path.read_text(encoding="utf-8")
        assert '> "$HERE/.deps.txt"' in text or "> \"$HERE/.deps.txt\"" in text, (
            f"{name} no longer writes the legacy .deps.txt (backward-compat break)"
        )
        assert re.search(r'\.deps\.\$\{?COMPOSE_PROJECT_NAME\}?\.txt', text), (
            f"{name} does not mirror its deps write into a COMPOSE_PROJECT_NAME-"
            f"namespaced path -- a missed reference, the Docker build would still "
            f"consume the shared/global .deps.txt for this caller"
        )


# ==========================================================================
# End-to-end, via the real (fake-docker-backed) prepare-base-db.sh: two
# DIFFERENT repos sharing one harness dir (== one ODOO_HARNESS_DIR) must each
# get their OWN namespaced deps file, and neither clobbers the other's.
# ==========================================================================
def test_two_different_repos_sharing_one_harness_dir_get_distinct_deps_files_no_clobber(tmp_path):
    project_a = tmp_path / "repo-a"
    project_b = tmp_path / "repo-b"
    _make_module(project_a / "custom-addons", "mod_a", py_deps=["deps_only_repo_a"])
    _make_module(project_b / "custom-addons", "mod_b", py_deps=["deps_only_repo_b"])

    # ONE shared harness dir -- the documented "one ODOO_HARNESS_DIR" setup RED-16
    # flags as the deployment pattern that exposes the defect.
    harness = _copy_harness(tmp_path)
    slug_a = _harness_proj_slug(harness, project_a)
    slug_b = _harness_proj_slug(harness, project_b)
    assert slug_a != slug_b, "test setup invalid: two different repos hashed to the same slug"

    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)

    def run(project: Path) -> subprocess.CompletedProcess[str]:
        env = _base_env(fake_bin, docker_log)
        return subprocess.run(
            ["bash", str(harness / "prepare-base-db.sh"), str(project)],
            cwd=harness, env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
        )

    result_a = run(project_a)
    assert result_a.returncode == 0, result_a.stdout
    deps_a_path = harness / f".deps.{slug_a}.txt"
    assert deps_a_path.exists(), (
        f"expected namespaced deps file for repo A at {deps_a_path} was not written"
    )
    assert "deps_only_repo_a" in deps_a_path.read_text(encoding="utf-8")

    result_b = run(project_b)
    assert result_b.returncode == 0, result_b.stdout
    deps_b_path = harness / f".deps.{slug_b}.txt"
    assert deps_b_path.exists(), (
        f"expected namespaced deps file for repo B at {deps_b_path} was not written"
    )
    assert "deps_only_repo_b" in deps_b_path.read_text(encoding="utf-8")

    # THE core RED-16 proof: repo A's namespaced file must SURVIVE repo B's later
    # run in the SAME shared harness dir -- no clobber.
    assert "deps_only_repo_a" in deps_a_path.read_text(encoding="utf-8"), (
        "repo A's namespaced deps file was overwritten/clobbered by repo B's run "
        "in the shared harness dir -- the RED-16 defect is NOT fixed"
    )
    assert "deps_only_repo_b" not in deps_a_path.read_text(encoding="utf-8")
    assert "deps_only_repo_a" not in deps_b_path.read_text(encoding="utf-8")


def test_same_project_run_twice_reuses_the_same_namespaced_deps_file(tmp_path):
    """Regression: the SAME repo, run twice, must resolve to the SAME namespaced
    filename both times (stable naming -- not e.g. a fresh/random name per run)."""
    project = tmp_path / "repo"
    _make_module(project / "custom-addons", "mod1", py_deps=["somepkg"])

    harness = _copy_harness(tmp_path)
    slug = _harness_proj_slug(harness, project)

    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    env = _base_env(fake_bin, docker_log)

    for _ in range(2):
        result = subprocess.run(
            ["bash", str(harness / "prepare-base-db.sh"), str(project)],
            cwd=harness, env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
        )
        assert result.returncode == 0, result.stdout

    deps_path = harness / f".deps.{slug}.txt"
    assert deps_path.exists()
    assert "somepkg" in deps_path.read_text(encoding="utf-8")
    # Only ONE namespaced deps file for this repo exists (no accumulation of
    # differently-named files across repeated runs of the SAME project).
    namespaced = sorted(p.name for p in harness.glob(".deps.*.txt"))
    assert namespaced == [f".deps.{slug}.txt"], namespaced


def test_legacy_deps_txt_still_written_backward_compat(tmp_path):
    """Regression: the pre-existing, already-shipped test suite asserts on the
    plain `.deps.txt` (see tests/test_odoo_prepare_base_db_defense2.py,
    tests/test_odoo_prepush_enforced_gate_r11.py) -- this fix must not remove
    that file, only add the namespaced one alongside it."""
    project = tmp_path / "repo"
    _make_module(project / "custom-addons", "mod1", py_deps=["legacycheck"])

    harness = _copy_harness(tmp_path)
    docker_log = tmp_path / "docker.log"
    fake_bin = _fake_docker_bin(tmp_path, docker_log)
    env = _base_env(fake_bin, docker_log)

    result = subprocess.run(
        ["bash", str(harness / "prepare-base-db.sh"), str(project)],
        cwd=harness, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
    )
    assert result.returncode == 0, result.stdout
    legacy = harness / ".deps.txt"
    assert legacy.exists()
    assert "legacycheck" in legacy.read_text(encoding="utf-8")


# Non-vacuousness control for the end-to-end proof: the exact pre-fix deps-write
# shape (writes ONLY the unnamespaced `.deps.txt`), embedded literally, driven
# through the identical two-repos-one-harness-dir scenario.
OLD_PREPARE_BASE_DB_DEPS_WRITE_SH = """#!/usr/bin/env bash
set -euo pipefail
HERE="$1"; PROJECT_ADDONS="$2"
python3 - "$PROJECT_ADDONS" > "$HERE/.deps.txt" <<'PY'
import ast,glob,os,sys
root=sys.argv[1]; deps=set()
for m in glob.glob(os.path.join(root,"*","__manifest__.py")):
    try:
        d=ast.literal_eval(open(m,encoding="utf-8").read())
        for p in (d.get("external_dependencies",{}) or {}).get("python",[]) or []: deps.add(p)
    except Exception: pass
print("\\n".join(sorted(deps)))
PY
"""


def test_old_deps_write_would_have_let_repo_b_clobber_repo_a_in_shared_harness_dir(tmp_path):
    project_a = tmp_path / "repo-a"
    project_b = tmp_path / "repo-b"
    _make_module(project_a / "custom-addons", "mod_a", py_deps=["deps_only_repo_a"])
    _make_module(project_b / "custom-addons", "mod_b", py_deps=["deps_only_repo_b"])

    here = tmp_path / "harness_old"
    here.mkdir()
    old_script = tmp_path / "old_deps_write.sh"
    old_script.write_text(OLD_PREPARE_BASE_DB_DEPS_WRITE_SH, encoding="utf-8")
    old_script.chmod(old_script.stat().st_mode | stat.S_IXUSR)

    r_a = subprocess.run(
        ["bash", str(old_script), str(here), str(project_a / "custom-addons")],
        text=True, capture_output=True, check=False,
    )
    assert r_a.returncode == 0, r_a.stdout + r_a.stderr
    assert "deps_only_repo_a" in (here / ".deps.txt").read_text(encoding="utf-8")

    # Repo B's build runs SECOND in the SAME shared harness dir -- exactly the
    # "overlapping/sequential first-builds" scenario RED-16 describes.
    r_b = subprocess.run(
        ["bash", str(old_script), str(here), str(project_b / "custom-addons")],
        text=True, capture_output=True, check=False,
    )
    assert r_b.returncode == 0, r_b.stdout + r_b.stderr

    final = (here / ".deps.txt").read_text(encoding="utf-8")
    assert "deps_only_repo_b" in final
    assert "deps_only_repo_a" not in final, (
        "the embedded pre-fix deps-write no longer reproduces the clobber -- this "
        f"control is no longer discriminating. final .deps.txt:\n{final}"
    )
