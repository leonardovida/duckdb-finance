"""Parser for docs/function_examples.sql (one runnable example per fin_* function)."""

import re
from dataclasses import dataclass
from pathlib import Path

from run_sql_with_trace import split_statements


ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "docs" / "function_examples.sql"

HEADER = re.compile(r"-- (fin_[a-z0-9_]+)(?:\((.*)\))?")
PARAMETER = re.compile(r"([a-z_][a-z0-9_]*)(?::([A-Z][A-Z0-9_ ]*(?:\[\])*))?")


@dataclass(frozen=True)
class FunctionExample:
    name: str
    signatures: tuple[tuple[tuple[str, str], ...], ...]
    sql: str
    line: int


class ExampleError(ValueError):
    pass


def parse_signature(text: str, line: int) -> tuple[tuple[str, str], ...]:
    text = text.strip()
    if not text:
        return ()
    parameters = []
    for part in text.split(","):
        match = PARAMETER.fullmatch(part.strip())
        if not match:
            raise ExampleError(f"line {line}: invalid parameter {part.strip()!r} (use name or name:TYPE)")
        parameters.append((match.group(1), match.group(2) or ""))
    names = [name for name, _ in parameters]
    if len(set(names)) != len(names):
        raise ExampleError(f"line {line}: duplicate parameter name in signature")
    return tuple(parameters)


def normalize_sql(lines: list[str]) -> str:
    return " ".join(line.strip() for line in lines if line.strip())


def parse_examples(path: Path = EXAMPLES) -> list[FunctionExample]:
    examples: list[FunctionExample] = []
    name = None
    signatures: list[tuple[tuple[str, str], ...]] = []
    header_line = 0
    has_bare_header = False
    body: list[str] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.rstrip()
        header = HEADER.fullmatch(line)
        if body:
            if line.lstrip().startswith("--"):
                raise ExampleError(f"line {number}: comments are not allowed inside the {name} example")
            body.append(line)
        elif header:
            if name is not None and header.group(1) != name:
                raise ExampleError(f"line {number}: header for {header.group(1)} follows {name} without an example")
            if name is None:
                header_line = number
            name = header.group(1)
            if header.group(2) is None:
                has_bare_header = True
            else:
                signatures.append(parse_signature(header.group(2), number))
            continue
        elif not line.strip() or line.startswith("--"):
            if name is not None and line.strip():
                raise ExampleError(f"line {number}: unexpected comment after the {name} header")
            continue
        elif name is None:
            raise ExampleError(f"line {number}: SQL without a '-- fin_name' header")
        else:
            body.append(line)
        if body and line.endswith(";"):
            sql = normalize_sql(body)
            statements = split_statements(sql)
            if len(statements) != 1:
                raise ExampleError(f"line {header_line}: the {name} example must be exactly one statement")
            if has_bare_header and signatures:
                raise ExampleError(f"line {header_line}: {name} mixes a bare header with signature headers")
            examples.append(FunctionExample(name, tuple(signatures), sql, header_line))
            name = None
            signatures = []
            has_bare_header = False
            body = []
    if name is not None:
        raise ExampleError(f"line {header_line}: the {name} example does not end with ';'")
    return examples


def render_signatures(example: FunctionExample) -> str:
    """Encode signatures for the C++ metadata table: `a,b:TYPE;spec`."""
    return ";".join(
        ",".join(f"{name}:{hint}" if hint else name for name, hint in signature)
        for signature in example.signatures
    )
