# Non-text custom metadata fields

**Status:** deferred
**Priority:** low
**Effort:** M

## Context

Custom-category metadata fields are text-only in v1 (Spec § 6). For lists like "Wines" with a Vintage field, the user would benefit from a number input with sensible keyboard; for a list of board games with a Player Count field, a number would be similarly natural. Some fields would benefit from controlled vocabularies (a "Genre" dropdown for a custom Books list).

## Acceptance criteria

- Add a `fieldType` to `RankList.customFieldNames` — likely promoting it to an array of structs (`CustomField { name, type }`) instead of `[String]`.
- Supported types: text (current), number (Int or Double), date, single-select (with a curated list of options defined per-list), URL.
- The custom-add and custom-detail screens render the right input control per type.
- Validation: numbers reject non-numeric input; URLs validate scheme on save.
- Migration plan for existing custom lists (no production users yet, so this can be lossless — assume `text` for all existing fields).

## Notes

Worth checking what users actually do with the text-only version before committing. If most stay on plain text, this can stay deferred forever. If users start jamming numbers into text fields, the demand is real.
