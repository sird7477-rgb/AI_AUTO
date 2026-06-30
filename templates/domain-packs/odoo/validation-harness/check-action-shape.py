#!/usr/bin/env python3
"""Screen Odoo act_window action dicts that can crash the web client.

Failure mode (Odoo 19): a method returns an `ir.actions.act_window` dict that is
dispatched to the client as a RAW object (e.g. a JS field widget doing
`this.action.doAction(await orm.call(...))`). If the dict has `target: 'new'`
(popup) but no `views` key, the client's `_preprocessAction` runs
`action.views.map(...)` on `undefined` -> `TypeError: Cannot read properties of
undefined (reading 'map')`. `view_mode` alone does NOT save this raw-dispatch
path.

This is a SCREEN, not a judge. The same dict shape is safe in many places
(dispatched via a button / server round-trip that normalizes views from
view_mode), so a hard "missing views" rule false-positives heavily. We therefore:
  - only flag the crash signature: act_window + target:'new' + no `views`,
  - scope to CHANGED lines (diff vs base) so only new/edited actions surface,
  - exit 0 (advisory) by default — the flagged list is handed to a reviewer/AI
    to confirm via a local popup smoke (console-error-0), never auto-passed.

Usage:
  check-action-shape.py [--base REF] [--root DIR] [--all] [--strict]
    --base REF   integration ref for the diff (default env CHECK_ACTION_BASE_REF or 'main')
    --root DIR   addons root to scan (default 'custom-addons')
    --all        scan every *.py under root (full backlog audit; ignores diff)
    --strict     exit 1 if anything is flagged (for a blocking gate)
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


# Empty-tree OID (in the repo's hash algo) fed to `git --attr-source=` so the project's
# in-repo `.gitattributes` is IGNORED during the diff below: an attacker's attribute-driven
# clean/smudge/textconv/diff driver therefore cannot exec. `--no-ext-diff`/`--no-textconv`
# additionally close the `.git/config` `diff.external` / textconv vectors. NOTE: a bare
# `git diff <base> -- <path>` is worktree-vs-tree and DOES run the clean filter even WITH
# `--no-ext-diff --no-textconv` (verified); `--attr-source=<empty-tree>` is what neutralizes it.
_EMPTY_TREE = run(["git", "hash-object", "-t", "tree", os.devnull]).strip() \
    or "4b825dc642cb6eb9a060e54bf8d69288fbee4904"


def act_window_dicts(path):
    """Yield (lineno, end_lineno, res_model) for risky act_window dicts in a file."""
    try:
        tree = ast.parse(Path(path).read_text(encoding="utf-8"))
    except (OSError, SyntaxError):
        return
    for node in ast.walk(tree):
        if not isinstance(node, ast.Dict):
            continue
        d = {}
        for k, v in zip(node.keys, node.values):
            if isinstance(k, ast.Constant) and isinstance(k.value, str):
                d[k.value] = v

        def const(key):
            v = d.get(key)
            return v.value if isinstance(v, ast.Constant) else None

        if const("type") != "ir.actions.act_window":
            continue
        if const("target") != "new":
            continue
        if "views" in d:
            continue
        yield (node.lineno, getattr(node, "end_lineno", node.lineno), const("res_model"))


def changed_files(base, root):
    files = set()
    # --attr-source even here: git runs the in-repo clean filter to decide whether a worktree
    # file changed, so a `--name-only` worktree diff is ALSO a clean-filter RCE vector.
    out = run(["git", "--attr-source=" + _EMPTY_TREE, "diff", "--name-only", base, "--", "*.py"])
    files.update(line for line in out.splitlines() if line.endswith(".py"))
    out = run(["git", "ls-files", "--others", "--exclude-standard", "--", "*.py"])
    files.update(line for line in out.splitlines() if line.endswith(".py"))
    root = root.rstrip("/") + "/"
    return sorted(f for f in files if f.startswith(root) and Path(f).is_file())


def added_lines(base, path, untracked):
    """Set of NEW-file line numbers that are added/changed for this file."""
    if untracked:
        try:
            n = len(Path(path).read_text(encoding="utf-8").splitlines())
        except OSError:
            return set()
        return set(range(1, n + 1))
    out = run(["git", "--attr-source=" + _EMPTY_TREE, "diff", "--no-ext-diff", "--no-textconv", "-U0", base, "--", path])
    lines = set()
    for line in out.splitlines():
        if line.startswith("@@"):
            # @@ -a,b +c,d @@
            try:
                plus = line.split("+", 1)[1].split(" ", 1)[0]
                start, _, count = plus.partition(",")
                start = int(start)
                count = int(count) if count else 1
                lines.update(range(start, start + max(count, 1)))
            except (ValueError, IndexError):
                continue
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=os.environ.get("CHECK_ACTION_BASE_REF", "main"))
    ap.add_argument("--root", default="custom-addons")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()

    if not Path(args.root).is_dir():
        print(f"[action-shape] no addons root '{args.root}'; nothing to check")
        return 0

    flags = []
    if args.all:
        for path in sorted(str(p) for p in Path(args.root).rglob("*.py")):
            for lineno, end, model in act_window_dicts(path):
                flags.append((path, lineno, model))
    else:
        in_git = run(["git", "rev-parse", "--is-inside-work-tree"]).strip() == "true"
        if not in_git:
            print("[action-shape] not a git work tree; use --all for a full scan")
            return 0
        base = run(["git", "merge-base", args.base, "HEAD"]).strip() or run(
            ["git", "rev-parse", "HEAD"]
        ).strip()
        tracked = set(run(["git", "ls-files", "--", "*.py"]).splitlines())
        for path in changed_files(base, args.root):
            added = added_lines(base, path, untracked=path not in tracked)
            for lineno, end, model in act_window_dicts(path):
                if added and not (added & set(range(lineno, end + 1))):
                    continue
                flags.append((path, lineno, model))

    if not flags:
        print("[action-shape] OK: no changed act_window popup actions missing 'views'")
        return 0

    print(f"[action-shape] {len(flags)} act_window popup action(s) to CONFIRM "
          "(target:'new' + no 'views'):")
    for path, lineno, model in flags:
        print(f"  {path}:{lineno}  res_model={model or '?'}")
    print("[action-shape] Odoo 19 raw doAction(dict) needs 'views' or the client "
          "crashes (undefined.map in _preprocessAction).")
    print("[action-shape] CONFIRM each by opening the popup on local serve and "
          "checking console-error=0; do NOT pass on inspection alone.")
    print("[action-shape] safe if dispatched via a normalizing path (button/server); "
          "add 'views': [(False, 'form')] if reached by a raw JS doAction.")
    return 1 if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
