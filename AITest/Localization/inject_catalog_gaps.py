#!/usr/bin/env python3
"""
inject_catalog_gaps.py — add UI strings missing from Localizable.xcstrings.

Scans:
  - init-arg literals (text:/title:/note:/…)
  - enum `localizedLabel` case literals
  - String(localized: "key", defaultValue: "…") explicit keys

    python3 AITest/Localization/inject_catalog_gaps.py
    python3 AITest/Localization/catalog_gap_check.py
    python3 AITest/Localization/translate_catalog.py
"""

import argparse
import json
import os
import re
import glob

CATALOG = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Localizable.xcstrings")
)
LABEL_ARGS = ("text", "note", "title", "subtitle", "description", "action",
              "headline", "label", "message", "hint", "placeholder", "caption", "prompt")
ARG_RE = re.compile(r'\b(?:' + "|".join(LABEL_ARGS) + r'):\s*"((?:[^"\\]|\\.)*)"')
ENUM_LABEL_BLOCK = re.compile(
    r'var\s+localizedLabel:\s*LocalizedStringKey\s*\{([^}]+)\}', re.DOTALL)
CASE_LIT = re.compile(r'case\s+\.[\w]+:\s*"((?:[^"\\]|\\.)*)"')
LOCALIZED_CALL = re.compile(
    r'String\(\s*localized:\s*"((?:[^"\\]|\\.)*)"(?:\s*,\s*defaultValue:\s*"((?:[^"\\]|\\.)*)")?\s*\)'
)
L_HELPER_CALL = re.compile(
    r'\bL\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)'
)

SKIP_LITERALS = {"Sample description"}


def strip_previews(src: str) -> str:
    out = []
    depth = 0
    in_preview = False
    for line in src.splitlines(keepends=True):
        if not in_preview and re.search(r'#Preview\b', line):
            in_preview = True
            depth = line.count("{") - line.count("}")
            continue
        if in_preview:
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                in_preview = False
            continue
        out.append(line)
    return "".join(out)


def collect_from_sources(root: str, keys: set[str]) -> tuple[set[str], dict[str, str]]:
    """Returns (literal keys to add, explicit localized keys -> English default)."""
    literals: set[str] = set()
    explicit: dict[str, str] = {}

    for path in glob.glob(f"{root}/**/*.swift", recursive=True):
        if "/build/" in path:
            continue
        try:
            src = strip_previews(open(path, encoding="utf-8").read())
        except OSError:
            continue

        for lit in ARG_RE.findall(src):
            s = lit.strip()
            if s and re.search(r"[A-Za-z]", s) and "\\(" not in s and s not in SKIP_LITERALS:
                literals.add(s)

        for block in ENUM_LABEL_BLOCK.findall(src):
            for lit in CASE_LIT.findall(block):
                s = lit.strip()
                if s and re.search(r"[A-Za-z]", s):
                    literals.add(s)

        for key, default in LOCALIZED_CALL.findall(src):
            k = key.strip()
            if not k or not re.search(r"[A-Za-z]", k):
                continue
            if default:
                explicit[k] = default.strip()
            elif k not in keys:
                explicit[k] = k

        for key, default in L_HELPER_CALL.findall(src):
            k = key.strip()
            if not k or not re.search(r"[A-Za-z]", k):
                continue
            explicit[k] = default.strip() if default else k

    literals -= keys
    explicit = {k: v for k, v in explicit.items() if k not in keys}
    return literals, explicit


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="AITest")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)
    strings = catalog.setdefault("strings", {})
    keys = set(strings.keys())

    literals, explicit = collect_from_sources(args.root, keys)
    total = len(literals) + len(explicit)
    print(f"Missing init/enum literals: {len(literals)}")
    print(f"Missing String(localized:) keys: {len(explicit)}")
    if total == 0:
        print("Nothing to inject.")
        return

    for key in sorted(literals):
        strings.setdefault(key, {})

    for key, default in sorted(explicit.items()):
        entry = strings.setdefault(key, {})
        if default and default != key:
            entry.setdefault("localizations", {}).setdefault("en", {}).setdefault(
                "stringUnit", {"state": "translated", "value": default}
            )

    if args.dry_run:
        for s in sorted(literals)[:15]:
            print(f"  literal: {s!r}")
        for k, v in list(sorted(explicit.items()))[:15]:
            print(f"  key: {k!r} -> {v!r}")
        return

    with open(CATALOG, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
    print(f"Injected {total} entries into {CATALOG}")


if __name__ == "__main__":
    main()
