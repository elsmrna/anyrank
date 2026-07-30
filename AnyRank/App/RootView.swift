import SwiftUI

/// Top-level view. Wraps the home screen in a NavigationStack so list
/// detail and item detail can push naturally.
struct RootView: View {
    var body: some View {
        NavigationStack {
            ListsHomeView()
        }
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
