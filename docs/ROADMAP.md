# VerbaSeed roadmap

## v0.1 — production foundation

- Flutter Android/Web application shell
- Open Course Schema v0.1
- FSRS learning-engine boundary
- Sentence typing vertical slice
- GitHub Actions quality gates
- Vercel production deployment

## v0.2 — local-first learner state (in progress)

- Drift/SQLite local source of truth across native and web
- Multiple learner profiles with atomic active-profile switching
- Serializable and persisted FSRS card state plus append-only review events
- Local import-job queue
- Content Source Protocol primitives for camera, PDF, GitHub, web, subtitles and pasted text
- GitHub source validation and raw manifest resolution
- Plain-text Course Compiler draft path
- Drift Web worker + sqlite3 WASM build pipeline

Next v0.2 increments:

- Durable large-file content store for PDF/image bytes
- Camera and file picker adapters
- OCR/layout extraction boundary and deterministic import retries
- GitHub course manifest fetch, validation, version pinning and update checks
- Backup/export/import of learner data

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
