import SwiftUI

/// Top-level view. Wraps the home screen in a NavigationStack so list
/// detail and item detail can push naturally. The stack's path lives on
/// `AppRouter` so flows like import can navigate programmatically.
struct RootView: View {
    @Environment(\.router) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            ListsHomeView()
        }
        #if DEBUG
        .screenshotRoute()
        #endif
    }
}

#Preview("Empty") {
    RootView()
        .environment(PreviewSupport.emptyRepository())
        .environment(AuthSession.previewSignedOut())
        .environment(SyncCoordinator.preview())
}

#Preview("Multiple lists") {
    RootView()
        .environment(PreviewSupport.multipleListsRepository())
        .environment(AuthSession.previewSignedIn())
        .environment(SyncCoordinator.preview())
}
