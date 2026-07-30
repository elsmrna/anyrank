# Product Spec — Relative-Ranking iOS App

_Working name: TBD (folder is `anyrank`). Single source of truth for v1 requirements. All decisions below are committed unless explicitly listed under "Open TBDs"._

## 1. Overview

A native iOS app for ranking the things you experience — restaurants, bars, movies, anything — by comparing them against each other rather than rating them on an absolute scale. When you add a new item, the app shows you a small number of items already on your list and asks "which did you prefer?" Your answers locate the new item via a bucket-constrained binary search, and a 0.0–10.0 score is interpolated from where it landed.

The product thesis is that people have an easier time saying "I liked A more than B" than picking a number, and that the resulting list is more honest because it forces direct comparisons rather than letting every item settle around a 7. v1 is single-user and local-only, but the data model and account flow are designed so a Google-backed sync layer can ship later without rebuilding.

## 2. Platform & Tech Stack

The app is native iOS. Language is Swift, UI is SwiftUI, persistence is SwiftData. Minimum deployment target is iOS 18, which lets us use the latest SwiftUI and SwiftData APIs without compatibility shims.

For external lookups, the Restaurants and Bars categories integrate with Google Places (search + place details). Movies integrates with a movie metadata API — TMDB is the recommended choice (free for non-commercial, well-documented, returns IMDB IDs so we can construct IMDB links cleanly). Books integrate with Open Library (free, no API key) for catalog search, with StoryGraph URLs constructed from the result — StoryGraph itself doesn't publish a public API. Custom categories do not use external APIs.

There is no backend in v1. Data lives on-device. The future sync layer will use Google OAuth (the official `GoogleSignIn-iOS` SDK) and Google Sheets as the backing store. The local data model must be designed so each list and item has a stable UUID, all timestamps are tracked, and serialization to a Sheet's row format is straightforward.

## 3. Data Model

The core entities are `List`, `Item`, and `ComparisonRecord`. A `List` belongs to a single `Category`. A list has a UUID, a user-chosen display name, a category type, a created-at timestamp, and a configurable `additionsSinceLastRerankPrompt` counter used by the periodic re-rank prompt. Multiple lists can share the same category — a user could have a "Restaurants — NYC" list and a "Restaurants — Tokyo" list living independently.

Categories are a closed enum at the type level: `restaurants`, `bars`, `movies`, `books`, `custom`. Each predefined category implies a metadata schema. Restaurants and Bars store a Google Places place ID, the canonical name, address, latitude, longitude, and a Google Maps URL. Movies store a TMDB ID, title, release year, and IMDB URL. Books store an author, publication year (reusing the `releaseYear` field on the item), an optional ISBN, and a StoryGraph URL. Custom stores a user-pasted URL plus a list of user-defined text-only key/value metadata fields, where the user can name the fields per-list (so a "Wines" custom list could have "Region", "Vintage", "Grape" fields, all free text).

