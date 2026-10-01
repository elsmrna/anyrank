# Import a collection and rank it as a resumable queue

**Status:** closed
**Priority:** high
**Effort:** L
**Closed:** 2026-09-30 — `AnyRank/Import/`, `AnyRank/Views/Import/` (no commit; repo not under git yet)

## Context

Users with an existing corpus (a Steam library, a Letterboxd diary, a Goodreads shelf) shouldn't add things one at a time. Earlier import notes (`import-pattern.md`, `import-storygraph.md`, `import-movies.md`) assumed a source's star ratings would map straight into buckets. That skips the product's whole thesis — comparison beats rating — so this design treats the corpus as a **queue** that the user works through with the normal compare flow, at their own pace.

## What shipped

- **Generic pipeline:** source → candidates (`ImportCandidate`) → `ImportMatcher.plan` against a target list (new or existing) → persisted `ImportSession` queue → `RankingSpreeView`.
- **Dedupe** against the target list, its existing queue, and within the export: strong IDs (source URL, TMDB ID, ISBN, place ID, Spotify link) or normalized names with compatible years (and matching addresses for places).
- **Sources:** Steam (Web API, most-played first, "skip never-played" toggle; sample library without a key), Letterboxd / Goodreads / StoryGraph CSV exports (rating → *suggested* bucket, dates, reviews), and a pasted list for any category.
- **Spree:** each item goes through bucket pick → comparisons, auto-advancing. "Skip for now" (to the back), "Not this one" (dropped). Pause = close the sheet; placed items are already saved and the queue persists across launches (`imports.json`, local only, not synced).
- **Resuming:** Home cards show "N to rank"; the list shows a progress card with up-next covers and "Continue ranking · N left" as the primary action. Opening a just-created import starts the spree automatically.
- **Abandon import** (list card menu): discards every un-ranked item; ranked ones stay. Deleting a list abandons its import.
- **Just-in-time enrichment:** queued items without artwork (Letterboxd rows, pasted titles) are looked up with the category's search service as they come up — exact normalized-title matches only.

## Follow-ups

- Verify the Letterboxd / Goodreads / StoryGraph parsers against real export files; they were written from the documented column names, not a sample.
- IMDb ratings CSV (`import-movies.md`).
- More sources worth the same treatment: Trakt, Backloggd, Spotify saved albums (OAuth), Google Maps saved places.
- Steam needs a Web API key in `Secrets.xcconfig` (`STEAM_WEB_API_KEY`). A shipping app would proxy this server-side or use Steam OpenID instead of a per-build key.
- Enrichment for Steam games via IGDB (year, platforms) — Steam art is already present, so it's cosmetic.
