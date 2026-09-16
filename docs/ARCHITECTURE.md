# Architecture

VerbaSeed is structured as a local-first modular monolith. The learner app owns presentation and orchestration; reusable capabilities live in packages with explicit contracts.

## Architectural invariants

1. **Core learning must work offline.** Network services are optional enhancements, never the only path to learn.
2. **Content is normalized before learning.** Every source passes through a compiler into the Open Course model.
3. **Learning decisions are data-driven.** Activity outcomes update learner state; scheduling is performed by the learning engine.
4. **AI is behind a gateway.** Local models, Ollama and OpenAI-compatible providers are interchangeable adapters.
5. **Speech is behind a runtime boundary.** ASR, TTS and pronunciation engines can vary by platform without leaking into domain logic.
6. **Children do not require internet accounts.** Learner identity is a local profile by default.
7. **Copyright provenance is explicit.** Course metadata carries source and licensing information; the official registry only indexes redistributable content.

## Runtime layers

```text
Flutter UI
   |
Application / feature coordinators
   |
Domain contracts
   |-- course_schema
   |-- content_source
   |-- document_processing
   |-- learning_engine
   |-- learner_model (planned)
   |-- exercise_engine (planned)
   |
Infrastructure adapters
   |-- local_store (SQLite / OPFS)
   |-- content_store (filesystem / IndexedDB)
   |-- pdf_extractor_pdfrx (local PDF text/layout)
   |-- OCR extractors (platform adapters, planned)
   |-- speech_runtime
   |-- ai_gateway
```

`document_processing` owns provider-neutral extraction requests/results, page ranges, normalized layout blocks and the retry state machine. It does not select a concrete OCR/PDF engine. Processing timestamps are explicit inputs and retries use bounded deterministic backoff, so recovery decisions can be reproduced in tests and after an app restart.

`pdf_extractor_pdfrx` is the first concrete document adapter. It extracts an existing PDF text layer and fragment geometry locally. The application coordinator persists the `extracting` state before invoking it, writes the normalized extraction result to the content-addressed Content Store, and marks the import successful only after that result is durable. PDFs without usable text are marked for the OCR fallback rather than being silently treated as successfully understood.

## Reliability model

The application treats the local device as the source of truth for core learning data. Future cloud sync is replication, not ownership. Writes are durable locally before any optional remote synchronization is acknowledged.

Persistence rules:

- SQLite transactions for learner progress, reviews and course metadata;
- append-only review events where practical;
- schema migrations are forward-only and tested against fixtures;
- import jobs are staged and validated before replacing active course state;
- original imported assets are content-addressed and integrity-checked outside SQLite;
- normalized extraction artifacts are stored outside SQLite and referenced by content-addressed metadata;
- document-processing state is stored with import metadata, including attempt count and retry eligibility;
- processing state is persisted before provider work so a crash cannot masquerade as success;
- interrupted extraction runs transition back through a bounded retry schedule instead of retrying forever;
- retryable and permanent provider failures remain distinct;
- remote content is cached with integrity hashes and provenance metadata;
- AI output is never accepted as canonical course data without schema validation.

## Availability

Core learning has no server availability dependency. Hosted Web deployments are static and CDN-distributed. Optional APIs must fail open to local capabilities: loss of an AI, speech or sync provider degrades only that enhancement.

## Scaling

The primary scaling strategy is edge/static delivery plus on-device execution. Central compute is reserved for explicitly enabled services. This reduces operating cost and removes a central bottleneck for ordinary learning sessions.
