# ADR 0005 — Persistence: shared_preferences + sqflite, corruption-safe

* Status: Accepted
* Date: 2026-10-13

## Context

We persist user settings (theme, default formats, quality, export destination, privacy) and
conversion history / queue recovery records. The prompt requires handling corrupted settings
gracefully.

## Decision

* **Settings** → `shared_preferences` behind `SettingsStore`
  (`SharedPreferencesSettingsStore`), which reads each key through a typed, defaulted accessor.
  Unknown, malformed or out-of-range values fall back to the documented default and are
  re-written.
* **History** → `sqflite` (`conversion_history.db`, table `history`) with a schema version and
  transactional writes.
* **Queue recovery** → the unfinished queue is mirrored to a small JSON file
  (`conversion_queue.json`) through `FileQueueStore`. A missing or corrupt file yields an empty
  queue instead of a crash, and a failed write never interrupts a conversion.

## Rationale

Settings are small and read on every launch → key/value storage is ideal. History grows without
bound and needs querying (recent, by status, by source) → SQL is appropriate.

## Consequences

* No user credentials or media content are stored in the database — only file paths, formats,
  sizes, timestamps and status.
* On corruption the affected store is recreated (or, for the queue snapshot, ignored) rather than
  crashing the app.
