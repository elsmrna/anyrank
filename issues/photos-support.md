# Per-item photos

**Status:** deferred
**Priority:** low
**Effort:** M

## Context

Beli lets users attach photos to a ranked restaurant — often a dish, a menu, or the room. We deferred this for v1 because it adds storage, a picker, a gallery, and meaningful design work. The decision is on file in Spec § 7.

## Acceptance criteria

- Users can attach one or more photos to a `RankItem`.
- Photos stored efficiently — `PHPickerViewController` for selection, on-device file storage referenced by URL on the model (not raw `Data` blobs in SwiftData).
- Photo gallery view on the item detail screen.
- Photos respected by the JSON export / Sheets sync (likely as Drive file links rather than embedded image data).
- Privacy: photos never leave the device unless sync is enabled.

## Notes

Storage strategy matters here. Storing image data in SwiftData would bloat the store; storing as files under the app sandbox with a path reference is cleaner and matches iOS conventions.

For Sheets sync, photos can't really live in cells. The realistic path is: upload to user's Drive (separate folder per list), store the Drive file ID in the Sheet, render the photo by fetching it back. That's coupled to the Sheets sync milestone — hold this feature until that's done.
