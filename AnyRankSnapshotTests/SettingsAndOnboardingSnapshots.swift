import XCTest
import SwiftUI
import SnapshotTesting
@testable import AnyRank

final class SettingsAndOnboardingSnapshots: XCTestCase {

    @MainActor
    func test_onboarding_signedOut() {
        let view = SignInOnboardingView()
            .environment(AuthSession.previewSignedOut())
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }

    @MainActor
    func test_settings_signedOut() {
        let view = SettingsView()
            .environment(AuthSession.previewSignedOut())
            .environment(SyncCoordinator.preview())
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }

    @MainActor
    func test_settings_signedIn_syncOff() {
        let view = SettingsView()
            .environment(AuthSession.previewSignedIn())
            .environment(SyncCoordinator.preview())
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }

    @MainActor
    func test_settings_signedIn_syncOn() {
        let view = SettingsView()
            .environment(AuthSession.previewSignedIn())
            .environment(SyncCoordinator.preview(
                status: .ready(spreadsheetID: "abc123", lastSyncedAt: Date(timeIntervalSinceReferenceDate: 770000000))
            ))
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }
}
