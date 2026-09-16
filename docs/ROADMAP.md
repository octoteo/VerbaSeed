# VerbaSeed roadmap

## v0.1 — production foundation

- Flutter Android/Web application shell
- Open Course Schema v0.1
- FSRS learning-engine boundary
- Sentence typing vertical slice
- GitHub Actions quality gates
- Vercel production deployment

## v0.2 — local-first learner state (in progress)

Completed foundation:

- Drift/SQLite local source of truth across native and web
- Multiple learner profiles with atomic active-profile switching
- Serializable and persisted FSRS card state plus append-only review events
- Local import-job queue
- Content Source Protocol primitives for camera, PDF, GitHub, web, subtitles and pasted text
- Drift Web worker + sqlite3 WASM build pipeline
- Content-addressed asset store with SHA-256 integrity checks
- Native filesystem asset backend and Web IndexedDB asset backend
- Camera capture plus image/PDF file selection
- GitHub course manifest fetch pinned to resolved commit SHA
- Plain-text Course Compiler draft path
- Document extraction contracts for page ranges, normalized layout blocks and provider adapters
- Persisted document-processing metadata with deterministic bounded retries and interrupted-run recovery
- Local PDF text/layout extraction through a provider adapter
- User-selectable PDF page ranges with bounds validation
- Durable extracted-document artifacts stored in Content Store before import completion
- Text-layer-empty PDF detection for explicit OCR fallback
- Native Android host scaffold with stable application namespace and camera capability declarations
- CI release-APK build gate with downloadable Android artifact
- Offline Google ML Kit text-recognition adapter for image and camera assets on Android/iOS
- Normalized OCR layout blocks with durable extraction artifacts and explicit empty-result review metadata
- Conditional Web stub that keeps unsupported OCR explicit instead of silently using a network service
- Image/camera imports automatically enter the local OCR runner only after the original asset is durable
- Visible OCR platform availability, retry/recovery controls and review-required status in the import experience
- Deterministic extracted-document → Open Course draft compilation with page-preserving lessons
- Local bilingual pairing for adjacent/inline Chinese-English textbook text, target-text de-duplication and noise filtering
- Durable course-draft JSON assets written only after document extraction is durable
- Course-draft metadata with item/lesson counts, warnings and explicit review state without requiring an AI API
- Local course-draft review page with editable course title, English text and Chinese translation
- Removal of OCR false-positive learning items before a course can be accepted
- Immutable reviewed course revisions written back to Content Store instead of mutating prior draft artifacts
- Explicit human-accepted draft state that clears review flags without installing a course implicitly
- Versioned installed-course tables separated from transient import jobs and accepted drafts
- Immutable installed-course version history referencing content-addressed course artifacts
- Per-learner course enrollment separate from device-wide course installation
- Accepted-draft installation service that idempotently seeds FSRS review cards for the selected learner
- Installed-course library UI with explicit pending-draft installation controls
- Existing installed courses can be enrolled into additional learner profiles from the local library

Next v0.2 increments:

- Render text-layer-empty PDF pages and feed them through the same OCR provider
- Add installed-course version switching and rollback controls
- GitHub update checks with user-controlled upgrades and rollback
- Backup/export/import of learner data and course manifests
- Production Android signing and release-distribution workflow

## v0.3 — early learning content

- Phonics progression
- Decodable stories
- Animation/provider integration without redistributing copyrighted media
- Listening and repeat activities

## v0.4 — local speech runtime

- Offline ASR/TTS runtime
- Pronunciation assessment
- British/American pronunciation assets

## v0.5 — adaptive planner

- Knowledge graph
- Weak-skill detection
- Activity selection based on learner history and FSRS state

## v1.0 — production learning system

- End-to-end preschool + primary-school English learning flow
- Stable course protocol and migration policy
- Backup/restore and device migration
- Accessibility, observability and failure recovery
- Android release pipeline and production PWA
