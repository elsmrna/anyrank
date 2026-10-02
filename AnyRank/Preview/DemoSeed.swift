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
            list.lastUsedAt = recentUse[list.name].map { Date(timeIntervalSinceNow: -$0 * 3600) } ?? list.createdAt
            repository.addList(list)
        }
    }

    /// Hours since each demo list was last used, so the home screen's Recent
    /// sort shows a believable order, including a Custom list near the top.
    private static let recentUse: [String: Double] = [
        "Restaurants — LA": 1,
        "Weekend Spots": 3,
        "Books — 2024": 20,
        "Movies": 30,
        "Games — All-time": 50,
        "Songs — All-time": 80,
        "Bars — Downtown": 120,
        "Anime — All-time": 200,
        "Books": 400,
    ]

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
