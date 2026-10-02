import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Loads cover art and posters for `ArtworkView` and keeps small thumbnails
/// on disk, so artwork shows up reliably and instantly after the first load.
///
/// Plain `AsyncImage` wasn't enough once whole libraries were imported:
/// - StoryGraph and Goodreads imports point at Open Library's cover-by-ISBN
///   endpoint, which allows 100 requests per 5 minutes per IP and then
///   answers 403. `AsyncImage` never retries, so covers went missing at
///   random while scrolling.
/// - An ISBN with no cover comes back as a 1×1 GIF with status 200, which
///   drew as an empty tile instead of the placeholder.
///
/// So ISBN cover URLs are resolved once to a cover ID through Open Library
/// search (the cover-ID endpoint isn't rate-limited, and search returns the
/// work's cover even when that edition has none). Downloads are capped per
/// host, images are downscaled and kept in Caches, and confirmed misses are
/// remembered so they show the placeholder without asking again. Transient
/// failures are left to the caller to retry.
actor ArtworkCache {

    static let shared = ArtworkCache()

    enum Outcome: Equatable {
        case image(UIImage)
        /// The source has no artwork for this item.
        case missing
        /// Network trouble, throttling, or a server error. Worth retrying.
        case failed
    }

    /// Longest edge of a stored thumbnail, in pixels. Item detail draws
    /// artwork up to 150pt wide, so this covers 3× screens.
    static let maxPixelSize = 480

    /// How long a confirmed "no artwork" answer is trusted before asking
    /// again, in case the source adds one.
    static let missingRetention: TimeInterval = 14 * 24 * 60 * 60

    // NSCache is thread-safe; kept outside the actor so views can read it
    // synchronously and draw cached artwork on their first frame.
    nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    private let session: URLSession
    private let directory: URL
    private var inFlight: [String: Task<Outcome, Never>] = [:]

    init(session: URLSession? = nil, directory: URL? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpMaximumConnectionsPerHost = 4
            config.urlCache = nil
            config.timeoutIntervalForRequest = 20
            config.httpAdditionalHeaders = ["User-Agent": "AnyRank (https://github.com/elsmrna/anyrank)"]
            self.session = URLSession(configuration: config)
        }
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Artwork already decoded in memory, for drawing without a flash of
    /// placeholder.
    nonisolated static func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    func load(_ url: URL) async -> Outcome {
        let key = url.absoluteString
        if let image = Self.memory.object(forKey: key as NSString) { return .image(image) }
        if let running = inFlight[key] { return await running.value }

        let task = Task { await fetch(url) }
        inFlight[key] = task
        let outcome = await task.value
        inFlight[key] = nil
        return outcome
    }

    // MARK: Fetching

    private func fetch(_ url: URL) async -> Outcome {
        let key = url.absoluteString
        let imageFile = file(for: url, extension: "jpg")
        let missingFile = file(for: url, extension: "missing")

        if let data = try? Data(contentsOf: imageFile), let image = UIImage(data: data) {
            Self.memory.setObject(image, forKey: key as NSString)
            return .image(image)
        }
        if let marked = modificationDate(of: missingFile),
           Date().timeIntervalSince(marked) < Self.missingRetention {
            return .missing
        }

        let data: Data
        if let placeID = PlacePhotos.placeID(from: url) {
            // No Places key: show the placeholder, but don't remember a
            // miss, since a key may be configured later.
            guard let loader = PlacePhotos.loader else { return .missing }
            switch await loader(placeID) {
            case .image(let photo): data = photo
            case .none:
                markMissing(missingFile)
                return .missing
            case .failed:
                return .failed
            }
        } else {
            let source: URL
            switch await resolve(url) {
            case .found(let resolved): source = resolved
            case .none:
                markMissing(missingFile)
                return .missing
            case .failed:
                return .failed
            }
            do {
                let (body, response) = try await session.data(from: source)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 404 {
                    markMissing(missingFile)
                    return .missing
                }
                guard status == 200 else { return .failed }
                data = body
            } catch {
                return .failed
            }
        }

        guard let thumbnail = Self.thumbnail(from: data) else {
            // Undecodable or a 1×1 stand-in for "no cover".
            markMissing(missingFile)
            return .missing
        }
        if let jpeg = thumbnail.jpegData(compressionQuality: 0.82) {
            try? jpeg.write(to: imageFile, options: .atomic)
        }
        Self.memory.setObject(thumbnail, forKey: key as NSString)
        return .image(thumbnail)
    }

    private enum Resolution {
        case found(URL)
        case none
        case failed
    }

    /// Where to actually download `url` from. Open Library cover-by-ISBN
    /// URLs (`/b/isbn/<isbn>-<size>.jpg`) become cover-ID URLs; anything
    /// else is used as-is.
    private func resolve(_ url: URL) async -> Resolution {
        guard let (isbn, size) = Self.openLibraryISBNCover(url) else { return .found(url) }

        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "isbn", value: isbn),
            URLQueryItem(name: "fields", value: "cover_i"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        do {
            let (data, response) = try await session.data(from: components.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .failed }
            let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let docs = decoded?["docs"] as? [[String: Any]] ?? []
            guard let coverID = docs.first?["cover_i"] as? Int, coverID > 0,
                  let resolved = URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-\(size).jpg")
            else { return .none }
            return .found(resolved)
        } catch {
            return .failed
        }
    }

    /// The ISBN and size letter from an Open Library cover-by-ISBN URL.
    static func openLibraryISBNCover(_ url: URL) -> (isbn: String, size: String)? {
        guard url.host == "covers.openlibrary.org" else { return nil }
        let parts = url.pathComponents // ["/", "b", "isbn", "9780804172448-M.jpg"]
        guard parts.count == 4, parts[1] == "b", parts[2] == "isbn" else { return nil }
        let stem = (parts[3] as NSString).deletingPathExtension
        let pieces = stem.split(separator: "-")
        guard let isbn = pieces.first, !isbn.isEmpty else { return nil }
        let size = pieces.count > 1 ? String(pieces[1]) : "M"
        return (String(isbn), size)
    }

    /// A downscaled copy of `data`, or nil when it isn't a real image
    /// (undecodable, or a tiny placeholder such as Open Library's 1×1 GIF).
    static func thumbnail(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 8, height > 8
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: Disk

    private func file(for url: URL, extension ext: String) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension(ext)
    }

    private func markMissing(_ file: URL) {
        try? Data().write(to: file, options: .atomic)
    }

    private func modificationDate(of file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }
}
