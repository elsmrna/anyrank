# Pick a value for periodic re-rank cadence

**Status:** open
**Priority:** low
**Effort:** S

## Context

Spec § 5 calls for a periodic re-rank prompt after every N additions to a list. The current implementation uses `rerankPromptThreshold = 10` as a per-list default in `RankList.init`. The value was chosen by gut feel — no data, no user testing.

## Acceptance criteria

- After dogfooding the app for a few weeks, revisit N. Possible signals: "the prompt fires too often" → raise it; "users never see re-rank suggestions" → lower it.
- Decide whether the threshold should scale with list size (e.g. larger lists prompt less often) or stay constant.
- If the latter, lock in the value as a constant in `RankList.swift` and remove the per-list override unless a user-facing setting is desired.
- If a user-facing setting is added, surface it on the list-detail view or a per-list settings sheet.

## Notes

A small refinement: the current implementation picks the *oldest* item in the list for re-rank. Alternatives worth considering — oldest-in-bucket (so all buckets get attention), random among the oldest 5 (so the same item isn't picked repeatedly if dismissed), or weighted by time-since-last-rerank (so a recently-re-ranked item doesn't re-surface).
