import SwiftUI

/// First-launch sheet offering Google sign-in alongside a clear bypass to
/// local-only mode. Shown once, gated by an `@AppStorage` flag. Either
/// outcome (signed in or bypassed) marks onboarding complete — the user
/// can still sign in later from Settings if they bypass here.
///
/// Per Spec § 2 the bypass preserves the v1 local-only behavior in full;
/// sign-in is purely about identity for the future Sheets sync milestone.
struct SignInOnboardingView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "list.star")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Welcome to AnyRank")
                    .font(.largeTitle.bold())
                Text("Rank the things you love by comparing them, not rating them.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Text("Sign in to save your lists across devices once cloud sync ships, or skip and keep everything on this device only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    Task {
                        await auth.signIn()
                        if auth.signedInUser != nil {
                            complete()
                        }
                    }
                } label: {
                    HStack {
                        if auth.isSigningIn {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.circle.fill")
                        }
                        Text(auth.isSigningIn ? "Signing in…" : "Sign in with Google")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(auth.isSigningIn)

                Button("Continue without an account") {
                    complete()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(auth.isSigningIn)

                if let error = auth.lastError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .interactiveDismissDisabled(true)
    }

    private func complete() {
        hasCompletedOnboarding = true
        dismiss()
    }
}

#Preview("Not signed in") {
    SignInOnboardingView()
        .environment(AuthSession.previewSignedOut())
}

#Preview("Sign-in error") {
    let session = AuthSession(driver: MockAuthDriver(
        signInResult: .failure(.notConfigured)
    ))
    return SignInOnboardingView()
        .environment(session)
}
