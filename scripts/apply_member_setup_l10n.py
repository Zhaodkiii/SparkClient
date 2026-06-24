#!/usr/bin/env python3
"""Apply member_setup_l10n_map.json to Localizable.strings and Swift UI contexts safely."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "scripts/member_setup_l10n_map.json"
SETUP_ROOT = ROOT / "SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup"
ZH_STRINGS = ROOT / "SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings"
EN_STRINGS = ROOT / "SparkClient/Projects/App/Resources/en.lproj/Localizable.strings"

KEY_LINE = re.compile(r'^"([^"]+)"\s*=')
UNSAFE_LINE = re.compile(r"==|!=|contains\(|removeAll|append\(|rawValue|\.value\s*=|value:\s*\"")

LABEL_PREFIX = r"(?<![A-Za-z_])"


def load_existing_keys(path: Path) -> set[str]:
    keys: set[str] = set()
    if not path.exists():
        return keys
    for line in path.read_text(encoding="utf-8").splitlines():
        m = KEY_LINE.match(line.strip())
        if m:
            keys.add(m.group(1))
    return keys


def append_strings(path: Path, entries: list[tuple[str, str]], marker: str) -> int:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        start = text.index(marker)
        text = text[:start].rstrip() + "\n"

    block_lines = [f"\n{marker}\n"]
    for key, value in entries:
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        block_lines.append(f'"{key}" = "{escaped}";')
    block_lines.append("")
    path.write_text(text + "\n".join(block_lines), encoding="utf-8")
    return len(entries)


def is_comment_line(line: str) -> bool:
    return line.lstrip().startswith("//")


def swift_literal(zh: str) -> str:
    return json.dumps(zh, ensure_ascii=False)


def replace_once(line: str, old: str, new: str) -> tuple[str, int]:
    if old not in line:
        return line, 0
    return line.replace(old, new, 1), 1


def replace_in_line(line: str, zh: str, key: str) -> tuple[str, int]:
    if is_comment_line(line) or "L10n.text(" in line:
        return line, 0
    if UNSAFE_LINE.search(line):
        # Allow ternary display fallback on otherwise unsafe lines.
        if not re.search(rf"\?\s*{re.escape(swift_literal(zh))}\s*:", line):
            return line, 0

    lit = swift_literal(zh)
    replacement = f'L10n.text("{key}")'
    count = 0

    patterns = [
        (rf"Text\({re.escape(lit)}\)", f"Text({replacement})"),
        (rf"{LABEL_PREFIX}title:\s*{re.escape(lit)}", f"title: {replacement}"),
        (rf"{LABEL_PREFIX}subtitle:\s*{re.escape(lit)}", f"subtitle: {replacement}"),
        (rf"{LABEL_PREFIX}placeholder:\s*{re.escape(lit)}", f"placeholder: {replacement}"),
        (rf"{LABEL_PREFIX}emptyHint:\s*{re.escape(lit)}", f"emptyHint: {replacement}"),
        (rf"{LABEL_PREFIX}primaryTitle:\s*{re.escape(lit)}", f"primaryTitle: {replacement}"),
        (rf"{LABEL_PREFIX}secondaryTitle:\s*{re.escape(lit)}", f"secondaryTitle: {replacement}"),
        (rf"Button\({re.escape(lit)}\)", f"Button({replacement})"),
        (rf"prompt:\s*Text\({re.escape(lit)}\)", f"prompt: Text({replacement})"),
        (rf"navigationTitle\({re.escape(lit)}\)", f"navigationTitle({replacement})"),
        (rf"Label\({re.escape(lit)},", f"Label({replacement},"),
        (rf"MemberSetupSection\({re.escape(lit)}\)", f"MemberSetupSection(title: {replacement})"),
        (rf"MemberSetupAccentAddButton\({re.escape(lit)}\)", f"MemberSetupAccentAddButton(title: {replacement})"),
        (rf"questionCard\({re.escape(lit)}\)", f"questionCard(title: {replacement})"),
        (rf"return\s+{re.escape(lit)}\s*;?", f"return {replacement};"),
        (rf"\?\s*{re.escape(lit)}\s*:", f"? {replacement} :"),
    ]

    for pattern, repl in patterns:
        regex = re.compile(pattern)
        line, n = regex.subn(repl, line, count=1)
        count += n
        if n:
            break

    return line, count


def replace_interpolated(content: str, zh_template: str, key: str) -> tuple[str, int]:
    if "%" not in zh_template:
        return content, 0

    parts = re.split(r"%[@df]", zh_template)
    if len(parts) < 2:
        return content, 0

    swift_pattern = re.escape(parts[0])
    for part in parts[1:]:
        swift_pattern += r"\\([^)]*\\)" + re.escape(part)

    regex = re.compile(rf'Text\("{swift_pattern}"\)')
    count = 0

    def repl(match: re.Match[str]) -> str:
        nonlocal count
        full = match.group(0)
        vars_found = re.findall(r"\\\(([^)]*)\)", full)
        count += 1
        args = ", ".join(vars_found)
        return f'Text(L10n.format("{key}", {args}))'

    return regex.sub(repl, content), count


def main() -> None:
    data = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    entries = data["entries"]

    existing_zh = load_existing_keys(ZH_STRINGS)
    existing_en = load_existing_keys(EN_STRINGS)

    zh_to_add: list[tuple[str, str]] = []
    en_to_add: list[tuple[str, str]] = []
    seen_keys: set[str] = set()

    for entry in entries:
        key = entry["key"]
        if key in seen_keys:
            continue
        seen_keys.add(key)
        if key not in existing_zh:
            zh_to_add.append((key, entry["zh"]))
        if key not in existing_en:
            en_to_add.append((key, entry["en"]))

    marker = "// MARK: - Member Setup (auto-generated)"
    added_zh = append_strings(ZH_STRINGS, sorted(zh_to_add), marker) if zh_to_add else 0
    added_en = append_strings(EN_STRINGS, sorted(en_to_add), marker) if en_to_add else 0

    replacements = sorted(
        [(e["zh"], e["key"]) for e in entries],
        key=lambda item: len(item[0]),
        reverse=True,
    )

    total_replacements = 0
    touched_files: dict[str, int] = {}

    for swift_path in sorted(SETUP_ROOT.rglob("*.swift")):
        content = swift_path.read_text(encoding="utf-8")
        original = content
        file_count = 0

        for zh, key in replacements:
            content, n = replace_interpolated(content, zh, key)
            file_count += n

        lines = content.splitlines(keepends=True)
        new_lines: list[str] = []
        for line in lines:
            new_line = line
            for zh, key in replacements:
                if zh in new_line:
                    updated, n = replace_in_line(new_line, zh, key)
                    if n:
                        new_line = updated
                        file_count += n
                        break
            new_lines.append(new_line)
        content = "".join(new_lines)

        if content != original:
            swift_path.write_text(content, encoding="utf-8")
            rel = str(swift_path.relative_to(SETUP_ROOT))
            touched_files[rel] = file_count
            total_replacements += file_count

    print(f"Added {added_zh} zh keys, {added_en} en keys")
    print(f"Replacements in {len(touched_files)} files, ~{total_replacements} occurrences")
    for rel, n in sorted(touched_files.items(), key=lambda x: -x[1])[:25]:
        print(f"  {n:4d}  {rel}")


if __name__ == "__main__":
    main()
