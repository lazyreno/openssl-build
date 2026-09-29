#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("root", type=Path)
parser.add_argument("--platform", required=True, choices=("macos", "windows"))
parser.add_argument("--arch", required=True, choices=("arm64", "x64"))
args = parser.parse_args()

required = [
    "include/openssl/crypto.h",
    "lib",
    "bin",
    "cmake/OpenSSLConfig.cmake",
    "cmake/OpenSSLConfigVersion.cmake",
    "licenses/Apache-2.0.txt",
    "manifest.json",
]
missing = [item for item in required if not (args.root / item).exists()]
if args.platform == "macos":
    runtime = args.root / "lib/libcrypto.3.dylib"
    if not runtime.is_file():
        missing.append("lib/libcrypto.3.dylib")
else:
    if not (args.root / "lib/libcrypto.lib").is_file():
        missing.append("lib/libcrypto.lib")
    if not any((args.root / "bin").glob("libcrypto-*.dll")):
        missing.append("bin/libcrypto-*.dll")
if missing:
    print("missing: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)

manifest = json.loads((args.root / "manifest.json").read_text(encoding="utf-8"))
matrix = json.loads(
    (Path(__file__).resolve().parents[1] / "config/platform-matrix.json").read_text(encoding="utf-8")
)["platforms"]
expected = next(
    (entry for entry in matrix if entry["os"] == args.platform and entry["arch"] == args.arch),
    None,
)
if expected is None:
    raise SystemExit("unsupported platform target")
if manifest.get("schemaVersion") != 2:
    raise SystemExit("manifest schemaVersion must be 2")
if manifest.get("os") != args.platform or manifest.get("arch") != args.arch:
    raise SystemExit("manifest OS or architecture mismatch")
if manifest.get("minimumSystemVersion") != expected["minimumSystemVersion"]:
    raise SystemExit("manifest minimumSystemVersion mismatch")
if manifest.get("licenseMode") != "Apache-2.0":
    raise SystemExit("manifest licenseMode must be Apache-2.0")
print(f"SDK layout valid: {args.platform}-{args.arch}")
