import Foundation
import UIKit
import GoogleSignIn

/// Real `AuthDriver` backed by the Google Sign-In iOS SDK. Only requests
/// profile + email scopes at sign-in — Sheets/Drive scopes are added later
/// via `requestAdditionalScopes` when the user enables sync in Settings
/// (see https://github.com/elsmrna/anyrank/issues/5), which re-prompts the
/// consent screen at that point. Keeping the initial prompt minimal
/// increases the odds users approve it.
struct GoogleAuthDriver: AuthDriver {

    func attemptSilentRestore() async -> SignedInUser? {
        guard Secrets.googleOAuthClientID != nil else { return nil }
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return nil }

        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            return user.toSignedInUser()
        } catch {
            // Silent restore can fail for legitimate reasons — token revoked,
            // user signed out elsewhere. Treat as "no session" rather than
            // surfacing an error to the user.
            return nil
        }
    }

    @MainActor
    func signIn(presenter: UIViewController) async throws -> SignedInUser {
        guard Secrets.googleOAuthClientID != nil else {
            throw AuthError.notConfigured
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            return result.user.toSignedInUser()
        } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
            throw AuthError.cancelled
        } catch {
            throw AuthError.sdkFailure(underlying: error)
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    @MainActor
    func requestAdditionalScopes(_ scopes: [String], presenter: UIViewController) async throws {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw AuthError.notConfigured
        }
        do {
            try await user.addScopes(scopes, presenting: presenter)
        } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
            throw AuthError.cancelled
        } catch {
            throw AuthError.sdkFailure(underlying: error)
        }
    }

    func currentAccessToken() async -> String? {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return nil }
        // refreshTokensIfNeeded transparently rotates expired access tokens.
        do {
            let refreshed = try await user.refreshTokensIfNeeded()
            return refreshed.accessToken.tokenString
        } catch {
            return user.accessToken.tokenString
        }
    }
}

private extension GIDGoogleUser {
    func toSignedInUser() -> SignedInUser {
        SignedInUser(
            displayName: profile?.name ?? profile?.givenName ?? "Signed in",
            email: profile?.email ?? "",
            avatarURL: profile?.imageURL(withDimension: 192)
        )
    }
}
