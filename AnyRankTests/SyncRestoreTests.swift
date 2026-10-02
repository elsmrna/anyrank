import XCTest
@testable import AnyRank

/// Turning sync on after a reinstall, against an in-memory fake of the
/// Drive and Sheets endpoints `GoogleSheetsClient` calls. Covers the gap
/// where the spreadsheet ID lived only in `UserDefaults`, so a reinstall
/// created a second, empty spreadsheet instead of restoring from the first.
@MainActor
final class SyncRestoreTests: XCTestCase {

    private var google: FakeGoogle!
    private var client: GoogleSheetsClient!
    private let auth = AuthSession.previewSignedIn()
    private let token = "mock-access-token"

    override func setUp() async throws {
        google = FakeGoogle()
        FakeGoogleProtocol.backend = google
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeGoogleProtocol.self]
        client = GoogleSheetsClient(session: URLSession(configuration: config))
        forgetSavedSpreadsheet()
    }

    override func tearDown() async throws {
        forgetSavedSpreadsheet()
        FakeGoogleProtocol.backend = nil
    }

    // MARK: Scenarios

    func test_reinstall_restoresListsFromExistingSheet() async throws {
        let original = makeLists()
        try await syncFromDevice(lists: original)

        // Reinstall: empty store, no saved spreadsheet ID.
        forgetSavedSpreadsheet()
        let repo = Repository(storage: MemoryListStorage())
        let sync = makeCoordinator(repo)
        try await sync.connectSpreadsheet(accessToken: token)

        XCTAssertEqual(google.spreadsheetCount, 1, "should reuse the backup, not create another")
        XCTAssertEqual(sync.restoredListCount, 2)
        XCTAssertEqual(Set(repo.lists.map(\.id)), Set(original.map(\.id)))
        let restaurants = try XCTUnwrap(repo.lists.first { $0.name == "Restaurants" })
        XCTAssertEqual(restaurants.category, .restaurants)
        XCTAssertEqual(restaurants.items.map(\.name), ["Bestia", "Republique"])
        XCTAssertEqual(restaurants.comparisons.count, 1)
    }

    func test_localListsMadeBeforeEnabling_mergeWithBackup() async throws {
        let original = makeLists()
        try await syncFromDevice(lists: original)

        forgetSavedSpreadsheet()
        let fresh = RankList(name: "Bars", category: .bars)
        fresh.items = [RankItem(name: "The Varnish", bucket: .loved, score: 10)]
        let repo = Repository(storage: MemoryListStorage(initialLists: [fresh]))
        await repo.loadAll()
        let sync = makeCoordinator(repo)
        try await sync.connectSpreadsheet(accessToken: token)
        await sync.flushNow()

        XCTAssertEqual(sync.restoredListCount, 2)
        XCTAssertEqual(Set(repo.lists.map(\.name)), ["Restaurants", "Wines", "Bars"])
        // The Sheet's index now covers all three, so nothing was dropped.
        let index = try SheetsIndexCodec.decode(google.csv(of: SheetsIndexCodec.tabName, in: google.onlySpreadsheetID))
        XCTAssertEqual(Set(index.map(\.name)), ["Restaurants", "Wines", "Bars"])
    }

    func test_prefersBackupWithListsOverNewerEmptyDuplicate() async throws {
        let original = makeLists()
        try await syncFromDevice(lists: original)
        // What the old flow left behind after a reinstall: a newer,
        // untouched "AnyRank Data" with only the default tab.
        google.addEmptySpreadsheet(title: SyncCoordinator.spreadsheetTitle, modified: .now.addingTimeInterval(3600))

        forgetSavedSpreadsheet()
        let repo = Repository(storage: MemoryListStorage())
        let sync = makeCoordinator(repo)
        try await sync.connectSpreadsheet(accessToken: token)

        XCTAssertEqual(Set(repo.lists.map(\.id)), Set(original.map(\.id)))
        XCTAssertFalse(repo.lists.contains { $0.name == "Sheet1" })
    }

    func test_onlyAnEmptySheetInDrive_restoresNothing() async throws {
        google.addEmptySpreadsheet(title: SyncCoordinator.spreadsheetTitle, modified: .now)

        let repo = Repository(storage: MemoryListStorage())
        let sync = makeCoordinator(repo)
        try await sync.connectSpreadsheet(accessToken: token)

        XCTAssertEqual(google.spreadsheetCount, 1)
        XCTAssertNil(sync.restoredListCount)
        XCTAssertTrue(repo.lists.isEmpty, "the default blank tab isn't a list")
    }

    func test_firstEnable_withNoBackup_createsSpreadsheet() async throws {
        let list = RankList(name: "Movies", category: .movies)
        let repo = Repository(storage: MemoryListStorage(initialLists: [list]))
        await repo.loadAll()
        let sync = makeCoordinator(repo)
        try await sync.connectSpreadsheet(accessToken: token)
        await sync.flushNow()

        XCTAssertEqual(google.spreadsheetCount, 1)
        XCTAssertNil(sync.restoredListCount)
        let index = try SheetsIndexCodec.decode(google.csv(of: SheetsIndexCodec.tabName, in: google.onlySpreadsheetID))
        XCTAssertEqual(index.map(\.name), ["Movies"])
    }

    func test_findSpreadsheets_queriesByTitleAndParsesNewestFirst() async throws {
        google.addEmptySpreadsheet(title: "AnyRank Data", modified: Date(timeIntervalSince1970: 1_000))
        google.addEmptySpreadsheet(title: "AnyRank Data", modified: Date(timeIntervalSince1970: 2_000))
        google.addEmptySpreadsheet(title: "Something else", modified: Date(timeIntervalSince1970: 3_000))

        let found = try await client.findSpreadsheets(titled: "AnyRank Data", accessToken: token)

        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found.map(\.modifiedTime), [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 1_000)])
        let query = try XCTUnwrap(google.lastDriveQuery)
        XCTAssertTrue(query.contains("name = 'AnyRank Data'"))
        XCTAssertTrue(query.contains("mimeType = 'application/vnd.google-apps.spreadsheet'"))
        XCTAssertTrue(query.contains("trashed = false"))
    }

    // MARK: Helpers

    private func makeCoordinator(_ repo: Repository) -> SyncCoordinator {
        let sync = SyncCoordinator(repository: repo, auth: auth, sheetsClient: client)
        repo.syncObserver = sync
        return sync
    }

    /// Device A: turn sync on with `lists` and push everything.
    private func syncFromDevice(lists: [RankList]) async throws {
        let repo = Repository(storage: MemoryListStorage(initialLists: lists))
        await repo.loadAll()
        let sync = makeCoordinator(repo)
        try await sync.connectSpreadsheet(accessToken: token)
        await sync.flushNow()
        XCTAssertEqual(google.spreadsheetCount, 1)
    }

    private func makeLists() -> [RankList] {
        let restaurants = RankList(name: "Restaurants", category: .restaurants)
        let bestia = RankItem(name: "Bestia", bucket: .loved, score: 10)
        let republique = RankItem(name: "Republique", bucket: .loved, score: 8)
        restaurants.items = [bestia, republique]
        restaurants.comparisons = [ComparisonRecord(winnerItemID: bestia.id, loserItemID: republique.id, kind: .binarySearch)]

        let wines = RankList(name: "Wines", category: .custom, customFieldNames: ["Vintage"])
        let barolo = RankItem(name: "Barolo", bucket: .liked, score: 7)
        barolo.customFieldValues = ["Vintage": "2016"]
        wines.items = [barolo]
        return [restaurants, wines]
    }

    private func forgetSavedSpreadsheet() {
        UserDefaults.standard.removeObject(forKey: "syncSpreadsheetID.\(SignedInUser.previewSample.email)")
    }
}

