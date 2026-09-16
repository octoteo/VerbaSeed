# ADR-0006: Local persistence uses Drift/SQLite

Status: Accepted

## Context

VerbaSeed must work without an account, preserve multiple learner profiles, retain FSRS state across sessions, and behave consistently on Android and Web. Browser storage also needs a safe fallback when OPFS is unavailable.

## Decision

Use Drift 2.35 with SQLite as the local source of truth. Native Flutter platforms use the Drift native runtime. Flutter Web uses sqlite3 WebAssembly plus Drift's worker runtime, preferring OPFS and falling back to IndexedDB when browser capabilities require it.

The database currently owns learner profiles, serialized FSRS card state, append-only review events, and import-job metadata. Course binaries and large user media are intentionally not stored as SQLite blobs in this phase.

Vercel serves the Drift worker and sqlite3 WASM asset generated from the exact dependency versions resolved during the build. The web deployment enables COOP/COEP headers so compatible browsers can use the stronger OPFS implementation.

## Consequences

- Core learner state remains local and usable without an account or cloud API.
- Review events can later support analytics, migration, backup, and model recalibration.
- Schema migrations become a production contract and must be covered by tests before schemaVersion changes.
- Large PDF/image/video assets require a separate content-store abstraction rather than unbounded database blobs.
- If COOP/COEP conflicts with a future external media provider, the media integration must be tested explicitly; Drift can fall back to IndexedDB if these headers are relaxed.
