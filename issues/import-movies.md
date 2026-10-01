# Import movie lists from IMDB or Letterboxd

**Status:** open
**Priority:** medium
**Effort:** M

**Progress (2026-09-30):** Letterboxd shipped via the import queue (`closed/import-ranking-spree.md`) — ratings suggest a bucket, posters fill in from TMDB as each film comes up. IMDb remains: add an `ImportSourceKind.imdb` case and a parser in `FileImporters`, using the `tt…` ID for a TMDB `/find` lookup.

## Context

Same shape as the StoryGraph import for Books, but for movies. Two realistic sources:

- **IMDB** — logged-in users can export ratings (`https://www.imdb.com/user/<uid>/ratings/export`) and watchlists as CSV. Columns include title, IMDB ID (`tt…`), year, rating (1–10), rated date, title type.
- **Letterboxd** — very common tracking app for movies with a clean CSV export from account settings. Star ratings 0.5–5 in 0.5 increments, plus watched date and short reviews.

Both exports produce CSVs. Different rating scales, otherwise the same shape. Users who track their movies at all almost certainly track them in one of these two.

## Acceptance criteria

- New Settings action: **Import from IMDB** and **Import from Letterboxd** — separate menu items since the CSVs differ enough to warrant a small per-source parser.
- IMDB rating (1–10) → bucket:
  - 9–10 → Loved
  - 7–8 → Liked
  - 5–6 → Fine
  - 1–4 → Didn't like
- Letterboxd rating (0.5–5) → bucket:
  - 4.5–5 → Loved
  - 3.5–4 → Liked
  - 2.5–3 → Fine
  - 0.5–2 → Didn't like
- IMDB rows carry an IMDB ID directly — use it to construct the item's `imdbURLString` immediately and, in a follow-up pass, look up the TMDB ID via `/find/{external_id}?external_source=imdb_id` so posters populate.
- Letterboxd rows carry the film title + year + Letterboxd URL; use those to search TMDB for the poster + TMDB ID.
- Unrated / diary-only rows: user picks a target bucket at import time (like StoryGraph).
- Watched date → `RankItem.dateConsumed`; reviews → `notes`.
- Preview screen before commit — N films, distribution across buckets, TMDB-match rate ("posters found for 92% of rows"), skipped rows and why.
- Default list name "Imported from IMDB — YYYY-MM-DD" or "Imported from Letterboxd — YYYY-MM-DD".

## Notes

The TMDB lookup pass is potentially slow for large exports (Letterboxd users often have 1000+ films). Do it in the background with progress; import can proceed with placeholder posters and backfill as lookups complete.

For IMDB the `tt…` ID is authoritative — `/find/?external_source=imdb_id` on TMDB is one call per film and reliable. For Letterboxd only the title+year is stable — TMDB's `/search/movie?query=…&year=…` mostly works but occasionally returns the wrong film (remakes, ambiguous titles). Accept the imperfection; users can correct via item detail.

IMDB scrapes are a thing users still do when the CSV export is inconvenient. Not worth supporting — the CSV path is the sanctioned one.

Same generic pattern lives in `issues/import-pattern.md`.
