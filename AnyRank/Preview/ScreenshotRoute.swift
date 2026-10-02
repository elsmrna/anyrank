#if DEBUG
import SwiftUI

/// Opens a specific screen at launch so `scripts/screenshots.sh` can capture
/// it. Launch with `-seedDemoData -screenshotRoute <route>`; the route waits
/// for the demo lists to load before navigating.
enum ScreenshotRoute: String, CaseIterable {
    case home
    case list
    case bucketPick
    case compare
    case importSources

    static var current: ScreenshotRoute? {
        UserDefaults.standard.string(forKey: "screenshotRoute").flatMap(Self.init(rawValue:))
    }
}

extension View {
    /// No-op unless the app was launched with `-screenshotRoute`.
    func screenshotRoute() -> some View {
        modifier(ScreenshotRouteModifier())
    }
}

private struct ScreenshotRouteModifier: ViewModifier {
    @Environment(Repository.self) private var repository
    @Environment(\.router) private var router

    @State private var applied = false
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case placement(AddItemCoordinator)
        case importSources

        var id: String {
            switch self {
            case .placement: return "placement"
            case .importSources: return "importSources"
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .placement(let coordinator):
                    PlacementFlowView(
                        coordinator: coordinator,
                        rootTitle: "Add to \(coordinator.list.name)",
                        newItemImageURLString: \.artworkURLString,
                        newItemSecondaryText: \.secondaryText,
                        onCommit: { _, _ in }
                    ) {
                        BucketPickerScreen(
                            itemName: coordinator.staged?.name ?? "",
                            artworkURLString: coordinator.staged?.artworkURLString,
                            category: coordinator.list.category,
                            secondaryText: coordinator.staged?.secondaryText
                        ) { bucket in
                            coordinator.bucketPicked(bucket)
                        }
                    }
                case .importSources:
                    ImportFlowView()
                }
            }
            .task(id: repository.lists.count) { apply() }
    }

    private func apply() {
        guard !applied, let route = ScreenshotRoute.current,
              let books = repository.lists
                  .filter({ $0.category == .books })
                  .max(by: { $0.items.count < $1.items.count })
        else { return }
        applied = true

        switch route {
        case .home:
            break
        case .list:
            router.path = [books.id]
        case .bucketPick, .compare:
            router.path = [books.id]
            let coordinator = AddItemCoordinator(placing: Self.stationEleven, in: books)
            if route == .compare { coordinator.bucketPicked(.loved) }
            sheet = .placement(coordinator)
        case .importSources:
            sheet = .importSources
        }
    }

    private static var stationEleven: StagedItem {
        var staged = StagedItem(name: "Station Eleven", category: .books)
        staged.book = BookSearchResult(
            id: "screenshot-station-eleven",
            title: "Station Eleven",
            author: "Emily St. John Mandel",
            publicationYear: 2014,
            isbn: "9780804172448",
            storyGraphURL: nil,
            coverURL: URL(string: "https://covers.openlibrary.org/b/isbn/9780804172448-M.jpg")
        )
        return staged
    }
}
#endif
