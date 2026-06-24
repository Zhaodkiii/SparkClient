#!/usr/bin/env python3
"""Migrate String(format: L10n.text(...)) to L10n.format(...)."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "SparkClient"

LOCALE_SUFFIX = re.compile(r",\s*locale:\s*(?:Locale\.current|\.current)")


def find_matching_paren(text: str, open_index: int) -> int:
    """Return index of closing paren matching `(` at open_index."""
    depth = 0
    i = open_index
    in_string = False
    escape = False
    while i < len(text):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            i += 1
            continue

        if ch == '"':
            in_string = True
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError(f"Unmatched paren at {open_index}")


def extract_l10n_text_args(l10n_call: str) -> str:
    """L10n.text("k", fallback: "f") -> '"k", fallback: "f"'"""
    assert l10n_call.startswith("L10n.text(") and l10n_call.endswith(")")
    return l10n_call[len("L10n.text(") : -1]


def convert_content(content: str) -> tuple[str, int]:
    prefix = "String(format: "
    count = 0
    out: list[str] = []
    i = 0

    while True:
        idx = content.find(prefix, i)
        if idx == -1:
            out.append(content[i:])
            break

        out.append(content[i:idx])

        # Must be String(format: L10n.text(
        l10n_start = idx + len(prefix)
        if not content[l10n_start:].startswith("L10n.text("):
            out.append(prefix)
            i = idx + len(prefix)
            continue

        l10n_open = l10n_start + len("L10n.text")  # points to '('
        l10n_close = find_matching_paren(content, l10n_open)
        l10n_call = content[l10n_start : l10n_close + 1]

        tail_start = l10n_close + 1
        tail = content[tail_start:]
        locale_match = LOCALE_SUFFIX.match(tail)
        if locale_match:
            tail = tail[locale_match.end() :]

        args = ""
        if tail.startswith(","):
            args = tail[1:].lstrip()
            # args end at closing paren of String(format: ...)
            string_open = content.index("(", idx)  # String(
            string_close = find_matching_paren(content, string_open)
            args = content[tail_start + 1 + (len(content[tail_start + 1 :]) - len(tail[1:].lstrip())) : string_close].strip()
            if args.startswith(","):
                args = args[1:].strip()

            out.append(f"L10n.format({extract_l10n_text_args(l10n_call)}")
            if args:
                out.append(f", {args}")
            out.append(")")
            count += 1
            i = string_close + 1
        else:
            # String(format: L10n.text("key")) with no extra args
            if tail.startswith(")"):
                out.append(f"L10n.format({extract_l10n_text_args(l10n_call)})")
                count += 1
                i = tail_start + 1
            else:
                out.append(prefix)
                i = idx + len(prefix)

    return "".join(out), count


def main() -> None:
    total = 0
    files_changed = 0
    for path in sorted(SRC.rglob("*.swift")):
        original = path.read_text(encoding="utf-8")
        if "String(format: L10n.text(" not in original:
            continue
        converted, n = convert_content(original)
        if n and converted != original:
            path.write_text(converted, encoding="utf-8")
            files_changed += 1
            total += n
            print(f"{n:3d}  {path.relative_to(ROOT)}")

    print(f"\nConverted {total} occurrences in {files_changed} files")


if __name__ == "__main__":
    main()
