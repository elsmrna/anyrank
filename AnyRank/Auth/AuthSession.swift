import Foundation
import Observation
import UIKit

/// Observable session state for Google sign-in. Holds the current user (or
/// nil for local-only mode), exposes async sign-in / sign-out actions, and
/// performs a silent restore on launch.
///
/// `AuthSession` is the only thing views observe. The underlying SDK is
/// hidden behind an `AuthDriver` so previews can construct an `AuthSession`
/// with a `MockAuthDriver` and exercise every UI branch without ever
/// touching the network.
@MainActor
@Observable
final class AuthSession {

    /// The currently signed-in user, or nil for local-only mode. This is
    /// the only signal views need to render the sign-in vs signed-in UI.
    private(set) var signedInUser: SignedInUser?

    /// True while a sign-in network round-trip is in flight. The UI uses
    /// this to disable the sign-in button and show a spinner.
    private(set) var isSigningIn: Bool = false

    /// The most recent sign-in error, if any. Cleared on successful sign-in
    /// or by calling `clearError()`. Surfaces "missing config" and "user
    /// cancelled" so the UI can render them distinctly.
    private(set) var lastError: AuthError?

    private let driver: AuthDriver

    init(driver: AuthDriver) {
        self.driver = driver
    }

    /// Test/preview convenience that constructs a session already in the
    /// signed-in state with a `MockAuthDriver`. Avoids needing each preview
    /// to call `attemptSilentRestore()` and wait for async work.
    @MainActor
    static func previewSignedIn(as user: SignedInUser = .previewSample) -> AuthSession {
        let session = AuthSession(driver: MockAuthDriver(restoredUser: user))
        session.signedInUser = user
        return session
    }

    @MainActor
    static func previewSignedOut() -> AuthSession {
        AuthSession(driver: MockAuthDriver())
    }

    /// Restore a previous sign-in from the SDK's persistent storage, if any.
    /// Call once at app launch. Safe to call regardless of OAuth
    /// configuration — if the SDK isn't configured, returns silently
    /// without touching anything.
    func attemptSilentRestore() async {
        signedInUser = await driver.attemptSilentRestore()
    }

    /// Start the interactive sign-in flow. Presents the Google sign-in
    /// sheet over the topmost view controller. On success, `signedInUser`
    /// becomes non-nil. On failure (including user cancel), `lastError` is
    /// set and `signedInUser` is unchanged.
    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }

        guard let presenter = topMostViewController() else {
            lastError = .sdkFailure(underlying: NSError(
                domain: "AuthSession",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No presenting view controller."]
            ))
            return
        }

        do {
            signedInUser = try await driver.signIn(presenter: presenter)
        } catch let error as AuthError {
            lastError = error
        } catch {
            lastError = .sdkFailure(underlying: error)
        }
    }

    /// Sign out locally. Does not revoke server-side access. Local data
    /// stays intact — sign-in is for syncing identity, not gating storage.
    func signOut() {
        driver.signOut()
        signedInUser = nil
        lastError = nil
    }

    func clearError() {
        lastError = nil
    }

    // MARK: Incremental scope request

    /// Drive + Sheets scopes needed for the sync layer. `drive.file` limits
    /// us to files our app creates or opens — strictly narrower than full
    /// Drive access, and the right scope for app-managed sheets.
    static let syncScopes: [String] = [
        "https://www.googleapis.com/auth/drive.file",
        "https://www.googleapis.com/auth/spreadsheets"
    ]

    /// Re-prompt the consent screen to grant Sheets/Drive access on top of
    /// the v1 profile+email scopes. Called by `SyncCoordinator.enableSync`.
    func requestSyncScopes() async throws {
        guard signedInUser != nil else { throw AuthError.notConfigured }
        guard let presenter = topMostViewController() else {
            throw AuthError.sdkFailure(underlying: NSError(
                domain: "AuthSession",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No presenting view controller."]
            ))
        }
        try await driver.requestAdditionalScopes(Self.syncScopes, presenter: presenter)
    }

    /// Read-only accessor for `SyncCoordinator` to obtain a usable access
    /// token. Auto-refreshes if expired.
    func currentAccessToken() async -> String? {
        await driver.currentAccessToken()
    }

    /// Walk up from the connected scenes to find the topmost view
    /// controller to present from. SwiftUI doesn't expose this directly;
    /// the GIDSignIn API insists on a UIViewController so we reach into
    /// UIKit just for this one call.
    private func topMostViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
