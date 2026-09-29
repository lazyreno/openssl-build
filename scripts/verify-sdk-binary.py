#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def find_dumpbin():
    program_files = os.environ.get("ProgramFiles(x86)")
    if not program_files:
        raise SystemExit("ProgramFiles(x86) is not set; cannot locate dumpbin")
    vswhere = Path(program_files) / "Microsoft Visual Studio/Installer/vswhere.exe"
    if not vswhere.is_file():
        raise SystemExit(f"vswhere was not found: {vswhere}")
    installation = run(
        str(vswhere),
        "-latest",
        "-products",
        "*",
        "-requires",
        "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "-property",
        "installationPath",
    ).strip()
    target_architecture = "arm64" if args.arch == "arm64" else "x64"
    candidates = list(
        (Path(installation) / "VC/Tools/MSVC").glob(f"*/bin/*/{target_architecture}/dumpbin.exe")
    )
    if not candidates:
        raise SystemExit("dumpbin.exe was not found in the Visual Studio installation")
    return candidates[0]


parser = argparse.ArgumentParser()
parser.add_argument("root", type=Path)
parser.add_argument("--os", required=True, choices=("macos", "windows"))
parser.add_argument("--arch", required=True, choices=("arm64", "x64"))
args = parser.parse_args()
manifest = json.loads((args.root / "manifest.json").read_text(encoding="utf-8"))

if args.os == "macos":
    library = args.root / "lib/libcrypto.3.dylib"
    expected_arch = "x86_64" if args.arch == "x64" else "arm64"
    subprocess.run(["lipo", str(library), "-verify_arch", expected_arch], check=True)
    minos = run("xcrun", "vtool", "-show-build", str(library))
    if f"minos {manifest['minimumSystemVersion']}" not in minos:
        raise SystemExit(f"libcrypto minimum version does not match the SDK manifest: {library}")
    install_name = run("otool", "-D", str(library))
    if "@rpath/libcrypto.3.dylib" not in install_name:
        raise SystemExit(f"libcrypto install name is not relocatable: {library}")
else:
    library = next((args.root / "bin").glob("libcrypto-*.dll"))
    expected_machine = "AA64" if args.arch == "arm64" else "8664"
    headers = run(str(find_dumpbin()), "/headers", str(library))
    if expected_machine not in headers:
        raise SystemExit(f"libcrypto PE architecture mismatch: {library}")
    subsystem = re.search(r"^\s*(\d+)\.(\d+)\s+subsystem version$", headers, re.IGNORECASE | re.MULTILINE)
    if not subsystem:
        raise SystemExit(f"libcrypto PE subsystem version is missing: {library}")
    actual_version = tuple(map(int, subsystem.groups()))
    expected_version = tuple(map(int, manifest["minimumSystemVersion"].split(".")))
    if actual_version > expected_version:
        raise SystemExit(f"libcrypto PE subsystem version exceeds the support policy: {library}")

if manifest["os"] != args.os or manifest["arch"] != args.arch:
    raise SystemExit("manifest target mismatch")
print(f"SDK binary valid: {args.os}-{args.arch}")
