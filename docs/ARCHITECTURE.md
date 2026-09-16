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
   |-- learning_engine
   |-- learner_model (planned)
   |-- exercise_engine (planned)
   |
Infrastructure adapters
   |-- local_store (SQLite / OPFS)
   |-- content_source
   |-- speech_runtime
   |-- ai_gateway
```

## Reliability model

The application treats the local device as the source of truth for core learning data. Future cloud sync is replication, not ownership. Writes are durable locally before any optional remote synchronization is acknowledged.

Planned persistence rules:

- SQLite transactions for learner progress, reviews and course metadata.
- append-only review events where practical;
- schema migrations are forward-only and tested against fixtures;
- import jobs are staged and validated before replacing active course state;
- remote content is cached with integrity hashes and provenance metadata;
- AI output is never accepted as canonical course data without schema validation.

## Availability

Core learning has no server availability dependency. Hosted Web deployments are static and CDN-distributed. Optional APIs must fail open to local capabilities: loss of an AI, speech or sync provider degrades only that enhancement.

## Scaling

The primary scaling strategy is edge/static delivery plus on-device execution. Central compute is reserved for explicitly enabled services. This reduces operating cost and removes a central bottleneck for ordinary learning sessions.
