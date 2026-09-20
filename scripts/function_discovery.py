"""Shared source inventory for documentation and test coverage checks."""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def source_files() -> list[Path]:
    suffixes = {".cpp", ".inc", ".hpp"}
    return sorted(path for path in (ROOT / "src").rglob("*") if path.suffix in suffixes)


def registered_functions() -> set[str]:
    source = "\n".join(read(path) for path in source_files())
    functions = set(re.findall(r'"(fin_[A-Za-z0-9_]+)"', source))
    functions.discard("fin_cdl_")
    return functions
