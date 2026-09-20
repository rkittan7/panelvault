#!/usr/bin/env python3
"""Type-checks the three native apps without building them.

CI used to check them with `swiftc -parse`, which is syntax only. Parsing
cannot see a method called on the wrong type, or an assignment to a name that a
shadowing `if let` made immutable. Those errors reached `main` and then surfaced
minutes later inside the xcodebuild job, in the middle of its output, where they
read like a build problem rather than a source problem.

`swiftc -typecheck` runs the same type checker xcodebuild runs and stops the
moment the module is proven sound: no SIL, no optimizer, no asset catalog, no
linking, no simulator destination to resolve. It is the cheapest check that
catches the whole class of error, and it runs on the macOS job that is already
there.

This does not replace the xcodebuild job. That job still catches what only a
real build can: asset catalogs, Info.plist keys, linking. This catches source
errors first, and says plainly which app and which line.

It is the compiler-backed counterpart to `check_worker.py`, which approximates
these checks on a machine with no Swift toolchain. Where both can run, this one
is the authority.

Requires macOS with Xcode. Run from the repo root:

    python3 tools/typecheck_swift.py                 # all three apps
    python3 tools/typecheck_swift.py manager worker  # just these
"""

import concurrent.futures
import os
import platform
import re
import shutil
import subprocess
import sys
import time

# Each app is one Swift module, compiled from every source listed here exactly
# as its Xcode target compiles it. `settings` is the file the deployment target
# and Swift version are read from, so this check cannot drift from the build.
APPS = [
    {
        "name": "manager",
        "module": "Runner",
        "sources": ["ios/Runner"],
        "settings": "ios/Runner.xcodeproj/project.pbxproj",
    },
    {
        "name": "worker",
        "module": "Worker",
        "sources": ["worker/Sources"],
        "settings": "worker/project.yml",
    },
    {
        "name": "warehouse",
        "module": "Warehouse",
        "sources": ["warehouse/Sources"],
        "settings": "warehouse/project.yml",
    },
]


def swift_files(roots):
    """Every .swift file under the given directories, in a stable order."""
    found = []
    for root in roots:
        for directory, _, names in os.walk(root):
            found += [
                os.path.join(directory, name)
                for name in names
                if name.endswith(".swift")
            ]
    return sorted(found)


def setting(path, patterns, label):
    """The lowest value any of `patterns` matches in `path`.

    The deployment target appears once per build configuration, and an app is
    only as new as its oldest one: checking against the lowest keeps an
    availability mistake from passing here and failing in Xcode.
    """
    text = open(path, encoding="utf-8").read()
    values = []
    for pattern in patterns:
        values += re.findall(pattern, text)
    if not values:
        sys.exit(f"no {label} found in {path}")
    return min(values, key=lambda value: [int(part) for part in value.split(".")])


def deployment_target(path):
    return setting(
        path,
        [
            r"IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);",  # Xcode project
            r'iOS:\s*"([0-9.]+)"',                       # XcodeGen spec
        ],
        "iOS deployment target",
    )


def swift_version(path):
    return setting(
        path,
        [
            r'SWIFT_VERSION = "?([0-9.]+)"?;',  # Xcode project
            r'SWIFT_VERSION:\s*"([0-9.]+)"',    # XcodeGen spec
        ],
        "Swift version",
    )


def typecheck(app, sdk, arch):
    """Type-check one app. Returns (seconds, exit code, compiler output)."""
    sources = swift_files(app["sources"])
    if not sources:
        return 0.0, 1, f"no Swift sources under {', '.join(app['sources'])}\n"

    target = deployment_target(app["settings"])
    language = swift_version(app["settings"]).split(".")[0]
    command = [
        "swiftc",
        "-typecheck",
        "-sdk", sdk,
        "-target", f"{arch}-apple-ios{target}-simulator",
        "-swift-version", language,
        # The apps get their entry point from @main, like every Xcode app
        # target. Without this swiftc treats the first file as a script and
        # rejects @main alongside it.
        "-parse-as-library",
        "-module-name", app["module"],
    ] + sources

    started = time.monotonic()
    result = subprocess.run(command, capture_output=True, text=True)
    elapsed = time.monotonic() - started
    return elapsed, result.returncode, result.stdout + result.stderr


def main(argv):
    if not os.path.isdir("tools"):
        sys.exit("run from the repo root")
    if platform.system() != "Darwin" or not shutil.which("xcrun"):
        sys.exit("needs macOS with Xcode: swiftc cannot reach the iOS SDK here")

    wanted = argv or [app["name"] for app in APPS]
    known = {app["name"]: app for app in APPS}
    unknown = [name for name in wanted if name not in known]
    if unknown:
        sys.exit(f"unknown app(s) {', '.join(unknown)}; pick from {', '.join(known)}")
    apps = [known[name] for name in wanted]

    sdk = subprocess.run(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    # The simulator SDK carries both slices, so this only has to match the
    # runner it is on.
    arch = platform.machine()
    print(f"Type-checking against {os.path.basename(sdk)} for {arch}\n")

    # One process per app, run together: they share no sources, and the macOS
    # runner has the cores. Output is held and printed per app so three
    # compilers cannot interleave their diagnostics.
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(apps)) as pool:
        results = list(pool.map(lambda app: typecheck(app, sdk, arch), apps))

    failed = []
    for app, (elapsed, code, output) in zip(apps, results):
        state = "ok" if code == 0 else "FAILED"
        count = len(swift_files(app["sources"]))
        print(f"{app['name']} ({app['module']}, {count} files): {state} in {elapsed:.0f}s")
        if output.strip():
            print("".join(f"  {line}\n" for line in output.strip().split("\n")))
        if code != 0:
            failed.append(app["name"])

    if failed:
        print(f"\nType errors in {', '.join(failed)}. Fix these before the build runs.")
        return 1
    print("\nAll three apps type-check.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
