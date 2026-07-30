# App name and branding

**Status:** open
**Priority:** medium
**Effort:** M

## Context

Working name is "AnyRank" (folder name). No final name, app icon, launch screen, or color palette has been picked. The four bucket colors currently use SwiftUI's default `.green`, `.blue`, `.yellow`, `.red` — readable but generic. Spec.md § 8 flagged this as a TBD.

## Acceptance criteria

- A chosen app name (used in `CFBundleDisplayName`, App Store listing, marketing).
- App icon at all required sizes shipped via `Assets.xcassets`.
- Launch screen designed (currently a default blank background via `UILaunchScreen: {}`).
- A defined bucket color palette — four colors that are distinguishable, accessible at the default text contrast, and look right both light and dark mode. Stored as named asset colors so they're swappable centrally.
- Accent color picked (currently SwiftUI default tint).

## Notes

Bucket colors are the most user-visible color choice; they appear on every item row. Worth testing the palette against colorblind users (deuteranopia is the main risk for red/green pairs). One option is to add a secondary signal — a glyph or position indicator — alongside color, but the spec deliberately chose color-only so the list view stays minimal.
