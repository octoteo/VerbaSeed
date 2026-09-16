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

Next v0.2 increments:

- Platform OCR/layout adapters for image imports and scanned PDFs, starting with a local/offline implementation
- Course installation tables separate from raw import jobs
- GitHub update checks with user-controlled upgrades and rollback
- Backup/export/import of learner data and course manifests
- Android project scaffold and release build gate

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
