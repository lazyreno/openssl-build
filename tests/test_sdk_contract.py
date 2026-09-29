import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class OpenSslSdkContractTest(unittest.TestCase):
    def stage_fake_macos_sdk(self, directory):
        root = Path(directory)
        install = root / "install"
        (install / "include/openssl").mkdir(parents=True)
        (install / "lib").mkdir()
        (install / "include/openssl/crypto.h").write_text("", encoding="utf-8")
        (install / "lib/libcrypto.3.dylib").write_text("", encoding="utf-8")
        sdk = root / "sdk"
        subprocess.run(
            [
                "scripts/stage-sdk.sh",
                "--install",
                str(install),
                "--output",
                str(sdk),
                "--platform",
                "macos",
                "--arch",
                "arm64",
            ],
            cwd=ROOT,
            check=True,
        )
        return sdk

    def test_repository_license_is_complete(self):
        license_text = (ROOT / "LICENSE").read_text(encoding="utf-8")
        self.assertIn("END OF TERMS AND CONDITIONS", license_text)

    def test_matrix_emits_the_four_supported_artifacts(self):
        result = subprocess.run(
            [sys.executable, "scripts/generate-github-matrix.py"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )

        matrix = json.loads(result.stdout)["include"]
        self.assertEqual(
            [entry["key"] for entry in matrix],
            ["macos-arm64", "macos-x64", "windows-arm64", "windows-x64"],
        )
        self.assertEqual(
            [entry["minimumSystemVersion"] for entry in matrix[:2]], ["13.0", "13.0"]
        )

    def test_staged_manifest_uses_os_and_arch_without_a_redundant_key(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk = self.stage_fake_macos_sdk(directory)
            manifest = json.loads((sdk / "manifest.json").read_text(encoding="utf-8"))

        self.assertEqual(manifest["schemaVersion"], 2)
        self.assertNotIn("platformKey", manifest)
        self.assertEqual(manifest["os"], "macos")
        self.assertEqual(manifest["arch"], "arm64")

    def test_staged_sdk_supports_exact_cmake_version_lookup(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk = self.stage_fake_macos_sdk(directory)
            result = subprocess.run(
                [
                    "cmake",
                    "-S",
                    "tests/cmake-consumer",
                    "-B",
                    str(Path(directory) / "build"),
                    f"-DOpenSSL_DIR={sdk / 'cmake'}",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_windows_ci_contains_a_load_and_rand_smoke_test(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")

        self.assertIn("Smoke-test Windows libcrypto", workflow)
        self.assertIn("ctypes.WinDLL", workflow)
        self.assertIn("RAND_bytes", workflow)

    def test_tagged_release_uses_and_validates_the_triggering_git_tag(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")

        self.assertIn("release_tag=\"${REF_NAME}\"", workflow)
        self.assertIn("release tag must match sdkVersion", workflow)

    def test_layout_validator_rejects_sdk_without_crypto_library(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("include", "lib", "bin", "cmake", "licenses"):
                (root / name).mkdir()
            (root / "manifest.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "platform": "macos",
                        "arch": "arm64",
                        "minimumSystemVersion": "13.0",
                    }
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    "scripts/validate-sdk-layout.py",
                    str(root),
                    "--platform",
                    "macos",
                    "--arch",
                    "arm64",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("libcrypto", result.stderr)


if __name__ == "__main__":
    unittest.main()
