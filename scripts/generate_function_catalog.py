#!/usr/bin/env python3
"""Generate docs/function_catalog.jsonl: one JSON object per registered fin_* function.

The catalog is the machine-readable twin of docs/function_reference.md. It joins
the reference row (category, usage, purpose, returns), the runnable example and
native parameter names from docs/function_examples.sql, the SQL-macro parameter
lists from src/macros/*.inc, and the source file that registers the function.
"""
import argparse
import json
import re
import sys
from pathlib import Path

from check_function_surface import registered_by_source
from function_examples import ExampleError, parse_examples


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs" / "function_reference.md"
OUTPUT = ROOT / "docs" / "function_catalog.jsonl"

KINDS = {
    "scalar": "scalar",
    "aggregate": "aggregate",
    "macros": "macro",
    "table_functions": "table",
}

MACRO_ENTRY = re.compile(r'\{\s*"(fin_[a-z0-9_]+)"\s*,\s*((?:"(?:[^"\\]|\\.)*"\s*)+)\}')
STRING_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def split_row(line: str) -> list[str]:
    """Split a markdown table row on unescaped pipes."""
    cells = re.split(r"(?<!\\)\|", line.strip().strip("|"))
    return [cell.strip().replace("\\|", "|") for cell in cells]


def reference_rows() -> dict[str, dict[str, str]]:
    rows: dict[str, dict[str, str]] = {}
    category = ""
    for line in read(DOCS).splitlines():
        heading = re.fullmatch(r"###\s+(.+)", line)
        if heading:
            category = heading.group(1).strip()
            continue
        if not line.startswith("| `fin_"):
            continue
        cells = split_row(line)
        if len(cells) != 4:
            raise ValueError(f"Could not parse function reference row: {line[:120]}")
        name = cells[0].strip("`")
        rows[name] = {
            "category": category,
            "usage": cells[1].strip("`"),
            "purpose": cells[2],
            "returns": cells[3],
        }
    return rows


def top_level_split(text: str) -> list[str]:
    parts: list[str] = []
    depth = 0
    quote = ""
    start = 0
    for index, char in enumerate(text):
        if quote:
            if char == quote:
                quote = ""
            continue
        if char in "'\"":
            quote = char
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1
    parts.append(text[start:].strip())
    return [part for part in parts if part]


def macro_parameters() -> dict[str, list[str]]:
    """Parameter lists (with defaults) of the SQL macros in src/macros/*.inc."""
    parameters: dict[str, list[str]] = {}
    for path in sorted((ROOT / "src" / "macros").glob("*.inc")):
        for name, literals in MACRO_ENTRY.findall(read(path)):
            definition = "".join(
                json.loads(f'"{piece}"') for piece in STRING_LITERAL.findall(literals)
            )
            depth = 0
            quote = ""
            for index, char in enumerate(definition):
                if quote:
                    if char == quote:
                        quote = ""
                    continue
                if char in "'\"":
                    quote = char
                elif char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
                    if depth == 0:
                        parameters[name] = top_level_split(definition[1:index])
                        break
    return parameters


def catalog() -> list[dict[str, object]]:
    rows = reference_rows()
    examples = {example.name: example for example in parse_examples()}
    macros = macro_parameters()
    entries = []
    for name, (source, source_kind) in sorted(registered_by_source().items()):
        row = rows.get(name)
        example = examples.get(name)
        if row is None or example is None:
            raise ValueError(f"{name} needs a function reference row and an example")
        kind = KINDS.get(source_kind)
        if kind is None:
            raise ValueError(f"{name}: cannot classify source file {source.relative_to(ROOT)}")
        if example.signatures:
            parameters = [
                [f"{parameter}:{hint}" if hint else parameter for parameter, hint in signature]
                for signature in example.signatures
            ]
        elif name in macros:
            parameters = [macros[name]]
        else:
            parameters = []
        entries.append(
            {
                "name": name,
                "kind": kind,
                "category": row["category"],
                "usage": row["usage"],
                "parameters": parameters,
                "purpose": row["purpose"],
                "returns": row["returns"],
                "example": example.sql,
                "source": str(source.relative_to(ROOT)),
            }
        )
    return entries


def render(entries: list[dict[str, object]]) -> str:
    return "".join(json.dumps(entry, ensure_ascii=False) + "\n" for entry in entries)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if docs/function_catalog.jsonl is stale")
    args = parser.parse_args()

    try:
        rendered = render(catalog())
    except (ExampleError, ValueError) as error:
        print(error)
        return 1
    count = rendered.count("\n")
    if args.check:
        try:
            current = read(OUTPUT)
        except FileNotFoundError:
            print(f"{OUTPUT.relative_to(ROOT)} is missing; run scripts/generate_function_catalog.py")
            return 1
        if current != rendered:
            print(f"{OUTPUT.relative_to(ROOT)} is stale; run scripts/generate_function_catalog.py")
            return 1
        print(f"Function catalog covers {count} registered functions.")
        return 0

    OUTPUT.write_text(rendered, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)} with {count} functions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
