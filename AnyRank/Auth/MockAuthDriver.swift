import Foundation
import UIKit

/// Canned `AuthDriver` for previews, snapshot tests, and any non-SDK build.
/// Behavior is configurable at construction so callers can simulate the
/// three states that matter: already-signed-in, signed-out, and sign-in
/// fails. The mock is deliberately deterministic — no async delays, no
/// random failures.
struct MockAuthDriver: AuthDriver {

    var restoredUser: SignedInUser?
    var signInResult: Result<SignedInUser, AuthError>

    init(
        restoredUser: SignedInUser? = nil,
        signInResult: Result<SignedInUser, AuthError> = .success(.previewSample)
    ) {
        self.restoredUser = restoredUser
        self.signInResult = signInResult
    }

    func attemptSilentRestore() async -> SignedInUser? {
        restoredUser
    }

    @MainActor
    func signIn(presenter: UIViewController) async throws -> SignedInUser {
        switch signInResult {
        case .success(let user): return user
        case .failure(let error): throw error
        }
    }

    func signOut() {}

    @MainActor
    func requestAdditionalScopes(_ scopes: [String], presenter: UIViewController) async throws {
        // Mock pretends the user always approves the new scopes immediately.
        // To simulate denial in tests, override `signInResult` and inspect the
        // .failure case in the calling code path.
    }

    func currentAccessToken() async -> String? {
        // Mock returns a non-nil sentinel when "signed in" so call sites that
        // gate on token presence behave the way they would with real auth.
        restoredUser != nil ? "mock-access-token" : nil
    }
}

extension SignedInUser {
    /// Sample user used by previews and the default mock auth driver.
    static let previewSample = SignedInUser(
        displayName: "Ellis Miranda",
        email: "ellis@example.com",
        avatarURL: nil
    )
}
