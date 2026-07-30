# Local Development & Visual Testing Plan

_Companion to `Spec.md`. Covers how to develop and visually validate the app on your Mac without ever installing it on an iPhone, and how to add light visual regression tests so layout drift gets caught early._

## 1. Goal

Most of the day-to-day iteration on this app should happen in two places: Xcode's SwiftUI preview canvas, and the iOS Simulator. Neither requires a physical device, an Apple Developer account, or code signing. A new contributor should be able to clone the repo, open the Xcode project, and see a populated list view rendering within a minute. Visual regressions — accidental layout shifts, unintended color changes, broken empty states — should be caught by a small set of cheap snapshot tests rather than discovered manually.

## 2. The Three-Layer Visual Loop

The fastest loop is **Xcode Previews**. Every SwiftUI view in the project gets a `#Preview` block at the bottom of its file, sometimes several. Xcode renders these live in the canvas pane next to the source; saving a file re-renders within a second or two. This is where ~80% of UI work should happen — composing layouts, tweaking spacing, iterating on colors and typography. Because previews are isolated views with controlled inputs, they expose layout problems faster than any other mode.

The second loop is the **iOS Simulator**. When you need to exercise navigation, gestures, focus, animation transitions, or anything stateful that crosses view boundaries, Cmd-R builds the full app and runs it in a simulated iPhone (or iPad). You can switch device and OS version from the scheme menu — keep simulators for at least one small phone (iPhone SE 3rd gen) and one large phone (iPhone 16 Pro Max) installed so size-class issues show up. The Simulator boots in under 30 seconds on Apple Silicon and supports cold-launch debugging, view-hierarchy inspection (Debug → View Debugging → Capture View Hierarchy), and slow-motion animations (Debug menu → Slow Animations).

The third loop is **"My Mac (Designed for iPad)"**. Xcode lets you run an iPad-sized version of the app as a windowed Mac app with zero code changes — pick "My Mac (Designed for iPad)" as the run destination. This is useful when you want the app open in a window on the side of the screen while working on something else, or when you want to take screenshots without rotating a simulator. It is not a primary target — we don't ship a Mac build — but it's a free productivity win during development. Skip Mac Catalyst entirely; it would require code changes and we have no plans to ship to the Mac App Store.

## 3. Preview Infrastructure

SwiftUI previews are only useful if they render with realistic data. Because we use SwiftData, this means each preview needs its own in-memory `ModelContainer` seeded with sample entities. We will centralize this in a single file, `PreviewSupport.swift`, that exposes a small library of seeded containers.

The pattern looks like a `PreviewSupport` enum with static factory methods: `emptyList()`, `smallRestaurantList()`, `fullRankedRestaurantList()`, `listSpanningAllBuckets()`, and similar. Each method returns a configured `ModelContainer` (using `ModelConfiguration(isStoredInMemoryOnly: true)`) populated with hand-written sample `List` and `Item` objects. Views that need a model context wrap their preview in `.modelContainer(PreviewSupport.fullRankedRestaurantList())` so the SwiftData environment is populated as Xcode renders the view.

External services — Google Places, TMDB — are accessed through protocols (`PlacesSearchService`, `MovieSearchService`) with a real implementation and a `Mock…Service` that returns canned results. Previews and tests inject the mock; the production app injects the real one. This is also how we keep previews fast and offline — a preview should never hit the network.

Each major view should ship at least three previews: an empty state, a populated state, and one edge case relevant to that view (e.g. for the list view: "list with one item, no scores yet" — covering the <3-items-in-bucket rule). Previews are not just for the developer at the moment of authoring; they are the most stable contract we have for "this view, in this state, looks like this."

## 4. Visual Testing Strategy

We use **point-free's `swift-snapshot-testing`** library as the snapshot tool. It's the de facto standard, has been maintained for years, ships as a Swift Package, and works inside the standard XCTest target with no external runner. It supports SwiftUI directly, can render to PNG or to a recursive description string, and stores reference images alongside the test source.

The bar for v1 is intentionally low: snapshot the views where layout or visual regressions would be most painful, not every view in the app. The initial snapshot suite covers four targets — the list home screen, the list detail view (the score-sorted ranked list), the comparison screen (the side-by-side "which did you prefer?" UI), and the item detail view. Each target gets snapshots for its meaningful states, mirroring the previews: empty, small, full, and any state with conditional UI like the "no score until 3 items in bucket" rule. That's roughly 12–16 reference images total — small enough to review by eye when one changes.

Snapshots run as part of the standard `cmd-U` test pass, alongside whatever unit tests we accumulate for the ranking algorithm. They produce a named PNG under `__Snapshots__/` adjacent to the test file. When a snapshot intentionally needs to change (we redesigned a view), the developer deletes the relevant PNG and re-runs the tests, which writes the new reference; the diff is then reviewed in the PR. Reference images are committed to the repo.

We snapshot at a single canonical device size — iPhone 16 Pro at default Dynamic Type — for v1. We do not run a device matrix or accessibility-size matrix; that's a real cost we don't want to pay until the app is more mature. If a specific view has known size-class branching (e.g. a future iPad layout), it can opt into additional snapshots locally.

The ranking algorithm itself gets unit tests, not snapshot tests — given a starting list and a sequence of comparison answers, assert the resulting bucket assignments and scores. These are fast, deterministic, and the most valuable tests in the suite because the algorithm is the product. Visual snapshots are insurance, not the foundation.

## 5. What's Explicitly Out of Scope for v1

Full XCUITest end-to-end UI tests are out of scope. They're slow, flaky on simulator boot timing, and duplicate what previews + snapshots cover for our app size. We can revisit when the app is large enough that integration coverage actually pays off.

