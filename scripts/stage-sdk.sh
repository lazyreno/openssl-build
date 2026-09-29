#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: $0 --install <prefix> --output <dir> --os <macos|windows> --arch <arm64|x64>" >&2; exit 2; }
INSTALL_PREFIX=""; STAGE_ROOT=""; SDK_OS=""; SDK_ARCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL_PREFIX="$2"; shift 2 ;;
    --output) STAGE_ROOT="$2"; shift 2 ;;
    --os) SDK_OS="$2"; shift 2 ;;
    --arch) SDK_ARCH="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "${INSTALL_PREFIX}" && -n "${STAGE_ROOT}" && -n "${SDK_OS}" && -n "${SDK_ARCH}" ]] || usage
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
read_config_value() {
  python3 - "${ROOT}/config/$1" "$2" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]])
PY
}
SDK_VERSION="$(read_config_value sdk-version.json sdkVersion)"
OPENSSL_VERSION="$(read_config_value sdk-version.json opensslVersion)"
SOURCE_SHA256="$(read_config_value source-lock.json sourceArchiveSha256)"
MINIMUM_SYSTEM_VERSION="$(python3 - "${ROOT}/config/platform-matrix.json" "${SDK_OS}" "${SDK_ARCH}" <<'PY'
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

[[ ! -e "${STAGE_ROOT}" ]] || { echo "staging output must not exist: ${STAGE_ROOT}" >&2; exit 1; }
mkdir -p "${STAGE_ROOT}/include" "${STAGE_ROOT}/lib" "${STAGE_ROOT}/bin" "${STAGE_ROOT}/cmake" "${STAGE_ROOT}/licenses"
cp -R "${INSTALL_PREFIX}/include/openssl" "${STAGE_ROOT}/include/"
cp "${ROOT}/LICENSE" "${STAGE_ROOT}/licenses/Apache-2.0.txt"

if [[ "${SDK_OS}" == "macos" ]]; then
  cp "${INSTALL_PREFIX}/lib/libcrypto.3.dylib" "${STAGE_ROOT}/lib/"
  RUNTIME_FILE="libcrypto.3.dylib"
  CMAKE_LOCATION='${_openssl_root}/lib/libcrypto.3.dylib'
  CMAKE_IMPLIB=''
elif [[ "${SDK_OS}" == "windows" ]]; then
  cp "${INSTALL_PREFIX}/lib/libcrypto.lib" "${STAGE_ROOT}/lib/"
  runtime="$(find "${INSTALL_PREFIX}/bin" -maxdepth 1 -type f -name 'libcrypto-*.dll' -print -quit)"
  [[ -n "${runtime}" ]] || { echo "OpenSSL runtime DLL is missing" >&2; exit 1; }
  cp "${runtime}" "${STAGE_ROOT}/bin/"
  RUNTIME_FILE="$(basename "${runtime}")"
  CMAKE_LOCATION='${_openssl_root}/bin/'"${RUNTIME_FILE}"
  CMAKE_IMPLIB='    IMPORTED_IMPLIB "${_openssl_root}/lib/libcrypto.lib"'
else
  echo "unsupported OS: ${SDK_OS}" >&2; exit 2
fi

cat > "${STAGE_ROOT}/manifest.json" <<JSON
{"schemaVersion":2,"sdkVersion":"${SDK_VERSION}","opensslVersion":"${OPENSSL_VERSION}","sourceArchiveSha256":"${SOURCE_SHA256}","os":"${SDK_OS}","arch":"${SDK_ARCH}","minimumSystemVersion":"${MINIMUM_SYSTEM_VERSION}","licenseMode":"Apache-2.0","runtimeFile":"${RUNTIME_FILE}"}
JSON
cat > "${STAGE_ROOT}/cmake/OpenSSLConfig.cmake" <<CMAKE
get_filename_component(_openssl_root "\${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
if(NOT TARGET OpenSSL::Crypto)
  add_library(OpenSSL::Crypto SHARED IMPORTED)
  set_target_properties(OpenSSL::Crypto PROPERTIES
    IMPORTED_LOCATION "${CMAKE_LOCATION}"
${CMAKE_IMPLIB}
    INTERFACE_INCLUDE_DIRECTORIES "\${_openssl_root}/include")
endif()
set(OpenSSL_VERSION "${OPENSSL_VERSION}")
set(OpenSSL_RUNTIME_DIR "\${_openssl_root}/$( [[ "${SDK_OS}" == "macos" ]] && printf lib || printf bin )")
set(OpenSSL_LICENSE_DIR "\${_openssl_root}/licenses")
set(OpenSSL_MANIFEST_FILE "\${_openssl_root}/manifest.json")
CMAKE
cat > "${STAGE_ROOT}/cmake/OpenSSLConfigVersion.cmake" <<CMAKE
set(PACKAGE_VERSION "${OPENSSL_VERSION}")
if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  set(PACKAGE_VERSION_EXACT TRUE)
endif()
CMAKE
