#!/usr/bin/env python3
"""Package verified Android artifacts for an immutable GitHub Release."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

APPLICATION_ID = "io.github.octoteo.verbaseed"
APK_NAME = "verbaseed-android.apk"
AAB_NAME = "verbaseed-android.aab"
MANIFEST_NAME = "android-release-manifest.json"
CHECKSUMS_NAME = "SHA256SUMS"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _normalize_sha256(value: str, label: str) -> str:
    normalized = value.replace(":", "").strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", normalized):
        raise ValueError(f"{label} must be a SHA-256 digest")
    return normalized


def package_release(
    *,
    apk: Path,
    aab: Path,
    output_dir: Path,
    version_name: str,
    version_code: int,
    tag: str,
    commit: str,
    repository: str,
    signer_sha256: str,
) -> dict[str, object]:
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", version_name):
        raise ValueError("version_name must be a semantic version")
    if version_code < 1:
        raise ValueError("version_code must be positive")
    if tag != f"v{version_name}":
        raise ValueError(f"tag must be v{version_name}")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", commit):
        raise ValueError("commit must be a 40-character Git SHA")
    if not re.fullmatch(r"[^/\s]+/[^/\s]+", repository):
        raise ValueError("repository must use owner/name form")
    signer = _normalize_sha256(signer_sha256, "signer_sha256")

    apk = apk.resolve()
    aab = aab.resolve()
    if not apk.is_file():
        raise FileNotFoundError(apk)
    if not aab.is_file():
        raise FileNotFoundError(aab)

    output_dir.mkdir(parents=True, exist_ok=True)
    output_apk = output_dir / APK_NAME
    output_aab = output_dir / AAB_NAME
    shutil.copyfile(apk, output_apk)
    shutil.copyfile(aab, output_aab)

    apk_sha = _sha256(output_apk)
    aab_sha = _sha256(output_aab)
    release_base = f"https://github.com/{repository}/releases/download/{tag}"
    latest_base = f"https://github.com/{repository}/releases/latest/download"

    manifest: dict[str, object] = {
        "schemaVersion": 1,
        "applicationId": APPLICATION_ID,
        "versionName": version_name,
        "versionCode": version_code,
        "tag": tag,
        "commit": commit.lower(),
        "signingCertificateSha256": signer,
        "artifacts": {
            "apk": {
                "file": APK_NAME,
                "sha256": apk_sha,
                "url": f"{release_base}/{APK_NAME}",
                "latestUrl": f"{latest_base}/{APK_NAME}",
            },
            "aab": {
                "file": AAB_NAME,
                "sha256": aab_sha,
                "url": f"{release_base}/{AAB_NAME}",
                "latestUrl": f"{latest_base}/{AAB_NAME}",
            },
        },
    }

    manifest_path = output_dir / MANIFEST_NAME
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    manifest_sha = _sha256(manifest_path)

    checksum_lines = [
        f"{aab_sha}  {AAB_NAME}",
        f"{apk_sha}  {APK_NAME}",
        f"{manifest_sha}  {MANIFEST_NAME}",
    ]
    (output_dir / CHECKSUMS_NAME).write_text(
        "\n".join(checksum_lines) + "\n",
        encoding="utf-8",
    )
    return manifest


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--aab", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--version-name", required=True)
    parser.add_argument("--version-code", required=True, type=int)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--signer-sha256", required=True)
    return parser


def main() -> None:
    args = _parser().parse_args()
    package_release(
        apk=args.apk,
        aab=args.aab,
        output_dir=args.output_dir,
        version_name=args.version_name,
        version_code=args.version_code,
        tag=args.tag,
        commit=args.commit,
        repository=args.repository,
        signer_sha256=args.signer_sha256,
    )


if __name__ == "__main__":
    main()
