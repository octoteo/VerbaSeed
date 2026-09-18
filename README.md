# VerbaSeed

VerbaSeed is a local-first, AI-native, open-source language learning platform designed to grow with a learner from early childhood through formal curriculum and independent study.

## Product principles

- **Local-first:** core learning works without an account or cloud dependency.
- **Adaptive:** every activity contributes to a learner model and future review plan.
- **Open courses:** content can come from open course repositories, local files, camera/OCR pipelines, PDFs, URLs, subtitles, and other providers.
- **Pronunciation-aware:** British and American English are first-class; courses may define their default accent.
- **Child-safe by design:** learner profiles are local by default and cloud features are opt-in.
- **Extensible:** course schema, content sources, speech, AI, and learning algorithms are separated behind contracts.

## Repository layout

```text
apps/learner/                Flutter learner application
packages/course_schema/      Open Course data model
packages/learning_engine/    Review scheduling and learner progression
schemas/                     Language-agnostic JSON contracts
docs/                        Architecture, ADRs, roadmap and policies
.github/workflows/           CI quality gates and production release workflows
```

## Run the web app

```bash
cd apps/learner
flutter pub get
flutter run -d chrome
```

## Build for production

```bash
cd apps/learner
flutter analyze
flutter test
flutter build web --release
```

The generated site is in `apps/learner/build/web` and can be deployed to Vercel as a static SPA.

Android production artifacts are built only by the tagged release workflow with an externally managed signing key. See [Android production releases](docs/ANDROID_RELEASE.md) for the trust model, required GitHub Environment configuration, signer pinning and release process.

## Current milestone

`v0.2` completes the local-first learner foundation: durable learner/review state, local content ingestion and OCR, immutable course installation/versioning, explicit GitHub course updates, portable backup/restore, and a production Android signing/distribution pipeline. See [ROADMAP](docs/ROADMAP.md).

## License

GNU Affero General Public License v3.0. See [LICENSE](LICENSE).
