import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _run_guard(*, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    merged_env.update(env)
    return subprocess.run(
        [
            "bash",
            "-c",
            '. scripts/docker-config-guard.sh; ai_auto_configure_docker_config; printf "DOCKER_CONFIG=%s\\n" "${DOCKER_CONFIG:-}"',
        ],
        cwd=ROOT,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def test_docker_config_guard_uses_temp_config_for_wsl_desktop_credsstore(tmp_path: Path) -> None:
    home = tmp_path / "home"
    docker_config = home / ".docker"
    guard_dir = tmp_path / "guard"
    docker_config.mkdir(parents=True)
    (docker_config / "config.json").write_text('{"credsStore": "desktop.exe"}\n', encoding="utf-8")

    result = _run_guard(
        env={
            "HOME": str(home),
            "AI_AUTO_DOCKER_CONFIG_DIR": str(guard_dir),
            "DOCKER_CONFIG": "",
        }
    )

    assert result.returncode == 0, result.stderr
    assert f"DOCKER_CONFIG={guard_dir}" in result.stdout
    assert guard_dir.is_dir()


def test_docker_config_guard_does_not_override_explicit_docker_config(tmp_path: Path) -> None:
    home = tmp_path / "home"
    docker_config = home / ".docker"
    explicit_config = tmp_path / "explicit"
    docker_config.mkdir(parents=True)
    (docker_config / "config.json").write_text('{"credsStore": "desktop.exe"}\n', encoding="utf-8")

    result = _run_guard(
        env={
            "HOME": str(home),
            "AI_AUTO_DOCKER_CONFIG_DIR": str(tmp_path / "guard"),
            "DOCKER_CONFIG": str(explicit_config),
        }
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout == f"DOCKER_CONFIG={explicit_config}\n"


def test_docker_config_guard_is_noop_without_wsl_desktop_credsstore(tmp_path: Path) -> None:
    home = tmp_path / "home"
    docker_config = home / ".docker"
    docker_config.mkdir(parents=True)
    (docker_config / "config.json").write_text('{"auths": {}}\n', encoding="utf-8")

    result = _run_guard(
        env={
            "HOME": str(home),
            "AI_AUTO_DOCKER_CONFIG_DIR": str(tmp_path / "guard"),
            "DOCKER_CONFIG": "",
        }
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout == "DOCKER_CONFIG=\n"
