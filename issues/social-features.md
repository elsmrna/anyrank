# Social features (Beli-style)

**Status:** deferred
**Priority:** low
**Effort:** L

## Context

In the initial product discussion we noted that Beli's social layer (following friends, seeing their rankings, list sharing) is on the radar but explicitly out of scope for v1. Spec § 7 commits to keeping v1 architecture compatible with adding social later — UUIDs everywhere, no assumption the local user is the only author, "authoring" and "viewing" cleanly separated in the data model.

## Acceptance criteria

- Backend exists (custom API or Firebase). Sheets sync alone isn't enough for social.
- User profile model with display name and identifier separate from Google account.
- Follow / unfollow flow.
- Friends-feed view showing recent activity from people the user follows.
- Public list view (read-only) for someone else's list.
- Privacy controls — per-list visibility (private / friends / public).

## Notes

This is a real product, not a feature. It changes the company shape: hosting costs, content moderation policies, abuse reporting. Worth not undertaking until v1 has demonstrated organic value to a small set of personal users.

Worth periodically checking that v1 changes don't accidentally close the door on this. For example, hard-coding "current user" assumptions in views or relying on a single non-portable identifier would create future migration pain.
