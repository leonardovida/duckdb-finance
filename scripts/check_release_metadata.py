#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DESCRIPTION = ROOT / "community-extension" / "description.yml"
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
SHA = re.compile(r"^[0-9a-f]{40}$")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def field(text: str, name: str) -> str | None:
    match = re.search(rf"(?m)^\s*{re.escape(name)}:\s*(\S+)\s*$", text)
    return match.group(1) if match else None


def render_exact_ref(text: str, sha: str) -> str:
    if not SHA.fullmatch(sha):
        raise ValueError(f"release SHA must be a 40-character lowercase hex commit, got {sha!r}")
    rendered, count = re.subn(r"(?m)^(\s*ref:\s*)\S+\s*$", rf"\g<1>{sha}", text)
    if count != 1:
        raise ValueError("community-extension/description.yml must contain exactly one repo.ref entry")
    return rendered


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", help="release tag, for example v0.1.0")
    parser.add_argument("--sha", help="exact commit SHA to render into the community extension manifest")
    parser.add_argument("--render", type=Path, help="write a release-ready manifest with repo.ref pinned to --sha")
    args = parser.parse_args()

    text = read(DESCRIPTION)
    errors: list[str] = []

    version = field(text, "version")
    repo = field(text, "github")
    ref = field(text, "ref")
    license_name = field(text, "license")

    if not version or not SEMVER.fullmatch(version):
        errors.append("extension.version must be a plain MAJOR.MINOR.PATCH value")
    if repo != "leonardovida/duckdb-finance":
        errors.append("repo.github must be leonardovida/duckdb-finance")
    if not ref or (ref != "main" and not SHA.fullmatch(ref)):
        errors.append("repo.ref must be main for development or an exact 40-character commit SHA for submission")
    if license_name != "MIT":
        errors.append("extension.license must be MIT")
    if "licence:" in text:
        errors.append("use extension.license, not extension.licence")

    if args.tag:
        expected = args.tag[1:] if args.tag.startswith("v") else args.tag
        if expected != version:
            errors.append(f"tag {args.tag} does not match extension.version {version}")

    if args.render and not args.sha:
        errors.append("--render requires --sha")

    if errors:
        print("Release metadata check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    if args.render:
        rendered = render_exact_ref(text, args.sha)
        args.render.parent.mkdir(parents=True, exist_ok=True)
        args.render.write_text(rendered, encoding="utf-8")
        print(f"Rendered release manifest to {args.render}")
    else:
        print(f"Release metadata is valid for finance {version}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
