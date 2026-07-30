# Comparison screen visual design pass

**Status:** closed
**Closed:** Vertical-stack layout with thumbnails, secondary text, and "Comparison N of ~M" step estimate shipped. Places photos deferred — tracked separately in `issues/live-places-photos.md`.
**Priority:** medium
**Effort:** M

## Context

`ComparisonScreen.swift` worked functionally — two side-by-side cards, tap the preferred one — but the visual treatment was plain and users saw it dozens of times per list. It deserved more thought than the boilerplate it originally was.

## What landed

Layout switched from side-by-side to a **vertical stack** — new item on top, "vs" divider, opponent on bottom. Bottom card sits in the thumb zone for one-handed use; the top card is a small stretch. Each card is a horizontal composition of thumbnail (56×80, poster-aspect) + name + one-line secondary text. Whole card is the tap target.

**Thumbnails** wired for Movies (TMDB poster via `posterURLString`) and Books (Open Library cover via `coverURLString`). Places and Custom render a category-neutral placeholder. `AsyncImage` handles loading/failure with no extra state.

**Secondary text** populated per category by `RankingApplier.comparisonSecondaryText(for:in:)`: year for movies, "author · year" for books, address for places. Nil when there's nothing useful to say (custom items without an address).

**Step estimate.** New `RankingSession.estimatedTotalRounds` computed as `ceil(log2(bucketCount + 1)) + 1` — approximate but honest. Round label shows "Comparison 2 of ~3" during binary search, swaps to "Tie-break" or "Bucket boundary check" during those phases so the user knows what kind of question they're answering.

**Round transitions** use an asymmetric slide+fade keyed on opponent ID, so each new round reads as a distinct question. This was the underlying UX issue behind users tapping NEW twice by reflex.

`RankingSession.ItemRef` gained `imageURLString` and `secondaryText` fields so the snapshot carries the display data — the comparison screen doesn't need to look up the original `RankItem`.

## What deferred

Google Places photos on Restaurants/Bars cards. Would need an extra `GMSPlacesClient.lookUpPhotos` call per result (billed separately) plus a photo cache. Not worth the complexity while the rest of the UX pass was landing. Tracked in `issues/live-places-photos.md`.

## Notes

The `kindLabel` subtitle from the previous iteration ("checking the bucket boundary", "breaking a tie") is preserved — still shown under the cards when applicable, since users benefit from knowing why a "one more" question appeared after the binary search "finished."

Beli's reference pattern was the direct inspiration for the vertical stack. On very tall phones the whole thing lives comfortably in the top two-thirds of the screen; the add-item safe-area button doesn't overlap the cards.
