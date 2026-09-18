import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from package_android_release import (
    AAB_NAME,
    APK_NAME,
    CHECKSUMS_NAME,
    MANIFEST_NAME,
    package_release,
)


class PackageAndroidReleaseTest(unittest.TestCase):
    def test_packages_stable_assets_manifest_and_checksums(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            apk = root / "input.apk"
            aab = root / "input.aab"
            apk.write_bytes(b"apk-bytes")
            aab.write_bytes(b"aab-bytes")
            output = root / "dist"
            signer = "12" * 32

            manifest = package_release(
                apk=apk,
                aab=aab,
                output_dir=output,
                version_name="0.2.14",
                version_code=16,
                tag="v0.2.14",
                commit="ab" * 20,
                repository="octoteo/VerbaSeed",
                signer_sha256=signer,
            )

            self.assertEqual(manifest["applicationId"], "io.github.octoteo.verbaseed")
            self.assertEqual(manifest["versionCode"], 16)
            self.assertEqual(manifest["signingCertificateSha256"], signer)
            self.assertEqual((output / APK_NAME).read_bytes(), b"apk-bytes")
            self.assertEqual((output / AAB_NAME).read_bytes(), b"aab-bytes")

            disk_manifest = json.loads((output / MANIFEST_NAME).read_text())
            apk_entry = disk_manifest["artifacts"]["apk"]
            self.assertEqual(
                apk_entry["sha256"], hashlib.sha256(b"apk-bytes").hexdigest()
            )
            self.assertEqual(
                apk_entry["latestUrl"],
                "https://github.com/octoteo/VerbaSeed/releases/latest/download/verbaseed-android.apk",
            )
            checksums = (output / CHECKSUMS_NAME).read_text()
            self.assertIn(hashlib.sha256(b"apk-bytes").hexdigest(), checksums)
            self.assertIn(hashlib.sha256(b"aab-bytes").hexdigest(), checksums)

    def test_rejects_mismatched_tag(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            apk = root / "input.apk"
            aab = root / "input.aab"
            apk.write_bytes(b"apk")
            aab.write_bytes(b"aab")
            with self.assertRaisesRegex(ValueError, "tag must be v0.2.14"):
                package_release(
                    apk=apk,
                    aab=aab,
                    output_dir=root / "dist",
                    version_name="0.2.14",
                    version_code=16,
                    tag="v0.2.13",
                    commit="ab" * 20,
                    repository="octoteo/VerbaSeed",
                    signer_sha256="12" * 32,
                )

    def test_rejects_invalid_signer_digest(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            apk = root / "input.apk"
            aab = root / "input.aab"
            apk.write_bytes(b"apk")
            aab.write_bytes(b"aab")
            with self.assertRaisesRegex(ValueError, "signer_sha256"):
                package_release(
                    apk=apk,
                    aab=aab,
                    output_dir=root / "dist",
                    version_name="0.2.14",
                    version_code=16,
                    tag="v0.2.14",
                    commit="ab" * 20,
                    repository="octoteo/VerbaSeed",
                    signer_sha256="not-a-digest",
                )


if __name__ == "__main__":
    unittest.main()
