# Video games category (IGDB)

**Status:** closed
**Closed:** Shipped. `Category.games` case, IGDB via Twitch client-credentials OAuth (`AppOAuthTokenStore` handles refresh), platform-abbreviated secondary text, CSV round-trip. `AnyRankApp` falls back to `MockGameSearchService` when Twitch secrets aren't configured.
**Priority:** low
**Effort:** M

## Context

Games are the natural fifth ranking domain after Restaurants, Bars, Movies, Books, Music, and Anime. Well-established metadata (title, platforms, release year, cover art) and users have strong opinions about ranking — this app is for that.

## What landed

- `Category.games` with the `gamecontroller` SF Symbol.
- `GameSearchResult` carries IGDB id, name, platforms (abbreviations, IGDB order preserved), first release year, cover URL, IGDB URL, summary.
- `LiveIGDBSearchService` POSTs Apicalypse queries to `api.igdb.com/v4/games`. Cover URLs use IGDB's `t_cover_big` size (277×370). Platforms rendered compactly ("PC, PS5, XSX +2 more") in the search screen and comparison card; full list on item detail.
- `AppOAuthTokenStore` — a small actor cache that holds a client-credentials bearer token and refreshes when within 60s of expiry. Provider-agnostic (Music/Spotify will reuse it).
- `LiveIGDBSearchService.init?()` returns nil when either `TWITCH_CLIENT_ID` or `TWITCH_CLIENT_SECRET` is missing. `AnyRankApp` then injects `MockGameSearchService` instead.
- `RankItem` gained `platforms: [String]?` and `igdbURLString`. CSV codec encodes platforms as a `|`-joined string (commas would collide with the CSV delimiter).
- `GameSearchScreen` following the pattern of the other search screens.

## Notes

Twitch's client-credentials tokens last ~60 days. `AppOAuthTokenStore` transparently refreshes when needed; no user interaction required. The client secret sits in `Secrets.xcconfig` (gitignored) — same trust model as the Places API key. If this ever ships to the App Store, the standard fix is a backend proxy that mints tokens.

IGDB's search is fuzzy — good for typeahead, occasionally quirky (spin-offs before mainline titles). Acceptable given the picker UI.

Consider showing SF Symbol platform icons (`iphone`, `gamecontroller`, `desktopcomputer`) rather than abbreviations in a future polish pass — the abbreviations are compact but IGDB's naming ("XONE" vs "XSX") isn't obvious to everyone.

Music (Spotify) is next — will share the `AppOAuthTokenStore` helper for its own client-credentials flow.
