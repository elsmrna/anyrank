import Foundation
import SwiftUI

/// One game in a Steam library.
struct SteamOwnedGame: Sendable, Equatable {
    let appID: Int
    let name: String
    let minutesPlayed: Int
    let lastPlayed: Date?
}

protocol SteamLibraryService: Sendable {
    /// True when this is canned sample data rather than a real library.
    var isSample: Bool { get }
    /// Every game owned by the profile. `profile` may be a profile URL,
    /// a custom (vanity) URL name, or a 17-digit SteamID64.
    func ownedGames(profile: String) async throws -> [SteamOwnedGame]
}

enum SteamImport {
    /// Portrait library art — 2:3, matching the Games artwork aspect.
    static func coverURL(appID: Int) -> URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg")
    }

    static func storeURL(appID: Int) -> URL? {
        URL(string: "https://store.steampowered.com/app/\(appID)/")
    }

    /// Turn a library into import candidates, most-played first — the games
    /// you've spent the most time with are the ones you have opinions about.
    static func candidates(from games: [SteamOwnedGame]) -> [ImportCandidate] {
        games
            .sorted { ($0.minutesPlayed, $1.name) > ($1.minutesPlayed, $0.name) }
            .map { game in
                var staged = StagedItem(name: game.name, category: .games)
                staged.game = GameSearchResult(
                    id: game.appID,
                    name: game.name,
                    platforms: [],
                    firstReleaseYear: nil,
                    coverURL: coverURL(appID: game.appID),
                    igdbURL: nil,
                    summary: nil
                )
                staged.sourceURL = storeURL(appID: game.appID)
                staged.sourceNote = playtimeNote(minutes: game.minutesPlayed)
                staged.dateConsumed = game.lastPlayed
                return ImportCandidate(item: staged, neverEngaged: game.minutesPlayed == 0)
            }
    }

    static func playtimeNote(minutes: Int) -> String {
        switch minutes {
        case 0:         return "Never played"
        case ..<60:     return "\(minutes) min played"
        case ..<600:    return String(format: "%.1f hours played", Double(minutes) / 60)
        default:        return "\(minutes / 60) hours played"
        }
    }

    enum ProfileReference: Equatable {
        case steamID(String)
        case vanity(String)
    }

    /// Accepts `https://steamcommunity.com/id/name/`,
    /// `https://steamcommunity.com/profiles/7656…/`, a bare SteamID64, or a
    /// bare custom-URL name.
    static func parseProfile(_ raw: String) -> ProfileReference? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let host = url.host, host.contains("steamcommunity.com") {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2 {
                if parts[0] == "profiles" { return .steamID(parts[1]) }
                if parts[0] == "id" { return .vanity(parts[1]) }
            }
            return nil
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if text.count == 17, text.allSatisfy(\.isNumber), text.hasPrefix("7656") {
            return .steamID(text)
        }
        return .vanity(text)
    }
}

enum SteamImportError: LocalizedError {
    case badProfile
    case profileNotFound
    case privateLibrary
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badProfile:
            return "That doesn't look like a Steam profile. Paste your profile URL, e.g. steamcommunity.com/id/yourname."
        case .profileNotFound:
            return "Couldn't find that Steam profile."
        case .privateLibrary:
            return "Steam didn't return any games. In Steam, set Privacy Settings → Game details to Public, then try again."
        case .http(let code):
            return "Steam returned an error (\(code)). Try again in a moment."
        }
    }
}

// MARK: - Live

/// Steam Web API client. Needs a Web API key (`STEAM_WEB_API_KEY` in
/// `Secrets.xcconfig`); `init?()` returns nil without one so the app can
/// fall back to the sample library.
final class LiveSteamLibraryService: SteamLibraryService, @unchecked Sendable {
    let isSample = false
    private let key: String
    private let session: URLSession

    init?(session: URLSession = .shared) {
        guard let key = Secrets.steamWebAPIKey else { return nil }
        self.key = key
        self.session = session
    }

