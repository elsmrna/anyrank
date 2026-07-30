# Import book lists from StoryGraph

**Status:** open
**Priority:** medium
**Effort:** M

## Context

Users who already track books on StoryGraph shouldn't have to re-add their read list one at a time. StoryGraph offers a CSV export from account settings — one row per book with title, author, ISBN, star rating (0–5), status (read / currently reading / to-read), date read, review, and a few tags.

The import shouldn't try to *sync* with StoryGraph — that's a bigger commitment and StoryGraph has no read API. This is a one-time (or occasional, on-demand) migration: the user uploads their StoryGraph export, we build a Books list from the "read" rows, mapping star ratings to buckets.

## Acceptance criteria

- New Settings action: **Import from StoryGraph** — opens a document picker for a `.csv` file.
- Parser tolerant of StoryGraph's actual export shape (which uses a header row, commas inside quoted fields, occasional missing values in optional columns).
- Only rows with `Read Status: read` become items. `to-read` and `currently-reading` are ignored (open a future "wishlist" concept later if desired).
- Star rating → bucket mapping:
  - 5 stars → Loved
  - 4 stars → Liked
  - 3 stars → Fine
  - 1–2 stars → Didn't like
  - Unrated → user picks a target bucket at import time (one bucket for all unrated rows, or "skip unrated").
- Each imported item's `dateConsumed` set from the CSV's `Date Read` when present.
- `notes` populated from the CSV's `Review` when present.
- Within a bucket, items are inserted in the order they appear in the CSV (StoryGraph exports date-read desc by default) so subsequent re-ranks can refine the order. Score renormalization happens automatically via existing `ScoreInterpolation.renormalize`.
- Preview screen before commit: shows import summary — N books, distribution across buckets, any rows skipped and why. User confirms before the list is created.
- New list gets a default name ("Imported from StoryGraph — YYYY-MM-DD") that the user can rename.

## Notes

The star-to-bucket mapping is opinionated. Some users only rate the extremes; the "Fine" bucket may be sparse. That's OK — comparisons on subsequent adds will refine order within any bucket as it grows.

StoryGraph's export includes `ISBN/UID` for most rows — worth carrying over to `RankItem.isbn` so the item's StoryGraph URL and Open Library cover can be resolved after import (via `LiveBookSearchService`'s existing URL construction). Cover art won't be in the CSV; lazy-fetch it once the item is on-screen.

This design intentionally doesn't handle re-importing a superset export later (merging vs replacing) — v1 always creates a new list. If the user wants to merge, they can rename and copy items manually. Follow-up if this becomes a pain point.

Same pattern applies to Goodreads CSV imports (their export format is nearly identical). Worth generalizing later; see `issues/import-pattern.md`.
