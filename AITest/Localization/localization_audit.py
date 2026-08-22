#!/usr/bin/env python3
"""
localization_audit.py  —  find UI text that will NOT localize.

SwiftUI only auto-localizes STRING LITERALS: Text("Revenue").
Text(someVariable) and Text("...\\(interpolation)...") do NOT localize, even if
the underlying string is in the String Catalog. This script lists those cases so
the S18 sweep can be verified complete.

It filters out property names that clearly hold USER DATA (item/storage names,
categories, symbols, prices) which must STAY untranslated. Whatever remains is a
candidate UI label that should be localized (LocalizedStringKey / String(localized:)).

Usage:
  python3 AITest/Localization/localization_audit.py            # summary + per-file
  python3 AITest/Localization/localization_audit.py --all      # list every hit
Goal for S18: the "LIKELY UI LABELS" list is empty (only data vars remain).
"""

import argparse
import glob
import os
import re

# Variable expressions that hold DATA (leave untranslated). Matched as a suffix.
DATA_SUFFIXES = (
    ".name", ".location", ".symbol", ".displayname", ".displayprice",
    ".category", ".uomname", ".uomsymbol", ".sku", ".barcode", ".price",
    ".email", ".displaydescription",
    ".smartformatted", ".stockstatus", ".relativeformatted", ".formatteddisplay",
    ".capitalized", ".itemname", ".actorname", ".occurredat",
    ".englishname", ".nativename",
)
DATA_EXACT = {
    "name", "cat", "category", "uomsymbol", "storagename", "itemname",
    "sku", "barcode", "pdffilename", "filename", "newvalue", "value",
    "displayname", "err", "query", "transcript", "msg", "number",
    "expression", "formatteddisplay", "analyzeprogress",
}
# Properties that return String(localized:) / LocalizedStringKey at source — Text(var) is OK.
LOCALIZED_AT_SOURCE = (
    "localizedtitle", "localizedtitlestring", "paywallheadline", "paywallsubtitle",
    "pricehint", "previewtitle", "daystext", "editstockstatuslabel", "statusdescription",
    "negativestockalertmessage", "primarybuttonlabel", "emptyfiltertitle", "emptyfiltersubtitle",
    "unresolvedbannertext", "validationerror", "usagetext", "freestorageusagetext",
    "errormessage", "alertmessage", "successmessage", "storagedescription",
    "pricesectiontitle", "localizedtitle", "insight.subtitle", "label",  # health label etc.
    "syncstate.description", "batchitem.notes", "count.adjustmentreason",
)
LABEL_HINTS = {"title", "subtitle", "text", "message", "description", "note",
               "headline", "hint", "label", "placeholder", "caption", "prompt"}

var_pat = re.compile(r'\bText\(\s*([A-Za-z_][A-Za-z0-9_.?!]*)\s*\)')
interp_pat = re.compile(r'\bText\(\s*("(?:[^"\\]|\\.)*\\\((?:[^()]|\([^()]*\))*\)(?:[^"\\]|\\.)*")\s*\)')


def is_data(expr: str) -> bool:
    low = expr.lower().rstrip("?!")
    if low in DATA_EXACT:
        return True
    if low.startswith("announcement."):
        return True
    if low.startswith("currency."):
        return True
    if low.startswith("event.itemname") or low.startswith("sale.itemname"):
        return True
    return any(low.endswith(sfx) for sfx in DATA_SUFFIXES)


def localized_at_source(expr: str) -> bool:
    low = expr.lower().rstrip("?!")
    return any(h in low for h in LOCALIZED_AT_SOURCE)


def looks_like_label(expr: str) -> bool:
    low = expr.lower()
    return any(h in low for h in LABEL_HINTS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="print every occurrence")
    ap.add_argument("--root", default="AITest")
    args = ap.parse_args()

    labels, data, interp = [], [], []
    for path in glob.glob(f"{args.root}/**/*.swift", recursive=True):
        if "/build/" in path:
            continue
        try:
            src = open(path, encoding="utf-8").read()
        except Exception:
            continue
        fname = os.path.relpath(path)
        for expr in var_pat.findall(src):
            entry = (fname, expr)
            if is_data(expr) or localized_at_source(expr):
                data.append(entry)
            else:
                labels.append(entry)
        for lit in interp_pat.findall(src):
            interp.append((fname, lit[:60]))

    print(f"Text(variable) total: {len(labels)+len(data)}  |  "
          f"likely LABELS: {len(labels)}  data(ok): {len(data)}  |  "
          f"Text(interpolation): {len(interp)}\n")

    print("=== LIKELY UI LABELS (localize these) ===")
    by_file = {}
    for f, e in labels:
        by_file.setdefault(f, []).append(e)
    for f, es in sorted(by_file.items(), key=lambda x: -len(x[1])):
        flag = "  <-- has label-ish names" if any(looks_like_label(e) for e in es) else ""
        print(f"  {f}: {len(es)}{flag}")
        if args.all:
            print("      " + ", ".join(sorted(set(es))))

    print(f"\n=== INTERPOLATED Text (localize with String(localized:) + format args): {len(interp)} ===")
    if args.all:
        for f, lit in interp:
            print(f"  {f}: {lit}")

    print("\nS18 done when LIKELY UI LABELS shows only genuine data vars "
          "(review the --all list to confirm none are user-facing labels).")


if __name__ == "__main__":
    main()
