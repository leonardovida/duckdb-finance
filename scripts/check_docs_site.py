#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def page_permalinks() -> dict[str, Path]:
    pages: dict[str, Path] = {}
    for path in sorted(DOCS.glob("*.md")):
        text = read(path)
        match = re.search(r"^permalink:\s*(\S+)\s*$", text, re.M)
        if match:
            pages[match.group(1)] = path
    return pages


def config_nav_urls() -> list[str]:
    config = read(DOCS / "_config.yml")
    return re.findall(r"^\s+url:\s*(\S+)\s*$", config, re.M)


def main() -> int:
    pages = page_permalinks()
    missing_nav = [url for url in config_nav_urls() if url not in pages]
    if missing_nav:
        print("Docs nav entries without matching page permalinks:")
        for url in missing_nav:
            print(f"  {url}")
        return 1

    required_pages = [
        "/",
        "/getting-started/",
        "/agent-guide/",
        "/installation/",
        "/function-cookbook/",
        "/function-reference/",
        "/data-source-compatibility/",
        "/experimental-functions/",
        "/playbooks/",
        "/best-practices/",
        "/quant-developer-guide/",
        "/release/",
        "/performance-testing/",
        "/development/",
    ]
    missing_pages = [url for url in required_pages if url not in pages]
    if missing_pages:
        print("Missing required documentation pages:")
        for url in missing_pages:
            print(f"  {url}")
        return 1

    workflow = read(ROOT / ".github" / "workflows" / "pages.yml")
    required_workflow_fragments = [
        "branches:\n      - main",
        "pages: write",
        "id-token: write",
        "actions/configure-pages@v6",
        "enablement: true",
        "actions/jekyll-build-pages@v1",
        "source: ./docs",
        "actions/upload-pages-artifact@v5",
        "actions/deploy-pages@v5",
    ]
    missing_fragments = [fragment for fragment in required_workflow_fragments if fragment not in workflow]
    if missing_fragments:
        print("Pages workflow is missing required publishing configuration:")
        for fragment in missing_fragments:
            print(f"  {fragment}")
        return 1

    descriptor = read(ROOT / "community-extension" / "description.yml")
    required_descriptor_fragments = [
        "name: finance",
        "version:",
        "language: C++",
        "build: cmake",
        "license: MIT",
        "maintainers:",
        "github: leonardovida/duckdb-finance",
        "ref:",
        "hello_world:",
        "INSTALL finance FROM community",
    ]
    missing_descriptor_fragments = [
        fragment for fragment in required_descriptor_fragments if fragment not in descriptor
    ]
    if missing_descriptor_fragments:
        print("Community extension descriptor is missing required install metadata:")
        for fragment in missing_descriptor_fragments:
            print(f"  {fragment}")
        return 1

    layout = read(DOCS / "_layouts" / "default.html")
    required_layout_fragments = [
        "<span>Namespace</span>",
        "<code>fin_* functions</code>",
    ]
    missing_layout_fragments = [
        fragment for fragment in required_layout_fragments if fragment not in layout
    ]
    if missing_layout_fragments:
        print("Docs layout is missing the neutral sidebar namespace snippet:")
        for fragment in missing_layout_fragments:
            print(f"  {fragment}")
        return 1

    forbidden_layout_fragments = [
        "INSTALL finance FROM community;",
    ]
    ambiguous_layout_fragments = [
        fragment for fragment in forbidden_layout_fragments if fragment in layout
    ]
    if ambiguous_layout_fragments:
        print("Docs layout should not advertise unpublished install commands site-wide:")
        for fragment in ambiguous_layout_fragments:
            print(f"  {fragment}")
        return 1

    forbidden_fragments = [
        "/Users/" + "leov/",
        "build/debug/" + "extension/finance/finance." + "duckdb_extension",
        "LOAD '",
    ]
    public_doc_paths = [
        ROOT / "README.md",
        ROOT / "CONTRIBUTING.md",
        ROOT / "AGENTS.md",
        *DOCS.glob("*.md"),
        *DOCS.glob("_layouts/*.html"),
        *ROOT.glob("examples/*.sql"),
    ]
    docs_with_forbidden_fragments = []
    for path in public_doc_paths:
        text = read(path)
        matches = [fragment for fragment in forbidden_fragments if fragment in text]
        if matches:
            docs_with_forbidden_fragments.append((path.relative_to(ROOT), matches))
    if docs_with_forbidden_fragments:
        print("Docs contain local extension binary load requirements:")
        for path, matches in docs_with_forbidden_fragments:
            print(f"  {path}: {', '.join(matches)}")
        return 1

    print(f"Docs site nav covers {len(config_nav_urls())} pages and Pages publishing CI is configured.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
