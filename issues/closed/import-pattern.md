# Generic import pattern for external lists

**Status:** closed
**Priority:** low
**Effort:** M

**Closed:** 2026-09-30 — superseded by `closed/import-ranking-spree.md`. The shared machinery exists (`AnyRank/Import/`), but imports queue items for the compare flow rather than mapping ratings straight to buckets; source ratings become a *suggested* bucket only.

## Context

Both `import-storygraph.md` and `import-movies.md` describe the same three-step flow: user uploads a CSV → we parse it into rows → we map rows into `RankItem`s with buckets. When there's a third or fourth importer (Goodreads, Trakt, Steam wishlist, Airbnb saved places, …) it's worth extracting the shared machinery so each new source is a small parser plus a rating→bucket mapping table, not a whole new screen.

This issue is a meta-note about that pattern. It's `deferred` because we shouldn't build it until we have at least two live importers to generalize from — designing the abstraction before that risks over-fitting.

## Acceptance criteria

- A `ListImporter` protocol with a small surface: `sourceName: String`, `fileTypes: [UTType]`, `preview(url:) async throws -> ImportPreview`, `commit(preview:) async throws -> RankList`.
- `ImportPreview` carries: source name, resolved `Category`, per-bucket counts, sample rows for the confirmation UI, unresolved rows (missing fields, unmapped ratings) plus what to do with them.
- Concrete implementations for each source implement `ListImporter`, live under `AnyRank/Import/<Source>Importer.swift`.
- A single `ImportView` sheet handles file picking, invoking `preview(url:)`, showing the preview, and calling `commit(preview:)`.
- Settings has a single **Import list** entry that shows a menu of every registered importer, rather than one action per importer.
- New importers register themselves at app startup in a small `ListImporterRegistry`.

## Notes

The rating-scale mapping is the piece each importer expresses differently. Some sources are 1–5 stars, some 1–10, some heart/no-heart, some 0.5-increments. Keep it as a per-importer strategy — resist trying to unify them behind a "normalized 0–1 score" that then maps to buckets. The bucket boundaries encode qualitative meaning ("Loved" is not "top 20%"), and that intent gets lost through a normalization step.

The metadata-enrichment step (TMDB poster lookup, Open Library cover lookup) is also per-source but similar in shape. Factor into a `MetadataEnricher` per category if a second one lands.

Skip this issue's implementation until we have at least two importers live. Design-in-a-vacuum is where import frameworks go to die.

## Related

- `import-storygraph.md`
- `import-movies.md`
- Future: Goodreads, Trakt, Serializd (TV), etc.
