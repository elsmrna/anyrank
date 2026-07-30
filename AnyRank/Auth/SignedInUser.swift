import Foundation

/// Minimal identity payload we keep about a signed-in Google user. We only
/// store what we display — name, email, an optional avatar URL — and use the
/// GoogleSignIn SDK as the source of truth for tokens. The token itself
/// never escapes the SDK's Keychain storage.
struct SignedInUser: Equatable, Hashable, Sendable {
    let displayName: String
    let email: String
    let avatarURL: URL?
}
