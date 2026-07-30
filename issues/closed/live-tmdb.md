# Wire up live TMDB movie search

**Status:** closed
**Closed:** Live search ships when a `TMDB_READ_TOKEN` is present in `Secrets.xcconfig`; `AnyRankApp` falls back to `MockMovieSearchService` when it isn't. See `AnyRank/Services/LiveMovieSearchService.swift`.
**Priority:** high
**Effort:** S

## Context

`LiveMovieSearchService.swift` was a stub. The app used `MockMovieSearchService` with a hand-picked set of recognizable movies. Real search via TMDB was straightforward — no SDK needed, just URLSession against the v3 REST API.

## What landed

`LiveMovieSearchService` hits `/3/search/movie?query=…&include_adult=false` with the read access token as a Bearer header, then fans out to `/3/movie/{id}/external_ids` for the top hits to resolve IMDB IDs. Poster URLs are constructed from TMDB's `image.tmdb.org/t/p/w342` CDN. Detail fan-out is capped at the top 8 results so a long typeahead session doesn't blow through rate budget.

`Secrets.tmdbReadToken` reads the value from Info.plist (populated via `TMDB_READ_TOKEN` xcconfig). The Live service exposes a failable initializer that returns nil when the token is missing; `AnyRankApp` uses that to pick `LiveMovieSearchService()` when configured or `MockMovieSearchService()` otherwise, so dev/preview/test stay usable without a token.

Error handling is basic: any non-2xx status throws `LiveServiceError.notImplemented(...)` with the HTTP code, which `MovieSearchScreen` surfaces via its existing error-state UI. Rate limit and auth failures land in that same code path.

## Notes

Fan-out to `/external_ids` is sequential rather than parallel. TMDB's rate limits are generous (~50 req/s), but sequential keeps the impl Sendable-clean under Swift 6 strict concurrency and the request count small enough that latency isn't user-noticeable.

If IMDB link population ever becomes a bottleneck, the referenced optimization — defer external-id lookup until the user picks a result — is still available. Not worth the complexity today.