// MARK: - Fake Google backend

/// Just enough of Drive v3 `files.list` and Sheets v4 (create, tab
/// properties, values get/put/clear, addSheet/deleteSheet) to run the sync
/// flows end to end.
final class FakeGoogle: @unchecked Sendable {

    private struct Spreadsheet {
        var title: String
        var modified: Date
        var tabs: [(id: Int, title: String, rows: [[String]])]
    }

    private let lock = NSLock()
    private var spreadsheets: [String: Spreadsheet] = [:]
    private var nextID = 1
    private(set) var lastDriveQuery: String?

    var spreadsheetCount: Int { lock.withLock { spreadsheets.count } }

    var onlySpreadsheetID: String {
        lock.withLock {
            precondition(spreadsheets.count == 1)
            return spreadsheets.keys.first!
        }
    }

    func csv(of tab: String, in spreadsheetID: String) -> String {
        lock.withLock {
            CSV.encode(rows: spreadsheets[spreadsheetID]?.tabs.first { $0.title == tab }?.rows ?? [])
        }
    }

    @discardableResult
    func addEmptySpreadsheet(title: String, modified: Date) -> String {
        lock.withLock { create(title: title, modified: modified) }
    }

    private func create(title: String, modified: Date) -> String {
        let id = "sheet-\(nextID)"
        nextID += 1
        spreadsheets[id] = Spreadsheet(title: title, modified: modified, tabs: [(0, "Sheet1", [])])
        return id
    }

