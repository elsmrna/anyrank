#if DEBUG
import Foundation

/// Fills an empty store with the preview datasets so the real app can be
/// eyeballed on a simulator without adding everything by hand. Launch with
/// the `-seedDemoData` argument (Scheme → Run → Arguments) to enable it.
@MainActor
enum DemoSeed {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedDemoData")
    }

    static func seedIfEmpty(_ repository: Repository) {
        guard repository.lists.isEmpty else { return }
        let sources = [
            PreviewSupport.customMapsLinkedRepository(),
            PreviewSupport.songsRepository(),
            PreviewSupport.gamesRepository(),
            PreviewSupport.animeRepository(),
            PreviewSupport.booksRepository(),
            PreviewSupport.multipleListsRepository(),
            PreviewSupport.fullRestaurantsRepository(),
        ]
        var seen = Set<String>()
        for list in sources.flatMap(\.lists).reversed() where seen.insert(list.name).inserted {
            for item in list.items where list.category == .books {
                item.coverURLString = coverURLs[item.name]
            }
            repository.addList(list)
        }
    }

    /// Open Library cover CDN, keyed by title.
    private static let coverURLs: [String: String] = [
        "Beloved": "https://covers.openlibrary.org/b/isbn/9781400033416-M.jpg",
        "Pachinko": "https://covers.openlibrary.org/b/isbn/9781455563937-M.jpg",
        "The Three-Body Problem": "https://covers.openlibrary.org/b/isbn/9780765382030-M.jpg",
        "Mrs Dalloway": "https://covers.openlibrary.org/b/isbn/9780156628709-M.jpg",
        "A Brief History of Time": "https://covers.openlibrary.org/b/isbn/9780553380163-M.jpg",
        "The Great Gatsby": "https://covers.openlibrary.org/b/isbn/9780743273565-M.jpg",
    ]
}
#endif
