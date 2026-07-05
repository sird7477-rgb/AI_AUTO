#!/usr/bin/env python3
"""Registry-derived Odoo schema screen.

This is a cheap screen, not an installability judge. It checks changed addon
references against a warm-base catalog dumped from ``ir.model.fields``. Missing
catalog means NOT screened; only Odoo registry-load is the final oracle.
"""

from __future__ import annotations

import argparse
import ast
import glob
import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def run(args: list[str]) -> str:
    try:
        return subprocess.run(args, capture_output=True, text=True, check=False).stdout
    except Exception:
        return ""


_EMPTY_TREE = run(["git", "hash-object", "-t", "tree", os.devnull]).strip() \
    or "4b825dc642cb6eb9a060e54bf8d69288fbee4904"


def load_catalog(path: Path) -> tuple[dict, str | None]:
    try:
        catalog = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return {}, f"catalog unavailable, NOT screened: {path} ({exc})"
    if catalog.get("schema") != 1 or not isinstance(catalog.get("models"), dict):
        return {}, f"catalog unavailable, NOT screened: {path} (unsupported schema)"
    return catalog, None


def module_set_sha(root: Path) -> str:
    mods: list[str] = []
    for manifest in sorted(root.glob("*/__manifest__.py")):
        try:
            data = ast.literal_eval(manifest.read_text(encoding="utf-8"))
        except Exception:
            continue
        if data.get("installable", True):
            mods.append(manifest.parent.name)
    import hashlib

    return hashlib.sha256(",".join(mods).encode()).hexdigest()


def changed_modules(base: str, root: Path) -> list[str] | None:
    if run(["git", "rev-parse", "--is-inside-work-tree"]).strip() != "true":
        return None
    merge_base = run(["git", "merge-base", base, "HEAD"]).strip() or run(
        ["git", "rev-parse", "HEAD"]
    ).strip()
    files = run([
        "git",
        "--attr-source=" + _EMPTY_TREE,
        "-c",
        "core.fsmonitor=",
        "diff",
        "--name-only",
        merge_base,
        "--",
    ]).splitlines()
    files += run([
        "git",
        "-c",
        "core.fsmonitor=",
        "-c",
        "core.hooksPath=/dev/null",
        "ls-files",
        "--others",
        "--exclude-standard",
        "--",
    ]).splitlines()
    prefix = root.as_posix().rstrip("/") + "/"
    mods = {line[len(prefix):].split("/", 1)[0] for line in files if line.startswith(prefix)}
    return sorted(m for m in mods if (root / m / "__manifest__.py").is_file())


def class_models(node: ast.ClassDef) -> list[str]:
    models: list[str] = []
    for stmt in node.body:
        if not isinstance(stmt, ast.Assign):
            continue
        names = [t.id for t in stmt.targets if isinstance(t, ast.Name)]
        if not any(name in names for name in ("_inherit", "_name")):
            continue
        value = stmt.value
        if isinstance(value, ast.Constant) and isinstance(value.value, str):
            models.append(value.value)
        elif isinstance(value, (ast.List, ast.Tuple)):
            models.extend(
                elt.value
                for elt in value.elts
                if isinstance(elt, ast.Constant) and isinstance(elt.value, str)
            )
    return models


def field_call(stmt: ast.Assign) -> tuple[str, ast.Call] | None:
    if not isinstance(stmt.value, ast.Call):
        return None
    func = stmt.value.func
    if not (
        isinstance(func, ast.Attribute)
        and isinstance(func.value, ast.Name)
        and func.value.id == "fields"
    ):
        return None
    for target in stmt.targets:
        if isinstance(target, ast.Name):
            return target.id, stmt.value
    return None


def const_kw(call: ast.Call, name: str) -> str | None:
    for kw in call.keywords:
        if kw.arg == name and isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
            return kw.value.value
    return None


def validate_related(models: dict, start_model: str, chain: str) -> str | None:
    model = start_model
    parts = [p for p in chain.split(".") if p]
    for index, part in enumerate(parts):
        if model not in models:
            return f"Invalid model {model}"
        fields = models[model].get("fields", {})
        field = fields.get(part)
        if field is None:
            return f"Invalid field {model}.{part}"
        if index < len(parts) - 1:
            model = field.get("relation") or ""
            if not model:
                return f"Invalid related chain {chain}: {model or start_model}.{part} has no relation"
    return None