    func handle(_ request: URLRequest, body: Data?) -> (Int, [String: Any]) {
        lock.withLock { () -> (Int, [String: Any]) in
            let url = request.url!
            let method = request.httpMethod ?? "GET"
            let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]

            if url.host == "www.googleapis.com", url.path == "/drive/v3/files" {
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "q" }?.value ?? ""
                lastDriveQuery = query
                let files = spreadsheets
                    .filter { query.contains("name = '\($0.value.title)'") }
                    .sorted { $0.value.modified > $1.value.modified }
                    .map { ["id": $0.key, "modifiedTime": $0.value.modified.formatted(.iso8601)] }
                return (200, ["files": files])
            }

            var parts = url.path.split(separator: "/").map(String.init) // ["v4", "spreadsheets", ...]
            guard parts.count >= 2, parts[0] == "v4", parts[1] == "spreadsheets" else { return (404, [:]) }
            parts.removeFirst(2)

            if parts.isEmpty, method == "POST" {
                let title = (json?["properties"] as? [String: Any])?["title"] as? String ?? ""
                return (200, ["spreadsheetId": create(title: title, modified: .now)])
            }

            var spreadsheetID = parts[0]
            if spreadsheetID.hasSuffix(":batchUpdate") {
                spreadsheetID = String(spreadsheetID.dropLast(":batchUpdate".count))
                guard var sheet = spreadsheets[spreadsheetID] else { return (404, [:]) }
                for change in json?["requests"] as? [[String: Any]] ?? [] {
                    if let add = change["addSheet"] as? [String: Any],
                       let title = (add["properties"] as? [String: Any])?["title"] as? String {
                        sheet.tabs.append(((sheet.tabs.map(\.id).max() ?? 0) + 1, title, []))
                    }
                    if let delete = change["deleteSheet"] as? [String: Any], let id = delete["sheetId"] as? Int {
                        sheet.tabs.removeAll { $0.id == id }
                    }
                }
                sheet.modified = .now
                spreadsheets[spreadsheetID] = sheet
                return (200, [:])
            }

            guard var sheet = spreadsheets[spreadsheetID] else { return (404, [:]) }

            if parts.count == 1 {
                let props = sheet.tabs.map { ["properties": ["title": $0.title, "sheetId": $0.id]] }
                return (200, ["sheets": props])
            }

            guard parts.count == 3, parts[1] == "values" else { return (404, [:]) }
            var tab = parts[2]
            let clearing = tab.hasSuffix(":clear")
            if clearing { tab = String(tab.dropLast(":clear".count)) }
            guard let index = sheet.tabs.firstIndex(where: { $0.title == tab }) else {
                return (400, ["error": "Unable to parse range: \(tab)"])
            }

            switch (method, clearing) {
            case ("POST", true):
                sheet.tabs[index].rows = []
            case ("PUT", false):
                sheet.tabs[index].rows = json?["values"] as? [[String]] ?? []
            case ("GET", false):
                let rows = sheet.tabs[index].rows
                return (200, rows.isEmpty ? ["range": tab] : ["range": tab, "values": rows])
            default:
                return (405, [:])
            }
            sheet.modified = .now
            spreadsheets[spreadsheetID] = sheet
            return (200, [:])
        }
    }
}

final class FakeGoogleProtocol: URLProtocol {
    nonisolated(unsafe) static var backend: FakeGoogle?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let backend = Self.backend else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (status, payload) = backend.handle(request, body: request.httpBody ?? readBodyStream())
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands protocols the body as a stream, not `httpBody`.
    private func readBodyStream() -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
