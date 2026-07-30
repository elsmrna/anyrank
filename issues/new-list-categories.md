# Additional predefined list categories

**Status:** open
**Priority:** medium
**Effort:** M per category

## Update — Books landed

The Books category shipped, with mock data backing the in-app search initially. The live integration (Open Library catalog + constructed StoryGraph URLs) landed subsequently; see `closed/live-storygraph.md`. The pattern proved out cleanly — adding a new category was contained to `Category`, `RankItem`'s optional fields, `ListCSVCodec`'s column list, a service protocol + mock + stub, a search screen, `ItemSearchScreen` dispatch, `ItemDetailView`'s metadata section, `ItemRow`'s secondary-text helper, `StagedItem`'s apply mapping, and a `PreviewSupport` seed. About 250 lines of additions across ~10 files. Future categories follow the same template.

## Context

v1 ships with Restaurants, Bars, Movies, Books, plus the Custom escape hatch. The original product discussion (Spec § 1) called out each of these and the framework is built to make additions cheap: each new category needs a `Category` case, optional metadata fields on `RankItem`, a search service protocol + mock + live implementation, and a small per-category search screen. Everything else (ranking, scoring, list views, item detail) inherits for free.

## Acceptance criteria (per new category)

- New `Category` case added to `Category.swift` with display name and SF Symbol icon.
- Per-category metadata fields added to `RankItem.swift` as optionals.
- A search service protocol and mock implementation under `AnyRank/Services/`.
- A search screen under `AnyRank/Views/AddItem/` modeled on `MovieSearchScreen.swift`.
- `ItemSearchScreen.swift` dispatches the new case.
- `ItemDetailView.swift`'s metadata section handles the new case.
- `PreviewSupport.swift` seeds a sample list for the new category.
- `StagedItem.swift` extended with the new fields and the `apply(to:)` mapping updated.

## Candidates

- **Books — Open Library + StoryGraph URL** (shipped). See `closed/live-storygraph.md`.
- **Music (Albums + Songs) — Spotify** (shipped). See `closed/music-albums-and-songs.md`.
- **Anime — AniList** (shipped). See `closed/category-anime.md`.
- **Video games — IGDB** (shipped). See `closed/category-video-games.md`.
- **Board games — BoardGameGeek.** Title, year, player count range. BGG has an XML API. Not tracked separately yet.
- **TV shows — TMDB.** TMDB already handles movies; their `/search/tv` endpoint reuses the same auth. Could be a sub-category under Movies or its own thing. Not tracked separately yet.
- **Hotels / places to stay — Google Places.** Same SDK as restaurants/bars, different `kind`. Not tracked separately yet.
- **Manga — AniList / MAL** — related to Anime but different unit of ranking (chapters). Not tracked separately yet.

## Notes

The Custom category is the pressure relief — anything not on this list can still be ranked. Predefined categories exist for two reasons only: rich metadata (search, links) and a polished add experience. Don't add categories that don't clear that bar; a generic Books category with paste-a-link is no better than Custom.

Order of work: Books shipped first. Albums (Spotify or MusicBrainz) is the natural second, since the metadata shape (title + artist + year + cover) is almost identical to Movies and the consent flow is already proven by Google sign-in. After that, evaluate whether the abstraction is still holding up. Each new category compounds in surface area — keep the bar high.

Each integration also needs a per-category live issue when picked up, similar to the now-closed `closed/live-google-places.md`, `closed/live-tmdb.md`, and `closed/live-storygraph.md`.
