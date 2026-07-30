# User-defined tags

**Status:** deferred
**Priority:** low
**Effort:** M

## Context

A common request once a list gets long: filter by tag. "Show me only restaurants tagged 'date night'" or "movies tagged 'rewatch'." We deferred this for v1 because it adds tag management UI (autocomplete, normalize, color?), a filter chip strip in the list view, and a persistence model decision.

## Acceptance criteria

- A `Tag` model or a `[String]` field on `RankItem` (decision pending — see notes).
- Tag picker on the item-detail edit screen with autocomplete suggesting existing tags from the same list.
- Filter chips on the list-detail view to constrain visible items by tag.
- Tags respected by JSON export and Sheets sync.

## Notes

A separate `Tag` model lets us colorize tags consistently and enforce normalization, but adds a relationship to manage. A simple `[String]` is cheaper and matches how users think — they want to type a tag, not pick from a curated list. Recommendation: start with `[String]`, add a real model if a user-facing tag-management screen becomes warranted.
