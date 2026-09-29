#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: $0 --install <prefix> --output <dir> --platform <macos|windows> --arch <arm64|x64>" >&2; exit 2; }
INSTALL=""; OUTPUT=""; PLATFORM=""; ARCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "${INSTALL}" && -n "${OUTPUT}" && -n "${PLATFORM}" && -n "${ARCH}" ]] || usage
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
read_config() {
  python3 - "${ROOT}/config/$1" "$2" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]])
PY
}
SDK_VERSION="$(read_config sdk-version.json sdkVersion)"
OPENSSL_VERSION="$(read_config sdk-version.json opensslVersion)"
SOURCE_SHA256="$(read_config source-lock.json sourceArchiveSha256)"
MINIMUM_SYSTEM_VERSION="$(python3 - "${ROOT}/config/platform-matrix.json" "${PLATFORM}" "${ARCH}" <<'PY'
import json
import sys
for value in json.load(open(sys.argv[1], encoding="utf-8"))["platforms"]:
    if value["os"] == sys.argv[2] and value["arch"] == sys.argv[3]:
        print(value["minimumSystemVersion"])
        break
else:
    raise SystemExit("unsupported platform")
PY
)"
if [[ -n "${SDK_MINIMUM_SYSTEM_VERSION:-}" && "${SDK_MINIMUM_SYSTEM_VERSION}" != "${MINIMUM_SYSTEM_VERSION}" ]]; then
  echo "SDK_MINIMUM_SYSTEM_VERSION does not match the platform matrix" >&2
  exit 1
fi

rm -rf "${OUTPUT}"
mkdir -p "${OUTPUT}/include" "${OUTPUT}/lib" "${OUTPUT}/bin" "${OUTPUT}/cmake" "${OUTPUT}/licenses"
cp -R "${INSTALL}/include/openssl" "${OUTPUT}/include/"
cp "${ROOT}/LICENSE" "${OUTPUT}/licenses/Apache-2.0.txt"

if [[ "${PLATFORM}" == "macos" ]]; then
  cp "${INSTALL}/lib/libcrypto.3.dylib" "${OUTPUT}/lib/"
  RUNTIME_FILE="libcrypto.3.dylib"
  CMAKE_LOCATION='${_openssl_root}/lib/libcrypto.3.dylib'
  CMAKE_IMPLIB=''
elif [[ "${PLATFORM}" == "windows" ]]; then
  cp "${INSTALL}/lib/libcrypto.lib" "${OUTPUT}/lib/"
  runtime="$(find "${INSTALL}/bin" -maxdepth 1 -type f -name 'libcrypto-*.dll' -print -quit)"
  [[ -n "${runtime}" ]] || { echo "OpenSSL runtime DLL is missing" >&2; exit 1; }
  cp "${runtime}" "${OUTPUT}/bin/"
  RUNTIME_FILE="$(basename "${runtime}")"
  CMAKE_LOCATION='${_openssl_root}/bin/'"${RUNTIME_FILE}"
  CMAKE_IMPLIB='    IMPORTED_IMPLIB "${_openssl_root}/lib/libcrypto.lib"'
else
  echo "unsupported platform: ${PLATFORM}" >&2; exit 2
fi

cat > "${OUTPUT}/manifest.json" <<JSON
{"schemaVersion":2,"sdkVersion":"${SDK_VERSION}","opensslVersion":"${OPENSSL_VERSION}","sourceArchiveSha256":"${SOURCE_SHA256}","os":"${PLATFORM}","arch":"${ARCH}","minimumSystemVersion":"${MINIMUM_SYSTEM_VERSION}","licenseMode":"Apache-2.0","runtimeFile":"${RUNTIME_FILE}"}
JSON
cat > "${OUTPUT}/cmake/OpenSSLConfig.cmake" <<CMAKE
get_filename_component(_openssl_root "\${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
if(NOT TARGET OpenSSL::Crypto)
  add_library(OpenSSL::Crypto SHARED IMPORTED)
  set_target_properties(OpenSSL::Crypto PROPERTIES
    IMPORTED_LOCATION "${CMAKE_LOCATION}"
${CMAKE_IMPLIB}
    INTERFACE_INCLUDE_DIRECTORIES "\${_openssl_root}/include")
endif()
set(OpenSSL_VERSION "${OPENSSL_VERSION}")
set(OpenSSL_RUNTIME_DIR "\${_openssl_root}/$( [[ "${PLATFORM}" == "macos" ]] && printf lib || printf bin )")
set(OpenSSL_LICENSE_DIR "\${_openssl_root}/licenses")
set(OpenSSL_MANIFEST_FILE "\${_openssl_root}/manifest.json")
CMAKE
cat > "${OUTPUT}/cmake/OpenSSLConfigVersion.cmake" <<CMAKE
set(PACKAGE_VERSION "${OPENSSL_VERSION}")
if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  set(PACKAGE_VERSION_EXACT TRUE)
endif()
CMAKE
