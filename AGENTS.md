# VerbaSeed Agent Engineering Rules

## Mission

Build VerbaSeed as a reliable local-first learning platform. Prefer durable contracts and end-to-end vertical slices over isolated demos.

## Non-negotiable architecture rules

1. Core study flows must not require an account, paid API, or always-on server.
2. Feature UI must not directly depend on a concrete AI, speech, OCR, sync, or content provider. Depend on contracts/adapters.
3. Imported content must be normalized and validated before becoming an active course.
4. Learning outcomes must be recorded as structured events/state, not inferred only from UI state.
5. Child profiles and raw voice/image material are local by default. Upload requires explicit feature-level opt-in.
6. Do not add copyrighted textbook pages, commercial animation files, paid audio, or unclear re-uploads to the repository.
7. Schema changes require versioning, backwards-compatibility analysis, migration strategy and tests.
8. A network failure must not corrupt local learning state. Remote sync is replication, not the source of truth.

## Quality bar

Every production change should include the smallest relevant automated test. `flutter analyze --fatal-infos`, `flutter test`, and the web release build must pass before merge; warnings such as stale imports are release failures.

Widget tests using Drift/Riverpod streams must fully dispose providers/databases and flush async cleanup. Prefer provider overrides/fakes when the persistence stream itself is not under test; drive expandable/stateful UI into the asserted state before checking hidden children. Pending timers or lifecycle leaks are test failures, not ignorable CI noise.

Avoid unbounded retries, silent exception swallowing, hidden global mutable state, and feature code that writes directly to platform storage.

## UI

Support narrow phones and desktop Web from the same feature implementation. Preserve keyboard accessibility on Web and touch targets on mobile. Do not encode pedagogy solely in color or animation.

## Data and time

Persist timestamps in UTC. Convert to learner locale only at presentation boundaries. Review scheduling must remain deterministic for a given scheduler configuration and event history.

## Dependencies

Prefer mature, actively maintained dependencies with compatible licenses. New dependencies need a concrete capability reason; do not add packages only to save a few lines of code.

## Delivery

Use small PRs with clear acceptance criteria. Keep public schemas and architectural decisions documented alongside code.

Vercel is a release gate, not the inner development loop. Keep docs-only changes skippable, avoid duplicate full Flutter builds for superseded commits, and batch coherent edits before pushing. When deployments queue, validate the newest commit SHA rather than waiting on stale previews. Merge only after the latest commit's required CI and relevant deployment checks pass.

Web releases are build-once/promote-unchanged: GitHub Actions creates and tests `.vercel/output`; the deployment stage must upload that exact artifact and must not rerun Flutter, Drift codegen, analysis, or tests.
