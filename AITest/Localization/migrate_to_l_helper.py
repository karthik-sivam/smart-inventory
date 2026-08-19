#!/usr/bin/env python3
"""Replace String(localized:...) with L(...) for S39 live language switch."""
import re
import glob
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
SKIP = {"build", "Localization/inject_catalog_gaps.py", "Localization/localization_audit.py"}

PATTERN = re.compile(
    r'String\(\s*localized:\s*"((?:[^"\\]|\\.)*)"(?:\s*,\s*defaultValue:\s*"((?:[^"\\]|\\.)*)")?\s*\)',
    re.DOTALL,
)


def should_skip(path: str) -> bool:
    for part in SKIP:
        if part in path:
            return True
    return False


def convert(content: str) -> tuple[str, int]:
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        count += 1
        key = m.group(1)
        default = m.group(2) if m.group(2) is not None else key
        return f'L("{key}", "{default}")'

    return PATTERN.sub(repl, content), count


def main():
    total = 0
    files_changed = 0
    for path in glob.glob(f"{ROOT}/**/*.swift", recursive=True):
        if should_skip(path):
            continue
        with open(path, encoding="utf-8") as f:
            original = f.read()
        updated, n = convert(original)
        if n:
            with open(path, "w", encoding="utf-8") as f:
                f.write(updated)
            files_changed += 1
            total += n
            print(f"  {n:3d}  {os.path.relpath(path, ROOT)}")
    print(f"Converted {total} call sites in {files_changed} files.")


if __name__ == "__main__":
    main()
