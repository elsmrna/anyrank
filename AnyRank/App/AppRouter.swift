import Observation
import SwiftUI

/// App-level navigation state: the home stack's path, plus a one-shot
/// request to start a list's ranking spree once it's on screen (used right
/// after an import is created).
@Observable
final class AppRouter: @unchecked Sendable {
    var path: [UUID] = []
    /// A list whose import spree should open as soon as its detail view
    /// can present it. Cleared by that view.
    var spreeRequestListID: UUID?

    /// Show `listID`'s detail and start ranking its import.
    func openAndRank(_ listID: UUID) {
        if path.last != listID {
            path = [listID]
        }
        spreeRequestListID = listID
    }
}

private struct AppRouterKey: EnvironmentKey {
    static let defaultValue = AppRouter()
}

extension EnvironmentValues {
    var router: AppRouter {
        get { self[AppRouterKey.self] }
        set { self[AppRouterKey.self] = newValue }
    }
}
