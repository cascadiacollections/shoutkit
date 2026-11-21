#!/usr/bin/env python3
"""Summarize launch and memory baselines from `xcresulttool get test-results metrics`.

Reads the JSON on stdin and prints a Markdown table to stdout, one row per
measurement the Baselines test plan takes (#148). Companion to the coverage
summaries: baseline reporter, no threshold, never fails the build.

Reports the median and the range rather than the average alone, because
simulator timings on a shared runner are noisy and a single figure hides that.
Only peak memory is reported: XCTMemoryMetric's "Memory Physical" is a delta over
the measured block, and its "Absolute" figure tracks the peak to within a few
kilobytes, so neither adds anything.
"""

from __future__ import annotations

import json
import statistics
import sys

# metric identifier suffix -> (label, unit conversion, display unit)
WANTED = {
    "ApplicationFirstFramePresentationResponsive.duration": ("Launch until responsive", 1.0, "s"),
    ".physical_peak": ("Peak memory", 1 / 1024, "MB"),
    # TapToAudioBaselineUITests: tap until "Pause" shows. Includes XCTest's
    # polling for the button, so it reads about a second high; compare runs
    # on the same runner, not across machines.
    "XCTMetric_Clock.time.monotonic": ("Tap to playing (UI)", 1.0, "s"),
}


def describe(identifier: str):
    for suffix, spec in WANTED.items():
        if identifier.endswith(suffix):
            return spec
    return None


def main() -> int:
    try:
        tests = json.load(sys.stdin)
    except ValueError as error:
        print(f"Baseline metrics could not be parsed: {error}")
        return 0

    rows = []
    for test in tests if isinstance(tests, list) else []:
        name = test.get("testIdentifier", "").split("/")[-1].removesuffix("()")
        for run in test.get("testRuns", []):
            device = run.get("device", {}).get("deviceName", "?")
            for metric in run.get("metrics", []):
                spec = describe(metric.get("identifier", ""))
                values = metric.get("measurements") or []
                if spec is None or not values:
                    continue
                label, scale, unit = spec
                scaled = [value * scale for value in values]
                rows.append(
                    f"| {name} | {label} | {statistics.median(scaled):.2f} {unit} "
                    f"| {min(scaled):.2f}–{max(scaled):.2f} | {len(scaled)} | {device} |"
                )

    if not rows:
        print("No baseline metrics were recorded (the Baselines plan did not run, or every test skipped).")
        return 0

    print("### Launch and memory baselines (#148)")
    print()
    print("Measured on the CI simulator; compare across runs, not against a device.")
    print()
    print("| Test | Metric | Median | Range | Runs | Device |")
    print("|---|---|---|---|---|---|")
    for row in rows:
        print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main())
