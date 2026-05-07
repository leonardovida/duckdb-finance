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

    required_pages = ["/", "/function-reference/", "/performance-testing/"]
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
        "actions/configure-pages@v5",
        "enablement: true",
        "actions/jekyll-build-pages@v1",
        "source: ./docs",
        "actions/deploy-pages@v4",
    ]
    missing_fragments = [fragment for fragment in required_workflow_fragments if fragment not in workflow]
    if missing_fragments:
        print("Pages workflow is missing required publishing configuration:")
        for fragment in missing_fragments:
            print(f"  {fragment}")
        return 1

    print(f"Docs site nav covers {len(config_nav_urls())} pages and Pages publishing CI is configured.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
