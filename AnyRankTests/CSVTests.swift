import XCTest
@testable import AnyRank

/// Round-trip tests for the CSV encoder/decoder. The decoder is the
/// fragile half — quoting rules, embedded newlines, escaped quotes — so
/// most of the coverage focuses there. Each test encodes a known input,
/// decodes the result, and asserts equality with the original.
final class CSVTests: XCTestCase {

    func test_emptyInput_decodesToEmpty() throws {
        let rows = try CSV.decode("")
        XCTAssertEqual(rows, [])
    }

    func test_simpleRows_roundTrip() throws {
        let original: [[String]] = [
            ["a", "b", "c"],
            ["1", "2", "3"]
        ]
        let encoded = CSV.encode(rows: original)
        let decoded = try CSV.decode(encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_fieldWithComma_isQuoted() throws {
        let original: [[String]] = [
            ["hello, world", "no comma"]
        ]
        let encoded = CSV.encode(rows: original)
        XCTAssertTrue(encoded.contains("\"hello, world\""))
        let decoded = try CSV.decode(encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_fieldWithEmbeddedQuote_escapesAndRoundTrips() throws {
        let original: [[String]] = [
            ["she said \"hi\"", "normal"]
        ]
        let encoded = CSV.encode(rows: original)
        // Embedded quote must be doubled.
        XCTAssertTrue(encoded.contains("\"\""))
        let decoded = try CSV.decode(encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_fieldWithNewline_isQuoted() throws {
        let original: [[String]] = [
            ["line1\nline2", "next"]
        ]
        let encoded = CSV.encode(rows: original)
        // Newline must live inside a quoted field; ensure exactly two newlines
        // (one inside the field, one terminating the row).
        XCTAssertEqual(encoded.filter { $0 == "\n" }.count, 2)
        let decoded = try CSV.decode(encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_emptyFields_areTolerated() throws {
        let original: [[String]] = [
            ["", "b", ""],
            ["a", "", ""]
        ]
        let encoded = CSV.encode(rows: original)
        let decoded = try CSV.decode(encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_carriageReturns_areIgnored() throws {
        // Spreadsheets sometimes emit CRLF; the decoder should treat \r as
        // a no-op and use \n as the row terminator.
        let withCRLF = "a,b\r\nc,d\r\n"
        let decoded = try CSV.decode(withCRLF)
        XCTAssertEqual(decoded, [["a", "b"], ["c", "d"]])
    }

    func test_unterminatedQuote_throws() {
        let bad = "\"unterminated,a"
        XCTAssertThrowsError(try CSV.decode(bad))
    }
}
