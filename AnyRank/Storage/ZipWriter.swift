import Foundation

/// Just enough ZIP writing to package a list export. Entries are stored
/// uncompressed (the CSVs are small), with UTF-8 names. The output opens in
/// Files, Finder, and `ZipReader`.
enum ZipWriter {

    struct Entry {
        let path: String
        let data: Data
    }

    static func archive(_ entries: [Entry], modified: Date = .now) -> Data {
        let (time, date) = dosTimestamp(modified)
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(archive.count)

            // Local file header
            archive.append(u32: 0x0403_4B50)
            archive.append(u16: 20)          // version needed
            archive.append(u16: 0x0800)      // flags: UTF-8 names
            archive.append(u16: 0)           // method: stored
            archive.append(u16: time)
            archive.append(u16: date)
            archive.append(u32: crc)
            archive.append(u32: size)        // compressed
            archive.append(u32: size)        // uncompressed
            archive.append(u16: UInt16(name.count))
            archive.append(u16: 0)           // extra length
            archive.append(name)
            archive.append(entry.data)

            // Central directory record
            centralDirectory.append(u32: 0x0201_4B50)
            centralDirectory.append(u16: 20) // version made by
            centralDirectory.append(u16: 20) // version needed
            centralDirectory.append(u16: 0x0800)
            centralDirectory.append(u16: 0)
            centralDirectory.append(u16: time)
            centralDirectory.append(u16: date)
            centralDirectory.append(u32: crc)
            centralDirectory.append(u32: size)
            centralDirectory.append(u32: size)
            centralDirectory.append(u16: UInt16(name.count))
            centralDirectory.append(u16: 0)  // extra length
            centralDirectory.append(u16: 0)  // comment length
            centralDirectory.append(u16: 0)  // disk number
            centralDirectory.append(u16: 0)  // internal attributes
            centralDirectory.append(u32: 0)  // external attributes
            centralDirectory.append(u32: offset)
            centralDirectory.append(name)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        // End of central directory
        archive.append(u32: 0x0605_4B50)
        archive.append(u16: 0)
        archive.append(u16: 0)
        archive.append(u16: UInt16(entries.count))
        archive.append(u16: UInt16(entries.count))
        archive.append(u32: UInt32(centralDirectory.count))
        archive.append(u32: centralDirectoryOffset)
        archive.append(u16: 0)
        return archive
    }

    // MARK: Helpers

    /// MS-DOS time and date, the only timestamp a basic ZIP header carries.
    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = (c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2
        let day = max((c.year ?? 1980) - 1980, 0) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1)
        return (UInt16(time), UInt16(day))
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(u16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(u32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
