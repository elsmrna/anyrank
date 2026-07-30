# Show Google Places photos on comparison cards

**Status:** open
**Priority:** low
**Effort:** S

## Context

The comparison screen redesign (see `closed/comparison-screen-design.md`) added thumbnails for Movies (TMDB posters) and Books (Open Library covers). Restaurants/Bars/Custom-with-Maps cards fall back to a neutral placeholder because Google Places photos aren't wired up.

Adding them makes the comparison meaningfully more visual for the categories users interact with most.

## Acceptance criteria

- Extend `PlaceSearchResult` with an optional `photoReference: String` (or first-photo URL) populated during `LivePlacesSearchService.fetchDetails(placeID:)` — requires adding `.photos` to the `GMSPlaceField` fetch list.
- Resolve the photo reference into a `URL` via `GMSPlacesClient.lookUpPhotos` (async, one extra SDK call per result). Cap the width at ~200px so the thumbnail size doesn't cost full-resolution image quota.
- Store the resulting URL string on `RankItem` (new field, plumbed through `StagedItem.apply` and the CSV codec) so it round-trips through persistence + Sheets sync.
- Populate `RankingSession.ItemRef.imageURLString` from that field in `RankingApplier.comparisonImageURLString(for:in:)` for the Restaurants/Bars/Custom cases.
- Cache resolved photo URLs so scrolling a long list doesn't re-fetch. `URLCache.shared` handles this at the HTTP layer if we set caching headers appropriately, but Places' image URLs are signed and short-lived — so cache the resolved URL keyed on the photo reference, not the image bytes.

## Notes

Places photos have a per-request cost like every other Places call. The fan-out is already capped at 8 detail fetches per search (see `LivePlacesSearchService`); adding `lookUpPhotos` on the same 8 doubles that per-search cost. Consider fetching the photo lazily only when the item lands on a comparison card, rather than eagerly at search time.

Custom Maps-linked lists also benefit from this — they share the same `PlaceSearchResult` shape.
