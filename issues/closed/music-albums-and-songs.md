# Music categories (Albums and Songs)

**Status:** closed
**Closed:** Shipped as two peer categories (`Category.albums`, `Category.songs`) sharing one `MusicSearchService`. Live via `LiveSpotifyMusicService` (client-credentials OAuth through `AppOAuthTokenStore`), with mock fallback when Spotify credentials aren't configured.
**Priority:** medium
**Effort:** L

## Context

Music was the obvious next category after Books, Anime, and Games. Two decisions up front: **one category or two**, and **which metadata source**.

## What landed

**Two peer categories.** `Category.albums` and `Category.songs` are first-class alongside Movies/Books/etc. Users rank songs against songs, albums against albums. The alternative (one "Music" category with a picker) was rejected because the "unit of ranking" is genuinely different — you rate a *song*, and you separately rate the *album* it lives on.

**One shared service.** `MusicSearchService` protocol has two methods (`searchAlbums`, `searchSongs`) so the two categories share auth, rate-limit budget, and token refresh. Both categories dispatch through the same `.musicService` environment key.

**Spotify.** Chosen over MusicBrainz for metadata quality — richer artist metadata, cover art at reliable sizes, higher user familiarity for the Spotify URLs on item detail. Auth is Spotify's client-credentials flow (app-level, no user consent) — the same shape as IGDB's Twitch flow, and it reuses the `AppOAuthTokenStore` actor we introduced for Games. `LiveSpotifyMusicService.init?()` returns nil when either secret is missing so the mock takes over cleanly.

**Data model.** `RankItem` gained `artist` (both categories), `albumTitle` (songs only), `durationSeconds` (songs only), and `spotifyURLString`. Cover art rides the existing `coverURLString`. CSV codec expanded with four new columns (`artist`, `album_title`, `duration_seconds`, `spotify_url`). Song duration renders as `mm:ss` on item detail.

**Search screens.** `AlbumSearchScreen` and `SongSearchScreen`, both following the auto-focus + typeahead pattern of the other search screens. Album secondary text is `artist · year`; song secondary text is `artist · album` (album disambiguates same-title covers and live-vs-studio).

## Notes

Client Credentials tokens last ~1 hour; the shared `AppOAuthTokenStore` refreshes on demand with a 60-second slack margin. Both Spotify and IGDB tokens flow through the same actor now, which is the shape we wanted.

Storing client secrets in `Secrets.xcconfig` is fine for a personal side-loaded app. If AnyRank ever ships to the App Store, the standard fix — backend proxy that mints tokens on request — becomes worth doing.

Songs and Albums share the artist+cover metadata plumbing. Custom lists could theoretically use these fields too, but that's what the Custom category is for; no crossover intended.

If Spotify's terms ever push us off, MusicBrainz + Cover Art Archive is the direct swap. The `MusicSearchService` protocol wouldn't need to change; only the live implementation.
