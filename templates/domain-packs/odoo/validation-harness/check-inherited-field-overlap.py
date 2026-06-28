#!/usr/bin/env python3
"""Advisory screen: two or more CHANGED addons add/override the SAME field name
on the SAME inherited Odoo model.

Failure mode (odoo.sh build 2026-06-15, queue `odoo:post-install-gap-field-
semantic-collision`): a generic field name (e.g. `jw_billing_type_code`) was
defined by two independent addons on the same inherited model (`account.move`).
Warm registry-load stays GREEN — the modules install and the registry loads —
because the conflict is BEHAVIORAL (which addon's compute/related/store wins),
surfaced only by post-install tests. The cheap warm tier cannot see it.

This is a SCREEN, not a judge, and deliberately NOT a duplicate-field lint
(forbidden by ../commit-tier/README.md Article 1.1; it false-positives on legal
inherited overrides). The single-addon override — one addon extending another's
field — is normal and is NEVER flagged here: the signature is two or more
DISTINCT changed addons writing the SAME (inherited model, field name) pair.
That pair is rare and high-precision, unlike "any field on a shared mixin"
(res.partner / mail.thread are extended everywhere) which would be pure noise.

It only narrows attention; it never decides validity and never blocks:
  - scope to CHANGED field assignments (diff vs base) so only new/edited fields
    surface,
  - flag a (inherited_model, field_name) pair only when >= 2 changed addons
    write it,
  - exit 0 (advisory) by default — the flagged pairs are handed to validate-full
    (post-install test tier), the real oracle, before push/PR.

Usage:
  check-inherited-field-overlap.py [--base REF] [--root DIR] [--all] [--strict]
    --base REF   integration ref for the diff (default env CHECK_INHERIT_BASE_REF or 'main')
    --root DIR   addons root to scan (default 'custom-addons')
    --all        scan every *.py under root (full backlog audit; ignores diff)
    --strict     exit 1 if anything is flagged (opt-in; default is advisory rc 0)
"""
import argparse
import ast
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path


def run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, check=False).stdout
    except Exception:
        return ""


def _inherit_targets(class_node):
    """Literal _inherit model name(s) for a class, or [] when none/dynamic."""
    targets = []
    for stmt in class_node.body:
        if not isinstance(stmt, ast.Assign):
            continue
        names = [t.id for t in stmt.targets if isinstance(t, ast.Name)]
        if "_inherit" not in names:
            continue
        v = stmt.value
        if isinstance(v, ast.Constant) and isinstance(v.value, str):
            targets.append(v.value)
        elif isinstance(v, (ast.List, ast.Tuple)):
            for elt in v.elts:
                if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                    targets.append(elt.value)
    return targets


def _field_assignments(class_node):
    """Yield (field_name, lineno) for `name = fields.X(...)` in a class body."""
    for stmt in class_node.body:
        if not isinstance(stmt, ast.Assign) or not isinstance(stmt.value, ast.Call):
            continue
        func = stmt.value.func
        if not (isinstance(func, ast.Attribute)
                and isinstance(func.value, ast.Name)
                and func.value.id == "fields"):
            continue
        for tgt in stmt.targets:
            if isinstance(tgt, ast.Name):
                yield (tgt.id, stmt.lineno)


def inherited_fields(path):
    """Yield (inherit_model, field_name, lineno) for fields defined on an
    inherited model in this file."""
    try:
        tree = ast.parse(Path(path).read_text(encoding="utf-8"))
    except (OSError, SyntaxError):
        return
    for node in ast.walk(tree):
        if not isinstance(node, ast.ClassDef):
            continue
        targets = _inherit_targets(node)
        if not targets:
            continue
        for field_name, lineno in _field_assignments(node):
            for model in targets:
                yield (model, field_name, lineno)


def addon_of(path, root):
    """First path component under root, e.g. custom-addons/<addon>/..."""
    rel = path[len(root.rstrip("/")) + 1:] if path.startswith(root.rstrip("/")) else path
    parts = rel.split("/")
    return parts[0] if parts and parts[0] else path


def changed_files(base, root):
    files = set()
    out = run(["git", "diff", "--name-only", base, "--", "*.py"])
    files.update(line for line in out.splitlines() if line.endswith(".py"))
    out = run(["git", "ls-files", "--others", "--exclude-standard", "--", "*.py"])
    files.update(line for line in out.splitlines() if line.endswith(".py"))
    root = root.rstrip("/") + "/"
    return sorted(f for f in files if f.startswith(root) and Path(f).is_file())


def added_lines(base, path, untracked):
    if untracked:
        try:
            n = len(Path(path).read_text(encoding="utf-8").splitlines())
        except OSError:
            return set()
        return set(range(1, n + 1))
    out = run(["git", "diff", "-U0", base, "--", path])
    lines = set()
    for line in out.splitlines():
        if line.startswith("@@"):
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
    ap.add_argument("--base", default=os.environ.get("CHECK_INHERIT_BASE_REF", "main"))
    ap.add_argument("--root", default="custom-addons")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()

    if not Path(args.root).is_dir():
        print(f"[inherit-overlap] no addons root '{args.root}'; nothing to check")
        return 0

    # (model, field) -> {addon: first_lineno}
    pairs = defaultdict(dict)

    if args.all:
        scan = sorted(str(p) for p in Path(args.root).rglob("*.py"))
        for path in scan:
            addon = addon_of(path, args.root)
            for model, field, lineno in inherited_fields(path):
                pairs[(model, field)].setdefault(addon, lineno)
    else:
        in_git = run(["git", "rev-parse", "--is-inside-work-tree"]).strip() == "true"
        if not in_git:
            print("[inherit-overlap] not a git work tree; use --all for a full scan")
            return 0
        base = run(["git", "merge-base", args.base, "HEAD"]).strip() or run(
            ["git", "rev-parse", "HEAD"]
        ).strip()
        tracked = set(run(["git", "ls-files", "--", "*.py"]).splitlines())
        for path in changed_files(base, args.root):
            untracked = path not in tracked
            added = added_lines(base, path, untracked=untracked)
            # A tracked file with NO added lines (deletion-only / mode-only change)
            # introduces no new field assignment. Skip it so an unrelated deletion
            # never makes a pre-existing field pair count as newly relevant — that
            # would break the diff-scoped, high-precision contract. Untracked files
            # are wholly new, so their added set is the whole file.
            if not untracked and not added:
                continue
            addon = addon_of(path, args.root)
            for model, field, lineno in inherited_fields(path):
                if added and lineno not in added:
                    continue
                pairs[(model, field)].setdefault(addon, lineno)

    flagged = {mf: addons for mf, addons in pairs.items() if len(addons) >= 2}
    if not flagged:
        print("[inherit-overlap] OK: no inherited-model field name written by 2+ changed addons")
        return 0

    print(f"[inherit-overlap] {len(flagged)} inherited-model field name(s) written by "
          f"2+ changed addons — coordination risk (advisory, NOT a collision verdict):")
    for (model, field), addons in sorted(flagged.items()):
        who = ", ".join(sorted(addons))
        print(f"  - {model}.{field}: {who}")
    print("[inherit-overlap] warm registry-load does NOT exercise the behavioral "
          "interaction (compute/related/store/override order).")
    print("[inherit-overlap] run validate-full.sh (post-install test tier) before "
          "push/PR; it is the oracle, not this screen.")
    return 1 if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
