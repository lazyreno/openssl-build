#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


parser = argparse.ArgumentParser()
parser.add_argument("--release-assets", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--base-url", required=True)
parser.add_argument("--release-tag", required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
sdk = json.loads((root / "config/sdk-version.json").read_text(encoding="utf-8"))
source = json.loads((root / "config/source-lock.json").read_text(encoding="utf-8"))
platforms = json.loads((root / "config/platform-matrix.json").read_text(encoding="utf-8"))["platforms"]
artifacts = []
for platform in platforms:
    name = f"openssl-sdk-{platform['key']}.zip"
    archive = args.release_assets / name
    checksum = args.release_assets / f"{name}.sha256"
    if not archive.exists() or not checksum.exists():
        raise SystemExit(f"missing SDK asset: {name}")
    actual = sha256(archive)
    if checksum.read_text(encoding="utf-8").split()[0] != actual:
        raise SystemExit(f"checksum mismatch for {name}")
    artifacts.append({
        "os": platform["os"],
        "arch": platform["arch"],
        "minimumSystemVersion": platform["minimumSystemVersion"],
        "archiveExt": platform["archiveExt"],
        "file": name,
        "url": f"{args.base_url.rstrip('/')}/{name}",
        "sha256": actual,
        "size": archive.stat().st_size,
    })
args.output.write_text(json.dumps({
    "schemaVersion": 2,
    "name": "openssl-build",
    "sdkVersion": sdk["sdkVersion"],
    "opensslVersion": sdk["opensslVersion"],
    "sourceArchiveSha256": source["sourceArchiveSha256"],
    "releaseTag": args.release_tag,
    "licenseMode": sdk["licenseMode"],
    "artifacts": artifacts,
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
