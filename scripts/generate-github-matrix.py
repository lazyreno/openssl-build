#!/usr/bin/env python3
import json
import pathlib
import sys


root = pathlib.Path(__file__).resolve().parents[1]
platforms = json.loads((root / "config/platform-matrix.json").read_text(encoding="utf-8"))["platforms"]
expected = ["macos-arm64", "macos-x64", "windows-arm64", "windows-x64"]

if [platform["key"] for platform in platforms] != expected:
    raise SystemExit("platform matrix must list the four supported platforms in release order")
if any(platform["os"] == "macos" and platform["minimumSystemVersion"] != "13.0" for platform in platforms):
    raise SystemExit("macOS OpenSSL SDK artifacts must target macOS 13.0")

matrix = json.dumps({"include": platforms}, separators=(",", ":"))
if len(sys.argv) == 3 and sys.argv[1] == "--github-output":
    pathlib.Path(sys.argv[2]).open("a", encoding="utf-8").write(f"matrix={matrix}\n")
else:
    print(matrix)
