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

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // A tiny illustration of the core mechanic: two cards, pick one.
            ZStack {
                demoCard(title: "Bestia", subtitle: "Arts District", category: .restaurants, chosen: true)
                    .rotationEffect(.degrees(-5))
                    .offset(x: -18, y: appeared ? -44 : -20)
                demoCard(title: "Kismet", subtitle: "Los Feliz", category: .restaurants, chosen: false)
                    .rotationEffect(.degrees(4))
                    .offset(x: 18, y: appeared ? 52 : 24)
            }
            .frame(height: 220)
            .opacity(appeared ? 1 : 0)
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Rank by comparing,\nnot rating.")
                    .font(.display(.largeTitle))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Pick between two things you've tried. AnyRank does the math and builds a list that reflects what you actually prefer.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 24)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button {
                    complete()
                } label: {
                    Text("Get started")
                }
                .buttonStyle(.primary)
                .disabled(auth.isSigningIn)

                Button {
                    Task {
                        await auth.signIn()
                        if auth.signedInUser != nil {
                            complete()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if auth.isSigningIn {
                            ProgressView()
                        }
                        Text(auth.isSigningIn ? "Signing in…" : "Sign in with Google")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(auth.isSigningIn)

                Text("Everything stays on this device unless you sign in and turn on Google Sheets backup.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                if let error = auth.lastError {
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 16)
        .screenBackground()
        .presentationBackground(Theme.background)
        .interactiveDismissDisabled(true)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
    }

    private func demoCard(title: String, subtitle: String, category: Category, chosen: Bool) -> some View {
        HStack(spacing: 12) {
            CategoryIconTile(category: category, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 12)
            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(chosen ? Theme.accent : Theme.hairline)
        }
        .padding(16)
        .frame(width: 280)
        .card(cornerRadius: 20)
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
