# Issues

Flat-file issue tracker. Each markdown file is a single open question, feature, or piece of work that surfaced during product discussion or implementation but isn't done yet. Open issues live at the top level; closed issues move to `closed/` so a bare `ls issues/` only shows what's actionable. The closed files stay in the repo as institutional memory — `grep -r X issues/` still answers "did we ever consider X?".

## File format

Each issue uses this header structure:

```
# <one-line title>

**Status:** open | deferred | closed
**Priority:** high | medium | low
**Effort:** S (<1 day) | M (1–3 days) | L (3+ days)
```

Then three sections: **Context** (why this matters, how it came up), **Acceptance criteria** (what makes this done), and **Notes** (free-form). Keep each section tight — issues are not specs.

## File naming

Lowercase, kebab-case, descriptive. `live-google-places.md`, not `issue-3.md` or `GooglePlaces.md`. No numeric prefixes — git history is the ordering, not the filename.

## Status meanings

`open` — actionable now or soon. Lives at `issues/<name>.md`.
`deferred` — known and intentional, not in current scope. Lives at `issues/<name>.md`.
`closed` — done; the file remains for history. Lives at `issues/closed/<name>.md` with `Status: closed` and (ideally) a `**Closed:**` line near the top pointing to the resolving commit or PR.

When closing an issue, flip the `Status:` line to `closed`, add the `**Closed:**` pointer, and move the file into `closed/` in the same change.
