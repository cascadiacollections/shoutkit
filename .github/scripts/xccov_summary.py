#!/usr/bin/env python3
"""Summarize per-target line coverage from an `xccov view --report --json` feed.

Reads the JSON report on stdin and prints a Markdown table to stdout, one row
per non-test target. Companion to coverage_summary.py, which does the same job
for the mac-host SwiftPM packages; this one covers the iOS-only targets that can
only be measured on a simulator.

Baseline reporter: no threshold, never fails the build.
"""

from __future__ import annotations

import json
import sys


def main() -> int:
    try:
        report = json.load(sys.stdin)
    except ValueError as error:
        print(f"Coverage report could not be parsed: {error}")
        return 0

    rows = []
    for target in report.get("targets", []):
        name = target.get("name", "")
        # Test bundles report their own coverage, which is noise — a test bundle
        # is close to fully covered by construction.
        if name.endswith(".xctest"):
            continue
        rows.append(f"| {name} | {target.get('lineCoverage', 0.0) * 100:.1f}% |")

    if not rows:
        print("Coverage report contained no non-test targets.")
        return 0

    print("### iOS target coverage (lines)")
    print()
    print("| Target | % |")
    print("|---|---:|")
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
