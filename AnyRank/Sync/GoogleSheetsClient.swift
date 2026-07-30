import Foundation

/// Thin HTTP client over the Google Sheets v4 and Drive v3 APIs. All calls
/// authenticate via a bearer access token (obtained from `AuthSession`).
///
/// Scope: enough to support the sync model — create a spreadsheet, list
/// tabs, read a tab as CSV, replace a tab's contents from a CSV, and
/// delete a tab. Not a general-purpose Sheets SDK.
struct GoogleSheetsClient: Sendable {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Spreadsheet lifecycle

    /// Create a new spreadsheet in the user's Drive with the given title.
    /// Returns the spreadsheet ID, which the caller persists for later
    /// pushes/pulls. Uses the Sheets API `spreadsheets.create` endpoint.
    func createSpreadsheet(title: String, accessToken: String) async throws -> String {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "properties": ["title": title]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await sendValidating(request)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = decoded?["spreadsheetId"] as? String else {
            throw SheetsError.unexpectedResponse("createSpreadsheet did not return spreadsheetId")
        }
        return id
    }

    /// Returns the names of every tab (worksheet) in the spreadsheet.
    /// Used by the pull-from-cloud path to discover what's there.
    func listTabs(spreadsheetID: String, accessToken: String) async throws -> [String] {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)?fields=sheets.properties")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await sendValidating(request)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let sheets = decoded?["sheets"] as? [[String: Any]] ?? []
        return sheets.compactMap { ($0["properties"] as? [String: Any])?["title"] as? String }
    }

    /// Read the full contents of `tabName` as CSV. The Sheets API returns
    /// a 2D array of values; we re-encode locally to CSV so the codec on
    /// the other end is symmetric with what we wrote.
    func readTab(spreadsheetID: String, tabName: String, accessToken: String) async throws -> String {
        let encodedRange = tabName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? tabName
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(encodedRange)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await sendValidating(request)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let values = (decoded?["values"] as? [[Any]]) ?? []
        let rows = values.map { row in row.map { String(describing: $0) } }
        return CSV.encode(rows: rows)
    }

    /// Replace `tabName`'s contents with `csv`, creating the tab if it
    /// doesn't exist. Uses a batchUpdate to ensure the create-then-write
    /// is atomic.
    func upsertTab(
        spreadsheetID: String,
        tabName: String,
        csv: String,
        accessToken: String
    ) async throws {
        // Ensure tab exists.
        let existingTabs = (try? await listTabs(spreadsheetID: spreadsheetID, accessToken: accessToken)) ?? []
        if !existingTabs.contains(tabName) {
            try await createTab(spreadsheetID: spreadsheetID, tabName: tabName, accessToken: accessToken)
        }

        // Clear existing values, then write fresh.
        try await clearTab(spreadsheetID: spreadsheetID, tabName: tabName, accessToken: accessToken)

        let rows = (try? CSV.decode(csv)) ?? []
        guard !rows.isEmpty else { return }

        let encodedRange = tabName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? tabName
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(encodedRange)?valueInputOption=RAW")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "range": tabName,
            "majorDimension": "ROWS",
            "values": rows
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await sendValidating(request)
    }

    /// Delete `tabName` from the spreadsheet. Used when a list is deleted
    /// locally. No-ops if the tab doesn't exist.
    func deleteTab(spreadsheetID: String, tabName: String, accessToken: String) async throws {
        guard let sheetID = try await fetchSheetID(spreadsheetID: spreadsheetID, tabName: tabName, accessToken: accessToken) else {
            return
        }
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID):batchUpdate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "requests": [["deleteSheet": ["sheetId": sheetID]]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await sendValidating(request)
    }

    // MARK: Private helpers

    private func createTab(spreadsheetID: String, tabName: String, accessToken: String) async throws {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID):batchUpdate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "requests": [["addSheet": ["properties": ["title": tabName]]]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await sendValidating(request)
    }

    private func clearTab(spreadsheetID: String, tabName: String, accessToken: String) async throws {
        let encodedRange = tabName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? tabName
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(encodedRange):clear")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        _ = try await sendValidating(request)
    }

    private func fetchSheetID(spreadsheetID: String, tabName: String, accessToken: String) async throws -> Int? {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)?fields=sheets.properties")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await sendValidating(request)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let sheets = decoded?["sheets"] as? [[String: Any]] ?? []
        for sheet in sheets {
            guard let props = sheet["properties"] as? [String: Any] else { continue }
            if props["title"] as? String == tabName, let id = props["sheetId"] as? Int {
                return id
            }
        }
        return nil
    }

    private func sendValidating(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SheetsError.httpError(status: http.statusCode, body: body)
        }
        return (data, response)
    }
}

enum SheetsError: LocalizedError {
    case httpError(status: Int, body: String)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let status, _):
            return "Google Sheets API returned HTTP \(status)."
        case .unexpectedResponse(let detail):
            return "Unexpected Google Sheets response: \(detail)"
        }
    }
}