An `Item` has a UUID, a back-reference to its list, the name shown in the list view, the category-specific metadata payload, free-text notes, an optional date-visited/consumed value, a current `bucket` (Loved / Liked / Fine / Didn't like), a `score` (Double, 0.0–10.0), the count of items in its bucket at the time of its last placement (used for re-normalization), and a created-at timestamp. The `score` is recomputed any time the bucket's membership changes.

A `ComparisonRecord` is a small append-only log of pairwise outcomes — `(itemA, itemB, winner, timestamp)`. We keep this so re-ranks and future re-normalization passes can audit how the list was built, and so a future Sheets sync has full provenance to write back. It is not strictly required for the algorithm to function; it's a write-ahead history for safety.

## 4. Ranking Algorithm

This is the core IP of the app and is specified precisely.

There are four buckets, each with a fixed score range: **Loved** maps to 8.0–10.0, **Liked** to 6.0–7.9, **Fine** to 3.0–5.9, **Didn't like** to 0.0–2.9. Buckets are user-facing in the add and re-rank flows; the score is what's stored and shown in the list.

When the user adds a new item, the flow is:

First, the user picks a bucket — "How was it?" — choosing Loved, Liked, Fine, or Didn't like. This is the only sentiment input from the user; no slider, no number.

Second, the app runs a binary search **constrained to existing items in the chosen bucket**. The new item is presented next to the median item in the bucket, and the user picks the one they prefer. The search recurses on the appropriate half. The maximum number of comparisons is capped at 5; if `log2(bucketSize) <= 5`, the search runs to completion (true binary search). If the bucket is large enough that the cap would be exceeded, the search uses its 5 comparisons greedily on bisection and the remaining ambiguity is resolved in step four below.

Third, after the binary search resolves, a **boundary check** runs if the new item landed at the very top or very bottom of its bucket. If it landed at the top, the app does one additional comparison against the lowest-scoring item in the next-higher bucket; if the new item wins that comparison, it gets promoted to the higher bucket and is inserted at the bottom of that bucket. If it landed at the bottom, the equivalent check runs against the top of the next-lower bucket. Demotion or promotion happens at most once per add — the boundary check does not cascade.

Fourth, if the comparison cap was hit before the search resolved (the search narrowed the position to a range but couldn't pick exactly), the app does one final tie-breaking comparison against a randomly selected item from the unresolved range. The new item is then placed immediately above or immediately below that random item depending on which won. This trades a single extra comparison for a deterministic placement.

Once the position is locked, the score is interpolated. Within a bucket of N items, the i-th ranked item (1-indexed from the top) gets a score of `bucketHigh - (bucketHigh - bucketLow) * ((i - 1) / max(N - 1, 1))`. So in the Loved bucket (range 8.0–10.0), if there are 5 items, the top one is 10.0, the bottom is 8.0, the middle is 9.0. When an item is added or removed from a bucket, every score in that bucket is recomputed by the same formula. Scores in other buckets are unaffected.

A bucket containing fewer than 3 items does not display numeric scores in the list view — the row shows just the item name and the bucket's color accent. This avoids assigning meaningless precision to an item that has only been compared once or zero times. The threshold of 3 is intentional: 2 items can be ordered with a single comparison but the gap between their scores would be nominal; 3 is the smallest size where a score reflects actual relative information.

The `ComparisonRecord` log is appended during step two. The record is written even for the boundary-check and tie-break comparisons.

## 5. User Flows

The home screen lists the user's lists, grouped by category, with the count of items in each. Tapping a list opens its detail view.

The list detail view shows items sorted by score descending. Each row displays the item name, its score (when the bucket has ≥3 items, otherwise omitted), and a small colored accent indicating its bucket — green for Loved, blue for Liked, yellow for Fine, red for Didn't like. Tapping a row opens the item detail view; a primary "+" button in the navigation bar starts the add-item flow.

The add-item flow first asks the user what they're adding — for Restaurants and Bars, an in-app Google Places search; for Movies, a TMDB search; for Custom, a free-text name field plus a paste-link field plus the list's user-defined metadata fields. After the item is identified, the bucket question is shown ("How was it? Loved / Liked / Fine / Didn't like"). After the bucket, the comparison flow begins as specified in section 4. The comparison UI shows the new item on one side and the current comparison candidate on the other — name, link icon, and a "Choose" button under each. After comparisons resolve and the score is computed, the app shows a brief confirmation screen with the final score and bucket, then returns to the list view with the new item visible in its sorted position.

The item detail view shows the item's name, score, bucket, link (tappable, opens in-app browser or out to Maps/IMDB), notes, date visited, and metadata. From here the user can edit any of the metadata or notes (these never trigger a re-rank), or tap "Re-rank" to throw the item back into the comparison flow. Re-ranking discards the item's current bucket and score, asks the bucket question again, runs the comparison flow against the bucket's other items (excluding itself), applies the boundary check, and writes the new score. The re-rank emits new `ComparisonRecord` entries; previous ones are kept for history.

There is no drag-to-reorder anywhere. Rank is determined exclusively by the comparison flow.

After every N additions to a list (N is an open TBD, suggested starting value: 10), the app surfaces a soft prompt the next time the user opens that list: "Want to re-check a few items?" This selects 1–3 items from the list — biased toward items added longest ago — and walks the user through re-ranking them one at a time. The user can dismiss the prompt without consequence.

Items can be deleted from the item detail view. Deleting an item removes it and re-normalizes the scores of remaining items in its bucket.

## 6. Categories & Metadata

For Restaurants, the in-app add flow is a Google Places autocomplete search. The selected place's place ID, display name, formatted address, latitude/longitude, and a Google Maps URL are stored. The link icon in the list view opens the URL in the Google Maps app if installed, otherwise in Safari.

For Bars, the integration is identical to Restaurants — same Google Places autocomplete, same fields, same link behavior. Bars is a separate category from Restaurants because users want them ranked separately.

For Movies, the in-app add flow searches TMDB by title. The selected movie's TMDB ID, title, release year, poster image URL (cached locally), and the corresponding IMDB URL (constructed from the TMDB-provided IMDB ID) are stored. The link icon opens the IMDB page.

For Books, the in-app add flow searches Open Library by title or author. The selected book's title, author, publication year (stored in the same `releaseYear` field Movies uses), ISBN, and a StoryGraph URL are stored. The StoryGraph URL is constructed from the title — StoryGraph itself doesn't publish a search API, so the URL is generated rather than fetched. The link icon opens the StoryGraph page in Safari.

For Custom, the user names the list and defines its metadata schema at list creation time — they pick zero or more text field names (e.g. "Region", "Vintage"). When adding an item, the user types the item name, optionally pastes a URL, optionally fills in each metadata field. All metadata for custom categories is plain text in v1 — no validation, no controlled vocabularies. The link icon, if a URL is present, opens it in Safari.

## 7. Future Roadmap (Non-v1)

Google OAuth sign-in and Google Sheets sync is the next planned milestone. The schema written to the sheet would be one tab per list, with columns for item UUID, name, bucket, score, link, notes, date visited, and any per-category or custom metadata. The sync should be pull-then-push with a clear conflict-resolution rule (local-wins or last-write-wins; design this when we get there).

Social features (Beli-style following, friends' rankings, list sharing) are explicitly deferred but should not be made impossible by v1 architecture. Concretely, this means UUIDs everywhere, no assumptions that the local user is the only author, and a clear separation between "authoring" and "viewing" in the data model.

Photos, tags, and richer metadata for custom categories (number fields, dropdowns) are deferred.

## 8. Open TBDs

Re-rank prompt cadence: the value of N (additions before a periodic re-rank prompt is shown). Suggested 10; revisit after first usage.

App name and branding: working folder is `anyrank`; final name, icon, and color palette pending.

API key sourcing and rate-limit strategy: Google Places billing setup, TMDB API key registration, secure storage of keys (likely a config file excluded from version control plus a build-time injection step).

Local backup/export format: before Sheets sync ships, users have no way to back up their data. Worth shipping a JSON export to share-sheet at a minimum.

Onboarding: first-launch experience, sample lists, empty-state copy. Likely a one-screen explainer plus a "create your first list" CTA.

Comparison-screen visual treatment: how to make the side-by-side comparison feel decisive and fast. Worth a design pass before implementation.
