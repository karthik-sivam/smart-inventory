#!/usr/bin/env python3
"""
catalog_gap_check.py  —  the definitive "will this actually translate?" gate.

The subtle bug S18 missed: a UI string literal passed to a CUSTOM view initializer
(e.g. PaywallFeatureRow(text: "Unlimited storage areas")) is NOT reliably extracted
into Localizable.xcstrings by Xcode, even when the parameter is LocalizedStringKey.
So the string renders as its English key on every device — looks "not translated".

This scans for string literals passed to UI-label init arguments and reports the
ones that are NOT present as keys in the catalog. Those are the real gaps.

Gate for S19: this must print 0 missing.

Usage:
  python3 AITest/Localization/catalog_gap_check.py
  python3 AITest/Localization/catalog_gap_check.py --all
"""

import argparse, json, os, re, glob

CATALOG = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Localizable.xcstrings"))
# init-argument names that carry user-facing UI text
LABEL_ARGS = ("text", "note", "title", "subtitle", "description", "action",
              "headline", "label", "message", "hint", "placeholder", "caption", "prompt")
ARG_RE = re.compile(r'\b(?:' + "|".join(LABEL_ARGS) + r'):\s*"((?:[^"\\]|\\.)*)"')

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

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--root", default="AITest")
    args = ap.parse_args()
    keys = set(json.load(open(CATALOG, encoding="utf-8"))["strings"].keys())

    missing = {}
    seen = set()
    for path in glob.glob(f"{args.root}/**/*.swift", recursive=True):
        if "/build/" in path:
            continue
        try:
            src = strip_previews(open(path, encoding="utf-8").read())
        except Exception:
            continue
        for lit in ARG_RE.findall(src):
            s = lit.strip()
            if not s or not re.search(r"[A-Za-z]", s) or "\\(" in s:
                continue  # skip empty, non-letter, or interpolated
            if s in SKIP_LITERALS:
                continue
            if s in seen:
                continue
            seen.add(s)
            if s not in keys:
                missing.setdefault(os.path.relpath(path), []).append(s)

    total = sum(len(v) for v in missing.values())
    print(f"UI-label literals passed to init params but MISSING from catalog: {total}")
    if total == 0:
        print("GATE PASS — every UI-label init literal is in the catalog.")
        return
    for f, v in sorted(missing.items(), key=lambda x: -len(x[1])):
        print(f"  {f}: {len(v)}")
        if args.all:
            for s in v:
                print(f"      {s!r}")

if __name__ == "__main__":
    main()
