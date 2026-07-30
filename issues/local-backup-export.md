# Local backup / JSON export

**Status:** open
**Priority:** medium
**Effort:** S

## Context

The app is local-only in v1. If the user's phone is lost, reset, or the app is reinstalled, all ranking data is gone. The eventual Google Sheets sync solves this, but it's a separate large milestone. A simple JSON export to the iOS share sheet would give users a manual escape hatch in the meantime.

## Acceptance criteria

- A "Export all data" action exposed in a settings sheet (which doesn't exist yet — this issue may need to create one) or as a long-press on the lists-home view.
- Export produces a single JSON file containing every `RankList`, `RankItem`, and `ComparisonRecord`, with stable UUIDs and ISO 8601 timestamps.
- The file is offered via `UIActivityViewController` so the user can save to Files, mail it to themselves, or AirDrop it.
- A matching "Import from JSON" action that restores the data, with a confirmation dialog warning about overwriting existing lists.

## Notes

The same JSON shape should be reusable as the Google Sheets schema (one tab per list, with the JSON's columns as headers). Designing the export format once carefully saves rework when sync ships.

Round-trip test: export → wipe app → reinstall → import → verify everything restored. Worth a snapshot or integration test.
