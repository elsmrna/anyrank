# Anime category (MyAnimeList / AniList)

**Status:** closed
**Closed:** Shipped. `Category.anime` case, `RankItem` gained `animeFormat`/`episodeCount`/`aniListURLString`, live search via `LiveAniListSearchService` (GraphQL, no auth), search screen, detail metadata, CSV round-trip, preview seed.
**Priority:** low
**Effort:** M

## Context

Anime deserved its own category rather than living under Movies — the unit of ranking is usually a series, not a film, and the metadata shape (episode count, seasons, studio) differs enough that overloading Movies would be lossy.

## What landed

- `Category.anime` case with SF Symbol `tv` icon.
- `AnimeSearchResult` carries id (AniList media id), display title (English preferred, romaji fallback), alternate titles for item detail, format, seasonYear, episodeCount, cover URL, AniList URL.
- `LiveAniListSearchService` posts one fixed GraphQL query per search to `https://graphql.anilist.co` — no auth required. `MockAnimeSearchService` supplies 6 canned entries for previews and offline dev. `AnyRankApp` injects the live service unconditionally.
- Title picking prefers English, falls back to romaji, then native. The two not-picked variants become `alternateTitles` so item detail can show them.
- Comparison card renders the cover via the existing `imageURLString` plumbing. Secondary text is `year · N eps` (only shows fields that are populated).
- CSV codec gained `anime_format`, `episode_count`, `anilist_url` columns.
- `PreviewSupport.animeRepository()` seeds a mixed TV/Movie list spanning two buckets.

## Notes

Cover URLs come from AniList's CDN and are stable enough to store on the `RankItem` — no need to re-fetch. `RankItem.coverURLString` is now shared across Books and Anime, and will pick up Music and Games when those land.

Manga (chapters, ongoing/completed) is a related-but-different unit of ranking. Punted; open a separate issue if it comes up.

TV shows generally (Trakt/TVDB/TMDB-TV) is a separate ask, not covered here.
