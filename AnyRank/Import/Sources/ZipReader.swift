import Compression
import Foundation

/// Just enough ZIP reading to open a service's data export without making
/// the user unzip it first (Letterboxd sends a .zip). Supports stored and
/// deflated entries via the Compression framework; no ZIP64, no encryption.
enum ZipReader {

    struct Entry {
        let path: String
        let data: Data
    }

    enum ZipError: LocalizedError {
        case malformed
        case unsupported

        var errorDescription: String? {
            switch self {
            case .malformed:   return "This .zip file looks damaged. Try downloading the export again."
            case .unsupported: return "This .zip uses a format AnyRank can't open. Unzip it in Files and choose the .csv instead."
            }
        }
    }

    static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard let eocd = endOfCentralDirectory(bytes) else { throw ZipError.malformed }
        let count = Int(u16(bytes, eocd + 10))
        var cursor = Int(u32(bytes, eocd + 16))

        var entries: [Entry] = []
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, u32(bytes, cursor) == 0x0201_4B50 else { throw ZipError.malformed }
            let method = u16(bytes, cursor + 10)
            let compressedSize = Int(u32(bytes, cursor + 20))
            let uncompressedSize = Int(u32(bytes, cursor + 24))
            let nameLength = Int(u16(bytes, cursor + 28))
            let extraLength = Int(u16(bytes, cursor + 30))
            let commentLength = Int(u16(bytes, cursor + 32))
            let localOffset = Int(u32(bytes, cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else { throw ZipError.malformed }
            let path = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength

            if path.hasSuffix("/") { continue }

            // The local header's name/extra lengths can differ from the
            // central directory's, so read them from the local header.
            guard localOffset + 30 <= bytes.count, u32(bytes, localOffset) == 0x0403_4B50 else { throw ZipError.malformed }
            let start = localOffset + 30 + Int(u16(bytes, localOffset + 26)) + Int(u16(bytes, localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw ZipError.malformed }
            let payload = Array(bytes[start..<(start + compressedSize)])

            switch method {
            case 0:
                entries.append(Entry(path: path, data: Data(payload)))
            case 8:
                entries.append(Entry(path: path, data: try inflate(payload, expectedSize: uncompressedSize)))
            default:
                throw ZipError.unsupported
            }
        }
        return entries
    }

    // MARK: Helpers

    private static func endOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowest = max(0, bytes.count - 22 - 65_535)
        var i = bytes.count - 22
        while i >= lowest {
            if u32(bytes, i) == 0x0605_4B50 { return i }
            i -= 1
        }
        return nil
    }

    /// Raw DEFLATE (what ZIP uses) — Compression's ZLIB algorithm is raw
    /// deflate without the zlib header.
    private static func inflate(_ input: [UInt8], expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: expectedSize)
        let written = input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, expectedSize, src.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ZipError.malformed }
        return Data(output)
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        guard i + 1 < b.count else { return 0 }
        return UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i + 3 < b.count else { return 0 }
        return UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}
