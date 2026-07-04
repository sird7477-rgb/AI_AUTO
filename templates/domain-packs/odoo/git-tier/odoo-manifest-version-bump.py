#!/usr/bin/env python3
"""Create one push-time Odoo manifest version bump commit.

This is reference tooling for projects that want to retire per-commit manifest
version hooks. It intentionally runs before `safe-push.sh` pushes, not from a
raw pre-push hook whose pushed SHA has already been selected by Git.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


VERSION_RE = re.compile(
    r"^(?P<prefix>\s*['\"]version['\"]\s*:\s*['\"])(?P<version>[^'\"]+)(?P<suffix>['\"]\s*,?\s*)$"
)


def git(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def git_output(args: list[str], *, check: bool = True) -> str:
    return git(args, check=check).stdout


def ensure_clean_worktree() -> None:
    status = git_output(
        [
            "-c",
            "core.fsmonitor=",
            "-c",
            "core.hooksPath=/dev/null",
            "status",
            "--porcelain=v1",
            "--untracked-files=no",
        ]
    )
    if status.strip():
        raise SystemExit("[manifest-bump] refusing to create a bump commit with a dirty worktree")


def ref_exists(ref: str) -> bool:
    return git(["rev-parse", "--verify", f"{ref}^{{commit}}"], check=False).returncode == 0


def changed_paths(base: str | None) -> list[str]:
    if base and ref_exists(base):
        out = git_output(["diff", "--name-only", f"{base}...HEAD"])
        return [line for line in out.splitlines() if line]

    commits = git_output(["rev-list", "HEAD", "--not", "--remotes"], check=False)
    paths: set[str] = set()
    for commit in [line for line in commits.splitlines() if line]:
        out = git_output(["diff-tree", "-r", "--no-commit-id", "--name-only", commit])
        paths.update(line for line in out.splitlines() if line)
    return sorted(paths)


def modules_from_paths(paths: list[str]) -> list[str]:
    modules: set[str] = set()
    for path in paths:
        parts = Path(path).parts
        if len(parts) >= 3 and parts[0] == "custom-addons":
            modules.add(parts[1])
    return sorted(modules)


def bump_version(value: str) -> str:
    parts = value.split(".")
    for index in range(len(parts) - 1, -1, -1):
        if parts[index].isdigit():
            width = len(parts[index])
            parts[index] = str(int(parts[index]) + 1).zfill(width)
            return ".".join(parts)
    raise ValueError(f"version has no numeric component: {value!r}")


def bump_manifest(path: Path) -> tuple[str, str]:
    if not path.is_file():
        raise SystemExit(f"[manifest-bump] missing manifest: {path}")
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    matches: list[tuple[int, re.Match[str]]] = []
    for index, line in enumerate(lines):
        body = line[:-1] if line.endswith("\n") else line
        match = VERSION_RE.match(body)
        if match:
            matches.append((index, match))
    if len(matches) != 1:
        raise SystemExit(f"[manifest-bump] expected exactly one standalone version line in {path}")

    index, match = matches[0]
    old = match.group("version")
    try:
        new = bump_version(old)
    except ValueError as exc:
        raise SystemExit(f"[manifest-bump] {path}: {exc}") from exc
    newline = "\n" if lines[index].endswith("\n") else ""
    lines[index] = f"{match.group('prefix')}{new}{match.group('suffix')}{newline}"
    path.write_text("".join(lines), encoding="utf-8")
    return old, new


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", help="base ref to compare against, usually refs/remotes/<remote>/<branch>")
    parser.add_argument("--root", default="custom-addons", help="addons root, default: custom-addons")
    parser.add_argument("--commit", action="store_true", help="commit bumped manifests")
    parser.add_argument("--message", default="chore: bump Odoo manifest versions for push")
    parser.add_argument("modules", nargs="*", help="module names; when omitted, derive from changed paths")
    args = parser.parse_args(argv)

    ensure_clean_worktree()
    modules = sorted(set(args.modules)) if args.modules else modules_from_paths(changed_paths(args.base))
    if not modules:
        print("[manifest-bump] no changed custom-addons modules; no version bump needed")
        return 0

    root = Path(args.root)
    bumped: list[Path] = []
    for module in modules:
        manifest = root / module / "__manifest__.py"
        old, new = bump_manifest(manifest)
        bumped.append(manifest)
        print(f"[manifest-bump] {module}: {old} -> {new}")

    if args.commit:
        git(["-c", "core.hooksPath=/dev/null", "add", "--", *[str(path) for path in bumped]])
        git(["-c", "core.hooksPath=/dev/null", "commit", "-m", args.message])
        print(f"[manifest-bump] committed one push-time bump for {len(bumped)} module(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
