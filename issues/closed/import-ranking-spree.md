# Import a collection and rank it as a resumable queue

**Status:** closed
**Priority:** high
**Effort:** L
**Closed:** 2026-09-30 — commit 9cf527c (`AnyRank/Import/`, `AnyRank/Views/Import/`)

## Context

Users with an existing corpus (a Steam library, a Letterboxd diary, a Goodreads shelf) shouldn't add things one at a time. Earlier import notes (`import-pattern.md`, `import-storygraph.md`, `import-movies.md`) assumed a source's star ratings would map straight into buckets. That skips the product's whole thesis — comparison beats rating — so this design treats the corpus as a **queue** that the user works through with the normal compare flow, at their own pace.

## What shipped

- **Generic pipeline:** source → candidates (`ImportCandidate`) → `ImportMatcher.plan` against a target list (new or existing) → persisted `ImportSession` queue → `RankingSpreeView`.
- **Dedupe** against the target list, its existing queue, and within the export: strong IDs (source URL, TMDB ID, ISBN, place ID, Spotify link) or normalized names with compatible years (and matching addresses for places).
- **Sources:** Steam ("Sign in with Steam" via OpenID in a system web-auth sheet, or a profile link; most-played first, "skip never-played" toggle; sample library without the app's key), Letterboxd (whole export .zip or any CSV, merged per film), IMDb (ratings, lists, watchlist; exact TMDB `/find` by IMDb ID), Goodreads / StoryGraph CSV exports (rating → *suggested* bucket, dates, reviews), and a pasted list for any category. Each file source has phone-oriented export steps with "Open export page" links, and files are recognized by their headers whichever source was picked.
- **Spree:** each item goes through bucket pick → comparisons, auto-advancing. "Skip for now" (to the back), "Not this one" (dropped). Pause = close the sheet; placed items are already saved and the queue persists across launches (`imports.json`, local only, not synced).
- **Resuming:** Home cards show "N to rank"; the list shows a progress card with up-next covers and "Continue ranking · N left" as the primary action. Opening a just-created import starts the spree automatically.
- **Abandon import** (list card menu): discards every un-ranked item; ranked ones stay. Deleting a list abandons its import.
- **Just-in-time enrichment:** queued items without artwork (Letterboxd rows, pasted titles) are looked up with the category's search service as they come up — exact normalized-title matches only.

## Follow-ups

- Verify the Letterboxd / IMDb / Goodreads / StoryGraph parsers and the export-page links against real exports and accounts; they were written from the documented formats, not samples. (StoryGraph's `/user-export` URL is the least certain.)
- Confirm the Steam OpenID round-trip with a real account; Steam accepts the `anyrank://` return_to and shows its login page, but the redirect back hasn't been exercised end to end.
- More sources worth the same treatment: Trakt, Backloggd, Spotify saved albums (OAuth), Google Maps saved places.
- Steam needs one developer Web API key in `Secrets.xcconfig` (`STEAM_WEB_API_KEY`) — users never see it, and sign-in uses Steam OpenID. Before shipping widely, move the key behind a small server-side proxy (as for the other embedded API credentials) so it can't be extracted from the binary.
- Steam only exposes libraries with Game details set to Public; the import explains this and links to the setting. There's no third-party API for private libraries.
- Enrichment for Steam games via IGDB (year, platforms) — Steam art is already present, so it's cosmetic.
