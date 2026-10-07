#!/usr/bin/env python3
"""Fail when Xcode silently omits a test target declared in the test plan."""

import json
import subprocess
import sys
from pathlib import Path


def check(plan_path: str, result_path: str) -> int:
    plan = json.loads(Path(plan_path).read_text())
    expected = {
        entry["target"]["name"]
        for entry in plan["testTargets"]
        if not entry.get("skipped", False)
    }
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests",
         "--path", result_path, "--format", "json"],
        check=True, capture_output=True, text=True,
    )
    found = set()

    def visit(node: dict) -> None:
        if node.get("nodeType") == "Unit test bundle":
            found.add(node["name"])
        for child in node.get("children", []):
            visit(child)

    for node in json.loads(result.stdout)["testNodes"]:
        visit(node)
    missing = expected - found
    if missing:
        print("::error::Test plan targets missing from results: " + ", ".join(sorted(missing)))
        return 1
    print("All test plan targets executed: " + ", ".join(sorted(expected)))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: check-simulator-test-targets.py PLAN XCRESULT")
    sys.exit(check(*sys.argv[1:]))
