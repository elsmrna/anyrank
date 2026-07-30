# API key management strategy

**Status:** closed
**Closed:** Landed as part of the Google OAuth sign-in work. See `Secrets.xcconfig.example`, `Secrets.xcconfig`, `AnyRank/Auth/Secrets.swift`, and the `Project.yml` `baseConfiguration` wiring.
**Priority:** high
**Effort:** S

## Context

Both `live-google-places` and `live-tmdb` need API credentials. The `.gitignore` already excludes `Secrets.xcconfig`, but no concrete pattern exists for injecting those values into the app at build time. Without one, the first developer to wire up live services will improvise — and the improvisation will leak into the app's history.

## Acceptance criteria

- A documented `Secrets.xcconfig.example` checked into the repo with placeholder keys (`GOOGLE_PLACES_API_KEY = `, `TMDB_READ_TOKEN = `).
- `Secrets.xcconfig` referenced from `Project.yml` so xcconfig values flow into Info.plist via build settings.
- A small `Secrets.swift` helper reads values out of Info.plist at runtime, exposing typed accessors (`Secrets.googlePlacesAPIKey`, etc.).
- README updated with the "copy Secrets.xcconfig.example to Secrets.xcconfig, paste your keys" step.
- App fails gracefully if a key is missing — services throw `LiveServiceError.missingCredentials` rather than crashing.

## Notes

For solo development this is fine. If the project ever grows to multiple contributors, switching to a secrets manager (1Password CLI, Doppler) is the natural next step but is overkill for v1.

For App Store builds, the keys ship inside the app binary, which is the standard pattern — Apple does not provide secrets-at-runtime infrastructure. Restrict the Places key by bundle ID in the Google Cloud Console to mitigate exfiltration risk.