    func ownedGames(profile: String) async throws -> [SteamOwnedGame] {
        guard let reference = SteamImport.parseProfile(profile) else { throw SteamImportError.badProfile }
        let steamID: String
        switch reference {
        case .steamID(let id): steamID = id
        case .vanity(let name): steamID = try await resolveVanity(name)
        }

        var components = URLComponents(string: "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/")!
        components.queryItems = [
            .init(name: "key", value: key),
            .init(name: "steamid", value: steamID),
            .init(name: "include_appinfo", value: "true"),
            .init(name: "include_played_free_games", value: "true"),
            .init(name: "format", value: "json"),
        ]
        let data = try await fetch(components.url!)

        struct Envelope: Decodable {
            struct Response: Decodable {
                struct Game: Decodable {
                    let appid: Int
                    let name: String?
                    let playtime_forever: Int?
                    let rtime_last_played: Int?
                }
                let games: [Game]?
            }
            let response: Response
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        // A private library comes back as an empty `response` object.
        guard let games = envelope.response.games, !games.isEmpty else {
            throw SteamImportError.privateLibrary
        }
        return games.compactMap { game in
            guard let name = game.name, !name.isEmpty else { return nil }
            let last = game.rtime_last_played.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
            return SteamOwnedGame(appID: game.appid, name: name, minutesPlayed: game.playtime_forever ?? 0, lastPlayed: last)
        }
    }

    private func resolveVanity(_ name: String) async throws -> String {
        var components = URLComponents(string: "https://api.steampowered.com/ISteamUser/ResolveVanityURL/v1/")!
        components.queryItems = [.init(name: "key", value: key), .init(name: "vanityurl", value: name)]
        let data = try await fetch(components.url!)
        struct Envelope: Decodable {
            struct Response: Decodable { let steamid: String?; let success: Int }
            let response: Response
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.response.success == 1, let id = envelope.response.steamid else {
            throw SteamImportError.profileNotFound
        }
        return id
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Steam answers 401/403 for private profiles on some endpoints.
            if http.statusCode == 401 || http.statusCode == 403 { throw SteamImportError.privateLibrary }
            throw SteamImportError.http(http.statusCode)
        }
        return data
    }
}

// MARK: - Sample

/// Canned library used when no Steam Web API key is configured. Real app
/// IDs, so cover art loads from Steam's CDN like the real thing.
struct SampleSteamLibraryService: SteamLibraryService {
    let isSample = true

    func ownedGames(profile: String) async throws -> [SteamOwnedGame] {
        guard SteamImport.parseProfile(profile) != nil else { throw SteamImportError.badProfile }
        try await Task.sleep(for: .milliseconds(600))
        let day: TimeInterval = 86_400
        let now = Date()
        let library: [(Int, String, Int, Double?)] = [
            (292030, "The Witcher® 3: Wild Hunt", 9_840, 400),
            (1245620, "ELDEN RING", 7_310, 60),
            (1145360, "Hades", 4_020, 200),
            (1086940, "Baldur's Gate 3", 11_200, 30),
            (367520, "Hollow Knight", 2_650, 500),
            (413150, "Stardew Valley", 6_100, 120),
            (620, "Portal 2", 1_020, 900),
            (504230, "Celeste", 870, 700),
            (646570, "Slay the Spire", 5_400, 45),
            (753640, "Outer Wilds", 1_380, 650),
            (1091500, "Cyberpunk 2077", 3_300, 90),
            (1174180, "Red Dead Redemption 2", 4_700, 330),
            (588650, "Dead Cells", 1_900, 380),
            (105600, "Terraria", 3_050, 800),
            (268910, "Cuphead", 640, 1_000),
            (1794680, "Vampire Survivors", 1_500, 240),
            (632470, "Disco Elysium - The Final Cut", 2_200, 420),
            (391540, "Undertale", 520, 1_100),
            (2379780, "Balatro", 3_900, 10),
            (730, "Counter-Strike 2", 12_600, 5),
            (220, "Half-Life 2", 780, 1_400),
            (1817070, "Marvel's Spider-Man Remastered", 0, nil),
            (1627720, "Lies of P", 0, nil),
            (814380, "Sekiro™: Shadows Die Twice", 35, 1_200),
        ]
        return library.map { appID, name, minutes, daysAgo in
            SteamOwnedGame(
                appID: appID,
                name: name,
                minutesPlayed: minutes,
                lastPlayed: daysAgo.map { now.addingTimeInterval(-$0 * day) }
            )
        }
    }
}

// MARK: - Environment

private struct SteamLibraryServiceKey: EnvironmentKey {
    static let defaultValue: any SteamLibraryService = SampleSteamLibraryService()
}

extension EnvironmentValues {
    var steamLibraryService: any SteamLibraryService {
        get { self[SteamLibraryServiceKey.self] }
        set { self[SteamLibraryServiceKey.self] = newValue }
    }
}
