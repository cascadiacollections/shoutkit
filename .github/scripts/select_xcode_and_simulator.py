#!/usr/bin/env python3
"""Pick an Xcode and an iPhone simulator that belong together.

Prints two `key=value` lines to stdout, meant for `$GITHUB_OUTPUT`:

    developer_dir=/Applications/Xcode_27.app/Contents/Developer
    udid=0C91FFD9-...

Why the pairing matters: the `xcode-27` image carries several Xcodes (27.0
GA, 27.1, 27.2 beta at the time of writing) but installs simulator runtimes
for only some of them. `xcodebuild test` will happily build with Xcode N's
SDK and launch on an older runtime, and the app itself even runs — but the
test bundle links Xcode N's testing frameworks (AppIntentsTesting, XCTest),
which reference symbols that only exist in runtime N. The bundle then fails
to dlopen and the job burns ~20 minutes before reporting "Failed to load the
test bundle". Run 35958089959 is the worked example: Xcode 27.2 beta against
the only installed runtime, iOS 27.0.

So: the newest Xcode whose iOS Simulator SDK (major.minor) has a matching
installed iOS runtime with an available iPhone wins. If no Xcode matches,
fall back to the image's default Xcode (`/Applications/Xcode.app`, which
GitHub keeps pointed at the stable release) and the newest iPhone, with a
warning — better a run that might work than a guaranteed red one.

Diagnostics and `::warning::`/`::error::` annotations go to stderr. Exits
non-zero only when there is no available iPhone simulator at all.

Environment overrides, used only to exercise this off-runner:
  XCODE_GLOB  glob for Xcode bundles (default /Applications/Xcode*.app)
  XCODE_DEFAULT  the image default bundle (default /Applications/Xcode.app)
"""

from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys


def log(message: str) -> None:
    print(message, file=sys.stderr)


def version(text: str) -> tuple[int, ...]:
    # Compared as numbers, not as text: lexicographically "9.0" sorts above
    # "27.0", and "27.10" below "27.2".
    return tuple(int(part) for part in re.findall(r"\d+", text))


def runtime_version(identifier: str) -> tuple[int, ...]:
    # com.apple.CoreSimulator.SimRuntime.iOS-27-1 -> (27, 1)
    return version(identifier.rsplit(".", 1)[-1])


def simulator_sdk_version(developer_dir: str) -> tuple[int, ...] | None:
    try:
        result = subprocess.run(
            ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
            env={**os.environ, "DEVELOPER_DIR": developer_dir},
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        log(f"  {developer_dir}: no iOS Simulator SDK ({error})")
        return None
    parsed = version(result.stdout.strip())
    return parsed or None


def iphones_by_runtime() -> dict[tuple[int, ...], list[tuple[str, str]]]:
    raw = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    found: dict[tuple[int, ...], list[tuple[str, str]]] = {}
    for runtime, devices in json.loads(raw).get("devices", {}).items():
        if ".SimRuntime.iOS-" not in runtime:
            continue
        for device in devices:
            if device.get("isAvailable") and "iPhone" in device.get("name", ""):
                found.setdefault(runtime_version(runtime)[:2], []).append(
                    (device["name"], device["udid"])
                )
    return found


def main() -> int:
    iphones = iphones_by_runtime()
    if not iphones:
        log("::error::No available iPhone simulator on the runner image")
        return 1
    for runtime in sorted(iphones):
        names = ", ".join(sorted(name for name, _ in iphones[runtime]))
        log(f"iOS {'.'.join(map(str, runtime))} runtime: {names}")

    # Resolve symlinks first: the image aliases each Xcode several times
    # (Xcode_27.app, Xcode_27.0.app, Xcode_27.0.0.app, Xcode.app).
    bundles = sorted(
        {os.path.realpath(path) for path in glob.glob(os.environ.get("XCODE_GLOB", "/Applications/Xcode*.app"))}
    )
    candidates = []
    for bundle in bundles:
        developer_dir = os.path.join(bundle, "Contents", "Developer")
        sdk = simulator_sdk_version(developer_dir)
        if sdk is None:
            continue
        log(f"  {bundle}: iOS Simulator SDK {'.'.join(map(str, sdk))}")
        candidates.append((sdk[:2], bundle, developer_dir))

    # Newest SDK first; path is the tiebreak so the choice is stable run to run.
    candidates.sort(reverse=True)
    for sdk, bundle, developer_dir in candidates:
        if sdk in iphones:
            chosen_dir, runtime = developer_dir, sdk
            log(f"Selected {bundle} with its matching iOS {'.'.join(map(str, sdk))} runtime")
            break
    else:
        default = os.path.realpath(os.environ.get("XCODE_DEFAULT", "/Applications/Xcode.app"))
        chosen_dir = os.path.join(default, "Contents", "Developer")
        runtime = max(iphones)
        log(
            "::warning::No installed Xcode has an iOS Simulator SDK matching an installed "
            f"iPhone runtime; falling back to {default} on iOS {'.'.join(map(str, runtime))}. "
            "If the test bundle fails to load, this mismatch is why."
        )

    # Device name is the tiebreak so a runner with several iPhones on the
    # chosen runtime still resolves to the same one every run.
    name, udid = max(iphones[runtime])
    log(f"Using {name} ({udid})")
    print(f"developer_dir={chosen_dir}")
    print(f"udid={udid}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
