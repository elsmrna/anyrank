# Wire up live book search (Open Library + StoryGraph URL construction)

**Status:** closed
**Closed:** Open Library-backed search shipped with slug-optimistic StoryGraph URL construction and cover-art URLs. See `AnyRank/Services/LiveBookSearchService.swift`; `BookSearchResult`/`RankItem` carry a new `coverURL` field.
**Priority:** medium
**Effort:** M

## Context

`LiveBookSearchService.swift` was a stub. The app used `MockBookSearchService` with a hand-picked set of recognizable books. Real search was needed before the Books category was more than a demo.

StoryGraph does not publish a public read API, so the integration shape uses Open Library as the catalog and constructs StoryGraph URLs from the result.

## What landed

`LiveBookSearchService` calls `https://openlibrary.org/search.json?q=…&fields=key,title,author_name,first_publish_year,isbn,cover_i&limit=15` and maps each hit into a `BookSearchResult`. First-author-first-ISBN heuristic per the acceptance criteria.

StoryGraph URLs are constructed slug-optimistically from the title: lowercase, strip non-alphanumerics, join whitespace with hyphens → `https://app.thestorygraph.com/books/<slug>`. When the slug ends up empty (all-punctuation titles), fall back to the browse URL keyed on the raw title. No HEAD-check to verify the slug — the acceptance criteria explicitly accepted occasional 404s as the cost of avoiding an extra round trip.

Cover URLs come from `https://covers.openlibrary.org/b/id/<cover_i>-L.jpg`. Both `BookSearchResult.coverURL` and `RankItem.coverURLString` carry them; the CSV codec gained a `cover_url` column so covers round-trip through persistence + Sheets sync.

`AnyRankApp` injects `LiveBookSearchService()` unconditionally — no API key is required. The mock stays wired into previews and tests via environment injection.

## Notes

Open Library has no rate limit for non-commercial use and no API key. That's why it's the primary source even though the spec named StoryGraph — Goodreads would be the obvious alternative but their API is deprecated.

The "fall back to StoryGraph browse URL" path is a deliberate compromise. Slug URLs work most of the time; a proper fix would need an ISBN→StoryGraph-slug map that neither party publishes. Permanent until StoryGraph ships an API.