Pixel-perfect cross-device snapshot matrices are out of scope. One device, one type size.

Continuous integration is out of scope for v1 — the whole project is local on one machine. The test suite should still be runnable headlessly via `xcodebuild test -scheme … -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` so that adding CI later is a config change, not a refactor.

Visual testing of the future Google Sheets sync layer or any networked path is deferred until that layer exists.

## 6. Setup Steps (One-Time)

When the Xcode project is first scaffolded, four things need to land in the repo. First, `swift-snapshot-testing` added as a Swift Package dependency on the test target only (`https://github.com/pointfreeco/swift-snapshot-testing`, latest 1.x). Second, the `PreviewSupport.swift` helper with at least the four seeded-container factories named above. Third, the service protocol files (`PlacesSearchService.swift`, `MovieSearchService.swift`) and their mock implementations, even before real implementations exist — previews can develop against the mocks indefinitely. Fourth, an initial set of snapshot tests for whichever views exist on day one, to establish the convention even if the suite is small.

The Simulator destination used by the snapshot tests should be pinned in the test scheme so reference images don't drift between developer machines. Pin to "iPhone 16 Pro" on the project's deployment iOS version.

## 7. Day-to-Day Workflow

Building a new view: write the view file, add 2–3 `#Preview` blocks covering its meaningful states, iterate in Canvas until it looks right, then run the app in Simulator to validate it in context with navigation and real interaction. If the view is one of the four snapshot targets, add (or update) snapshot tests before opening the change for review. If reference images change, the diff between old and new PNGs goes into the PR description so the visual change is reviewable.

Refactoring an existing view: run `cmd-U` first, see which snapshots fail, decide whether each failure is intended. Delete intended-to-change PNGs, re-run, commit the new references.

Designing a new screen end-to-end: start from previews with mock data; only move to Simulator once the static layout is settled. The Simulator is for behavior, not for layout iteration — Canvas is much faster for layout.

## 8. Shipping to a Physical Device

Previews and the Simulator cover ~95% of development. Occasionally you want the app on a real phone — to feel taps under thumbs, test the actual Google sign-in redirect, or hand the phone to a friend. This section is the checklist for that trip, aimed at the free-Apple-ID case (no paid Developer Program membership). The paid path is the same steps with fewer expirations.

### One-time setup

**Xcode → Settings → Accounts**: sign in with your Apple ID and add it as an Apple Development account. Xcode uses this to auto-provision a development certificate and provisioning profile the first time you run to device.

**Bundle ID**: the project uses `com.ellismiranda.anyrank.AnyRank`. If a different developer clones this repo they need to change `bundleIdPrefix` and `PRODUCT_BUNDLE_IDENTIFIER` in `Project.yml` to a reverse-DNS string tied to their own Apple ID, then re-run `xcodegen generate`. The Google OAuth iOS client and any bundle-ID-restricted API keys also have to be updated to match.

**On the phone** (first time only): plug in with a cable, unlock the phone, tap **Trust This Computer** on the prompt. Then enable Developer Mode: **Settings → Privacy & Security → Developer Mode → On**, reboot when prompted. Developer Mode is required on iOS 16+ for locally-signed apps to launch.

### Signing

In the generated `.xcodeproj`, select the AnyRank target → **Signing & Capabilities**:
- Tick **Automatically manage signing**.
- Set **Team** to your personal Apple ID (labeled "Personal Team" for free accounts).

Xcode issues a development certificate and a provisioning profile scoped to your device on first run. If you see a signing error, the fix is almost always a matching problem between the bundle ID in `Project.yml` and the one Xcode's provisioning system expects — check both and re-run `xcodegen generate`.

### Run

Pick your device from the destination dropdown at the top of Xcode (next to the scheme), then **Cmd-R**. The first install prompts on-device: **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**. Launch again from the home screen; from then on Cmd-R installs silently over the previous build.

Wireless debugging works once the device has been paired via cable at least once. Enable it under **Window → Devices and Simulators** in Xcode. After that, unplug the cable and Cmd-R runs over Wi-Fi as long as both machines are on the same network.

### Free-tier limits worth knowing

**7-day cert expiry.** Free-tier development certificates expire after seven days. When the app stops launching on the phone with an "untrusted developer" or "unable to verify app" error, plug back in and Cmd-R; the app reinstalls over itself with a fresh cert. No data loss — local CSVs survive because the bundle ID stays the same. Paid Developer Program certs last a year.

**10-app cap.** A free-tier developer can have up to 10 signed apps active on a device at once. AnyRank counts as one; not a real constraint unless you're side-loading a lot of side projects.

**No push notifications, Sign in with Apple, or Associated Domains.** None of these are used by AnyRank today, so the free tier is fine. If any of them become interesting the paid program is the escape hatch.

**Google Sign-In and Places work on free tier.** Both are OAuth or API-key gated, not entitlement-gated, so they don't care about your Apple Developer tier. Just make sure the Google OAuth client's bundle ID matches whatever you set in `Project.yml`.

### When something breaks

If Xcode won't sign, the error usually points at either "no provisioning profile for `com.…`" or "no matching provisioning profile found." Both mean the bundle ID drifted from what the auto-provisioning system prepared for. Verify `Project.yml`, run `xcodegen generate`, close and reopen the `.xcodeproj`, and let Xcode re-provision.

If the app installs but sign-in fails, the OAuth iOS client's registered bundle ID probably doesn't match your app's bundle ID. Fix that in Google Cloud Console → APIs & Services → Credentials → your iOS client. Same idea if Places search returns "REQUEST_DENIED": the API key restriction needs to include this app's bundle ID.

If Cmd-R hangs on "Waiting for the device to respond," the phone is asleep or the cable is flaky. Unlock and wiggle.
