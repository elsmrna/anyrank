# First-launch onboarding (educational walkthrough)

**Status:** open
**Priority:** medium
**Effort:** M

## Update — partial implementation in place

A minimal first-launch sheet exists as `SignInOnboardingView` (gated by the `hasCompletedOnboarding` `@AppStorage` flag) but it currently only handles the sign-in vs local-only decision. The educational portion below — explaining the bucket model and the comparison flow — is still TODO. Likely shape: insert one or two explainer screens before the sign-in screen, sharing the same `hasCompletedOnboarding` gate.

## Context

On first launch the user lands in `ListsHomeView`'s empty state, which has a "Create your first list" CTA but no explanation of what the app is or how the ranking model works. The Beli-style four-bucket comparison flow isn't intuitive — users need to understand they pick a bucket and then compare, not rate.

## Acceptance criteria

- Brief multi-screen walkthrough preceding the existing sign-in screen, explaining: (1) what AnyRank does, (2) how the bucket + comparison flow works, (3) what to expect for scores. ~2–3 screens, dismissible.
- Optionally seed a sample list (read-only or marked "Sample") that the user can poke at and delete.
- A "Show me again" affordance in Settings.

## Notes

The bucket model is the part most likely to confuse new users — "why does my favorite restaurant have score 9.3 instead of 10.0?" is the kind of question onboarding should preempt. A simple illustration of three items in the Loved bucket with scores 10.0 / 9.0 / 8.0 would land the concept fast.

Worth keeping minimal — most users skip onboarding. The "create your first list" path should remain a one-tap escape.
