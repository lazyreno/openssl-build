#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 <destination>" >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="$1"
LOCK="${ROOT}/config/source-lock.json"
command -v curl >/dev/null
command -v gpg >/dev/null

read_lock() {
  python3 - "${LOCK}" "$1" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]])
PY
}

ARCHIVE_URL="$(read_lock sourceArchiveUrl)"
ARCHIVE_SHA256="$(read_lock sourceArchiveSha256)"
SIGNATURE_URL="$(read_lock sourceSignatureUrl)"
KEY_URL="$(read_lock signingKeyUrl)"
FINGERPRINT="$(read_lock signingKeyFingerprint)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

curl --fail --location --retry 3 --output "${WORK}/source.tar.gz" "${ARCHIVE_URL}"
printf '%s  %s\n' "${ARCHIVE_SHA256}" "${WORK}/source.tar.gz" | shasum -a 256 -c -
curl --fail --location --retry 3 --output "${WORK}/source.tar.gz.asc" "${SIGNATURE_URL}"
curl --fail --location --retry 3 --output "${WORK}/pubkeys.asc" "${KEY_URL}"
export GNUPGHOME="${WORK}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"
gpg --batch --import "${WORK}/pubkeys.asc" >/dev/null
gpg --batch --with-colons --fingerprint "${FINGERPRINT}" | grep -Fq "fpr:::::::::${FINGERPRINT}:" || {
  echo "OpenSSL signing key fingerprint was not imported: ${FINGERPRINT}" >&2
  exit 1
}
gpg --batch --verify "${WORK}/source.tar.gz.asc" "${WORK}/source.tar.gz"
rm -rf "${DESTINATION}"
mkdir -p "${DESTINATION}"
tar -xzf "${WORK}/source.tar.gz" --strip-components=1 -C "${DESTINATION}"
