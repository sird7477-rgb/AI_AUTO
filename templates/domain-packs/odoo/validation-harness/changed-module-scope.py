#!/usr/bin/env python3
"""Compute changed Odoo addon scope, optionally expanded by reverse dependencies."""

from __future__ import annotations

import argparse
import ast
from pathlib import Path


def load_deps(addons_root: Path) -> dict[str, set[str]]:
    deps: dict[str, set[str]] = {}
    for manifest in sorted(addons_root.glob("*/__manifest__.py")):
        name = manifest.parent.name
        try:
            data = ast.literal_eval(manifest.read_text(encoding="utf-8"))
        except Exception:
            deps[name] = set()
            continue
        if not data.get("installable", True):
            continue
        deps[name] = set(data.get("depends", []) or [])
    return deps


def reverse_closure(deps: dict[str, set[str]], changed: set[str]) -> list[str]:
    custom = set(deps)
    reverse: dict[str, set[str]] = {}
    for addon, addon_deps in deps.items():
        for dep in addon_deps:
            if dep in custom:
                reverse.setdefault(dep, set()).add(addon)
    closure = {addon for addon in changed if addon in custom}
    stack = list(closure)
    while stack:
        addon = stack.pop()
        for dependent in reverse.get(addon, set()):
            if dependent not in closure:
                closure.add(dependent)
                stack.append(dependent)
    return sorted(closure)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addons-root", default="custom-addons")
    parser.add_argument("--changed", nargs="+", required=True)
    parser.add_argument("--reverse-deps", action="store_true")
    parser.add_argument("--format", choices=("comma", "space", "lines"), default="comma")
    args = parser.parse_args()

    deps = load_deps(Path(args.addons_root))
    changed = set(args.changed)
    scope = reverse_closure(deps, changed) if args.reverse_deps else sorted(changed & set(deps))

    if args.format == "comma":
        print(",".join(scope))
    elif args.format == "space":
        print(" ".join(scope))
    else:
        print("\n".join(scope))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
