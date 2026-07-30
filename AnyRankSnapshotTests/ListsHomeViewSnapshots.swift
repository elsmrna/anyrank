import XCTest
import SwiftUI
import SnapshotTesting
@testable import AnyRank

final class ListsHomeViewSnapshots: XCTestCase {

    override func setUp() {
        super.setUp()
        // Suppress the first-launch onboarding sheet so tests render the
        // home view itself, not the onboarding cover.
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        super.tearDown()
    }

    @MainActor
    func test_emptyState() {
        let view = NavigationStack {
            ListsHomeView()
        }
        .environment(PreviewSupport.emptyRepository())
        .environment(AuthSession.previewSignedOut())
        .environment(SyncCoordinator.preview())
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }

    @MainActor
    func test_multipleLists() {
        let view = NavigationStack {
            ListsHomeView()
        }
        .environment(PreviewSupport.multipleListsRepository())
        .environment(AuthSession.previewSignedIn())
        .environment(SyncCoordinator.preview())
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }
}
