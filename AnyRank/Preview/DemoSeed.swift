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
            PreviewSupport.staysRepository(),
            PreviewSupport.tvRepository(),
            PreviewSupport.mangaRepository(),
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
            for item in list.items {
                if let (lat, lon) = coordinates[item.name] {
                    item.latitude = lat
                    item.longitude = lon
                }
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
        "Manga": 26,
        "Stays — LA": 60,
        "Movies": 30,
        "TV — All-time": 40,
        "Games — All-time": 50,
        "Bars — Downtown": 120,
        "Anime — All-time": 200,
        "Books": 400,
    ]

    /// Approximate locations for the demo places, so place lists have a map.
    /// "Tourist Trap" is left off to show an item without a location.
    private static let coordinates: [String: (Double, Double)] = [
        "Bestia": (34.0337, -118.2295),
        "Kismet": (34.1020, -118.2900),
        "Republique": (34.0643, -118.3440),
        "Gjelina": (33.9906, -118.4649),
        "Sushi Note": (34.1480, -118.4320),
        "Joe's Diner": (34.0500, -118.2470),
        "The Varnish": (34.0450, -118.2490),
        "Death & Co": (34.0410, -118.2350),
        "Griffith Observatory": (34.1184, -118.3004),
        "The Last Bookstore": (34.0476, -118.2494),
        "Echo Park Lake": (34.0726, -118.2606),
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
