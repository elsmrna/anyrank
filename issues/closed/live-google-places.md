# Wire up live Google Places search

**Status:** closed
**Closed:** Places SDK wired up; Restaurants/Bars and the new Maps-linked Custom-list flow all go through `LivePlacesSearchService` when a `GOOGLE_PLACES_API_KEY` is configured. See `AnyRank/Services/LivePlacesSearchService.swift`, `GooglePlacesBootstrap.swift`, and the sign-in gate in `PlaceSearchScreen`.
**Priority:** high
**Effort:** M

## Context

`LivePlacesSearchService.swift` was a stub that threw `LiveServiceError.notImplemented`. The app used `MockPlacesSearchService` for both Restaurants and Bars lookups, with a small canned dataset of LA-area places. Real search was needed before the app was usable beyond the demo dataset.

## What landed

The Google Places SDK for iOS is now a Swift Package dependency (`Project.yml`), and `LivePlacesSearchService` is implemented against `GMSPlacesClient.findAutocompletePredictions` + `fetchPlace`. The same autocomplete session token is reused across the two-stage flow so the SDK bills both calls as one session rather than per-keystroke. Type filters bias predictions appropriately (`restaurant`, `bar`); a new `.any` kind disables the filter for the Custom-list Maps lookup path.

A new `Secrets.googlePlacesAPIKey` accessor reads the key from Info.plist (populated from `Secrets.xcconfig` at build time). `GooglePlacesBootstrap.configure()` provisions the SDK once at app launch; when no key is present, `AnyRankApp` falls back to `MockPlacesSearchService` so dev/preview/test stay usable without a real key.

The user-facing sign-in gate lives in `PlaceSearchScreen`: signed-out users see a "Sign in to look up places" prompt that triggers `AuthSession.signIn()`. Under the hood Places is API-key gated, not OAuth-gated — the sign-in requirement is a UX choice that ties the Maps feature to the signed-in experience.

Custom lists pick up the same machinery via the new `RankList.linksToMapsLocation` flag. When that flag is on, `ItemSearchScreen` dispatches to `PlaceSearchScreen` with kind `.any` and stages items as `.custom`, so a "Weekend Spots" custom list works the same way Restaurants does — type a name, pick the canonical Maps result, item carries name + address + lat/lng + Maps URL.

## Notes

Places API has a per-request cost; the session token batches autocomplete + detail fetch into a single session for billing. Cost still scales with the number of typeahead refinements per search; the implementation caps detail-fetch fan-out at 8 results and runs sequentially to avoid pathological keystroke patterns blowing through budget.

Mock remains for previews and tests via environment injection (`ServiceEnvironment.swift`). The signed-out gate preview also exercises the no-key path.

The implementation is sequential rather than parallel for the detail fetches. Concurrency isn't needed for a list of 5–10 predictions, and going sequential sidesteps having to ferry non-Sendable SDK objects across task boundaries under Swift 6 strict concurrency.