def scan_python(path: Path, addon: str, models: dict) -> tuple[list[str], list[str]]:
    invalid: list[str] = []
    advisory: list[str] = []
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"))
    except SyntaxError:
        return invalid, advisory
    except OSError:
        return invalid, advisory
    for node in ast.walk(tree):
        if not isinstance(node, ast.ClassDef):
            continue
        class_model_names = class_models(node)
        if not class_model_names:
            continue
        for stmt in node.body:
            if not isinstance(stmt, ast.Assign):
                continue
            fc = field_call(stmt)
            if fc is None:
                continue
            field_name, call = fc
            related = const_kw(call, "related")
            for model in class_model_names:
                if model not in models:
                    invalid.append(f"{path}:{stmt.lineno}: Invalid model {model}")
                    continue
                existing = models[model].get("fields", {}).get(field_name)
                if existing and addon not in set(existing.get("modules", [])):
                    owners = ",".join(existing.get("modules", [])) or "catalog"
                    advisory.append(
                        f"{path}:{stmt.lineno}: catalog collision advisory {model}.{field_name} already owned by {owners}"
                    )
                if related:
                    problem = validate_related(models, model, related)
                    if problem:
                        invalid.append(f"{path}:{stmt.lineno}: {problem} in related={related!r}")
    return invalid, advisory


def xml_view_models(path: Path) -> tuple[list[tuple[str, str, int]], list[str]]:
    refs: list[tuple[str, str, int]] = []
    invalid_models: list[str] = []
    try:
        tree = ET.parse(path)
    except ET.ParseError:
        return refs, invalid_models
    except OSError:
        return refs, invalid_models
    root = tree.getroot()
    for record in root.iter("record"):
        if record.attrib.get("model") != "ir.ui.view":
            continue
        model_name = None
        arch = None
        for child in list(record):
            if child.tag != "field":
                continue
            if child.attrib.get("name") == "model":
                model_name = (child.text or "").strip()
            elif child.attrib.get("name") == "arch":
                arch = child
        if not model_name:
            invalid_models.append(f"{path}: Invalid model <missing ir.ui.view model>")
            continue
        if arch is None:
            continue
        for arch_child in list(arch):
            for field in arch_child.iter("field"):
                name = field.attrib.get("name")
                if name:
                    refs.append((model_name, name, getattr(field, "sourceline", 0) or 0))
    return refs, invalid_models


def scan_xml(path: Path, models: dict) -> list[str]:
    invalid: list[str] = []
    refs, model_errors = xml_view_models(path)
    invalid.extend(model_errors)
    for model, field, line in refs:
        if model not in models:
            invalid.append(f"{path}:{line}: Invalid model {model}")
        elif field not in models[model].get("fields", {}):
            invalid.append(f"{path}:{line}: Invalid field {model}.{field}")
    return invalid


def resolve_modules(args: argparse.Namespace, root: Path) -> list[str] | None:
    if args.modules:
        return [m for m in args.modules if (root / m / "__manifest__.py").is_file()]
    if args.all:
        return sorted(p.parent.name for p in root.glob("*/__manifest__.py"))
    return changed_modules(args.base, root)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", default=os.environ.get("ODOO_SCHEMA_CATALOG", ""))
    parser.add_argument("--root", default="custom-addons")
    parser.add_argument("--base", default=os.environ.get("CHECK_SCHEMA_BASE_REF", "main"))
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--modules", nargs="*", default=None)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    root = Path(args.root)
    if not root.is_dir():
        print(f"[schema-catalog] no addons root '{root}'; nothing to check")
        return 0
    catalog_path = Path(args.catalog) if args.catalog else Path(".odoo-schema-catalog.json")
    catalog, unavailable = load_catalog(catalog_path)
    if unavailable:
        print(f"[schema-catalog] {unavailable}")
        return 1 if args.strict else 0
    stamped_sha = catalog.get("module_set_sha")
    if stamped_sha and stamped_sha != module_set_sha(root):
        print("[schema-catalog] catalog unavailable, NOT screened: module_set_sha drift")
        return 1 if args.strict else 0

    modules = resolve_modules(args, root)
    if modules is None:
        print("[schema-catalog] not a git work tree; pass --all or --modules")
        return 0
    models = catalog["models"]
    invalid: list[str] = []
    advisory: list[str] = []
    for mod in modules:
        moddir = root / mod
        for py in sorted(moddir.rglob("*.py")):
            bad, notes = scan_python(py, mod, models)
            invalid.extend(bad)
            advisory.extend(notes)
        for xml in sorted(glob.glob(str(moddir / "**" / "*.xml"), recursive=True)):
            invalid.extend(scan_xml(Path(xml), models))

    for note in advisory:
        print(f"[schema-catalog] {note}")
    if invalid:
        print(f"[schema-catalog] {len(invalid)} invalid schema reference(s):")
        for problem in invalid:
            print(f"[schema-catalog] {problem}")
        print("[schema-catalog] registry-load remains the oracle; fix or confirm with Odoo before push.")
        return 1 if args.strict else 0
    print(f"[schema-catalog] OK: screened {len(modules)} module(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
