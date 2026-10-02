import Foundation

/// Export and restore of every list as a .zip of the on-disk format: the
/// `index.json` and per-list CSVs that `FileListStorage` keeps in
/// Application Support. Gives people who don't use Sheets sync a backup they
/// can keep in Files or move to another device.
///
/// Import queues (`imports.json`) are deliberately left out — they're a
/// local, in-progress convenience, not ranked data.
@MainActor
enum ListArchive {

    enum ArchiveError: LocalizedError {
        case notAnExport
        case empty

        var errorDescription: String? {
            switch self {
            case .notAnExport: return "This file isn't an AnyRank export. Choose a .zip made with Export lists."
            case .empty:       return "This export doesn't contain any lists."
            }
        }
    }

    /// Folder the files sit in inside the zip, so unzipping in Files gives
    /// one tidy folder.
    static let folderName = "AnyRank Lists"

    static func fileName(for date: Date) -> String {
        "\(folderName) \(date.formatted(.iso8601.year().month().day())).zip"
    }

    /// Writes `lists` to a zip in the temporary directory and returns its URL.
    static func export(_ lists: [RankList], date: Date = .now) async throws -> URL {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }

        let storage = FileListStorage(baseDirectory: staging)
        for list in lists {
            try await storage.save(list)
        }

        let entries = try fileManager.contentsOfDirectory(atPath: staging.path).sorted().map { name in
            ZipWriter.Entry(
                path: "\(folderName)/\(name)",
                data: try Data(contentsOf: staging.appendingPathComponent(name))
            )
        }

        let url = fileManager.temporaryDirectory.appendingPathComponent(fileName(for: date))
        try ZipWriter.archive(entries, modified: date).write(to: url, options: .atomic)
        return url
    }

    /// Reads the lists out of an export without touching the app's store.
    static func lists(fromArchive data: Data) async throws -> [RankList] {
        guard ZipReader.isZip(data) else { throw ArchiveError.notAnExport }

        // Keep only the files an export contains, by name, so a zip that was
        // re-compressed in Finder (extra folders, __MACOSX, .DS_Store) still
        // restores.
        let files = try ZipReader.entries(in: data).compactMap { entry -> (name: String, data: Data)? in
            guard !entry.path.contains("__MACOSX") else { return nil }
            let name = (entry.path as NSString).lastPathComponent
            guard name == "index.json" || (name.hasSuffix(".csv") && !name.hasPrefix(".")) else { return nil }
            return (name, entry.data)
        }
        guard files.contains(where: { $0.name == "index.json" }) else { throw ArchiveError.notAnExport }

        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        for file in files {
            try file.data.write(to: staging.appendingPathComponent(file.name))
        }

        let lists: [RankList]
        do {
            lists = try await FileListStorage(baseDirectory: staging).loadAll()
        } catch {
            throw ArchiveError.notAnExport
        }
        guard !lists.isEmpty else { throw ArchiveError.empty }
        return lists
    }
}
