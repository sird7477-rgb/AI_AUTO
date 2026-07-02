#!/usr/bin/env python3
"""Static Odoo manifest-integrity screen (no docker).

Failure mode: a module's ``__manifest__.py`` lists a ``data`` / ``demo`` file that
does not exist in the module. ``odoo -u <module>`` and odoo.sh then fail at module
load (``FileNotFoundError`` resolving the data file) -- a post-push build failure
even though nothing crashed at runtime. The pre-push warm-base validation catches
it too, but only when docker + the harness are configured; when that is skipped
(no docker / ``ODOO_HARNESS_DIR`` unset) the missing-file class slips through to
odoo.sh. This screen runs WITHOUT docker, so it closes that gap.

Unlike ``check-action-shape.py`` (which over-approximates a runtime crash shape and
is therefore advisory), a listed ``data``/``demo`` path either exists or it does
not -- the check is deterministic with no false positives, so it is a fail-closed
gate (``--strict``, the default).

Only ``data`` and ``demo`` are checked: they are exact module-relative paths.
``assets`` bundle entries are addons-root-relative (module-name-prefixed) and may
be globs, so a zero-match is not necessarily a typo; they are intentionally NOT
checked here (the warm-base/web-asset build remains their oracle).

Usage:
  check-manifest-files.py [--base REF] [--root DIR] [--all] [--modules M ...] [--no-strict]
    --base REF     integration ref for the diff (default env CHECK_MANIFEST_BASE_REF or 'main')
    --root DIR     addons root to scan (default 'custom-addons')
    --all          check every module under root (ignores the diff)
    --modules M..  check exactly these module names (ignores the diff)
    --no-strict    report only; exit 0 even when files are missing
"""
import argparse
import ast
import os
import subprocess
import sys
from pathlib import Path


def run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, check=False).stdout
    except Exception:
        return ""


# Empty-tree OID fed to `git --attr-source=` so the project's in-repo `.gitattributes` is
# IGNORED on the worktree `--name-only` diff below. git runs the clean filter to decide whether
# a worktree file changed even for `--name-only`, so that diff is a clean-filter RCE vector over
# an untrusted project; --attr-source neutralizes the attribute-driven clean/smudge/textconv/diff
# drivers. (No --no-ext-diff/--no-textconv needed: --name-only emits no patch, so textconv/
# external-diff never run; only the clean filter, which --attr-source disarms.)
_EMPTY_TREE = run(["git", "hash-object", "-t", "tree", os.devnull]).strip() \
    or "4b825dc642cb6eb9a060e54bf8d69288fbee4904"


def manifest_refs(manifest_path):
    """Return [(key, relpath)] for data/demo string entries in a manifest dict."""
    try:
        tree = ast.parse(Path(manifest_path).read_text(encoding="utf-8"))
    except (OSError, SyntaxError):
        return []
    refs = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Dict):
            continue
        # The first Dict reached is the module-level manifest dict.
        for key_node, val_node in zip(node.keys, node.values):
            if not (isinstance(key_node, ast.Constant) and key_node.value in ("data", "demo")):
                continue
            if not isinstance(val_node, ast.List):
                continue
            for elt in val_node.elts:
                if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                    refs.append((key_node.value, elt.value))
        break
    return refs


def changed_modules(base, root):
    files = run(["git", "--attr-source=" + _EMPTY_TREE, "-c", "core.fsmonitor=", "diff", "--name-only", base, "--"]).splitlines()
    # R22: inline `-c core.fsmonitor= -c core.hooksPath=/dev/null` closes the ls-files index-refresh
    # fsmonitor/post-index-change hook RCE on the STANDALONE path (no git-scrub env pin inherited).
    files += run(["git", "-c", "core.fsmonitor=", "-c", "core.hooksPath=/dev/null", "ls-files", "--others", "--exclude-standard", "--"]).splitlines()
    prefix = root.rstrip("/") + "/"
    mods = set()
    for line in files:
        if line.startswith(prefix):
            mod = line[len(prefix):].split("/", 1)[0]
            if mod:
                mods.add(mod)
    return sorted(m for m in mods if (Path(root) / m / "__manifest__.py").is_file())


def module_problems(root, mod):
    moddir = Path(root) / mod
    return [
        (key, rel)
        for key, rel in manifest_refs(moddir / "__manifest__.py")
        if not (moddir / rel).is_file()
    ]


def resolve_modules(args):
    root = args.root
    if args.modules:
        return [m for m in args.modules if (Path(root) / m / "__manifest__.py").is_file()]
    if args.all:
        return sorted(p.parent.name for p in Path(root).glob("*/__manifest__.py"))
    if run(["git", "rev-parse", "--is-inside-work-tree"]).strip() != "true":
        print("[manifest-files] not a git work tree; pass --all or --modules")
        return None
    base = (
        run(["git", "merge-base", args.base, "HEAD"]).strip()
        or run(["git", "rev-parse", "HEAD"]).strip()
    )
    return changed_modules(base, root)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=os.environ.get("CHECK_MANIFEST_BASE_REF", "main"))
    ap.add_argument("--root", default="custom-addons")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--modules", nargs="*", default=None)
    ap.add_argument("--no-strict", action="store_true")
    args = ap.parse_args()

    if not Path(args.root).is_dir():
        print(f"[manifest-files] no addons root '{args.root}'; nothing to check")
        return 0

    mods = resolve_modules(args)
    if mods is None:
        return 0

    problems = [(mod, key, rel) for mod in mods for key, rel in module_problems(args.root, mod)]

    if not problems:
        if mods:
            print(f"[manifest-files] OK: data/demo references resolve in {len(mods)} "
                  f"module(s): {', '.join(mods)}")
        else:
            print("[manifest-files] OK: no changed modules to check")
        return 0

    print(f"[manifest-files] {len(problems)} manifest reference(s) point to a MISSING file:")
    for mod, key, rel in problems:
        print(f"  {mod}: {key} -> {rel}  ({args.root}/{mod}/{rel} not found)")
    print("[manifest-files] odoo -u <module> and odoo.sh fail to load a module whose")
    print("[manifest-files] __manifest__.py lists a file that does not exist. Add the file,")
    print("[manifest-files] fix the path, or remove the stale entry.")
    return 0 if args.no_strict else 1


if __name__ == "__main__":
    sys.exit(main())
