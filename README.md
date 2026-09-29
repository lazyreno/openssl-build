# openssl-build

Reproducible OpenSSL 3.5.8 SDK artifacts for macOS arm64/x64 and Windows arm64/x64.

Each release artifact contains only OpenSSL headers, `libcrypto`, a CMake
`OpenSSL::Crypto` target, the Apache-2.0 notice, and a target manifest. The
release workflow verifies the source tarball SHA-256 and OpenSSL signing key,
runs the upstream test suite, then checks the staged binary architecture and
macOS 13 deployment target before publishing it. Manifests and the artifact
index use `os` and `arch` as separate target fields.
