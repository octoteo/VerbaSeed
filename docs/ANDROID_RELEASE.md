# Android production releases

VerbaSeed keeps production Android signing material outside the repository. Pull requests and normal CI exercise the same signing path with an ephemeral CI key, but those CI artifacts are **not** production-distributable builds.

## Trust model

A production release is accepted only when all of the following are true:

1. The release tag already exists and uses `vX.Y.Z` form.
2. The tag version exactly matches `apps/learner/pubspec.yaml` (`X.Y.Z+versionCode`).
3. The tagged commit is already contained in `main`.
4. No GitHub Release exists for that tag yet; releases are never overwritten.
5. All four signing secrets are present in the `android-production` GitHub Environment.
6. The keystore certificate matches the pinned `ANDROID_RELEASE_CERT_SHA256` environment variable.
7. The built APK verifies successfully and its actual signer fingerprint matches that same pinned certificate.
8. The AAB verifies as a signed JAR.
9. SHA-256 checksums for the APK, AAB and release manifest verify before publication.

The workflow then creates one GitHub Release containing stable asset names:

- `verbaseed-android.apk`
- `verbaseed-android.aab`
- `android-release-manifest.json`
- `SHA256SUMS`

Stable names make `releases/latest/download/...` usable by a future updater without weakening per-release hashes or signer pinning.

## One-time GitHub setup

Create a GitHub Environment named `android-production`. Configure approval/protection rules if the repository plan supports them, then add these Environment secrets:

- `ANDROID_RELEASE_KEYSTORE_BASE64`
- `ANDROID_RELEASE_KEYSTORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

Also add this Environment variable:

- `ANDROID_RELEASE_CERT_SHA256`

The certificate fingerprint is public metadata, not a private key. Store it without spaces; colons are accepted. The release workflow normalizes the value before comparison.

### Encode the keystore

Do this on a trusted machine. Never commit the keystore or the encoded value.

```bash
base64 -w 0 verbaseed-release.jks
```

On macOS, use:

```bash
base64 < verbaseed-release.jks | tr -d '\n'
```

Copy the result into `ANDROID_RELEASE_KEYSTORE_BASE64`.

### Calculate the pinned certificate SHA-256

```bash
keytool -exportcert \
  -alias YOUR_ALIAS \
  -keystore verbaseed-release.jks \
  -rfc \
  | openssl x509 -outform der \
  | sha256sum
```

On macOS, replace `sha256sum` with `shasum -a 256`.

The first field is the value for `ANDROID_RELEASE_CERT_SHA256`.

## Key custody

The production signing key is part of VerbaSeed's update identity. Losing it can prevent existing direct-APK installations from accepting future updates. Replacing it with an unrelated key can do the same.

Keep at least two encrypted offline backups of the keystore and its passwords, stored separately. Restrict GitHub Environment access and do not reuse the key for unrelated applications.

If VerbaSeed later uses Google Play App Signing, document the distinction between the Play app-signing key and any upload key before changing this workflow. Do not silently substitute one for the other.

## Publishing a release

1. Merge the intended release commit to `main` and let normal CI pass.
2. Confirm `apps/learner/pubspec.yaml` has the intended `X.Y.Z+N` version.
3. Create and push an annotated tag pointing at that commit:

```bash
git tag -a vX.Y.Z -m "VerbaSeed X.Y.Z"
git push origin vX.Y.Z
```

4. The **Android production release** workflow starts automatically.
5. If the tag-triggered run failed only because Environment configuration was not ready, fix the configuration and use `workflow_dispatch` with the existing tag. The workflow never creates or moves tags.

Do not delete and recreate a published tag or overwrite an existing GitHub Release. Publish a new version instead.

## Release manifest

`android-release-manifest.json` is deterministic for the same binaries, commit, version, repository and signer. Schema version 1 records:

- Android application ID
- version name and version code
- Git tag and exact commit SHA
- signing certificate SHA-256
- APK/AAB SHA-256 values
- immutable tag-specific download URLs
- stable `releases/latest/download` URLs

`SHA256SUMS` covers the APK, AAB and manifest itself.

## CI behavior

Normal CI creates a short-lived signing key and sets `VERBASEED_REQUIRE_RELEASE_SIGNING=true`. This proves that the production signing Gradle branch, APK verification, AAB verification, release-manifest generation and checksum validation all work without exposing the real key.

The CI artifact is named `verbaseed-android-ci-build` and is intentionally signed by an ephemeral key. It must never be redistributed as a production build.

Local `flutter build apk --release` remains possible without signing variables for developer validation, but Gradle emits a warning and uses debug signing. Any production workflow must set `VERBASEED_REQUIRE_RELEASE_SIGNING=true`, which makes missing or partial signing configuration a hard failure.
