import Foundation

/// BoardGameGeek-backed `BoardGameSearchService`, using the XML API v2.
///
/// Since July 2025 every request needs `Authorization: Bearer <token>` from
/// an application registered at boardgamegeek.com/applications (approved by
/// hand; it can take a week or more). Without `BGG_API_TOKEN` in
/// `Secrets.xcconfig`, `AnyRankApp` uses `MockBoardGameSearchService`.
///
/// Two calls per search:
///   1. `/xmlapi2/search?type=boardgame&query=…` for matching IDs. BGG
///      doesn't rank these by relevance.
///   2. `/xmlapi2/thing?id=…&stats=1` for up to 20 of them in one batch:
///      box art, year, player counts, playing time, and how many people
///      rated it, which orders the results so well-known games come first.
struct LiveBGGSearchService: BoardGameSearchService {

    private static let base = "https://boardgamegeek.com/xmlapi2"
    private static let detailLimit = 20

    private let token: String
    private let session: URLSession

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    init?() {
        guard let token = Secrets.bggAPIToken else { return nil }
        self.init(token: token)
    }

    func searchBoardGames(query: String) async throws -> [BoardGameSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var search = URLComponents(string: "\(Self.base)/search")!
        search.queryItems = [URLQueryItem(name: "type", value: "boardgame"), URLQueryItem(name: "query", value: trimmed)]
        let found = BGGXML.items(in: try await get(search.url!))
        var seen = Set<Int>()
        let ids = found.compactMap(\.id).filter { seen.insert($0).inserted }.prefix(Self.detailLimit)
        guard !ids.isEmpty else { return [] }

        var thing = URLComponents(string: "\(Self.base)/thing")!
        thing.queryItems = [
            URLQueryItem(name: "id", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "stats", value: "1"),
        ]
        let details = BGGXML.items(in: try await get(thing.url!))
        let wanted = ImportMatcher.normalize(trimmed)
        return details
            .compactMap { $0.result }
            .sorted { a, b in
                // Exact title matches first, then the most-rated.
                let aExact = ImportMatcher.normalize(a.result.name) == wanted
                let bExact = ImportMatcher.normalize(b.result.name) == wanted
                if aExact != bExact { return aExact }
                return a.ratings > b.ratings
            }
            .map(\.result)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveServiceError.notImplemented("BoardGameGeek HTTP \(http.statusCode)")
        }
        return data
    }
}

/// Just enough of BGG's XML for search and thing responses: each `<item>`
/// with its primary name, year, players, playing time, thumbnail, and rating
/// count.
enum BGGXML {

    struct Item {
        var id: Int?
        var name: String?
        var year: Int?
        var minPlayers: Int?
        var maxPlayers: Int?
        var playingMinutes: Int?
        var thumbnail: String?
        var ratings = 0

        var result: (result: BoardGameSearchResult, ratings: Int)? {
            guard let id, let name else { return nil }
            let cover = thumbnail.flatMap { $0.hasPrefix("//") ? URL(string: "https:" + $0) : URL(string: $0) }
            return (BoardGameSearchResult(
                id: id, name: name, yearPublished: year,
                minPlayers: minPlayers, maxPlayers: maxPlayers, playingMinutes: playingMinutes,
                coverURL: cover
            ), ratings)
        }
    }

    static func items(in data: Data) -> [Item] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [Item] = []
        private var current: Item?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            let value = attributes["value"]
            switch element {
            case "item":
                current = Item(id: attributes["id"].flatMap(Int.init))
            case "name":
                // The primary name wins; alternates only fill a gap.
                if attributes["type"] == "primary" || current?.name == nil { current?.name = value }
            case "yearpublished": current?.year = value.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
            case "minplayers":    current?.minPlayers = value.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
            case "maxplayers":    current?.maxPlayers = value.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
            case "playingtime":   current?.playingMinutes = value.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
            case "usersrated":    current?.ratings = value.flatMap(Int.init) ?? 0
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            switch element {
            case "thumbnail":
                current?.thumbnail = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "item":
                if let current { items.append(current) }
                current = nil
            default: break
            }
        }
    }
}
