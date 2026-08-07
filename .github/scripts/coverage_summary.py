#!/usr/bin/env python3
"""Summarize per-package line coverage as a GitHub step-summary table.

Reads the llvm-cov JSON export that `swift test --enable-code-coverage` writes
next to the profdata, for each package directory named on the command line, and
prints one Markdown table row per package to stdout.

This is a *baseline* reporter: it has no threshold and never fails the build.
See the calling step in .github/workflows/ci.yml for why there is no gate yet.
"""

from __future__ import annotations

import json
import pathlib
import sys


def find_export(package_dir: pathlib.Path) -> pathlib.Path | None:
    """Locate the codecov JSON under a package's .build directory.

    Globbed rather than constructed: the path carries a build-triple segment
    (.build/arm64-apple-macosx/debug/codecov/) that differs across machines, and
    SwiftPM has moved it between layouts before. Newest wins if a stale export
    from an earlier layout is still lying around.
    """
    candidates = sorted(
        package_dir.glob(".build/**/codecov/*.json"),
        key=lambda path: path.stat().st_mtime,
    )
    return candidates[-1] if candidates else None


def measure(export: pathlib.Path, package_dir: pathlib.Path) -> tuple[int, int]:
    """Return (covered, total) executable lines for the package's own sources."""
    with export.open() as handle:
        payload = json.load(handle)

    # Only this package's own Sources/: the export also covers its test bundle
    # and every local-package dependency it links, so counting everything would
    # let one package's number move because a *different* package grew a file.
    own_sources = str(package_dir.resolve() / "Sources") + "/"

    covered = total = 0
    for datum in payload.get("data", []):
        for entry in datum.get("files", []):
            if not entry.get("filename", "").startswith(own_sources):
                continue
            lines = entry.get("summary", {}).get("lines", {})
            covered += lines.get("covered", 0)
            total += lines.get("count", 0)
    return covered, total


def main(argv: list[str]) -> int:
    rows = []
    for argument in argv:
        package_dir = pathlib.Path(argument)
        name = package_dir.name

        export = find_export(package_dir)
        if export is None:
            rows.append(f"| {name} | — | — | no export |")
            continue

        try:
            covered, total = measure(export, package_dir)
        except (OSError, ValueError) as error:
            # A malformed or unreadable export is worth saying out loud, but not
            # worth failing a run over — the suites themselves already passed.
            rows.append(f"| {name} | — | — | unreadable ({type(error).__name__}) |")
            continue

        percent = f"{covered / total * 100:.1f}%" if total else "no data"
        rows.append(f"| {name} | {covered} | {total} | {percent} |")

    print("### Package coverage (lines)")
    print()
    print("| Package | Covered | Total | % |")
    print("|---|---:|---:|---:|")
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
