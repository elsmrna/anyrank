import Foundation
import UIKit

/// Driver-level abstraction over the Google Sign-In SDK. Exposes just the
/// surface area `AuthSession` needs, so previews and tests can substitute
/// a mock without ever loading the real SDK at construction time.
protocol AuthDriver: Sendable {

    /// Restore a previously signed-in user from the SDK's persistent storage,
    /// if any. Called once at app launch. Returns nil if no credential is
    /// stored or restoration failed (e.g. revoked token).
    func attemptSilentRestore() async -> SignedInUser?

    /// Begin the interactive sign-in flow. The driver is responsible for
    /// presenting whatever UI it needs (Google's case: a Safari-backed
    /// authorization sheet). Throws on user cancellation or network/SDK error.
    @MainActor
    func signIn(presenter: UIViewController) async throws -> SignedInUser

    /// Forget the current session locally. Does not revoke server-side
    /// access — that's a separate, more destructive action we don't expose
    /// in v1.
    func signOut()

    /// Request additional OAuth scopes for the currently signed-in user.
    /// Called when the user enables Sheets sync, since v1's initial sign-in
    /// only requested profile + email. Re-prompts the consent screen for
    /// the new scopes; existing tokens remain valid.
    @MainActor
    func requestAdditionalScopes(_ scopes: [String], presenter: UIViewController) async throws

    /// Return a usable access token for the currently signed-in user,
    /// refreshing if necessary. Nil if the user isn't signed in.
    func currentAccessToken() async -> String?
}

/// Errors thrown by the auth layer. Surface these in the UI rather than
/// burying inside the SDK's opaque errors.
enum AuthError: LocalizedError {
    case notConfigured
    case cancelled
    case sdkFailure(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google sign-in isn't configured. Add an OAuth client ID to Secrets.xcconfig."
        case .cancelled:
            return "Sign-in cancelled."
        case .sdkFailure(let underlying):
            return underlying.localizedDescription
        }
    }
}
