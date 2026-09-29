#!/usr/bin/env bash
set -euo pipefail
: "${SDK_ARCH:?SDK_ARCH is required}"
: "${OPENSSL_SRC:?OPENSSL_SRC is required}"
: "${OPENSSL_PREFIX:?OPENSSL_PREFIX is required}"
: "${SDK_MINIMUM_SYSTEM_VERSION:?SDK_MINIMUM_SYSTEM_VERSION is required}"

case "${SDK_ARCH}" in
  arm64) target="darwin64-arm64-cc" ;;
  x64) target="darwin64-x86_64-cc" ;;
  *) echo "unsupported macOS SDK architecture: ${SDK_ARCH}" >&2; exit 2 ;;
esac

export MACOSX_DEPLOYMENT_TARGET="${SDK_MINIMUM_SYSTEM_VERSION}"
cd "${OPENSSL_SRC}"
./Configure "${target}" shared --prefix="${OPENSSL_PREFIX}" --openssldir=/etc/ssl
make -j"$(sysctl -n hw.ncpu)"
make test
make install_sw
install_name_tool -id @rpath/libcrypto.3.dylib "${OPENSSL_PREFIX}/lib/libcrypto.3.dylib"
