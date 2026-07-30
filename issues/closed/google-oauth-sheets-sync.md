# Google OAuth + Google Sheets sync

**Status:** closed
**Closed:** Sign-in and Sheets sync both landed. See `AnyRank/Auth/` for the auth layer (`AuthSession`, `GoogleAuthDriver`, `MockAuthDriver`) and `AnyRank/Sync/` for the sync layer (`SyncCoordinator`, `GoogleSheetsClient`, `SheetsIndexCodec`). Local persistence is in `AnyRank/Storage/` (`Repository`, `FileListStorage`, `ListCSVCodec`, `CSV`).
**Priority:** medium
**Effort:** L

## Context

Spec § 2 and § 7 committed to Google Sheets as the eventual backing store, with Google OAuth for sign-in. The work shipped in two passes — sign-in first, then sync — and the result mirrors the spec closely.

## What landed

The local store is one CSV file per list (`<uuid>.csv` plus `<uuid>_comparisons.csv`) under Application Support, with a top-level `index.json` carrying list-level metadata (category, custom field names, re-rank threshold). `Repository` is the in-memory source of truth and owns the persistence and sync hooks.

The synced spreadsheet mirrors that layout exactly. Each list becomes a tab (the tab name is the list's display name). Each list's comparison log becomes a `<list-name>_comparisons` tab. A single `_index` tab — the cloud analogue of the local `index.json` — carries per-list metadata so a pulled list can be reconstructed with the right category and custom field names. Custom field names are JSON-encoded into the `_index` row's cell so user-chosen names containing commas or quotes survive round-trips.

Sync is opt-in via a toggle in `SettingsView`. Enabling sync requests the additional `drive.file` and `spreadsheets` OAuth scopes (the v1 sign-in only requested `profile` and `email`). On first enable, `SyncCoordinator` creates the "AnyRank Data" spreadsheet in the user's Drive via the Sheets v4 API, stores the spreadsheet ID in `UserDefaults` keyed by the user's email, and pushes every existing list. Subsequent changes go through a 2-second debounce that coalesces rapid edits into one push cycle; backgrounding the app force-flushes any pending pushes via `SyncCoordinator.flushNow()`.

The sync model is **local-primary, Sheet-as-backup, one-way push**. Local is always the source of truth at read time — the app reads its lists from the local CSV store, never from the Sheet. Writes push to the Sheet via the debounced path and the background flush. Pull only fires when the local store is empty (a fresh install, reinstall, or wiped storage), as a recovery seed from the Sheet. The Sheet is otherwise a write destination, not a read source. Concurrent edits to the Sheet outside the app — direct browser editing, edits on another device — will be overwritten by the next push and are explicitly not supported.

## Notes

The Sheets schema is documented implicitly via `ListCSVCodec.swift` and `SheetsIndexCodec.swift`. Worth promoting that into a dedicated `docs/sheets-schema.md` if external consumers ever appear.

Edit-in-Sheets works today as a one-way road: the user edits the spreadsheet, then on next app launch the pull picks up the changes (if the local store is empty). True bidirectional editing needs the merge work in the follow-up issue.
