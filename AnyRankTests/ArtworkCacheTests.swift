import UIKit
import XCTest
@testable import AnyRank

/// `ArtworkCache` against canned responses: Open Library ISBN covers get
/// resolved to cover-ID URLs, blank stand-in images count as "no artwork",
/// throttling is retryable, and results stick on disk.
final class ArtworkCacheTests: XCTestCase {

    private var directory: URL!
    private var session: URLSession!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArtworkStubProtocol.self]
        session = URLSession(configuration: config)
        ArtworkStubProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        ArtworkStubProtocol.reset()
    }

    func test_isbnCover_resolvesToCoverID_andIsCachedOnDisk() async throws {
        ArtworkStubProtocol.respond { url in
            if url.host == "openlibrary.org", url.path == "/search.json" {
                XCTAssertTrue(url.query?.contains("isbn=9780804172448") ?? false)
                return (200, Data(#"{"docs":[{"cover_i":7369961}]}"#.utf8))
            }
            if url.absoluteString == "https://covers.openlibrary.org/b/id/7369961-M.jpg" {
                return (200, Self.jpeg(width: 1200, height: 1800))
            }
            return (500, Data())
        }
        let isbnURL = URL(string: "https://covers.openlibrary.org/b/isbn/9780804172448-M.jpg")!

        let first = await ArtworkCache(session: session, directory: directory).load(isbnURL)
        guard case .image(let image) = first else { return XCTFail("expected an image, got \(first)") }
        XCTAssertLessThanOrEqual(max(image.size.width * image.scale, image.size.height * image.scale), 480)
        XCTAssertFalse(ArtworkStubProtocol.requested.contains { $0.path.hasPrefix("/b/isbn/") },
                       "the rate-limited ISBN endpoint should never be hit")

        // A fresh cache (new launch) reads the thumbnail from disk.
        ArtworkStubProtocol.requested.removeAll()
        ArtworkStubProtocol.respond { _ in (500, Data()) }
        let second = await ArtworkCache(session: session, directory: directory).load(isbnURL)
        guard case .image = second else { return XCTFail("expected the disk copy, got \(second)") }
        XCTAssertTrue(ArtworkStubProtocol.requested.isEmpty)
    }

    func test_isbnWithNoCover_isMissing_andNotAskedAgain() async {
        ArtworkStubProtocol.respond { _ in (200, Data(#"{"docs":[]}"#.utf8)) }
        let url = URL(string: "https://covers.openlibrary.org/b/isbn/9780000000001-M.jpg")!

        let first = await ArtworkCache(session: session, directory: directory).load(url)
        XCTAssertEqual(first, .missing)

        ArtworkStubProtocol.requested.removeAll()
        let second = await ArtworkCache(session: session, directory: directory).load(url)
        XCTAssertEqual(second, .missing)
        XCTAssertTrue(ArtworkStubProtocol.requested.isEmpty)
    }

    func test_onePixelPlaceholderImage_countsAsMissing() async {
        // Open Library's "no cover" stand-in: a 43-byte 1×1 GIF with status 200.
        let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!
        ArtworkStubProtocol.respond { _ in (200, gif) }
        let outcome = await ArtworkCache(session: session, directory: directory)
            .load(URL(string: "https://covers.openlibrary.org/b/id/1-M.jpg")!)
        XCTAssertEqual(outcome, .missing)
    }

    func test_throttling_isRetryable_andNotRememberedAsMissing() async {
        let url = URL(string: "https://image.tmdb.org/t/p/w342/poster.jpg")!
        ArtworkStubProtocol.respond { _ in (403, Data()) }
        let throttled = await ArtworkCache(session: session, directory: directory).load(url)
        XCTAssertEqual(throttled, .failed)

        ArtworkStubProtocol.respond { _ in (200, Self.jpeg(width: 342, height: 513)) }
        let retried = await ArtworkCache(session: session, directory: directory).load(url)
        guard case .image = retried else { return XCTFail("expected an image after the retry, got \(retried)") }
    }

    func test_openLibraryISBNCover_parsing() {
        let parsed = ArtworkCache.openLibraryISBNCover(URL(string: "https://covers.openlibrary.org/b/isbn/9780804172448-L.jpg")!)
        XCTAssertEqual(parsed?.isbn, "9780804172448")
        XCTAssertEqual(parsed?.size, "L")
        XCTAssertNil(ArtworkCache.openLibraryISBNCover(URL(string: "https://covers.openlibrary.org/b/id/7369961-M.jpg")!))
        XCTAssertNil(ArtworkCache.openLibraryISBNCover(URL(string: "https://image.tmdb.org/t/p/w342/x.jpg")!))
    }

    private static func jpeg(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .jpegData(withCompressionQuality: 0.8) { context in
                UIColor.brown.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
    }
}

final class ArtworkStubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URL) -> (Int, Data))?
    nonisolated(unsafe) static var requested: [URL] = []

    static func respond(_ handler: @escaping (URL) -> (Int, Data)) { self.handler = handler }
    static func reset() { handler = nil; requested = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requested.append(url)
        let (status, data) = Self.handler?(url) ?? (500, Data())
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
